TOPLEVEL_LANG = verilog

SIM ?= verilator
WAVES ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

RTL_DIR = ../src/rtl

DUT      = top_k
MODULE   = test_$(DUT)
TOPLEVEL = $(DUT)
# cocotb 2.x spellings of the two above
COCOTB_TEST_MODULES = $(MODULE)
COCOTB_TOPLEVEL     = $(TOPLEVEL)

VERILOG_SOURCES += $(RTL_DIR)/$(DUT).v

# module parameters
TOP_K_NUM ?= 16
export PARAM_TOP_K_NUM := $(TOP_K_NUM)

# one build tree per configuration, so changing one rebuilds instead of
# silently reusing the previous binary
SIM_BUILD ?= sim_build/$(SIM)_k$(TOP_K_NUM)$(if $(filter 1,$(WAVES)),_waves)

ifeq ($(SIM), verilator)
    COMPILE_ARGS += --sv
    COMPILE_ARGS += -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC
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
