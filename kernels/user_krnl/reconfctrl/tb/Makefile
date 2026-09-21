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
    # The shipping default is ~0.5 s of cycles; the timeout test would take
    # minutes of wall clock at that value.
    COMPILE_ARGS += -GPR_DONE_TIMEOUT_CYCLES=4096
    ifeq ($(WAVES), 1)
        COMPILE_ARGS += --trace-fst
        VERILATOR_TRACE = 1
    endif
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
