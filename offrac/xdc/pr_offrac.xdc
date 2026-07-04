set pr_region_site_filter {NAME =~ SLICE_* || NAME =~ DSP48E2_* || NAME =~ RAMB18_* || NAME =~ RAMB36_* || NAME =~ URAM288_* || NAME =~ LAGUNA_*}

create_pblock pblock_c02_bbx_inst
add_cells_to_pblock [get_pblocks pblock_c02_bbx_inst] [get_cells -quiet [list offrac_inst/user_krnl_inst/ipcore_top_top_k_inst/top_instance/pkt_logic_inst/c02_bbx_inst]]
resize_pblock [get_pblocks pblock_c02_bbx_inst] -add [get_sites -quiet -of_objects [get_clock_regions {X4Y0 X5Y0 X6Y0 X7Y0 X4Y1 X5Y1 X6Y1 X7Y1 X4Y2 X5Y2 X6Y2 X7Y2 X4Y3 X5Y3 X6Y3 X7Y3}] -filter $pr_region_site_filter]
set_property RESET_AFTER_RECONFIG true [get_pblocks pblock_c02_bbx_inst]
set_property SNAPPING_MODE ON [get_pblocks pblock_c02_bbx_inst]
set_property IS_SOFT FALSE [get_pblocks pblock_c02_bbx_inst]
set_property HD.RECONFIGURABLE true [get_cells -hierarchical -filter {NAME =~ *c02_bbx_inst}]
create_pblock pblock_c01_bbx_inst
add_cells_to_pblock [get_pblocks pblock_c01_bbx_inst] [get_cells -quiet [list offrac_inst/user_krnl_inst/ipcore_top_top_k_inst/top_instance/pkt_logic_inst/c01_bbx_inst]]
resize_pblock [get_pblocks pblock_c01_bbx_inst] -add [get_sites -quiet -of_objects [get_clock_regions {X3Y6 X4Y6 X5Y6 X6Y6 X7Y6 X3Y7 X4Y7 X5Y7 X6Y7 X7Y7}] -filter $pr_region_site_filter]
set_property RESET_AFTER_RECONFIG true [get_pblocks pblock_c01_bbx_inst]
set_property SNAPPING_MODE ON [get_pblocks pblock_c01_bbx_inst]
set_property IS_SOFT FALSE [get_pblocks pblock_c01_bbx_inst]
set_property HD.RECONFIGURABLE true [get_cells -hierarchical -filter {NAME =~ *c01_bbx_inst}]
create_pblock pblock_c00_bbx_inst
add_cells_to_pblock [get_pblocks pblock_c00_bbx_inst] [get_cells -quiet [list offrac_inst/user_krnl_inst/ipcore_top_top_k_inst/top_instance/pkt_logic_inst/c00_bbx_inst]]
resize_pblock [get_pblocks pblock_c00_bbx_inst] -add [get_sites -quiet -of_objects [get_clock_regions {X2Y8 X3Y8 X4Y8 X5Y8 X6Y8 X7Y8 X2Y9 X3Y9 X4Y9 X5Y9 X6Y9 X7Y9 X2Y10 X3Y10 X4Y10 X5Y10 X6Y10 X7Y10 X2Y11 X3Y11 X4Y11 X5Y11 X6Y11 X7Y11}] -filter $pr_region_site_filter]
set_property RESET_AFTER_RECONFIG true [get_pblocks pblock_c00_bbx_inst]
set_property SNAPPING_MODE ON [get_pblocks pblock_c00_bbx_inst]
set_property IS_SOFT FALSE [get_pblocks pblock_c00_bbx_inst]
set_property HD.RECONFIGURABLE true [get_cells -hierarchical -filter {NAME =~ *c00_bbx_inst}]
set_property C_CLK_INPUT_FREQ_HZ 200000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]
