# OpenSTA run script for the isolated apb4_ga2d block netlist
# (physical/smoke/syn/yosys/ga2d_block.mk, target sta-ga2d-block). Mirrors
# opensta.tcl; the block needs no IO/SRAM link libraries because the yosys
# netlist references IHP130 standard cells only.

foreach variable {OPENSTA_NETLIST OPENSTA_LIBERTY OPENSTA_SDC OPENSTA_REPORT OPENSTA_TOP_PATHS OPENSTA_METRICS} {
    if {![info exists ::env($variable)] || $::env($variable) eq ""} {
        error "required environment variable is missing: $variable"
    }
}

read_liberty $::env(OPENSTA_LIBERTY)
read_verilog $::env(OPENSTA_NETLIST)
link_design apb4_ga2d_block_top
read_sdc $::env(OPENSTA_SDC)

report_checks -path_delay min_max -sort_by_slack -slack_max 0.0 -group_path_count 1000 -endpoint_path_count 1000 > $::env(OPENSTA_REPORT)
report_checks -path_delay max -sort_by_slack -group_path_count 10 -endpoint_path_count 1 > $::env(OPENSTA_TOP_PATHS)

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
