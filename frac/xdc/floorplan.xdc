
create_pblock pblock_cmac_krnl_inst
add_cells_to_pblock [get_pblocks pblock_cmac_krnl_inst] [get_cells -quiet [list frac_inst/cmac_krnl_inst]]
resize_pblock [get_pblocks pblock_cmac_krnl_inst] -add {CLOCKREGION_X0Y8:CLOCKREGION_X1Y11}
# No static pblock, deliberately. The cmac block above is the only floorplan
# constraint on static logic; network_krnl_inst, sys_rst_inst,
# tcp_open_status_width_conv_inst and user_krnl_inst are left unconstrained and
# the placer spreads them wherever it likes, around the reconfigurable cells.
#
# This matches the one design in the campaign that ever reconfigured on
# hardware: reconf_hdr_frmt's floorplan.xdc names pblock_1 in two
# resize_pblock lines but never creates it, so those lines are inert and its
# static logic is unconstrained. Every conservative sibling that DOES define a
# real pblock_1 (pr, pr_2, wo_pr_feedback, reg_icap_feedback_pblock) is in the
# non-working camp. Build 4544 is this same design WITH a static pblock, so the
# pair differs in exactly this one variable.
#
# Leaving user_krnl_inst unconstrained also removes the [Place 30-1100] risk
# around the ICAPE3: its only legal site, CONFIG_SITE_X0Y0 in clock region
# X7Y1, can no longer fall outside an area constraint.

set_property C_CLK_INPUT_FREQ_HZ 200000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]
