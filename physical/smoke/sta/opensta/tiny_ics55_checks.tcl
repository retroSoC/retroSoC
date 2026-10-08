# The Python precondition binds the consumed netlist to its structural audit:
# one disabled PLL, 32 SYS SRAM macros and common CPU/SRAM clock connectivity.
# This script adds observations, not PLL timing arcs or new timing exceptions.
set audit_dir [file dirname $::env(OPENSTA_REPORT)]
set pll [get_cells -hierarchical -filter {ref_name == PLL_TOP}]
set ram [get_cells -hierarchical -filter {ref_name == ics55_ecos_sram_1024x32_m8}]
if {[llength $pll] != 1 || [llength $ram] != 32} { error "Tiny ICS55 macro binding mismatch" }
if {[llength [get_clocks clk_system]] != 1} { error "Tiny SYS clock missing" }
report_clock_properties > $audit_dir/clocks.rpt
check_setup -verbose > $audit_dir/coverage.rpt
report_check_types -recovery -removal -min_pulse_width -min_period -max_slew -max_capacitance -max_fanout -violators -verbose > $audit_dir/constraint-violations.rpt
report_checks -path_group clk_system -path_delay max -group_path_count 20 -fields {capacitance slew fanout} > $audit_dir/sys-setup.rpt
report_checks -path_group clk_system -path_delay min -group_path_count 20 -fields {capacitance slew fanout} > $audit_dir/sys-hold.rpt
set ram_inputs {}
set ram_outputs {}
foreach pin [get_pins -of_objects $ram] {
    if {[get_property $pin direction] eq "input"} { lappend ram_inputs $pin }
    if {[get_property $pin direction] eq "output"} { lappend ram_outputs $pin }
}
report_checks -to $ram_inputs -path_delay min_max -group_path_count 20 > $audit_dir/sram-input-paths.rpt
report_checks -from $ram_outputs -path_delay min_max -group_path_count 20 > $audit_dir/sram-return-paths.rpt
puts "TINY_ICS55_STA_AUDIT_PASS: SAFE24 only; PLL held off; no PLL timing qualification"
