#!/usr/bin/env python
"""Standalone beat-integrity bench for scheduler.v.

The reassembly suite cannot see the scheduler datapath: the sim slot model
ignores request payload and pkt_logic forwards only the final response beat.
This drives the scheduler directly and checks every beat that comes out.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

MASK512 = (1 << 512) - 1

# Input : {dstPort[608:593], packet_size[592:561], workload[560:545],
#          meta[544:513], tlast[512], payload[511:0]}
# Output: {request_end[577], dstPort[576:561], workload[560:545],
#          meta[544:513], tcp_tlast[512], payload[511:0]}

REQ_FIRST_BIT = 480          # payload bit read by scheduler as rx_is_header
REQ_LAST_BIT = 481


def make_beat(payload, tlast, length, conn_id, workload, packet_size,
              dstport, first=False, last=False):
    d = payload & MASK512
    if first:
        d |= 1 << REQ_FIRST_BIT
    if last:
        d |= 1 << REQ_LAST_BIT
    meta = ((length & 0xFFFF) << 16) | (conn_id & 0xFFFF)
    d |= (tlast & 1) << 512
    d |= meta << 513
    d |= (workload & 0xFFFF) << 545
    d |= (packet_size & 0xFFFFFFFF) << 561
    d |= (dstport & 0xFFFF) << 593
    return d


def decode(d):
    return {
        "payload": d & MASK512,
        "tlast": (d >> 512) & 1,
        "conn_id": (d >> 513) & 0xFFFF,
        "length": (d >> 529) & 0xFFFF,
        "workload": (d >> 545) & 0xFFFF,
        "dstport": (d >> 561) & 0xFFFF,
        "req_end": (d >> 577) & 1,
    }


def tag(request_id, beat_index):
    """Payload that identifies its request and position, clear of the flag bits."""
    return (request_id << 32) | beat_index


class Bench:
    def __init__(self, dut):
        self.dut = dut
        self.sent = []
        self.received = []

    async def start(self):
        cocotb.start_soon(Clock(self.dut.clk, 4, units="ns").start())
        self.dut.rst.value = 1
        self.dut.rx_tvalid.value = 0
        self.dut.rx_tdata.value = 0
        self.dut.tx_tready.value = 1
        for _ in range(10):
            await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        for _ in range(5):
            await RisingEdge(self.dut.clk)
        cocotb.start_soon(self._sink())

    async def _sink(self):
        while True:
            await RisingEdge(self.dut.clk)
            await Timer(1, units="ns")
            if self.dut.tx_tvalid.value == 1 and self.dut.tx_tready.value == 1:
                self.received.append(decode(int(self.dut.tx_tdata.value)))

    async def send(self, beat):
        """Drive one beat, honouring rx_tready."""
        self.dut.rx_tdata.value = beat
        self.dut.rx_tvalid.value = 1
        while True:
            await RisingEdge(self.dut.clk)
            await Timer(1, units="ns")
            if self.dut.rx_tready.value == 1:
                break
        self.dut.rx_tvalid.value = 0

    async def send_request(self, request_id, conn_id, n_beats, workload=0x0000,
                           dstport=0x1234):
        """One request carried in a single TCP packet of n_beats lines."""
        nbytes = n_beats * 64
        for i in range(n_beats):
            beat = make_beat(
                payload=tag(request_id, i),
                tlast=1 if i == n_beats - 1 else 0,
                length=nbytes,
                conn_id=conn_id,
                workload=workload,
                packet_size=nbytes,
                dstport=dstport,
                first=(i == 0),
                last=(i == n_beats - 1),
            )
            self.sent.append((request_id, i))
            await self.send(beat)

    async def idle(self, cycles):
        self.dut.rx_tvalid.value = 0
        for _ in range(cycles):
            await RisingEdge(self.dut.clk)

    def report(self):
        # Tag lives in the low 64 bits; bits 480/481 carry the request flags.
        got = []
        for r in self.received:
            low = r["payload"] & ((1 << 64) - 1)
            got.append((low >> 32, low & 0xFFFFFFFF))
        return got


def check(bench, expected):
    got = bench.report()
    assert got == expected, (
        f"\n  beats sent     : {expected}"
        f"\n  beats received : {got}"
        f"\n  (tuples are (request_id, beat_index))"
    )


@cocotb.test()
async def test_single_request_three_beats(dut):
    """One 3-beat request, queue empty afterwards. Known-good case."""
    tb = Bench(dut)
    await tb.start()
    await tb.send_request(request_id=1, conn_id=0x0001, n_beats=3)
    await tb.idle(200)
    check(tb, [(1, 0), (1, 1), (1, 2)])
    assert tb.received[-1]["req_end"] == 1, "last beat must carry request_end"
    assert all(r["req_end"] == 0 for r in tb.received[:-1]), \
        "only the final beat may carry request_end"


@cocotb.test()
async def test_two_requests_gap(dut):
    """Two requests with the queue fully drained in between."""
    tb = Bench(dut)
    await tb.start()
    await tb.send_request(request_id=1, conn_id=0x0001, n_beats=3)
    await tb.idle(100)
    await tb.send_request(request_id=2, conn_id=0x0002, n_beats=3)
    await tb.idle(200)
    check(tb, [(1, 0), (1, 1), (1, 2), (2, 0), (2, 1), (2, 2)])


@cocotb.test()
async def test_two_requests_back_to_back(dut):
    """Two requests fed with no gap, so the second is already queued when the
    first finishes draining. This is the condition a per-slot FIFO creates."""
    tb = Bench(dut)
    await tb.start()
    await tb.send_request(request_id=1, conn_id=0x0001, n_beats=3)
    await tb.send_request(request_id=2, conn_id=0x0002, n_beats=3)
    await tb.idle(300)
    check(tb, [(1, 0), (1, 1), (1, 2), (2, 0), (2, 1), (2, 2)])


@cocotb.test()
async def test_four_requests_back_to_back(dut):
    """Sustained back-to-back load across both credit queues."""
    tb = Bench(dut)
    await tb.start()
    for rid in range(1, 5):
        await tb.send_request(request_id=rid, conn_id=rid, n_beats=3)
    await tb.idle(400)
    expected = [(rid, i) for rid in range(1, 5) for i in range(3)]
    check(tb, expected)


@cocotb.test()
async def test_back_to_back_with_stalled_sink(dut):
    """Sink stalls mid-stream, as a busy accelerator does today."""
    tb = Bench(dut)
    await tb.start()
    dut.tx_tready.value = 0
    await tb.send_request(request_id=1, conn_id=0x0001, n_beats=3)
    await tb.send_request(request_id=2, conn_id=0x0002, n_beats=3)
    await tb.idle(50)
    dut.tx_tready.value = 1
    await tb.idle(300)
    check(tb, [(1, 0), (1, 1), (1, 2), (2, 0), (2, 1), (2, 2)])


async def send_packet(tb, request_id, beat_index, conn_id, packet_size,
                      first, workload=0x0000, dstport=0x1234):
    """One single-beat TCP packet belonging to a multi-packet request."""
    beat = make_beat(
        payload=tag(request_id, beat_index),
        tlast=1,
        length=64,
        conn_id=conn_id,
        workload=workload,
        packet_size=packet_size,
        dstport=dstport,
        first=first,
        last=False,
    )
    await tb.send(beat)


@cocotb.test()
async def test_interleaved_requests_two_queues(dut):
    """Two concurrent multi-packet requests, TCP packets interleaved, so both
    credit queues are occupied and the arbiter must switch between them."""
    tb = Bench(dut)
    await tb.start()
    # A pkt0, B pkt0, A pkt1 (completes A), B pkt1 (completes B)
    await send_packet(tb, 1, 0, conn_id=0x00A0, packet_size=128, first=True)
    await send_packet(tb, 2, 0, conn_id=0x00B0, packet_size=128, first=True)
    await send_packet(tb, 1, 1, conn_id=0x00A0, packet_size=128, first=False)
    await send_packet(tb, 2, 1, conn_id=0x00B0, packet_size=128, first=False)
    await tb.idle(400)

    got = tb.report()
    a = [b for (r, b) in got if r == 1]
    b = [bb for (r, bb) in got if r == 2]
    assert a == [0, 1], f"request 1 beats lost/reordered: {a} (full: {got})"
    assert b == [0, 1], f"request 2 beats lost/reordered: {b} (full: {got})"
