#FPGA_PART = xcu280-fsvh2892-2L-e
FPGA_TOP = frac_top

FDEV_NAME ?= u280

ifeq ($(FDEV_NAME),u280)
    FPGA_PART        := xcu280-fsvh2892-2L-e
    FNS_PLATFORM     := xilinx_u280_xdma_201920_3
    FNS_PLATFORM_PART:= xcu280-fsvh2892-2L-e
    CMAC_SLR         := SLR2
endif

NETWORK_BANDWIDTH            ?= 100
NETWORK_INTERFACE            ?= 100
DATA_WIDTH                   ?= 64
CLOCK_PERIOD                 ?= 5.0
TCP_STACK_EN                 ?= 0
UDP_STACK_EN                 ?= 1
# fpga-network-stack's CMake reads these as TCP_STACK_*. They used to be
# passed as FNS_TCP_STACK_*, the names the Vitis_with_100Gbps_TCP-IP wrapper
# maps from, which nothing here reads -- so the TOE was built with hls/toe's
# own default MSS of 1460 whatever was set here.
#
# The TOE advertises its MSS in the SYN-ACK, so the host never sends a longer
# segment, and it is the TOE's own TX segment size (it ignores the host's).
# pkt_receiver.v takes only segments that are whole 64-byte lines, at most
# its MAX_PACKET_BYTES of 8192: with 1460 the host cut every write over 1408
# bytes at a non-line boundary and the request got no reply.
#
# 8192 is the payload of an 8232-byte jumbo frame, and needs MTU >= 8232 on
# every link to the host. On a 1500-byte MTU the host still cuts at 1460 for
# its own MTU and the TOE's 8192-byte segments never reach it; build with
# TCP_STACK_MSS=1408 there, the largest multiple of 64 that fits. The cap
# below is MAX_PACKET_BYTES in pkt_receiver.v -- raise both together or the
# receiver refuses every segment the host cuts at the advertised MSS.
TCP_STACK_MSS                ?= 8192
TCP_STACK_RX_DDR_BYPASS_EN   ?= 1
TCP_STACK_WINDOW_SCALING_EN  ?= 1
TCP_STACK_MAX_SESSIONS       ?= 1000

ifneq ($(shell expr $(TCP_STACK_MSS) % 64 = 0 \& $(TCP_STACK_MSS) \<= 8192),1)
    $(error TCP_STACK_MSS=$(TCP_STACK_MSS) must be a multiple of 64 and at most 8192, or pkt_receiver.v refuses the segments the host cuts at it)
endif

CMAKE_ARGS += \
    -DFDEV_NAME=$(FDEV_NAME) \
    -DFPGA_PART=$(FPGA_PART) \
    -DFNS_PLATFORM=$(FNS_PLATFORM) \
    -DFNS_PLATFORM_PART=$(FNS_PLATFORM_PART) \
    -DCMAC_SLR=$(CMAC_SLR)\
    -DNETWORK_BANDWIDTH=$(NETWORK_BANDWIDTH) \
    -DNETWORK_INTERFACE=$(NETWORK_INTERFACE) \
    -DDATA_WIDTH=$(DATA_WIDTH) \
    -DCLOCK_PERIOD=$(CLOCK_PERIOD) \
    -DTCP_STACK_EN=$(TCP_STACK_EN) \
    -DUDP_STACK_EN=$(UDP_STACK_EN) \
    -DTCP_STACK_RX_DDR_BYPASS_EN=$(TCP_STACK_RX_DDR_BYPASS_EN) \
    -DTCP_STACK_MSS=$(TCP_STACK_MSS) \
    -DTCP_STACK_WINDOW_SCALING_EN=$(TCP_STACK_WINDOW_SCALING_EN) \
    -DTCP_STACK_MAX_SESSIONS=$(TCP_STACK_MAX_SESSIONS)

#RTL Files
#frac
RTL_FILES = frac/rtl/frac_top.v
RTL_FILES += frac/rtl/frac.v
RTL_FILES += frac/rtl/frac_hbm.v

#lib
RTL_FILES += lib/axis/rtl/axis_fifo.v
RTL_FILES += lib/axis/rtl/sync_reset.v
RTL_FILES += lib/axis/rtl/reset_gen.v
RTL_FILES += lib/axis/rtl/axis_fifo_ultra.v
RTL_FILES += lib/axis/rtl/axis_reg.v
RTL_FILES += lib/taxi/prim/rtl/taxi_penc.sv
RTL_FILES += lib/taxi/prim/rtl/taxi_arbiter.sv
RTL_FILES += lib/taxi/axis/rtl/taxi_axis_if.sv
RTL_FILES += lib/taxi/axis/rtl/taxi_axis_fifo.sv
RTL_FILES += lib/taxi/axis/rtl/taxi_axis_register.sv
RTL_FILES += lib/taxi/axis/rtl/taxi_axis_switch.sv

