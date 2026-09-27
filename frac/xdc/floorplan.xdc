
create_pblock pblock_cmac_krnl_inst
add_cells_to_pblock [get_pblocks pblock_cmac_krnl_inst] [get_cells -quiet [list frac_inst/cmac_krnl_inst]]
resize_pblock [get_pblocks pblock_cmac_krnl_inst] -add {CLOCKREGION_X0Y8:CLOCKREGION_X1Y11}
# Static owns the left half of SLR0 (X0-X3), the X4-X7 strip at Y1, and SLR1
# less the two reconfigurable cells (spinhdl.yaml): C00 at X6Y6:X7Y7 and C01
# at X5Y4:X7Y4. The strip is not optional: CONFIG_SITE_X0Y0 -- the only site
# the ICAPE3 may occupy -- lives in clock region X7Y1, and user_krnl_inst
# (which holds the ICAPE3) is confined to this pblock, so the strip must
# contain it or place_design fails with [Place 30-1100]. Each cell keeps
# static on two sides for its slot boundary logic: C00 has X5Y6:X5Y7 and
# X6Y5:X7Y5, C01 has X4Y4 and X5Y5:X7Y5. Keep the two files consistent.
create_pblock pblock_1
add_cells_to_pblock [get_pblocks pblock_1] [get_cells -quiet [list frac_inst/network_krnl_inst frac_inst/sys_rst_inst frac_inst/tcp_open_status_width_conv_inst frac_inst/user_krnl_inst]]
resize_pblock [get_pblocks pblock_1] -add {CLOCKREGION_X0Y0:CLOCKREGION_X3Y3 CLOCKREGION_X4Y1:CLOCKREGION_X7Y1 CLOCKREGION_X0Y4:CLOCKREGION_X4Y4 CLOCKREGION_X0Y5:CLOCKREGION_X7Y5 CLOCKREGION_X0Y6:CLOCKREGION_X5Y7}

# The debug hub stays although no ILA or VIO is left: the HBM IP carries a
# debug core of its own (hbm_0_inst, for the Hardware Manager's HBM monitor),
# so Vivado still inserts dbg_hub, and without a clock on it opt_design fails
# with [Chipscope 16-213] "The debug port 'dbg_hub/clk' has 1 unconnected
# channels".
set_property C_CLK_INPUT_FREQ_HZ 200000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]
