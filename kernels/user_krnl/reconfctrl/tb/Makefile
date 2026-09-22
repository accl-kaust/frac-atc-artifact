TOPLEVEL_LANG = verilog

SIM ?= verilator
WAVES ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

RTL_DIR = ../rtl

MODULE = test_reconfctrl
TOPLEVEL = reconfctrl

VERILOG_SOURCES += $(RTL_DIR)/reconfctrl.v

ifeq ($(SIM), verilator)
    COMPILE_ARGS += --sv
    COMPILE_ARGS += -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC
    ifeq ($(WAVES), 1)
        COMPILE_ARGS += --trace-fst
        VERILATOR_TRACE = 1
    endif
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
