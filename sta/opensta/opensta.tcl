foreach variable {OPENSTA_NETLIST OPENSTA_LIBERTY OPENSTA_IO_LIB OPENSTA_SRAM_LIBS OPENSTA_SDC OPENSTA_REPORT} {
    if {![info exists ::env($variable)] || $::env($variable) eq ""} {
        error "required environment variable is missing: $variable"
    }
}

read_liberty $::env(OPENSTA_IO_LIB)
read_liberty $::env(OPENSTA_LIBERTY)
foreach liberty $::env(OPENSTA_SRAM_LIBS) {
    read_liberty $liberty
}
read_verilog $::env(OPENSTA_NETLIST)
link_design retrosoc_asic
read_sdc $::env(OPENSTA_SDC)

report_checks -path_delay min_max -path_group {clk_ext clk_aud } -sort_by_slack -slack_max 0.0 -group_path_count 1000 -endpoint_path_count 1000 > $::env(OPENSTA_REPORT)

# set_propagated_clock clk
# read_spef gcd_sky130hd.spef
# set_power_activity -input -activity .1
# set_power_activity -input_port reset -activity 0
# report_power
