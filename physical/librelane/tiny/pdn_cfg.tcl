# Copyright 2025-2026 LibreLane Contributors and retroSoC Authors
# SPDX-License-Identifier: Apache-2.0
# Tiny IHP130 chip PDN: LibreLane default sg13g2 topology (M1 rails connect to
# the TopMetal1 stripe network directly) plus a macro grid that ties the SRAM
# banks' Metal4 power columns into the stripe network with Metal5 cross straps.

source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
source $::env(SCRIPTS_DIR)/openroad/common/set_global_connections.tcl
set_global_connections

# Use the PDK-native alternating routing directions (H/V/H/V/H).
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

# I/O rails are pad-ring internal and are absent from the synthesized top-level.
foreach {net signal_type} {IOVDD POWER IOVSS GROUND} {
    set db_net [[ord::get_db_block] findNet $net]
    if {$db_net == "NULL"} {
        set db_net [odb::dbNet_create [ord::get_db_block] $net]
        $db_net setSpecial
        $db_net setSigType $signal_type
    }
}

# IHP IO cells carry both core and external-IO power rails on lower-case pins.
add_global_connection -net $::env(VDD_NET) -inst_pattern .* -pin_pattern vdd -power
add_global_connection -net $::env(GND_NET) -inst_pattern .* -pin_pattern vss -ground
add_global_connection -net IOVDD -inst_pattern .* -pin_pattern iovdd -power
add_global_connection -net IOVSS -inst_pattern .* -pin_pattern iovss -ground
global_connect -verbose

# connect_by_abutment assigns IHP pad rails to corner-local *_RING nets. Rebind
# those physical pad and filler pins so the PDN knows they are VDD/VSS terminals.
proc reconnect_ihp_padring_rails {block} {
    foreach {net_name pin_name} {
        VDD vdd
        VSS vss
        IOVDD iovdd
        IOVSS iovss
    } {
        set net [$block findNet $net_name]
        foreach inst [$block getInsts] {
            set master_name [[$inst getMaster] getName]
            if {![string match "sg13g2_IOPad*" $master_name] &&
                ![string match "sg13g2_Filler*" $master_name] &&
                ![string match "sg13g2_Corner*" $master_name]} {
                continue
            }
            foreach iterm [$inst getITerms] {
                if {[[$iterm getMTerm] getName] != $pin_name} {
                    continue
                }
                odb::dbITerm_disconnect $iterm
                odb::dbITerm_connect $iterm $net
            }
        }
    }
}
reconnect_ihp_padring_rails [ord::get_db_block]

set_voltage_domain -name CORE -power $::env(VDD_NET) -ground $::env(GND_NET) \
    -secondary_power $secondary_supplies

set stdcell_grid_args [list]
if {$::env(PDN_ENABLE_PINS) == 1} {
    lappend stdcell_grid_args -pins "$::env(PDN_VERTICAL_LAYER) $::env(PDN_HORIZONTAL_LAYER)"
}
define_pdn_grid \
    -name stdcell_grid \
    -starts_with POWER \
    -voltage_domain CORE \
    {*}$stdcell_grid_args

add_pdn_stripe \
    -grid stdcell_grid \
    -layer $::env(PDN_VERTICAL_LAYER) \
    -width $::env(PDN_VWIDTH) \
    -pitch $::env(PDN_VPITCH) \
    -offset $::env(PDN_VOFFSET) \
    -spacing $::env(PDN_VSPACING) \
    -starts_with POWER \
    -extend_to_core_ring

add_pdn_stripe \
    -grid stdcell_grid \
    -layer $::env(PDN_HORIZONTAL_LAYER) \
    -width $::env(PDN_HWIDTH) \
    -pitch $::env(PDN_HPITCH) \
    -offset $::env(PDN_HOFFSET) \
    -spacing $::env(PDN_HSPACING) \
    -starts_with POWER \
    -extend_to_core_ring

# A low-metal ring just inside the core edge collects the Metal1 rails; the
# top-metal stripe mesh bridges to it where the stripes cross the ring legs.
add_pdn_ring \
    -grid stdcell_grid \
    -layers "Metal2 Metal3" \
    -widths "0.52 0.52" \
    -spacings "0.8 0.8" \
    -core_offsets "1.6 1.6" \
    -starts_with POWER \
    -add_connect

if {$::env(PDN_ENABLE_RAILS) == 1} {
    add_pdn_stripe \
        -grid stdcell_grid \
        -layer $::env(PDN_RAIL_LAYER) \
        -width $::env(PDN_RAIL_WIDTH) \
        -followpins \
        -extend_to_core_ring
    add_pdn_connect -grid stdcell_grid -layers "Metal1 Metal2"
    add_pdn_connect -grid stdcell_grid -layers "Metal1 Metal3"
    # The rail network meets the top-metal mesh at the low ring legs and at
    # every Metal1 rail / TopMetal1 stripe crossing (covers the standard-cell
    # channels between SRAM banks as well).
    add_pdn_connect -grid stdcell_grid -layers "Metal3 TopMetal1"
    add_pdn_connect -grid stdcell_grid -layers "Metal1 TopMetal1"
    add_pdn_connect -grid stdcell_grid -layers "Metal2 TopMetal2"
}

if {$::env(PDN_CORE_RING) == 1} {
    add_pdn_ring \
        -grid stdcell_grid \
        -layers "$::env(PDN_VERTICAL_LAYER) $::env(PDN_HORIZONTAL_LAYER)" \
        -widths "$::env(PDN_CORE_RING_VWIDTH) $::env(PDN_CORE_RING_HWIDTH)" \
        -spacings "$::env(PDN_CORE_RING_VSPACING) $::env(PDN_CORE_RING_HSPACING)" \
        -core_offsets "$::env(PDN_CORE_RING_VOFFSET) $::env(PDN_CORE_RING_HOFFSET)" \
        -connect_to_pads \
        -connect_to_pad_layers TopMetal2 \
        -add_connect
}

# Tiny hardens a single SRAM master: the 128 KiB on-chip RAM banks. Their power
# pins are vertical Metal4 columns spanning the bank height; horizontal Metal5
# straps cross every column and hand off to the stdcell TopMetal1 stripes
# outside the bank boundary.
set sram_cells [list \
    RM_IHPSG13_1P_1024x32_c2_bm_bist]

define_pdn_grid \
    -macro \
    -cells $sram_cells \
    -name sram_bank_grid \
    -grid_over_boundary \
    -voltage_domains CORE \
    -starts_with POWER

add_pdn_ring \
    -grid sram_bank_grid \
    -layers "Metal2 Metal3" \
    -widths "0.52 0.52" \
    -spacings "0.8 0.8" \
    -core_offsets "1.6 1.6" \
    -starts_with POWER \
    -add_connect

add_pdn_stripe \
    -grid sram_bank_grid \
    -layer Metal5 \
    -width 2.5 \
    -pitch 67.24 \
    -offset 10.0 \
    -spacing 2.5 \
    -starts_with POWER

add_pdn_connect -grid sram_bank_grid -layers "Metal4 Metal5"
add_pdn_connect -grid sram_bank_grid -layers "Metal5 TopMetal1"
add_pdn_connect -grid sram_bank_grid -layers "Metal2 TopMetal1"
add_pdn_connect -grid sram_bank_grid -layers "Metal3 TopMetal1"
add_pdn_connect -grid sram_bank_grid -layers "TopMetal1 TopMetal2"
# Rails trapped in the channels between banks tie into the bank rings.
add_pdn_connect -grid sram_bank_grid -layers "Metal1 Metal2"
add_pdn_connect -grid sram_bank_grid -layers "Metal1 Metal3"
