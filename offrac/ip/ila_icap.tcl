create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_icap
set_property -dict [list \
                        CONFIG.C_NUM_OF_PROBES {4} \
                        CONFIG.C_DATA_DEPTH {1024} \
                        CONFIG.C_EN_STRG_QUAL {1} \
                        CONFIG.C_ADV_TRIGGER {true} \
                        CONFIG.C_INPUT_PIPE_STAGES {1} \
                        CONFIG.C_PROBE0_WIDTH {1} \
                        CONFIG.C_PROBE1_WIDTH {1} \
                        CONFIG.C_PROBE2_WIDTH {32} \
                        CONFIG.C_PROBE3_WIDTH {1}
                   ] [get_ips ila_icap]
