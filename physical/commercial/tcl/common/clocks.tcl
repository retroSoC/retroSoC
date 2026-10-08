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
    variable commercial_clock_groups
    array set commercial_clock_groups {}
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

proc flow::register_clock {name async_group} {
    variable commercial_clock_names
    variable commercial_clock_groups
    lappend commercial_clock_names $name
    lappend commercial_clock_groups($async_group) $name
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
    set expected [product::expected_clock_domains]
    if {[lsort [dict keys $canonical_clock_domains]] ne [lsort $expected]} {
        flow::fail "canonical commercial clock-domain set is invalid for $flow::soc"
    }
    if {[llength $canonical_reset_ports] == 0} {
        flow::fail "canonical reset-port list is empty"
    }
}

proc flow::apply_clock_constraints {} {
    variable canonical_clock_domains
    variable canonical_reset_ports
    variable commercial_clock_names
    variable commercial_clock_groups

    set commercial_clock_names {}
    array set commercial_clock_groups {}
    set custom [product::custom_clock_domains]

    array set objects {}
    foreach domain [dict keys $canonical_clock_domains] {
        set objects($domain) [flow::domain_object $domain]
    }
    foreach domain [dict keys $canonical_clock_domains] {
        if {$domain in $custom} {
            continue
        }
        set values [dict get $canonical_clock_domains $domain]
        set name clk_$domain
        set source_domain [dict get $values source_domain]
        if {$source_domain eq ""} {
            create_clock -name $name -period [dict get $values period_ns] \
                $objects($domain)
        } else {
            if {$source_domain in $custom} {
                flow::fail "domain $domain derives from the product-managed \
                    domain $source_domain"
            }
            create_generated_clock -name $name -source $objects($source_domain) \
                -divide_by 1 $objects($domain)
        }
        flow::register_clock $name [dict get $values async_group]
    }
    product::apply_clock_overlays

    if {[array size commercial_clock_groups] > 1} {
        set command [list set_clock_groups -name retrosoc_async -asynchronous]
        foreach group [array names commercial_clock_groups] {
            lappend command -group [get_clocks $commercial_clock_groups($group)]
        }
        eval $command
    }

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
