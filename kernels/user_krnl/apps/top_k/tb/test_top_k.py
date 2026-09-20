#!/usr/bin/env python
"""
cocotb testbench for top_k.

Protocol under test (see ../src/rtl/top_k.v):

  optional header beat : tdata[447:0] all ones marks the beat as a header,
                         tdata[495:480] carries the result mask.  Not data.
  data beats           : 16 x 32-bit unsigned values, little-endian word order.
  tlast                : final beat of the request.
  response             : one beat, 16 x 32-bit values in descending order,
                         word 0 largest, word i zeroed when mask bit i is
                         clear, words >= TOP_K_NUM always zero.

Run:

  make                     # verilator, TOP_K_NUM=16
  make TOP_K_NUM=8         # override the parameter
  make WAVES=1             # dump dump.fst alongside this file
  make SIM=icarus
  pytest -n auto           # sweep TOP_K_NUM over several builds
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
MASK_ALL = 0xffff

# A line costs one cycle to accept plus one cycle per value.
LINE_CYCLES = WORDS_PER_LINE + 1

CLK_PERIOD_NS = 4

# Generous bound so a deadlocked DUT fails the run instead of hanging it; the
# pause generators can stretch a request several times over.
RESPONSE_TIMEOUT_NS = 64 * LINE_CYCLES * CLK_PERIOD_NS


# ------------------------------------------------------------------ packing

def pack_line(values):
    """One 64-byte beat holding up to 16 little-endian 32-bit values."""
    assert len(values) <= WORDS_PER_LINE
    padded = list(values) + [0] * (WORDS_PER_LINE - len(values))
    return b"".join(int(v).to_bytes(VALUE_BYTES, "little") for v in padded)


def unpack_line(data):
    data = bytes(data)
    assert len(data) == BYTE_LANES
    return [int.from_bytes(data[i:i+VALUE_BYTES], "little")
            for i in range(0, BYTE_LANES, VALUE_BYTES)]


def header_line(mask=MASK_ALL, size=0, workload_id=0):
    """
    A fRAC request header: 0xff over bytes 0..55 (tdata[447:0]), the request
    size in bytes 56..59, the config word -- which the slot reads as the
    result mask, tdata[495:480] -- in bytes 60..61, the workload id in bytes
    62..63.  Only the mask reaches the sorter; the other fields are filled in
    here to show that the slot ignores them.
    """
    return (bytes([0xff] * 56)
            + int(size).to_bytes(4, "little")
            + int(mask).to_bytes(2, "little")
            + int(workload_id).to_bytes(2, "little"))


def build_request(values, mask=None):
    """
    Build a request payload and return it with the value list the slot will
    actually sort.  `values` is split across as many 16-word lines as needed
    and the last line is zero-padded -- that padding is data, so it comes back
    in the returned list.  `values=None` builds a header-only request.
    """
    lines = []
    if values is not None:
        lines = [list(values[i:i+WORDS_PER_LINE])
                 for i in range(0, len(values), WORDS_PER_LINE)] or [[]]

    payload = b""
    if mask is not None:
        payload += header_line(mask, size=(len(lines) + 1) * BYTE_LANES)

    sent = []
    for line in lines:
        payload += pack_line(line)
        sent += line + [0] * (WORDS_PER_LINE - len(line))

    return payload, sent


def reference_response(sent, mask, top_k_num):
    """What the response beat should hold for the values the slot was given."""
    ranked = sorted(sent, reverse=True)[:top_k_num]
    ranked += [0] * (top_k_num - len(ranked))
    return ([v if (mask >> i) & 1 else 0 for i, v in enumerate(ranked)]
            + [0] * (WORDS_PER_LINE - top_k_num))


def sideband(value):
    """cocotbext-axi collapses a sideband signal to a scalar when uniform."""
    if isinstance(value, (list, tuple)):
        assert len(set(value)) == 1, f"sideband varies across the frame: {value}"
        return value[0]
    return value


def dut_top_k_num(dut):
    try:
        return int(dut.TOP_K_NUM.value)
    except AttributeError:
        return int(os.environ.get("PARAM_TOP_K_NUM", WORDS_PER_LINE))


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
        dut.s_axis_tstrb.setimmediatevalue(2**BYTE_LANES - 1)

        self.top_k_num = dut_top_k_num(dut)
        self.log.info("TOP_K_NUM = %d", self.top_k_num)

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

    async def send_request(self, values, mask=None, **frame_kwargs):
        payload, sent = build_request(values, mask)
        await self.source.send(AxiStreamFrame(payload, **frame_kwargs))
        return sent

    async def recv_response(self):
        frame = await with_timeout(self.sink.recv(), RESPONSE_TIMEOUT_NS, "ns")
        assert len(frame.tdata) == BYTE_LANES, "the response must be a single beat"
        return frame

    def check(self, frame, sent, mask=MASK_ALL):
        got = unpack_line(frame.tdata)
        want = reference_response(sent, mask, self.top_k_num)
        assert got == want, f"\n got  {got}\n want {want}"

    async def run_request(self, values, mask=None, **frame_kwargs):
        sent = await self.send_request(values, mask, **frame_kwargs)
        frame = await self.recv_response()
        self.check(frame, sent, MASK_ALL if mask is None else mask)
        return frame


async def wait_cycles(dut, count):
    for _ in range(count):
        await RisingEdge(dut.clk)


def cycle_pause():
    return itertools.cycle([1, 1, 1, 0])


def random_values(count, spread=VALUE_MAX):
    return [random.randrange(spread + 1) for _ in range(count)]


# ------------------------------------------------------------------- tests

async def run_test_single_line(dut, idle_inserter=None, backpressure_inserter=None):
    """One header plus one data line, against a reference sort."""
    tb = TB(dut)
    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await tb.run_request(random_values(WORDS_PER_LINE), mask=MASK_ALL)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_multi_line(dut, line_count=2, idle_inserter=None, backpressure_inserter=None):
    """A request spread over several data lines -- more values than K."""
    tb = TB(dut)
    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    await tb.run_request(random_values(line_count * WORDS_PER_LINE), mask=MASK_ALL)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_no_header(dut):
    """Without a header line the mask defaults to all-ones and no beat is eaten."""
    tb = TB(dut)
    await tb.reset()

    values = random_values(2 * WORDS_PER_LINE)
    frame = await tb.run_request(values, mask=None)

    assert unpack_line(frame.tdata)[0] == max(values)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_header_only(dut):
    """A header carrying tlast is a complete request: an all-zero response."""
    tb = TB(dut)
    await tb.reset()

    frame = await tb.run_request(None, mask=MASK_ALL)
    assert unpack_line(frame.tdata) == [0] * WORDS_PER_LINE

    # ...and the slot is left ready for a real request.
    await tb.run_request(random_values(WORDS_PER_LINE), mask=MASK_ALL)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_mask(dut, mask=MASK_ALL):
    """The mask gates result words; a thermometer mask returns the low K."""
    tb = TB(dut)
    await tb.reset()

    values = [(i + 1) * 100 for i in range(WORDS_PER_LINE)]
    random.shuffle(values)
    frame = await tb.run_request(values, mask=mask)

    words = unpack_line(frame.tdata)
    for i in range(WORDS_PER_LINE):
        if i >= tb.top_k_num or not (mask >> i) & 1:
            assert words[i] == 0, f"word {i} not gated off by mask {mask:#06x}"

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_unsigned_compare(dut):
    """Values straddling 2**31 must rank as unsigned."""
    tb = TB(dut)
    await tb.reset()

    values = [0x7fffffff, 0xffffffff, 0x00000001, 0x80000000,
              0x00000000, 0xfffffffe, 0x80000001, 0x7ffffffe]
    values += [0] * (WORDS_PER_LINE - len(values))
    frame = await tb.run_request(values, mask=MASK_ALL)

    assert unpack_line(frame.tdata)[0] == 0xffffffff

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_duplicates_and_zeros(dut):
    """Ties must occupy their own slots and payload zeros must not be dropped."""
    tb = TB(dut)
    await tb.reset()

    def expect(ranked):
        return (ranked + [0] * WORDS_PER_LINE)[:tb.top_k_num]

    # every value identical except one outlier: the ties fill the rest of the
    # array rather than collapsing into one slot
    values = [7] * WORDS_PER_LINE
    values[5] = 42
    frame = await tb.run_request(values, mask=MASK_ALL)
    assert unpack_line(frame.tdata)[:tb.top_k_num] == expect([42] + [7] * (WORDS_PER_LINE - 1))

    # a line that is mostly zeros: the zeros are values, not padding to drop
    values = [0] * WORDS_PER_LINE
    values[0], values[1] = 9, 4
    frame = await tb.run_request(values, mask=MASK_ALL)
    assert unpack_line(frame.tdata)[:tb.top_k_num] == expect([9, 4])

    # two full lines of the same value, so every slot ties
    frame = await tb.run_request([123] * (2 * WORDS_PER_LINE), mask=MASK_ALL)
    assert unpack_line(frame.tdata)[:tb.top_k_num] == expect([123] * WORDS_PER_LINE)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_back_to_back(dut, backpressure_inserter=None):
    """State must not leak between requests: the array clears, the mask resets."""
    tb = TB(dut)
    await tb.reset()

    tb.set_backpressure_generator(backpressure_inserter)

    big = [0xf0000000 + i for i in range(WORDS_PER_LINE)]
    small = [i + 1 for i in range(WORDS_PER_LINE)]

    # a masked request, then an unmasked one that must see neither the old
    # mask nor the old (much larger) values
    sent_a = await tb.send_request(big, mask=0x0003)
    sent_b = await tb.send_request(small, mask=None)

    frame_a = await tb.recv_response()
    frame_b = await tb.recv_response()

    tb.check(frame_a, sent_a, 0x0003)
    tb.check(frame_b, sent_b, MASK_ALL)
    assert max(unpack_line(frame_b.tdata)) == max(small)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_sideband(dut):
    """tid/tdest/tuser come from the first beat of the request."""
    tb = TB(dut)
    await tb.reset()

    id_count = 2**len(tb.source.bus.tid)
    dest_count = 2**len(tb.source.bus.tdest)

    for tid, tdest, tuser in [(1, 1, 0), (id_count - 1, dest_count - 1, 1), (0, 0, 0)]:
        payload, sent = build_request(random_values(2 * WORDS_PER_LINE), mask=MASK_ALL)
        beats = len(payload) // BYTE_LANES

        # hold the intended sideband on the first beat only -- every later
        # beat carries something else, which the slot must ignore
        other = ((tid + 1) % id_count, (tdest + 1) % dest_count, tuser ^ 1)
        await tb.source.send(AxiStreamFrame(
            payload,
            tid=[tid] * BYTE_LANES + [other[0]] * BYTE_LANES * (beats - 1),
            tdest=[tdest] * BYTE_LANES + [other[1]] * BYTE_LANES * (beats - 1),
            tuser=[tuser] * BYTE_LANES + [other[2]] * BYTE_LANES * (beats - 1),
        ))

        frame = await tb.recv_response()
        tb.check(frame, sent, MASK_ALL)

        assert sideband(frame.tid) == tid
        assert sideband(frame.tdest) == tdest
        assert sideband(frame.tuser) == tuser

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_response_held(dut):
    """
    The response is held stable until it is accepted, and the slot refuses new
    input for as long as it is outstanding.
    """
    tb = TB(dut)

    # cocotbext-axi's sink samples `pause` at the top of its driver loop and
    # the setter wakes a parked driver before it stores the new value, so a
    # sink parked on an idle bus can miss the change and leave tready high.
    # Pausing before reset is released means the driver starts out paused.
    tb.sink.pause = True
    await tb.reset()

    sent = await tb.send_request(random_values(WORDS_PER_LINE), mask=MASK_ALL)

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
        assert int(dut.m_axis_tlast.value) == 1
        assert int(dut.s_axis_tready.value) == 0, "input accepted with a response pending"

    tb.sink.pause = False

    frame = await tb.recv_response()
    tb.check(frame, sent, MASK_ALL)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_test_timing(dut):
    """One value per cycle: a data line costs 17 cycles, a header costs one."""
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

    sent = await tb.send_request(random_values(2 * WORDS_PER_LINE), mask=MASK_ALL)
    frame = await tb.recv_response()
    watcher.kill()

    tb.check(frame, sent, MASK_ALL)

    assert len(accepts) == 3, f"expected header + 2 data beats, got {accepts}"
    assert accepts[1] - accepts[0] == 1, "a header beat should not stall the stream"
    assert accepts[2] - accepts[1] == LINE_CYCLES
    assert resp_cycle - accepts[2] == LINE_CYCLES

    await wait_cycles(dut, 2)


async def run_test_reset_mid_request(dut):
    """A reset part way through a request leaves no residue behind."""
    tb = TB(dut)
    await tb.reset()

    await tb.send_request([VALUE_MAX] * (8 * WORDS_PER_LINE), mask=0x0001)
    await wait_cycles(dut, LINE_CYCLES * 2)

    await tb.reset()
    # reset drops the frame in flight but leaves the driver queues alone
    tb.source.clear()
    tb.sink.clear()

    assert int(dut.m_axis_tvalid.value) == 0
    assert tb.sink.empty()

    values = random_values(WORDS_PER_LINE, spread=0xffff)
    frame = await tb.run_request(values, mask=None)
    assert unpack_line(frame.tdata)[0] == max(values)

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


async def run_stress_test(dut, idle_inserter=None, backpressure_inserter=None):
    """Randomised requests, masks and sideband, checked against the model."""
    tb = TB(dut)
    await tb.reset()

    tb.set_idle_generator(idle_inserter)
    tb.set_backpressure_generator(backpressure_inserter)

    id_count = 2**len(tb.source.bus.tid)
    dest_count = 2**len(tb.source.bus.tdest)

    pending = []

    for _ in range(64):
        lines = random.randint(1, 4)
        # a narrow spread every so often, to force ties in the sorted array
        spread = random.choice([VALUE_MAX, VALUE_MAX, 0xff, 7])
        values = random_values(lines * WORDS_PER_LINE, spread)
        mask = random.choice([None, MASK_ALL, random.randrange(0x10000)])
        tid = random.randrange(id_count)
        tdest = random.randrange(dest_count)

        sent = await tb.send_request(values, mask, tid=tid, tdest=tdest)
        pending.append((sent, MASK_ALL if mask is None else mask, tid, tdest))

    for sent, mask, tid, tdest in pending:
        frame = await tb.recv_response()
        tb.check(frame, sent, mask)
        assert sideband(frame.tid) == tid
        assert sideband(frame.tdest) == tdest

    assert tb.sink.empty()
    await wait_cycles(dut, 2)


if getattr(cocotb, 'top', None) is not None:

    factory = TestFactory(run_test_single_line)
    factory.add_option("idle_inserter", [None, cycle_pause])
    factory.add_option("backpressure_inserter", [None, cycle_pause])
    factory.generate_tests()

    factory = TestFactory(run_test_multi_line)
    factory.add_option("line_count", [1, 2, 5])
    factory.add_option("idle_inserter", [None, cycle_pause])
    factory.add_option("backpressure_inserter", [None, cycle_pause])
    factory.generate_tests()

    factory = TestFactory(run_test_mask)
    factory.add_option("mask", [0x0000, 0x0001, 0x0003, 0x0005, 0x00ff, 0xff00, 0xaaaa, 0xffff])
    factory.generate_tests()

    factory = TestFactory(run_test_back_to_back)
    factory.add_option("backpressure_inserter", [None, cycle_pause])
    factory.generate_tests()

    for test in [
                run_test_no_header,
                run_test_header_only,
                run_test_unsigned_compare,
                run_test_duplicates_and_zeros,
                run_test_sideband,
                run_test_response_held,
                run_test_timing,
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


@pytest.mark.parametrize("top_k_num", [1, 4, 8, 16])
def test_top_k(request, top_k_num):
    dut = "top_k"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [os.path.join(rtl_dir, f"{dut}.v")]

    parameters = {'TOP_K_NUM': top_k_num}

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
        extra_args=["--sv", "-Wno-WIDTHEXPAND", "-Wno-WIDTHTRUNC"],
    )
