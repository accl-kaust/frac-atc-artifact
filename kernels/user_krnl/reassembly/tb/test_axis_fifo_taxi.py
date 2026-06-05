#!/usr/bin/env python

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, with_timeout


async def reset_dut(dut):
    dut.rst.value = 1
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tdata.value = 0
    dut.m_axis_tready.value = 0
    await ClockCycles(dut.clk, 4)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)


async def send_words(dut, words):
    for word in words:
        dut.s_axis_tdata.value = word
        dut.s_axis_tvalid.value = 1
        while True:
            await RisingEdge(dut.clk)
            if dut.s_axis_tready.value.integer:
                break
    dut.s_axis_tvalid.value = 0


async def recv_words(dut, count, ready_pattern=(1,)):
    received = []
    cycle = 0
    while len(received) < count:
        dut.m_axis_tready.value = ready_pattern[cycle % len(ready_pattern)]
        await RisingEdge(dut.clk)
        if dut.m_axis_tvalid.value.integer and dut.m_axis_tready.value.integer:
            received.append(dut.m_axis_tdata.value.integer)
        cycle += 1
    dut.m_axis_tready.value = 0
    return received


@cocotb.test()
async def fifo_backpressure_preserves_order(dut):
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    await reset_dut(dut)

    words = list(range(64))
    sender = cocotb.start_soon(send_words(dut, words))
    received = await with_timeout(recv_words(dut, len(words), ready_pattern=(1, 0, 0, 1, 1, 0)), 20, "us")
    await with_timeout(sender, 20, "us")

    assert received == words


@cocotb.test()
async def fifo_reset_clears_queued_words(dut):
    cocotb.start_soon(Clock(dut.clk, 4, units="ns").start())
    await reset_dut(dut)

    await send_words(dut, [0x100 + idx for idx in range(4)])
    await ClockCycles(dut.clk, 2)

    dut.rst.value = 1
    await ClockCycles(dut.clk, 4)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    assert dut.m_axis_tvalid.value.integer == 0

    words = [0x200 + idx for idx in range(8)]
    sender = cocotb.start_soon(send_words(dut, words))
    received = await with_timeout(recv_words(dut, len(words), ready_pattern=(1, 1, 0)), 20, "us")
    await with_timeout(sender, 20, "us")

    assert received == words


tests_dir = os.path.dirname(__file__)
rtl_dir = os.path.abspath(os.path.join(tests_dir, "..", "rtl"))
taxi_rtl_dir = os.path.abspath(os.path.join(tests_dir, "..", "..", "..", "..", "lib", "taxi", "axis", "rtl"))


def test_axis_fifo_taxi(request):
    import cocotb_test.simulator

    cocotb_test.simulator.run(
        simulator="verilator",
        verilog_sources=[
            os.path.join(taxi_rtl_dir, "taxi_axis_if.sv"),
            os.path.join(taxi_rtl_dir, "taxi_axis_fifo.sv"),
            os.path.join(rtl_dir, "axis_fifo_taxi.sv"),
        ],
        toplevel="axis_fifo_taxi",
        module="test_axis_fifo_taxi",
        parameters={
            "DATA_WIDTH": 32,
            "DEPTH": 8,
            "RAM_PIPELINE": 1,
            "OUTPUT_FIFO_EN": 0,
        },
        sim_build=os.path.join(tests_dir, "sim_build", request.node.name),
        extra_args=["--sv", "-Wno-PINMISSING", "-Wno-WIDTHEXPAND", "-Wno-WIDTHTRUNC"],
    )
