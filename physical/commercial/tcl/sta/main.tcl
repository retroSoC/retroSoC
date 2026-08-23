# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

set flow_root [file normalize [file join [file dirname [info script]] ../..]]
source [file join $flow_root tcl common common.tcl]
source [file join $flow_root tcl common corners.tcl]
source [file join $flow_root tcl sta load.tcl]

proc count_violations {path} {
    set handle [open $path r]
    set text [read $handle]
    close $handle
    return [regexp -all -nocase {\mVIOLATED\M} $text]
}

proc run_sta {} {
    flow::require_qualified_synthesis
    set top [flow::env TOP]
    set tag [string tolower [flow::env STA_TAG]]
    set scenario [flow::env STA_SCENARIO]
    if {$tag ni {route eco}} {
        flow::fail "unsupported STA tag: $tag"
    }
    if {![dict exists $::flow::scenarios $scenario]} {
        flow::fail "unsupported STA scenario: $scenario"
    }
    set base [flow::stage_dirs sta $tag]
    set report_dir [file join $base reports]
    set output_dir [file join $base output]
    set work_dir [file join $base work]
    flow::load_pt_scenario $tag $scenario
    flow::require_commercial_clock_inventory

    update_timing -full
    if {![check_timing -include {no_clock unconstrained_endpoints}]} {
        flow::fail "check_timing failed in scenario $scenario"
    }

    set setup_paths [get_timing_paths -delay_type max \
        -slack_lesser_than 0.0 -max_paths 100000]
    set hold_paths [get_timing_paths -delay_type min \
        -slack_lesser_than 0.0 -max_paths 100000]
    set setup_count [sizeof_collection $setup_paths]
    set hold_count [sizeof_collection $hold_paths]
    set constraint_report [file join $report_dir ${scenario}.constraints.rpt]

    redirect [file join $report_dir ${scenario}.setup.rpt] {
        report_timing -delay_type max -slack_lesser_than 0.0 \
            -max_paths 100000 -path_type full_clock_expanded \
            -input_pins -nets -transition_time -capacitance -derate
    }
    redirect [file join $report_dir ${scenario}.hold.rpt] {
        report_timing -delay_type min -slack_lesser_than 0.0 \
            -max_paths 100000 -path_type full_clock_expanded \
            -input_pins -nets -transition_time -capacitance -derate
    }
    redirect $constraint_report { report_constraint -all_violators }
    redirect [file join $report_dir ${scenario}.coverage.rpt] {
        report_analysis_coverage -status_details untested
    }
    redirect [file join $report_dir ${scenario}.parasitics.rpt] {
        report_annotated_parasitics -check
    }
    redirect [file join $report_dir ${scenario}.clocks.rpt] {
        report_clock_timing -type summary
    }
    redirect [file join $report_dir ${scenario}.exceptions.rpt] {
        report_exceptions -nosplit
    }
    redirect [file join $report_dir ${scenario}.libraries.rpt] {
        foreach_in_collection library [get_libs *] {
            puts [get_object_name $library]
        }
    }
    set drv_count [count_violations $constraint_report]
    flow::write_text [file join $output_dir ${scenario}.summary.tsv] \
        "$scenario\t$setup_count\t$hold_count\t$drv_count\n"

    if {[flow::report_has_failure \
            [file join $report_dir ${scenario}.parasitics.rpt] \
            {{unannotated[^\n]*[1-9]} {not annotated}}]} {
        flow::fail "incomplete parasitic annotation in scenario $scenario"
    }

    if {$scenario eq "func_TYP_TYP_25"} {
        write_sdf -version 3.0 -context verilog \
            [file join $output_dir ${top}.${tag}.sdf]
    }
    if {$tag eq "eco"} {
        if {$setup_count > [flow::env MAX_SETUP_VIOLATIONS 0]} {
            flow::fail "setup violations exceed the configured limit"
        }
        if {$hold_count > [flow::env MAX_HOLD_VIOLATIONS 0]} {
            flow::fail "hold violations exceed the configured limit"
        }
        if {$drv_count > [flow::env MAX_DRV_VIOLATIONS 0]} {
            flow::fail "design-rule violations exceed the configured limit"
        }
    } else {
        flow::ensure_dir [file join $work_dir sessions]
        save_session [file join $work_dir sessions $scenario]
    }
    flow::write_pass [file join $output_dir ${scenario}.pass]
}

if {[catch {run_sta} message options]} {
    puts stderr $message
    if {[dict exists $options -errorinfo]} {
        puts stderr [dict get $options -errorinfo]
    }
    exit 2
}
exit
