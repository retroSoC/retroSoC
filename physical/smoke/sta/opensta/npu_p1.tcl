# NPU-P1 isolated OpenSTA run: parameterized top with path-based metrics.
# The locked OpenSTA 3.0.0 build reports no rows from report_checks/report_wns
# under this constraint set, so WNS/TNS are computed from find_timing_paths.
foreach variable {OPENSTA_NETLIST OPENSTA_LIBERTY OPENSTA_LINK_LIBS OPENSTA_SDC OPENSTA_REPORT OPENSTA_METRICS OPENSTA_TOP} {
    if {![info exists ::env($variable)] || $::env($variable) eq ""} {
        error "required environment variable is missing: $variable"
    }
}

foreach liberty $::env(OPENSTA_LINK_LIBS) {
    read_liberty $liberty
}
read_liberty $::env(OPENSTA_LIBERTY)
if {[info exists ::env(OPENSTA_SRAM_LIBS)] && $::env(OPENSTA_SRAM_LIBS) ne ""} {
    foreach liberty $::env(OPENSTA_SRAM_LIBS) {
        read_liberty $liberty
    }
}
read_verilog $::env(OPENSTA_NETLIST)
link_design $::env(OPENSTA_TOP)
read_sdc $::env(OPENSTA_SDC)

proc npu_collect_paths {delay report} {
    set worst 999.0
    set total 0.0
    set count 0
    puts $report "path_delay $delay"
    foreach path [find_timing_paths -path_delay $delay -slack_max 999.0 \
            -group_path_count 100000 -endpoint_path_count 100000] {
        set slack [get_property $path slack]
        incr count
        if {$slack < $worst} { set worst $slack }
        if {$slack < 0.0} {
            set total [expr {$total + $slack}]
            puts $report "VIOLATED [get_property $path startpoint] -> [get_property $path endpoint] slack=$slack"
        }
    }
    if {$count == 0} { set worst 0.0 }
    return [list $worst $total $count]
}

set report [open $::env(OPENSTA_REPORT) "w"]
set setup [npu_collect_paths max $report]
set hold [npu_collect_paths min $report]
close $report

set metrics [open $::env(OPENSTA_METRICS) "w"]
puts $metrics "wns_max=[lindex $setup 0]"
puts $metrics "tns_max=[lindex $setup 1]"
puts $metrics "paths_max=[lindex $setup 2]"
puts $metrics "wns_min=[lindex $hold 0]"
puts $metrics "tns_min=[lindex $hold 1]"
puts $metrics "paths_min=[lindex $hold 2]"
close $metrics
