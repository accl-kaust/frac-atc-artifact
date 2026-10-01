#!/usr/bin/env python
"""
The four accelerator slots and the credit links to them.

pkt_logic sends workload N to slot N, cell C0N, and talks to every cell
through a slot_boundary with credit flow control instead of a ready.  In this
bench C00 and C02 echo (pattern_slot) and C01 and C03 OR every line with all
ones (or_slot); cell_bbx_pattern_sim.sv counts the request beats each cell is
sent, which tells the two echoing cells, and the two OR-ing ones, apart.
"""

import random
from collections import defaultdict, deque

import cocotb
from cocotb.triggers import ClockCycles, RisingEdge, with_timeout

from test_reassembly import (
    BYTE_LANES, RECONF_APP, REQ_FLAG_FIRST, REQ_FLAG_SINGLE, TB, RequestHeader, TcpNotification, ToeRxBuffer,
    frame_to_int, int_to_le_bytes, pack_reconf_command, reconf_response_metadata, response_metadata,
)
from test_multiclient import ToeTx

OP_RECONF_ICAP = 3
SLOTS = 4
ECHO_SLOTS = (0, 2)


def cells(dut):
    logic = dut.pkt_logic_inst
    return [logic.c00_bbx_inst, logic.c01_bbx_inst, logic.c02_bbx_inst, logic.c03_bbx_inst]


def beats_in(dut):
    return [int(cell.in_beats.value) for cell in cells(dut)]


def slot_of(workload):
    return workload if workload < SLOTS else 0


