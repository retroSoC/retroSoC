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
source [file join $flow_root tcl apr mmmc.tcl]

proc restore_previous {run_root top stage} {
    array set previous {
        floorplan initialize
        preplace floorplan
        place preplace
        cts place
        route cts
        eco route
    }
    if {![info exists previous($stage)]} {
        flow::fail "no previous APR stage for $stage"
    }
    set prior $previous($stage)
    set database [file join $run_root apr $prior output ${top}.${prior}.enc.dat]
    if {![file isdirectory $database]} {
        flow::fail "APR checkpoint is missing: $database"
    }
    restoreDesign $database $top
}

proc connect_power_nets {} {
    set power [flow::env APR_POWER_NET]
    set ground [flow::env APR_GROUND_NET]
    foreach pin [flow::env APR_POWER_PINS] {
        globalNetConnect $power -type pgpin -pin $pin -all -verbose
    }
    foreach pin [flow::env APR_GROUND_PINS] {
        globalNetConnect $ground -type pgpin -pin $pin -all -verbose
    }
    globalNetConnect $power -type tiehi -all -verbose
    globalNetConnect $ground -type tielo -all -verbose
    applyGlobalNets
}

proc write_io_ring {path} {
    set die_width [flow::env DIE_WIDTH]
    set die_height [flow::env DIE_HEIGHT]
    set offset [flow::env APR_IO_OFFSET]
    set pitch [flow::env APR_IO_PITCH]
    set records {}
    foreach cell [flow::env APR_SIGNAL_PAD_CELLS] {
        set query [dbGet [dbGet -p2 top.insts.cell.name $cell].name]
        if {$query eq "0x0"} {
            continue
        }
        foreach instance $query {
            lappend records [list $instance $cell]
        }
    }
    set records [lsort -index 0 -unique $records]
    if {[llength $records] == 0} {
        flow::fail "no configured ICS55 signal pad cells were found"
    }

    set power_records {}
    set index 0
    foreach cell [flow::env APR_IO_POWER_CELLS] {
        lappend power_records [list POWER_$index $cell]
        incr index
    }
    if {[llength $power_records] == 0} {
        flow::fail "APR_IO_POWER_CELLS is empty"
    }

    array set sides {top {} right {} bottom {} left {}}
    set side_names {top right bottom left}
    set index 0
    foreach record $records {
        set side [lindex $side_names [expr {$index % 4}]]
        lappend sides($side) $record
        incr index
    }

    set handle [open $path w]
    puts $handle {(globals
    version = 3
    io_order = default
)
(iopad}
    set corners {
        topright CORNER_NE
        topleft CORNER_NW
        bottomleft CORNER_SW
        bottomright CORNER_SE
    }
    foreach {side name} $corners {
        puts $handle "    ($side"
        puts $handle "        (inst name=\"$name\" rel_orientation=R0 cell=\"[flow::env APR_IO_CORNER_CELL]\" )"
        puts $handle "    )"
        if {$side eq "topright"} {
            write_io_side $handle top $sides(top) $power_records $offset $pitch $die_width
        } elseif {$side eq "topleft"} {
            write_io_side $handle left $sides(left) $power_records $offset $pitch $die_height
        } elseif {$side eq "bottomleft"} {
            write_io_side $handle bottom $sides(bottom) $power_records $offset $pitch $die_width
        } else {
            write_io_side $handle right $sides(right) $power_records $offset $pitch $die_height
        }
    }
    puts $handle {)}
    close $handle
}

proc write_io_side {handle side signals power_records offset pitch length} {
    set records {}
    set split [expr {[llength $signals] / 2}]
    set records [concat [lrange $power_records 0 1] \
        [lrange $signals 0 [expr {$split - 1}]] \
        [lrange $power_records 2 end] [lrange $signals $split end]]
    set last [expr {$offset + $pitch * ([llength $records] - 1)}]
    if {$last > ($length - $offset)} {
        flow::fail "ICS55 $side pad ring exceeds the configured die dimension"
    }
    puts $handle "    ($side"
    set index 0
    foreach record $records {
        lassign $record instance cell
        if {[string match POWER_* $instance]} {
            set instance ${instance}_${side}
        }
        set position [expr {$offset + $pitch * $index}]
        puts $handle "        (inst name=\"$instance\" offset=$position relorientation=R0 cell=\"$cell\" )"
        incr index
    }
    puts $handle "    )"
}

