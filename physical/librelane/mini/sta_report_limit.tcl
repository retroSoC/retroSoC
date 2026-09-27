# LibreLane 3.0.5 hard-codes 1000 expanded paths per clock group. Cap only
# report enumeration; worst-slack/TNS analysis still covers the full graph.
set ::retrosoc_sta_group_path_count 10
puts "\[INFO\] OpenSTA executable: [info nameofexecutable]"
rename report_checks ::retrosoc_report_checks
proc report_checks {args} {
    set count_index [lsearch -exact $args -group_path_count]
    if {$count_index >= 0} {
        set value_index [expr {$count_index + 1}]
        if {$value_index < [llength $args]} {
            lset args $value_index $::retrosoc_sta_group_path_count
        }
    } else {
        lappend args -group_path_count $::retrosoc_sta_group_path_count
    }
    uplevel 1 [list ::retrosoc_report_checks {*}$args]
}

rename report_check_types ::retrosoc_report_check_types
proc report_check_types {args} {
    set violator_index [lsearch -exact $args -violators]
    if {$violator_index >= 0} {
        set args [lreplace $args $violator_index $violator_index]
    }
    uplevel 1 [list ::retrosoc_report_check_types {*}$args]
}

rename report_parasitic_annotation ::retrosoc_report_parasitic_annotation
proc report_parasitic_annotation {args} {
    set detail_index [lsearch -exact $args -report_unannotated]
    if {$detail_index >= 0} {
        set args [lreplace $args $detail_index $detail_index]
    }
    uplevel 1 [list ::retrosoc_report_parasitic_annotation {*}$args]
}
