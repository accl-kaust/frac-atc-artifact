#!/usr/bin/env python
"""
cocotb testbench for norm.

Min-max normalisation, y = (x - min) / (max - min), with min and max taken over
the whole request.  That is inherently two pass: pass 1 receives the request
into a replay buffer while scanning for min/max, pass 2 replays it through a
shared subtract core and a divide by the per-request constant (max - min).

  optional header beat : tdata[447:0] all ones.  Consumed, carries no data and
                         produces no output.  A header with tlast is a
                         complete (empty) request and yields no response beat.
  data beats           : 16 x 32-bit IEEE-754 singles, little-endian word order.
  response             : one beat per input data line, y[i] in word i, tlast on
                         the beat for the request's last line.

WHAT THIS VERIFIES.  The real cores are not in the repo (regenerate them with
src/ip/gen_ip.tcl), so this runs against tb/fp_stubs.v, which applies
invertible *integer* operations at the real cores' latencies:

    floating_point_0  a - b      latency 12   res = a - b
    floating_point_3  a / b      latency 29   res = {a[15:0], b[15:0]}

So the arithmetic checked here is integer, not IEEE-754.  What that still pins
down is everything norm actually owns: the ordering key that lets a single
unsigned compare find min and max across both signs, that the scan covers every
word of every line, that (max - min) is computed once and reaches the divider as
a constant for every element, replay order, tlast, handshakes, and the flush
logic that copes with floating-point cores which have no reset.  Because the
stubs never deassert tready they do not exercise the cores' Blocking flow
control.

KNOWN LIMITS OF THE DUT, not covered by assertions here:
  * NaN is not handled by the ordering key (norm.v says so); these tests
    generate finite values only.
  * A request longer than MAX_LINES lines is never completed -- the slot stops
    asserting tready at the buffer limit and nothing resets last_seen, so the
    request stalls.  run_test_buffer_limit checks the guard holds at the
    boundary; it does not assert the stall is acceptable.
  * All-equal input gives range == 0, i.e. a divide by zero in the real core.
    The stub cannot show what that produces.

Run:

  make                     # verilator, MAX_LINES=256
  make MAX_LINES=16        # override the parameter
  make WAVES=1             # dump dump.fst alongside this file
  make SIM=icarus
  pytest -n auto           # sweep MAX_LINES over several builds
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

# tb/fp_stubs.v -- must match, the reference model and the timing test use them
FP_SUB_LATENCY = 12
FP_DIV_LATENCY = 29

# pass 1: a line is accepted, then scanned one value per cycle
SCAN_LINE_CYCLES = WORDS_PER_LINE + 1
# pass 2: load the line, issue 16 values one per cycle, drain both cores, then
# a cycle to register the response
NORM_LINE_CYCLES = WORDS_PER_LINE + FP_SUB_LATENCY + FP_DIV_LATENCY + 2

CLK_PERIOD_NS = 4
DUT_FLUSH_CYCLES = 128                      # norm.v default


def response_timeout_ns(line_count):
    """Generous bound so a deadlocked DUT fails the run instead of hanging it;
    the pause generators can stretch a request several times over."""
    cycles = DUT_FLUSH_CYCLES + (line_count + 2) * (SCAN_LINE_CYCLES + NORM_LINE_CYCLES)
    return cycles * CLK_PERIOD_NS * 10


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
    the beat.  norm reads none of the remaining fields -- they are filled in
    here to show that it ignores them and just drops the beat.
    """
    return (bytes([0xff] * 56)
            + int(size).to_bytes(4, "little")
            + int(config).to_bytes(2, "little")
            + int(workload_id).to_bytes(2, "little"))


