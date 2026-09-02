# IHP SG13G2 supply pads are physical-only cells and are not retained by Yosys.
foreach {kind master count} {
    vdd sg13g2_IOPadVdd 24
    vss sg13g2_IOPadVss 24
    iovdd sg13g2_IOPadIOVdd 16
    iovss sg13g2_IOPadIOVss 16
} {
    for {set index 0} {$index < $count} {incr index} {
        set instance_name [format {%s_pads[%d].%s_pad} $kind $index $kind]
        set db_block [ord::get_db_block]
        if {[$db_block findInst $instance_name] == "NULL"} {
            make_instance $instance_name $master
        }
    }
}
source $::env(SCRIPTS_DIR)/openroad/common/pad_cfg.tcl
