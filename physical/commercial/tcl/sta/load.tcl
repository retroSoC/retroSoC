# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

# PrimeTime analysis settings adopted from the CX55 legacy signoff flow
# (Flow_CX55_SoC_CL_2026 bes_data/sta/scr/flow_com/pt_common_flow.tcl:78-105;
# only the legacy lines that are actually uncommented are enabled here). The
# legacy script assigns these with plain `set`; current PrimeTime releases
# expose them as application variables, so set_app_var is used instead.
proc flow::apply_pt_analysis_settings {} {
    # Clock reconvergence pessimism reduction (legacy lines 78 and 85).
    set_app_var timing_remove_clock_reconvergence_pessimism true
    set_app_var timing_crpr_threshold_ps 1
    # SMIC-recommended timing behavior (legacy lines 81-84).
    set_app_var timing_save_pin_arrival_and_slack true
    set_app_var timing_early_launch_at_borrowing_latches false
    set_app_var timing_clock_gating_propagate_enable true
    set_app_var timing_report_use_worst_parallel_cell_arc true
    # Path-based analysis behavior (legacy lines 87 and 99).
    set_app_var pba_exhaustive_endpoint_path_limit infinity
    set_app_var pba_enable_path_based_physical_exclusivity true
    # Constraint, parasitic, and linking behavior (legacy lines 90-92).
    set_app_var timing_enable_max_capacitance_set_case_analysis true
    set_app_var read_parasitics_load_locations true
    set_app_var link_create_black_boxes false
    # Signal-integrity and waveform-accurate delay calculation (legacy
    # lines 94-102; the commented-out si_xtalk_composite_aggr_* candidates
    # stay disabled). Coupling capacitors come from read_parasitics
    # -keep_capacitive_coupling in flow::load_pt_scenario.
    set_app_var si_enable_analysis true
    set_app_var si_xtalk_double_switching_mode full_design
    set_app_var si_xtalk_composite_aggr_mode statistical
    set_app_var si_noise_composite_aggr_mode statistical
    set_app_var si_xtalk_delay_analysis_mode all_path_edges
    set_app_var delay_calc_waveform_analysis_mode full_design
    set_app_var delay_calc_waveform_analysis_constraint_arcs_compatibility false
    # Automatic mux clock exclusivity (legacy line 105). The site-specific
    # legacy parasitics_log_file path (line 103) is not adopted; annotation
    # evidence is covered by report_annotated_parasitics in main.tcl.
    set_app_var timing_enable_auto_mux_clock_exclusivity true
}

proc flow::load_pt_scenario {tag scenario} {
    variable scenarios
    set top [flow::env TOP]
    set run_root [flow::env RUN_ROOT]
    flow::apply_pt_analysis_settings
    set netlist [file join $run_root apr $tag output ${top}.${tag}.v]
    set sdc [file join $run_root apr $tag output ${top}.${tag}.sdc]
    set spef_root [file join $run_root extract $tag output]
    foreach path [list $netlist $sdc] {
        if {![file isfile $path]} {
            flow::fail "PrimeTime input is missing: $path"
        }
    }

    if {![dict exists $scenarios $scenario]} {
        flow::fail "unknown PrimeTime scenario: $scenario"
    }
    lassign [dict get $scenarios $scenario] pvt rc purpose
    set libraries [flow::library_files $pvt]
    set search_path [list .]
    foreach library $libraries {
        lappend search_path [file dirname $library]
    }
    set_app_var search_path [lsort -unique $search_path]
    set_app_var link_path [concat * $libraries]
    read_verilog $netlist
    current_design $top
    if {![link_design $top]} {
        flow::fail "PrimeTime link failed in scenario $scenario"
    }
    set_operating_conditions -analysis_type on_chip_variation
    read_sdc $sdc
    # OCV clock derate per the scenario PVT corner (CX55 legacy
    # bes_data/common/signoff_table.tcl policy).
    flow::apply_signoff_derate $pvt
    set spef [file join $spef_root [flow::spef_name $top $rc]]
    if {![file isfile $spef]} {
        flow::fail "SPEF is missing for scenario $scenario: $spef"
    }
    read_parasitics -keep_capacitive_coupling $spef
}
