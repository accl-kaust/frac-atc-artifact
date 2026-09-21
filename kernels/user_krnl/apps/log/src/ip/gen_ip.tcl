# Xilinx IP for the `log` reconfigurable module: y = ln(x / (1 - x)).
#
# This is an IN-PROJECT script. spinhdl's generated create_project.tcl sources
# it into the unit's project (it is named under `ip:` in spin.yaml and in this
# unit's unit.yaml), so it must create IP and nothing else: no create_project,
# no close_project, no writing .xci files out by hand.
#
# It used to be a standalone generator that opened a throwaway project of its
# own, harvested the .xci files and deleted the project. Sourced into a real
# one, that closed the caller's project out from under it and left no IP behind,
# so `log` synthesised against an empty catalogue and died at
#     ERROR: [Synth 8-439] module 'floating_point_0' not found  [log.v:87]
# with create_project still reporting success. Every other IP tcl in this tree
# (cmac.tcl, network_stack.tcl, hbm_0.tcl) is in-project; this one was the
# exception.
#
# Generation and out-of-context synthesis of the IP are the caller's job.
# spinhdl's run_synth.tcl does `generate_target all [get_ips]` followed by
# `synth_ip [get_ips]` before it elaborates the RTL, so adding the IP here is
# the whole contract.
#
# Only what log.v instantiates is created, and none of the three carries tlast.
#
# Add_Sub_Value is the line that matters, and it defaults to `Both`. With
# `Both`, the core grows a THIRD input channel -- s_axis_operation_tvalid /
# _tready / _tdata -- to pick add or subtract per transaction. Neither log.v nor
# norm.v ever connected it, so opt_design trimmed the undriven channel inside
# the abstract shell and took an input off the LUT that combines the three
# channels' handshakes:
#     ERROR: [Opt 31-67] A LUT4 cell in the design is missing a connection on
#     input pin I0 ... need_combiner.use_3to1.skid_buffer_combiner ...
#     the connection was removed due to the trimming of unused logic
# `use_3to1` is the tell: A, B and OPERATION. Pinning the operation removes the
# channel, so there is nothing to leave dangling. Out-of-context synthesis never
# saw this -- the RM's boundary kept the port alive; only linking it into the
# shell exposed it.
#
# floating_point_0 also carried Has_B_TLAST until this was investigated. That
# was dead logic on its own merits -- s_axis_b_tlast was driven, but
# m_axis_result_tlast was left open and the RTL derives m_axis_tlast from its
# own resp_last -- so it is gone, and all three cores are now tlast-free. It was
# not the cause of the error above; removing it changed nothing.
# tb/fp_stubs.v mirrors these port lists exactly.

# ── floating_point_0 — subtract, latency 12 (log.v:87, 1.0 - x) ───────────────
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

# ── floating_point_1 — divide, latency 29 (log.v:147, x / (1 - x)) ────────────
create_ip -name floating_point \
          -vendor xilinx.com -library ip -version 7.1 \
          -module_name floating_point_1
set_property -dict [list \
    CONFIG.Operation_Type        {Divide}   \
    CONFIG.C_Latency             {29}       \
    CONFIG.Maximum_Latency       {false}    \
    CONFIG.C_Mult_Usage          {No_Usage} \
    CONFIG.Result_Precision_Type {Single}   \
    CONFIG.Flow_Control          {Blocking} \
    CONFIG.Has_RESULT_TREADY     {true}     \
] [get_ips floating_point_1]

# ── floating_point_2 — natural log, latency 23 (log.v:165) ───────────────────
create_ip -name floating_point \
          -vendor xilinx.com -library ip -version 7.1 \
          -module_name floating_point_2
set_property -dict [list \
    CONFIG.Operation_Type        {Logarithm}    \
    CONFIG.C_Latency             {23}           \
    CONFIG.Maximum_Latency       {false}        \
    CONFIG.C_Mult_Usage          {Medium_Usage} \
    CONFIG.Result_Precision_Type {Single}       \
    CONFIG.Flow_Control          {Blocking}     \
    CONFIG.Has_RESULT_TREADY     {true}         \
] [get_ips floating_point_2]
