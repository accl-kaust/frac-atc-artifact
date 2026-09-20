TOPLEVEL_LANG = verilog
.DEFAULT_GOAL := sim

SIM ?= verilator
WAVES ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

RTL_DIR  = ../../rtl
TAXI_DIR = ../../../../../lib/taxi/axis/rtl

MODULE   = test_scheduler
TOPLEVEL = scheduler

VERILOG_SOURCES += $(TAXI_DIR)/taxi_axis_if.sv
VERILOG_SOURCES += $(TAXI_DIR)/taxi_axis_fifo.sv
VERILOG_SOURCES += $(RTL_DIR)/axis_fifo_taxi.sv
VERILOG_SOURCES += $(RTL_DIR)/axis_data_fifo_replacements.sv
VERILOG_SOURCES += $(RTL_DIR)/axis_register.v
VERILOG_SOURCES += $(RTL_DIR)/axis_pipeline_register.v
VERILOG_SOURCES += $(RTL_DIR)/scheduler.v

ifeq ($(SIM), verilator)
    COMPILE_ARGS += --sv
    COMPILE_ARGS += -DSIMULATION
    COMPILE_ARGS += -Wno-PINMISSING -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-DECLFILENAME -Wno-TIMESCALEMOD
    ifeq ($(WAVES), 1)
        COMPILE_ARGS += --trace-fst
        VERILATOR_TRACE = 1
    endif
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
