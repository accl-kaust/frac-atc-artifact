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
                        CONFIG.USER_SAXI_01 {false} \
                        CONFIG.USER_SAXI_02 {true} \
                        CONFIG.USER_SAXI_03 {false} \
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
