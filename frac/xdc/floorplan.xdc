
create_pblock pblock_cmac_krnl_inst
add_cells_to_pblock [get_pblocks pblock_cmac_krnl_inst] [get_cells -quiet [list frac_inst/cmac_krnl_inst]]
resize_pblock [get_pblocks pblock_cmac_krnl_inst] -add {CLOCKREGION_X0Y8:CLOCKREGION_X1Y11}
# No static pblock: there are no reconfigurable cells to carve it around and
# no ICAPE3 site for it to reach, so the placer has the whole device. Only
# the CMAC stays pinned beside its transceivers.

# The debug hub stays although no ILA or VIO is left: the HBM IP carries a
# debug core of its own (hbm_0_inst, for the Hardware Manager's HBM monitor),
# so Vivado still inserts dbg_hub, and without a clock on it opt_design fails
# with [Chipscope 16-213] "The debug port 'dbg_hub/clk' has 1 unconnected
# channels".
set_property C_CLK_INPUT_FREQ_HZ 200000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]
