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
source [file join $flow_root tcl common corners.tcl]
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

    # Tool setup migrated from the CX55 legacy flow
    # (bes_data/syn/scr/flow_com/syn_common_flow.tcl:62-121); only the
    # settings that were active (not commented out) there are kept.
    set_app_var hdlin_vhdl_std 1987
    set_app_var hdlin_vrlg_std 2001
    set_app_var hdlin_sverilog_std 2012
    set_app_var alib_library_analysis_path $work_dir
    set_host_options -max_cores [flow::env SYN_COMPILE_CORES 16]
    suppress_message {
        VER-936 VER-129 VER-173 VHD-4 VER-314 VER-318 ELAB-924 ELAB-130
        ELAB-909 VHD-7 ELAB-931 PWR-429 PWR-415 PWR-416 PWR-12 PWR-414
        PWR-428 UID-401 VER-281 ELAB-910 TIM-250 PSYN-1002 DEFR-103
        PSYN-950 DEFR-35 DCT-197 PSYN-123 ELAB-311 ELAB-388 TIM-134
        OPT-806 OPT-805 DCT-055 DDB-74 UCN-1
    }
    set_app_var verilogout_show_unconnected_pins true
    set_app_var hdlin_check_no_latch true
    set_app_var timing_enable_multiple_clocks_per_reg true
    set_app_var compile_seqmap_identify_shift_registers false
    set_app_var verilogout_higher_designs_first true
    set_app_var hdlin_shorten_long_module_name true
    set_app_var hdlin_analyze_verbose_mode 2
    history keep 200
    set_app_var report_default_significant_digits 4

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

    # Legacy syn_common_flow.tcl:247-250: macro/IO cells that are already
    # mapped must survive optimization untouched.
    set mapped [get_cells -quiet -hierarchical \
        -filter "is_mapped == true && is_hierarchical == false && ref_name !~ *logic_*"]
    if {[sizeof_collection $mapped] > 0} {
        set_dont_touch $mapped
    }

    # Legacy syn_common_flow.tcl:273.
    set_max_area 0

    # Legacy syn_common_flow.tcl:281-292: latch-based clock-gating style and
    # exclusion of the input synchronizer registers.
    set_clock_gating_style -sequential_cell latch \
        -control_point before -control_signal scan_enable \
        -minimum_bitwidth 4 -observation_point false -max_fanout 32
    set sync_patterns [flow::env SYN_CLOCK_GATING_EXCLUDE_PATTERNS \
        "{*/synch_toggle} {*/synch_preset} {*/synch_enable} {*/synch_clear} {*/next_state}"]
    set sync_terms {}
    foreach pattern $sync_patterns {
        lappend sync_terms "full_name =~ $pattern"
    }
    set sync_endpoints ""
    foreach_in_collection input [all_inputs] {
        set fanout [all_fanout -from $input -flat -endpoints_only]
        append_to_collection -unique sync_endpoints \
            [filter_collection $fanout [join $sync_terms " || "]]
    }
    set sync_cells [get_cells -quiet -of_objects $sync_endpoints]
    if {[sizeof_collection $sync_cells] > 0} {
        set_clock_gating_objects -exclude $sync_cells
    }

    # Legacy syn_common_flow.tcl:300.
    set_dynamic_optimization true

    flow::apply_constraints
    # Synthesis links the TYP library set (flow::synthesis_library_files).
    # The legacy CX55 DC run at TYP applied no timing derate at all
    # (bes_data/syn/scr/flow_com/syn_common_flow.tcl never sources
    # signoff_table.tcl; bes_data/syn/log/asic_top.log has no
    # set_timing_derate), so no derate is applied here either; the OCV derate
    # policy lives in PrimeTime signoff (flow::apply_signoff_derate).
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

    # Legacy syn_common_flow.tcl:500-502: separate I/O path groups (the
    # legacy script names the -to [all_outputs] group "out2reg").
    group_path -weight 0.1 -name in2reg -from [all_inputs]
    group_path -weight 0.1 -name out2reg -to [all_outputs]
    group_path -weight 0.1 -name in2out -from [all_inputs] -to [all_outputs]
    # Legacy syn_common_flow.tcl:388: the legacy DC run was not in
    # topographical mode, and neither is this one (DC_SHELL := dc_shell).
    set_wire_load_mode top
    # Legacy syn_common_flow.tcl:517 with critical_range default 0.2 (:24).
    set_critical_range [flow::env SYN_CRITICAL_RANGE_NS 0.2] [current_design]

    set svf [file join $output_dir ${top}.svf]
    set_svf $svf
    # Legacy syn_common_flow.tcl:31-32,533: high-effort TNS optimization and
    # compile_ultra without sequential output inversion.
    set_app_var compile_timing_high_effort_tns true
    compile_ultra -no_autoungroup -no_seq_output_inversion -gate_clock
    compile_ultra -incremental -no_autoungroup -no_seq_output_inversion \
        -gate_clock
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
