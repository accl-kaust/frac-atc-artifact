# gen_ip.tcl
# Regenerates all Xilinx IP XCI files required by offrac_krnl.
#
# Usage:
#   vivado -mode batch -source gen_ip.tcl
#   vivado -mode batch -source gen_ip.tcl -tclargs <part>
#
# Default part: xcu280-fsvh2892-2L-e (Alveo U280)

set part "xcu280-fsvh2892-2L-e"
if {[llength $argv] > 0} {
    set part [lindex $argv 0]
}

set out_dir [file normalize [file dirname [info script]]]
set tmp_dir [file join $out_dir ip_gen_tmp]

puts "Generating IPs for part: $part"
puts "Output directory:        $out_dir"

# ── Create temporary project ──────────────────────────────────────────────────
create_project -force ip_gen_tmp $tmp_dir -part $part

# ── Helper: axis_data_fifo ────────────────────────────────────────────────────
proc make_axis_fifo {name tdata_bytes fifo_depth} {
    create_ip -name axis_data_fifo \
              -vendor xilinx.com -library ip -version 2.0 \
              -module_name $name
    set_property -dict [list \
        CONFIG.TDATA_NUM_BYTES $tdata_bytes \
        CONFIG.FIFO_DEPTH      $fifo_depth  \
    ] [get_ips $name]
}

make_axis_fifo  axis_data_fifo_0        71   4096
make_axis_fifo  axis_data_fifo_1        71  16384
make_axis_fifo  axis_data_fifo_2        75    512
make_axis_fifo  axis_data_fifo_3        69   1024
make_axis_fifo  axis_data_fifo_16        2     64
make_axis_fifo  axis_data_fifo_32        4    512
make_axis_fifo  axis_data_fifo_32_long   6  16384
make_axis_fifo  axis_data_fifo_40        5   8192
make_axis_fifo  axis_data_fifo_88       11    512
make_axis_fifo  axis_data_fifo_513      65    512

# ── floating_point_0  (Add/Subtract, latency=12, Full_Usage DSPs) ─────────────
create_ip -name floating_point \
          -vendor xilinx.com -library ip -version 7.1 \
          -module_name floating_point_0
set_property -dict [list \
    CONFIG.Operation_Type        {Add_Subtract} \
    CONFIG.C_Latency             {12}           \
    CONFIG.Maximum_Latency       {false}        \
    CONFIG.C_Mult_Usage          {Full_Usage}   \
    CONFIG.Result_Precision_Type {Single}       \
    CONFIG.Flow_Control          {Blocking}     \
    CONFIG.Has_B_TLAST           {true}         \
    CONFIG.Has_RESULT_TREADY     {true}         \
] [get_ips floating_point_0]

# ── floating_point_1  (Divide, latency=29) ────────────────────────────────────
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

# ── floating_point_2  (Logarithm, latency=23, Medium_Usage DSPs) ─────────────
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

# ── floating_point_3  (Divide, latency=29) ────────────────────────────────────
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

# ── Max_comparator  (Compare / Condition_Code, latency=3, 8-bit result) ───────
create_ip -name floating_point \
          -vendor xilinx.com -library ip -version 7.1 \
          -module_name Max_comparator
set_property -dict [list \
    CONFIG.Operation_Type          {Compare}        \
    CONFIG.C_Compare_Operation     {Condition_Code} \
    CONFIG.C_Latency               {3}              \
    CONFIG.Maximum_Latency         {false}          \
    CONFIG.C_Mult_Usage            {No_Usage}       \
    CONFIG.Result_Precision_Type   {Custom}         \
    CONFIG.C_Result_Exponent_Width {4}              \
    CONFIG.C_Result_Fraction_Width {0}              \
    CONFIG.Flow_Control            {Blocking}       \
    CONFIG.Has_A_TLAST             {true}           \
    CONFIG.Has_RESULT_TREADY       {true}           \
] [get_ips Max_comparator]

# ── Copy XCI files to offrac directory ───────────────────────────────────────
set ip_names {
    axis_data_fifo_0
    axis_data_fifo_1
    axis_data_fifo_2
    axis_data_fifo_3
    axis_data_fifo_16
    axis_data_fifo_32
    axis_data_fifo_32_long
    axis_data_fifo_40
    axis_data_fifo_88
    axis_data_fifo_513
    floating_point_0
    floating_point_1
    floating_point_2
    floating_point_3
    Max_comparator
}

foreach name $ip_names {
    set xci_files [get_files -of_objects [get_ips $name] -filter {FILE_TYPE == "IP"}]
    if {[llength $xci_files] > 0} {
        set src [lindex $xci_files 0]
        file copy -force $src [file join $out_dir ${name}.xci]
        puts "  wrote ${name}.xci"
    } else {
        puts "WARNING: XCI not found for $name"
    }
}

# ── Clean up ──────────────────────────────────────────────────────────────────
close_project
file delete -force $tmp_dir

puts "\nDone. All XCI files written to:\n  $out_dir"
