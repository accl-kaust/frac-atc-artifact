
create_pblock pblock_cmac_krnl_inst
add_cells_to_pblock [get_pblocks pblock_cmac_krnl_inst] [get_cells -quiet [list frac_inst/cmac_krnl_inst]]
resize_pblock [get_pblocks pblock_cmac_krnl_inst] -add {CLOCKREGION_X0Y8:CLOCKREGION_X1Y11}
# No cell is in SLR2 any more, so static and the cells share SLR0 and SLR1 and
# SLR2 is left to the cmac pblock alone.
#
# Static takes what the three cells leave: SLR0 except the C02 notch at
# X5Y3:X6Y3, and the X0-X4 columns of SLR1 (C00 and C01 hold X5-X7 there).
# Y0-Y2 is taken full width, which is what keeps CONFIG_SITE_X0Y0 -- the only
# site the ICAPE3 may occupy, in clock region X7Y1 -- inside this pblock;
# user_krnl_inst holds the ICAPE3, so losing that site fails place_design with
# [Place 30-1100].
create_pblock pblock_1
add_cells_to_pblock [get_pblocks pblock_1] [get_cells -quiet [list frac_inst/network_krnl_inst frac_inst/sys_rst_inst frac_inst/tcp_open_status_width_conv_inst frac_inst/user_krnl_inst]]
resize_pblock [get_pblocks pblock_1] -add {CLOCKREGION_X0Y0:CLOCKREGION_X7Y2 CLOCKREGION_X0Y3:CLOCKREGION_X4Y3 CLOCKREGION_X7Y3:CLOCKREGION_X7Y3 CLOCKREGION_X0Y4:CLOCKREGION_X4Y7}

set_property C_CLK_INPUT_FREQ_HZ 200000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]
