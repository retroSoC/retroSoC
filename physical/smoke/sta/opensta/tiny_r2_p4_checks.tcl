# P4 structural timing prerequisites, common to both supported Tiny PDKs.
# Negative timing remains observational; missing/incorrect clock objects do not.
set p4_dir [file dirname $::env(OPENSTA_REPORT)]
set p4_ram [get_cells -hierarchical -filter {ref_name == RM_IHPSG13_1P_1024x32_c2_bm_bist}]
set p4_clock_pin A_CLK
if {[llength $p4_ram] == 0} {
    set p4_ram [get_cells -hierarchical -filter {ref_name == ics55_ecos_sram_1024x32_m8}]
    set p4_clock_pin CLK
}
if {[llength $p4_ram] != 32} { error "P4 requires 32 main SRAM macros" }
set p4_expected {}
for {set group 0} {$group < 4} {incr group} {
    for {set bank 0} {$bank < 8} {incr bank} {
        lappend p4_expected [format {u_soc.u_sram.gen_group[%d].u_group.gen_bank[%d].u_ram.u_mem} $group $bank]
    }
}
set p4_seen {}
foreach cell $p4_ram {
    set name [string map {/ .} [get_full_name $cell]]
    foreach expected $p4_expected {
        if {[string equal [string range $name end-[expr {[string length $expected]-1}] end] $expected]} {
            lappend p4_seen $expected
        }
    }
}
if {[lsort $p4_seen] ne [lsort $p4_expected]} { error "P4 macro group hierarchy mismatch" }
set p4_source [get_pins -quiet {u_clock_buffer/clk_o}]
if {[llength $p4_source] != 1} { error "P4 SYS source missing" }
set p4_direct {}
foreach pin [get_fanout -from $p4_source -flat -pin_levels 1 -trace_arcs all] {
    dict set p4_direct [get_full_name $pin] 1
}
set p4_clock_report [open $p4_dir/p4-clock-bindings.rpt w]
foreach cell $p4_ram {
    set clocks {}
    foreach pin [get_pins -of_objects $cell] {
        if {[string match "*/$p4_clock_pin" [get_full_name $pin]]} { lappend clocks $pin }
    }
    if {[llength $clocks] != 1} { error "P4 macro clock pin missing" }
    set name [get_full_name [lindex $clocks 0]]
    if {![dict exists $p4_direct $name]} { error "P4 SRAM clock is not direct SYS: $name" }
    puts $p4_clock_report $name
}
set p4_cpu [get_pins -hierarchical -quiet {*u_hazard3_cpu_2port*/CLK *u_hazard3_cpu_2port*/CK *u_hazard3_cpu_2port*/CKN}]
set p4_front [get_pins -hierarchical -quiet {*u_cpu_mem*/CLK *u_cpu_mem*/CK *u_cpu_mem*/CKN}]
if {[llength $p4_cpu] == 0 || [llength $p4_front] == 0} { error "P4 CPU/frontend clock endpoints missing" }
foreach pin [concat $p4_cpu $p4_front] {
    set name [get_full_name $pin]
    if {![dict exists $p4_direct $name]} { error "P4 CPU/frontend does not share SYS: $name" }
}
puts $p4_clock_report "CPU clock endpoints: [llength $p4_cpu]"
puts $p4_clock_report "Frontend clock endpoints: [llength $p4_front]"
close $p4_clock_report
puts "TINY_R2_P4_BINDING_PASS: four groups, 32 macros, common CPU/SRAM SYS; not timing qualification"
