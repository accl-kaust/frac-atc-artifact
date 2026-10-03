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

The core streams: a line's 16 values enter the cores on 16 cycles in a row and
the next line's follow straight after, so several lines -- of one request or
of several -- are in the cores at once.  Their responses wait in an output
FIFO of OUT_DEPTH lines, and the core takes no line it could not answer.

TWO LEVELS.  LEVEL=core (the default) drives log_core itself: every handshake,
the sideband, the timing.  LEVEL=slot drives the module as it is built into a
cell, behind the static side of its slot (reassembly/tb/tb_slot.sv): credits
and PIPE_LEN register stages each way, which carry no sideband.

WHEN A RUN GOES RED.  The floating-point cores have no reset -- see
reset_mid_request_flushes_fp_chain -- so a test that ends with values still
in the pipeline corrupts whichever test runs next.  Fix the FIRST failure and
re-run; the ones after it are usually fallout, not separate defects.

Run:

  make                     # verilator, the core, ALIGN_DEPTH=32, OUT_DEPTH=8
  make LEVEL=slot          # the module behind its slot's static side
  make ALIGN_DEPTH=64      # override a parameter (LEVEL=core)
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

# Once the pipeline is full, lines are taken and answered one every
# LINE_CYCLES: a value per cycle.
LINE_CYCLES = WORDS_PER_LINE

# From a data line taken to its response beat: a cycle into in_line, one into
# cur_line, its 16 values issued, the chain, then the output FIFO
OUT_FIFO_LATENCY = 3
FIRST_RESPONSE_CYCLES = 2 + (WORDS_PER_LINE - 1) + CHAIN_LATENCY + OUT_FIFO_LATENCY

# What one line costs taken alone, the slowest the core ever is: the bound
# for timeouts and drains
SOLO_LINE_CYCLES = FIRST_RESPONSE_CYCLES + 1

DUT_FLUSH_CYCLES = 128                      # log_core.v default

LEVEL = os.environ.get("LEVEL", "core")

# static's response sink: its FIFO, CREDITS deep, and its output register
SLOT_RESPONSE_LINES = 64 + 1

# A line is about 100 cycles between being taken and leaving, so the output
# FIFO must answer for 7 lines for a line to go in every 16 cycles.  Smaller
# OUT_DEPTH is correct but slower; the rate checks need at least this.
FULL_RATE_OUT_DEPTH = 8

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
    return (DUT_FLUSH_CYCLES + (line_count + 2) * SOLO_LINE_CYCLES) * CLK_PERIOD_NS * 10


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


def dut_out_depth(dut):
    try:
        return int(dut.OUT_DEPTH.value)
    except AttributeError:
        return int(os.environ.get("PARAM_OUT_DEPTH", 8))


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
        if LEVEL == "slot":
            dut.decouple.setimmediatevalue(0)

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


