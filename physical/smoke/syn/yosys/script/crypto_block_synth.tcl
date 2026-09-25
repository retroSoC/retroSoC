# Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# SPDX-License-Identifier: MulanPSL-2.0
# Diagnostic checkpoints around the UNCHANGED full-SoC synthesis recipe.
# The only elaboration difference is the explicit standalone interface boundary.
rename yosys crypto_original_yosys
proc yosys {args} {
    set command [lindex $args 0]
    if {$command eq "read_slang"} {
        lappend args --allow-toplevel-iface-ports
    }
    if {$command eq "memory"} {
        crypto_original_yosys write_json "$::env(REPORTS)/pre_memory_design.json"
    }
    if {$command eq "opt_dff" && [lsearch -exact $args -sat] >= 0} {
        crypto_original_yosys write_json "$::env(REPORTS)/pre_sat_design.json"
    }
    set result [uplevel 1 [list crypto_original_yosys {*}$args]]
    if {$command eq "proc"} {
        crypto_original_yosys write_json "$::env(REPORTS)/initial_design.json"
    }
    if {$command eq "opt_dff" && [lsearch -exact $args -sat] >= 0} {
        crypto_original_yosys write_json "$::env(REPORTS)/post_sat_design.json"
    }
    return $result
}
source [file join [file dirname [info script]] synth.tcl]
crypto_original_yosys write_json "$::env(REPORTS)/mapped_design.json"
