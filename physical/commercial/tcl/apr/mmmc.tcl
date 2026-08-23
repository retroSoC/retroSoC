# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

proc flow::write_mmmc {path sdc} {
    variable scenarios
    set handle [open $path w]
    puts $handle "# Generated commercial MMMC configuration; do not edit."
    foreach pvt {MAX WCL TYP MIN ML} {
        puts $handle [list create_library_set -name lib_$pvt \
            -timing [flow::timing_files $pvt]]
    }

    set seen_rc {}
    dict for {scenario values} $scenarios {
        lassign $values pvt rc purpose
        if {$rc ni $seen_rc} {
            lappend seen_rc $rc
            set rc_values [dict get $::flow::extraction_corners $rc]
            set temperature [lindex $rc_values 1]
            puts $handle [list create_rc_corner -name rc_$rc \
                -cap_table [flow::rc_cap_table $rc] -T $temperature]
        }
        puts $handle [list create_delay_corner -name delay_${pvt}_${rc} \
            -library_set lib_$pvt -rc_corner rc_$rc]
    }
    puts $handle [list create_constraint_mode -name func -sdc_files [list $sdc]]

    set setup_views {}
    set hold_views {}
    dict for {scenario values} $scenarios {
        lassign $values pvt rc purpose
        puts $handle [list create_analysis_view -name $scenario \
            -constraint_mode func -delay_corner delay_${pvt}_${rc}]
        if {$purpose in {setup both}} {
            lappend setup_views $scenario
        }
        if {$purpose in {hold both}} {
            lappend hold_views $scenario
        }
    }
    puts $handle [list set_analysis_view -setup $setup_views -hold $hold_views]
    close $handle
}
