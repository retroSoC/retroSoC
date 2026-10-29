foreach name {PIOLITE_NETLIST PIOLITE_LIBERTY PIOLITE_REPORT_DIR} {
    if {![info exists ::env($name)]} { error "missing $name" }
}
read_liberty $::env(PIOLITE_LIBERTY)
read_verilog $::env(PIOLITE_NETLIST)
link_design apb4_piolite_block_top
read_sdc [file join [file dirname [info script]] piolite_block.sdc]
check_setup -verbose > $::env(PIOLITE_REPORT_DIR)/constraints.rpt
report_checks -path_delay min_max -group_path_count 20 > $::env(PIOLITE_REPORT_DIR)/paths.rpt
report_wns -max > $::env(PIOLITE_REPORT_DIR)/setup_wns.rpt
report_tns -max > $::env(PIOLITE_REPORT_DIR)/setup_tns.rpt
report_wns -min > $::env(PIOLITE_REPORT_DIR)/hold_wns.rpt
report_tns -min > $::env(PIOLITE_REPORT_DIR)/hold_tns.rpt
