# Xilinx IP for the `norm` reconfigurable module: y = (x - min) / (max - min).
#
# This is an IN-PROJECT script. spinhdl's generated create_project.tcl sources
# it into the unit's project (it is named under `ip:` in spin.yaml and in this
# unit's unit.yaml), so it must create IP and nothing else: no create_project,
# no close_project, no writing .xci files out by hand.
#
# It used to be a standalone generator that opened a throwaway project of its
# own, harvested the .xci files and deleted the project. Sourced into a real
# one, that closed the caller's project out from under it and left no IP behind,
# so `norm` synthesised against an empty catalogue and died at
#     ERROR: [Synth 8-439] module 'floating_point_0' not found  [norm.v:160]
# with create_project still reporting success. Every other IP tcl in this tree
# (cmac.tcl, network_stack.tcl, hbm_0.tcl) is in-project; this one was the
# exception.
#
# Generation and out-of-context synthesis of the IP are the caller's job.
# spinhdl's run_synth.tcl does `generate_target all [get_ips]` followed by
# `synth_ip [get_ips]` before it elaborates the RTL, so adding the IP here is
# the whole contract.
#
# Only what norm.v instantiates is created -- two cores, not the fifteen the
# shared copy of this file used to build. There is no comparator IP: norm orders
# floats with the `fkey` total-ordering trick in pure logic, which is why the
# two-pass min/max costs no DSP.
#
# Add_Sub_Value defaults to `Both`, which grows a third input channel
# (s_axis_operation_*) to pick add or subtract per transaction. norm never
# connected it, so opt_design trimmed the undriven channel inside the abstract
# shell and took an input off the LUT combining the three handshakes:
# ERROR: [Opt 31-67] on need_combiner.use_3to1.skid_buffer_combiner -- `3to1`
# being A, B and OPERATION. Pinning it to Subtract removes the channel entirely.
# Out-of-context synthesis never saw this; only linking into the shell did.
#
# Neither core carries tlast either. norm drove s_axis_b_tlast with a constant
# 1'b1 and left m_axis_result_tlast open, so that path fed nothing and is gone.
# That was dead logic worth removing, but it was NOT the cause of the error
# above.

# ── floating_point_0 — subtract, latency 12 ──────────────────────────────────
# Shared between the two passes (norm.v:160): `a` is muxed between max_val and
# the value being normalised, `b` is always min_val.
create_ip -name floating_point \
          -vendor xilinx.com -library ip -version 7.1 \
          -module_name floating_point_0
set_property -dict [list \
    CONFIG.Operation_Type        {Add_Subtract} \
    CONFIG.Add_Sub_Value         {Subtract}     \
    CONFIG.C_Latency             {12}           \
    CONFIG.Maximum_Latency       {false}        \
    CONFIG.C_Mult_Usage          {Full_Usage}   \
    CONFIG.Result_Precision_Type {Single}       \
    CONFIG.Flow_Control          {Blocking}     \
    CONFIG.Has_RESULT_TREADY     {true}         \
] [get_ips floating_point_0]

# ── floating_point_3 — divide, latency 29 (norm.v:182) ───────────────────────
# Same configuration as log's floating_point_1, kept under its own module name
# because the two units are separate reconfigurable modules and each names the
# core its own RTL instantiates.
create_ip -name floating_point \
          -vendor xilinx.com -library ip -version 7.1 \
          -module_name floating_point_3
set_property -dict [list \
    CONFIG.Operation_Type        {Divide}   \
    CONFIG.C_Latency             {29}       \
    CONFIG.Maximum_Latency       {false}    \
    CONFIG.C_Mult_Usage          {No_Usage} \
    CONFIG.Result_Precision_Type {Single}   \
    CONFIG.Flow_Control          {Blocking} \
    CONFIG.Has_RESULT_TREADY     {true}     \
] [get_ips floating_point_3]
