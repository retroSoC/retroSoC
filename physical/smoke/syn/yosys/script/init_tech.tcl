# Copyright (c) 2022 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>
#
# -- Adaptable modifications are redistributed under compatible License --
#
# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

# get environment variables
set root_dir [file normalize [file join [file dirname [info script]] ../../../../..]]

puts "0. Executing init_tech: load technology from Github PDK"

set have_sram_macro [expr {
    [info exists ::env(HAVE_SRAM_MACRO)] && $::env(HAVE_SRAM_MACRO) eq "YES"
}]

if {$pdk == "IHP130"} {
    set pdk_dir "$root_dir/physical/pdk/IHP-Open-PDK"
    set pdk_cells_lib ${pdk_dir}/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib
    set pdk_sram_lib  ${pdk_dir}/ihp-sg13g2/libs.ref/sg13g2_sram/lib
    set pdk_io_lib    ${pdk_dir}/ihp-sg13g2/libs.ref/sg13g2_io/lib
    set tech_cells    [list "$pdk_cells_lib/sg13g2_stdcell_typ_1p20V_25C.lib"]
    set tech_macros   [list]
    if {$have_sram_macro} {
        set tech_macros [glob -nocomplain -directory $pdk_sram_lib *_typ_1p20V_25C.lib]
    }
    lappend tech_macros "$pdk_io_lib/sg13g2_io_typ_1p2V_3p3V_25C.lib"
    # for hilomap
    set tech_cell_tiehi {sg13g2_tiehi L_HI}
    set tech_cell_tielo {sg13g2_tielo L_LO}
    set abc_driver        sg13g2_buf_4
    set abc_load          6.0
} elseif {$pdk == "ICS55"} {
    set pdk_dir "$root_dir/physical/pdk/icsprout55-pdk"
    set pdk_cells_lib "$root_dir/.cache/retrosoc/pdk/ics55"
    set pdk_io_lib "${pdk_dir}/IP/IO/ICsprout_55LLULP1233_IO_251013/liberty"
    set tech_cells [list "$pdk_cells_lib/ics55_h7cr_tt.lib"]
    set tech_macros [list "$pdk_io_lib/ICSIOA_N55_3P3_tt_1p2_3p3_25c.lib"]
    # for hilomap
    set tech_cell_tiehi {TIEHIH7R Z}
    set tech_cell_tielo {TIELOH7R Z}
    set abc_driver        BUFX4H7R
    set abc_load          6.0
} elseif {$pdk == "GF180"} {
    set pdk_sram_lib "$root_dir/physical/pdk/gf180mcu-pdk/macros/gf180mcu_fd_ip_sram/latest/cells/gf180mcu_fd_ip_sram__sram512x8m8wm1"
    set pdk_cells_lib "$root_dir/.cache/retrosoc/pdk/gf180"
    set tech_cells [list "$pdk_cells_lib/gf180mcu_fd_sc_mcu7t5v0__tt_025C_5v00.lib"]
    set tech_macros [list]
    if {$have_sram_macro} {
        lappend tech_macros "$pdk_sram_lib/gf180mcu_fd_ip_sram__sram512x8m8wm1__tt_025C_5v00.lib"
    }
    # The aggregate GF180 Liberty does not characterize the available tie cells.
    # Keep constants as logic instead of mapping them to an uncharacterized cell.
    set tech_cell_tiehi {}
    set tech_cell_tielo {}
    set abc_driver        gf180mcu_fd_sc_mcu7t5v0__buf_4
    set abc_load          13.43
} elseif {$pdk == "SKY130"} {
    set pdk_cells_lib "$root_dir/.cache/retrosoc/pdk/sky130"
    set pdk_sram_lib "$pdk_cells_lib/openram"
    set tech_cells [list "$pdk_cells_lib/sky130_fd_sc_hd__tt_025C_1v80.lib"]
    set tech_macros [list]
    if {$have_sram_macro} {
        lappend tech_macros "$pdk_sram_lib/sky130_sram_4kbyte_1rw_32x1024_8_TT_1p8V_25C.lib"
    }
    set tech_cell_tiehi {sky130_fd_sc_hd__conb_1 HI}
    set tech_cell_tielo {sky130_fd_sc_hd__conb_1 LO}
    set abc_driver        sky130_fd_sc_hd__buf_1
    set abc_load          5
} else {
    error "unsupported PDK for Yosys: $pdk"
}

# pre-formated for easier use in yosys commands
# all liberty files
set lib_list          [concat [split $tech_cells] [split $tech_macros] ]
set liberty_args_list [lmap lib $lib_list {concat "-liberty" $lib}]
set liberty_args      [concat {*}$liberty_args_list]
# only the standard cells
set tech_cells_args_list [lmap lib $tech_cells {concat "-liberty" $lib}]
set tech_cells_args      [concat {*}$tech_cells_args_list]

# read library files
foreach file $lib_list {
    yosys read_liberty -lib "$file"
}
