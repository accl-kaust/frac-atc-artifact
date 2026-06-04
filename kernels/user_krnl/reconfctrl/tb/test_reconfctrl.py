#!/usr/bin/env python

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


OP_WRITE_HBM = 1
OP_READ_HBM = 2
OP_RECONF_ICAP = 3
ERR_OK = 0
ERR_ALIGN = 2
BYTE_LANES = 64
AXI_BYTES = 32


def pack_command(opcode, addr, size):
    payload = bytearray(BYTE_LANES)
    payload[0] = opcode
    payload[8:16] = int(addr).to_bytes(8, "little")
    payload[16:24] = int(size).to_bytes(8, "little")
    return bytes(payload)


def bytes_to_int(data):
    return int.from_bytes(bytes(data), "little")


def int_to_bytes(value, size):
    return int(value).to_bytes(size, "little")


async def wait_cycles(dut, count):
    for _ in range(count):
        await RisingEdge(dut.clk)


class AxiMemory:
    def __init__(self, dut, default=0x00):
        self.dut = dut
        self.default = default
        self.mem = {}
        self.write_addrs = []

    def read(self, addr, size):
        return bytes(self.mem.get(addr + idx, self.default) for idx in range(size))

    def write(self, addr, data, strobe):
        for idx, byte in enumerate(data):
            if (strobe >> idx) & 1:
                self.mem[addr + idx] = byte

    async def write_slave(self):
        dut = self.dut
        dut.m_axi_awready.value = 1
        dut.m_axi_wready.value = 1
        dut.m_axi_bid.value = 0
        dut.m_axi_bresp.value = 0
        dut.m_axi_bvalid.value = 0

        while True:
            await RisingEdge(dut.clk)

            if dut.m_axi_bvalid.value and dut.m_axi_bready.value:
                dut.m_axi_bvalid.value = 0

            if dut.m_axi_awvalid.value and dut.m_axi_awready.value:
                self.write_addrs.append(int(dut.m_axi_awaddr.value))

            if dut.m_axi_wvalid.value and dut.m_axi_wready.value:
                assert self.write_addrs, "write data arrived before write address"
                addr = self.write_addrs.pop(0)
                data = int_to_bytes(int(dut.m_axi_wdata.value), AXI_BYTES)
                strobe = int(dut.m_axi_wstrb.value)
                self.write(addr, data, strobe)
                dut.m_axi_bresp.value = 0
                dut.m_axi_bvalid.value = 1

    async def read_slave(self):
        dut = self.dut
        dut.m_axi_arready.value = 1
        dut.m_axi_rid.value = 0
        dut.m_axi_rdata.value = 0
        dut.m_axi_rdata_parity.value = 0
        dut.m_axi_rresp.value = 0
        dut.m_axi_rlast.value = 0
        dut.m_axi_rvalid.value = 0

        while True:
            await RisingEdge(dut.clk)

            if dut.m_axi_rvalid.value and dut.m_axi_rready.value:
                dut.m_axi_rvalid.value = 0
                dut.m_axi_rlast.value = 0

            if dut.m_axi_arvalid.value and dut.m_axi_arready.value and not dut.m_axi_rvalid.value:
                addr = int(dut.m_axi_araddr.value)
                dut.m_axi_rdata.value = bytes_to_int(self.read(addr, AXI_BYTES))
                dut.m_axi_rresp.value = 0
                dut.m_axi_rlast.value = 1
                dut.m_axi_rvalid.value = 1


