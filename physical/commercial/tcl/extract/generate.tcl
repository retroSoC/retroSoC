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

proc generate_starrc {} {
    set top [flow::env TOP]
    set run_root [flow::env RUN_ROOT]
    set tag [string tolower [flow::env EXTRACT_TAG]]
    if {$tag ni {route eco}} {
        flow::fail "unsupported extraction tag: $tag"
    }
    set base [flow::stage_dirs extract $tag]
    set work_dir [file join $base work]
    set report_dir [file join $base reports]
    set output_dir [file join $base output]
    set def_file [file join $run_root apr $tag output ${top}.${tag}.def]
    if {![file isfile $def_file]} {
        flow::fail "routed DEF is missing: $def_file"
    }

    set corners_file [file join $work_dir corners.star]
    set handle [open $corners_file w]
    set selected {}
    dict for {corner values} $::flow::extraction_corners {
        lassign $values rc temperature tech_var
        set technology [lindex [flow::env_list $tech_var] 0]
        lappend selected ${corner}.spef
        puts $handle "CORNER_NAME             : ${corner}.spef"
        puts $handle "TCAD_GRD_FILE           : $technology"
        puts $handle "OPERATING_TEMPERATURE   : $temperature"
        puts $handle ""
    }
    close $handle

    set command_file [file join $work_dir ${top}.star]
    set handle [open $command_file w]
    puts $handle "BLOCK                        : $top"
    puts $handle "BUS_BIT                      : \[\]"
    puts $handle "CASE_SENSITIVE               : YES"
    puts $handle "HIERARCHICAL_SEPARATOR       : /"
    puts $handle "LEF_FILE                     : [join [flow::all_lefs] { }]"
    puts $handle "TOP_DEF_FILE                 : $def_file"
    puts $handle "CORNERS_FILE                 : $corners_file"
    puts $handle "SELECTED_CORNERS             : [join $selected { }]"
    puts $handle "SIMULTANEOUS_MULTI_CORNER    : YES"
    puts $handle "EXTRACTION                   : RC"
    puts $handle "COUPLE_TO_GROUND             : NO"
    puts $handle "EXTRACT_VIA_CAPS             : YES"
    puts $handle "MAPPING_FILE                 : [lindex [flow::env_list STARRC_MAP] 0]"
    puts $handle "NETS                         : *"
    puts $handle "NUM_CORES                    : [flow::env STARRC_CORES 8]"
    puts $handle "POWER_EXTRACT                : NO"
    puts $handle "POWER_NETS                   : [flow::env APR_POWER_NET] [flow::env APR_GROUND_NET]"
    puts $handle "STAR_DIRECTORY               : [file join $work_dir database]"
    puts $handle "SUMMARY_FILE                 : [file join $report_dir ${top}.summary]"
    puts $handle "NETLIST_COMPRESS_COMMAND     : gzip"
    puts $handle "NETLIST_FILE                 : [file join $output_dir ${top}.gz]"
    puts $handle "NETLIST_FORMAT               : SPEF"
    puts $handle "NETLIST_NODE_SECTION         : YES"
    puts $handle "REDUCTION                    : NO_EXTRA_LOOPS"
    puts $handle "COUPLING_ABS_THRESHOLD       : 1E-15"
    puts $handle "COUPLING_REL_THRESHOLD       : 0.01"
    close $handle
}

if {[catch {generate_starrc} message options]} {
    puts stderr $message
    if {[dict exists $options -errorinfo]} {
        puts stderr [dict get $options -errorinfo]
    }
    exit 2
}
