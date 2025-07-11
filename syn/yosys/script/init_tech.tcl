# Copyright (c) 2022 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>
#
# -- Adaptable modifications are redistributed under compatible License --
#
# Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
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

if {$pdk == "S110"} {
    set pdk_dir "$root_dir/pdk/s110"
    set pdk_cells_lib ${pdk_dir}
    set pdk_sram_lib  ${pdk_dir}
    set pdk_io_lib    ${pdk_dir}
    set pdk_pll_lib   ${pdk_dir}
    set tech_cells    [list "$pdk_cells_lib/scc011ums_hd_lvt_tt_v1p2_25c_basic.lib"]
    set tech_macros   [glob -nocomplain -directory $pdk_sram_lib *_TT_1.2_25.lib]
    lappend tech_macros "$pdk_io_lib/SP013D3WP_V1p7_typ.lib"
    lappend tech_macros "$pdk_pll_lib/S013PLLFN_v1.5.1_typ.lib"
    # for hilomap
    set tech_cell_tiehi {LVT_PULLHD1 Z}
    set tech_cell_tielo {LVT_PULLHD0 Z}
    set dff_dont_use_cells  [list "LVT_CLKLAHAQHDV1" "LVT_CLKLAHAQHDV2" "LVT_CLKLAHAQHDV4" "LVT_CLKLAHAQHDV8" "LVT_CLKLAHQHDV1" "LVT_CLKLAHQHDV2" "LVT_CLKLAHQHDV4" "LVT_CLKLAHQHDV8" "LVT_DGRSNHDV1" "LVT_DGRSNHDV2" "LVT_DGRSNHDV4" "LVT_DRSNHDV1" "LVT_DRSNHDV2" "LVT_DRSNHDV4" "LVT_DXHDV1" "LVT_DXHDV2" "LVT_DXHDV4" "LVT_EDGRNHDV1" "LVT_EDGRNHDV2" "LVT_EDGRNHDV4" "LVT_EDGRNQHDV1" "LVT_EDGRNQHDV2" "LVT_EDGRNQHDV4" "LVT_EDHDV1" "LVT_EDHDV2" "LVT_EDHDV4" "LVT_EDQHDV1" "LVT_EDQHDV2" "LVT_EDQHDV4" "LVT_EDRNHDV1" "LVT_EDRNHDV2" "LVT_EDRNHDV4" "LVT_EDRNQHDV1" "LVT_EDRNQHDV2" "LVT_EDRNQHDV4" "LVT_LAHHDV1" "LVT_LAHHDV2" "LVT_LAHHDV4" "LVT_LAHRNHDV1" "LVT_LAHRNHDV2" "LVT_LAHRNHDV4" "LVT_LAHRSNHDV1" "LVT_LAHRSNHDV1" "LVT_LAHRSNHDV2" "LVT_LAHRSNHDV2" "LVT_LAHRSNHDV4" "LVT_LAHRSNHDV4" "LVT_LAHSNHDV1" "LVT_LAHSNHDV2" "LVT_LAHSNHDV4" "LVT_LALHDV1" "LVT_LALHDV2" "LVT_LALHDV4" "LVT_LALRNHDV1" "LVT_LALRNHDV2" "LVT_LALRNHDV4" "LVT_LALRSNHDV1" "LVT_LALRSNHDV1" "LVT_LALRSNHDV2" "LVT_LALRSNHDV2" "LVT_LALRSNHDV4" "LVT_LALRSNHDV4" "LVT_LALSNHDV1" "LVT_LALSNHDV2" "LVT_LALSNHDV4" "LVT_NDRSNHDV1" "LVT_NDRSNHDV1" "LVT_NDRSNHDV2" "LVT_NDRSNHDV2" "LVT_NDRSNHDV4" "LVT_NDRSNHDV4" "LVT_SDGRNHDV1" "LVT_SDGRNHDV2" "LVT_SDGRNHDV4" "LVT_SDGRNQHDV1" "LVT_SDGRNQHDV2" "LVT_SDGRNQHDV4" "LVT_SDGRSNHDV1" "LVT_SDGRSNHDV1" "LVT_SDGRSNHDV2" "LVT_SDGRSNHDV2" "LVT_SDGRSNHDV4" "LVT_SDGRSNHDV4" "LVT_SDGSNHDV1" "LVT_SDGSNHDV2" "LVT_SDGSNHDV4" "LVT_SDHDV1" "LVT_SDHDV2" "LVT_SDHDV4" "LVT_SDQHDV1" "LVT_SDQHDV2" "LVT_SDQHDV4" "LVT_SDRNHDV1" "LVT_SDRNHDV2" "LVT_SDRNHDV4" "LVT_SDRNQHDV1" "LVT_SDRNQHDV2" "LVT_SDRNQHDV4" "LVT_SDRSNHDV1" "LVT_SDRSNHDV1" "LVT_SDRSNHDV2" "LVT_SDRSNHDV2" "LVT_SDRSNHDV4" "LVT_SDRSNHDV4" "LVT_SDSNHDV1" "LVT_SDSNHDV2" "LVT_SDSNHDV4" "LVT_SDXHDV1" "LVT_SDXHDV1" "LVT_SDXHDV2" "LVT_SDXHDV2" "LVT_SDXHDV4" "LVT_SDXHDV4" "LVT_SEDGRNHDV1" "LVT_SEDGRNHDV2" "LVT_SEDGRNHDV4" "LVT_SEDGRNQHDV1" "LVT_SEDGRNQHDV2" "LVT_SEDGRNQHDV4" "LVT_SEDHDV1" "LVT_SEDHDV2" "LVT_SEDHDV4" "LVT_SEDQHDV1" "LVT_SEDQHDV2" "LVT_SEDQHDV4" "LVT_SEDRNHDV1" "LVT_SEDRNHDV2" "LVT_SEDRNHDV4" "LVT_SEDRNQHDV1" "LVT_SEDRNQHDV2" "LVT_SEDRNQHDV4" "LVT_SNDHDV1" "LVT_SNDHDV2" "LVT_SNDHDV4" "LVT_SNDRNHDV1" "LVT_SNDRNHDV2" "LVT_SNDRNHDV4" "LVT_SNDRSNHDV1" "LVT_SNDRSNHDV1" "LVT_SNDRSNHDV1" "LVT_SNDRSNHDV2" "LVT_SNDRSNHDV2" "LVT_SNDRSNHDV2" "LVT_SNDRSNHDV4" "LVT_SNDRSNHDV4" "LVT_SNDRSNHDV4" "LVT_SNDSNHDV1" "LVT_SNDSNHDV2" "LVT_SNDSNHDV4"]
    set comb_dont_use_cells [list "LVT_AO222HDV0" "LVT_AO222HDV1" "LVT_AO222HDV2" "LVT_AO222HDV4" "LVT_AO33HDV0" "LVT_AO33HDV1" "LVT_AO33HDV2" "LVT_AO33HDV4" "LVT_AOI222HDV0" "LVT_AOI222HDV1" "LVT_AOI222HDV2" "LVT_AOI222HDV4" "LVT_AOI33HDV0" "LVT_AOI33HDV1" "LVT_AOI33HDV2" "LVT_AOI33HDV4" "LVT_CKMUX2HDV0" "LVT_CKMUX2HDV1" "LVT_CKMUX2HDV2" "LVT_CKMUX2HDV4" "LVT_CLKAND2HDV0" "LVT_CLKAND2HDV1" "LVT_CLKAND2HDV2" "LVT_CLKAND2HDV4" "LVT_CLKAND2HDV8" "LVT_CLKBUFHDV0" "LVT_CLKBUFHDV1" "LVT_CLKBUFHDV12" "LVT_CLKBUFHDV16" "LVT_CLKBUFHDV2" "LVT_CLKBUFHDV20" "LVT_CLKBUFHDV24" "LVT_CLKBUFHDV3" "LVT_CLKBUFHDV4" "LVT_CLKBUFHDV6" "LVT_CLKBUFHDV8" "LVT_CLKLAHAQHDV1" "LVT_CLKLAHAQHDV2" "LVT_CLKLAHAQHDV4" "LVT_CLKLAHAQHDV8" "LVT_CLKLAHQHDV1" "LVT_CLKLAHQHDV2" "LVT_CLKLAHQHDV4" "LVT_CLKLAHQHDV8" "LVT_CLKLANAQHDV1" "LVT_CLKLANAQHDV2" "LVT_CLKLANAQHDV4" "LVT_CLKLANAQHDV8" "LVT_CLKLANQHDV1" "LVT_CLKLANQHDV12" "LVT_CLKLANQHDV16" "LVT_CLKLANQHDV2" "LVT_CLKLANQHDV20" "LVT_CLKLANQHDV24" "LVT_CLKLANQHDV3" "LVT_CLKLANQHDV4" "LVT_CLKLANQHDV6" "LVT_CLKLANQHDV8" "LVT_CLKNAND2HDV0" "LVT_CLKNAND2HDV1" "LVT_CLKNAND2HDV2" "LVT_CLKNAND2HDV3" "LVT_CLKNAND2HDV4" "LVT_CLKNAND2HDV8" "LVT_CLKNHDV0" "LVT_CLKNHDV1" "LVT_CLKNHDV12" "LVT_CLKNHDV16" "LVT_CLKNHDV2" "LVT_CLKNHDV20" "LVT_CLKNHDV24" "LVT_CLKNHDV3" "LVT_CLKNHDV4" "LVT_CLKNHDV6" "LVT_CLKNHDV8" "LVT_CLKXOR2HDV0" "LVT_CLKXOR2HDV1" "LVT_CLKXOR2HDV2" "LVT_CLKXOR2HDV4" "LVT_DEL1HDV1" "LVT_DEL1HDV4" "LVT_DEL2HDV1" "LVT_DEL2HDV4" "LVT_DEL3HDV1" "LVT_DEL3HDV4" "LVT_DEL4HDV1" "LVT_DEL4HDV4" "LVT_FDCAPHD16" "LVT_FDCAPHD32" "LVT_FDCAPHD4" "LVT_FDCAPHD64" "LVT_FDCAPHD8" "LVT_F_DIODEHD2" "LVT_F_DIODEHD4" "LVT_F_DIODEHD8" "LVT_I2NOR4HDV0" "LVT_I2NOR4HDV1" "LVT_I2NOR4HDV2" "LVT_I2NOR4HDV4" "LVT_IAO22HDV0" "LVT_IAO22HDV1" "LVT_IAO22HDV2" "LVT_IAO22HDV4" "LVT_INOR4HDV0" "LVT_INOR4HDV1" "LVT_INOR4HDV2" "LVT_INOR4HDV4" "LVT_MAOI222HDV0" "LVT_MAOI222HDV1" "LVT_MAOI222HDV2" "LVT_MAOI222HDV4" "LVT_MUX4HDV1" "LVT_NOR4HDV0" "LVT_NOR4HDV1" "LVT_NOR4HDV2" "LVT_NOR4HDV3" "LVT_NOR4HDV4" "LVT_NOR4HDV8" "LVT_OA222HDV0" "LVT_OA222HDV1" "LVT_OA222HDV2" "LVT_OA222HDV4" "LVT_OA33HDV0" "LVT_OA33HDV1" "LVT_OA33HDV2" "LVT_OA33HDV4" "LVT_OAI222HDV0" "LVT_OAI222HDV1" "LVT_OAI222HDV2" "LVT_OAI222HDV4" "LVT_OAI33HDV0" "LVT_OAI33HDV1" "LVT_OAI33HDV2" "LVT_OAI33HDV4" "LVT_PULLHD0" "LVT_PULLHD1" "LVT_TBUFHDV0" "LVT_TBUFHDV1" "LVT_TBUFHDV12" "LVT_TBUFHDV16" "LVT_TBUFHDV2" "LVT_TBUFHDV20" "LVT_TBUFHDV24" "LVT_TBUFHDV3" "LVT_TBUFHDV4" "LVT_TBUFHDV6" "LVT_TBUFHDV8" "LVT_XNOR4HDV0" "LVT_XNOR4HDV1" "LVT_XNOR4HDV2" "LVT_XNOR4HDV4"]
    # set the dff dont_use
    set dff_cells_dont_use_list [lmap cell $dff_dont_use_cells {concat "-dont_use" $cell}]
    set dff_cells_dont_use_args [concat {*}$dff_cells_dont_use_list]
    # set the comb dont_use
    set comb_cells_dont_use_list [lmap cell $comb_dont_use_cells {concat "-dont_use" $cell}]
    set comb_cells_dont_use_args [concat {*}$comb_cells_dont_use_list]
} elseif {$pdk == "IHP130"} {
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