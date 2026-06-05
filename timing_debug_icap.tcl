set rpt_dir ./timing_debug
file mkdir $rpt_dir

proc require_nonempty {name objects} {
    set count [llength $objects]
    puts "$name = $count"
    if {$count == 0} {
        puts "WARNING: $name is empty"
    }
}

set icap_clk_pin [get_pins -hier -quiet -filter {REF_PIN_NAME == CLK && NAME =~ *icap_ctrl_inst/ICAPE3_inst/CLK}]
set prerror_pin  [get_pins -hier -quiet -filter {NAME =~ *icap_ctrl_inst/ICAPE3_inst/PRERROR}]
set prdone_pin   [get_pins -hier -quiet -filter {NAME =~ *icap_ctrl_inst/ICAPE3_inst/PRDONE}]

set reconf_regs [get_cells -hier -quiet -filter {IS_SEQUENTIAL && NAME =~ *reconfctrl_inst/*}]
set m_axi_regs  [get_cells -hier -quiet -filter {IS_SEQUENTIAL && NAME =~ *reconfctrl_inst/m_axi_*}]
set m_axis_regs [get_cells -hier -quiet -filter {IS_SEQUENTIAL && NAME =~ *reconfctrl_inst/m_axis_*}]
set ctrl_regs   [get_cells -hier -quiet -filter {IS_SEQUENTIAL && NAME =~ *reconfctrl_inst/* && !(NAME =~ *reconfctrl_inst/m_axi_*) && !(NAME =~ *reconfctrl_inst/m_axis_*)}]

require_nonempty icap_clk_pin $icap_clk_pin
require_nonempty prerror_pin $prerror_pin
require_nonempty prdone_pin $prdone_pin
require_nonempty reconf_regs $reconf_regs
require_nonempty m_axi_regs $m_axi_regs
require_nonempty m_axis_regs $m_axis_regs
require_nonempty ctrl_regs $ctrl_regs

report_clocks \
  -file $rpt_dir/clocks.rpt

report_clock_networks \
  -file $rpt_dir/clock_networks.rpt

report_clock_interaction \
  -file $rpt_dir/clock_interaction.rpt

report_timing_summary \
  -delay_type max \
  -report_unconstrained \
  -check_timing_verbose \
  -file $rpt_dir/timing_summary.rpt

if {[llength $icap_clk_pin] && [llength $reconf_regs]} {
    report_timing \
      -from $icap_clk_pin \
      -to $reconf_regs \
      -slack_lesser_than 0 \
      -max_paths 200 \
      -input_pins \
      -nets \
      -sort_by group \
      -name icap_to_reconfctrl \
      -file $rpt_dir/icap_to_reconfctrl.rpt
}

if {[llength $icap_clk_pin] && [llength $m_axi_regs]} {
    report_timing \
      -from $icap_clk_pin \
      -to $m_axi_regs \
      -slack_lesser_than 0 \
      -max_paths 100 \
      -input_pins \
      -nets \
      -name icap_to_reconfctrl_m_axi \
      -file $rpt_dir/icap_to_reconfctrl_m_axi.rpt
}

if {[llength $icap_clk_pin] && [llength $m_axis_regs]} {
    report_timing \
      -from $icap_clk_pin \
      -to $m_axis_regs \
      -slack_lesser_than 0 \
      -max_paths 100 \
      -input_pins \
      -nets \
      -name icap_to_reconfctrl_m_axis \
      -file $rpt_dir/icap_to_reconfctrl_m_axis.rpt
}

if {[llength $icap_clk_pin] && [llength $ctrl_regs]} {
    report_timing \
      -from $icap_clk_pin \
      -to $ctrl_regs \
      -slack_lesser_than 0 \
      -max_paths 100 \
      -input_pins \
      -nets \
      -name icap_to_reconfctrl_ctrl \
      -file $rpt_dir/icap_to_reconfctrl_ctrl.rpt
}

if {[llength $prerror_pin] && [llength $reconf_regs]} {
    report_timing \
      -through $prerror_pin \
      -to $reconf_regs \
      -slack_lesser_than 0 \
      -max_paths 100 \
      -input_pins \
      -nets \
      -name through_prerror_to_reconfctrl \
      -file $rpt_dir/through_prerror_to_reconfctrl.rpt
}

if {[llength $prdone_pin] && [llength $reconf_regs]} {
    report_timing \
      -through $prdone_pin \
      -to $reconf_regs \
      -slack_lesser_than 0 \
      -max_paths 100 \
      -input_pins \
      -nets \
      -name through_prdone_to_reconfctrl \
      -file $rpt_dir/through_prdone_to_reconfctrl.rpt
}

puts "Wrote timing debug reports to $rpt_dir"
