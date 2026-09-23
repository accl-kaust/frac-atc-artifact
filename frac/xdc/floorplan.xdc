
create_pblock pblock_cmac_krnl_inst
add_cells_to_pblock [get_pblocks pblock_cmac_krnl_inst] [get_cells -quiet [list frac_inst/cmac_krnl_inst]]
resize_pblock [get_pblocks pblock_cmac_krnl_inst] -add {CLOCKREGION_X0Y8:CLOCKREGION_X1Y11}
# Static owns the left half of SLR0 (X0-X3), the whole of SLR1, and what is
# left of the Y1 row once C02 takes X5Y1:X6Y1 -- that is, X4Y1 and X7Y1.
#
# Keeping X7Y1 is not optional: CONFIG_SITE_X0Y0, the only site the ICAPE3 may
# occupy, lives in that clock region, and user_krnl_inst (which holds the
# ICAPE3) is confined to this pblock, so dropping it fails place_design with
# [Place 30-1100].
#
# The three reconfigurable cells sit in the notch left open here -- SLR0 at
# X5Y1, X5Y2 and X5Y3, each two clock regions wide (spinhdl.yaml). Keep the two
# files consistent.
create_pblock pblock_1
add_cells_to_pblock [get_pblocks pblock_1] [get_cells -quiet [list frac_inst/network_krnl_inst frac_inst/sys_rst_inst frac_inst/tcp_open_status_width_conv_inst frac_inst/user_krnl_inst]]
resize_pblock [get_pblocks pblock_1] -add {CLOCKREGION_X0Y0:CLOCKREGION_X3Y3 CLOCKREGION_X4Y1:CLOCKREGION_X4Y1 CLOCKREGION_X7Y1:CLOCKREGION_X7Y1 CLOCKREGION_X0Y4:CLOCKREGION_X7Y7}

set_property C_CLK_INPUT_FREQ_HZ 200000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]
