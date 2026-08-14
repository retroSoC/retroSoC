foreach variable {OPENSTA_NETLIST OPENSTA_LIBERTY OPENSTA_LINK_LIBS OPENSTA_SDC OPENSTA_REPORT OPENSTA_METRICS} {
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
link_design retrosoc_asic
read_sdc $::env(OPENSTA_SDC)

report_checks -path_delay min_max -sort_by_slack -slack_max 0.0 -group_path_count 1000 -endpoint_path_count 1000 > $::env(OPENSTA_REPORT)

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

# set_propagated_clock clk
# read_spef gcd_sky130hd.spef
# set_power_activity -input -activity .1
# set_power_activity -input_port reset -activity 0
# report_power
