TOPLEVEL_LANG = verilog
.DEFAULT_GOAL := sim

SIM ?= verilator
WAVES ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

RTL_DIR = ../rtl
TAXI_RTL_DIR = ../../../../lib/taxi/axis/rtl

MODULE = test_reassembly,test_multiclient,test_throughput
TOPLEVEL = tcp_top_loopback

VERILOG_SOURCES += $(TAXI_RTL_DIR)/taxi_axis_if.sv
VERILOG_SOURCES += $(TAXI_RTL_DIR)/taxi_axis_fifo.sv
VERILOG_SOURCES += $(RTL_DIR)/axis_fifo_taxi.sv
VERILOG_SOURCES += $(RTL_DIR)/axis_data_fifo_replacements.sv
VERILOG_SOURCES += $(RTL_DIR)/axis_register.v
VERILOG_SOURCES += $(RTL_DIR)/axis_pipeline_register.v
VERILOG_SOURCES += $(RTL_DIR)/dispatcher.v
VERILOG_SOURCES += $(RTL_DIR)/scheduler.v
# pkt_logic instantiates the one kernel, pattern_slot, directly
APPS_DIR = ../../apps
VERILOG_SOURCES += $(APPS_DIR)/pattern_slot/src/rtl/pattern_slot.v
VERILOG_SOURCES += $(APPS_DIR)/pattern_slot/src/rtl/pattern_slot_core.v
VERILOG_SOURCES += $(RTL_DIR)/pkt_logic.v
VERILOG_SOURCES += $(RTL_DIR)/pkt_receiver.v
VERILOG_SOURCES += $(RTL_DIR)/pkt_sender.v
VERILOG_SOURCES += $(RTL_DIR)/tcp_top_loopback.v

ifeq ($(SIM), verilator)
    COMPILE_ARGS += --sv
    COMPILE_ARGS += -DSIMULATION
    COMPILE_ARGS += -Wno-PINMISSING -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC
    ifeq ($(WAVES), 1)
        COMPILE_ARGS += --trace-fst
        VERILATOR_TRACE = 1
    endif
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
