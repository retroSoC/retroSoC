# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

namespace eval flow {
    variable extraction_corners {
        Cworst_m40  {Cworst -40 NXTGRD_CWORST}
        Cworst_125  {Cworst 125 NXTGRD_CWORST}
        RCworst_m40 {RCworst -40 NXTGRD_RCWORST}
        RCworst_125 {RCworst 125 NXTGRD_RCWORST}
        Cbest_m40   {Cbest -40 NXTGRD_CBEST}
        Cbest_125   {Cbest 125 NXTGRD_CBEST}
        RCbest_m40  {RCbest -40 NXTGRD_RCBEST}
        RCbest_125  {RCbest 125 NXTGRD_RCBEST}
        TYP_25      {TYP 25 NXTGRD_TYP}
    }

    variable scenarios {
        func_MAX_Cworst_125   {MAX Cworst_125 setup}
        func_MAX_RCworst_125  {MAX RCworst_125 setup}
        func_WCL_Cworst_m40   {WCL Cworst_m40 setup}
        func_WCL_RCworst_m40  {WCL RCworst_m40 setup}
        func_TYP_TYP_25       {TYP TYP_25 both}
        func_MIN_Cworst_m40   {MIN Cworst_m40 hold}
        func_MIN_RCworst_m40  {MIN RCworst_m40 hold}
        func_MIN_Cbest_m40    {MIN Cbest_m40 hold}
        func_MIN_RCbest_m40   {MIN RCbest_m40 hold}
        func_ML_Cworst_125    {ML Cworst_125 hold}
        func_ML_RCworst_125   {ML RCworst_125 hold}
        func_ML_Cbest_125     {ML Cbest_125 hold}
        func_ML_RCbest_125    {ML RCbest_125 hold}
    }
}

proc flow::rc_cap_table {corner} {
    switch -glob -- $corner {
        Cworst_*  { return [lindex [flow::env_list CAP_TABLE_CWORST] 0] }
        RCworst_* { return [lindex [flow::env_list CAP_TABLE_RCWORST] 0] }
        Cbest_*   { return [lindex [flow::env_list CAP_TABLE_CBEST] 0] }
        RCbest_*  { return [lindex [flow::env_list CAP_TABLE_RCBEST] 0] }
        TYP_*     { return [lindex [flow::env_list CAP_TABLE_TYP] 0] }
        default   { flow::fail "unknown RC corner: $corner" }
    }
}

proc flow::spef_name {top corner} {
    return "${top}.${corner}.spef.gz"
}

# CX55 OCV policy for PrimeTime signoff (legacy bes_data/common/
# signoff_table.tcl:364-390, expanded by bes_data/sta/scr/flow_com/
# transform_signoff_table.tcl:10-25; command forms verified in legacy PT logs
# bes_data/sta/log/asic_top_V2026_1_CTS_MIN_CWORST.log and
# asic_top_CTS_TYP_TYP.log:2672-2673):
#   MAX/WCL: clock-path early derate 0.95 (cell and net), all other arcs unity
#   MIN/ML:  clock-path early derate 0.90 (cell and net), all other arcs unity
#   TYP:     unqualified "set_timing_derate -early 0.95" with unity late (the
#            legacy "default default" entry)
# The legacy DC synthesis run linked the TYP library and applied no timing
# derate at all (bes_data/syn/scr/flow_com/syn_common_flow.tcl never sources
# signoff_table.tcl; bes_data/syn/log/asic_top.log contains no
# set_timing_derate), so the synthesis flow does not call this helper.
proc flow::apply_signoff_derate {pvt} {
    switch -glob -- $pvt {
        MAX - WCL {
            set cell_early [flow::env TIMING_DERATE_SETUP_CELL_CLOCK_EARLY 0.95]
            set net_early [flow::env TIMING_DERATE_SETUP_NET_CLOCK_EARLY 0.95]
        }
        MIN - ML {
            set cell_early [flow::env TIMING_DERATE_HOLD_CELL_CLOCK_EARLY 0.90]
            set net_early [flow::env TIMING_DERATE_HOLD_NET_CLOCK_EARLY 0.90]
        }
        default {
            set early [flow::env TIMING_DERATE_DEFAULT_EARLY 0.95]
            if {$early != 1.0} {
                set_timing_derate -late 1.0
                set_timing_derate -early $early
            }
            return
        }
    }
    set_timing_derate -cell_delay -clock -early $cell_early
    set_timing_derate -cell_delay -clock -late 1.0
    set_timing_derate -cell_delay -data -early 1.0
    set_timing_derate -cell_delay -data -late 1.0
    set_timing_derate -net_delay -clock -early $net_early
    set_timing_derate -net_delay -clock -late 1.0
    set_timing_derate -net_delay -data -early 1.0
    set_timing_derate -net_delay -data -late 1.0
}

# Innovus derate and per-stage setup uncertainty (legacy
# pd_data/pr/scr/CL1/set_derate_uncertainty.tcl).
proc flow::apply_apr_derate {} {
    set clock_early [flow::env APR_DERATE_CLOCK_EARLY 1.0]
    set clock_late [flow::env APR_DERATE_CLOCK_LATE 1.0]
    set data_late [flow::env APR_DERATE_DATA_LATE 1.0]
    if {$clock_early != 1.0} {
        set_timing_derate -early $clock_early -clock \
            -delay_corner [all_delay_corners]
    }
    if {$clock_late != 1.0} {
        set_timing_derate -late $clock_late -clock \
            -delay_corner [all_delay_corners]
    }
    if {$data_late != 1.0} {
        set_timing_derate -late $data_late -data -delay_corner [all_delay_corners]
    }
}

proc flow::apply_apr_stage_uncertainty {stage} {
    switch -- $stage {
        place { set value [flow::env APR_SETUP_UNCERTAINTY_PLACE_NS ""] }
        cts { set value [flow::env APR_SETUP_UNCERTAINTY_CTS_NS ""] }
        route { set value [flow::env APR_SETUP_UNCERTAINTY_ROUTE_NS ""] }
        default { set value "" }
    }
    if {$value ne ""} {
        set_clock_uncertainty -setup $value [all_clocks]
    }
}