proc write_apr_reports {report_dir stage} {
    redirect [file join $report_dir ${stage}.summary.rpt] { summaryReport }
    redirect [file join $report_dir ${stage}.timing.rpt] {
        timeDesign -expandedViews -numPaths 1000
    }
    redirect [file join $report_dir ${stage}.design.rpt] { checkDesign -all }
}

proc verify_route {report_dir} {
    set connectivity [file join $report_dir connectivity.rpt]
    set geometry [file join $report_dir geometry.rpt]
    verifyConnectivity -type all -error 100000 -warning 100000 -report $connectivity
    verifyGeometry -report $geometry
    foreach report [list $connectivity $geometry] {
        if {[flow::report_has_failure $report \
                {{Total[^\n]*Violations?[ \t]*:[ \t]*[1-9]} \
                 {^ERROR} {unconnected[^\n]*[1-9]}}]} {
            flow::fail "APR physical verification failed: $report"
        }
    }
}

proc write_data_out {run_root top stage output_dir report_dir} {
    set prefix [file join $output_dir ${top}.${stage}]
    defOut -floorplan -netlist -routing ${prefix}.def
    saveNetlist ${prefix}.v
    saveNetlist -includePowerGround ${prefix}.pg.v
    write_sdc ${prefix}.sdc
    write_sdf -version 3.0 ${prefix}.sdf
    streamOut ${prefix}.gds -mapFile [flow::env STREAM_MAP] \
        -structureName $top -mode ALL
    verify_route $report_dir
}

