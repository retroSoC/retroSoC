# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of MulanPSL2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

namespace eval flow {
    variable canonical_clock_domains {}
    variable canonical_reset_ports {}
    variable commercial_clock_names {}
}

proc flow::required_ports {label names} {
    set objects [get_ports -quiet $names]
    if {[sizeof_collection $objects] != [llength $names]} {
        flow::fail "required $label ports are missing: $names"
    }
    return $objects
}

proc flow::required_pins {label name} {
    set objects [get_pins -quiet $name]
    if {[sizeof_collection $objects] == 0} {
        flow::fail "required $label pin is missing: $name"
    }
    return $objects
}

proc flow::required_net_driver_pin {label name} {
    set nets [get_nets -quiet $name]
    if {[sizeof_collection $nets] != 1} {
        flow::fail "required $label net is missing or ambiguous: $name"
    }
    set drivers [filter_collection [get_pins -quiet -of_objects $nets] \
        "direction == out"]
    if {[sizeof_collection $drivers] != 1} {
        flow::fail "required $label net must have one output driver: $name"
    }
    return $drivers
}

proc flow::domain_object {domain} {
    variable canonical_clock_domains
    set values [dict get $canonical_clock_domains $domain]
    set observation [dict get $values observation]
    if {[dict get $values object_type] eq "port"} {
        return [flow::required_ports "clock $domain" [list $observation]]
    }
    if {[dict get $values object_type] eq "net_driver"} {
        return [flow::required_net_driver_pin "clock $domain" $observation]
    }
    return [flow::required_pins "clock $domain" $observation]
}

proc flow::load_canonical_timing_contract {} {
    variable canonical_clock_domains
    variable canonical_reset_ports
    variable run_root
    set contract [file join $run_root input rtl contracts commercial_timing_contract.tcl]
    if {![file isfile $contract] || ![file readable $contract]} {
        flow::fail "canonical commercial timing contract is missing: $contract"
    }
    source $contract
    set expected {external system audio jtag dvp usb2_ulpi}
    if {[lsort [dict keys $canonical_clock_domains]] ne [lsort $expected]} {
        flow::fail "canonical commercial clock-domain set is invalid"
    }
    if {[llength $canonical_reset_ports] == 0} {
        flow::fail "canonical reset-port list is empty"
    }
}

proc flow::create_canonical_master_clock {domain} {
    variable canonical_clock_domains
    set values [dict get $canonical_clock_domains $domain]
    set name clk_$domain
    create_clock -name $name -period [dict get $values period_ns] \
        [flow::domain_object $domain]
    return $name
}

proc flow::apply_clock_constraints {} {
    variable canonical_clock_domains
    variable canonical_reset_ports
    variable commercial_clock_names

    set commercial_clock_names {}
    foreach domain {external audio jtag dvp usb2_ulpi} {
        lappend commercial_clock_names [flow::create_canonical_master_clock $domain]
    }

    set xtal_pin [flow::required_pins crystal_clock u_rcu/u_xtal_buf/clk_o]
    create_clock -name clk_xtal -period [flow::env XTAL_CLK_PERIOD_NS] $xtal_pin
    lappend commercial_clock_names clk_xtal

    set pll_pin [flow::required_pins pll_clock u_rcu/u_tc_pll/u_PLL_TOP/CKOUT1]
    create_clock -name clk_pll -period [flow::env PLL_OUTPUT_PERIOD_NS] $pll_pin
    lappend commercial_clock_names clk_pll

    set ext_pin [flow::domain_object external]
    set sys_pin [flow::domain_object system]
    create_generated_clock -name clk_system_ext -master_clock clk_external \
        -source $ext_pin -divide_by 1 $sys_pin
    create_generated_clock -name clk_system_pll -master_clock clk_pll \
        -source $pll_pin -divide_by 1 -add $sys_pin
    lappend commercial_clock_names clk_system_ext clk_system_pll

    set ext_group [get_clocks {clk_external clk_system_ext}]
    set pll_group [get_clocks {clk_pll clk_system_pll}]
    set_clock_groups -name retrosoc_system_sources -physically_exclusive \
        -group $ext_group -group $pll_group

    set system_group [get_clocks \
        {clk_external clk_system_ext clk_pll clk_system_pll}]
    set async_groups [list \
        $system_group \
        [get_clocks clk_audio] \
        [get_clocks clk_xtal] \
        [get_clocks clk_jtag] \
        [get_clocks clk_dvp] \
        [get_clocks clk_usb2_ulpi]]
    set command [list set_clock_groups -name retrosoc_async -asynchronous]
    foreach group $async_groups {
        lappend command -group $group
    }
    eval $command

    set clocks [get_clocks $commercial_clock_names]
    if {[sizeof_collection $clocks] != [llength $commercial_clock_names]} {
        flow::fail "not all commercial clocks were created"
    }
    set_clock_uncertainty -setup [flow::env CLOCK_SETUP_UNCERTAINTY_NS] $clocks
    set_clock_uncertainty -hold [flow::env CLOCK_HOLD_UNCERTAINTY_NS] $clocks
    set_clock_transition [flow::env CLOCK_TRANSITION_NS] $clocks

    set resets [flow::required_ports reset $canonical_reset_ports]
    set_false_path -from $resets
}
