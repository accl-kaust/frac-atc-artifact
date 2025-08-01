
create_pblock pblock_cmac_krnl_inst
add_cells_to_pblock [get_pblocks pblock_cmac_krnl_inst] [get_cells -quiet [list offrac_inst/cmac_krnl_inst]]
resize_pblock [get_pblocks pblock_cmac_krnl_inst] -add {CLOCKREGION_X0Y8:CLOCKREGION_X1Y11}
create_pblock pblock_1
add_cells_to_pblock [get_pblocks pblock_1] [get_cells -quiet [list offrac_inst/network_krnl_inst offrac_inst/sys_rst_inst offrac_inst/tcp_open_status_width_conv_inst offrac_inst/user_krnl_inst]]
resize_pblock [get_pblocks pblock_1] -add {CLOCKREGION_X0Y0:CLOCKREGION_X2Y7 CLOCKREGION_X3Y0:CLOCKREGION_X3Y3}

set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]
