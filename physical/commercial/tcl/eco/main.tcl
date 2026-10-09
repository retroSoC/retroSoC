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

proc eco_flag {name} {
    set value [string toupper [flow::env $name NO]]
    if {$value ni {YES NO}} {
        flow::fail "$name must be YES or NO"
    }
    return [expr {$value eq "YES"}]
}

proc eco_pba_mode {} {
    set mode [string tolower [flow::env ECO_PBA_MODE none]]
    if {$mode ni {none path exhaustive}} {
        flow::fail "ECO_PBA_MODE must be none, path, or exhaustive"
    }
    return $mode
}

proc run_eco {} {
    set run_root [flow::env RUN_ROOT]
    set top [flow::env TOP]
    set base [flow::stage_dirs eco ""]
    set report_dir [file join $run_root eco reports]
    set output_dir [file join $run_root eco output]
    set work_dir [file join $run_root eco work]

    set process_count [flow::env ECO_MAX_PROCESSES]
    if {$process_count > [dict size $::flow::scenarios]} {
        set process_count [dict size $::flow::scenarios]
    }
    set_host_option -max_cores 1 -num_processes $process_count \
        -name retroSoC_ECO
    start_hosts
    dict for {scenario unused} $::flow::scenarios {
        set image [file join $run_root sta route work sessions $scenario]
        if {![file isdirectory $image]} {
            flow::fail "missing PrimeTime session image: $image"
        }
        create_scenario -name $scenario -image $image
    }
    current_session -all

    set eco_tech_lef [flow::env TECH_LEF]
    set eco_lefs [concat [flow::env_list STD_LEFS] \
        [flow::env_list IO_LEFS] [flow::env_list MACRO_LEFS]]
    set eco_def [file join $run_root apr route output ${top}.route.def]
    set eco_dont_use [flow::env_list SYN_DONT_USE]
    set_distributed_variables {eco_tech_lef eco_lefs eco_def eco_dont_use}
    remote_execute {
        set_eco_options -physical_enable_clock_data \
            -physical_tech_lib_path $eco_tech_lef \
            -physical_lib_path $eco_lefs \
            -physical_design_path $eco_def \
            -log_file load_physical.log
        foreach pattern $eco_dont_use {
            set cells [get_lib_cells -quiet */$pattern]
            if {[sizeof_collection $cells] != 0} {
                set_dont_use $cells
            }
        }
        update_timing -full
    }

    redirect [file join $report_dir setup.rpt] {
        fix_eco_timing -type setup -methods size_cell \
            -setup_margin [flow::env ECO_SETUP_MARGIN_NS] \
            -hold_margin [flow::env ECO_HOLD_MARGIN_NS] \
            -physical_mode [flow::env ECO_PHYSICAL_MODE] -verbose
        fix_eco_timing -type setup -methods insert_buffer \
            -buffer_list [flow::env ECO_SETUP_BUFFERS] \
            -setup_margin [flow::env ECO_SETUP_MARGIN_NS] \
            -hold_margin [flow::env ECO_HOLD_MARGIN_NS] \
            -physical_mode [flow::env ECO_PHYSICAL_MODE] -verbose
    }
    # Optional power-recovery subflows (legacy pd_data/pteco/scr/flow/swap.tcl
    # and size_down.tcl); both default off and run after the setup fix.
    if {[eco_flag ECO_ENABLE_VT_SWAP]} {
        define_user_attribute -type string -class lib_cell cell_footprint -import
        set_app_var eco_alternative_cell_attribute_restrictions \
            "area cell_footprint"
        set_app_var eco_alternative_area_ratio_threshold 2
        remote_execute {
            define_user_attribute -type string -class lib_cell cell_footprint -import
            set_app_var eco_alternative_cell_attribute_restrictions \
                "area cell_footprint"
            set_app_var eco_alternative_area_ratio_threshold 2
            update_timing -full
        }
        redirect [file join $report_dir vt_swap.rpt] {
            fix_eco_power -methods size_cell \
                -pattern_priority [flow::env ECO_VT_PATTERN_PRIORITY] \
                -setup_margin [flow::env ECO_SETUP_MARGIN_NS] \
                -pba_mode [eco_pba_mode] -verbose
        }
    }
    if {[eco_flag ECO_ENABLE_SIZE_DOWN]} {
        redirect [file join $report_dir size_down.rpt] {
            fix_eco_power -methods size_cell \
                -setup_margin [flow::env ECO_SETUP_MARGIN_NS] \
                -pba_mode [eco_pba_mode] -verbose
        }
    }
    redirect [file join $report_dir hold.rpt] {
        fix_eco_timing -type hold -methods insert_buffer \
            -buffer_list [flow::env ECO_HOLD_BUFFERS] \
            -setup_margin [flow::env ECO_SETUP_MARGIN_NS] \
            -hold_margin [flow::env ECO_HOLD_MARGIN_NS] \
            -physical_mode [flow::env ECO_PHYSICAL_MODE] -verbose
    }
    # Optional redundant-buffer removal (legacy
    # pd_data/pteco/scr/flow/remove_buffer.tcl); defaults off and runs after
    # the hold fix, matching the legacy flow order.
    if {[eco_flag ECO_ENABLE_REMOVE_BUFFER]} {
        redirect [file join $report_dir remove_buffer.rpt] {
            fix_eco_power -methods remove_buffer \
                -setup_margin [flow::env ECO_SETUP_MARGIN_NS] \
                -hold_margin [flow::env ECO_HOLD_MARGIN_NS] \
                -pba_mode [eco_pba_mode] -verbose
        }
    }
    redirect [file join $report_dir drc.rpt] {
        foreach type {max_transition max_capacitance} {
            fix_eco_drc -type $type -methods size_cell \
                -setup_margin [flow::env ECO_SETUP_MARGIN_NS] \
                -hold_margin [flow::env ECO_HOLD_MARGIN_NS] \
                -physical_mode [flow::env ECO_PHYSICAL_MODE] -verbose
            fix_eco_drc -type $type -methods insert_buffer \
                -buffer_list [flow::env ECO_SETUP_BUFFERS] \
                -setup_margin [flow::env ECO_SETUP_MARGIN_NS] \
                -hold_margin [flow::env ECO_HOLD_MARGIN_NS] \
                -physical_mode [flow::env ECO_PHYSICAL_MODE] -verbose
        }
    }

    # Every scenario records its own change list in DMSA (legacy
    # pd_data/pteco/scr/app/output.tcl writes changes from every worker);
    # exporting only one scenario drops scenario-specific fixes. Iterate over
    # every scenario with a current session so each write_changes lands in a
    # dedicated file, then let translate_eco.py merge and deduplicate them.
    set raw_changes {}
    dict for {scenario unused} $::flow::scenarios {
        set eco_raw [file join $work_dir ${scenario}.icc2.tcl]
        set_distributed_variables {eco_raw}
        current_session $scenario
        remote_execute { write_changes -format icc2tcl -output $eco_raw }
        lappend raw_changes $eco_raw
    }
    set command [list [flow::env FLOW_PYTHON python] \
        [file join $::flow::root scripts translate_eco.py] \
        --output [file join $output_dir eco.tcl] --allow-empty]
    foreach raw $raw_changes {
        lappend command --input $raw
    }
    if {[catch {exec {*}$command} message]} {
        flow::fail "PrimeTime ECO translation failed: $message"
    }
    flow::write_pass [file join $output_dir verdict.pass]
}

if {[catch {run_eco} message options]} {
    puts stderr $message
    if {[dict exists $options -errorinfo]} {
        puts stderr [dict get $options -errorinfo]
    }
    exit 2
}
exit
