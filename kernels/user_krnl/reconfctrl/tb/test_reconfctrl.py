#!/usr/bin/env python

import itertools
import random

import cocotb
from cocotb.clock import Clock
from cocotb.result import SimTimeoutError
from cocotb.triggers import ReadOnly, RisingEdge, with_timeout
from cocotb.utils import get_sim_time

from cocotbext.axi import AxiBus, AxiRam, AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource


OP_WRITE_HBM = 1
OP_READ_HBM = 2
OP_RECONF_ICAP = 3
OP_QUERY_ICAP_STATUS = 4
ERR_OK = 0
ERR_ALIGN = 2
ERR_SLOT = 8
ERR_ICAP = 9
ERR_PR_TIMEOUT = 10
BYTE_LANES = 64


def pack_command(opcode, addr, size, slot_id=0):
    payload = bytearray(BYTE_LANES)
    payload[0] = opcode
    payload[1] = slot_id
    payload[8:16] = int(addr).to_bytes(8, "little")
    payload[16:24] = int(size).to_bytes(8, "little")
    return bytes(payload)


def assert_keep_all(frame, byte_count):
    assert frame.tkeep is None or frame.tkeep == [1] * byte_count


async def wait_cycles(dut, count):
    for _ in range(count):
        await RisingEdge(dut.clk)


async def capture_read_ar_events(dut, count):
    events = []
    while len(events) < count:
        await RisingEdge(dut.clk)
        if int(dut.m_axi_arvalid.value):
            events.append((int(dut.m_axi_arlen.value), get_sim_time()))
            while int(dut.m_axi_arvalid.value):
                await RisingEdge(dut.clk)
    return events


class TB:
    def __init__(self, dut):
        self.dut = dut

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        self.source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
        self.response_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)
        self.icap_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis_icap"), dut.clk, dut.rst)
        self.axi_ram = AxiRam(AxiBus.from_prefix(dut, "m_axi"), dut.clk, dut.rst, size=2**20)

        dut.m_axi_rdata_parity.setimmediatevalue(0)
        dut.icap_pr_done.setimmediatevalue(0)
        dut.icap_pr_err.setimmediatevalue(0)
        dut.icap_avail.setimmediatevalue(1)

    async def reset(self):
        self.dut.rst.setimmediatevalue(0)
        await wait_cycles(self.dut, 2)
        self.dut.rst.value = 1
        await wait_cycles(self.dut, 2)
        self.dut.rst.value = 0
        await wait_cycles(self.dut, 4)

    async def send_frame(self, payload):
        await self.source.send(AxiStreamFrame(payload))

    async def recv_response(self):
        return await self.response_sink.recv()

    async def recv_icap_frame(self):
        return await self.icap_sink.recv()

    async def pulse_pr_done(self):
        self.dut.icap_pr_done.value = 1
        await RisingEdge(self.dut.clk)
        self.dut.icap_pr_done.value = 0

    async def pulse_pr_err(self):
        self.dut.icap_pr_err.value = 1
        await RisingEdge(self.dut.clk)
        self.dut.icap_pr_err.value = 0


@cocotb.test()
async def test_write_hbm_status_and_strobes(dut):
    tb = TB(dut)
    await tb.reset()

    addr = 0x1000
    payload = bytes(range(96))
    tb.axi_ram.write(addr, bytes([0xAA] * 128))

    await tb.send_frame(pack_command(OP_WRITE_HBM, addr, len(payload)))
    await tb.send_frame(payload)

    response = await tb.recv_response()

    assert bytes(response.tdata)[0] == ERR_OK
    assert bytes(response.tdata)[1:] == bytes(BYTE_LANES - 1)
    assert_keep_all(response, BYTE_LANES)
    assert tb.axi_ram.read(addr, len(payload)) == payload
    assert tb.axi_ram.read(addr + len(payload), 32) == bytes([0xAA] * 32)


