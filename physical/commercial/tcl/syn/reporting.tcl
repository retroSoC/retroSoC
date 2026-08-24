# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

proc flow::collection_area {objects} {
    set total 0.0
    foreach_in_collection object $objects {
        set area [get_attribute -quiet $object area]
        if {$area ne ""} {
            set total [expr {$total + $area}]
        }
    }
    return $total
}

proc flow::timing_metrics {group delay_type} {
    set options [list get_timing_paths -delay_type $delay_type -nworst 1]
    if {$group ne ""} {
        lappend options -group $group
    }
    set worst [eval [concat $options [list -max_paths 1]]]
    if {[sizeof_collection $worst] == 0} {
        set wns NA
    } else {
        set wns [format %.4f [get_attribute $worst slack]]
    }
    set violations [eval [concat $options \
        [list -slack_lesser_than 0.0 -max_paths 100000]]]
    set tns 0.0
    foreach_in_collection path $violations {
        set tns [expr {$tns + [get_attribute $path slack]}]
    }
    return [list $wns [format %.4f $tns] [sizeof_collection $violations]]
}

proc flow::write_path_group_summary {path} {
    set handle [open $path w]
    puts $handle "path_group\twns_ns\ttns_ns\tviolating_paths"
    foreach_in_collection group [get_path_groups *] {
        set name [get_object_name $group]
        lassign [flow::timing_metrics $name max] wns tns violations
        puts $handle "$name\t$wns\t$tns\t$violations"
    }
    close $handle
}

proc flow::vt_cells {suffix} {
    return [get_cells -quiet -hierarchical \
        -filter "is_hierarchical == false && ref_name =~ *$suffix"]
}

proc flow::write_synthesis_summary {path drv_count} {
    variable io_qualified
    set setup [flow::timing_metrics "" max]
    set hold [flow::timing_metrics "" min]
    lassign $setup setup_wns setup_tns setup_violations
    lassign $hold hold_wns hold_tns hold_violations
    set timing_met [expr {$setup_violations == 0 && $hold_violations == 0}]
    set drv_met [expr {$drv_count == 0}]

    set leaf [get_cells -quiet -hierarchical -filter "is_hierarchical == false"]
    set sequential [get_cells -quiet -hierarchical \
        -filter "is_hierarchical == false && is_sequential == true"]
    set combinational [get_cells -quiet -hierarchical \
        -filter "is_hierarchical == false && is_combinational == true"]
    set memories [get_cells -quiet -hierarchical \
        -filter "is_hierarchical == false && is_memory_cell == true"]

    array set vt_suffix {HVT H7H LVT H7L SVT H7R}
    set std_area 0.0
    set std_count 0
    foreach group {HVT LVT SVT} {
        set cells [flow::vt_cells $vt_suffix($group)]
        set vt_count($group) [sizeof_collection $cells]
        set vt_area($group) [flow::collection_area $cells]
        set std_count [expr {$std_count + $vt_count($group)}]
        set std_area [expr {$std_area + $vt_area($group)}]
    }

    set handle [open $path w]
    puts $handle "metric\tvalue"
    puts $handle "flow_pass\tyes"
    puts $handle "constraints_complete\tyes"
    puts $handle "io_qualified\t[expr {$io_qualified ? {yes} : {no}}]"
    puts $handle "timing_met\t[expr {$timing_met ? {yes} : {no}}]"
    puts $handle "drv_met\t[expr {$drv_met ? {yes} : {no}}]"
    puts $handle "setup_wns_ns\t$setup_wns"
    puts $handle "setup_tns_ns\t$setup_tns"
    puts $handle "setup_violating_paths\t$setup_violations"
    puts $handle "hold_wns_ns\t$hold_wns"
    puts $handle "hold_tns_ns\t$hold_tns"
    puts $handle "hold_violating_paths\t$hold_violations"
    puts $handle "drv_violations\t$drv_count"
    puts $handle "leaf_cells\t[sizeof_collection $leaf]"
    puts $handle "combinational_cells\t[sizeof_collection $combinational]"
    puts $handle "sequential_cells\t[sizeof_collection $sequential]"
    puts $handle "memory_macros\t[sizeof_collection $memories]"
    puts $handle "standard_cells\t$std_count"
    puts $handle "standard_cell_area_um2\t[format %.4f $std_area]"
    puts $handle "total_leaf_area_um2\t[format %.4f [flow::collection_area $leaf]]"
    foreach group {HVT LVT SVT} {
        set percent 0.0
        if {$std_area > 0.0} {
            set percent [expr {100.0 * $vt_area($group) / $std_area}]
        }
        puts $handle "[string tolower $group]_cells\t$vt_count($group)"
        puts $handle "[string tolower $group]_area_um2\t[format %.4f $vt_area($group)]"
        puts $handle "[string tolower $group]_area_percent\t[format %.2f $percent]"
    }
    close $handle
}

proc flow::configure_synthesis_libraries {} {
    foreach {group pattern} {HVT *H7CH* LVT *H7CL* SVT *H7CR*} {
        set libraries [get_libs -quiet $pattern]
        if {[sizeof_collection $libraries] == 0} {
            flow::fail "missing $group H7C library in the TYP link set"
        }
        set_attribute $libraries default_threshold_voltage_group $group -type string
    }
    set library [flow::env SYN_OPERATING_CONDITION_LIBRARY]
    set condition [flow::env SYN_OPERATING_CONDITION]
    if {[sizeof_collection [get_libs -quiet $library]] != 1} {
        flow::fail "SYN_OPERATING_CONDITION_LIBRARY is not uniquely loaded: $library"
    }
    set_operating_conditions -analysis_type single -library $library $condition
}
