TOPLEVEL_LANG = verilog

SIM ?= verilator
WAVES ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

RTL_DIR = ../rtl
RECONF_RTL_DIR = ../../reconfctrl/rtl
TAXI_RTL_DIR = ../../../../lib/taxi/axis/rtl

MODULE = test_reassembly
TOPLEVEL = tcp_top_loopback

VERILOG_SOURCES += $(TAXI_RTL_DIR)/taxi_axis_if.sv
VERILOG_SOURCES += $(TAXI_RTL_DIR)/taxi_axis_fifo.sv
VERILOG_SOURCES += ../../../../lib/taxi/prim/rtl/taxi_penc.sv
VERILOG_SOURCES += ../../../../lib/taxi/prim/rtl/taxi_arbiter.sv
VERILOG_SOURCES += $(TAXI_RTL_DIR)/taxi_axis_register.sv
VERILOG_SOURCES += $(TAXI_RTL_DIR)/taxi_axis_switch.sv
VERILOG_SOURCES += $(RTL_DIR)/axis_fifo_taxi.sv
VERILOG_SOURCES += $(RTL_DIR)/axis_data_fifo_replacements.sv
VERILOG_SOURCES += $(RTL_DIR)/axis_register.v
VERILOG_SOURCES += $(RTL_DIR)/axis_pipeline_register.v
VERILOG_SOURCES += $(RTL_DIR)/dispatcher.v
VERILOG_SOURCES += $(RTL_DIR)/scheduler.v
VERILOG_SOURCES += $(RTL_DIR)/slot_tx_axis_switch.sv
VERILOG_SOURCES += $(RECONF_RTL_DIR)/axis_dfx_decoupler.sv
VERILOG_SOURCES += $(RECONF_RTL_DIR)/cell_bbx.sv
VERILOG_SOURCES += $(RECONF_RTL_DIR)/reconfctrl.v
VERILOG_SOURCES += $(RECONF_RTL_DIR)/icap_ctrl.v
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
