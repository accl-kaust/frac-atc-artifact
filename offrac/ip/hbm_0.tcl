create_ip -name hbm -vendor xilinx.com -library ip -module_name hbm_0

set_property -dict [list \
                        CONFIG.USER_HBM_DENSITY {4GB} \
                        CONFIG.USER_APB_PCLK_0 {50} \
                        CONFIG.USER_APB_PCLK_PERIOD_0 {20.0} \
                        CONFIG.USER_TEMP_POLL_CNT_0 {50000} \
                        CONFIG.USER_CLK_SEL_LIST0 {AXI_00_ACLK} \
                        CONFIG.USER_MC_ENABLE_02 {FALSE} \
                        CONFIG.USER_MC_ENABLE_03 {FALSE} \
                        CONFIG.USER_MC_ENABLE_04 {FALSE} \
                        CONFIG.USER_MC_ENABLE_05 {FALSE} \
                        CONFIG.USER_MC_ENABLE_06 {FALSE} \
                        CONFIG.USER_MC_ENABLE_07 {FALSE} \
                        CONFIG.USER_SAXI_01 {true} \
                        CONFIG.USER_SAXI_02 {true} \
                        CONFIG.USER_SAXI_03 {true} \
                        CONFIG.USER_SAXI_04 {false} \
                        CONFIG.USER_SAXI_05 {false} \
                        CONFIG.USER_SAXI_06 {false} \
                        CONFIG.USER_SAXI_07 {false} \
                        CONFIG.USER_SAXI_08 {false} \
                        CONFIG.USER_SAXI_09 {false} \
                        CONFIG.USER_SAXI_10 {false} \
                        CONFIG.USER_SAXI_11 {false} \
                        CONFIG.USER_SAXI_12 {false} \
                        CONFIG.USER_SAXI_13 {false} \
                        CONFIG.USER_SAXI_14 {false} \
                        CONFIG.USER_SAXI_15 {false} \
                        CONFIG.USER_AXI_INPUT_CLK_FREQ {200} \
                        CONFIG.USER_AXI_INPUT_CLK_NS {5.000} \
                        CONFIG.USER_AXI_INPUT_CLK_PS {5000} \
                        CONFIG.USER_AXI_INPUT_CLK_XDC {5.000} \
                        CONFIG.HBM_MMCM_FBOUT_MULT0 {18} \
                        CONFIG.USER_APB_EN {false}
                   ] [get_ips hbm_0]

create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_hbm_debug
set_property -dict [list \
                        CONFIG.C_EN_PROBE_IN_ACTIVITY {0} \
                        CONFIG.C_NUM_PROBE_IN {13} \
                        CONFIG.C_NUM_PROBE_OUT {5} \
                        CONFIG.C_PROBE_IN0_WIDTH {1} \
                        CONFIG.C_PROBE_IN1_WIDTH {1} \
                        CONFIG.C_PROBE_IN2_WIDTH {1} \
                        CONFIG.C_PROBE_IN3_WIDTH {1} \
                        CONFIG.C_PROBE_IN4_WIDTH {4} \
                        CONFIG.C_PROBE_IN5_WIDTH {32} \
                        CONFIG.C_PROBE_IN6_WIDTH {32} \
                        CONFIG.C_PROBE_IN7_WIDTH {33} \
                        CONFIG.C_PROBE_IN8_WIDTH {1} \
                        CONFIG.C_PROBE_IN9_WIDTH {1} \
                        CONFIG.C_PROBE_IN10_WIDTH {1} \
                        CONFIG.C_PROBE_IN11_WIDTH {32} \
                        CONFIG.C_PROBE_IN12_WIDTH {32} \
                        CONFIG.C_PROBE_OUT0_WIDTH {1} \
                        CONFIG.C_PROBE_OUT1_WIDTH {1} \
                        CONFIG.C_PROBE_OUT2_WIDTH {33} \
                        CONFIG.C_PROBE_OUT3_WIDTH {16} \
                        CONFIG.C_PROBE_OUT4_WIDTH {2}
                   ] [get_ips vio_hbm_debug]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_hbm_debug
set_property -dict [list \
                        CONFIG.C_NUM_OF_PROBES {23} \
                        CONFIG.C_DATA_DEPTH {1024} \
                        CONFIG.C_EN_STRG_QUAL {1} \
                        CONFIG.C_ADV_TRIGGER {true} \
                        CONFIG.C_INPUT_PIPE_STAGES {1} \
                        CONFIG.C_PROBE0_WIDTH {4} \
                        CONFIG.C_PROBE1_WIDTH {1} \
                        CONFIG.C_PROBE2_WIDTH {1} \
                        CONFIG.C_PROBE3_WIDTH {1} \
                        CONFIG.C_PROBE4_WIDTH {1} \
                        CONFIG.C_PROBE5_WIDTH {1} \
                        CONFIG.C_PROBE6_WIDTH {1} \
                        CONFIG.C_PROBE7_WIDTH {2} \
                        CONFIG.C_PROBE8_WIDTH {1} \
                        CONFIG.C_PROBE9_WIDTH {1} \
                        CONFIG.C_PROBE10_WIDTH {1} \
                        CONFIG.C_PROBE11_WIDTH {1} \
                        CONFIG.C_PROBE12_WIDTH {2} \
                        CONFIG.C_PROBE13_WIDTH {1} \
                        CONFIG.C_PROBE14_WIDTH {33} \
                        CONFIG.C_PROBE15_WIDTH {32} \
                        CONFIG.C_PROBE16_WIDTH {32} \
                        CONFIG.C_PROBE17_WIDTH {256} \
                        CONFIG.C_PROBE18_WIDTH {256} \
                        CONFIG.C_PROBE19_WIDTH {1} \
                        CONFIG.C_PROBE20_WIDTH {1} \
                        CONFIG.C_PROBE21_WIDTH {1} \
                        CONFIG.C_PROBE22_WIDTH {1}
                   ] [get_ips ila_hbm_debug]
