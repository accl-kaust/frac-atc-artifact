TOPLEVEL_LANG = verilog

SIM ?= verilator
WAVES ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

RTL_DIR = ../src/rtl

DUT      = norm
MODULE   = test_$(DUT)
TOPLEVEL = $(DUT)
# cocotb 2.x spellings of the two above
COCOTB_TEST_MODULES = $(MODULE)
COCOTB_TOPLEVEL     = $(TOPLEVEL)

# The Xilinx floating-point cores are not in the repo (regenerate the .xci with
# src/ip/gen_ip.tcl); fp_stubs.v stands in for them.
VERILOG_SOURCES += fp_stubs.v
VERILOG_SOURCES += $(RTL_DIR)/$(DUT).v

# module parameters
MAX_LINES ?= 256
export PARAM_MAX_LINES := $(MAX_LINES)

# one build tree per configuration, so changing one rebuilds instead of
# silently reusing the previous binary
SIM_BUILD ?= sim_build/$(SIM)_l$(MAX_LINES)$(if $(filter 1,$(WAVES)),_waves)

ifeq ($(SIM), verilator)
    COMPILE_ARGS += --sv
    COMPILE_ARGS += -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL
    COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-G$(subst PARAM_,,$(v))=$($(v)))
    ifeq ($(WAVES), 1)
        COMPILE_ARGS += --trace-fst
        VERILATOR_TRACE = 1
    endif
else ifeq ($(SIM), icarus)
    PLUSARGS += -fst
    COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-P$(TOPLEVEL).$(subst PARAM_,,$(v))=$($(v)))
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

# cocotb's own `clean` only removes the current SIM_BUILD
.PHONY: distclean
distclean:
	rm -rf sim_build results.xml dump.fst dump.vcd __pycache__
