#!/usr/bin/env python
"""
cocotb testbench for log.

The slot computes the logit, ln(x / (1 - x)), over a stream of 32-bit floats,
16 per 512-bit line, through three Xilinx floating-point cores chained
subtract -> divide -> log.

  optional header beat : tdata[447:0] all ones.  Consumed, carries no data and
                         produces no output.  A header with tlast is a
                         complete (empty) request and yields no response beat.
  data beats           : 16 x 32-bit values, little-endian word order.
  response             : one beat per input data line, words in natural order,
                         tlast on the beat for the request's last line.
  slot boundary        : tdata = {meta[31:0], tlast, payload[511:0]}, 545 bits.
                         Request meta is {request size, session}, the size
                         being the header's packet_size for the whole request;
                         the last response beat carries {response bytes,
                         session} -- the request size less the header line --
                         which pkt_sender hands the TCP stack as the tx metadata.

WHAT THIS VERIFIES.  The real cores are not in the repo (regenerate them with
src/ip/gen_ip.tcl), so this runs against tb/fp_stubs.v, which applies
invertible *integer* operations at the real cores' latencies:

    floating_point_0  1 - x      latency 12   res = a - b
    floating_point_1  x / (1-x)  latency 29   res = {a[15:0], b[15:0]}
    floating_point_2  ln(.)      latency 23   res = a ^ 32'hA5A5A5A5

So these tests check the *dataflow*: word order, operand alignment through the
align FIFO (the divide stub concatenates both operands, so a misaligned x and
1-x show up immediately), tlast propagation, handshakes and slot state.  They
say nothing about IEEE-754 arithmetic, and because the stubs never deassert
tready they do not exercise the real cores' Blocking flow control.

WHEN A RUN GOES RED.  The floating-point cores have no reset -- see
reset_mid_request_flushes_fp_chain -- so a test that ends with values still
in the pipeline corrupts whichever test runs next.  Fix the FIRST failure and
re-run; the ones after it are usually fallout, not separate defects.

Run:

  make                     # verilator, ALIGN_DEPTH=32
  make ALIGN_DEPTH=64      # override the parameter
  make WAVES=1             # dump dump.fst alongside this file
  make SIM=icarus
  pytest -n auto           # sweep ALIGN_DEPTH over several builds
"""

import itertools
import logging
import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.regression import TestFactory
from cocotb.triggers import RisingEdge, with_timeout

from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource


VALUE_W = 32
VALUE_BYTES = VALUE_W // 8
BYTE_LANES = 64                             # 512-bit stream
WORDS_PER_LINE = BYTE_LANES // VALUE_BYTES  # 16
VALUE_MAX = 2**VALUE_W - 1

FP_ONE = 0x3F800000                         # 1.0f

# tb/fp_stubs.v -- must match, the reference model and the timing test use them
FP_SUB_LATENCY = 12
FP_DIV_LATENCY = 29
FP_LOG_LATENCY = 23
CHAIN_LATENCY = FP_SUB_LATENCY + FP_DIV_LATENCY + FP_LOG_LATENCY

# 16 values issued one per cycle, then the chain drains, then a cycle to
# register the response
LINE_CYCLES = WORDS_PER_LINE + CHAIN_LATENCY + 1

CLK_PERIOD_NS = 4


# ------------------------------------------------------ slot boundary beats
#
# The slot's tdata is the upstream offrac workload interface flattened onto one
# AXI-Stream (see ../src/rtl/log.v): {meta[31:0], tlast, payload[511:0]}, 545
# bits, one beat per 64-byte line.  cocotbext-axi sees a one-lane bus of
# 545-bit "bytes", so a frame's tdata is a list of ints, one per beat.

PAYLOAD_W = 512
META_W = 32
TLAST_BIT = PAYLOAD_W
META_SHIFT = PAYLOAD_W + 1
PAYLOAD_MASK = (1 << PAYLOAD_W) - 1

