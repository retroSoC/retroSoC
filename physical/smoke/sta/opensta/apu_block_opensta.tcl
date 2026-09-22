# retroSoC APU block-level OpenSTA run (top: apb4_apu), derived from opensta.tcl.
# Reports max-delay and min-delay (hold) results separately, records the same
# wns/tns metric format as the SoC flow, and adds an explicit check_timing
# inventory so unconstrained endpoints are visible in the evidence set.

foreach variable {OPENSTA_NETLIST OPENSTA_LIBERTY OPENSTA_SDC OPENSTA_REPORT \
        OPENSTA_REPORT_MIN OPENSTA_WORST OPENSTA_METRICS OPENSTA_CHECK_TIMING \
        OPENSTA_CHECK_TYPES} {
    if {![info exists ::env($variable)] || $::env($variable) eq ""} {
        error "required environment variable is missing: $variable"
    }
}

read_liberty $::env(OPENSTA_LIBERTY)
if {[info exists ::env(OPENSTA_SRAM_LIBS)] && $::env(OPENSTA_SRAM_LIBS) ne ""} {
    foreach liberty $::env(OPENSTA_SRAM_LIBS) {
        read_liberty $liberty
    }
}
read_verilog $::env(OPENSTA_NETLIST)
link_design apb4_apu
read_sdc $::env(OPENSTA_SDC)

# max-delay (setup) violations; empty report means no negative-slack path
report_checks -path_delay max -sort_by_slack -slack_max 0.0 \
    -group_path_count 1000 -endpoint_path_count 1000 > $::env(OPENSTA_REPORT)

# min-delay (hold) violations, reported separately per docs/ip/apu.md
report_checks -path_delay min -sort_by_slack -slack_max 0.0 \
    -group_path_count 1000 -endpoint_path_count 1000 > $::env(OPENSTA_REPORT_MIN)

# worst paths regardless of sign: 20 worst max-delay and 20 worst min-delay
set worst_file $::env(OPENSTA_WORST)
report_checks -path_delay max -sort_by_slack -format full \
    -group_path_count 20 -endpoint_path_count 1 > $worst_file
report_checks -path_delay min -sort_by_slack -format full \
    -group_path_count 20 -endpoint_path_count 1 >> $worst_file

# unconstrained-path inventory: only paths carrying the explicit
# "(Path is unconstrained)" marker count as unconstrained evidence
report_checks -unconstrained -sort_by_slack \
    -group_path_count 1000 -endpoint_path_count 1000 > $::env(OPENSTA_CHECK_TIMING)

# design-rule inventory (slew/fanout/capacitance/pulse-width), report-only
report_check_types > $::env(OPENSTA_CHECK_TYPES)

set metrics_file $::env(OPENSTA_METRICS)
set metrics_tmp "${metrics_file}.tmp"
set metrics [open $metrics_file "w"]

report_wns -min > $metrics_tmp
set input [open $metrics_tmp "r"]
puts $metrics "wns_min=[string trim [read $input]]"
close $input

report_wns -max > $metrics_tmp
set input [open $metrics_tmp "r"]
puts $metrics "wns_max=[string trim [read $input]]"
close $input

report_tns -min > $metrics_tmp
set input [open $metrics_tmp "r"]
puts $metrics "tns_min=[string trim [read $input]]"
close $input

report_tns -max > $metrics_tmp
set input [open $metrics_tmp "r"]
puts $metrics "tns_max=[string trim [read $input]]"
close $input

close $metrics
file delete -force $metrics_tmp