def core(dut):
    """log_core: the top level at LEVEL=core, inside the module at LEVEL=slot.
    The checks about the core's own handshake -- when it accepts, when it
    answers, when it refuses -- read its ports; everything else goes through
    the top level."""
    return dut if LEVEL == "core" else dut.rm_inst.core_inst


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

    for _ in range(2 * SOLO_LINE_CYCLES):
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
    A response is held stable until it is accepted, and the core takes no line
    it could not answer: with the sink stalled it takes OUT_DEPTH lines beyond
    the ones it has sent and then refuses.  At LEVEL=slot static's response
    sink holds SLOT_RESPONSE_LINES more.  Released, every response comes back
    in order and intact.
    """
    tb = TB(dut)

    # cocotbext-axi's sink samples `pause` at the top of its driver loop and
    # the setter wakes a parked driver before it stores the new value, so a
    # sink parked on an idle bus can miss the change and leave tready high.
    # Pausing before reset is released means the driver starts out paused.
    tb.sink.pause = True
    await tb.reset()

    capacity = dut_out_depth(dut) + (SLOT_RESPONSE_LINES if LEVEL == "slot" else 0)
    hs = core(dut)

    # one data line per request, no header, so every beat taken is a line
    requests = [await tb.send_request(random_values(WORDS_PER_LINE), header=False)
                for _ in range(capacity + 4)]

    taken = 0

    async def count_taken():
        nonlocal taken
        while True:
            await RisingEdge(dut.clk)
            if int(hs.s_axis_tvalid.value) and int(hs.s_axis_tready.value):
                taken += 1

    counter = cocotb.start_soon(count_taken())
    await wait_cycles(dut, DUT_FLUSH_CYCLES + (capacity + 4) * SOLO_LINE_CYCLES)

    assert taken == capacity, f"took {taken} lines with room to answer {capacity}"
    assert int(hs.s_axis_tready.value) == 0, "input accepted with no room for its response"

    held = int(dut.m_axis_tdata.value)
    core_held = int(hs.m_axis_tdata.value)
    for _ in range(32):
        await RisingEdge(dut.clk)
        assert int(dut.m_axis_tvalid.value) == 1, "tvalid dropped before tready"
        assert int(dut.m_axis_tdata.value) == held, "tdata moved before tready"
        assert int(hs.m_axis_tvalid.value) == 1, "the core dropped its waiting response"
        assert int(hs.m_axis_tdata.value) == core_held, "the core's waiting response moved"
        assert int(hs.s_axis_tready.value) == 0, "input accepted with no room for its response"
    counter.kill()

    tb.sink.pause = False

    for sent in requests:
        frame = await tb.recv_response(1)
        tb.check(frame, sent)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_timing(dut):
    """
    The core streams.  A header costs one cycle.  The first data line goes
    straight to cur_line and the second waits in in_line, so they are taken
    two cycles apart; after that a line is taken as cur_line finishes, every
    16 cycles.  The first response leaves FIRST_RESPONSE_CYCLES after its line
    was taken and the rest follow one every 16 cycles.
    """
    tb = TB(dut)
    await tb.reset()

    lines = 4
    accepts = []
    responses = []
    cycle = 0
    hs = core(dut)

    async def watch():
        nonlocal cycle
        while True:
            await RisingEdge(dut.clk)
            cycle += 1
            if int(hs.s_axis_tvalid.value) and int(hs.s_axis_tready.value):
                accepts.append(cycle)
            if int(hs.m_axis_tvalid.value) and int(hs.m_axis_tready.value):
                responses.append(cycle)

    watcher = cocotb.start_soon(watch())

    sent = await tb.send_request(random_values(lines * WORDS_PER_LINE), header=True)
    frame = await tb.recv_response(lines)
    watcher.kill()

    tb.check(frame, sent)

    assert len(accepts) == lines + 1, f"expected header + {lines} data beats, got {accepts}"
    assert accepts[1] - accepts[0] == 1, "a header beat should not stall the stream"
    data = accepts[1:]
    gaps = [b - a for a, b in zip(data, data[1:])]
    assert gaps == [2] + [LINE_CYCLES] * (lines - 2), f"data line spacing {gaps}"

    assert len(responses) == lines
    assert responses[0] - data[0] == FIRST_RESPONSE_CYCLES, (
        f"first response {responses[0] - data[0]} cycles after its line, "
        f"want {FIRST_RESPONSE_CYCLES}")
    gaps = [b - a for a, b in zip(responses, responses[1:])]
    assert gaps == [LINE_CYCLES] * (lines - 1), f"response spacing {gaps}"

    await wait_cycles(dut, 2)


async def run_test_stream_4k(dut):
    """
    A 4 KB request -- a header and 63 data lines -- streams: its responses
    leave a line every 16 cycles, so the last is FIRST_RESPONSE_CYCLES +
    62 x 16 cycles after the first data line was taken, where taking one line
    at a time cost 81 cycles a line.
    """
    tb = TB(dut)
    await tb.reset()

    lines = 63
    first_take = None
    responses = []
    hs = core(dut)
    cycle = 0

    async def watch():
        nonlocal cycle, first_take
        while True:
            await RisingEdge(dut.clk)
            cycle += 1
            if first_take is None and int(hs.s_axis_tvalid.value) and int(hs.s_axis_tready.value):
                first_take = cycle
            if int(hs.m_axis_tvalid.value) and int(hs.m_axis_tready.value):
                responses.append(cycle)

    watcher = cocotb.start_soon(watch())
    await tb.run_request(random_values(lines * WORDS_PER_LINE), header=True)
    watcher.kill()

    # the header is taken a cycle before the first data line
    total = responses[-1] - (first_take + 1)
    want = FIRST_RESPONSE_CYCLES + (lines - 1) * LINE_CYCLES
    if dut_out_depth(dut) >= FULL_RATE_OUT_DEPTH:
        assert total == want, f"{lines} lines took {total} cycles, want {want}"
    else:
        tb.log.info("OUT_DEPTH %d: %d lines took %d cycles (%d at full rate)",
                    dut_out_depth(dut), lines, total, want)

    await wait_cycles(dut, 2)


async def run_test_requests_overlap(dut):
    """
    Requests follow one another into the cores without waiting for the one
    ahead to be answered, and each line still comes back with its own
    request's meta and tlast.  Sessions differ, and the first request has a
    header while the second does not, so the response lengths differ too.
    """
    tb = TB(dut)
    await tb.reset()

    hs = core(dut)
    takes = []

    async def watch():
        while True:
            await RisingEdge(dut.clk)
            if int(hs.s_axis_tvalid.value) and int(hs.s_axis_tready.value):
                takes.append(int(hs.s_axis_tlast.value))
            if takes and int(hs.m_axis_tvalid.value):
                # once the first response is out, both requests are already in
                return

    watcher = cocotb.start_soon(watch())
    sent_a = await tb.send_request(random_values(3 * WORDS_PER_LINE), header=True, session=0x1111)
    sent_b = await tb.send_request(random_values(2 * WORDS_PER_LINE), header=False, session=0x2222)

    frame_a = await tb.recv_response(3, session=0x1111)
    frame_b = await tb.recv_response(2, session=0x2222)
    tb.check(frame_a, sent_a)
    tb.check(frame_b, sent_b)
    await watcher

    if dut_out_depth(dut) >= FULL_RATE_OUT_DEPTH:
        assert takes.count(1) == 2, (
            f"the second request was not taken before the first was answered: {takes}")

    assert tb.sink.empty()
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
    await wait_cycles(dut, 4 * SOLO_LINE_CYCLES)

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

    await wait_cycles(dut, 4 * SOLO_LINE_CYCLES)


@cocotb.test()
async def reset_with_lines_in_flight(dut):
    """
    Streaming puts several lines in the cores at once, and more in in_line,
    cur_line and the output FIFO.  A reset taken at any point of a long
    request must drop all of it: the next request comes back alone and right.
    """
    tb = TB(dut)
    await tb.reset()

    # fill align_mem so a skew reads stale data rather than X
    await tb.run_request(random_values(dut_align_depth(dut)), header=True)

    for stall in [20, 40, 70, 100, 140]:
        await tb.send_request(random_values(12 * WORDS_PER_LINE), header=True)
        await tb.source.wait()
        await wait_cycles(dut, stall)

        await tb.reset()
        tb.source.clear()
        tb.sink.clear()

        sent = await tb.send_request(random_values(2 * WORDS_PER_LINE), header=True)
        await wait_cycles(dut, DUT_FLUSH_CYCLES + 4 * SOLO_LINE_CYCLES)

        frames = [tb.sink.recv_nowait() for _ in range(tb.sink.count())]
        beats = sum(len(f.tdata) for f in frames)
        assert beats == 2, f"reset at {stall}: {beats} beats, want the 2 of the next request"
        tb.check(frames[0], sent)


async def run_stress_test(dut, idle_inserter=None, backpressure_inserter=None):
    """Randomised requests and sideband, checked against the stub-chain model."""
    tb = TB(dut)
    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    id_count = 2**len(tb.source.bus.tid) if LEVEL == "core" else 1
    dest_count = 2**len(tb.source.bus.tdest) if LEVEL == "core" else 1

    pending = []

    for _ in range(16):
        lines = random.randint(1, 3)
        values = random_values(lines * WORDS_PER_LINE)
        header = random.choice([True, False])
        tid = random.randrange(id_count) if LEVEL == "core" else 0
        tdest = random.randrange(dest_count) if LEVEL == "core" else 0
        session = random.randrange(0x10000)

        sent = await tb.send_request(values, header, session, tid=tid, tdest=tdest)
        pending.append((sent, lines, tid, tdest, session))

    for sent, lines, tid, tdest, session in pending:
        frame = await tb.recv_response(lines, session)
        tb.check(frame, sent)
        if LEVEL == "core":
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
                run_test_response_meta,
                run_test_response_held,
                run_test_timing,
                run_test_stream_4k,
                run_test_requests_overlap,
                run_test_reset_when_idle,
            ]:
        TestFactory(test).generate_tests()

    # the slot boundary carries no sideband
    if LEVEL == "core":
        TestFactory(run_test_sideband).generate_tests()

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


@pytest.mark.parametrize("level,align_depth,out_depth", [
    ("core", 16, 8), ("core", 32, 8), ("core", 64, 8), ("core", 32, 4), ("core", 32, 16),
    ("slot", 32, 8),
])
def test_log(request, level, align_depth, out_depth):
    dut = "log"
    module = os.path.splitext(os.path.basename(__file__))[0]
    reasm_dir = os.path.join(tests_dir, "..", "..", "..", "reassembly")
    taxi_dir = os.path.join(tests_dir, "..", "..", "..", "..", "..", "lib", "taxi", "axis", "rtl")

    verilog_sources = [
        os.path.join(tests_dir, "fp_stubs.v"),
        os.path.join(rtl_dir, f"{dut}_core.v"),
        os.path.join(taxi_dir, "taxi_axis_if.sv"),
        os.path.join(taxi_dir, "taxi_axis_fifo.sv"),
        os.path.join(reasm_dir, "rtl", "axis_fifo_taxi.sv"),
    ]
    extra_args = ["--sv", "-DSIMULATION", "-Wno-WIDTHEXPAND", "-Wno-WIDTHTRUNC",
                  "-Wno-DECLFILENAME", "-Wno-UNUSEDSIGNAL"]

    if level == "slot":
        toplevel = "tb_slot"
        verilog_sources += [
            os.path.join(rtl_dir, f"{dut}.v"),
            os.path.join(reasm_dir, "rtl", "slot_credit.v"),
            os.path.join(reasm_dir, "rtl", "slot_boundary.v"),
            os.path.join(reasm_dir, "tb", "tb_slot.sv"),
        ]
        extra_args.append(f"-DSLOT_RM={dut}")
        parameters = {}
    else:
        toplevel = f"{dut}_core"
        parameters = {'ALIGN_DEPTH': align_depth, 'OUT_DEPTH': out_depth}

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}
    extra_env['LEVEL'] = level

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
        extra_args=extra_args,
    )
