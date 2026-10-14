# P7 uses a dedicated, provenance-checked Python macro/clock audit. Historical
# P1/P4 checks retain their direct-SYS/parked-PLL assumptions unchanged.
set p7_dir [file dirname $::env(OPENSTA_REPORT)]
foreach clock {clk_aon clk_system clk_memory clk_peripheral clk_audio clk_jtag clk_sys_div2 clk_sys_div4 clk_clkout_source} {
    if {[llength [get_clocks -quiet $clock]] != 1} { error "P7 clock missing: $clock" }
}
set p7_pll [get_cells -hierarchical -quiet -filter {ref_name == PLL_TOP}]
if {[llength $p7_pll] > 1} { error "P7 contains multiple PLL macros" }
if {[llength $p7_pll] == 1} {
    # The analysis is explicitly the cold SAFE24 boot operating state.
    set p7_enable [get_pins -quiet "[get_full_name [lindex $p7_pll 0]]/EN"]
    if {[llength $p7_enable] != 1} { error "P7 PLL enable pin missing" }
    set_case_analysis 0 $p7_enable
}
report_clock_properties > $p7_dir/clocks.rpt
check_setup -verbose > $p7_dir/coverage.rpt
report_check_types -recovery -removal -min_pulse_width -min_period -max_slew -max_capacitance -max_fanout -violators -verbose > $p7_dir/constraint-violations.rpt
foreach domain {system memory peripheral aon} {
    report_checks -path_group clk_$domain -path_delay max -group_path_count 20 -fields {capacitance slew fanout} > $p7_dir/$domain-setup.rpt
    report_checks -path_group clk_$domain -path_delay min -group_path_count 20 -fields {capacitance slew fanout} > $p7_dir/$domain-hold.rpt
}
puts "TINY_R2_P7_STA_OBSERVATION: SAFE24 boot only; not active PLL, routed or PVT qualification"
