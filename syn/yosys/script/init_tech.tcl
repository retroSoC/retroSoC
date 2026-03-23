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
set root_dir [file dirname [file dirname [file dirname [file dirname [info script]]]]]

puts "0. Executing init_tech: load technology from Github PDK"

if {$pdk == "IHP130"} {
    set pdk_dir "$root_dir/pdk/IHP-Open-PDK"
    set pdk_cells_lib ${pdk_dir}/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib
    set pdk_sram_lib  ${pdk_dir}/ihp-sg13g2/libs.ref/sg13g2_sram/lib
    set pdk_io_lib    ${pdk_dir}/ihp-sg13g2/libs.ref/sg13g2_io/lib
    set tech_cells    [list "$pdk_cells_lib/sg13g2_stdcell_typ_1p20V_25C.lib"]
    set tech_macros   [glob -nocomplain -directory $pdk_sram_lib *_typ_1p20V_25C.lib]
    lappend tech_macros "$pdk_io_lib/sg13g2_io_typ_1p2V_3p3V_25C.lib"
    # for hilomap
    set tech_cell_tiehi {sg13g2_tiehi L_HI}
    set tech_cell_tielo {sg13g2_tielo L_LO}
} elseif {$pdk == "ICS55"} {
    set pdk_dir "/nfs/share/home/zhuangchunan/proj/Flow_CX55/lib_data"
    set pdk_cells_lib /nfs/share/home/qiming/yosys-flow
    set pdk_sram_lib  ${pdk_dir}/mem
    set pdk_io_lib    ${pdk_dir}/ccslib
    set tech_cells    [list "$pdk_cells_lib/ETSCA_N55_H7BL_DSS_PRCMAX_V1P0_T125.lib"]
    set tech_macros   [list "$pdk_sram_lib/S55NLLG1PH_X256Y4D32_BW_ss_1.08_125.lib"]
    lappend tech_macros "$pdk_io_lib/ETIOA_N55_3P3_ss1p08v2p97v125c.lib"
    # for hilomap
    set tech_cell_tiehi {TIEHIH7H Y}
    set tech_cell_tielo {TIELOH7H Y}
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