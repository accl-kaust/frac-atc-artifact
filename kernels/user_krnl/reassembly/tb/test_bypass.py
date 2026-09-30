#!/usr/bin/env python
"""
tcp_top_loopback with pkt_receiver wired straight to pkt_sender: no pkt_logic.

Every TCP segment pkt_receiver reads goes back out as its own response, on its
own session, announced with its own length.  Nothing parses a request header,
so a request spread over several segments comes back as several responses --
the same bytes on the connection, in the same order -- and any bytes at all
are echoed.

What pkt_receiver and pkt_sender do on their own is unchanged: a refused
segment is read and thrown away, a close is not read, and a response the stack
will not take whole goes out in pieces, or is dropped with its connection.
The benches that check those, and every echo of a request that arrives in one
segment -- which pkt_logic also answered with one response of the same bytes
-- are imported from the reassembly benches as they are.
"""

import random
from collections import defaultdict

import cocotb
from cocotb.triggers import ClockCycles, with_timeout

from test_reassembly import (
    BYTE_LANES, MAX_PACKET_BYTES, RECONF_APP, REQ_FLAG_FIRST, TB, TOE_MSS, RequestHeader, ToeRxBuffer,
    assert_keep_all, build_echo_request, frame_to_int, response_metadata, segment_request, send_segments,
)
from test_multiclient import ToeTx, cut, make_request

# pkt_receiver and pkt_sender alone, or a request in one segment: unchanged.
from test_reassembly import (  # noqa: F401
    test_close_notification_is_not_read,
    test_header_flags_replace_ff_prefix_for_single_packet,
    test_refused_segments_are_read_and_discarded,
    test_request_cut_at_legacy_mss_leaves_later_requests_intact,
    test_single_packet_echo_app,
    test_single_tcp_packet_multi_beat_echo_app,
)
from test_multiclient import (  # noqa: F401
    test_closed_connection_responses_are_dropped,
    test_four_clients_one_segment_requests,
    test_four_clients_single_and_multi_line_requests,
    test_no_send_window_at_first,
    test_one_client_one_segment_requests,
    test_sixteen_clients_two_requests_in_flight,
    test_small_send_window_splits_responses,
    test_stack_answers_race_the_last_beat,
)


async def expect_echo(tb, conn_id, segment):
    await tb.send_tx_status_ok()
    metadata_frame, data_frame = await with_timeout(tb.recv_response(), 20, "us")
    assert frame_to_int(metadata_frame) == response_metadata(conn_id, len(segment)), (
        f"{len(segment)}B segment: meta {frame_to_int(metadata_frame):#010x}")
    assert bytes(data_frame.tdata) == segment, f"{len(segment)}B segment: {len(data_frame.tdata)}B back"
    assert_keep_all(data_frame, len(segment))
    return bytes(data_frame.tdata)


@cocotb.test()
async def test_each_segment_is_its_own_response(dut):
    """Segments of one line up to TOE_MSS, each echoed whole and announced with its own length."""
    tb = TB(dut)
    await tb.reset()

    conn_id = 0x3100
    for length in (BYTE_LANES, 2 * BYTE_LANES, 1024, TOE_MSS):
        segment = bytes((length + idx) & 0xff for idx in range(length))
        await send_segments(tb, [segment], conn_id)
        await expect_echo(tb, conn_id, segment)
    await tb.expect_no_response()


@cocotb.test()
async def test_request_over_segments_comes_back_segment_by_segment(dut):
    """
    A request spread over segments -- cut at 1024 bytes, or framed as sw/app
    frames it, the header line alone first, which splits even the longest
    request pkt_receiver takes in one segment -- comes back as one response
    per segment, each announced with that segment's length, where pkt_logic
    sent one response announcing the whole request.  The bytes on the
    connection are the same.
    """
    tb = TB(dut)
    await tb.reset()

    for conn_id, total_bytes, segment_bytes, header_alone in (
            (0x3200, 4096, 1024, False),
            (0x3201, 4096, 1024, True),
            (0x3202, MAX_PACKET_BYTES, MAX_PACKET_BYTES, True)):
        request = build_echo_request(total_bytes, conn_id)
        segments = segment_request(request, segment_bytes, header_alone)
        await send_segments(tb, segments, conn_id)
        stream = b""
        for segment in segments:
            stream += await expect_echo(tb, conn_id, segment)
        assert stream == request
    await tb.expect_no_response()


