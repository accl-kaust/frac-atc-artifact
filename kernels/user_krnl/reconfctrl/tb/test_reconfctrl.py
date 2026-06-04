#!/usr/bin/env python

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from cocotbext.axi import AxiBus, AxiRam, AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource


OP_WRITE_HBM = 1
OP_READ_HBM = 2
OP_RECONF_ICAP = 3
ERR_OK = 0
ERR_ALIGN = 2
BYTE_LANES = 64


def pack_command(opcode, addr, size):
    payload = bytearray(BYTE_LANES)
    payload[0] = opcode
    payload[8:16] = int(addr).to_bytes(8, "little")
    payload[16:24] = int(size).to_bytes(8, "little")
    return bytes(payload)


def assert_keep_all(frame, byte_count):
    assert frame.tkeep is None or frame.tkeep == [1] * byte_count


async def wait_cycles(dut, count):
    for _ in range(count):
        await RisingEdge(dut.clk)


class TB:
    def __init__(self, dut):
        self.dut = dut

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        self.source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
        self.response_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)
        self.icap_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis_icap"), dut.clk, dut.rst)
        self.axi_ram = AxiRam(AxiBus.from_prefix(dut, "m_axi"), dut.clk, dut.rst, size=2**20)

        dut.m_axi_rdata_parity.setimmediatevalue(0)

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
    response = await tb.recv_response()

    assert bytes(icap_frame.tdata) == payload
    assert bytes(response.tdata)[0] == ERR_OK
    assert bytes(response.tdata)[1:] == bytes(BYTE_LANES - 1)
    assert_keep_all(response, BYTE_LANES)


@cocotb.test()
async def test_invalid_unaligned_address_returns_error(dut):
    tb = TB(dut)
    await tb.reset()

    await tb.send_frame(pack_command(OP_READ_HBM, 0x1234, 64))
    response = await tb.recv_response()

    assert bytes(response.tdata)[0] == ERR_ALIGN
    assert_keep_all(response, BYTE_LANES)
