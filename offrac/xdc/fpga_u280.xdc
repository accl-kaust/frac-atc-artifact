set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.CONFIG.CONFIGFALLBACK ENABLE [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 85.0 [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN DISABLE [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.OVERTEMPSHUTDOWN Enable [current_design]

set_operating_conditions -design_power_budget 160

#100 MHz
set_property -dict {LOC BJ43 IOSTANDARD LVDS} [get_ports clk_100mhz_0_p]
set_property -dict {LOC BJ44 IOSTANDARD LVDS} [get_ports clk_100mhz_0_n]
create_clock -period 10.000 -name clk_100mhz_0 [get_ports clk_100mhz_0_p]

# 100 MHz
set_property -dict {LOC BH6 IOSTANDARD LVDS} [get_ports clk_100mhz_1_p]
set_property -dict {LOC BJ6 IOSTANDARD LVDS} [get_ports clk_100mhz_1_n]
create_clock -period 10.000 -name clk_100mhz_1 [get_ports clk_100mhz_1_p]

set_property -dict {LOC L53} [get_ports {qsfp0_rx_p[0]}]
set_property -dict {LOC L54} [get_ports {qsfp0_rx_n[0]}]
set_property -dict {LOC L48} [get_ports {qsfp0_tx_p[0]}]
set_property -dict {LOC L49} [get_ports {qsfp0_tx_n[0]}]
set_property -dict {LOC K51} [get_ports {qsfp0_rx_p[1]}]
set_property -dict {LOC K52} [get_ports {qsfp0_rx_n[1]}]
set_property -dict {LOC L44} [get_ports {qsfp0_tx_p[1]}]
set_property -dict {LOC L45} [get_ports {qsfp0_tx_n[1]}]
set_property -dict {LOC J53} [get_ports {qsfp0_rx_p[2]}]
set_property -dict {LOC J54} [get_ports {qsfp0_rx_n[2]}]
set_property -dict {LOC K46} [get_ports {qsfp0_tx_p[2]}]
set_property -dict {LOC K47} [get_ports {qsfp0_tx_n[2]}]
set_property -dict {LOC H51} [get_ports {qsfp0_rx_p[3]}]
set_property -dict {LOC H52} [get_ports {qsfp0_rx_n[3]}]
set_property -dict {LOC J48} [get_ports {qsfp0_tx_p[3]}]
set_property -dict {LOC J49} [get_ports {qsfp0_tx_n[3]}]
set_property -dict {LOC T42} [get_ports qsfp0_mgt_refclk_1_p]
set_property -dict {LOC T43} [get_ports qsfp0_mgt_refclk_1_n]
#set_property -dict {LOC R40} [get_ports qsfp0_mgt_refclk_1_p]
#set_property -dict {LOC R41} [get_ports qsfp0_mgt_refclk_1_n]
set_property -dict {LOC H32 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports qsfp0_refclk_oe_b]
set_property -dict {LOC G32 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 8} [get_ports qsfp0_refclk_fs]

# 156.25 MHz MGT reference clock (from SI546, fs = 0)
create_clock -period 6.400 -name qsfp0_mgt_refclk_1 [get_ports qsfp0_mgt_refclk_1_p]

# 161.1328125 MHz MGT reference clock (from SI546, fs = 1)
#create_clock -period 6.206 -name qsfp0_mgt_refclk_1 [get_ports qsfp0_mgt_refclk_1_p]

set_false_path -to [get_ports {qsfp0_refclk_oe_b qsfp0_refclk_fs}]
set_output_delay 0.000 [get_ports {qsfp0_refclk_oe_b qsfp0_refclk_fs}]

set_property PACKAGE_PIN K28 [get_ports {msp_gpio[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {msp_gpio[0]}]
set_property PACKAGE_PIN J29 [get_ports {msp_gpio[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {msp_gpio[1]}]
set_property PACKAGE_PIN K29 [get_ports {msp_gpio[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {msp_gpio[2]}]
set_property PACKAGE_PIN J31 [get_ports {msp_gpio[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {msp_gpio[3]}]
set_property -dict {LOC D29 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 4} [get_ports msp_uart_txd]
set_property -dict {LOC E28 IOSTANDARD LVCMOS18} [get_ports msp_uart_rxd]

set_false_path -to [get_ports msp_uart_txd]
set_output_delay 0.000 [get_ports msp_uart_txd]
set_false_path -from [get_ports {{msp_gpio[*]} msp_uart_rxd}]
set_input_delay 0.000 [get_ports {{msp_gpio[*]} msp_uart_rxd}]