@cocotb.test()
async def test_nothing_in_a_segment_is_parsed(dut):
    """
    With no dispatcher a segment's bytes mean nothing: an or_slot header, a
    reconfiguration request, a line without the FIRST flag that pkt_logic
    would have dropped, and a header declaring more than its segment holds
    all come back as they went in.
    """
    tb = TB(dut)
    await tb.reset()

    no_first = bytearray(RequestHeader(total_size=BYTE_LANES, workload_id=0x0000).to_bytes())
    no_first[60] &= 0xfe
    conn_id = 0x3300
    for segment in (
        RequestHeader(total_size=BYTE_LANES, workload_id=0x0001).to_bytes(),
        RequestHeader(total_size=2 * BYTE_LANES, workload_id=RECONF_APP).to_bytes() + bytes(BYTE_LANES),
        bytes(no_first),
        RequestHeader(total_size=4096, workload_id=0x0000, request_flags=REQ_FLAG_FIRST).to_bytes(),
    ):
        await send_segments(tb, [segment], conn_id)
        await expect_echo(tb, conn_id, segment)
    await tb.expect_no_response()


async def run_clients_segment_echo(dut, n_clients, sizes, framing, requests_per_client, seed=1, patience=20000):
    """
    n_clients connections, each sending requests_per_client requests cut into
    segments as `framing` says (see test_multiclient.cut), all up front, their
    segments reaching the TOE round robin.  Every connection must get back
    exactly the segments it sent, in order, each announced with its own length.
    """
    tb = TB(dut)
    await tb.reset()
    toe = ToeRxBuffer(tb)
    tx = ToeTx(tb)
    rng = random.Random(seed)

    conns = [0x400 + c for c in range(n_clients)]
    sent = {c: [segment for s in range(requests_per_client)
                for segment in cut(make_request(rng.choice(sizes), c, s), framing)]
            for c in conns}
    unsent = {c: list(sent[c]) for c in conns}
    while any(unsent.values()):
        for c in conns:
            if unsent[c]:
                await toe.receive_segment(unsent[c].pop(0), conn_id=c)
    total = sum(len(sent[c]) for c in conns)
    for _ in range(0, patience, 16):
        if len(tx.responses) >= total:
            break
        await ClockCycles(dut.clk, 16)
    await ClockCycles(dut.clk, 500)

    dut._log.info(f"{n_clients} clients, {framing}, sizes {sizes}: {total} segments, "
                  f"{len(tx.responses)} responses")
    got = defaultdict(list)
    for meta, data in tx.responses:
        assert meta is not None and meta >> 16 == len(data), f"{len(data)}B response announced as {meta}"
        got[meta & 0xffff].append(data)
    for c in conns:
        assert got[c] == sent[c], f"connection {c:#x}: {len(got[c])} of {len(sent[c])} segments back as sent"


@cocotb.test()
async def test_clients_framing_as_sw_app_get_their_segments_back(dut):
    """Four clients, each sending a header segment and then the data, interleaved."""
    await run_clients_segment_echo(dut, 4, [1024, 4096], "header_alone", 8)


@cocotb.test()
async def test_multi_segment_requests_from_eight_clients_do_not_stall(dut):
    """
    The reassembly benches' known limit -- more multi-segment requests open at
    once than the scheduler has queues stalls the input -- belongs to the
    scheduler.  Without it the same load, eight clients opening 16 and 24 KB
    requests at MSS 8192, comes back segment by segment.
    """
    await run_clients_segment_echo(dut, 8, [16384, 24576], "one_write", 4)
