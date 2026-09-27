#!/usr/bin/env python
"""
Echo throughput through tcp_top_loopback against a cycle-level model of the
TOE, the way the board sees it under load.

RX: 16 connections send 4096-byte requests, one segment each, round robin.
The TOE queues segments in one FIFO (RX_DDR_BYPASS); each read_package
releases the segment at its head, whose beats follow RX_LATENCY cycles later,
back to back.

TX: tx metadata is always taken, as network_krnl's 256-deep FIFO takes it.
The status of a request reaches pkt_sender no sooner than STATUS_RTT cycles
after its metadata handshake, and no sooner than STATUS_INTERVAL after the
previous status, since tasi_metaLoader handles one request at a time.  Both
were measured in xsim on the real chain -- the TOE's HLS RTL, the network
kernel's two FIFOs and its register slice.  Every request is accepted, and tx
data is always ready.

A response is 64 beats.  Waiting out the round trip after every one, as
pkt_sender did before it issued the next request ahead, left 87 cycles per
response, 0.74 beats a cycle: 75 Gb/s at 200 MHz.  With the round trip under
the data only the scheduler's cycle to re-grant between requests is left.
"""

from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

STATUS_RTT = 18         # metadata handshake to status, cycles
STATUS_INTERVAL = 8     # between statuses
RX_LATENCY = 8          # read_package to the segment's first beat
CONNECTIONS = 16
REQUESTS = 160
REQUEST_BYTES = 4096
WARMUP = 40             # responses before the measured window
TAIL = 20               # and after it
MIN_BEATS_PER_CYCLE = 0.97

BYTE_LANES = 64


def header(total_bytes):
    """A request header line for workload 0, the echo in C00, whole in one segment."""
    flags = 0x3                 # FIRST | LAST
    config = 0xfffc | flags
    return (bytes([0xff] * 56) + total_bytes.to_bytes(4, "little")
            + config.to_bytes(2, "little") + (0).to_bytes(2, "little"))


def make_request(total_bytes, conn, seq):
    """Data lines carry (connection, request, line), so a misplaced beat shows."""
    lines = []
    for i in range(total_bytes // BYTE_LANES - 1):
        line = bytearray(bytes([conn & 0xff, seq & 0xff, (i + 1) & 0xff, 0x5a]) * 16)
        line[60] &= 0xfe        # FIRST flag clear in data lines
        lines.append(bytes(line))
    return header(total_bytes) + b"".join(lines)


def beats_of(segment):
    return [int.from_bytes(segment[o:o + BYTE_LANES], "little") for o in range(0, len(segment), BYTE_LANES)]


def v(signal):
    return int(signal.value)


async def reset(dut):
    dut.rst.value = 1
    for name, value in [
            ("m_axis_open_connection_tready", 1), ("s_axis_open_status_tvalid", 0),
            ("s_axis_open_status_tdata", 0), ("m_axis_close_connection_tready", 1),
            ("m_axis_listen_port_tready", 1), ("s_axis_listen_port_status_tvalid", 0),
            ("s_axis_listen_port_status_tdata", 0), ("s_axis_rx_metadata_tvalid", 0),
            ("s_axis_rx_metadata_tdata", 0), ("m_axi_rdata_parity", 0), ("m_axi_awready", 1),
            ("m_axi_wready", 1), ("m_axi_bvalid", 0), ("m_axi_arready", 1), ("m_axi_rvalid", 0),
            ("s_axis_notifications_tvalid", 0), ("s_axis_notifications_tdata", 0),
            ("m_axis_read_package_tready", 1), ("s_axis_rx_data_tvalid", 0), ("s_axis_rx_data_tdata", 0),
            ("s_axis_rx_data_tkeep", (1 << BYTE_LANES) - 1), ("s_axis_rx_data_tlast", 0),
            ("m_axis_tx_metadata_tready", 1), ("s_axis_tx_status_tvalid", 0),
            ("s_axis_tx_status_tdata", 0), ("m_axis_tx_data_tready", 1)]:
        getattr(dut, name).value = value
    await ClockCycles(dut.clk, 4)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 4)


