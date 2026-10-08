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

proc connect_pin_map {map type} {
    foreach group $map {
        set fields [split $group :]
        if {[llength $fields] != 2} {
            flow::fail "invalid APR pin map group (expect NET:pin1,pin2): $group"
        }
        set net [string trim [lindex $fields 0]]
        set pins [string trim [lindex $fields 1]]
        if {$net eq "" || $pins eq ""} {
            flow::fail "invalid APR pin map group (expect NET:pin1,pin2): $group"
        }
        # Create the physical net when the netlist does not carry it, mirroring
        # legacy CL1/user_add_pg.tcl:4-15.
        if {[dbGet top.nets.name $net] eq "0x0"} {
            if {$type eq "power"} {
                addNet $net -physical -power
            } else {
                addNet $net -physical -ground
            }
            setNet -type special -net $net
        }
        foreach pin [split $pins ,] {
            set pin [string trim $pin]
            if {$pin eq ""} {
                continue
            }
            globalNetConnect $net -type pgpin -pin $pin -all -verbose
        }
    }
}

# Legacy CL1/user_add_pg.tcl connects every power domain to its own pin group
# (independent PLL_AVDD/PLL_AVSS pairs for the PLL macro at lines 22-23 and
# 32-33). APR_POWER_PIN_MAP / APR_GROUND_PIN_MAP express the same grouping as
# "NET:pin1,pin2 NET2:pin3"; when a map is empty every configured pin joins
# the single APR_POWER_NET / APR_GROUND_NET as before.
proc connect_power_nets {} {
    set power [flow::env APR_POWER_NET]
    set ground [flow::env APR_GROUND_NET]
    set power_map [string trim [flow::env APR_POWER_PIN_MAP ""]]
    set ground_map [string trim [flow::env APR_GROUND_PIN_MAP ""]]
    if {$power_map ne ""} {
        connect_pin_map $power_map power
    } else {
        foreach pin [flow::env APR_POWER_PINS] {
            globalNetConnect $power -type pgpin -pin $pin -all -verbose
        }
    }
    if {$ground_map ne ""} {
        connect_pin_map $ground_map ground
    } else {
        foreach pin [flow::env APR_GROUND_PINS] {
            globalNetConnect $ground -type pgpin -pin $pin -all -verbose
        }
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

# Innovus engine modes from legacy setting/common_setting.tcl (lines 17 and
# 21-22). Session modes are not preserved across restoreDesign, so every
# stage re-applies them; the APR stages run in a fresh Innovus process, so the
# legacy "-reset" prelude is not needed.
proc apply_engine_settings {} {
    setDesignMode -process [flow::env APR_DESIGN_PROCESS 55]
    setAnalysisMode -cppr both -analysisType onChipVariation
}

# Placement modes from legacy setting/place_setting.tcl (effective lines 1-11).
proc apply_place_settings {} {
    setPlaceMode -timingDriven true
    setPlaceMode -place_global_clock_gate_aware true
    setPlaceMode -place_global_place_io_pins false
    setPlaceMode -honorSoftBlockage true
    setPlaceMode -place_detail_honor_inst_pad true
    setPlaceMode -place_global_uniform_density true
    setPlaceMode -place_global_clock_power_driven true
    setPlaceMode -place_global_cong_effort auto
    setPlaceMode -place_detail_legalization_inst_gap 1
}

# Routing modes from legacy setting/route_setting.tcl (effective lines 1-16).
# Layer bounds stay name-based through APR_SIGNAL_MIN_LAYER/MAX_LAYER; the
# legacy numeric earlyGlobal window (lines 5-6) applies only when the optional
# APR_EARLY_GLOBAL_MIN_LAYER / APR_EARLY_GLOBAL_MAX_LAYER indexes are set.
proc apply_route_settings {} {
    setNanoRouteMode -routeBottomRoutingLayer [flow::env APR_SIGNAL_MIN_LAYER]
    setNanoRouteMode -routeTopRoutingLayer [flow::env APR_SIGNAL_MAX_LAYER]
    setNanoRouteMode -drouteEndIteration 20
    setNanoRouteMode -routeWithSiDriven true
    setNanoRouteMode -routeWithTimingDriven true
    setNanoRouteMode -drouteNoTaperOnoutputPin false
    setTrialRouteMode -skipTracks {}
    setTrialRouteMode -ignoreAbutted2TermNet true
    setOptMode -maxLength 500
    set early_min [string trim [flow::env APR_EARLY_GLOBAL_MIN_LAYER ""]]
    if {$early_min ne ""} {
        setRouteMode -earlyGlobalMinRouteLayer $early_min
    }
    set early_max [string trim [flow::env APR_EARLY_GLOBAL_MAX_LAYER ""]]
    if {$early_max ne ""} {
        setRouteMode -earlyGlobalMaxRouteLayer $early_max
    }
}

# Per-stage timing tightening: derate plus setup uncertainty from legacy
# CL1/set_derate_uncertainty.tcl, and the design-rule limits from legacy
# CL1/update_sdc.tcl:3-10 (max_fanout 32, max_transition 0.08 ns,
# max_capacitance 0.15 pF). MMMC constraint modes are read-only until enabled
# interactively (legacy place.tcl:19-25).
proc apply_stage_constraints {stage} {
    set_interactive_constraint_modes [all_constraint_modes]
    flow::apply_apr_derate
    flow::apply_apr_stage_uncertainty $stage
    set_max_fanout [flow::env APR_MAX_FANOUT 32] [current_design]
    set_max_transition [flow::env APR_MAX_TRANSITION_NS 0.08] [current_design]
    set_max_capacitance [flow::env APR_MAX_CAPACITANCE_PF 0.15] [current_design]
    set_interactive_constraint_mode {}
}

# 2x-width 2x-spacing clock NDR across the configured clock routing layers
# (legacy setting/cts_setting.tcl:21-23: CLKNDR on MET3:MET5 with
# width/spacing 0.2/0.2 um).
proc create_clock_ndr {} {
    set name retrosoc_clock_ndr
    if {[dbGet head.rules.name $name] eq "0x0"} {
        set layers [flow::env APR_CLOCK_ROUTING_LAYERS]
        set range "[lindex $layers 0]:[lindex $layers end]"
        add_ndr -name $name \
            -width [list $range [flow::env APR_CTS_NDR_WIDTH_UM 0.2]] \
            -spacing [list $range [flow::env APR_CTS_NDR_SPACING_UM 0.2]]
    }
    return $name
}

# Legacy generate_ccopt_spec.tcl:17-27 binds every clock route type to the
# NDR and shields the top route type with the ground net (VSS, line 22). The
# legacy trunk and top types share the same layer window, so the single
# retrosoc trunk route type carries both the NDR and the ground shield.
proc create_clock_trunk_route_type {ndr} {
    set name retrosoc_clock_trunk
    if {[dbGet head.routeTypes.name $name] eq "0x0"} {
        create_route_type -name $name \
            -top_preferred_layer [lindex [flow::env APR_CLOCK_ROUTING_LAYERS] end] \
            -bottom_preferred_layer [lindex [flow::env APR_CLOCK_ROUTING_LAYERS] 0] \
            -non_default_rule $ndr \
            -shield_net [flow::env APR_GROUND_NET]
    }
    set_ccopt_property -net_type trunk route_type $name
}

# ccopt targets from legacy setting/cts_setting.tcl:1-12 and
# generate_ccopt_spec.tcl:29-36: skew 0.08 ns, leaf/trunk transition 0.78 ns
# (max_sink_tran/max_buf_tran), insertion delay 0.05 ns (cts_max_delay),
# fanout 4.
proc configure_ccopt_targets {} {
    set_ccopt_property target_skew [flow::env APR_CTS_TARGET_SKEW_NS 0.08]
    set_ccopt_property target_max_trans -net_type leaf \
        [flow::env APR_CTS_TARGET_MAX_TRANS_LEAF_NS 0.78]
    set_ccopt_property target_max_trans -net_type trunk \
        [flow::env APR_CTS_TARGET_MAX_TRANS_TRUNK_NS 0.78]
    set_ccopt_property target_insertion_delay \
        [flow::env APR_CTS_TARGET_INSERTION_DELAY_NS 0.05]
    set_ccopt_property max_fanout [flow::env APR_CTS_MAX_FANOUT 4]
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
    # Legacy dataOut.tcl:15,19 drop pad and seal-ring instances from the
    # netlists; APR_NETLIST_EXCLUDE_CELLS carries the same exclusion list.
    set exclude [string trim [flow::env APR_NETLIST_EXCLUDE_CELLS ""]]
    if {$exclude eq ""} {
        saveNetlist ${prefix}.v
        saveNetlist -includePowerGround ${prefix}.pg.v
    } else {
        saveNetlist ${prefix}.v -excludeCellInst $exclude
        saveNetlist -includePowerGround ${prefix}.pg.v -excludeCellInst $exclude
    }
    write_sdc ${prefix}.sdc
    write_sdf -version 3.0 ${prefix}.sdf
    # Legacy dataOut.tcl:26-35 stream-out contract.
    setStreamOutMode -virtualConnection false
    streamOut ${prefix}.gds -mapFile [flow::env STREAM_MAP] \
        -structureName $top -mode ALL \
        -stripes 1 -units 1000 \
        -attachInstanceName 2 -attachNetName 2 \
        -dieAreaAsBoundary
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
            # MMMC is ready once init_design completes; apply the engine modes
            # (legacy setting/common_setting.tcl) and derate every delay
            # corner (legacy CL1/set_derate_uncertainty.tcl:1-3).
            apply_engine_settings
            flow::apply_apr_derate
            checkDesign -all
        }
        floorplan {
            floorPlan -site [flow::env APR_SITE] -d \
                [flow::env DIE_WIDTH] [flow::env DIE_HEIGHT] \
                [flow::env CORE_MARGIN_LEFT] [flow::env CORE_MARGIN_BOTTOM] \
                [flow::env CORE_MARGIN_RIGHT] [flow::env CORE_MARGIN_TOP]
            # Legacy floorplan.tcl:6 loads a reviewed IO order file; the
            # generated round-robin ring stays the default fallback.
            set io_order_file [string trim [flow::env APR_IO_ORDER_FILE ""]]
            if {$io_order_file ne ""} {
                if {![file isfile $io_order_file] || \
                        ![file readable $io_order_file]} {
                    flow::fail "APR_IO_ORDER_FILE is not readable: $io_order_file"
                }
                set io_file [file normalize $io_order_file]
                set io_order file
            } else {
                set io_file [file join $work_dir ${top}.io]
                write_io_ring $io_file
                set io_order round_robin
            }
            loadIoFile $io_file
            fixAllIos
            puts "APR floorplan io_order=$io_order io_file=$io_file"
            flow::write_text [file join $output_dir floorplan.io.json] \
                "{\n    \"stage\": \"floorplan\",\n    \"io_order\": \"$io_order\",\n    \"io_file\": \"$io_file\"\n}\n"
            addIoFiller -cell [flow::env APR_IO_FILLERS] -prefix IOFILL
            # Optional macro pre-placement (legacy floorplan.tcl:11 sources
            # CL1/<design>_macro_loc.tcl; the file carries
            # placeInstance/place_macro/createPlaceBlockage commands) plus a
            # uniform macro placement halo (legacy prePlace.tcl:9 uses
            # "addHaloToBlock -allMacro 2 2 2 2"; CL1/add_mem_blk.tcl instead
            # extends every SRAM by 1.5 um as a pgnet route blockage).
            set macro_loc [string trim [flow::env APR_MACRO_LOC_FILE ""]]
            if {$macro_loc ne ""} {
                flow::source_hook APR_MACRO_LOC_FILE
                set halo [flow::env APR_MACRO_HALO_UM 5]
                addHaloToBlock -allMacro $halo $halo $halo $halo
            }
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
            # Legacy place.tcl:7-23 re-sources every setting file plus the
            # per-stage constraint updates after restoreDesign.
            apply_engine_settings
            apply_place_settings
            apply_route_settings
            apply_stage_constraints place
            # Legacy place_setting.tcl:1 fixes density at 0.7; the retroSoC
            # product policy keeps it driven by CORE_UTILIZATION.
            setPlaceMode -place_global_max_density [flow::env CORE_UTILIZATION]
            placeDesign -concurrent_macros
            optDesign -preCTS
            flow::source_hook APR_PLACE_HOOK
        }
        cts {
            # Legacy CTS.tcl:7-25 applies the same settings and constraints.
            apply_engine_settings
            apply_place_settings
            apply_route_settings
            apply_stage_constraints cts
            set_ccopt_property buffer_cells [flow::env APR_CTS_BUFFER_CELLS]
            set_ccopt_property inverter_cells [flow::env APR_CTS_INVERTER_CELLS]
            # Legacy generate_ccopt_spec.tcl: snapshot the tree spec, then
            # bind the NDR route type and targets before ccopt_design.
            create_ccopt_clock_tree_spec -file [file join $work_dir ccopt.spec]
            set clock_ndr [create_clock_ndr]
            create_clock_trunk_route_type $clock_ndr
            configure_ccopt_targets
            source [file join $work_dir ccopt.spec]
            ccopt_design
            optDesign -postCTS
            optDesign -postCTS -hold
            flow::source_hook APR_CTS_HOOK
        }
        route {
            # Legacy route.tcl:6-25 applies the same settings and constraints.
            apply_engine_settings
            apply_place_settings
            apply_route_settings
            apply_stage_constraints route
            # Legacy setting/common_setting.tcl:29-33 enables coupled
            # postRoute extraction once the route step starts.
            setExtractRCMode -engine postRoute -effortLevel medium -couples true
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
