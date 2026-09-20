create_ip -name axi_dwidth_converter -vendor xilinx.com -library ip -module_name axi_dwidth_conv

set_property -dict [list \
                        CONFIG.ADDR_WIDTH {64} \
                        CONFIG.SI_DATA_WIDTH {512} \
                        CONFIG.MI_DATA_WIDTH {256} \
                        CONFIG.READ_WRITE_MODE {READ_WRITE}
                   ] [get_ips axi_dwidth_conv]
