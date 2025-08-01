#FPGA_PART = xcu280-fsvh2892-2L-e
FPGA_TOP = offrac_top

FDEV_NAME ?= u280

ifeq ($(FDEV_NAME),u280)
    FPGA_PART        := xcu280-fsvh2892-2L-e
    FNS_PLATFORM     := xilinx_u280_xdma_201920_3
    FNS_PLATFORM_PART:= xcu280-fsvh2892-2L-e
    NETWORK_KRNL_MEM := HBM[15]
    CMAC_SLR         := SLR2
endif

NETWORK_BANDWIDTH            ?= 100
NETWORK_INTERFACE            ?= 100
DATA_WIDTH                   ?= 64
CLOCK_PERIOD                 ?= 3.2
TCP_STACK_EN                 ?= 0
UDP_STACK_EN                 ?= 1
FNS_TCP_STACK_RX_DDR_BYPASS_EN ?= 1
FNS_TCP_STACK_MSS            ?= 4096
FNS_TCP_STACK_WINDOW_SCALING_EN ?= 1
FNS_TCP_STACK_MAX_SESSIONS   ?= 1000

CMAKE_ARGS += \
    -DFDEV_NAME=$(FDEV_NAME) \
    -DFPGA_PART=$(FPGA_PART) \
    -DFNS_PLATFORM=$(FNS_PLATFORM) \
    -DFNS_PLATFORM_PART=$(FNS_PLATFORM_PART) \
    -DNETWORK_KRNL_MEM=$(NETWORK_KRNL_MEM) \
    -DCMAC_SLR=$(CMAC_SLR)\
	-DNETWORK_BANDWIDTH=$(NETWORK_BANDWIDTH) \
    -DNETWORK_INTERFACE=$(NETWORK_INTERFACE) \
    -DDATA_WIDTH=$(DATA_WIDTH) \
    -DCLOCK_PERIOD=$(CLOCK_PERIOD) \
    -DTCP_STACK_EN=$(TCP_STACK_EN) \
    -DUDP_STACK_EN=$(UDP_STACK_EN) \
    -DFNS_TCP_STACK_RX_DDR_BYPASS_EN=$(FNS_TCP_STACK_RX_DDR_BYPASS_EN) \
    -DFNS_TCP_STACK_MSS=$(FNS_TCP_STACK_MSS) \
    -DFNS_TCP_STACK_WINDOW_SCALING_EN=$(FNS_TCP_STACK_WINDOW_SCALING_EN) \
    -DFNS_TCP_STACK_MAX_SESSIONS=$(FNS_TCP_STACK_MAX_SESSIONS)

#RTL Files
#offrac
RTL_FILES = offrac/rtl/offrac_top.v
RTL_FILES += offrac/rtl/offrac.v
RTL_FILES += offrac/rtl/offrac_hbm.v

#lib
RTL_FILES += lib/axis/rtl/axis_fifo.v
RTL_FILES += lib/axis/rtl/sync_reset.v
RTL_FILES += lib/axis/rtl/reset_gen.v
RTL_FILES += lib/axis/rtl/axis_fifo_ultra.v
RTL_FILES += lib/axis/rtl/axis_reg.v

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
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/top_mul.v
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/pkt_logic.v
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/scheduler.v
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/dispatcher.v
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/pkt_sender.v
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/top_mul.v
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/top_k_krnl.v
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/top_k_unit.v
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/top_k_block.v
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/nukv_fifogen.v
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/echo_workload.v
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/pkt_receiver.v
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/top_k_workload.v
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/EventAcceptor.vhd
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/MM_4_4_workload.v
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/ipcore_top_top_k.v
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/tcp_top_loopback.v
RTL_FILES += kernels/user_krnl/top_k_krnl/rtl/user_krnl_control_s_axi.v

#XDC
XDC_FILES = offrac/xdc/fpga_u280.xdc
XDC_FILES += lib/axis/xdc/sync_reset.tcl
XDC_FILES += offrac/xdc/floorplan.xdc

# IP
XCI_FILES = kernels/user_krnl/top_k_krnl/ip/axis_data_fifo_0.xci
XCI_FILES += kernels/user_krnl/top_k_krnl/ip/axis_data_fifo_1.xci
XCI_FILES += kernels/user_krnl/top_k_krnl/ip/axis_data_fifo_3.xci
XCI_FILES += kernels/user_krnl/top_k_krnl/ip/axis_data_fifo_88.xci
XCI_FILES += kernels/user_krnl/top_k_krnl/ip/axis_data_fifo_513.xci

IP_TCL_FILES = kernels/network_krnl/ip/network_stack.tcl
IP_TCL_FILES += kernels/network_krnl/ip/network_infrastructure.tcl
IP_TCL_FILES += kernels/network_krnl/ip/network_ultrascale.tcl
IP_TCL_FILES += offrac/ip/proc_sys_reset.tcl
IP_TCL_FILES += offrac/ip/axis_data_width_conv.tcl
IP_TCL_FILES += kernels/cmac_krnl/ip/cmac.tcl
IP_TCL_FILES += offrac/ip/hbm_0.tcl
IP_TCL_FILES += offrac/ip/axi_prot_conv.tcl
IP_TCL_FILES += offrac/ip/axi_data_width_conv.tcl

include hls.mk
include vivado.mk
