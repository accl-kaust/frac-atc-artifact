#!/usr/bin/env python

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, with_timeout
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


async def capture_first_burst_rready(dut, arlen):
    while True:
        await RisingEdge(dut.clk)
        if int(dut.m_axi_arvalid.value) and int(dut.m_axi_arready.value) and int(dut.m_axi_arlen.value) == arlen:
            break

    samples = []
    while True:
        await RisingEdge(dut.clk)
        if int(dut.m_axi_rvalid.value):
            samples.append(int(dut.m_axi_rready.value))
            if int(dut.m_axi_rready.value) and int(dut.m_axi_rlast.value):
                return samples


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
async def test_reconf_icap_uses_max_burst_then_tail_read(dut):
    tb = TB(dut)
    await tb.reset()

    addr = 0x9000
    payload = bytes(idx & 0xFF for idx in range(17 * 32))
    tb.axi_ram.write(addr, payload)

    ar_task = cocotb.start_soon(capture_read_ar_events(dut, 2))
    rready_task = cocotb.start_soon(capture_first_burst_rready(dut, 15))
    await tb.send_frame(pack_command(OP_RECONF_ICAP, addr, len(payload)))
    icap_frame = await tb.recv_icap_frame()
    ar_events = await with_timeout(ar_task, 5, "us")
    rready_samples = await with_timeout(rready_task, 5, "us")
    await tb.pulse_pr_done()
    response = await tb.recv_response()

    assert [arlen for arlen, _ in ar_events] == [15, 0]
    assert ar_events[1][1] < icap_frame.sim_time_end
    assert len(rready_samples) == 16
    assert all(rready_samples)
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