@cocotb.test()
async def test_read_hbm_64B_response(dut):
    tb = TB(dut)
    await tb.reset()

    addr = 0x2000
    payload = bytes((0x80 + idx) & 0xFF for idx in range(BYTE_LANES))
    tb.axi_ram.write(addr, payload)

    await tb.send_frame(pack_command(OP_READ_HBM, addr, len(payload)))
    response = await tb.recv_response()

    assert bytes(response.tdata) == payload
    assert_keep_all(response, BYTE_LANES)


@cocotb.test()
async def test_reconf_icap_dma_streams_all_words(dut):
    tb = TB(dut)
    await tb.reset()

    addr = 0x3000
    words = [0xC0000000 + idx for idx in range(10)]
    payload = b"".join(word.to_bytes(4, "little") for word in words)
    tb.axi_ram.write(addr, payload)

    await tb.send_frame(pack_command(OP_RECONF_ICAP, addr, len(payload)))
    icap_frame = await tb.recv_icap_frame()
    await tb.pulse_pr_done()
    response = await tb.recv_response()

    assert bytes(icap_frame.tdata) == payload
    assert bytes(response.tdata)[0] == ERR_OK
    assert bytes(response.tdata)[1:] == bytes(BYTE_LANES - 1)
    assert_keep_all(response, BYTE_LANES)


@cocotb.test()
async def test_reconf_icap_single_beat_reads(dut):
    """The reconf DMA fetches one 32-byte beat per AR, ARLEN always 0."""
    tb = TB(dut)
    await tb.reset()

    addr = 0x9000
    payload = bytes(idx & 0xFF for idx in range(17 * 32))
    tb.axi_ram.write(addr, payload)

    ar_task = cocotb.start_soon(capture_read_ar_events(dut, 17))
    await tb.send_frame(pack_command(OP_RECONF_ICAP, addr, len(payload)))
    icap_frame = await tb.recv_icap_frame()
    ar_events = await with_timeout(ar_task, 10, "us")
    await tb.pulse_pr_done()
    response = await tb.recv_response()

    assert [arlen for arlen, _ in ar_events] == [0] * 17
    assert bytes(icap_frame.tdata) == payload
    assert bytes(response.tdata)[0] == ERR_OK


@cocotb.test()
async def test_invalid_unaligned_address_returns_error(dut):
    tb = TB(dut)
    await tb.reset()

    await tb.send_frame(pack_command(OP_READ_HBM, 0x1234, 64))
    response = await tb.recv_response()

    assert bytes(response.tdata)[0] == ERR_ALIGN
    assert_keep_all(response, BYTE_LANES)


@cocotb.test()
async def test_reconf_icap_asserts_selected_slot_decouple(dut):
    tb = TB(dut)
    await tb.reset()

    addr = 0x4000
    payload = bytes(range(32))
    tb.axi_ram.write(addr, payload)

    await tb.send_frame(pack_command(OP_RECONF_ICAP, addr, len(payload), slot_id=1))
    await wait_cycles(dut, 8)

    assert int(dut.slot_decouple.value) == 0b10

    icap_frame = await tb.recv_icap_frame()
    assert bytes(icap_frame.tdata) == payload
    assert int(dut.slot_decouple.value) == 0b10

    await tb.pulse_pr_done()
    response = await tb.recv_response()

    assert bytes(response.tdata)[0] == ERR_OK
    assert int(dut.slot_decouple.value) == 0


@cocotb.test()
async def test_reconf_icap_waits_for_prdone(dut):
    tb = TB(dut)
    await tb.reset()

    addr = 0x5000
    payload = bytes(range(16))
    tb.axi_ram.write(addr, payload)

    await tb.send_frame(pack_command(OP_RECONF_ICAP, addr, len(payload), slot_id=0))
    icap_frame = await tb.recv_icap_frame()
    assert bytes(icap_frame.tdata) == payload

    response_task = cocotb.start_soon(tb.recv_response())
    await wait_cycles(dut, 16)
    assert not response_task.done()
    assert int(dut.slot_decouple.value) == 0b01

    await tb.pulse_pr_done()
    response = await response_task

    assert bytes(response.tdata)[0] == ERR_OK
    assert int(dut.slot_decouple.value) == 0


