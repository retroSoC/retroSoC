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
set script_dir [file dirname [info script]]
source $script_dir/common.tcl

# read liberty files and prepare some variables
source $script_dir/init_tech.tcl

# # read design
yosys read_slang --top $top_design -F $sv_flist \
        --keep-hierarchy --allow-use-before-declare --ignore-initial --ignore-timing

# # preserve hierarchy of selected modules/instances
if { [info exists ::env(YOSYS_KEEP_HIER_INST)] } {
    foreach sel $::env(YOSYS_KEEP_HIER_INST) {
        puts "Keeping hierarchy of selection: $sel"
        yosys select -list {*}$sel
        yosys setattr -set keep_hierarchy 1 {*}$sel
    }
}

# map dont_touch attribute commonly applied to output-nets of async regs to keep
yosys attrmap -rename dont_touch keep
# copy the keep attribute to their driving cells (retain on net for debugging)
yosys attrmvcp -copy -attr keep


# -----------------------------------------------------------------------------
# this section heavily borrows from the yosys synth command:
# synth - check
yosys hierarchy -check -top $top_design
yosys proc
yosys tee -q -o "${report_dir}/${proj_name}_initial.rpt" stat
yosys write_verilog -norename -noexpr -attr2comment ${build_dir}/${proj_name}_yosys_initial.v

# synth - coarse:
# yosys synth -run coarse -noalumacc
yosys opt_expr
yosys opt_clean
yosys check
yosys opt -noff
yosys fsm
yosys opt
yosys tee -q -o "${report_dir}/${proj_name}_initial_opt.rpt" stat
yosys wreduce 
yosys peepopt
yosys opt_clean
yosys opt -full
yosys booth
yosys alumacc
yosys share
yosys opt
yosys memory
yosys opt -fast

yosys opt_dff -sat -nodffe -nosdff
yosys share
yosys opt -full
yosys clean -purge

yosys write_verilog -norename ${work_dir}/${proj_name}_abstract.yosys.v
yosys tee -q -o "${report_dir}/${proj_name}_abstract.rpt" stat -tech cmos

yosys techmap
yosys opt -fast
yosys clean -purge


# -----------------------------------------------------------------------------
yosys tee -q -o "${report_dir}/${proj_name}_generic.rpt" stat -tech cmos
yosys tee -q -o "${report_dir}/${proj_name}_generic.json" stat -json -tech cmos

if {[envVarValid "YOSYS_FLATTEN_HIER"]} {
	yosys flatten
}

yosys clean -purge


# -----------------------------------------------------------------------------
# split internal nets
yosys splitnets -format __v
# rename DFFs from the driven signal
yosys rename -wire -suffix _reg t:*DFF*
yosys select -write ${report_dir}/${proj_name}_registers.rpt t:*DFF*
# rename all other cells
# yosys autoname t:*DFF* %n
yosys clean -purge

# print paths to important instances
set report [open ${report_dir}/${proj_name}_instances.rpt "w"]
close $report
if { [info exists ::env(YOSYS_REPORT_INSTS)] } {
    foreach sel $::env(YOSYS_REPORT_INSTS) {
        yosys tee -q -a ${report_dir}/${proj_name}_instances.rpt  select -list {*}$sel
    }
}

yosys tee -q -o "${report_dir}/${proj_name}_pre_tech.rpt" stat -tech cmos
yosys tee -q -o "${report_dir}/${proj_name}_pre_tech.json" stat -json -tech cmos


# -----------------------------------------------------------------------------
# mapping to technology

set abc_script_src $script_dir/abc_${synth_recipe}.script
if {![file exists $abc_script_src]} {
    error "unsupported SYNTH_RECIPE: $synth_recipe"
}
set abc_script [processAbcScript $abc_script_src]

set abc_constr $work_dir/abc.constr
set constr_file [open $abc_constr w]
puts $constr_file "set_driving_cell $abc_driver"
puts $constr_file "set_load $abc_load"
close $constr_file

puts "Using SYNTH_RECIPE=$synth_recipe ABC script $abc_script_src (period_ps=$period_ps)"
yosys dfflibmap {*}$tech_cells_args
yosys abc {*}$tech_cells_args -D $period_ps -script $abc_script -constr $abc_constr


yosys clean -purge


# -----------------------------------------------------------------------------
# prep for openROAD
yosys write_verilog -norename -noexpr -attr2comment ${build_dir}/${proj_name}_yosys_debug.v

yosys splitnets -ports -format __v
yosys setundef -zero
yosys clean -purge

if {[llength $tech_cell_tiehi] > 0 && [llength $tech_cell_tielo] > 0} {
    yosys hilomap -singleton -hicell {*}$tech_cell_tiehi -locell {*}$tech_cell_tielo
}

# final reports
yosys tee -q -o "${report_dir}/${proj_name}_synth.rpt" check
yosys tee -q -o "${report_dir}/${proj_name}_area.rpt" stat -top $top_design {*}$liberty_args
yosys tee -q -o "${report_dir}/${proj_name}_area.json" stat -json -top $top_design {*}$liberty_args
yosys tee -q -o "${report_dir}/${proj_name}_area_logic.rpt" stat -top $top_design {*}$tech_cells_args

# final netlist
yosys write_verilog -noattr -noexpr -nohex -nodec $netlist

# Record the configuration only after the netlist has been written successfully.
set config_tmp "${config}.tmp"
set config_file [open $config_tmp "w"]
puts $config_file "PDK=$pdk"
puts $config_file "SOC=$soc"
puts $config_file "TOP_DESIGN=$top_design"
puts $config_file "SYNTH_RECIPE=$synth_recipe"
puts $config_file "PERIOD_PS=$period_ps"
puts $config_file "HAVE_SRAM_MACRO=$::env(HAVE_SRAM_MACRO)"
puts $config_file "SRAM_SIZE_KIB=$::env(SRAM_SIZE_KIB)"
close $config_file
file rename -force $config_tmp $config
