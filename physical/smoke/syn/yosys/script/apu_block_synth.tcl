# Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

# APU block-level synthesis (top: apb4_apu), derived from script/synth.tcl.
# Differences from the whole-SoC flow:
#   * APU_ENABLE_P7 selects the apb4_apu EnableP7 parameter via chparam.
#   * The hierarchy keep list comes from the flow environment and keeps every
#     apu_* submodule plus the tc_sram wrappers for per-block accounting.
#   * Additional latch and PDK macro inventory reports are emitted (before
#     ABC, so long-running runs still leave that evidence behind).
#   * The ABC recipe prefers abc_<recipe>_apu_block.script when present: the
#     whole-SoC recipe's "&fraig -x" pass does not terminate on the APU
#     multiplier-dominated AIGs; the variant drops only that pass.
#   * ABC runs in two phases: the giant KWS register-file window module
#     (apu_kws_sram_client) uses abc_<recipe>_apu_block_kws.script (the block
#     recipe minus "&dch -f", which does not terminate on its 36.7M-AND
#     network); every other module uses the standard block recipe.

# get environment variables
set script_dir [file dirname [info script]]
source $script_dir/common.tcl

# read liberty files and prepare some variables
source $script_dir/init_tech.tcl

if {![info exists ::env(APU_ENABLE_P7)] || ($::env(APU_ENABLE_P7) ni {0 1})} {
    error "APU_ENABLE_P7 must be 0 or 1"
}
set apu_enable_p7 $::env(APU_ENABLE_P7)

# # read design
# --allow-toplevel-iface-ports: apb4_apu has SystemVerilog interface ports
# (apb4/axi4/streams); slang elaborates each as an unconnected top-level
# interface instance so the block can be synthesized standalone.
# -G EnableP7: slang elaborates parameters itself, so the APU feature
# configuration is applied as a top-level parameter override (the same
# mechanism as the .EnableP7(...) binding in rtl/mini/top/apb4_periph.sv);
# yosys chparam cannot re-parameterize an already-elaborated module.
yosys read_slang --top $top_design -F $sv_flist -G EnableP7=$apu_enable_p7 \
        --keep-hierarchy --allow-use-before-declare --ignore-initial --ignore-timing \
        --allow-toplevel-iface-ports

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

yosys tee -q -o "${report_dir}/${proj_name}_pre_tech.rpt" stat -tech cmos
yosys tee -q -o "${report_dir}/${proj_name}_pre_tech.json" stat -json -tech cmos

# inferred-latch and PDK macro inventories are mapping-independent; emit them
# before ABC so long-running runs still leave this evidence behind
yosys tee -q -o "${report_dir}/${proj_name}_latches.rpt" select -list t:*DLATCH*
yosys tee -q -o "${report_dir}/${proj_name}_macros.rpt" select -list t:RM_IHPSG13*


# -----------------------------------------------------------------------------
# mapping to technology

# Prefer the APU block recipe variant (abc_<recipe>_apu_block.script): the
# whole-SoC recipe's "&fraig -x" SAT sweeping does not terminate on the APU
# multiplier-dominated AIGs (14+ h on apu_kernel_engine alone); the variant
# drops only that pass. See the script header for the measured evidence.
set abc_script_block $script_dir/abc_${synth_recipe}_apu_block.script
set abc_script_src $script_dir/abc_${synth_recipe}.script
if {[file exists $abc_script_block]} {
    set abc_script_src $abc_script_block
} elseif {![file exists $abc_script_src]} {
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

# Two-phase ABC. apu_kws_sram_client models the 64 KiB KWS model/scratch
# register-file window as one 16384x32 RTL memory with 36 asynchronous read
# ports and 7 write ports; memory_map lowers it to ~12.6M gate-level cells
# (36.7M ANDs after strash). On that network the block recipe's "&dch -f"
# choice pass does not terminate (>50 min without progress, killed,
# yosys-abc 0.67, 2026-09-17), exactly like the stock recipe's "&fraig -x"
# (two orphaned abc children at ~208 GB RSS each, killed, 2026-09-16). The
# KWS module alone is therefore mapped with abc_<recipe>_apu_block_kws.script
# (block recipe minus both passes; measured 1 h 27 min / 20.4 GB peak on the
# exact abc input network, -D 20833 ps, sg13g2 typ liberty). Every other
# module keeps the standard block recipe with identical liberty, driving
# cell, load, and delay target. The assert fails the run loudly if RTL
# renames the module instead of silently hanging in the heavy recipe.
set abc_script_kws $script_dir/abc_${synth_recipe}_apu_block_kws.script
if {![file exists $abc_script_kws]} {
    error "missing KWS-window ABC script: $abc_script_kws"
}
set abc_kws [processAbcScript $abc_script_kws]
puts "Using KWS-window ABC script $abc_script_kws for apu_kws_sram_client only"
yosys select -assert-any apu_kws_sram_client*
yosys abc {*}$tech_cells_args -D $period_ps -script $abc_kws -constr $abc_constr apu_kws_sram_client*
yosys abc {*}$tech_cells_args -D $period_ps -script $abc_script -constr $abc_constr * apu_kws_sram_client* %d


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
puts $config_file "APU_ENABLE_P7=$apu_enable_p7"
puts $config_file "HAVE_SRAM_MACRO=$::env(HAVE_SRAM_MACRO)"
puts $config_file "SRAM_SIZE_KIB=$::env(SRAM_SIZE_KIB)"
close $config_file
file rename -force $config_tmp $config
