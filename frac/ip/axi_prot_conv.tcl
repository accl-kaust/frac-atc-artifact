create_ip -name axi_protocol_converter -vendor xilinx.com -library ip -module_name axi_prot_conv

set_property -dict [list \
                        CONFIG.SI_PROTOCOL {AXI4} \
                        CONFIG.MI_PROTOCOL {AXI3} \
                        CONFIG.ADDR_WIDTH {64} \
                        CONFIG.DATA_WIDTH {256} \
                        CONFIG.TRANSLATION_MODE {2}
                   ] [get_ips axi_prot_conv]
