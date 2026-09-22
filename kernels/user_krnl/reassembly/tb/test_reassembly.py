#!/usr/bin/env python

import os
from dataclasses import dataclass

import cocotb
from cocotb.clock import Clock
from cocotb.result import SimTimeoutError
from cocotb.triggers import RisingEdge, with_timeout

from cocotbext.axi import AxiBus, AxiRam, AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource


BYTE_LANES = 64
MAX_PACKET_BYTES = 512
RECONF_APP = 0x00AB
OP_WRITE_HBM = 1
OP_READ_HBM = 2
REQ_FLAG_FIRST = 0x1
REQ_FLAG_LAST = 0x2
REQ_FLAG_SINGLE = REQ_FLAG_FIRST | REQ_FLAG_LAST


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


def response_metadata(conn_id, byte_count):
    """
    The TCP tx metadata pkt_sender hands the stack, {length, session}, read
    from the response beat that carries tlast.  The scheduler gives the slot
    {request size, session} as meta (the header's packet_size, not the length
    of one TCP packet), so the echo forwards it unchanged and the response is
    reported as long as the whole request, however many TCP packets it came in.
    """
    return TcpNotification(length=byte_count, conn_id=conn_id).pack()


def reconf_response_metadata(conn_id):
    return response_metadata(conn_id, BYTE_LANES)


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
    request_flags: int = REQ_FLAG_SINGLE

    def to_bytes(self) -> bytes:
        config = (self.top_config & ~0x3) | (self.request_flags & 0x3)
        return (
            bytes([0xff] * 56)
            + self.total_size.to_bytes(4, "little")
            + config.to_bytes(2, "little")
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
        return RequestHeader(total_size=self.length, workload_id=self.workload_id, request_flags=REQ_FLAG_SINGLE)

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
        header = RequestHeader(total_size=self.total_size, workload_id=self.workload_id, request_flags=REQ_FLAG_FIRST).to_bytes()
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
        await with_timeout(self.notifications_source.send(AxiStreamFrame(notification.to_bytes())), 2, "us")
        read_cmd = await with_timeout(self.read_package_sink.recv(), 2, "us")
        return frame_to_int(read_cmd)

    async def expect_notification_rejected(self, notification: TcpNotification):
        await self.notifications_source.send(AxiStreamFrame(notification.to_bytes()))
        try:
            await with_timeout(self.read_package_sink.recv(), 200, "ns")
        except SimTimeoutError:
            return
        raise AssertionError("invalid notification produced a read command")

    async def send_rx_payload(self, payload: bytes):
        await with_timeout(self.rx_data_source.send(AxiStreamFrame(payload)), 2, "us")

    async def send_tx_status_ok(self):
        await with_timeout(self.tx_status_source.send(AxiStreamFrame(int_to_le_bytes(0, 8))), 2, "us")

    async def recv_response(self):
        metadata_frame = await self.tx_metadata_sink.recv()
        data_frame = await self.tx_data_sink.recv()
        return metadata_frame, data_frame

    async def expect_no_response(self, timeout=500, units="ns"):
        try:
            metadata_frame = await with_timeout(self.tx_metadata_sink.recv(), timeout, units)
        except SimTimeoutError:
            return
        raise AssertionError(f"unexpected extra response metadata 0x{frame_to_int(metadata_frame):08x}")


def echo_response(payloads) -> bytes:
    """C00 (apps/pattern_slot): every request beat is echoed, payload and meta
    unchanged; the meta names the request size, which is the response size."""
    return b"".join(payloads)


def or_response(payloads) -> bytes:
    """C01 (apps/or_slot): every request beat comes back with its payload OR-ed
    with all ones, meta unchanged."""
    return bytes([0xff]) * sum(len(payload) for payload in payloads)


async def run_single_packet_request(dut, workload_id, expected):
    tb = TB(dut)
    await tb.reset()

    request = SinglePacketRequest(conn_id=0x1234, workload_id=workload_id)
    expected_payload = expected([request.payload])

    read_cmd = await tb.send_notification(request.notification)
    assert read_cmd == request.metadata

    await tb.send_rx_payload(request.payload)
    await tb.send_tx_status_ok()

    metadata_frame, data_frame = await tb.recv_response()

    assert bytes(data_frame.tdata) == expected_payload
    assert_keep_all(data_frame, BYTE_LANES)
    assert frame_to_int(metadata_frame) == response_metadata(request.conn_id, len(expected_payload))


async def run_multi_packet_request(dut, workload_id, expected):
    tb = TB(dut)
    await tb.reset()

    request = MultiPacketRequest(packet_lengths=(BYTE_LANES, BYTE_LANES), conn_id=0x2345, workload_id=workload_id)
    expected_payload = expected(request.payloads)

    for notification, payload in zip(request.notifications, request.payloads):
        read_cmd = await tb.send_notification(notification)
        assert read_cmd == notification.pack()
        await tb.send_rx_payload(payload)

    await tb.send_tx_status_ok()

    metadata_frame, data_frame = await with_timeout(tb.recv_response(), 20, "us")

    # two TCP packets of 64 bytes: the meta names the 128-byte request, not the last packet
    assert frame_to_int(metadata_frame) == response_metadata(request.conn_id, len(expected_payload))
    assert bytes(data_frame.tdata) == expected_payload
    assert_keep_all(data_frame, len(expected_payload))


async def run_single_tcp_packet_multi_beat_app_request(dut, workload_id, expected):
    tb = TB(dut)
    await tb.reset()

    total_size = 2 * BYTE_LANES
    notification = TcpNotification(length=total_size, conn_id=0x2456)
    payload = RequestHeader(total_size=total_size, workload_id=workload_id).to_bytes() + bytes([0x5a] * BYTE_LANES)
    expected_payload = expected([payload])

    read_cmd = await tb.send_notification(notification)
    assert read_cmd == notification.pack()

    await tb.send_rx_payload(payload)
    await tb.send_tx_status_ok()

    metadata_frame, data_frame = await with_timeout(tb.recv_response(), 20, "us")

    assert frame_to_int(metadata_frame) == response_metadata(notification.conn_id, len(expected_payload))
    assert bytes(data_frame.tdata) == expected_payload
    assert_keep_all(data_frame, len(expected_payload))


@cocotb.test()
async def test_header_flags_replace_ff_prefix_for_single_packet(dut):
    tb = TB(dut)
    await tb.reset()

    header = bytearray(RequestHeader(total_size=BYTE_LANES, workload_id=0x0000).to_bytes())
    header[0:56] = bytes((idx + 1) & 0xFF for idx in range(56))
    notification = TcpNotification(length=BYTE_LANES, conn_id=0x2468)

    read_cmd = await tb.send_notification(notification)
    assert read_cmd == notification.pack()

    await tb.send_rx_payload(bytes(header))
    await tb.send_tx_status_ok()

    metadata_frame, data_frame = await with_timeout(tb.recv_response(), 20, "us")

    assert frame_to_int(metadata_frame) == response_metadata(notification.conn_id, BYTE_LANES)
    assert bytes(data_frame.tdata) == echo_response([bytes(header)])
    assert_keep_all(data_frame, BYTE_LANES)


@cocotb.test()
async def test_multi_packet_payload_ff_and_flag_bits_are_not_header(dut):
    tb = TB(dut)
    await tb.reset()

    conn_id = 0x2470
    first = RequestHeader(total_size=2 * BYTE_LANES, workload_id=0x0000, request_flags=REQ_FLAG_FIRST).to_bytes()
    continuation = bytes([0xff] * BYTE_LANES)
    notifications = [
        TcpNotification(length=BYTE_LANES, conn_id=conn_id),
        TcpNotification(length=BYTE_LANES, conn_id=conn_id),
    ]

    for notification, payload in zip(notifications, [first, continuation]):
        read_cmd = await tb.send_notification(notification)
        assert read_cmd == notification.pack()
        await tb.send_rx_payload(payload)

    await tb.send_tx_status_ok()

    metadata_frame, data_frame = await with_timeout(tb.recv_response(), 20, "us")

    assert frame_to_int(metadata_frame) == response_metadata(conn_id, 2 * BYTE_LANES)
    assert bytes(data_frame.tdata) == echo_response([first, continuation])
    assert_keep_all(data_frame, 2 * BYTE_LANES)
    await tb.expect_no_response()


async def run_repeated_multi_packet_requests(dut, workload_id, line_count, request_count, expected):
    tb = TB(dut)
    await tb.reset()

    for request_idx in range(request_count):
        request = MultiPacketRequest(
            packet_lengths=tuple([BYTE_LANES] * line_count),
            conn_id=0x5000 + request_idx,
            workload_id=workload_id,
        )

        for notification, payload in zip(request.notifications, request.payloads):
            read_cmd = await tb.send_notification(notification)
            assert read_cmd == notification.pack()
            await tb.send_rx_payload(payload)

        await tb.send_tx_status_ok()

        metadata_frame, data_frame = await with_timeout(tb.recv_response(), 20, "us")

        expected_payload = expected(request.payloads)
        assert frame_to_int(metadata_frame) == response_metadata(request.conn_id, len(expected_payload))
        assert bytes(data_frame.tdata) == expected_payload
        assert_keep_all(data_frame, len(expected_payload))


async def run_back_to_back_three_line_requests(dut, workload_id, expected):
    tb = TB(dut)
    await tb.reset()

    requests = [
        MultiPacketRequest(packet_lengths=(BYTE_LANES, BYTE_LANES, BYTE_LANES), conn_id=0x5000, workload_id=workload_id),
        MultiPacketRequest(packet_lengths=(BYTE_LANES, BYTE_LANES, BYTE_LANES), conn_id=0x5000, workload_id=workload_id),
    ]

    for request in requests:
        for notification, payload in zip(request.notifications, request.payloads):
            read_cmd = await tb.send_notification(notification)
            assert read_cmd == notification.pack()
            await tb.send_rx_payload(payload)

    await tb.send_tx_status_ok()
    await tb.send_tx_status_ok()

    for request in requests:
        metadata_frame, data_frame = await with_timeout(tb.recv_response(), 20, "us")

        expected_payload = expected(request.payloads)
        assert frame_to_int(metadata_frame) == response_metadata(request.conn_id, len(expected_payload))
        assert bytes(data_frame.tdata) == expected_payload
        assert_keep_all(data_frame, len(expected_payload))


@cocotb.test()
async def test_single_packet_echo_app(dut):
    await run_single_packet_request(dut, workload_id=0x0000, expected=echo_response)


@cocotb.test()
async def test_single_packet_or_app(dut):
    await run_single_packet_request(dut, workload_id=0x0001, expected=or_response)


@cocotb.test()
async def test_multi_packet_echo_app(dut):
    await run_multi_packet_request(dut, workload_id=0x0000, expected=echo_response)


@cocotb.test()
async def test_single_tcp_packet_multi_beat_echo_app(dut):
    await run_single_tcp_packet_multi_beat_app_request(dut, workload_id=0x0000, expected=echo_response)


@cocotb.test()
async def test_repeated_three_line_echo_app(dut):
    await run_repeated_multi_packet_requests(dut, workload_id=0x0000, line_count=3, request_count=8, expected=echo_response)


@cocotb.test()
async def test_back_to_back_three_line_echo_app(dut):
    await run_back_to_back_three_line_requests(dut, workload_id=0x0000, expected=echo_response)


@cocotb.test()
async def test_repeated_six_line_echo_app(dut):
    await run_repeated_multi_packet_requests(dut, workload_id=0x0000, line_count=6, request_count=8, expected=echo_response)


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

    assert frame_to_int(metadata_frame) == reconf_response_metadata(notification.conn_id)
    assert bytes(data_frame.tdata) == expected_payload
    assert_keep_all(data_frame, BYTE_LANES)


@cocotb.test()
async def test_reconf_write_hbm_uses_command_size(dut):
    tb = TB(dut)
    await tb.reset()

    addr = 0x5000
    write_size = 96
    payload_capacity = 2 * BYTE_LANES
    payload = bytes((0x80 + idx) & 0xFF for idx in range(payload_capacity))
    original = bytes([0xee] * payload_capacity)
    tb.axi_ram.write(addr, original)

    request_payload = (
        RequestHeader(total_size=BYTE_LANES + BYTE_LANES + payload_capacity, workload_id=RECONF_APP).to_bytes()
        + pack_reconf_command(OP_WRITE_HBM, addr, write_size)
        + payload
    )
    notification = TcpNotification(length=len(request_payload), conn_id=0x4567)

    read_cmd = await tb.send_notification(notification)
    assert read_cmd == notification.pack()

    await tb.send_rx_payload(request_payload)
    await tb.send_tx_status_ok()

    metadata_frame, data_frame = await with_timeout(tb.recv_response(), 20, "us")

    assert frame_to_int(metadata_frame) == reconf_response_metadata(notification.conn_id)
    assert bytes(data_frame.tdata) == bytes(BYTE_LANES)
    assert_keep_all(data_frame, BYTE_LANES)
    assert bytes(tb.axi_ram.read(addr, payload_capacity)) == payload[:write_size] + original[write_size:]


@cocotb.test()
async def test_reconf_write_hbm_exact_board_packet_has_one_response(dut):
    tb = TB(dut)
    await tb.reset()

    addr = 0x4000
    payload = bytes((0x40 + idx) & 0xFF for idx in range(BYTE_LANES))
    original = bytes([0xee] * BYTE_LANES)
    tb.axi_ram.write(addr, original)

    request_payload = (
        RequestHeader(total_size=2 * BYTE_LANES, workload_id=RECONF_APP).to_bytes()
        + pack_reconf_command(OP_WRITE_HBM, addr, BYTE_LANES)
        + payload
    )
    notification = TcpNotification(length=len(request_payload), conn_id=0x6c00)

    assert len(request_payload) == 3 * BYTE_LANES
    assert request_payload[56:60] == bytes([0x80, 0x00, 0x00, 0x00])

    read_cmd = await tb.send_notification(notification)
    assert read_cmd == notification.pack()

    await tb.send_rx_payload(request_payload)
    await tb.send_tx_status_ok()

    metadata_frame, data_frame = await with_timeout(tb.recv_response(), 20, "us")

    assert frame_to_int(metadata_frame) == reconf_response_metadata(notification.conn_id)
    assert bytes(data_frame.tdata) == bytes(BYTE_LANES)
    assert_keep_all(data_frame, BYTE_LANES)
    assert bytes(tb.axi_ram.read(addr, BYTE_LANES)) == payload

    await tb.expect_no_response()

    await tb.send_tx_status_ok()
    await tb.expect_no_response()

    await tb.send_tx_status_ok()
    await tb.expect_no_response()


@cocotb.test()
async def test_reconf_write_hbm_payload_ff_prefix_is_not_header(dut):
    tb = TB(dut)
    await tb.reset()

    addr = 0x4800
    payload = bytes([0xff] * 56) + bytes((0x80 + idx) & 0xFF for idx in range(8))
    original = bytes([0xee] * BYTE_LANES)
    tb.axi_ram.write(addr, original)

    request_payload = (
        RequestHeader(total_size=2 * BYTE_LANES, workload_id=RECONF_APP).to_bytes()
        + pack_reconf_command(OP_WRITE_HBM, addr, BYTE_LANES)
        + payload
    )
    notification = TcpNotification(length=len(request_payload), conn_id=0x6d00)

    read_cmd = await tb.send_notification(notification)
    assert read_cmd == notification.pack()

    await tb.send_rx_payload(request_payload)
    await tb.send_tx_status_ok()

    metadata_frame, data_frame = await with_timeout(tb.recv_response(), 20, "us")

    assert frame_to_int(metadata_frame) == reconf_response_metadata(notification.conn_id)
    assert bytes(data_frame.tdata) == bytes(BYTE_LANES)
    assert_keep_all(data_frame, BYTE_LANES)
    assert bytes(tb.axi_ram.read(addr, BYTE_LANES)) == payload

    await tb.expect_no_response()


@cocotb.test()
async def test_reconf_repeated_exact_write_hbm_has_one_response_each(dut):
    tb = TB(dut)
    await tb.reset()

    for req_idx in range(3):
        addr = 0x4000 + req_idx * BYTE_LANES
        payload = bytes((0x40 + req_idx + idx) & 0xFF for idx in range(BYTE_LANES))
        request_payload = (
            RequestHeader(total_size=2 * BYTE_LANES, workload_id=RECONF_APP).to_bytes()
            + pack_reconf_command(OP_WRITE_HBM, addr, BYTE_LANES)
            + payload
        )
        notification = TcpNotification(length=len(request_payload), conn_id=0x6c00 + req_idx)

        read_cmd = await tb.send_notification(notification)
        assert read_cmd == notification.pack()

        await tb.send_rx_payload(request_payload)
        await tb.send_tx_status_ok()

        metadata_frame, data_frame = await with_timeout(tb.recv_response(), 20, "us")

        assert frame_to_int(metadata_frame) == reconf_response_metadata(notification.conn_id)
        assert bytes(data_frame.tdata) == bytes(BYTE_LANES)
        assert_keep_all(data_frame, BYTE_LANES)
        assert bytes(tb.axi_ram.read(addr, BYTE_LANES)) == payload

        await tb.expect_no_response()


@cocotb.test()
async def test_reconf_write_hbm_ignores_transport_padding(dut):
    tb = TB(dut)
    await tb.reset()

    addr = 0x6000
    write_size = BYTE_LANES
    payload_capacity = 2 * BYTE_LANES
    payload = bytes((0x20 + idx) & 0xFF for idx in range(payload_capacity))
    original = bytes([0xee] * payload_capacity)
    tb.axi_ram.write(addr, original)

    request_payload = (
        RequestHeader(total_size=BYTE_LANES + payload_capacity, workload_id=RECONF_APP).to_bytes()
        + pack_reconf_command(OP_WRITE_HBM, addr, write_size)
        + payload
    )
    notification = TcpNotification(length=len(request_payload), conn_id=0x5678)

    read_cmd = await tb.send_notification(notification)
    assert read_cmd == notification.pack()

    await tb.send_rx_payload(request_payload)
    await tb.send_tx_status_ok()

    metadata_frame, data_frame = await with_timeout(tb.recv_response(), 20, "us")

    assert frame_to_int(metadata_frame) == reconf_response_metadata(notification.conn_id)
    assert bytes(data_frame.tdata) == bytes(BYTE_LANES)
    assert_keep_all(data_frame, BYTE_LANES)
    assert bytes(tb.axi_ram.read(addr, payload_capacity)) == payload[:write_size] + original[write_size:]

    await tb.expect_no_response()
    await tb.send_tx_status_ok()
    await tb.expect_no_response()


@cocotb.test()
async def test_reconf_read_hbm_ignores_extra_packet_data(dut):
    tb = TB(dut)
    await tb.reset()

    addr = 0x7000
    expected_payload = bytes((0x60 + idx) & 0xFF for idx in range(BYTE_LANES))
    tb.axi_ram.write(addr, expected_payload)
    extra_payload = bytes((0xa0 + idx) & 0xFF for idx in range(BYTE_LANES))

    request_payload = (
        RequestHeader(total_size=3 * BYTE_LANES, workload_id=RECONF_APP).to_bytes()
        + pack_reconf_command(OP_READ_HBM, addr, BYTE_LANES)
        + extra_payload
    )
    notification = TcpNotification(length=len(request_payload), conn_id=0x6789)

    read_cmd = await tb.send_notification(notification)
    assert read_cmd == notification.pack()

    await tb.send_rx_payload(request_payload)
    await tb.send_tx_status_ok()

    metadata_frame, data_frame = await with_timeout(tb.recv_response(), 20, "us")

    assert frame_to_int(metadata_frame) == reconf_response_metadata(notification.conn_id)
    assert bytes(data_frame.tdata) == expected_payload
    assert_keep_all(data_frame, BYTE_LANES)

    await tb.expect_no_response()
    await tb.send_tx_status_ok()
    await tb.expect_no_response()


@cocotb.test()
async def test_notification_length_limit(dut):
    tb = TB(dut)
    await tb.reset()

    max_notification = TcpNotification(length=MAX_PACKET_BYTES, conn_id=0x4567)
    read_cmd = await tb.send_notification(max_notification)
    assert read_cmd == max_notification.pack()

    await tb.expect_notification_rejected(TcpNotification(length=MAX_PACKET_BYTES + BYTE_LANES, conn_id=0x4567))


tests_dir = os.path.dirname(__file__)
rtl_dir = os.path.abspath(os.path.join(tests_dir, "..", "rtl"))
reconf_rtl_dir = os.path.abspath(os.path.join(tests_dir, "..", "..", "reconfctrl", "rtl"))
taxi_rtl_dir = os.path.abspath(os.path.join(tests_dir, "..", "..", "..", "..", "lib", "taxi", "axis", "rtl"))
taxi_prim_rtl_dir = os.path.abspath(os.path.join(tests_dir, "..", "..", "..", "..", "lib", "taxi", "prim", "rtl"))


def test_reassembly(request):
    import cocotb_test.simulator

    verilog_sources = [
        os.path.join(taxi_rtl_dir, "taxi_axis_if.sv"),
        os.path.join(taxi_rtl_dir, "taxi_axis_fifo.sv"),
        os.path.join(taxi_prim_rtl_dir, "taxi_penc.sv"),
        os.path.join(taxi_prim_rtl_dir, "taxi_arbiter.sv"),
        os.path.join(taxi_rtl_dir, "taxi_axis_register.sv"),
        os.path.join(taxi_rtl_dir, "taxi_axis_switch.sv"),
        os.path.join(rtl_dir, "axis_fifo_taxi.sv"),
        os.path.join(rtl_dir, "axis_data_fifo_replacements.sv"),
        os.path.join(rtl_dir, "axis_register.v"),
        os.path.join(rtl_dir, "axis_pipeline_register.v"),
        os.path.join(rtl_dir, "dispatcher.v"),
        os.path.join(rtl_dir, "scheduler.v"),
        os.path.join(rtl_dir, "slot_tx_axis_switch.sv"),
        os.path.join(reconf_rtl_dir, "axis_dfx_decoupler.sv"),
        os.path.join(tests_dir, "cell_bbx_pattern_sim.sv"),
        os.path.join(reconf_rtl_dir, "reconfctrl.v"),
        os.path.join(reconf_rtl_dir, "icap_ctrl.v"),
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
        extra_args=["--sv", "-DSIMULATION", "-Wno-PINMISSING", "-Wno-WIDTHEXPAND", "-Wno-WIDTHTRUNC"],
    )
