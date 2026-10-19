foreach name {SPI_NETLIST SPI_LIBERTY SPI_REPORT_DIR} {
    if {![info exists ::env($name)]} { error "missing $name" }
}
read_liberty $::env(SPI_LIBERTY)
read_verilog $::env(SPI_NETLIST)
link_design apb4_spi_block_top
read_sdc [file join [file dirname [info script]] spi_block.sdc]
check_setup -verbose > $::env(SPI_REPORT_DIR)/constraints.rpt
report_checks -path_delay min_max -group_path_count 20 > $::env(SPI_REPORT_DIR)/paths.rpt
report_wns -max > $::env(SPI_REPORT_DIR)/setup_wns.rpt
report_tns -max > $::env(SPI_REPORT_DIR)/setup_tns.rpt
report_wns -min > $::env(SPI_REPORT_DIR)/hold_wns.rpt
report_tns -min > $::env(SPI_REPORT_DIR)/hold_tns.rpt