def build_request(values, header=False):
    """
    Build a request payload and return it with the flat list of data words the
    slot will normalise.  `values` is split across as many 16-word lines as
    needed and the last line is zero-padded -- that padding is data, and it
    takes part in the min/max scan.  `values=None` builds a header-only request.
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


# ------------------------------------------------------------ reference model

def fkey(f):
    """
    norm's IEEE-754 total ordering: map a float to an unsigned key whose order
    matches the float's numeric order, so one unsigned compare serves both
    signs.  Undefined for NaN, exactly as in the RTL.
    """
    return (~f) & VALUE_MAX if f >> 31 else f | 0x80000000


def reference_min_max(sent):
    """
    The DUT compares strictly, so a tie keeps the first occurrence -- which is
    what max()/min() do too.  The values are equal either way.
    """
    return min(sent, key=fkey), max(sent, key=fkey)


def reference_response(sent):
    """
    What the stub chain produces: subtract gives (x - min) and (max - min), the
    divide stub concatenates the low halves of its two operands, so every word
    carries the element in its high half and the per-request range in its low
    half.  A range that differs word to word is an alignment bug, not an
    arithmetic one.
    """
    vmin, vmax = reference_min_max(sent)
    vrange = (vmax - vmin) & VALUE_MAX
    return [((((x - vmin) & VALUE_MAX) & 0xffff) << 16) | (vrange & 0xffff)
            for x in sent]


def sideband(value):
    """cocotbext-axi collapses a sideband signal to a scalar when uniform."""
    if isinstance(value, (list, tuple)):
        assert len(set(value)) == 1, f"sideband varies across the frame: {value}"
        return value[0]
    return value


def dut_max_lines(dut):
    try:
        return int(dut.MAX_LINES.value)
    except AttributeError:
        return int(os.environ.get("PARAM_MAX_LINES", 256))


# ----------------------------------------------------------------- harness

class TB:
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())

        self.source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
        self.sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)

        # tstrb is not part of AxiStreamBus and the slot ignores it -- drive it
        # anyway so the input side is never X.
        dut.s_axis_tstrb.setimmediatevalue(2**BYTE_LANES - 1)

        self.max_lines = dut_max_lines(dut)
        self.log.info("MAX_LINES = %d", self.max_lines)

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

    async def send_request(self, values, header=False, **frame_kwargs):
        payload, sent = build_request(values, header)
        await self.source.send(AxiStreamFrame(payload, **frame_kwargs))
        return sent

    async def recv_response(self, line_count):
        frame = await with_timeout(self.sink.recv(), response_timeout_ns(line_count), "ns")
        # one frame means tlast fired exactly once, on the final beat
        assert len(frame.tdata) == line_count * BYTE_LANES, (
            f"expected {line_count} response beats, got {len(frame.tdata) / BYTE_LANES}")
        return frame

    def check(self, frame, sent):
        got = unpack_words(frame.tdata)
        want = reference_response(sent)
        if got != want:
            vmin, vmax = reference_min_max(sent)
            bad = next(i for i, (g, w) in enumerate(zip(got, want)) if g != w)
            raise AssertionError(
                f"word {bad}: got {got[bad]:#010x} want {want[bad]:#010x} for "
                f"x={sent[bad]:#010x}, reference min={vmin:#010x} max={vmax:#010x} "
                f"(dut range low half {got[bad] & 0xffff:#06x}, "
                f"expected {(vmax - vmin) & 0xffff:#06x})")

    async def run_request(self, values, header=False, **frame_kwargs):
        sent = await self.send_request(values, header, **frame_kwargs)
        frame = await self.recv_response(len(sent) // WORDS_PER_LINE)
        self.check(frame, sent)
        return frame


async def wait_cycles(dut, count):
    for _ in range(count):
        await RisingEdge(dut.clk)


def cycle_pause():
    return itertools.cycle([1, 1, 1, 0])


def random_values(count):
    """
    Random finite IEEE-754 singles as bit patterns.  Inf and NaN are left out:
    norm's ordering key does not handle NaN, and the all-ones exponent is where
    both live.
    """
    out = []
    while len(out) < count:
        bits = random.randrange(1 << 32)
        if (bits >> 23) & 0xff != 0xff:
            out.append(bits)
    return out


# floats straddling zero, so the ordering key is genuinely exercised
MIXED_SIGN = [
    0x3F800000,  # 1.0
    0xBF800000,  # -1.0
    0x40000000,  # 2.0
    0xC0000000,  # -2.0
    0x3F000000,  # 0.5
    0xBF000000,  # -0.5
    0x3E800000,  # 0.25
    0xBE800000,  # -0.25
    0x40400000,  # 3.0
    0xC0400000,  # -3.0
    0x3DCCCCCD,  # 0.1
    0xBDCCCCCD,  # -0.1
    0x41200000,  # 10.0
    0xC1200000,  # -10.0
    0x00000000,  # +0.0
    0x80000000,  # -0.0
]


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
    """
    min/max span the whole request, so a multi-line request is the case that
    matters: one response beat per line, tlast only on the last of them.
    """
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

    for _ in range(SCAN_LINE_CYCLES + NORM_LINE_CYCLES):
        await RisingEdge(dut.clk)
        assert int(dut.m_axis_tvalid.value) == 0, "empty request produced a response"

    assert tb.sink.empty()

    # ...and the slot is left ready for a real request
    await tb.run_request(random_values(WORDS_PER_LINE), header=True)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_mixed_sign(dut):
    """
    The ordering key is the whole point of the scan: one unsigned compare has
    to rank negatives below positives, and -0.0 below +0.0.
    """
    tb = TB(dut)
    await tb.reset()

    values = list(MIXED_SIGN)
    random.shuffle(values)
    sent = await tb.send_request(values, header=True)
    frame = await tb.recv_response(1)
    tb.check(frame, sent)

    vmin, vmax = reference_min_max(sent)
    assert vmin == 0xC1200000, f"min should be -10.0, model says {vmin:#010x}"
    assert vmax == 0x41200000, f"max should be 10.0, model says {vmax:#010x}"

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_extreme_position(dut, position="first"):
    """
    The scan must cover every word of every line.  Park the extremes where a
    truncated scan window would miss them.
    """
    tb = TB(dut)
    await tb.reset()

    lines = min(4, tb.max_lines)
    values = [0x3F000000] * (lines * WORDS_PER_LINE)   # all 0.5
    low, high = 0xC1200000, 0x41200000                 # -10.0, 10.0

    spots = {
        "first": (0, 1),
        "last": (len(values) - 1, len(values) - 2),
        "line_edges": (WORDS_PER_LINE - 1, len(values) - WORDS_PER_LINE),
    }[position]
    values[spots[0]] = low
    values[spots[1]] = high

    sent = await tb.send_request(values, header=True)
    frame = await tb.recv_response(lines)
    tb.check(frame, sent)

    vmin, vmax = reference_min_max(sent)
    assert (vmin, vmax) == (low, high)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_range_is_constant(dut):
    """
    (max - min) is a per-request constant.  The divide stub puts its second
    operand in the low half of every result word, so every word must carry the
    same range -- a per-element value there would mean the divider is being fed
    something that moves.
    """
    tb = TB(dut)
    await tb.reset()

    lines = min(3, tb.max_lines)
    sent = await tb.send_request(random_values(lines * WORDS_PER_LINE), header=True)
    frame = await tb.recv_response(lines)
    tb.check(frame, sent)

    vmin, vmax = reference_min_max(sent)
    lows = {w & 0xffff for w in unpack_words(frame.tdata)}
    assert lows == {(vmax - vmin) & 0xffff}, f"range not constant across the request: {lows}"

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_all_equal(dut):
    """
    Every value identical: min == max, so the range is zero.  The stub divide
    does not care; this pins the dataflow, and documents that the real core
    would be dividing by zero here.
    """
    tb = TB(dut)
    await tb.reset()

    sent = await tb.send_request([0x40490FDB] * WORDS_PER_LINE, header=True)
    frame = await tb.recv_response(1)
    tb.check(frame, sent)

    assert all(w & 0xffff == 0 for w in unpack_words(frame.tdata))

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_word_order(dut):
    """
    y[i] lands in word i.  The module norm replaced packed in reverse, so this
    is worth stating outright.
    """
    tb = TB(dut)
    await tb.reset()

    # a permutation, not a ramp: a monotonic vector normalises to a monotonic
    # response, in which a reordering would be invisible
    values = [0x3F800000 + ((i * 7) % WORDS_PER_LINE) * 0x00010001
              for i in range(WORDS_PER_LINE)]
    sent = await tb.send_request(values, header=False)
    frame = await tb.recv_response(1)
    tb.check(frame, sent)

    vmin, _ = reference_min_max(sent)
    words = unpack_words(frame.tdata)
    assert words[0] >> 16 == ((values[0] - vmin) & VALUE_MAX) & 0xffff
    assert words[-1] >> 16 == ((values[-1] - vmin) & VALUE_MAX) & 0xffff
    assert words != sorted(words), "vector too weak: a sort would be invisible"
    assert words != words[::-1], "vector too weak: a reversal would be invisible"

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_back_to_back(dut, backpressure_inserter=None):
    """
    min/max must be rescanned per request.  The second request here is entirely
    inside the first one's range, so a stale min or max would show.
    """
    tb = TB(dut)
    await tb.reset()

    tb.set_backpressure_generator(backpressure_inserter)

    wide = [0xC1200000, 0x41200000] + random_values(WORDS_PER_LINE - 2)
    narrow = [0x3F000000 + i for i in range(WORDS_PER_LINE)]

    sent_a = await tb.send_request(wide, header=True)
    sent_b = await tb.send_request(narrow, header=False)

    frame_a = await tb.recv_response(1)
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
    lines = min(2, tb.max_lines)

    for tid, tdest, tuser in [(1, 1, 0), (id_count - 1, dest_count - 1, 1), (0, 0, 0)]:
        payload, sent = build_request(random_values(lines * WORDS_PER_LINE), header=True)
        beats = len(payload) // BYTE_LANES

        # the intended sideband is on the first beat only; every later beat
        # carries something else, which the slot must ignore
        other = ((tid + 1) % id_count, (tdest + 1) % dest_count, tuser ^ 1)
        await tb.source.send(AxiStreamFrame(
            payload,
            tid=[tid] * BYTE_LANES + [other[0]] * BYTE_LANES * (beats - 1),
            tdest=[tdest] * BYTE_LANES + [other[1]] * BYTE_LANES * (beats - 1),
            tuser=[tuser] * BYTE_LANES + [other[2]] * BYTE_LANES * (beats - 1),
        ))

        frame = await tb.recv_response(lines)
        tb.check(frame, sent)

        assert sideband(frame.tid) == tid
        assert sideband(frame.tdest) == tdest
        assert sideband(frame.tuser) == tuser

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_response_held(dut):
    """
    A response beat is held stable until it is accepted, and the slot refuses
    new input while a request is in progress.
    """
    tb = TB(dut)

    # cocotbext-axi's sink samples `pause` at the top of its driver loop and
    # the setter wakes a parked driver before it stores the new value, so a
    # sink parked on an idle bus can miss the change and leave tready high.
    # Pausing before reset is released means the driver starts out paused.
    tb.sink.pause = True
    await tb.reset()

    sent = await tb.send_request(random_values(WORDS_PER_LINE), header=True)

    for _ in range(DUT_FLUSH_CYCLES + 4 * NORM_LINE_CYCLES):
        if int(dut.m_axis_tvalid.value):
            break
        await RisingEdge(dut.clk)
    else:
        raise AssertionError("no response within the expected window")

    held = int(dut.m_axis_tdata.value)
    for _ in range(32):
        await RisingEdge(dut.clk)
        assert int(dut.m_axis_tvalid.value) == 1, "tvalid dropped before tready"
        assert int(dut.m_axis_tdata.value) == held, "tdata moved before tready"
        assert int(dut.s_axis_tready.value) == 0, "input accepted mid-request"

    tb.sink.pause = False

    frame = await tb.recv_response(1)
    tb.check(frame, sent)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_timing(dut):
    """
    Pass 1 scans one value per cycle, so input lines are accepted every
    SCAN_LINE_CYCLES.  Pass 2 issues one value per cycle and drains both cores
    per line, so response beats come every NORM_LINE_CYCLES.
    """
    tb = TB(dut)
    await tb.reset()

    lines = min(3, tb.max_lines)
    accepts = []
    responses = []
    cycle = 0

    async def watch():
        nonlocal cycle
        while True:
            await RisingEdge(dut.clk)
            cycle += 1
            if int(dut.s_axis_tvalid.value) and int(dut.s_axis_tready.value):
                accepts.append(cycle)
            if int(dut.m_axis_tvalid.value) and int(dut.m_axis_tready.value):
                responses.append(cycle)

    watcher = cocotb.start_soon(watch())

    sent = await tb.send_request(random_values(lines * WORDS_PER_LINE), header=True)
    frame = await tb.recv_response(lines)
    watcher.kill()

    tb.check(frame, sent)

    assert len(accepts) == lines + 1, f"expected header + {lines} data beats, got {accepts}"
    assert accepts[1] - accepts[0] == 1, "a header beat should not stall the stream"
    for a, b in zip(accepts[1:], accepts[2:]):
        assert b - a == SCAN_LINE_CYCLES, f"input line spacing {b - a}, want {SCAN_LINE_CYCLES}"

    assert len(responses) == lines
    for a, b in zip(responses, responses[1:]):
        assert b - a == NORM_LINE_CYCLES, f"response spacing {b - a}, want {NORM_LINE_CYCLES}"

    await wait_cycles(dut, 2)


async def run_test_buffer_limit(dut):
    """
    The replay buffer is MAX_LINES deep.  A request that exactly fills it must
    still complete, and the slot must stop accepting past the limit rather than
    wrapping and overwriting line 0.
    """
    tb = TB(dut)
    await tb.reset()

    await tb.run_request(random_values(tb.max_lines * WORDS_PER_LINE), header=False)
    assert tb.sink.empty()

    # one line too many: the guard has to stop accepting rather than wrap and
    # overwrite line 0.  Count beats -- tready is low during pass 2 regardless,
    # so sampling it would pass whether the guard exists or not.
    accepted = 0

    async def count_accepts():
        nonlocal accepted
        while True:
            await RisingEdge(dut.clk)
            if int(dut.s_axis_tvalid.value) and int(dut.s_axis_tready.value):
                accepted += 1

    counter = cocotb.start_soon(count_accepts())
    await tb.send_request(random_values((tb.max_lines + 1) * WORDS_PER_LINE), header=False)
    await wait_cycles(dut, (tb.max_lines + 2) * SCAN_LINE_CYCLES)
    counter.kill()

    assert accepted == tb.max_lines, (
        f"accepted {accepted} lines into a buffer that holds {tb.max_lines}")
    assert tb.sink.empty()

    await tb.reset()
    tb.source.clear()
    tb.sink.clear()
    await wait_cycles(dut, 2)


async def run_test_reset_mid_request(dut):
    """
    The floating-point cores have no reset, so norm counts data through them
    instead: `outstanding` drops results that arrive when none are expected,
    and `flush_cnt` holds tready low after reset for longer than the cores'
    combined latency.  A reset with values in flight must therefore leave no
    residue in the next request.
    """
    tb = TB(dut)
    await tb.reset()

    lines = min(4, tb.max_lines)

    # Reset across the whole request, including the window where all 16 values
    # of a line sit inside the cores at once -- that is the case the stale
    # result guard exists for.
    # How much survives a reset depends on exactly where in the drain it lands,
    # so sweep the whole pass-2 window rather than sampling a few points.
    pass1 = SCAN_LINE_CYCLES * lines + 4
    stalls = [SCAN_LINE_CYCLES, pass1]                       # mid pass 1, between passes
    stalls += list(range(pass1 + FP_SUB_LATENCY,             # across pass 2's drain
                         pass1 + FP_SUB_LATENCY + WORDS_PER_LINE + FP_DIV_LATENCY, 3))

    for stall in stalls:
        await tb.send_request(random_values(lines * WORDS_PER_LINE), header=True)
        await wait_cycles(dut, DUT_FLUSH_CYCLES + stall)

        await tb.reset()
        # reset drops the frame in flight but leaves the driver queues alone
        tb.source.clear()
        tb.sink.clear()

        assert int(dut.m_axis_tvalid.value) == 0

        # no header: the tightest turnaround from reset to pass 2, which is the
        # worst case for stale results still leaving the cores
        await tb.run_request(random_values(WORDS_PER_LINE), header=False)
        assert tb.sink.empty()

    await wait_cycles(dut, 2)


async def run_stress_test(dut, idle_inserter=None, backpressure_inserter=None):
    """Randomised requests and sideband, checked against the stub-chain model."""
    tb = TB(dut)
    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    id_count = 2**len(tb.source.bus.tid)
    dest_count = 2**len(tb.source.bus.tdest)

    pending = []

    for _ in range(12):
        lines = random.randint(1, min(3, tb.max_lines))
        values = random_values(lines * WORDS_PER_LINE)
        # sometimes force the extremes onto known lanes
        if random.random() < 0.5:
            values[random.randrange(len(values))] = 0xC1200000
            values[random.randrange(len(values))] = 0x41200000
        header = random.choice([True, False])
        tid = random.randrange(id_count)
        tdest = random.randrange(dest_count)

        sent = await tb.send_request(values, header, tid=tid, tdest=tdest)
        pending.append((sent, lines, tid, tdest))

    for sent, lines, tid, tdest in pending:
        frame = await tb.recv_response(lines)
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

    factory = TestFactory(run_test_extreme_position)
    factory.add_option("position", ["first", "last", "line_edges"])
    factory.generate_tests()

    factory = TestFactory(run_test_back_to_back)
    factory.add_option("backpressure_inserter", [None, cycle_pause])
    factory.generate_tests()

    for test in [
                run_test_header_only,
                run_test_mixed_sign,
                run_test_range_is_constant,
                run_test_all_equal,
                run_test_word_order,
                run_test_sideband,
                run_test_response_held,
                run_test_timing,
                run_test_buffer_limit,
                run_test_reset_mid_request,
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


@pytest.mark.parametrize("max_lines", [4, 16, 256])
def test_norm(request, max_lines):
    dut = "norm"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(tests_dir, "fp_stubs.v"),
        os.path.join(rtl_dir, f"{dut}.v"),
    ]

    parameters = {'MAX_LINES': max_lines}

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