proc run_apr {} {
    flow::require_qualified_synthesis
    set top [flow::env TOP]
    set run_root [flow::env RUN_ROOT]
    set stage [string tolower [flow::env APR_STAGE]]
    if {$stage ni {initialize floorplan preplace place cts route eco}} {
        flow::fail "unsupported APR stage: $stage"
    }
    set base [flow::stage_dirs apr $stage]
    set work_dir [file join $base work]
    set report_dir [file join $base reports]
    set output_dir [file join $base output]

    setMultiCpuUsage -localCpu 8
    setMultiCpuUsage -keepLicense true

    if {$stage eq "initialize"} {
        set mmmc [file join $work_dir mmmc.tcl]
        flow::write_mmmc $mmmc [file join $run_root syn output ${top}.syn.sdc]
        set init_top_cell $top
        set init_verilog [file join $run_root syn output ${top}.syn.v]
        set init_lef_file [flow::all_lefs]
        set init_mmmc_file $mmmc
        set init_pwr_net [flow::env APR_POWER_NET]
        set init_gnd_net [flow::env APR_GROUND_NET]
        init_design
        connect_power_nets
    } else {
        restore_previous $run_root $top $stage
    }
    flow::require_commercial_clock_inventory

    switch -- $stage {
        initialize {
            checkDesign -all
        }
        floorplan {
            floorPlan -site [flow::env APR_SITE] -d \
                [flow::env DIE_WIDTH] [flow::env DIE_HEIGHT] \
                [flow::env CORE_MARGIN_LEFT] [flow::env CORE_MARGIN_BOTTOM] \
                [flow::env CORE_MARGIN_RIGHT] [flow::env CORE_MARGIN_TOP]
            set io_file [file join $work_dir ${top}.io]
            write_io_ring $io_file
            loadIoFile $io_file
            fixAllIos
            addIoFiller -cell [flow::env APR_IO_FILLERS] -prefix IOFILL
            flow::source_hook APR_FLOORPLAN_HOOK
            connect_power_nets
            set ring_layers [flow::env APR_RING_LAYERS]
            if {[llength $ring_layers] != 2} {
                flow::fail "APR_RING_LAYERS must contain horizontal and vertical layers"
            }
            addRing -nets [list [flow::env APR_POWER_NET] [flow::env APR_GROUND_NET]] \
                -type core_rings \
                -layer [list top [lindex $ring_layers 0] bottom [lindex $ring_layers 0] \
                    left [lindex $ring_layers 1] right [lindex $ring_layers 1]] \
                -width [flow::env APR_RING_WIDTH] \
                -spacing [flow::env APR_RING_SPACING] \
                -offset [flow::env APR_RING_OFFSET]
            addStripe -nets [list [flow::env APR_POWER_NET] [flow::env APR_GROUND_NET]] \
                -layer [flow::env APR_STRIPE_LAYER] \
                -width [flow::env APR_STRIPE_WIDTH] \
                -spacing [flow::env APR_STRIPE_SPACING] \
                -set_to_set_distance [flow::env APR_STRIPE_PITCH]
            flow::source_hook APR_POWER_HOOK
            sroute -connect {corePin blockPin padPin padRing floatingStripe}
        }
        preplace {
            setEndCapMode -reset
            setEndCapMode -boundary_tap true -rightEdge [flow::env APR_ENDCAP_CELLS] \
                -leftEdge [flow::env APR_ENDCAP_CELLS]
            addEndCap -prefix ENDCAP
            addTieHiLo -cell [list [flow::env APR_TIE_HIGH_CELL] \
                [flow::env APR_TIE_LOW_CELL]] -prefix TIE
            checkFPlan -reportUtil
        }
        place {
            setPlaceMode -place_global_max_density [flow::env CORE_UTILIZATION]
            placeDesign -concurrent_macros
            optDesign -preCTS
            flow::source_hook APR_PLACE_HOOK
        }
        cts {
            set_ccopt_property buffer_cells [flow::env APR_CTS_BUFFER_CELLS]
            set_ccopt_property inverter_cells [flow::env APR_CTS_INVERTER_CELLS]
            set_ccopt_property route_type -net_type trunk \
                -route_type_name retrosoc_clock_trunk
            create_route_type -name retrosoc_clock_trunk \
                -top_preferred_layer [lindex [flow::env APR_CLOCK_ROUTING_LAYERS] end] \
                -bottom_preferred_layer [lindex [flow::env APR_CLOCK_ROUTING_LAYERS] 0]
            create_ccopt_clock_tree_spec -file [file join $work_dir ccopt.spec]
            source [file join $work_dir ccopt.spec]
            ccopt_design
            optDesign -postCTS
            optDesign -postCTS -hold
            flow::source_hook APR_CTS_HOOK
        }
        route {
            setNanoRouteMode -routeBottomRoutingLayer [flow::env APR_SIGNAL_MIN_LAYER]
            setNanoRouteMode -routeTopRoutingLayer [flow::env APR_SIGNAL_MAX_LAYER]
            routeDesign -globalDetail
            optDesign -postRoute
            optDesign -postRoute -hold
            flow::source_hook APR_ROUTE_HOOK
            addFiller -cell [flow::env APR_CORE_FILLERS] -prefix FILL
            ecoRoute
            write_data_out $run_root $top route $output_dir $report_dir
        }
        eco {
            set eco_file [file join $run_root eco output eco.tcl]
            if {![file isfile $eco_file]} {
                flow::fail "PrimeTime ECO file is missing: $eco_file"
            }
            source $eco_file
            ecoRoute
            optDesign -postRoute
            optDesign -postRoute -hold
            write_data_out $run_root $top eco $output_dir $report_dir
        }
    }

    write_apr_reports $report_dir $stage
    saveDesign [file join $output_dir ${top}.${stage}.enc]
    flow::write_pass [file join $output_dir verdict.pass]
}

if {[catch {run_apr} message options]} {
    puts stderr $message
    if {[dict exists $options -errorinfo]} {
        puts stderr [dict get $options -errorinfo]
    }
    exit 2
}
exit