def make_request(total_bytes, workload, conn_id, seq):
    """A request whose data lines carry (connection, request, line)."""
    flags = REQ_FLAG_SINGLE if total_bytes == BYTE_LANES else REQ_FLAG_FIRST
    header = RequestHeader(total_size=total_bytes, workload_id=workload, request_flags=flags).to_bytes()
    lines = []
    for idx in range(total_bytes // BYTE_LANES - 1):
        tag = (conn_id & 0xffff) | ((seq & 0xffff) << 16) | ((idx + 1) << 32)
        line = bytearray(int_to_le_bytes(tag, 8) * 8)
        line[60] &= 0xfe        # FIRST flag clear in data lines
        lines.append(bytes(line))
    return header + b"".join(lines)


def response_to(request, workload):
    """What the bench's cell for this workload sends back."""
    if slot_of(workload) in ECHO_SLOTS:
        return request
    return bytes([0xff]) * len(request)


async def send_request(tb, request, conn_id):
    """One request in one segment, read as soon as it is notified."""
    notification = TcpNotification(length=len(request), conn_id=conn_id)
    read_cmd = await tb.send_notification(notification)
    assert read_cmd == notification.pack()
    await tb.send_rx_payload(request)


@cocotb.test()
async def test_each_workload_reaches_its_slot(dut):
    """Workloads 0-3 go to C00-C03; any other but the controller's goes to C00."""
    tb = TB(dut)
    await tb.reset()

    for workload in (0, 1, 2, 3, 5):
        conn_id = 0x700 + workload
        request = make_request(2 * BYTE_LANES, workload, conn_id, 0)
        before = beats_in(dut)

        await send_request(tb, request, conn_id)
        await tb.send_tx_status_ok()
        metadata_frame, data_frame = await with_timeout(tb.recv_response(), 20, "us")

        assert bytes(data_frame.tdata) == response_to(request, workload), f"workload {workload}"
        assert frame_to_int(metadata_frame) == response_metadata(conn_id, len(request))
        sent = [after - b for after, b in zip(beats_in(dut), before)]
        expected = [0] * SLOTS
        expected[slot_of(workload)] = len(request) // BYTE_LANES
        assert sent == expected, f"workload {workload}: beats per cell {sent}"


async def watch_credits(dut, seen):
    """
    Records each time a credit link runs dry outside reset: the static end of
    a slot's request link (the cell's FIFO full) and the cell's end of its
    response link (static's FIFO full).
    """
    logic = dut.pkt_logic_inst
    boundaries = [logic.g_slot[slot].boundary_inst for slot in range(SLOTS)]
    cell_sources = []
    for slot, cell in enumerate(cells(dut)):
        rm = cell.echo_inst if slot in ECHO_SLOTS else cell.or_inst
        cell_sources.append(rm.resp_inst)
    while True:
        await RisingEdge(dut.clk)
        for slot in range(SLOTS):
            source = boundaries[slot].source_inst
            if not int(boundaries[slot].ends_rst.value) and int(source.credits.value) == 0:
                seen["requests", slot] += 1
            if not int(cell_sources[slot].rst.value) and int(cell_sources[slot].credits.value) == 0:
                seen["responses", slot] += 1


@cocotb.test()
async def test_four_slots_under_tx_backpressure(dut):
    """
    Eight connections, two to each slot, each with up to eight requests of
    64 B to 4 KB in flight, while the stack takes response data a quarter of
    the time.  That is more than pkt_sender can hold, so responses back up
    into every slot's response link and from the cell into its request link,
    and both run out of credits; every response must still come back whole,
    once, on its own connection, announced with its own length.
    """
    tb = TB(dut)
    await tb.reset()
    toe = ToeRxBuffer(tb)
    tx = ToeTx(tb)
    rng = random.Random(5)
    tb.tx_data_sink.set_pause_generator(iter(lambda: rng.random() < 0.75, None))
    seen = defaultdict(int)
    cocotb.start_soon(watch_credits(dut, seen))

    conns = {0x300 + c: c % SLOTS for c in range(8)}      # connection -> workload
    sizes = [BYTE_LANES, 16 * BYTE_LANES, 64 * BYTE_LANES, 64 * BYTE_LANES]
    requests = {c: [make_request(rng.choice(sizes), w, c, s) for s in range(12)] for c, w in conns.items()}
    unsent = {c: deque(requests[c]) for c in conns}
    in_flight = defaultdict(int)
    total = sum(len(r) for r in requests.values())
    before = beats_in(dut)

    credited = 0
    idle = 0
    while idle < 50000 and len(tx.responses) < total:
        progressed = False
        for c in conns:
            if unsent[c] and in_flight[c] < 8:
                await toe.receive_segment(unsent[c].popleft(), conn_id=c)
                in_flight[c] += 1
                progressed = True
        for meta, _ in tx.responses[credited:]:
            if meta is not None:
                in_flight[meta & 0xffff] = max(0, in_flight[meta & 0xffff] - 1)
            progressed = True
        credited = len(tx.responses)
        if progressed:
            idle = 0
        else:
            await ClockCycles(dut.clk, 16)
            idle += 16
    await ClockCycles(dut.clk, 500)

    got = defaultdict(list)
    for meta, data in tx.responses:
        assert meta is not None and (meta >> 16) == len(data), f"response announced as {meta}, {len(data)} bytes"
        got[meta & 0xffff].append(data)
    for c, w in conns.items():
        expected = [response_to(r, w) for r in requests[c]]
        assert len(got[c]) == len(expected), f"connection {c:#x}: {len(got[c])} of {len(expected)} responses"
        assert got[c] == expected, f"connection {c:#x}: a response is wrong"

    sent = [after - b for after, b in zip(beats_in(dut), before)]
    for slot in range(SLOTS):
        want = sum(len(r) // BYTE_LANES for c, w in conns.items() if slot_of(w) == slot for r in requests[c])
        assert sent[slot] == want, f"C0{slot} was sent {sent[slot]} beats, not {want}"
    dut._log.info(f"{total} requests over four slots; cycles a link was out of credits: {dict(seen)}")
    for slot in range(SLOTS):
        assert seen["responses", slot] > 0, f"C0{slot}'s response link never ran out of credits"
        assert seen["requests", slot] > 0, f"C0{slot}'s request link never ran out of credits"


@cocotb.test()
async def test_reconfiguring_a_slot_leaves_the_others_running(dut):
    """
    Slot 2 is reconfigured from a 32 KB stand-in bitstream.  While it is
    decoupled its cell is held in reset and sent nothing, C00 keeps
    answering, and a request for C02 waits in the scheduler.  Once the
    controller has reported, that request gets its answer and C02 goes on
    working with its credits whole.
    """
    tb = TB(dut)
    await tb.reset()
    logic = dut.pkt_logic_inst

    addr = 0x10000
    size = 32 * 1024
    tb.axi_ram.write(addr, bytes(size))
    command = (
        RequestHeader(total_size=2 * BYTE_LANES, workload_id=RECONF_APP).to_bytes()
        + pack_reconf_command(OP_RECONF_ICAP, addr, size, slot_id=2)
    )
    await send_request(tb, command, 0x3c0)

    for _ in range(4000):
        await RisingEdge(dut.clk)
        if int(logic.slot_decouple.value) & 0b0100:
            break
    else:
        raise AssertionError("slot 2 was never decoupled")
    await ClockCycles(dut.clk, 64)
    assert int(logic.slot_decouple.value) == 0b0100
    assert int(logic.cell_rst.value) == 0b0100, "only C02 should be held in reset"

    # C00 answers while C02 is decoupled
    request0 = make_request(4 * BYTE_LANES, 0, 0x3c1, 0)
    await send_request(tb, request0, 0x3c1)
    await tb.send_tx_status_ok()
    metadata_frame, data_frame = await with_timeout(tb.recv_response(), 20, "us")
    assert int(logic.slot_decouple.value) & 0b0100, "the reconfiguration ended before C00 answered"
    assert bytes(data_frame.tdata) == request0
    assert frame_to_int(metadata_frame) == response_metadata(0x3c1, len(request0))

    # a request for C02 waits for it
    before = beats_in(dut)[2]
    request2 = make_request(4 * BYTE_LANES, 2, 0x3c2, 0)
    await send_request(tb, request2, 0x3c2)
    await ClockCycles(dut.clk, 200)
    assert int(logic.slot_decouple.value) & 0b0100, "the reconfiguration ended too soon to test this"
    assert beats_in(dut)[2] == before, "C02 was sent a beat while decoupled"

    # the controller reports, then C02 answers
    await tb.send_tx_status_ok()
    await tb.send_tx_status_ok()
    metadata_frame, data_frame = await with_timeout(tb.recv_response(), 200, "us")
    assert frame_to_int(metadata_frame) == reconf_response_metadata(0x3c0)
    assert bytes(data_frame.tdata) == bytes(BYTE_LANES), "the reconfiguration did not report ERR_OK"
    metadata_frame, data_frame = await with_timeout(tb.recv_response(), 20, "us")
    assert bytes(data_frame.tdata) == request2
    assert frame_to_int(metadata_frame) == response_metadata(0x3c2, len(request2))
    assert int(logic.slot_decouple.value) == 0

    # and goes on working: 4 KB requests need all 64 credits, back to back
    for seq in range(1, 4):
        request = make_request(64 * BYTE_LANES, 2, 0x3c2, seq)
        await send_request(tb, request, 0x3c2)
        await tb.send_tx_status_ok()
        metadata_frame, data_frame = await with_timeout(tb.recv_response(), 50, "us")
        assert bytes(data_frame.tdata) == request
        assert frame_to_int(metadata_frame) == response_metadata(0x3c2, len(request))
    assert beats_in(dut)[2] == before + 4 + 3 * 64
