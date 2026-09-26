#!/usr/bin/env python
"""
Several TCP clients at once, as the board sees them under load.

The TOE queues every connection's segments in one RX FIFO (ToeRxBuffer), so
segments of different clients reach the dispatcher interleaved and back to
back.  Each client keeps a number of requests in flight, and every response
must come back whole, exactly once, on its own connection, announced with its
own length.
"""

import random
from collections import defaultdict, deque

import cocotb
from cocotb.triggers import ClockCycles
from cocotbext.axi import AxiStreamFrame

from test_reassembly import (
    BYTE_LANES, REQ_FLAG_FIRST, REQ_FLAG_SINGLE, TB, TOE_MSS, RequestHeader, ToeRxBuffer,
    frame_to_int, int_to_le_bytes,
)


def make_request(total_bytes, conn_id, seq):
    """
    An echo request whose data lines carry (connection, request, line), so a
    beat that lands in the wrong response, twice, or not at all shows.  Byte
    60 bit 0 -- the FIRST flag -- stays clear in data lines.
    """
    flags = REQ_FLAG_SINGLE if total_bytes == BYTE_LANES else REQ_FLAG_FIRST
    header = RequestHeader(total_size=total_bytes, workload_id=0x0000, request_flags=flags).to_bytes()
    lines = []
    for idx in range(total_bytes // BYTE_LANES - 1):
        tag = (conn_id & 0xffff) | ((seq & 0xffff) << 16) | ((idx + 1) << 32)
        line = bytearray(int_to_le_bytes(tag, 8) * 8)
        line[60] &= 0xfe
        lines.append(bytes(line))
    return header + b"".join(lines)


def cut(request, framing, mss=TOE_MSS):
    """
    The segments the host sends for one request: written in one piece and cut
    at the MSS ("one_write"), or sw/app's header segment followed by the data
    written in one piece ("header_alone").
    """
    if framing == "one_write":
        return [request[o:o + mss] for o in range(0, len(request), mss)]
    data = request[BYTE_LANES:]
    return [request[:BYTE_LANES]] + [data[o:o + mss] for o in range(0, len(data), mss)]


class ToeTx:
    """The TOE's TX side accepting every request: a response is its metadata and its data."""

    def __init__(self, tb, status_delay=8):
        self.tb = tb
        self.status_delay = status_delay
        self.metas = deque()
        self.responses = []     # (metadata, data)
        cocotb.start_soon(self._status())
        cocotb.start_soon(self._data())

    async def _status(self):
        while True:
            self.metas.append(frame_to_int(await self.tb.tx_metadata_sink.recv()))
            await ClockCycles(self.tb.dut.clk, self.status_delay)
            await self.tb.tx_status_source.send(AxiStreamFrame(int_to_le_bytes(0, 8)))

    async def _data(self):
        while True:
            data = bytes((await self.tb.tx_data_sink.recv()).tdata)
            self.responses.append((self.metas.popleft() if self.metas else None, data))


async def run_clients(dut, n_clients, sizes, framing, requests_per_client, window=1, seed=1, patience=20000):
    """
    n_clients connections sending requests of the given sizes, each keeping up
    to `window` of them in flight; their segments reach the TOE round robin.
    Returns how many responses were wrong, missing, or announced with a length
    other than their own.  Gives up after `patience` cycles without progress.
    """
    tb = TB(dut)
    await tb.reset()
    toe = ToeRxBuffer(tb)
    tx = ToeTx(tb)
    rng = random.Random(seed)

    conns = [0x100 + c for c in range(n_clients)]
    expected = {c: [make_request(rng.choice(sizes), c, s) for s in range(requests_per_client)] for c in conns}
    unsent = {c: deque(expected[c]) for c in conns}
    segments = {c: deque() for c in conns}
    in_flight = defaultdict(int)
    total = n_clients * requests_per_client
    credited = 0
    idle = 0
    while idle < patience and (credited < total or any(unsent[c] or segments[c] for c in conns)):
        progressed = False
        for c in conns:
            if not segments[c] and unsent[c] and in_flight[c] < window:
                segments[c].extend(cut(unsent[c].popleft(), framing))
                in_flight[c] += 1
            if segments[c]:
                await toe.receive_segment(segments[c].popleft(), conn_id=c)
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
    length_mismatch = 0
    for meta, data in tx.responses:
        if meta is None or (meta >> 16) != len(data):
            length_mismatch += 1
        if meta is not None:
            got[meta & 0xffff].append(data)
    wrong = sum(g != e for c in conns for g, e in zip(got[c], expected[c]))
    wrong += sum(max(0, len(got[c]) - len(expected[c])) for c in conns)
    missing = sum(max(0, len(expected[c]) - len(got[c])) for c in conns)
    dut._log.info(f"{n_clients} clients, {framing}, sizes {sizes}: {total} requests, "
                  f"{len(tx.responses)} responses, {wrong} wrong, {missing} missing, "
                  f"{length_mismatch} announced with another length")
    return wrong, missing, length_mismatch


def check(result):
    assert result == (0, 0, 0), "wrong={} missing={} length mismatch={}".format(*result)


@cocotb.test()
async def test_one_client_one_segment_requests(dut):
    """One client, requests of 128 to 4096 bytes, each written in one piece."""
    check(await run_clients(dut, 1, [128, 1024, 4096], "one_write", 12))


@cocotb.test()
async def test_four_clients_one_segment_requests(dut):
    """Four clients whose one-segment requests of 128 to 4096 bytes interleave."""
    check(await run_clients(dut, 4, [128, 1024, 4096], "one_write", 12))


@cocotb.test()
async def test_four_clients_single_and_multi_line_requests(dut):
    """
    One-line requests, which go straight to the single-packet FIFO, back to
    back with eight-line ones from other clients.
    """
    check(await run_clients(dut, 4, [64, 64, 512], "one_write", 16))


@cocotb.test()
async def test_sixteen_clients_two_requests_in_flight(dut):
    """Sixteen clients, two one-segment requests in flight each."""
    check(await run_clients(dut, 16, [64, 512, 1024, 4096], "one_write", 10, window=2))


@cocotb.test()
async def test_two_clients_header_segment_then_data(dut):
    """Two clients framing requests as sw/app does: a header segment, then the data."""
    check(await run_clients(dut, 2, [1024, 4096], "header_alone", 8))


@cocotb.test()
async def test_four_clients_header_segment_then_data(dut):
    """
    Four clients framing requests as sw/app does.  A header segment that
    arrives in the middle of another client's request starts a request of its
    own, carrying its own size.
    """
    check(await run_clients(dut, 4, [1024, 4096], "header_alone", 8))


@cocotb.test(expect_fail=True)
async def test_more_multi_segment_requests_than_queues_stall(dut):
    """
    KNOWN LIMIT.  A request spread over several segments holds a scheduler
    queue until its last segment is in.  Eight clients each opening an 8 or
    16 KB request at MSS 4096 need eight queues at once; the fifth request
    waits for one, and since the TOE hands every connection's segments over
    in order, the segments that would finish the first four are behind it.
    Nothing more comes out.
    """
    check(await run_clients(dut, 8, [8192, 16384], "one_write", 4))