class TB:
    def __init__(self, dut):
        self.dut = dut
        self.mem = AxiMemory(dut, default=0xAA)

    async def start(self):
        cocotb.start_soon(Clock(self.dut.clk, 4, units="ns").start())
        cocotb.start_soon(self.mem.write_slave())
        cocotb.start_soon(self.mem.read_slave())
        self.init_inputs()
        await self.reset()

    def init_inputs(self):
        dut = self.dut
        dut.rst.setimmediatevalue(1)
        dut.s_axis_tvalid.setimmediatevalue(0)
        dut.s_axis_tdata.setimmediatevalue(0)
        dut.s_axis_tkeep.setimmediatevalue(0)
        dut.s_axis_tlast.setimmediatevalue(0)
        dut.m_axis_tready.setimmediatevalue(0)
        dut.m_axis_icap_tready.setimmediatevalue(0)
        dut.m_axi_awready.setimmediatevalue(0)
        dut.m_axi_wready.setimmediatevalue(0)
        dut.m_axi_bvalid.setimmediatevalue(0)
        dut.m_axi_bresp.setimmediatevalue(0)
        dut.m_axi_bid.setimmediatevalue(0)
        dut.m_axi_arready.setimmediatevalue(0)
        dut.m_axi_rvalid.setimmediatevalue(0)
        dut.m_axi_rdata.setimmediatevalue(0)
        dut.m_axi_rdata_parity.setimmediatevalue(0)
        dut.m_axi_rresp.setimmediatevalue(0)
        dut.m_axi_rlast.setimmediatevalue(0)
        dut.m_axi_rid.setimmediatevalue(0)

    async def reset(self):
        self.dut.rst.value = 1
        await wait_cycles(self.dut, 5)
        self.dut.rst.value = 0
        await wait_cycles(self.dut, 2)

    async def send_axis(self, payload, last=1):
        assert len(payload) <= BYTE_LANES
        padded = bytes(payload) + bytes(BYTE_LANES - len(payload))
        dut = self.dut
        dut.s_axis_tdata.value = bytes_to_int(padded)
        dut.s_axis_tkeep.value = (1 << BYTE_LANES) - 1
        dut.s_axis_tlast.value = last
        dut.s_axis_tvalid.value = 1

        for _ in range(200):
            await RisingEdge(dut.clk)
            if dut.s_axis_tready.value:
                dut.s_axis_tvalid.value = 0
                dut.s_axis_tlast.value = 0
                return

        raise AssertionError("timeout waiting for input ready")

    async def recv_response(self):
        dut = self.dut
        prev_valid = 0
        prev_data = bytes(BYTE_LANES)
        prev_keep = 0
        prev_last = 0

        dut.m_axis_tready.value = 1

        for _ in range(1000):
            await RisingEdge(dut.clk)
            if prev_valid:
                dut.m_axis_tready.value = 0
                return prev_data, prev_keep, prev_last

            prev_valid = int(dut.m_axis_tvalid.value)
            prev_data = int_to_bytes(int(dut.m_axis_tdata.value), BYTE_LANES)
            prev_keep = int(dut.m_axis_tkeep.value)
            prev_last = int(dut.m_axis_tlast.value)

        raise AssertionError("timeout waiting for response")

    async def recv_icap_words(self, count):
        dut = self.dut
        words = []
        lasts = []
        prev_valid = 0
        prev_data = 0
        prev_last = 0

        dut.m_axis_icap_tready.value = 1

        for _ in range(5000):
            await RisingEdge(dut.clk)
            if prev_valid:
                words.append(prev_data)
                lasts.append(prev_last)
                if len(words) == count:
                    dut.m_axis_icap_tready.value = 0
                    return words, lasts

            prev_valid = int(dut.m_axis_icap_tvalid.value)
            prev_data = int(dut.m_axis_icap_tdata.value)
            prev_last = int(dut.m_axis_icap_tlast.value)

        raise AssertionError("timeout waiting for ICAP words")


@cocotb.test()
async def test_write_hbm_status_and_strobes(dut):
    tb = TB(dut)
    await tb.start()

    addr = 0x1000
    payload = bytes(range(96))
    await tb.send_axis(pack_command(OP_WRITE_HBM, addr, len(payload)))
    await tb.send_axis(payload[:64])
    await tb.send_axis(payload[64:])

    response, keep, last = await tb.recv_response()

    assert response[0] == ERR_OK
    assert response[1:] == bytes(BYTE_LANES - 1)
    assert keep == (1 << BYTE_LANES) - 1
    assert last == 1
    assert tb.mem.read(addr, len(payload)) == payload
    assert tb.mem.read(addr + len(payload), 32) == bytes([0xAA] * 32)


@cocotb.test()
async def test_read_hbm_64B_response(dut):
    tb = TB(dut)
    await tb.start()

    addr = 0x2000
    payload = bytes((0x80 + idx) & 0xFF for idx in range(BYTE_LANES))
    tb.mem.write(addr, payload[:32], (1 << 32) - 1)
    tb.mem.write(addr + 32, payload[32:], (1 << 32) - 1)

    await tb.send_axis(pack_command(OP_READ_HBM, addr, len(payload)))
    response, keep, last = await tb.recv_response()

    assert response == payload
    assert keep == (1 << BYTE_LANES) - 1
    assert last == 1


@cocotb.test()
async def test_reconf_icap_dma_streams_all_words(dut):
    tb = TB(dut)
    await tb.start()

    addr = 0x3000
    words = [0xC0000000 + idx for idx in range(10)]
    payload = b"".join(word.to_bytes(4, "little") for word in words)
    tb.mem.write(addr, payload[:32], (1 << 32) - 1)
    tb.mem.write(addr + 32, payload[32:] + bytes(24), (1 << 8) - 1)

    await tb.send_axis(pack_command(OP_RECONF_ICAP, addr, len(payload)))
    observed_words, observed_lasts = await tb.recv_icap_words(len(words))
    response, keep, last = await tb.recv_response()

    assert observed_words == words
    assert observed_lasts[:-1] == [0] * (len(words) - 1)
    assert observed_lasts[-1] == 1
    assert response[0] == ERR_OK
    assert response[1:] == bytes(BYTE_LANES - 1)
    assert keep == (1 << BYTE_LANES) - 1
    assert last == 1


@cocotb.test()
async def test_invalid_unaligned_address_returns_error(dut):
    tb = TB(dut)
    await tb.start()

    await tb.send_axis(pack_command(OP_READ_HBM, 0x1234, 64))
    response, keep, last = await tb.recv_response()

    assert response[0] == ERR_ALIGN
    assert keep == (1 << BYTE_LANES) - 1
    assert last == 1
