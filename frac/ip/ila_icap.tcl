# ILA on the reconfiguration controller, in the STATIC region.
#
# Ground truth for a partial reconfiguration that reports success and changes
# nothing: the ICAP stream and the ICAPE3 pins themselves, the decouple and
# state the controller drove, the handshake at each slot boundary, and the
# dispatcher's request framing -- which is where a byte-accounting desync
# during a long upload would show up as a payload line taken for a header.
#
# Every probe is a static net. The slot handshakes are the partition-pin nets
# at each cNN_bbx_inst; nothing reaches inside a reconfigurable partition.
#
# 36 probes, 284 bits, 8192 samples. Capture control (C_EN_STRG_QUAL) and the
# advanced trigger are on, so a run can be qualified on a decouple edge rather
# than filling the buffer with idle. Probes are wired in pkt_logic.v.
#
# probe  width  signal
#  0     1      reconf_axis_icap_tvalid
#  1     1      reconf_axis_icap_tready
#  2     32     reconf_axis_icap_tdata[31:0]
#  3     1      reconf_axis_icap_tlast
#  4     1      icap_pr_done
#  5     1      icap_pr_err
#  6     1      icap_avail
#  7     3      slot_decouple[2:0]
#  8     1      reconf_active
#  9     8      reconf_active_slot_id[7:0]
#  10    8      reconf_last_slot_id[7:0]
#  11    64     reconf_cycles[63:0]
#  12    64     reconf_last_cycles[63:0]
#  13    4      reconf_state[3:0]  (reconfctrl state_reg)
#  14    8      reconf_last_error[7:0]
#  15    1      icap_csib            ICAPE3 CSIB pin
#  16    1      icap_rdwrb           ICAPE3 RDWRB pin
#  17    32     icap_o[31:0]         ICAPE3 O status bus
#  18    1      pattern_pr_rx_tvalid c00 s_axis_tvalid
#  19    1      pattern_pr_rx_tready c00 s_axis_tready
#  20    1      pattern_pr_tx_tvalid c00 m_axis_tvalid
#  21    1      pattern_pr_tx_tready c00 m_axis_tready
#  22    1      or_pr_rx_tvalid      c01 s_axis_tvalid
#  23    1      or_pr_rx_tready      c01 s_axis_tready
#  24    1      or_pr_tx_tvalid      c01 m_axis_tvalid
#  25    1      or_pr_tx_tready      c01 m_axis_tready
#  26    1      c02_pr_rx_tvalid     c02 s_axis_tvalid
#  27    1      c02_pr_rx_tready     c02 s_axis_tready
#  28    1      c02_pr_tx_tvalid     c02 m_axis_tvalid
#  29    1      c02_pr_tx_tready     c02 m_axis_tready
#  30    1      disp_expecting_header
#  31    1      disp_config_header_line
#  32    16     disp_header_workload[15:0]
#  33    20     disp_request_bytes_remaining[19:0]
#  34    1      pkt_rx_tvalid        dispatcher rx_tvalid
#  35    1      pkt_rx_tready        dispatcher rx_tready

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_icap
set_property -dict [list \
                        CONFIG.C_NUM_OF_PROBES {36} \
                        CONFIG.C_DATA_DEPTH {8192} \
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
                        CONFIG.C_PROBE7_WIDTH {3} \
                        CONFIG.C_PROBE8_WIDTH {1} \
                        CONFIG.C_PROBE9_WIDTH {8} \
                        CONFIG.C_PROBE10_WIDTH {8} \
                        CONFIG.C_PROBE11_WIDTH {64} \
                        CONFIG.C_PROBE12_WIDTH {64} \
                        CONFIG.C_PROBE13_WIDTH {4} \
                        CONFIG.C_PROBE14_WIDTH {8} \
                        CONFIG.C_PROBE15_WIDTH {1} \
                        CONFIG.C_PROBE16_WIDTH {1} \
                        CONFIG.C_PROBE17_WIDTH {32} \
                        CONFIG.C_PROBE18_WIDTH {1} \
                        CONFIG.C_PROBE19_WIDTH {1} \
                        CONFIG.C_PROBE20_WIDTH {1} \
                        CONFIG.C_PROBE21_WIDTH {1} \
                        CONFIG.C_PROBE22_WIDTH {1} \
                        CONFIG.C_PROBE23_WIDTH {1} \
                        CONFIG.C_PROBE24_WIDTH {1} \
                        CONFIG.C_PROBE25_WIDTH {1} \
                        CONFIG.C_PROBE26_WIDTH {1} \
                        CONFIG.C_PROBE27_WIDTH {1} \
                        CONFIG.C_PROBE28_WIDTH {1} \
                        CONFIG.C_PROBE29_WIDTH {1} \
                        CONFIG.C_PROBE30_WIDTH {1} \
                        CONFIG.C_PROBE31_WIDTH {1} \
                        CONFIG.C_PROBE32_WIDTH {16} \
                        CONFIG.C_PROBE33_WIDTH {20} \
                        CONFIG.C_PROBE34_WIDTH {1} \
                        CONFIG.C_PROBE35_WIDTH {1}
                   ] [get_ips ila_icap]
