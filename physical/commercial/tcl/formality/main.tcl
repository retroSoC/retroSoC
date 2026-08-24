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

proc read_reference_rtl {filelist top} {
    set rtl [flow::read_filelist $filelist]
    foreach source [dict get $rtl sources] {
        set command [list read_sverilog -r -work_library WORK]
        if {[llength [dict get $rtl defines]] > 0} {
            lappend command -define [dict get $rtl defines]
        }
        lappend command $source
        eval $command
    }
    set_top r:/WORK/$top
}

proc run_formality {} {
    set top [flow::env TOP]
    set run_root [flow::env RUN_ROOT]
    set mode [flow::env FM_MODE]
    set lower_mode [string tolower $mode]
    if {$mode ni {RTL2SYN SYN2PR}} {
        flow::fail "unsupported Formality mode: $mode"
    }
    set base [flow::stage_dirs formality $lower_mode]
    set report_dir [file join $base reports]
    set output_dir [file join $base output]
    set libraries [flow::synthesis_library_files]

    set rtl_filelist [file join $run_root input rtl filelist.fl]
    set rtl [flow::read_filelist $rtl_filelist]
    set search_path [concat [list .] [dict get $rtl incdirs]]
    foreach library $libraries {
        lappend search_path [file dirname $library]
    }
    set_app_var search_path [lsort -unique $search_path]
    set_app_var link_library [concat * $libraries]
    set verification_set_undriven_signals synthesis
    set verification_assume_reg_init true

    foreach library $libraries {
        read_db -technology_library $library
    }

    if {$mode eq "RTL2SYN"} {
        read_reference_rtl $rtl_filelist $top
        set_svf [file join $run_root syn output ${top}.svf]
        read_verilog -i [file join $run_root syn output ${top}.syn.v]
    } else {
        read_verilog -r [file join $run_root syn output ${top}.syn.v]
        set_top r:/WORK/$top
        read_verilog -i [file join $run_root apr route output ${top}.route.v]
    }
    set_top i:/WORK/$top

    if {![match]} {
        redirect [file join $report_dir unmatched.rpt] { report_unmatched_points }
        flow::fail "Formality matching failed"
    }
    redirect [file join $report_dir unmatched.rpt] { report_unmatched_points }
    redirect [file join $report_dir matched.rpt] { report_matched_points }
    redirect [file join $report_dir setup.rpt] { report_setup_status }

    set unmatched_count [sizeof_collection [get_unmatched_points]]
    if {$unmatched_count != 0} {
        flow::fail "Formality has $unmatched_count unmatched points"
    }
    if {![verify]} {
        redirect [file join $report_dir failing.rpt] { report_failing_points }
        flow::fail "Formality verification failed"
    }
    redirect [file join $report_dir status.rpt] { report_verification_status }
    flow::write_pass [file join $output_dir verdict.pass]
}

if {[catch {run_formality} message options]} {
    puts stderr $message
    if {[dict exists $options -errorinfo]} {
        puts stderr [dict get $options -errorinfo]
    }
    exit 2
}
exit
