# Copyright 2025-2026 LibreLane Contributors and retroSoC Authors
# SPDX-License-Identifier: Apache-2.0
# Adapted from the IHP SG13G2 LibreLane full-chip template.

source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
source $::env(SCRIPTS_DIR)/openroad/common/set_global_connections.tcl
set_global_connections

set secondary_supplies []
foreach vdd $::env(VDD_NETS) gnd $::env(GND_NETS) {
    if {$vdd != $::env(VDD_NET)} {
        lappend secondary_supplies $vdd
        set db_net [[ord::get_db_block] findNet $vdd]
        if {$db_net == "NULL"} {
            set net [odb::dbNet_create [ord::get_db_block] $vdd]
            $net setSpecial
            $net setSigType "POWER"
        }
    }
    if {$gnd != $::env(GND_NET)} {
        lappend secondary_supplies $gnd
        set db_net [[ord::get_db_block] findNet $gnd]
        if {$db_net == "NULL"} {
            set net [odb::dbNet_create [ord::get_db_block] $gnd]
            $net setSpecial
            $net setSigType "GROUND"
        }
    }
}

# IHP IO cells carry both core and external-IO power rails on lower-case pins.
add_global_connection -net $::env(VDD_NET) -inst_pattern .* -pin_pattern vdd -power
add_global_connection -net $::env(GND_NET) -inst_pattern .* -pin_pattern vss -ground
add_global_connection -net IOVDD -inst_pattern .* -pin_pattern iovdd -power
add_global_connection -net IOVSS -inst_pattern .* -pin_pattern iovss -ground
global_connect -verbose

set_voltage_domain -name CORE -power $::env(VDD_NET) -ground $::env(GND_NET) \
    -secondary_power $secondary_supplies

define_pdn_grid \
    -name stdcell_grid \
    -starts_with POWER \
    -voltage_domain CORE

add_pdn_stripe \
    -grid stdcell_grid \
    -layer $::env(PDN_VERTICAL_LAYER) \
    -width $::env(PDN_VWIDTH) \
    -pitch $::env(PDN_VPITCH) \
    -offset $::env(PDN_VOFFSET) \
    -spacing $::env(PDN_VSPACING) \
    -starts_with POWER

add_pdn_stripe \
    -grid stdcell_grid \
    -layer $::env(PDN_HORIZONTAL_LAYER) \
    -width $::env(PDN_HWIDTH) \
    -pitch $::env(PDN_HPITCH) \
    -offset $::env(PDN_HOFFSET) \
    -spacing $::env(PDN_HSPACING) \
    -starts_with POWER

add_pdn_connect \
    -grid stdcell_grid \
    -layers "$::env(PDN_VERTICAL_LAYER) $::env(PDN_HORIZONTAL_LAYER)"

if {$::env(PDN_ENABLE_RAILS) == 1} {
    add_pdn_stripe \
        -grid stdcell_grid \
        -layer $::env(PDN_RAIL_LAYER) \
        -width $::env(PDN_RAIL_WIDTH) \
        -followpins
    add_pdn_connect \
        -grid stdcell_grid \
        -layers "$::env(PDN_RAIL_LAYER) $::env(PDN_VERTICAL_LAYER)"
}

if {$::env(PDN_CORE_RING) == 1} {
    add_pdn_ring \
        -grid stdcell_grid \
        -layers "$::env(PDN_VERTICAL_LAYER) $::env(PDN_HORIZONTAL_LAYER)" \
        -widths "$::env(PDN_CORE_RING_VWIDTH) $::env(PDN_CORE_RING_HWIDTH)" \
        -spacings "$::env(PDN_CORE_RING_VSPACING) $::env(PDN_CORE_RING_HSPACING)" \
        -core_offset "$::env(PDN_CORE_RING_VOFFSET) $::env(PDN_CORE_RING_HOFFSET)" \
        -connect_to_pads
}

define_pdn_grid \
    -macro \
    -default \
    -name macro_default \
    -starts_with POWER \
    -halo "$::env(PDN_HORIZONTAL_HALO) $::env(PDN_VERTICAL_HALO)"

add_pdn_connect \
    -grid macro_default \
    -layers "$::env(PDN_VERTICAL_LAYER) $::env(PDN_HORIZONTAL_LAYER)"

set packet_ram_instances [list \
    u_retrosoc.u_apb4_periph.u_apb4_usb2.u_link_domain.u_packet_store.u_packet_ram.u_packet_ram.u_data_high \
    u_retrosoc.u_apb4_periph.u_apb4_usb2.u_link_domain.u_packet_store.u_packet_ram.u_packet_ram.u_data_low \
    u_retrosoc.u_apb4_periph.u_apb4_usb2.u_link_domain.u_packet_store.u_packet_ram.u_packet_ram.u_ecc]

define_pdn_grid \
    -macro \
    -instances $packet_ram_instances \
    -name packet_ram_grid \
    -starts_with POWER

add_pdn_stripe \
    -grid packet_ram_grid \
    -layer Metal5 \
    -width 2.81 \
    -pitch 11.24 \
    -offset 2.81 \
    -spacing 2.81 \
    -nets "VSS VDD" \
    -starts_with POWER

add_pdn_connect -grid packet_ram_grid -layers "Metal4 Metal5"
add_pdn_connect -grid packet_ram_grid -layers "Metal5 TopMetal1"
