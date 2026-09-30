# AXI clock converters, and the register slices that go with them, in front of
# the HBM (frac_hbm.v). The masters -- the TCP stack's two memory ports and the
# reconfiguration controller -- run on the 200 MHz design clock; the HBM AXI
# ports and the width and protocol converters before them run on the 400 MHz
# HBM AXI clock.
#
# The conversion happens at 512 bits, before the 512->256 width converter, so
# the HBM port carries 256 b x 400 MHz = 12.8 GB/s: the whole 512 b x 200 MHz
# stream. Converting after the width converter would leave the port at 256 b x
# 200 MHz, 6.4 GB/s, which is the limit this replaces.

# m00_axi (TX buffer) and m01_axi (RX buffer, idle with RX_DDR_BYPASS)
create_ip -name axi_clock_converter -vendor xilinx.com -library ip -module_name axi_clock_conv_512

set_property -dict [list \
                        CONFIG.PROTOCOL {AXI4} \
                        CONFIG.ADDR_WIDTH {64} \
                        CONFIG.DATA_WIDTH {512} \
                        CONFIG.ID_WIDTH {0} \
                        CONFIG.ACLK_ASYNC {1} \
                        CONFIG.READ_WRITE_MODE {READ_WRITE}
                   ] [get_ips axi_clock_conv_512]

# reconfctrl's HBM master: 256 b, 33-bit addresses, 6-bit IDs, bursts of at
# most 16 beats (the HBM port is AXI3)
create_ip -name axi_clock_converter -vendor xilinx.com -library ip -module_name axi_clock_conv_reconf

set_property -dict [list \
                        CONFIG.PROTOCOL {AXI4} \
                        CONFIG.ADDR_WIDTH {33} \
                        CONFIG.DATA_WIDTH {256} \
                        CONFIG.ID_WIDTH {6} \
                        CONFIG.ACLK_ASYNC {1} \
                        CONFIG.READ_WRITE_MODE {READ_WRITE}
                   ] [get_ips axi_clock_conv_reconf]

# Between each protocol converter and its HBM port: AXI3 like the port, 33-bit
# addresses, every channel fully registered, so the HBM's late outputs and its
# ready inputs only ever meet a flop
create_ip -name axi_register_slice -vendor xilinx.com -library ip -module_name axi_reg_slice_hbm

set_property -dict [list \
                        CONFIG.PROTOCOL {AXI3} \
                        CONFIG.ADDR_WIDTH {33} \
                        CONFIG.DATA_WIDTH {256} \
                        CONFIG.ID_WIDTH {0} \
                        CONFIG.REG_AW {1} \
                        CONFIG.REG_AR {1} \
                        CONFIG.REG_W {1} \
                        CONFIG.REG_R {1} \
                        CONFIG.REG_B {1}
                   ] [get_ips axi_reg_slice_hbm]

# Between each width converter and its protocol converter: every channel fully
# registered, so neither converter's logic shares a cycle with the other's
create_ip -name axi_register_slice -vendor xilinx.com -library ip -module_name axi_reg_slice_256

set_property -dict [list \
                        CONFIG.PROTOCOL {AXI4} \
                        CONFIG.ADDR_WIDTH {64} \
                        CONFIG.DATA_WIDTH {256} \
                        CONFIG.ID_WIDTH {0} \
                        CONFIG.REG_AW {1} \
                        CONFIG.REG_AR {1} \
                        CONFIG.REG_W {1} \
                        CONFIG.REG_R {1} \
                        CONFIG.REG_B {1}
                   ] [get_ips axi_reg_slice_256]

# Between each clock converter and its width converter: only the read channel
# is registered, in front of the clock converter's read FIFO write enable
create_ip -name axi_register_slice -vendor xilinx.com -library ip -module_name axi_reg_slice_512_r

set_property -dict [list \
                        CONFIG.PROTOCOL {AXI4} \
                        CONFIG.ADDR_WIDTH {64} \
                        CONFIG.DATA_WIDTH {512} \
                        CONFIG.ID_WIDTH {0} \
                        CONFIG.REG_AW {0} \
                        CONFIG.REG_AR {0} \
                        CONFIG.REG_W {0} \
                        CONFIG.REG_R {1} \
                        CONFIG.REG_B {0}
                   ] [get_ips axi_reg_slice_512_r]
