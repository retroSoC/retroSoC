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
    variable top [expr {[info exists ::env(TOP)] ? $::env(TOP) : "retrosoc_asic"}]
    variable root [file normalize [file join [file dirname [info script]] ../..]]
    variable run_root [expr {[info exists ::env(RUN_ROOT)] ? $::env(RUN_ROOT) : ""}]
}

proc flow::fail {message} {
    puts stderr "COMMERCIAL_FLOW_ERROR: $message"
    exit 2
}

proc flow::env {name {default __FLOW_REQUIRED__}} {
    if {[info exists ::env($name)] && [string trim $::env($name)] ne ""} {
        if {$::env($name) eq "REQUIRED"} {
            flow::fail "$name is not configured"
        }
        return $::env($name)
    }
    if {$default eq "__FLOW_REQUIRED__"} {
        flow::fail "required environment variable is missing: $name"
    }
    return $default
}

proc flow::env_list {name} {
    set value [string trim [flow::env $name]]
    set result {}
    foreach item $value {
        if {[regexp {[*?\[]} $item]} {
            flow::fail "$name contains a wildcard: $item"
        }
        if {![file exists $item] || ![file readable $item]} {
            flow::fail "$name is not readable: $item"
        }
        lappend result [file normalize $item]
    }
    if {[llength $result] == 0} {
        flow::fail "$name is empty"
    }
    return $result
}

proc flow::ensure_dir {path} {
    if {![file isdirectory $path]} {
        file mkdir $path
    }
}

proc flow::write_text {path text} {
    flow::ensure_dir [file dirname $path]
    set handle [open $path w]
    puts -nonewline $handle $text
    close $handle
}

proc flow::write_pass {path} {
    flow::write_text $path "PASS\n"
}

proc flow::source_hook {name} {
    set path [string trim [flow::env $name ""]]
    if {$path eq ""} {
        return
    }
    if {![file isfile $path] || ![file readable $path]} {
        flow::fail "$name is not a readable Tcl file: $path"
    }
    uplevel #0 [list source $path]
}

proc flow::stage_dirs {area stage} {
    variable run_root
    if {$run_root eq ""} {
        flow::fail "RUN_ROOT is not configured"
    }
    set base [file join $run_root $area $stage]
    foreach name {work log reports output} {
        flow::ensure_dir [file join $base $name]
    }
    return $base
}

proc flow::read_filelist {path} {
    if {![file isfile $path]} {
        flow::fail "RTL filelist does not exist: $path"
    }
    set base [file dirname [file normalize $path]]
    set defines {}
    set incdirs {}
    set sources {}
    set handle [open $path r]
    while {[gets $handle line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string index $line 0] eq "#"} {
            continue
        }
        set line [string trim $line "\""]
        if {[string match "+define+*" $line]} {
            lappend defines [string range $line 8 end]
        } elseif {[string match "+incdir+*" $line]} {
            set item [string range $line 8 end]
            if {[file pathtype $item] ne "absolute"} {
                set item [file join $base $item]
            }
            lappend incdirs [file normalize $item]
        } elseif {[regexp {^-v[ \t]+(.+)$} $line unused item]} {
            set item [string trim $item "\""]
            if {[file pathtype $item] ne "absolute"} {
                set item [file join $base $item]
            }
            lappend sources [file normalize $item]
        } elseif {[regexp {^-f[ \t]+(.+)$} $line unused nested]} {
            set nested [string trim $nested "\""]
            if {[file pathtype $nested] ne "absolute"} {
                set nested [file join $base $nested]
            }
            set child [flow::read_filelist $nested]
            set defines [concat $defines [dict get $child defines]]
            set incdirs [concat $incdirs [dict get $child incdirs]]
            set sources [concat $sources [dict get $child sources]]
        } else {
            if {[file pathtype $line] ne "absolute"} {
                set line [file join $base $line]
            }
            lappend sources [file normalize $line]
        }
    }
    close $handle
    foreach source $sources {
        if {![file isfile $source] || ![file readable $source]} {
            flow::fail "RTL source is not readable: $source"
        }
    }
    set unique_defines {}
    foreach item $defines {
        if {$item ni $unique_defines} {
            lappend unique_defines $item
        }
    }
    set unique_incdirs {}
    foreach item $incdirs {
        if {$item ni $unique_incdirs} {
            lappend unique_incdirs $item
        }
    }
    set unique_sources {}
    foreach item $sources {
        if {$item ni $unique_sources} {
            lappend unique_sources $item
        }
    }
    return [dict create defines $unique_defines \
        incdirs $unique_incdirs sources $unique_sources]
}

proc flow::library_files {pvt} {
    set result {}
    foreach prefix {STD_DB IO_DB SRAM_DB} {
        set result [concat $result [flow::env_list ${prefix}_${pvt}]]
    }
    set result [concat $result [flow::env_list PLL_DB]]
    return [lsort -unique $result]
}

proc flow::all_library_files {} {
    set result {}
    foreach pvt {MAX WCL TYP MIN ML} {
        set result [concat $result [flow::library_files $pvt]]
    }
    return [lsort -unique $result]
}

proc flow::synthesis_library_files {} {
    return [flow::library_files TYP]
}

proc flow::synthesis_target_files {} {
    return [flow::env_list SYN_STD_DB_TYP]
}

proc flow::timing_files {pvt} {
    set result {}
    foreach prefix {STD_LIB IO_LIB SRAM_LIB} {
        set result [concat $result [flow::env_list ${prefix}_${pvt}]]
    }
    set result [concat $result [flow::env_list PLL_LIB]]
    return [lsort -unique $result]
}

proc flow::all_lefs {} {
    set result [flow::env_list TECH_LEF]
    foreach name {STD_LEFS IO_LEFS MACRO_LEFS} {
        set result [concat $result [flow::env_list $name]]
    }
    return [lsort -unique $result]
}

proc flow::report_has_failure {path patterns} {
    if {![file isfile $path]} {
        flow::fail "required report was not written: $path"
    }

    proc flow::count_report_matches {path pattern} {
        if {![file isfile $path]} {
            flow::fail "required report was not written: $path"
        }
        set handle [open $path r]
        set text [read $handle]
        close $handle
        return [regexp -all -nocase -- $pattern $text]
    }

    proc flow::require_qualified_synthesis {} {
        variable run_root
        set summary [file join $run_root syn output synthesis.summary.tsv]
        if {![file isfile $summary]} {
            flow::fail "qualified synthesis summary is missing: $summary"
        }
        array set values {}
        set handle [open $summary r]
        while {[gets $handle line] >= 0} {
            if {[regexp {^([^\t]+)\t([^\t]+)$} $line unused name value]} {
                set values($name) $value
            }
        }

        proc flow::require_commercial_clock_inventory {} {
            set expected {
                clk_external clk_audio clk_jtag clk_dvp clk_usb2_ulpi
                clk_xtal clk_pll clk_system_ext clk_system_pll
            }
            foreach name $expected {
                if {[sizeof_collection [get_clocks -quiet $name]] != 1} {
                    flow::fail "commercial clock is missing or ambiguous: $name"
                }
            }
        }
        close $handle
        foreach name {flow_pass constraints_complete io_qualified} {
            if {![info exists values($name)] || $values($name) ne "yes"} {
                flow::fail "synthesis is not qualified for implementation: $name"
            }
        }
    }
    set handle [open $path r]
    set text [read $handle]
    close $handle
    foreach pattern $patterns {
        if {[regexp -nocase -- $pattern $text]} {
            return 1
        }
    }
    return 0
}
