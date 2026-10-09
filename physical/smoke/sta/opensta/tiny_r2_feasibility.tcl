# Source-bound Tiny R2 feasibility only. No timing exceptions are added here.
source [file join [file dirname [info script]] opensta.tcl]
set output $::env(TINY_R2_OUTPUT)
set candidate $::env(TINY_R2_CANDIDATE)
report_clock_properties > $output/clocks.rpt
report_checks -path_group clk_system -path_delay max -group_path_count 1 -fields {capacitance slew fanout} > $output/sys-setup.rpt
report_checks -path_group clk_system -path_delay min -group_path_count 1 -fields {capacitance slew fanout} > $output/sys-hold.rpt
report_check_types -recovery -removal -min_pulse_width -min_period -max_slew -max_capacitance -max_fanout -violators -verbose > $output/constraint-violations.rpt
check_setup -verbose > $output/coverage.rpt

set counts [open $output/reset-loads.tsv w]
puts $counts "name\tdrivers\tdirect_loads\tstructural_endpoints"
proc reset_report {label nets {drivers {}}} {
    global output counts
    if {[llength $nets] != 1} { error "expected one reset net for $label" }
    set net [lindex $nets 0]
    if {[llength $drivers] == 0} {
        set drivers [get_pins -of_objects $net -filter {direction == output}]
    }
    if {[llength $drivers] != 1} { error "expected one reset driver for $label" }
    set direct {}
    foreach pin [get_fanout -from $drivers -flat -pin_levels 1 -trace_arcs all] {
        if {[get_property $pin direction] eq "input"} { lappend direct $pin }
    }
    set endpoints [get_fanout -from $drivers -flat -endpoints_only -trace_arcs all]
    puts $counts "$label\t[get_full_name [lindex $drivers 0]]\t[llength $direct]\t[llength $endpoints]"
    report_net [get_full_name $net] > $output/$label-net.rpt
    report_checks -through $drivers -path_delay min_max -group_path_count 10 -fields {capacitance slew fanout} > $output/$label-paths.rpt
    set file [open $output/$label-endpoints.rpt w]
    foreach pin $endpoints { puts $file [get_full_name $pin] }
    close $file
}
reset_report system [get_nets -quiet {u_soc.s_rst_n}]
set leaf_instances [get_cells -hierarchical -quiet {*u_leaf_rst_sync}]
if {$candidate} {
    if {[llength $leaf_instances] != 17} { error "reset leaves merged or missing" }
    set output_register_pins [get_pins -hierarchical -quiet {*rst_n_o_reg/Q}]
    for {set index 0} {$index < 17} {incr index} {
        set selected {}
        foreach instance $leaf_instances {
            set name [get_full_name $instance]
            if {[regexp {gen_leaf\[([0-9]+)\][.]u_leaf_rst_sync$} $name -> leaf_index] && $leaf_index == $index} {
                lappend selected $instance
            }
        }
        if {[llength $selected] != 1} { error "leaf index missing or duplicated: $index" }
        set name [get_full_name [lindex $selected 0]]
        set driver {}
        foreach pin $output_register_pins {
            if {[get_full_name $pin] eq "$name/rst_n_o_reg/Q"} { lappend driver $pin }
        }
        if {[llength $driver] != 1} { error "mapped leaf output register missing: $name" }
        # Yosys may rename an alias to its APB interface. Resolve the consumed
        # net through the preserved leaf instance, not a source-level wire name.
        set outputs [get_pins -of_objects $selected -filter {direction == output}]
        reset_report leaf-$index [get_nets -of_objects $outputs] $driver
    }
} elseif {[llength $leaf_instances] != 0} {
    error "pre-change netlist already contains reset leaves"
}
close $counts

set clock_source [get_pins -quiet {u_clock_buffer/clk_o}]
if {[llength $clock_source] != 1} { error "system clock source missing" }
set macro_clocks {}
foreach pin [get_fanout -from $clock_source -flat -pin_levels 1 -trace_arcs all] {
    if {[string match {*/A_CLK} [get_full_name $pin]]} { lappend macro_clocks $pin }
}
if {[llength $macro_clocks] != 32} { error "expected 32 direct SYS main-SRAM clock loads" }
set macros [get_cells -hierarchical -filter {ref_name == RM_IHPSG13_1P_1024x32_c2_bm_bist}]
if {[llength $macros] != 32} { error "main-SRAM macro binding differs from 32" }
set file [open $output/sram-clock-pins.rpt w]
foreach pin $macro_clocks { puts $file [get_full_name $pin] }
close $file
set macro_inputs {}
set macro_outputs {}
foreach pin [get_pins -of_objects $macros] {
    set name [get_full_name $pin]
    if {[string match {*/A_DOUT*} $name]} { lappend macro_outputs $pin }
    if {[regexp {/A_(ADDR|DIN|BM|WEN|REN|MEN)} $name]} { lappend macro_inputs $pin }
}
if {[llength $macro_inputs] == 0 || [llength $macro_outputs] == 0} { error "SRAM data timing pins missing" }
report_checks -to $macro_inputs -path_delay min_max -group_path_count 20 -fields {capacitance slew fanout} > $output/sram-input-paths.rpt
report_checks -from $macro_outputs -path_delay min_max -group_path_count 20 -fields {capacitance slew fanout} > $output/sram-return-paths.rpt
set cpu_pins [get_pins -hierarchical -quiet {*u_cpu*/Q}]
if {[llength $cpu_pins] == 0} { error "CPU sequential launch pins missing" }
report_checks -from $cpu_pins -path_delay min_max -group_path_count 20 -fields {capacitance slew fanout} > $output/cpu-paths.rpt
puts "TINY_R2_FEASIBILITY_PASS: source-bound reports; 32 SYS macros; [llength $leaf_instances] reset leaves"
