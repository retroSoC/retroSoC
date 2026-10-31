foreach name {PPALITE_NETLIST PPALITE_LIBERTY PPALITE_REPORT_DIR} {
    if {![info exists ::env($name)]} { error "missing $name" }
}
read_liberty $::env(PPALITE_LIBERTY)
read_verilog $::env(PPALITE_NETLIST)
link_design apb4_ppalite_route_top
read_sdc [file join [file dirname [info script]] ppalite_route_block.sdc]
check_setup -verbose > $::env(PPALITE_REPORT_DIR)/constraints.rpt
report_checks -path_delay min_max -group_path_count 20 > $::env(PPALITE_REPORT_DIR)/paths.rpt
report_wns -max > $::env(PPALITE_REPORT_DIR)/setup_wns.rpt
report_tns -max > $::env(PPALITE_REPORT_DIR)/setup_tns.rpt
report_wns -min > $::env(PPALITE_REPORT_DIR)/hold_wns.rpt
report_tns -min > $::env(PPALITE_REPORT_DIR)/hold_tns.rpt