@cocotb.test()
async def test_reconf_icap_prerror_returns_error(dut):
    tb = TB(dut)
    await tb.reset()

    addr = 0x6000
    payload = bytes(range(16))
    tb.axi_ram.write(addr, payload)

    await tb.send_frame(pack_command(OP_RECONF_ICAP, addr, len(payload), slot_id=1))
    await tb.recv_icap_frame()
    await tb.pulse_pr_err()
    response = await tb.recv_response()

    assert bytes(response.tdata)[0] == ERR_ICAP
    assert int(dut.slot_decouple.value) == 0
    assert int(dut.last_reconf_cycles.value) > 0


@cocotb.test()
async def test_reconf_invalid_slot_returns_error(dut):
    tb = TB(dut)
    await tb.reset()

    await tb.send_frame(pack_command(OP_RECONF_ICAP, 0x7000, 4, slot_id=2))
    response = await tb.recv_response()

    assert bytes(response.tdata)[0] == ERR_SLOT
    assert int(dut.slot_decouple.value) == 0


@cocotb.test()
async def test_query_icap_status_idle(dut):
    tb = TB(dut)
    await tb.reset()

    await tb.send_frame(pack_command(OP_QUERY_ICAP_STATUS, 0, 0))
    response = await tb.recv_response()
    data = bytes(response.tdata)

    assert data[0] == ERR_OK
    assert data[1] == 0
    assert data[2] == 0
    assert data[3] == ERR_OK
    assert data[4] == 1
    assert int.from_bytes(data[8:16], "little") == 0
    assert int.from_bytes(data[16:24], "little") == 0


@cocotb.test()
async def test_query_icap_status_after_reconf(dut):
    tb = TB(dut)
    await tb.reset()

    addr = 0x8000
    payload = bytes(range(16))
    tb.axi_ram.write(addr, payload)

    await tb.send_frame(pack_command(OP_RECONF_ICAP, addr, len(payload), slot_id=1))
    await tb.recv_icap_frame()
    await tb.pulse_pr_done()
    response = await tb.recv_response()
    assert bytes(response.tdata)[0] == ERR_OK

    await tb.send_frame(pack_command(OP_QUERY_ICAP_STATUS, 0, 0))
    response = await tb.recv_response()
    data = bytes(response.tdata)

    assert data[0] == ERR_OK
    assert data[1] == 0
    assert data[2] == 1
    assert data[3] == ERR_OK
    assert int.from_bytes(data[8:16], "little") > 0
    assert int.from_bytes(data[16:24], "little") == 0


# ---------------------------------------------------------------------------
# HBM -> ICAP DMA stress tests
#
# The tests above drive the DUT with a zero-latency AXI RAM and an
# always-ready ICAP sink, which is nothing like HBM through the switch. The
# tests below re-run the RECONF_ICAP DMA with read latency, rvalid gaps,
# arready stalls, ICAP backpressure, and word counts that hit every beat
# boundary case, checking the ICAP word stream bit-for-bit each time.
# ---------------------------------------------------------------------------

CANARY = b"\xde\xad\xbe\xef"


def words_payload(nwords, seed):
    rng = random.Random(seed)
    return b"".join(rng.getrandbits(32).to_bytes(4, "little") for _ in range(nwords))


def burst_pause(on, off):
    return itertools.cycle([1] * on + [0] * off)


def duty_pause(seed, duty):
    rng = random.Random(seed)
    while True:
        yield 1 if rng.random() < duty else 0


def initial_delay_pause(delay, tail=None):
    return itertools.chain(itertools.repeat(1, delay), tail if tail is not None else itertools.repeat(0))


def _set_pause(channel, gen):
    # clear_pause_generator() kills the pause coroutine but leaves the last
    # pause value latched, so always drop the flag when swapping generators
    channel.clear_pause_generator()
    channel.pause = False
    if gen is not None:
        channel.set_pause_generator(gen)


def set_hbm_pauses(tb, ar=None, r=None):
    _set_pause(tb.axi_ram.read_if.ar_channel, ar)
    _set_pause(tb.axi_ram.read_if.r_channel, r)


def set_icap_pause(tb, gen=None):
    _set_pause(tb.icap_sink, gen)


