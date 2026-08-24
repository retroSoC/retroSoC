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
source [file join $flow_root tcl common constraints.tcl]
source [file join $flow_root tcl syn reporting.tcl]

proc run_synthesis {} {
    set top [flow::env TOP]
    set run_root [flow::env RUN_ROOT]
    set base [flow::stage_dirs syn ""]
    set work_dir [file join $run_root syn work]
    set report_dir [file join $run_root syn reports]
    set output_dir [file join $run_root syn output]
    set filelist [file join $run_root input rtl filelist.fl]
    set rtl [flow::read_filelist $filelist]
    set libraries [flow::synthesis_library_files]
    set target_library [flow::synthesis_target_files]

    set search_path [list . [file join $run_root input rtl]]
    set search_path [concat $search_path [dict get $rtl incdirs]]
    foreach library $libraries {
        lappend search_path [file dirname $library]
    }
    set_app_var search_path [lsort -unique $search_path]
    set_app_var target_library $target_library
    set_app_var link_library [concat * $libraries dw_foundation.sldb]
    set_app_var synthetic_library dw_foundation.sldb
    set_app_var hdlin_sv_enable_rtl_attributes true
    set_app_var verilogout_no_tri true
    set_app_var compile_clock_gating_through_hierarchy true

    define_design_lib WORK -path [file join $work_dir WORK]
    set analyze_command [list analyze -format sverilog -work WORK]
    if {[llength [dict get $rtl defines]] > 0} {
        lappend analyze_command -define [dict get $rtl defines]
    }
    lappend analyze_command [dict get $rtl sources]
    if {[catch {eval $analyze_command} message]} {
        flow::fail "RTL analysis failed: $message"
    }
    if {[catch {elaborate $top -library WORK} message]} {
        flow::fail "RTL elaboration failed: $message"
    }
    current_design $top
    if {![link]} {
        flow::fail "link failed for $top"
    }
    flow::configure_synthesis_libraries
    uniquify
    foreach pattern [flow::env SYN_DONT_USE] {
        set cells [get_lib_cells -quiet */$pattern]
        if {[sizeof_collection $cells] > 0} {
            set_dont_use $cells
        }
    }

    flow::apply_constraints
    redirect [file join $report_dir check_design.pre.rpt] { check_design }
    redirect [file join $report_dir check_timing.pre.rpt] {
        check_timing
    }
    if {![check_design]} {
        flow::fail "pre-compile Design Compiler check_design failed"
    }
    if {![check_timing -include {unconstrained_endpoints}]} {
        flow::fail "pre-compile timing constraints are incomplete"
    }
    set_fix_multiple_port_nets -all -buffer_constants
    set_boundary_optimization [current_design] true

    set svf [file join $output_dir ${top}.svf]
    set_svf $svf
    compile_ultra -no_autoungroup -gate_clock
    compile_ultra -incremental -no_autoungroup -gate_clock
    set_svf -off

    change_names -rules verilog -hierarchy
    redirect [file join $report_dir check_design.rpt] { check_design }
    redirect [file join $report_dir check_design.summary.rpt] {
        check_design -summary
    }
    redirect [file join $report_dir check_timing.rpt] {
        check_timing
    }
    redirect [file join $report_dir timing.setup.rpt] {
        report_timing -delay_type max -max_paths 1000 -input_pins -nets
    }
    redirect [file join $report_dir timing.hold.rpt] {
        report_timing -delay_type min -max_paths 1000 -input_pins -nets
    }
    redirect [file join $report_dir qor.rpt] { report_qor }
    redirect [file join $report_dir area.rpt] { report_area -hierarchy }
    redirect [file join $report_dir power.rpt] { report_power -hierarchy }
    set drv_report [file join $report_dir design_rules.rpt]
    redirect $drv_report {
        report_constraint -all_violators -max_transition -max_fanout \
            -max_capacitance
    }
    redirect [file join $report_dir timing_constraints.rpt] {
        report_constraint -all_violators -max_delay -min_delay
    }
    redirect [file join $report_dir clocks.rpt] { report_clock -skew -attributes }
    redirect [file join $report_dir clock_gating.rpt] {
        report_clock_gating -nosplit -verbose
    }
    redirect [file join $report_dir exceptions.rpt] { report_exceptions -nosplit }
    redirect [file join $report_dir library_binding.rpt] { report_design -library }
    redirect [file join $report_dir references.rpt] { report_reference -hierarchy }

    if {![check_design]} {
        flow::fail "Design Compiler check_design failed"
    }
    if {![check_timing -include {unconstrained_endpoints}]} {
        flow::fail "Design Compiler timing constraints are incomplete"
    }
    if {[flow::report_has_failure [file join $report_dir check_design.rpt] \
            {{unresolved reference} {link failed} {Error:}}]} {
        flow::fail "Design Compiler reports unresolved or invalid design data"
    }

    write -format ddc -hierarchy -output [file join $output_dir ${top}.ddc]
    write -format verilog -hierarchy -output [file join $output_dir ${top}.syn.v]
    write_sdc -nosplit [file join $output_dir ${top}.syn.sdc]
    write_sdf -version 3.0 -context verilog \
        [file join $output_dir ${top}.syn.sdf]
    set drv_count [flow::count_report_matches $drv_report {\mVIOLATED\M}]
    flow::write_path_group_summary \
        [file join $output_dir synthesis.path_groups.tsv]
    flow::write_synthesis_summary \
        [file join $output_dir synthesis.summary.tsv] $drv_count
    flow::write_pass [file join $output_dir verdict.pass]
}

if {[catch {run_synthesis} message options]} {
    puts stderr $message
    if {[dict exists $options -errorinfo]} {
        puts stderr [dict get $options -errorinfo]
    }
    exit 2
}
exit
