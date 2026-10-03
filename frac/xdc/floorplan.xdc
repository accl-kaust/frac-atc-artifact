
create_pblock pblock_cmac_krnl_inst
add_cells_to_pblock [get_pblocks pblock_cmac_krnl_inst] [get_cells -quiet [list frac_inst/cmac_krnl_inst]]
resize_pblock [get_pblocks pblock_cmac_krnl_inst] -add {CLOCKREGION_X0Y8:CLOCKREGION_X1Y11}
# Static owns the left half of SLR0 (X0-X3) with X4Y2:X4Y3 and the X4-X7 strip
# at Y1, X0-X3 of SLR1 with the left of X4 (SLICE_X117:X120 and RAMB X8 here),
# and X2-X4 of SLR2 right of the cmac pblock. The four reconfigurable cells
# (spinhdl.yaml) run down the right of the device: C00 at X5Y10:X7Y11 and C01
# at X5Y8:X7Y9 in SLR2, C02 from SLICE_X121 to the right edge, the full height
# of SLR1, and C03 at X5Y2:X7Y3 in SLR0. The strip is not optional:
# CONFIG_SITE_X0Y0 -- the only site the ICAPE3 may occupy -- lives in clock
# region X7Y1, and user_krnl_inst (which holds the ICAPE3) is confined to this
# pblock, so the strip must contain it or place_design fails with
# [Place 30-1100]. Every cell has static on its left for its slot boundary
# logic, column X4 for C00, C01 and C03 and X3 with the left of X4 for C02,
# and C03 also has the strip below. X4Y0 and X5Y0:X7Y0, along the HBM ports,
# stay outside every pblock. The pinned I/O are in X4Y1, X4Y5 and X4Y11, the
# QSFP GTs in X0Y10. X4Y5's are clk_100mhz_1, which feeds main_clk_mmcm_inst
# in the clocking column beside them: that is why C02 starts right of it.
# Keep the two files consistent.
create_pblock pblock_1
add_cells_to_pblock [get_pblocks pblock_1] [get_cells -quiet [list frac_inst/network_krnl_inst frac_inst/sys_rst_inst frac_inst/tcp_open_status_width_conv_inst frac_inst/user_krnl_inst]]
resize_pblock [get_pblocks pblock_1] -add {CLOCKREGION_X0Y0:CLOCKREGION_X3Y3 CLOCKREGION_X4Y1:CLOCKREGION_X7Y1 CLOCKREGION_X4Y2:CLOCKREGION_X4Y3 CLOCKREGION_X0Y4:CLOCKREGION_X3Y7 SLICE_X117Y240:SLICE_X120Y479 RAMB18_X8Y96:RAMB18_X8Y191 RAMB36_X8Y48:RAMB36_X8Y95 CLOCKREGION_X2Y8:CLOCKREGION_X4Y11}

# The debug hub stays although no ILA or VIO is left: the HBM IP carries a
# debug core of its own (hbm_0_inst, for the Hardware Manager's HBM monitor),
# so Vivado still inserts dbg_hub, and without a clock on it opt_design fails
# with [Chipscope 16-213] "The debug port 'dbg_hub/clk' has 1 unconnected
# channels".
set_property C_CLK_INPUT_FREQ_HZ 200000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]
