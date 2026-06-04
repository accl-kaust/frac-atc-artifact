#!/usr/bin/env python

import os
from dataclasses import dataclass

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from cocotbext.axi import AxiBus, AxiRam, AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource


BYTE_LANES = 64
RECONF_APP = 0x00AB
OP_READ_HBM = 2


def int_to_le_bytes(value, byte_count):
    return int(value).to_bytes(byte_count, "little")


def frame_to_int(frame):
    return int.from_bytes(bytes(frame.tdata), "little")


def assert_keep_all(frame, byte_count):
    assert frame.tkeep is None or frame.tkeep == [1] * byte_count


def pack_reconf_command(opcode, addr, size, slot_id=0):
    payload = bytearray(BYTE_LANES)
    payload[0] = opcode
    payload[1] = slot_id
    payload[8:16] = int(addr).to_bytes(8, "little")
    payload[16:24] = int(size).to_bytes(8, "little")
    return bytes(payload)


@dataclass
class TcpNotification:
    length: int
    conn_id: int

    def pack(self) -> int:
        return ((self.length & 0xffff) << 16) | (self.conn_id & 0xffff)

    def to_bytes(self) -> bytes:
        return int_to_le_bytes(self.pack(), 11)


@dataclass
class RequestHeader:
    total_size: int
    workload_id: int
    top_config: int = 0xffff

    def to_bytes(self) -> bytes:
        return (
            bytes([0xff] * 56)
            + self.total_size.to_bytes(4, "little")
            + self.top_config.to_bytes(2, "little")
            + self.workload_id.to_bytes(2, "little")
        )


@dataclass
class SinglePacketRequest:
    length: int = BYTE_LANES
    conn_id: int = 1
    workload_id: int = 0

    @property
    def notification(self) -> TcpNotification:
        return TcpNotification(length=self.length, conn_id=self.conn_id)

    @property
    def header(self) -> RequestHeader:
        return RequestHeader(total_size=self.length, workload_id=self.workload_id)

    @property
    def metadata(self) -> int:
        return self.notification.pack()

    @property
    def payload(self) -> bytes:
        return self.header.to_bytes()


@dataclass
class MultiPacketRequest:
    packet_lengths: tuple
    conn_id: int = 1
    workload_id: int = 0

    @property
    def total_size(self) -> int:
        return sum(self.packet_lengths)

    @property
    def notifications(self):
        return [TcpNotification(length=length, conn_id=self.conn_id) for length in self.packet_lengths]

    @property
    def payloads(self):
        header = RequestHeader(total_size=self.total_size, workload_id=self.workload_id).to_bytes()
        return [header] + [bytes([idx] * length) for idx, length in enumerate(self.packet_lengths[1:], start=1)]


class TB:
    def __init__(self, dut):
        self.dut = dut

        cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())

        self.notifications_source = AxiStreamSource(
            AxiStreamBus.from_prefix(dut, "s_axis_notifications"), dut.clk, dut.rst
        )
        self.rx_data_source = AxiStreamSource(
            AxiStreamBus.from_prefix(dut, "s_axis_rx_data"), dut.clk, dut.rst
        )
        self.tx_status_source = AxiStreamSource(
            AxiStreamBus.from_prefix(dut, "s_axis_tx_status"), dut.clk, dut.rst
        )

        self.read_package_sink = AxiStreamSink(
            AxiStreamBus.from_prefix(dut, "m_axis_read_package"), dut.clk, dut.rst
        )
        self.tx_metadata_sink = AxiStreamSink(
            AxiStreamBus.from_prefix(dut, "m_axis_tx_metadata"), dut.clk, dut.rst
        )
        self.tx_data_sink = AxiStreamSink(
            AxiStreamBus.from_prefix(dut, "m_axis_tx_data"), dut.clk, dut.rst
        )
        self.axi_ram = AxiRam(AxiBus.from_prefix(dut, "m_axi"), dut.clk, dut.rst, size=2**20)

    def init_static_inputs(self):
        dut = self.dut

        dut.rst.setimmediatevalue(1)
        dut.m_axis_open_connection_tready.setimmediatevalue(1)
        dut.s_axis_open_status_tvalid.setimmediatevalue(0)
        dut.s_axis_open_status_tdata.setimmediatevalue(0)
        dut.m_axis_close_connection_tready.setimmediatevalue(1)
        dut.m_axis_listen_port_tready.setimmediatevalue(1)
        dut.s_axis_listen_port_status_tvalid.setimmediatevalue(0)
        dut.s_axis_listen_port_status_tdata.setimmediatevalue(0)
        dut.s_axis_rx_metadata_tvalid.setimmediatevalue(0)
        dut.s_axis_rx_metadata_tdata.setimmediatevalue(0)
        dut.m_axi_rdata_parity.setimmediatevalue(0)

    async def reset(self):
        self.init_static_inputs()
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        for _ in range(4):
            await RisingEdge(self.dut.clk)

    async def send_notification(self, notification: TcpNotification) -> int:
        await self.notifications_source.send(AxiStreamFrame(notification.to_bytes()))
        read_cmd = await self.read_package_sink.recv()
        return frame_to_int(read_cmd)

    async def send_rx_payload(self, payload: bytes):
        await self.rx_data_source.send(AxiStreamFrame(payload))

    async def send_tx_status_ok(self):
        await self.tx_status_source.send(AxiStreamFrame(int_to_le_bytes(0, 8)))

    async def recv_response(self):
        metadata_frame = await self.tx_metadata_sink.recv()
        data_frame = await self.tx_data_sink.recv()
        return metadata_frame, data_frame


