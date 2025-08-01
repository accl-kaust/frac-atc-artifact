#update_ip_catalog

#create_ip -name axis_register_slice -vendor xilinx.com -library ip -module_name axis_register_slice_512
#set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.Component_Name {axis_register_slice_512}] [get_ips axis_register_slice_512]

#create_ip -name axis_data_fifo -vendor xilinx.com -library ip -module_name axis_pkg_fifo_512
#set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_MODE {2} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.Component_Name {axis_pkg_fifo_512}] [get_ips axis_pkg_fifo_512]

create_ip -name ethernet_frame_padding_512 -vendor ethz.systems.fpga -library hls -version 0.1 -module_name ethernet_frame_padding_512_ip

create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name cmac_usplus_axis

set gt_ref_clk 156.25
set freerunningclock 50
set core_selection  CMACE4_X0Y5
set group_selection X0Y40~X0Y43
set gt_clk_freq [expr int(${gt_ref_clk} * 1000000)]

set_property -dict [list \
                        CONFIG.CMAC_CAUI4_MODE             {1} \
                        CONFIG.NUM_LANES                   {4x25} \
                        CONFIG.GT_REF_CLK_FREQ             $gt_ref_clk \
                        CONFIG.CMAC_CORE_SELECT            $core_selection \
                        CONFIG.GT_GROUP_SELECT             $group_selection \
                        CONFIG.GT_DRP_CLK                  $freerunningclock \
                        CONFIG.USER_INTERFACE              {AXIS} \
                        CONFIG.TX_FLOW_CONTROL             {0} \
                        CONFIG.RX_FLOW_CONTROL             {0} \
                        CONFIG.ENABLE_PIPELINE_REG         {1}
]  [get_ips cmac_usplus_axis]

#create_ip -name axis_data_fifo -vendor xilinx.com -library ip -module_name axis_data_fifo_cc_udp_data
#set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {256} CONFIG.IS_ACLK_ASYNC {1} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.Component_Name {axis_data_fifo_cc_udp_data}] [get_ips axis_data_fifo_cc_udp_data]

##ila
create_ip -name ila -vendor xilinx.com -library ip -module_name ila_cmac
set_property -dict [list CONFIG.C_PROBE0_WIDTH {4}  CONFIG.C_PROBE8_WIDTH {4} CONFIG.C_PROBE9_WIDTH {6} CONFIG.C_PROBE12_WIDTH {4} CONFIG.C_NUM_OF_PROBES {14} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_ADV_TRIGGER {true} CONFIG.C_INPUT_PIPE_STAGES {1}] [get_ips ila_cmac]

create_ip -name ila -vendor xilinx.com -library ip -module_name ila_0
set_property -dict [list CONFIG.C_NUM_OF_PROBES {1} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_ADV_TRIGGER {true} CONFIG.C_INPUT_PIPE_STAGES {1}] [get_ips ila_0]
