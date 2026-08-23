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

proc quote_svrf {value} {
    return "\"[string map {\" \\\"} $value]\""
}

proc write_merge {run_root top} {
    set base [flow::stage_dirs pv merge]
    set input [file join $run_root apr eco output ${top}.eco.gds]
    set output [file join $base output ${top}.merged.gds]
    set verdict [file join $base output verdict.pass]
    set gds [concat [flow::env_list STD_GDS] [flow::env_list IO_GDS] \
        [flow::env_list MACRO_GDS]]
    set handle [open [file join $base work merge.tcl] w]
    puts $handle [list set input_gds $input]
    puts $handle [list set output_gds $output]
    puts $handle [list set top $top]
    puts $handle [list set library_gds $gds]
    puts $handle {if {[file exists $output_gds]} {
    file delete -force $output_gds
}}
    puts $handle [list set verdict $verdict]
    puts $handle {if {[file exists $verdict]} {
    file delete -force $verdict
}}
    puts $handle {set database [layout create $input_gds -dt_expand -preservePaths -preserveProperties]}
    puts $handle {foreach path $library_gds {
    if {![file isfile $path] || ![file readable $path]} {
        error "GDS is not readable: $path"
    }
    $database import layout $path false overwrite -dt_expand -preservePaths -preserveProperties
}}
    puts $handle {$database gdsout $output_gds $top}
    puts $handle {set marker [open $verdict w]
puts $marker "PASS"
close $marker}
    close $handle
}

proc write_drc {run_root top mode} {
    set base [flow::stage_dirs pv $mode]
    set gds [file join $run_root pv merge output ${top}.merged.gds]
    set runset [file join $base work ${mode}.runset]
    set deck_var [expr {$mode eq "drc" ? "CALIBRE_DRC_DECK" : "CALIBRE_ANT_DECK"}]
    set deck [lindex [flow::env_list $deck_var] 0]
    set handle [open $runset w]
    puts $handle "LAYOUT PATH [quote_svrf $gds]"
    puts $handle "LAYOUT PRIMARY [quote_svrf $top]"
    puts $handle "LAYOUT SYSTEM GDSII"
    puts $handle "DRC RESULTS DATABASE [quote_svrf [file join $base output ${top}.${mode}.results]] ASCII"
    puts $handle "DRC SUMMARY REPORT [quote_svrf [file join $base reports ${top}.${mode}.summary]]"
    puts $handle "DRC MAXIMUM RESULTS ALL"
    puts $handle "INCLUDE [quote_svrf $deck]"
    close $handle
}

proc write_lvs {run_root top} {
    set base [flow::stage_dirs pv lvs]
    set gds [file join $run_root pv merge output ${top}.merged.gds]
    set source [file join $base work ${top}.cdl]
    set includes [file join $base work includes.cdl]
    set handle [open $includes w]
    foreach path [concat [flow::env_list STD_CDL] [flow::env_list IO_CDL] \
            [flow::env_list MACRO_CDL]] {
        puts $handle ".INCLUDE \"$path\""
    }
    close $handle

    set hcells [file join $base work hcells.txt]
    set handle [open $hcells w]
    set seen {}
    foreach path [concat [flow::env_list STD_CDL] [flow::env_list IO_CDL] \
            [flow::env_list MACRO_CDL]] {
        set input [open $path r]
        while {[gets $input line] >= 0} {
            if {[regexp -nocase {^[ \t]*\.SUBCKT[ \t]+([^ \t]+)} $line unused cell] &&
                    ![dict exists $seen $cell]} {
                dict set seen $cell 1
                puts $handle "$cell $cell"
            }
        }
        close $input
    }
    close $handle

    set runset [file join $base work lvs.runset]
    set handle [open $runset w]
    puts $handle "LAYOUT PATH [quote_svrf $gds]"
    puts $handle "LAYOUT PRIMARY [quote_svrf $top]"
    puts $handle "LAYOUT SYSTEM GDSII"
    puts $handle "SOURCE PATH [quote_svrf $source]"
    puts $handle "SOURCE PRIMARY [quote_svrf $top]"
    puts $handle "SOURCE SYSTEM SPICE"
    puts $handle "LVS REPORT [quote_svrf [file join $base reports ${top}.lvs.rpt]]"
    puts $handle "LVS REPORT MAXIMUM ALL"
    puts $handle "LVS SPICE CULL PRIMITIVE SUBCIRCUITS YES"
    puts $handle "LVS SPICE OVERRIDE GLOBALS YES"
    puts $handle "LVS RECOGNIZE GATES NONE"
    puts $handle "LVS EXECUTE ERC YES"
    puts $handle "INCLUDE [quote_svrf [lindex [flow::env_list CALIBRE_LVS_DECK] 0]]"
    close $handle

    set driver [file join $base work lvs_driver.tcl]
    set verilog [file join $run_root apr eco output ${top}.eco.pg.v]
    set verdict [file join $base output verdict.pass]
    set handle [open $driver w]
    puts $handle [list set v2lvs [flow::env V2LVS]]
    puts $handle [list set calibre [flow::env CALIBRE]]
    puts $handle [list set verilog $verilog]
    puts $handle [list set includes $includes]
    puts $handle [list set source $source]
    puts $handle [list set hcells $hcells]
    puts $handle [list set runset $runset]
    puts $handle [list set report [file join $base reports ${top}.lvs.rpt]]
    puts $handle [list set verdict $verdict]
    puts $handle {if {[file exists $verdict]} {
    file delete -force $verdict
}
set started [clock seconds]
set convert [concat $v2lvs [list -v $verilog -lsr $includes -s $includes -o $source]]
if {[catch {exec {*}$convert >@ stdout 2>@ stderr} message]} {
    puts stderr $message
    exit 2
}
set verify [concat $calibre [list -64 -lvs -hier -hcell $hcells $runset]]
if {[catch {exec {*}$verify >@ stdout 2>@ stderr} message]} {
    puts stderr $message
    exit 2
}
if {![file isfile $report]} {
    puts stderr "missing LVS report: $report"
    exit 2
}
if {[file mtime $report] < ($started - 2)} {
    puts stderr "LVS report was not refreshed: $report"
    exit 2
}
set input [open $report r]
set text [read $input]
close $input
if {![regexp -indices -nocase \
        {OVERALL[ \t\r\n]+COMPARISON[ \t\r\n]+RESULTS} $text summary_indices]} {
    puts stderr "LVS report has no overall comparison result"
    exit 2
}
set summary_start [lindex $summary_indices 0]
set summary [string range $text $summary_start [expr {$summary_start + 2000}]]
if {![regexp -nocase {(^|[^A-Za-z])CORRECT([^A-Za-z]|$)} $summary] ||
        [regexp -nocase {INCORRECT|NOT[ \t]+COMPARED|ERROR:} $text]} {
    puts stderr "LVS did not complete cleanly"
    exit 2
}
set marker [open $verdict w]
puts $marker "PASS"
close $marker}
    close $handle
}

proc generate_pv {} {
    set run_root [flow::env RUN_ROOT]
    set top [flow::env TOP]
    set mode [string tolower [flow::env PV_MODE]]
    switch -- $mode {
        merge { write_merge $run_root $top }
        drc - antenna { write_drc $run_root $top $mode }
        lvs { write_lvs $run_root $top }
        default { flow::fail "unsupported PV mode: $mode" }
    }
}

if {[catch {generate_pv} message options]} {
    puts stderr $message
    if {[dict exists $options -errorinfo]} {
        puts stderr [dict get $options -errorinfo]
    }
    exit 2
}