SESSION = 0x1234        # default session id; varied where it matters


def slot_meta(length, session):
    """meta = {length[15:0], session[15:0]}."""
    return ((length & 0xffff) << 16) | (session & 0xffff)


def pack_beats(payload, session=SESSION, req_bytes=None):
    """
    Split a byte payload into slot beats, in-band tlast on the last one.  The
    request meta is {request size, session}: the scheduler puts the header's
    packet_size -- the size of the whole request, header line included -- in
    the length field of every beat (scheduler.v rx_req_size), so that is what
    the slot derives its response meta from.
    """
    lines = [payload[i:i+BYTE_LANES] for i in range(0, len(payload), BYTE_LANES)]
    if req_bytes is None:
        req_bytes = len(payload)
    return [(slot_meta(req_bytes, session) << META_SHIFT)
            | (int(i == len(lines) - 1) << TLAST_BIT)
            | int.from_bytes(line, "little")
            for i, line in enumerate(lines)]


def beat_payload(beat):
    return (beat & PAYLOAD_MASK).to_bytes(BYTE_LANES, "little")


def beat_tlast(beat):
    return (beat >> TLAST_BIT) & 1


def beat_meta(beat):
    return (beat >> META_SHIFT) & ((1 << META_W) - 1)


def frame_payload(frame):
    return b"".join(beat_payload(beat) for beat in frame.tdata)


def check_response_meta(frame, response_bytes, session=SESSION):
    """
    In-band tlast only on the final beat, and that beat's meta is
    {response bytes, session}: pkt_sender hands it to the TCP stack as the tx
    metadata, so a wrong length there truncates or stalls the reply on the
    board.  Nothing reads the meta of earlier beats, so they are not checked.
    """
    lasts = [beat_tlast(beat) for beat in frame.tdata]
    assert lasts == [0] * (len(lasts) - 1) + [1], f"in-band tlast per beat: {lasts}"
    got = beat_meta(frame.tdata[-1])
    want = slot_meta(response_bytes, session)
    assert got == want, (
        f"response meta {got:#010x}, want {want:#010x} (length {got >> 16} vs "
        f"{response_bytes}, session {got & 0xffff:#06x} vs {session:#06x})")


def response_timeout_ns(line_count):
    """Generous bound so a deadlocked DUT fails the run instead of hanging it;
    the pause generators can stretch a request several times over."""
    return (line_count + 2) * LINE_CYCLES * CLK_PERIOD_NS * 10


# ------------------------------------------------------------------ packing

def pack_line(values):
    """One 64-byte beat holding up to 16 little-endian 32-bit words."""
    assert len(values) <= WORDS_PER_LINE
    padded = list(values) + [0] * (WORDS_PER_LINE - len(values))
    return b"".join(int(v).to_bytes(VALUE_BYTES, "little") for v in padded)


def unpack_words(data):
    data = bytes(data)
    assert len(data) % VALUE_BYTES == 0
    return [int.from_bytes(data[i:i+VALUE_BYTES], "little")
            for i in range(0, len(data), VALUE_BYTES)]


def header_line(size=0, config=0xffff, workload_id=0):
    """
    A fRAC request header: 0xff over bytes 0..55 (tdata[447:0]) is what marks
    the beat.  log reads none of the remaining fields -- they are filled
    in here to show that it ignores them and just drops the beat.
    """
    return (bytes([0xff] * 56)
            + int(size).to_bytes(4, "little")
            + int(config).to_bytes(2, "little")
            + int(workload_id).to_bytes(2, "little"))


def build_request(values, header=False):
    """
    Build a request payload and return it with the flat list of data words the
    slot will transform.  `values` is split across as many 16-word lines as
    needed and the last line is zero-padded -- that padding is data.
    `values=None` with header=True builds a header-only request.
    """
    lines = []
    if values is not None:
        lines = [list(values[i:i+WORDS_PER_LINE])
                 for i in range(0, len(values), WORDS_PER_LINE)] or [[]]

    payload = b""
    if header:
        payload += header_line(size=(len(lines) + 1) * BYTE_LANES)

    sent = []
    for line in lines:
        payload += pack_line(line)
        sent += line + [0] * (WORDS_PER_LINE - len(line))

    return payload, sent


