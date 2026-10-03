TOPLEVEL_LANG = verilog

SIM ?= verilator
WAVES ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

RTL_DIR   = ../src/rtl
REASM_DIR = ../../../reassembly
TAXI_DIR  = ../../../../../lib/taxi/axis/rtl

DUT    = log
MODULE = test_$(DUT)
# cocotb 2.x spelling
COCOTB_TEST_MODULES = $(MODULE)

# LEVEL=core  the core alone: every handshake, the sideband, the timing
# LEVEL=slot  the module as built into a cell, behind the static side of its
#             slot (reassembly/tb/tb_slot.sv): credits, PIPE_LEN stages each way
LEVEL ?= core
export LEVEL

# The Xilinx floating-point cores are not in the repo (regenerate the .xci with
# src/ip/gen_ip.tcl); fp_stubs.v stands in for them.
VERILOG_SOURCES += fp_stubs.v
VERILOG_SOURCES += $(RTL_DIR)/$(DUT)_core.v
VERILOG_SOURCES += $(TAXI_DIR)/taxi_axis_if.sv
VERILOG_SOURCES += $(TAXI_DIR)/taxi_axis_fifo.sv
VERILOG_SOURCES += $(REASM_DIR)/rtl/axis_fifo_taxi.sv

ifeq ($(LEVEL), slot)
    TOPLEVEL = tb_slot
    VERILOG_SOURCES += $(RTL_DIR)/$(DUT).v
    VERILOG_SOURCES += $(REASM_DIR)/rtl/slot_credit.v
    VERILOG_SOURCES += $(REASM_DIR)/rtl/slot_boundary.v
    VERILOG_SOURCES += $(REASM_DIR)/tb/tb_slot.sv
    COMPILE_ARGS += -DSLOT_RM=$(DUT)
else
    TOPLEVEL = $(DUT)_core
endif
COCOTB_TOPLEVEL = $(TOPLEVEL)

# module parameters, the core's; at LEVEL=slot the module's defaults apply
ALIGN_DEPTH ?= 32
OUT_DEPTH ?= 8
ifneq ($(LEVEL), slot)
    export PARAM_ALIGN_DEPTH := $(ALIGN_DEPTH)
    export PARAM_OUT_DEPTH := $(OUT_DEPTH)
endif

# one build tree per configuration, so changing one rebuilds instead of
# silently reusing the previous binary
SIM_BUILD ?= sim_build/$(SIM)_$(LEVEL)_d$(ALIGN_DEPTH)_o$(OUT_DEPTH)$(if $(filter 1,$(WAVES)),_waves)

ifeq ($(SIM), verilator)
    COMPILE_ARGS += --sv -DSIMULATION
    COMPILE_ARGS += -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL
    COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-G$(subst PARAM_,,$(v))=$($(v)))
    ifeq ($(WAVES), 1)
        COMPILE_ARGS += --trace-fst
        VERILATOR_TRACE = 1
    endif
else ifeq ($(SIM), icarus)
    PLUSARGS += -fst
    COMPILE_ARGS += -DSIMULATION
    COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-P$(TOPLEVEL).$(subst PARAM_,,$(v))=$($(v)))
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

# cocotb's own `clean` only removes the current SIM_BUILD
.PHONY: distclean
distclean:
	rm -rf sim_build results.xml dump.fst dump.vcd __pycache__