@cocotb.test()
async def test_4k_echo_throughput(dut):
    """Back-to-back 4 KB echoes from 16 connections: every response intact, and
    at least MIN_BEATS_PER_CYCLE of tx data once the pipeline is full."""
    cocotb.start_soon(Clock(dut.clk, 5, units="ns").start())
    await reset(dut)

    requests = [(0x100 + i % CONNECTIONS, make_request(REQUEST_BYTES, 0x100 + i % CONNECTIONS, i // CONNECTIONS))
                for i in range(REQUESTS)]
    expected = {conn: deque() for conn in range(0x100, 0x100 + CONNECTIONS)}
    for conn, request in requests:
        expected[conn].append(request)

    to_notify = deque(requests)
    rx_buffer = deque()             # segments notified, not yet read
    rx_due = deque()                # (first edge the data may be valid, beats)
    rx_beats, rx_idx = None, 0
    status_due = deque()            # (first edge the status may be sampled, tdata)
    last_status = -10**9
    status_now = None
    metas = deque()
    response = []
    tlast_edges = []
    tx_fires = []
    wrong = 0

    edge = 0
    while len(tlast_edges) < REQUESTS and edge < 100000:
        await RisingEdge(dut.clk)
        edge += 1

        # sample what the edge just saw
        if v(dut.s_axis_notifications_tvalid) and v(dut.s_axis_notifications_tready):
            rx_buffer.append(to_notify.popleft()[1])
        if v(dut.m_axis_read_package_tvalid) and v(dut.m_axis_read_package_tready):
            rx_due.append((edge + RX_LATENCY, beats_of(rx_buffer.popleft())))
        if v(dut.s_axis_rx_data_tvalid) and v(dut.s_axis_rx_data_tready):
            rx_idx += 1
            if rx_idx == len(rx_beats):
                rx_beats = None
        if v(dut.m_axis_tx_metadata_tvalid) and v(dut.m_axis_tx_metadata_tready):
            meta = v(dut.m_axis_tx_metadata_tdata)
            metas.append(meta)
            last_status = max(edge + STATUS_RTT, last_status + STATUS_INTERVAL)
            # {error 0: accepted, usable window, length, session}
            status_due.append((last_status, (0x3ffff << 32) | meta))
        if v(dut.s_axis_tx_status_tvalid) and v(dut.s_axis_tx_status_tready):
            status_now = None
        fire = v(dut.m_axis_tx_data_tvalid) and v(dut.m_axis_tx_data_tready)
        tx_fires.append(fire)
        if fire:
            response.append(v(dut.m_axis_tx_data_tdata))
            if v(dut.m_axis_tx_data_tlast):
                tlast_edges.append(edge)
                meta = metas.popleft() if metas else None
                data = b"".join(b.to_bytes(BYTE_LANES, "little") for b in response)
                response = []
                conn = None if meta is None else meta & 0xffff
                if (conn not in expected or not expected[conn] or expected[conn].popleft() != data
                        or meta >> 16 != len(data)):
                    wrong += 1

        # drive the next edge
        if to_notify:
            dut.s_axis_notifications_tdata.value = (len(to_notify[0][1]) << 16) | to_notify[0][0]
            dut.s_axis_notifications_tvalid.value = 1
        else:
            dut.s_axis_notifications_tvalid.value = 0
        if rx_beats is None and rx_due and rx_due[0][0] <= edge + 1:
            rx_beats, rx_idx = rx_due.popleft()[1], 0
        if rx_beats is not None:
            dut.s_axis_rx_data_tdata.value = rx_beats[rx_idx]
            dut.s_axis_rx_data_tlast.value = int(rx_idx == len(rx_beats) - 1)
            dut.s_axis_rx_data_tvalid.value = 1
        else:
            dut.s_axis_rx_data_tvalid.value = 0
            dut.s_axis_rx_data_tlast.value = 0
        if status_now is None and status_due and status_due[0][0] <= edge + 1:
            status_now = status_due.popleft()[1]
        dut.s_axis_tx_status_tvalid.value = int(status_now is not None)
        if status_now is not None:
            dut.s_axis_tx_status_tdata.value = status_now

    assert len(tlast_edges) == REQUESTS, f"{len(tlast_edges)} of {REQUESTS} responses in {edge} cycles"
    assert wrong == 0, f"{wrong} responses wrong, misplaced or announced with another length"

    first, last = tlast_edges[WARMUP], tlast_edges[REQUESTS - TAIL]
    beats = sum(tx_fires[first:last])
    rate = beats / (last - first)
    per_response = (last - first) / (REQUESTS - TAIL - WARMUP)
    dut._log.info(f"{beats} beats in {last - first} cycles: {rate:.4f} a cycle, "
                  f"{per_response:.2f} cycles per {REQUEST_BYTES}-byte response, "
                  f"{rate * 512 * 200e6 / 1e9:.1f} Gb/s at 200 MHz")
    assert rate >= MIN_BEATS_PER_CYCLE, f"{rate:.4f} beats a cycle, want at least {MIN_BEATS_PER_CYCLE}"

    await ClockCycles(dut.clk, 10)
