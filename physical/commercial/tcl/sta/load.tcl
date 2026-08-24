# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

proc flow::load_pt_scenario {tag scenario} {
    variable scenarios
    set top [flow::env TOP]
    set run_root [flow::env RUN_ROOT]
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
    set spef [file join $spef_root [flow::spef_name $top $rc]]
    if {![file isfile $spef]} {
        flow::fail "SPEF is missing for scenario $scenario: $spef"
    }
    read_parasitics -keep_capacitive_coupling $spef
}