def dut_debug_state(dut):
    fields = {}
    for name in (
        "state",
        "icap_words_remaining_reg",
        "icap_word_index_reg",
        "reconf_beat_words_reg",
        "wait_done_cycles_reg",
        "m_axi_arvalid",
        "m_axi_rvalid",
        "m_axi_rready",
        "m_axis_icap_tvalid",
        "m_axis_icap_tready",
    ):
        try:
            fields[name] = int(getattr(dut, name).value)
        except Exception:
            fields[name] = None
    return " ".join(f"{key}={value}" for key, value in fields.items())


def assert_icap_payload(context, got, expected):
    if got == expected:
        return
    lines = [
        f"{context}: ICAP stream mismatch:"
        f" received {len(got)} bytes ({len(got) // 4} words),"
        f" expected {len(expected)} bytes ({len(expected) // 4} words)"
    ]
    for index in range(min(len(got), len(expected)) // 4):
        exp_word = int.from_bytes(expected[index * 4:index * 4 + 4], "little")
        got_word = int.from_bytes(got[index * 4:index * 4 + 4], "little")
        if exp_word != got_word:
            lines.append(f"first mismatch at word {index}: expected 0x{exp_word:08x} got 0x{got_word:08x}")
            if got_word.to_bytes(4, "little") in (CANARY, CANARY[::-1]):
                lines.append("mismatching word is the over-fetch canary: DUT forwarded data past the bitstream end")
            break
    else:
        if len(got) != len(expected):
            lines.append(f"streams agree up to word {min(len(got), len(expected)) // 4}, lengths differ")
    raise AssertionError("\n".join(lines))


async def monitor_icap_stream(dut, stats):
    prev_icap = None
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()

        now = get_sim_time("ns")
        cur_icap = (
            int(dut.m_axis_icap_tvalid.value),
            int(dut.m_axis_icap_tready.value),
            int(dut.m_axis_icap_tdata.value),
            int(dut.m_axis_icap_tlast.value),
        )
        if prev_icap is not None and prev_icap[0] and not prev_icap[1]:
            if not cur_icap[0]:
                stats["violations"].append(f"{now}ns: m_axis_icap_tvalid dropped while stalled (protocol violation)")
            elif cur_icap[2] != prev_icap[2] or cur_icap[3] != prev_icap[3]:
                stats["violations"].append(
                    f"{now}ns: m_axis_icap payload changed while stalled:"
                    f" tdata 0x{prev_icap[2]:08x}->0x{cur_icap[2]:08x} tlast {prev_icap[3]}->{cur_icap[3]}"
                )
        prev_icap = cur_icap


async def run_reconf_dma(tb, dut, context, addr, nwords, slot_id=0, seed=1, timeout_us=500):
    payload = words_payload(nwords, seed)
    tb.axi_ram.write(addr, payload)
    tb.axi_ram.write(addr + len(payload), CANARY * 32)

    await tb.send_frame(pack_command(OP_RECONF_ICAP, addr, len(payload), slot_id=slot_id))

    try:
        icap_frame = await with_timeout(tb.recv_icap_frame(), timeout_us, "us")
    except SimTimeoutError:
        raise AssertionError(
            f"{context}: timeout waiting for ICAP frame ({nwords} words); DUT state: {dut_debug_state(dut)}"
        )

    assert int(dut.slot_decouple.value) >> slot_id & 1, f"{context}: slot_decouple[{slot_id}] dropped before pr_done"
    assert_icap_payload(context, bytes(icap_frame.tdata), payload)

    await tb.pulse_pr_done()

    try:
        response = await with_timeout(tb.recv_response(), timeout_us, "us")
    except SimTimeoutError:
        raise AssertionError(
            f"{context}: timeout waiting for status response; DUT state: {dut_debug_state(dut)}"
        )

    status = bytes(response.tdata)[0]
    assert status == ERR_OK, f"{context}: status {status} != ERR_OK"
    assert int(dut.slot_decouple.value) == 0, f"{context}: slot_decouple not released after reconf"


@cocotb.test()
async def test_reconf_dma_word_boundary_sizes(dut):
    """Back-to-back reconfigs at every burst/FIFO/tail boundary, ideal RAM."""
    tb = TB(dut)
    await tb.reset()

    sizes = [1, 2, 7, 8, 9, 15, 16, 17, 120, 121, 123, 127, 128, 129, 136, 255, 256, 300]
    for index, nwords in enumerate(sizes):
        await run_reconf_dma(
            tb, dut, f"ideal size={nwords}w", 0x10000 + index * 0x1000, nwords,
            slot_id=index % 2, seed=100 + index,
        )


@cocotb.test()
async def test_reconf_dma_hbm_latency_and_gaps(dut):
    """RECONF_ICAP with HBM-like read latency, rvalid gaps and arready stalls."""
    tb = TB(dut)
    await tb.reset()

    stats = {"violations": []}
    cocotb.start_soon(monitor_icap_stream(dut, stats))

    configs = [
        ("r_gaps_75pct", lambda: (None, burst_pause(3, 1))),
        ("r_gaps_random", lambda: (duty_pause(7, 0.3), duty_pause(8, 0.5))),
        ("ar_stalled", lambda: (burst_pause(7, 1), None)),
        ("r_initial_latency_150", lambda: (None, initial_delay_pause(150, duty_pause(9, 0.25)))),
    ]

    for name, factory in configs:
        for offset, nwords in enumerate((121, 129, 1000)):
            ar_gen, r_gen = factory()
            set_hbm_pauses(tb, ar=ar_gen, r=r_gen)
            await run_reconf_dma(
                tb, dut, f"{name} size={nwords}w", 0x40000 + offset * 0x2000, nwords,
                slot_id=offset % 2, seed=sum(name.encode()) + nwords,
            )
    set_hbm_pauses(tb)

    assert not stats["violations"], "\n".join(stats["violations"])


@cocotb.test()
async def test_reconf_dma_icap_backpressure(dut):
    """A slow ICAP sink stalls the serializer without corrupting the stream."""
    tb = TB(dut)
    await tb.reset()

    stats = {"violations": []}
    cocotb.start_soon(monitor_icap_stream(dut, stats))

    set_icap_pause(tb, burst_pause(7, 1))
    await run_reconf_dma(tb, dut, "icap_bp size=136w", 0x60000, 136, slot_id=0, seed=61)
    await run_reconf_dma(tb, dut, "icap_bp size=512w", 0x62000, 512, slot_id=1, seed=62)
    set_icap_pause(tb)

    assert not stats["violations"], "\n".join(stats["violations"])


@cocotb.test()
async def test_reconf_dma_after_write_hbm(dut):
    """Full software flow: upload the bitstream through WRITE_HBM, then reconfigure from it."""
    tb = TB(dut)
    await tb.reset()

    addr = 0x70000
    payload = words_payload(160, seed=71)
    tb.axi_ram.write(addr + len(payload), CANARY * 32)

    for offset in range(0, len(payload), 64):
        chunk = payload[offset:offset + 64]
        await tb.send_frame(pack_command(OP_WRITE_HBM, addr + offset, len(chunk)))
        await tb.send_frame(chunk)
        response = await with_timeout(tb.recv_response(), 100, "us")
        assert bytes(response.tdata)[0] == ERR_OK

    assert tb.axi_ram.read(addr, len(payload)) == payload

    await tb.send_frame(pack_command(OP_RECONF_ICAP, addr, len(payload), slot_id=1))
    icap_frame = await with_timeout(tb.recv_icap_frame(), 500, "us")
    assert_icap_payload("write+reconf", bytes(icap_frame.tdata), payload)
    await tb.pulse_pr_done()
    response = await with_timeout(tb.recv_response(), 100, "us")
    assert bytes(response.tdata)[0] == ERR_OK


@cocotb.test()
async def test_reconf_dma_random_soak(dut):
    """Randomized pauses on AR, R and the ICAP sink at once, random sizes."""
    tb = TB(dut)
    await tb.reset()

    stats = {"violations": []}
    cocotb.start_soon(monitor_icap_stream(dut, stats))

    for trial in range(4):
        rng = random.Random(1000 + trial)
        nwords = rng.randrange(200, 1500)
        set_hbm_pauses(
            tb,
            ar=duty_pause(rng.getrandbits(30), rng.uniform(0.0, 0.5)),
            r=duty_pause(rng.getrandbits(30), rng.uniform(0.0, 0.7)),
        )
        set_icap_pause(tb, duty_pause(rng.getrandbits(30), rng.uniform(0.0, 0.6)))
        await run_reconf_dma(
            tb, dut, f"soak trial={trial} size={nwords}w", 0x80000 + trial * 0x4000, nwords,
            slot_id=trial % 2, seed=2000 + trial, timeout_us=1000,
        )

    set_hbm_pauses(tb, ar=duty_pause(51, 0.2), r=duty_pause(52, 0.4))
    set_icap_pause(tb, duty_pause(53, 0.3))
    await run_reconf_dma(tb, dut, "soak size=4096w", 0xA0000, 4096, seed=3000, timeout_us=2000)
    set_hbm_pauses(tb)
    set_icap_pause(tb)

    assert not stats["violations"], "\n".join(stats["violations"])


# ---------------------------------------------------------------------------
# PRDONE semantics
#
# ICAPE3 PRDONE idles HIGH: it only falls once the device accepts a partial's
# header and rises again at completion. On silicon the old level-sampling
# reported success the moment a command was accepted, whatever the ICAP did.
# ---------------------------------------------------------------------------


@cocotb.test()
async def test_reconf_prdone_idle_high_is_not_completion(dut):
    """An idle-high PRDONE level must not complete a reconf; a rising edge must."""
    tb = TB(dut)
    await tb.reset()

    dut.icap_pr_done.value = 1
    await wait_cycles(dut, 4)

    addr = 0xB0000
    payload = words_payload(24, seed=90)
    tb.axi_ram.write(addr, payload)

    await tb.send_frame(pack_command(OP_RECONF_ICAP, addr, len(payload)))
    icap_frame = await with_timeout(tb.recv_icap_frame(), 100, "us")
    assert_icap_payload("prdone_idle_high", bytes(icap_frame.tdata), payload)

    response_task = cocotb.start_soon(tb.recv_response())
    await wait_cycles(dut, 64)
    assert not response_task.done(), "reconf completed on the idle-high PRDONE level, without any edge"
    assert int(dut.slot_decouple.value) == 0b01

    # The device engages: PRDONE falls, then rises when the PR completes.
    dut.icap_pr_done.value = 0
    await wait_cycles(dut, 8)
    dut.icap_pr_done.value = 1
    await RisingEdge(dut.clk)

    response = await with_timeout(response_task, 100, "us")
    assert bytes(response.tdata)[0] == ERR_OK
    assert int(dut.slot_decouple.value) == 0


@cocotb.test()
async def test_reconf_prdone_never_arrives_times_out(dut):
    """A bitstream the device ignores draws no PRDONE edge; fail out, don't wedge."""
    tb = TB(dut)
    await tb.reset()

    dut.icap_pr_done.value = 1
    await wait_cycles(dut, 4)

    addr = 0xB4000
    payload = words_payload(8, seed=91)
    tb.axi_ram.write(addr, payload)

    await tb.send_frame(pack_command(OP_RECONF_ICAP, addr, len(payload), slot_id=1))
    await with_timeout(tb.recv_icap_frame(), 100, "us")

    # PR_DONE_TIMEOUT_CYCLES is overridden to 4096 in the Makefile (~16.4 us
    # at the 4 ns clock); the shipping default would take minutes here.
    response = await with_timeout(tb.recv_response(), 200, "us")
    assert bytes(response.tdata)[0] == ERR_PR_TIMEOUT
    assert int(dut.slot_decouple.value) == 0

    # The controller must be usable again after the timeout.
    await tb.send_frame(pack_command(OP_QUERY_ICAP_STATUS, 0, 0))
    status = await with_timeout(tb.recv_response(), 100, "us")
    data = bytes(status.tdata)
    assert data[0] == ERR_OK
    assert data[1] == 0
    assert data[3] == ERR_PR_TIMEOUT