async def run_single_packet_request(dut, workload_id, expected_payload):
    tb = TB(dut)
    await tb.reset()

    request = SinglePacketRequest(conn_id=0x1234, workload_id=workload_id)

    read_cmd = await tb.send_notification(request.notification)
    assert read_cmd == request.metadata

    await tb.send_rx_payload(request.payload)
    await tb.send_tx_status_ok()

    metadata_frame, data_frame = await tb.recv_response()

    assert frame_to_int(metadata_frame) == request.metadata
    assert bytes(data_frame.tdata) == expected_payload
    assert_keep_all(data_frame, BYTE_LANES)


async def run_multi_packet_request(dut, workload_id, expected_payload):
    tb = TB(dut)
    await tb.reset()

    request = MultiPacketRequest(packet_lengths=(BYTE_LANES, BYTE_LANES), conn_id=0x2345, workload_id=workload_id)

    for notification, payload in zip(request.notifications, request.payloads):
        read_cmd = await tb.send_notification(notification)
        assert read_cmd == notification.pack()
        await tb.send_rx_payload(payload)

    await tb.send_tx_status_ok()

    metadata_frame, data_frame = await tb.recv_response()

    assert frame_to_int(metadata_frame) == request.notifications[-1].pack()
    assert bytes(data_frame.tdata) == expected_payload
    assert_keep_all(data_frame, len(expected_payload))


@cocotb.test()
async def test_single_packet_pattern_app(dut):
    await run_single_packet_request(dut, workload_id=0x0000, expected_payload=bytes([0x01] * BYTE_LANES))


@cocotb.test()
async def test_single_packet_or_app(dut):
    await run_single_packet_request(dut, workload_id=0x0001, expected_payload=bytes([0xff] * BYTE_LANES))


@cocotb.test()
async def test_multi_packet_pattern_app(dut):
    await run_multi_packet_request(dut, workload_id=0x0000, expected_payload=bytes([0x01] * BYTE_LANES))


@cocotb.test()
async def test_reconf_read_hbm_request(dut):
    tb = TB(dut)
    await tb.reset()

    addr = 0x4000
    expected_payload = bytes((0x40 + idx) & 0xFF for idx in range(BYTE_LANES))
    tb.axi_ram.write(addr, expected_payload)

    request_payload = (
        RequestHeader(total_size=2 * BYTE_LANES, workload_id=RECONF_APP).to_bytes()
        + pack_reconf_command(OP_READ_HBM, addr, BYTE_LANES)
    )
    notification = TcpNotification(length=len(request_payload), conn_id=0x3456)

    read_cmd = await tb.send_notification(notification)
    assert read_cmd == notification.pack()

    await tb.send_rx_payload(request_payload)
    await tb.send_tx_status_ok()

    metadata_frame, data_frame = await tb.recv_response()

    assert frame_to_int(metadata_frame) == notification.pack()
    assert bytes(data_frame.tdata) == expected_payload
    assert_keep_all(data_frame, BYTE_LANES)


tests_dir = os.path.dirname(__file__)
rtl_dir = os.path.abspath(os.path.join(tests_dir, "..", "rtl"))
reconf_rtl_dir = os.path.abspath(os.path.join(tests_dir, "..", "..", "reconfctrl", "rtl"))
taxi_rtl_dir = os.path.abspath(os.path.join(tests_dir, "..", "..", "..", "..", "lib", "taxi", "axis", "rtl"))


def test_reassembly(request):
    import cocotb_test.simulator

    verilog_sources = [
        os.path.join(taxi_rtl_dir, "taxi_axis_if.sv"),
        os.path.join(taxi_rtl_dir, "taxi_axis_fifo.sv"),
        os.path.join(rtl_dir, "axis_fifo_taxi.sv"),
        os.path.join(rtl_dir, "axis_data_fifo_replacements.sv"),
        os.path.join(rtl_dir, "axis_register.v"),
        os.path.join(rtl_dir, "axis_pipeline_register.v"),
        os.path.join(rtl_dir, "dispatcher.v"),
        os.path.join(rtl_dir, "dummy_delayed_app.v"),
        os.path.join(rtl_dir, "scheduler.v"),
        os.path.join(reconf_rtl_dir, "reconfctrl.v"),
        os.path.join(rtl_dir, "pkt_logic.v"),
        os.path.join(rtl_dir, "pkt_receiver.v"),
        os.path.join(rtl_dir, "pkt_sender.v"),
        os.path.join(rtl_dir, "tcp_top_loopback.v"),
    ]

    sim_build = os.path.join(tests_dir, "sim_build", request.node.name.replace("[", "-").replace("]", ""))

    cocotb_test.simulator.run(
        simulator="verilator",
        verilog_sources=verilog_sources,
        toplevel="tcp_top_loopback",
        module="test_reassembly",
        sim_build=sim_build,
        extra_args=["--sv", "-Wno-PINMISSING", "-Wno-WIDTHEXPAND", "-Wno-WIDTHTRUNC"],
    )
