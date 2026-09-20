create_ip -name axis_dwidth_converter -vendor xilinx.com -library ip -module_name axis_tcp_stat_width_conv

set_property -dict [list \
                        CONFIG.S_TDATA_NUM_BYTES {16} \
                        CONFIG.M_TDATA_NUM_BYTES {4} \
                        CONFIG.HAS_TLAST {1} \
                        CONFIG.HAS_TKEEP {1}
                   ] [get_ips axis_tcp_stat_width_conv]