# common
RTL_FILES += kernels/common/types/network_intf.svh
RTL_FILES += kernels/common/types/network_types.svh
RTL_FILES += kernels/common/types/network_types.svh.in


#cmac krnl
RTL_FILES += kernels/cmac_krnl/rtl/cmac_krnl.sv
RTL_FILES += kernels/cmac_krnl/rtl/cmac_krnl_control_s_axi.sv
RTL_FILES += kernels/cmac_krnl/rtl/cmac_usplus_axis_wrapper.sv
RTL_FILES += kernels/cmac_krnl/rtl/network_module.sv
RTL_FILES += kernels/cmac_krnl/rtl/network_clk_cross.sv
RTL_FILES += kernels/cmac_krnl/rtl/axis_data_reg_array.sv
RTL_FILES += kernels/cmac_krnl/rtl/axis_data_reg.sv

#network krnl
RTL_FILES += kernels/network_krnl/rtl/tcp_stack.sv
RTL_FILES += kernels/network_krnl/rtl/udp_stack.sv
RTL_FILES += kernels/network_krnl/rtl/network_top.sv
RTL_FILES += kernels/network_krnl/rtl/network_krnl.sv
RTL_FILES += kernels/network_krnl/rtl/network_stack.sv
RTL_FILES += kernels/network_krnl/rtl/network_control_s_axi.sv
RTL_FILES += kernels/network_krnl/rtl/axis_data_reg.sv
RTL_FILES += kernels/network_krnl/rtl/axis_meta_reg.sv
RTL_FILES += kernels/network_krnl/rtl/axis_udp_meta_reg.sv
RTL_FILES += kernels/network_krnl/rtl/axis_data_reg_array.sv
RTL_FILES += kernels/network_krnl/rtl/mem_single_inf.sv

#user krnl
RTL_FILES += kernels/user_krnl/reassembly/rtl/user_krnl.v
RTL_FILES += kernels/user_krnl/reassembly/rtl/axis_fifo_taxi.sv
RTL_FILES += kernels/user_krnl/reassembly/rtl/axis_data_fifo_replacements.sv
RTL_FILES += kernels/user_krnl/reassembly/rtl/axis_register.v
RTL_FILES += kernels/user_krnl/reassembly/rtl/axis_pipeline_register.v
RTL_FILES += kernels/user_krnl/reassembly/rtl/dispatcher.v
RTL_FILES += kernels/user_krnl/reassembly/rtl/ipcore_top_top_k.v
RTL_FILES += kernels/user_krnl/reassembly/rtl/slot_tx_axis_switch.sv
RTL_FILES += kernels/user_krnl/reassembly/rtl/pkt_logic.v
RTL_FILES += kernels/user_krnl/reassembly/rtl/pkt_receiver.v
RTL_FILES += kernels/user_krnl/reassembly/rtl/pkt_sender.v
RTL_FILES += kernels/user_krnl/reassembly/rtl/scheduler.v
RTL_FILES += kernels/user_krnl/reassembly/rtl/tcp_top_loopback.v
RTL_FILES += kernels/user_krnl/reassembly/rtl/user_krnl_control_s_axi.v
RTL_FILES += kernels/user_krnl/reconfctrl/rtl/axis_dfx_decoupler.sv
RTL_FILES += kernels/user_krnl/reconfctrl/rtl/cell_bbx.sv
RTL_FILES += kernels/user_krnl/reconfctrl/rtl/reconfctrl.v
RTL_FILES += kernels/user_krnl/reconfctrl/rtl/icap_ctrl.v

#XDC
XDC_FILES = frac/xdc/fpga_u280.xdc
XDC_FILES += lib/axis/xdc/sync_reset.tcl
XDC_FILES += frac/xdc/floorplan.xdc

IP_TCL_FILES = kernels/network_krnl/ip/network_stack.tcl
IP_TCL_FILES += kernels/network_krnl/ip/network_infrastructure.tcl
IP_TCL_FILES += kernels/network_krnl/ip/network_ultrascale.tcl
IP_TCL_FILES += frac/ip/proc_sys_reset.tcl
IP_TCL_FILES += frac/ip/axis_data_width_conv.tcl
IP_TCL_FILES += kernels/cmac_krnl/ip/cmac.tcl
IP_TCL_FILES += frac/ip/hbm_0.tcl
IP_TCL_FILES += frac/ip/ila_icap.tcl
IP_TCL_FILES += frac/ip/axi_prot_conv.tcl
IP_TCL_FILES += frac/ip/axi_data_width_conv.tcl

include hls.mk
include vivado.mk
