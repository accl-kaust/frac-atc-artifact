create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_icap
set_property -dict [list \
                        CONFIG.C_NUM_OF_PROBES {15} \
                        CONFIG.C_DATA_DEPTH {1024} \
                        CONFIG.C_EN_STRG_QUAL {1} \
                        CONFIG.C_ADV_TRIGGER {true} \
                        CONFIG.C_INPUT_PIPE_STAGES {1} \
                        CONFIG.C_PROBE0_WIDTH {1} \
                        CONFIG.C_PROBE1_WIDTH {1} \
                        CONFIG.C_PROBE2_WIDTH {32} \
                        CONFIG.C_PROBE3_WIDTH {1} \
                        CONFIG.C_PROBE4_WIDTH {1} \
                        CONFIG.C_PROBE5_WIDTH {1} \
                        CONFIG.C_PROBE6_WIDTH {1} \
                        CONFIG.C_PROBE7_WIDTH {2} \
                        CONFIG.C_PROBE8_WIDTH {1} \
                        CONFIG.C_PROBE9_WIDTH {8} \
                        CONFIG.C_PROBE10_WIDTH {8} \
                        CONFIG.C_PROBE11_WIDTH {64} \
                        CONFIG.C_PROBE12_WIDTH {64} \
                        CONFIG.C_PROBE13_WIDTH {4} \
                        CONFIG.C_PROBE14_WIDTH {8}
                   ] [get_ips ila_icap]
