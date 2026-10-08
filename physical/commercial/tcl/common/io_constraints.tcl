# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of MulanPSL2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

namespace eval flow {
    variable io_qualified 0
    variable unqualified_interfaces {}
}

proc flow::interface_ports {label names} {
    return [flow::required_ports "$label interface" $names]
}

proc flow::apply_input_budget {prefix clock ports} {
    set_input_delay -clock $clock -max [flow::env ${prefix}_INPUT_DELAY_MAX_NS] $ports
    set_input_delay -clock $clock -min [flow::env ${prefix}_INPUT_DELAY_MIN_NS] $ports
    set_input_transition -max [flow::env ${prefix}_INPUT_TRANSITION_NS] $ports
    set_input_transition -min [flow::env ${prefix}_INPUT_TRANSITION_NS] $ports
}

proc flow::apply_output_budget {prefix clock ports} {
    set_output_delay -clock $clock -max [flow::env ${prefix}_OUTPUT_DELAY_MAX_NS] $ports
    set_output_delay -clock $clock -min [flow::env ${prefix}_OUTPUT_DELAY_MIN_NS] $ports
    set_load [flow::env ${prefix}_OUTPUT_LOAD_PF] $ports
}

proc flow::create_virtual_interface_clock {prefix} {
    set name vclk_[string tolower $prefix]
    create_clock -name $name -period [flow::env ${prefix}_CLOCK_PERIOD_NS]
    return $name
}

proc flow::numbered_ports {prefix first last suffix} {
    set names {}
    for {set index $first} {$index <= $last} {incr index} {
        lappend names ${prefix}${index}${suffix}
    }
    return $names
}

proc flow::apply_io_constraints {} {
    variable io_qualified
    variable unqualified_interfaces
    set mode [string toupper [flow::env IO_TIMING_QUALIFIED NO]]
    if {$mode eq "YES"} {
        set io_qualified 1
        set unqualified_interfaces {}
        product::apply_io_constraints
    } elseif {$mode eq "NO"} {
        set io_qualified 0
        set unqualified_interfaces [product::io_interface_groups]
        # Internal-QoR mode closes all sequential domains while explicitly
        # excluding board and package paths that do not yet have a budget.
        set_false_path -from [all_inputs]
        set_false_path -to [all_outputs]
    } else {
        flow::fail "IO_TIMING_QUALIFIED must be YES or NO"
    }
}