def stub_chain(x):
    """
    The word tb/fp_stubs.v produces for input word x:
      sub = 1.0f - x   (integer subtract)
      div = {x[15:0], sub[15:0]}
      log = div ^ 0xA5A5A5A5
    The high half of `div` is the operand that came back out of the align
    FIFO, so a mismatch there is a misalignment, not an arithmetic error.
    """
    sub = (FP_ONE - x) & VALUE_MAX
    return (((x & 0xffff) << 16) | (sub & 0xffff)) ^ 0xA5A5A5A5


def reference_response(sent):
    """One output word per input word, in the same order, packed the same way."""
    return b"".join(stub_chain(v).to_bytes(VALUE_BYTES, "little") for v in sent)


def dut_align_depth(dut):
    try:
        return int(dut.ALIGN_DEPTH.value)
    except AttributeError:
        return int(os.environ.get("PARAM_ALIGN_DEPTH", 32))


def sideband(value):
    """cocotbext-axi collapses a sideband signal to a scalar when uniform."""
    if isinstance(value, (list, tuple)):
        assert len(set(value)) == 1, f"sideband varies across the frame: {value}"
        return value[0]
    return value


# ----------------------------------------------------------------- harness

class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        self.source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
        self.sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)

        # tstrb is not part of AxiStreamBus and the slot ignores it -- drive it
        # anyway so the input side is never X.
        dut.s_axis_tstrb.setimmediatevalue(1)   # KEEP_W = 1: one 545-bit lane

    def set_idle_generator(self, generator=None):
        if generator:
            self.source.set_pause_generator(generator())

    def set_backpressure_generator(self, generator=None):
        if generator:
            self.sink.set_pause_generator(generator())

    async def reset(self):
        self.dut.rst.setimmediatevalue(0)
        await wait_cycles(self.dut, 2)
        self.dut.rst.value = 1
        await wait_cycles(self.dut, 2)
        self.dut.rst.value = 0
        await wait_cycles(self.dut, 2)

    async def send_request(self, values, header=False, session=SESSION, **frame_kwargs):
        payload, sent = build_request(values, header)
        await self.source.send(AxiStreamFrame(pack_beats(payload, session), **frame_kwargs))
        return sent

    async def recv_response(self, line_count, session=SESSION):
        frame = await with_timeout(self.sink.recv(), response_timeout_ns(line_count), "ns")
        # one frame means tlast fired exactly once, on the final beat
        assert len(frame.tdata) == line_count, (
            f"expected {line_count} response beats, got {len(frame.tdata)}")
        # one response line per data line: the request size less the header
        check_response_meta(frame, line_count * BYTE_LANES, session)
        return frame

    def check(self, frame, sent):
        got = unpack_words(frame_payload(frame))
        want = unpack_words(reference_response(sent))
        if got != want:
            bad = next(i for i, (g, w) in enumerate(zip(got, want)) if g != w)
            raise AssertionError(
                f"word {bad}: got {got[bad]:#010x} want {want[bad]:#010x} "
                f"for x={sent[bad]:#010x} "
                f"(align FIFO returned {(got[bad] ^ 0xA5A5A5A5) >> 16:#06x}, "
                f"expected {sent[bad] & 0xffff:#06x})")

    async def run_request(self, values, header=False, session=SESSION, **frame_kwargs):
        sent = await self.send_request(values, header, session, **frame_kwargs)
        frame = await self.recv_response(len(sent) // WORDS_PER_LINE, session)
        self.check(frame, sent)
        return frame


async def wait_cycles(dut, count):
    for _ in range(count):
        await RisingEdge(dut.clk)


def cycle_pause():
    return itertools.cycle([1, 1, 1, 0])


def random_values(count):
    return [random.randrange(VALUE_MAX + 1) for _ in range(count)]


# ------------------------------------------------------------------- tests

async def run_test_single_line(dut, header=True, idle_inserter=None, backpressure_inserter=None):
    """One data line, with and without a header beat in front of it."""
    tb = TB(dut)
    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await tb.run_request(random_values(WORDS_PER_LINE), header=header)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_multi_line(dut, line_count=2, idle_inserter=None, backpressure_inserter=None):
    """One response beat per data line, tlast only on the last of them."""
    tb = TB(dut)
    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await tb.run_request(random_values(line_count * WORDS_PER_LINE), header=True)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_header_only(dut):
    """A header carrying tlast is an empty request: consumed, no response."""
    tb = TB(dut)
    await tb.reset()

    await tb.send_request(None, header=True)

    for _ in range(LINE_CYCLES):
        await RisingEdge(dut.clk)
        assert int(dut.m_axis_tvalid.value) == 0, "empty request produced a response"

    assert tb.sink.empty()

    # ...and the slot is left ready for a real request
    await tb.run_request(random_values(WORDS_PER_LINE), header=True)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_operand_alignment(dut):
    """
    x and (1 - x) must reach the divide as a pair.  Every lane here carries a
    distinct value in both halves, so an align-FIFO off-by-one shows up as the
    wrong x in the high half of the result.
    """
    tb = TB(dut)
    await tb.reset()

    values = [((i + 1) << 16) | (0xffff - i) for i in range(2 * WORDS_PER_LINE)]
    frame = await tb.run_request(values, header=True)

    # spell the alignment check out rather than leaning on the model alone
    for i, word in enumerate(unpack_words(frame_payload(frame))):
        assert (word ^ 0xA5A5A5A5) >> 16 == values[i] & 0xffff, f"lane {i} took the wrong x"

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_word_order(dut):
    """Word i of the response is the transform of word i of the input line."""
    tb = TB(dut)
    await tb.reset()

    values = [0x3E000000 + i * 0x00110011 + i for i in range(WORDS_PER_LINE)]
    frame = await tb.run_request(values, header=False)

    words = unpack_words(frame_payload(frame))
    assert words[0] == stub_chain(values[0])
    assert words[-1] == stub_chain(values[-1])
    assert words != sorted(words), "test vector too weak to catch a reordering"

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_back_to_back(dut, backpressure_inserter=None):
    """Consecutive requests must not bleed state into one another."""
    tb = TB(dut)
    await tb.reset()

    tb.set_backpressure_generator(backpressure_inserter)

    sent_a = await tb.send_request(random_values(2 * WORDS_PER_LINE), header=True)
    sent_b = await tb.send_request(random_values(WORDS_PER_LINE), header=False)

    frame_a = await tb.recv_response(2)
    frame_b = await tb.recv_response(1)

    tb.check(frame_a, sent_a)
    tb.check(frame_b, sent_b)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_sideband(dut):
    """tid/tdest/tuser come from the first beat of the request."""
    tb = TB(dut)
    await tb.reset()

    id_count = 2**len(tb.source.bus.tid)
    dest_count = 2**len(tb.source.bus.tdest)

    for tid, tdest, tuser in [(1, 1, 0), (id_count - 1, dest_count - 1, 1), (0, 0, 0)]:
        payload, sent = build_request(random_values(2 * WORDS_PER_LINE), header=True)
        beats = pack_beats(payload)

        # the intended sideband is on the first beat only; every later beat
        # carries something else, which the slot must ignore
        other = ((tid + 1) % id_count, (tdest + 1) % dest_count, tuser ^ 1)
        await tb.source.send(AxiStreamFrame(
            beats,
            tid=[tid] + [other[0]] * (len(beats) - 1),
            tdest=[tdest] + [other[1]] * (len(beats) - 1),
            tuser=[tuser] + [other[2]] * (len(beats) - 1),
        ))

        frame = await tb.recv_response(2)
        tb.check(frame, sent)

        assert sideband(frame.tid) == tid
        assert sideband(frame.tdest) == tdest
        assert sideband(frame.tuser) == tuser

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_response_meta(dut):
    """
    The last response beat's meta is {response bytes, session}, both taken
    from the request's meta: the session as is, the length as the request size
    less the header line when the request had one (one response line per data
    line).  The slot does not count beats -- a request whose declared size
    disagrees with its beats is reported at the declared size.
    """
    tb = TB(dut)
    await tb.reset()

    for session in [0x0000, 0x0001, 0xabcd, 0xffff]:
        for header in [True, False]:
            for lines in [1, 3]:
                sent = await tb.send_request(random_values(lines * WORDS_PER_LINE), header, session)
                frame = await tb.recv_response(lines, session)
                tb.check(frame, sent)

    # declared size is the source of truth: 3 data lines declared, 2 sent
    payload, sent = build_request(random_values(2 * WORDS_PER_LINE), header=True)
    await tb.source.send(AxiStreamFrame(pack_beats(payload, req_bytes=4 * BYTE_LANES)))
    frame = await with_timeout(tb.sink.recv(), response_timeout_ns(2), "ns")
    assert len(frame.tdata) == 2
    check_response_meta(frame, 3 * BYTE_LANES)
    tb.check(frame, sent)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_response_held(dut):
    """
    A response beat is held stable until it is accepted, and the slot refuses
    new input while one is outstanding.
    """
    tb = TB(dut)

    # cocotbext-axi's sink samples `pause` at the top of its driver loop and
    # the setter wakes a parked driver before it stores the new value, so a
    # sink parked on an idle bus can miss the change and leave tready high.
    # Pausing before reset is released means the driver starts out paused.
    tb.sink.pause = True
    await tb.reset()

    sent = await tb.send_request(random_values(WORDS_PER_LINE), header=True)

    for _ in range(4 * LINE_CYCLES):
        if int(dut.m_axis_tvalid.value):
            break
        await RisingEdge(dut.clk)
    else:
        raise AssertionError("no response within four line times")

    held = int(dut.m_axis_tdata.value)
    for _ in range(32):
        await RisingEdge(dut.clk)
        assert int(dut.m_axis_tvalid.value) == 1, "tvalid dropped before tready"
        assert int(dut.m_axis_tdata.value) == held, "tdata moved before tready"
        assert int(dut.s_axis_tready.value) == 0, "input accepted with a response pending"

    tb.sink.pause = False

    frame = await tb.recv_response(1)
    tb.check(frame, sent)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_timing(dut):
    """
    Values go in one per cycle and the chain adds a fixed latency, so a line's
    response lands a deterministic number of cycles after the line is accepted.
    A header beat costs one cycle and nothing more.
    """
    tb = TB(dut)
    await tb.reset()

    accepts = []
    resp_cycle = None
    cycle = 0

    async def watch():
        nonlocal resp_cycle, cycle
        while True:
            await RisingEdge(dut.clk)
            cycle += 1
            if int(dut.s_axis_tvalid.value) and int(dut.s_axis_tready.value):
                accepts.append(cycle)
            if resp_cycle is None and int(dut.m_axis_tvalid.value):
                resp_cycle = cycle

    watcher = cocotb.start_soon(watch())

    sent = await tb.send_request(random_values(WORDS_PER_LINE), header=True)
    frame = await tb.recv_response(1)
    watcher.kill()

    tb.check(frame, sent)

    assert len(accepts) == 2, f"expected header + 1 data beat, got {accepts}"
    assert accepts[1] - accepts[0] == 1, "a header beat should not stall the stream"
    assert resp_cycle - accepts[1] == LINE_CYCLES

    await wait_cycles(dut, 2)


async def run_test_reset_when_idle(dut):
    """
    A reset taken with the chain drained clears the slot's own state -- frame,
    issue and pack counters -- and leaves it reusable.
    """
    tb = TB(dut)
    await tb.reset()

    await tb.run_request(random_values(2 * WORDS_PER_LINE), header=True)

    await tb.reset()
    # reset drops the frame in flight but leaves the driver queues alone
    tb.source.clear()
    tb.sink.clear()

    assert int(dut.m_axis_tvalid.value) == 0
    assert tb.sink.empty()

    await tb.run_request(random_values(WORDS_PER_LINE), header=True)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


@cocotb.test()
async def reset_mid_request_flushes_fp_chain(dut):
    """
    Regression guard for the FP-chain flush.

    log instantiates floating_point_0/1/2 with only .aclk connected, and
    src/ip/gen_ip.tcl enables no ARESETn on any of them, so neither the stubs
    nor the real cores have a reset.  A reset taken with values in flight
    therefore abandons up to CHAIN_LATENCY of them inside the pipeline.  They
    arrive afterwards, the packer -- restarted at pack_idx 0 -- accumulates
    them, and on the 16th it raises a response beat belonging to the discarded
    request.  That beat carries tlast 0, so a consumer sees it merged onto the
    FRONT of the next request's response frame: a one-line request comes back
    as two beats, the first of them garbage.

    That is now prevented without touching the IP, by two things in log.v:
    an `outstanding` counter, so a result arriving when none is expected is
    dropped rather than packed; and a `flush_cnt` window after reset, during
    which s_axis_tready stays low so nothing new is issued until the cores
    have had longer than their total latency to empty themselves.

    Giving the cores ARESETn (CONFIG.Has_ARESETn in gen_ip.tcl) and driving it
    would be the other way to do it, and would also give the PR flow a real
    reset path -- but it changes every .xci.
    """
    tb = TB(dut)
    await tb.reset()

    # align_mem has no reset and no initial value, so fill every entry first.
    # The stale beat then carries data that is wrong rather than undefined,
    # which keeps this test's outcome the same in 2-state and 4-state sims.
    await tb.run_request(random_values(dut_align_depth(dut)), header=True)

    await tb.send_request(random_values(WORDS_PER_LINE), header=True)
    await tb.source.wait()
    # every value issued, none of them packed yet: the whole line is in flight
    await wait_cycles(dut, WORDS_PER_LINE + 4)

    await tb.reset()
    tb.source.clear()
    tb.sink.clear()

    # the abandoned values are still travelling while this request is issued
    sent = await tb.send_request(random_values(WORDS_PER_LINE), header=True)

    # Drain before judging.  The cores have no reset, so a test that ends with
    # values still in the pipeline corrupts whichever test runs next -- this
    # one must not leave any behind.
    await wait_cycles(dut, 4 * LINE_CYCLES)

    frames = [tb.sink.recv_nowait() for _ in range(tb.sink.count())]
    beats = sum(len(f.tdata) for f in frames)
    assert beats == 1, f"the discarded request left {beats - 1} stale response beat(s)"

    # Counting beats is not enough: align_mem's pointers are also state the
    # cores' lack of reset can desync, and that corrupts the contents of an
    # otherwise correctly-shaped response.
    tb.check(frames[0], sent)


@cocotb.test()
async def reset_mid_request_realigns_operands(dut):
    """
    The flush test above only counts response beats. This one checks the DATA
    of the request that follows a mid-flight reset.

    align_mem's pointers are reset, but align_pop is driven by the subtractor's
    result valid. A reset taken with values in flight leaves stale results in
    the subtractor; each one pops the align FIFO after the reset, advancing
    align_rd while align_wr sits at 0 because nothing is being issued. The
    pointers then stay skewed for the life of the module and every later
    x_aligned is the wrong operand -- which the divide stub exposes, since it
    concatenates both of them.
    """
    tb = TB(dut)
    await tb.reset()

    # fill align_mem so a skew reads stale data rather than X
    await tb.run_request(random_values(dut_align_depth(dut)), header=True)

    await tb.send_request(random_values(WORDS_PER_LINE), header=True)
    await tb.source.wait()
    await wait_cycles(dut, WORDS_PER_LINE + 4)      # whole line in flight

    await tb.reset()
    tb.source.clear()
    tb.sink.clear()

    # run_request checks the response against the reference model
    await tb.run_request(random_values(WORDS_PER_LINE), header=True)
    await tb.run_request(random_values(2 * WORDS_PER_LINE), header=True)

    await wait_cycles(dut, 4 * LINE_CYCLES)


async def run_stress_test(dut, idle_inserter=None, backpressure_inserter=None):
    """Randomised requests and sideband, checked against the stub-chain model."""
    tb = TB(dut)
    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    id_count = 2**len(tb.source.bus.tid)
    dest_count = 2**len(tb.source.bus.tdest)

    pending = []

    for _ in range(16):
        lines = random.randint(1, 3)
        values = random_values(lines * WORDS_PER_LINE)
        header = random.choice([True, False])
        tid = random.randrange(id_count)
        tdest = random.randrange(dest_count)
        session = random.randrange(0x10000)

        sent = await tb.send_request(values, header, session, tid=tid, tdest=tdest)
        pending.append((sent, lines, tid, tdest, session))

    for sent, lines, tid, tdest, session in pending:
        frame = await tb.recv_response(lines, session)
        tb.check(frame, sent)
        assert sideband(frame.tid) == tid
        assert sideband(frame.tdest) == tdest

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


if getattr(cocotb, 'top', None) is not None:

    factory = TestFactory(run_test_single_line)
    factory.add_option("header", [True, False])
    factory.add_option("idle_inserter", [None, cycle_pause])
    factory.add_option("backpressure_inserter", [None, cycle_pause])
    factory.generate_tests()

    factory = TestFactory(run_test_multi_line)
    factory.add_option("line_count", [1, 2, 4])
    factory.add_option("idle_inserter", [None, cycle_pause])
    factory.add_option("backpressure_inserter", [None, cycle_pause])
    factory.generate_tests()

    factory = TestFactory(run_test_back_to_back)
    factory.add_option("backpressure_inserter", [None, cycle_pause])
    factory.generate_tests()

    for test in [
                run_test_header_only,
                run_test_operand_alignment,
                run_test_word_order,
                run_test_sideband,
                run_test_response_meta,
                run_test_response_held,
                run_test_timing,
                run_test_reset_when_idle,
            ]:
        TestFactory(test).generate_tests()

    factory = TestFactory(run_stress_test)
    factory.add_option("idle_inserter", [None, cycle_pause])
    factory.add_option("backpressure_inserter", [None, cycle_pause])
    factory.generate_tests()


# --------------------------------------------------------------- cocotb-test
#
# Imported down here so that `make` needs neither pytest nor cocotb-test.

import cocotb_test.simulator  # noqa: E402
import pytest  # noqa: E402

tests_dir = os.path.dirname(__file__)
rtl_dir = os.path.abspath(os.path.join(tests_dir, '..', 'src', 'rtl'))


@pytest.mark.parametrize("align_depth", [16, 32, 64])
def test_log(request, align_depth):
    dut = "log"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(tests_dir, "fp_stubs.v"),
        os.path.join(rtl_dir, f"{dut}.v"),
    ]

    parameters = {'ALIGN_DEPTH': align_depth}

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}

    sim_build = os.path.join(tests_dir, "sim_build",
        request.node.name.replace('[', '-').replace(']', ''))

    cocotb_test.simulator.run(
        simulator="verilator",
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        toplevel=toplevel,
        module=module,
        parameters=parameters,
        sim_build=sim_build,
        extra_env=extra_env,
        extra_args=["--sv", "-Wno-WIDTHEXPAND", "-Wno-WIDTHTRUNC",
                    "-Wno-DECLFILENAME", "-Wno-UNUSEDSIGNAL"],
    )
