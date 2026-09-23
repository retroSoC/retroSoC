# Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

# Isolated apb4_ga2d block synthesis evidence (GA2D Phase 6). This flow is
# additive to the full-SoC yosys flow in yosys.mk: it reuses script/synth.tcl
# with a GA2D-scoped filelist and TOP_DESIGN=apb4_ga2d_block_top (a pin-level
# wrapper exposing the apb4_ga2d interface ports as plain pins), keeps the
# balanced recipe, and targets the PCLK period from the clock/reset inventory.
# Outputs stay below $(SYN_BUILD_ROOT)/ga2d-block inside the current build
# variant.

GA2D_BLOCK_TOP    := apb4_ga2d_block_top
GA2D_BLOCK_BUILD  := $(SYN_BUILD_ROOT)/ga2d-block
GA2D_BLOCK_FL_DIR := $(GA2D_BLOCK_BUILD)/filelists
GA2D_BLOCK_OUT    := $(GA2D_BLOCK_BUILD)/out
GA2D_BLOCK_TMP    := $(GA2D_BLOCK_BUILD)/tmp
GA2D_BLOCK_RPT    := $(GA2D_BLOCK_BUILD)/rpt

GA2D_BLOCK_FLIST       := $(GA2D_BLOCK_FL_DIR)/ga2d_block_yosys.fl
GA2D_BLOCK_NETLIST     := $(GA2D_BLOCK_OUT)/$(GA2D_BLOCK_TOP)_yosys.v
GA2D_BLOCK_CONFIG      := $(GA2D_BLOCK_OUT)/$(GA2D_BLOCK_TOP)_yosys.config
GA2D_BLOCK_LOG         := $(GA2D_BLOCK_BUILD)/$(GA2D_BLOCK_TOP).log
GA2D_BLOCK_DEPFILE     := $(GA2D_BLOCK_BUILD)/yosys.d
GA2D_BLOCK_SUMMARY     := $(GA2D_BLOCK_RPT)/ga2d_block_summary.json
GA2D_BLOCK_SUMMARY_GEN := $(ROOT_PATH)/scripts/ga2d_block_summary.py
GA2D_BLOCK_SCRIPTS     := $(wildcard $(YOSYS_DIR)/script/*) $(YOSYS_DIR)/synth_config.mk \
                            $(YOSYS_DIR)/yosys.mk $(YOSYS_DIR)/ga2d_block.mk \
                            rtl/mini/filelist/ga2d_block.fl

# The GA2D block is clocked by PCLK; derive the ABC target period from the same
# clock/reset inventory as the SoC flow (20.833333333 ns, never weakened).
GA2D_BLOCK_TARGET_PERIOD_PS := $(shell python3 $(ROOT_PATH)/scripts/yosys_period.py \
	--domains $(ROOT_PATH)/rtl/mini/integration/clock_reset_domains.json --domain pclk)
ifeq ($(strip $(GA2D_BLOCK_TARGET_PERIOD_PS)),)
$(error Failed to derive GA2D_BLOCK_TARGET_PERIOD_PS from the clock/reset inventory)
endif

-include $(GA2D_BLOCK_DEPFILE)

# Private generated filelists: the canonical templates are expanded with the
# active DEF_LIST but without the SoC generated-include chain, so the block
# flow does not depend on the HP/pin-map generation stamps.
$(GA2D_BLOCK_FL_DIR)/.stamp: $(RTL_PATH)/script/generate_filelist.py \
	$(RTL_PATH)/script/filelist.py \
	$(sort $(wildcard $(ROOT_PATH)/rtl/filelist/pdk_*.fl) \
	$(wildcard $(RTL_PATH)/filelist/*.fl) $(RTL_PATH)/lint.msg)
	$(FLOW_PYTHON) $(RTL_PATH)/script/generate_filelist.py \
		--output-dir $(GA2D_BLOCK_FL_DIR) \
		$(foreach define,$(DEF_LIST),--define $(define))
	@touch $@

$(GA2D_BLOCK_FLIST): $(GA2D_BLOCK_FL_DIR)/.stamp $(MEMORY_MAP_STAMP)
	@python3 $(RTL_PATH)/script/comb.py \
		-f $(GA2D_BLOCK_FL_DIR)/def.fl \
		-f $(MEMORY_MAP_FILELIST) \
		-f $(GA2D_BLOCK_FL_DIR)/ga2d_block.fl --output $@
	@python3 $(RTL_PATH)/script/filelist_deps.py -f $@ \
		--extra $(MEMORY_MAP_FILELIST) \
		--target $(GA2D_BLOCK_NETLIST) --output $(GA2D_BLOCK_DEPFILE)

## Synthesize the isolated apb4_ga2d block using Yosys
synth-ga2d-block: $(GA2D_BLOCK_SUMMARY) | manifest

$(GA2D_BLOCK_NETLIST): $(GA2D_BLOCK_FLIST) $(GA2D_BLOCK_SCRIPTS)
	@mkdir -p $(GA2D_BLOCK_OUT)
	@mkdir -p $(GA2D_BLOCK_TMP)
	@mkdir -p $(GA2D_BLOCK_RPT)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool yosys \
		--log $(GA2D_BLOCK_LOG) --result $(GA2D_BLOCK_BUILD)/result-synth.json \
		--env PDK=$(PDK) --env SOC=$(SOC) --env SYNTH_RECIPE=$(SYNTH_RECIPE) \
		--env HAVE_SRAM_MACRO=$(HAVE_SRAM_MACRO) --env SRAM_SIZE_KIB=$(SRAM_SIZE_KIB) \
		--env YOSYS_TARGET_PERIOD_PS=$(GA2D_BLOCK_TARGET_PERIOD_PS) \
		--env SV_FLIST=$(GA2D_BLOCK_FLIST) --env TOP_DESIGN=$(GA2D_BLOCK_TOP) \
		--env CONFIG=$(GA2D_BLOCK_CONFIG) --env YOSYS_KEEP_HIER_INST= \
		--env YOSYS_REPORT_INSTS= \
		--env PROJ_NAME=$(GA2D_BLOCK_TOP) --env WORK=$(GA2D_BLOCK_TMP) \
		--env BUILD=$(GA2D_BLOCK_OUT) --env REPORTS=$(GA2D_BLOCK_RPT) \
		--env NETLIST=$(GA2D_BLOCK_NETLIST) -- \
		yosys -c $(YOSYS_DIR)/script/synth.tcl

# Fails loudly on inferred latches or non-PDK (black-box/unmapped) cells and
# records the register/FIFO mapping summary consumed by the evidence section.
$(GA2D_BLOCK_SUMMARY): $(GA2D_BLOCK_NETLIST) $(GA2D_BLOCK_SUMMARY_GEN)
	python3 $(GA2D_BLOCK_SUMMARY_GEN) \
		--log $(GA2D_BLOCK_LOG) \
		--check-report $(GA2D_BLOCK_RPT)/$(GA2D_BLOCK_TOP)_synth.rpt \
		--area-json $(GA2D_BLOCK_RPT)/$(GA2D_BLOCK_TOP)_area.json \
		--registers-report $(GA2D_BLOCK_RPT)/$(GA2D_BLOCK_TOP)_registers.rpt \
		--generic-report $(GA2D_BLOCK_RPT)/$(GA2D_BLOCK_TOP)_generic.rpt \
		--top $(GA2D_BLOCK_TOP) --pdk $(PDK) --recipe $(SYNTH_RECIPE) \
		--period-ps $(GA2D_BLOCK_TARGET_PERIOD_PS) \
		--cell-prefix sg13g2_ --output $@

synth-ga2d-block-clean:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(GA2D_BLOCK_BUILD)

# Dedicated synthesized-block transaction test (GA2D Phase 6): compiles the
# block netlist with the IHP130 standard-cell simulation models (the same
# models the full-SoC netl flow consumes via pdk_ihp130.fl) plus the shared
# netlist helper cells, and runs the pin-level testbench with exact result
# checks. Icarus 13 prints non-fatal "sorry: ifnone" notes for the PDK
# specify paths; -gno-specify keeps the run delay-free.
GA2D_BLOCK_IVERILOG ?= iverilog
GA2D_BLOCK_VVP      ?= vvp

GA2D_BLOCK_NETSIM_DIR     := $(VARIANT_ROOT)/sim/iverilog/netl-ga2d-block
GA2D_BLOCK_NETLIST_TB     := $(ROOT_PATH)/tests/rtl/ga2d_netlist_tb.sv
GA2D_BLOCK_CELL_MODELS    := \
	$(ROOT_PATH)/physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_stdcell/verilog/sg13g2_udp.v \
	$(ROOT_PATH)/physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_stdcell/verilog/sg13g2_stdcell.v \
	$(ROOT_PATH)/rtl/tech/netlist_sim_cells.v
GA2D_BLOCK_SUCCESS_MARKER := GA2D P6 netlist block test passed with exact FILL COPY BLEND and validation-error coverage

## Run the GA2D block netlist transaction test using Icarus Verilog
netsim-ga2d-block: $(GA2D_BLOCK_SUMMARY) $(GA2D_BLOCK_NETLIST_TB) $(GA2D_BLOCK_CELL_MODELS) | manifest
	@mkdir -p $(GA2D_BLOCK_NETSIM_DIR)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool iverilog \
		--log $(GA2D_BLOCK_NETSIM_DIR)/compile.log --result $(GA2D_BLOCK_NETSIM_DIR)/result-compile.json \
		--cwd $(GA2D_BLOCK_NETSIM_DIR) -- $(GA2D_BLOCK_IVERILOG) -g2012 -gno-specify \
		-I $(ROOT_PATH)/rtl/ip/multimedia \
		$(GA2D_BLOCK_CELL_MODELS) $(GA2D_BLOCK_NETLIST) $(GA2D_BLOCK_NETLIST_TB) \
		-o simv -s ga2d_netlist_tb
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool iverilog-sim \
		--log $(GA2D_BLOCK_NETSIM_DIR)/sim.log --result $(GA2D_BLOCK_NETSIM_DIR)/result-sim.json \
		--cwd $(GA2D_BLOCK_NETSIM_DIR) -- $(GA2D_BLOCK_VVP) simv
	python3 $(ROOT_PATH)/scripts/check_simulation.py --log $(GA2D_BLOCK_NETSIM_DIR)/sim.log \
		--result $(GA2D_BLOCK_NETSIM_DIR)/result-sim-check.json \
		--require '$(GA2D_BLOCK_SUCCESS_MARKER)'

netsim-ga2d-block-clean:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(GA2D_BLOCK_NETSIM_DIR)

# Block-level OpenSTA evidence (GA2D Phase 6): times the synthesized
# apb4_ga2d block at the PCLK 20.833333333 ns constraint carried by
# physical/smoke/sta/opensta/ga2d_block.sdc, using the same IHP130 slow-corner
# liberty as the SoC core-STA flow (pdk_timing.mk). The block config digest is
# checked against the block synthesis config, mirroring the SoC sta target.
include $(ROOT_PATH)/physical/smoke/sta/opensta/pdk_timing.mk

OPENSTA         ?= sta
OPENSTA_THREADS ?= $(JOBS)

GA2D_BLOCK_STA_DIR    := $(STA_BUILD_ROOT)/ga2d-block
GA2D_BLOCK_STA_SDC    := $(ROOT_PATH)/physical/smoke/sta/opensta/ga2d_block.sdc
GA2D_BLOCK_STA_TCL    := $(ROOT_PATH)/physical/smoke/sta/opensta/ga2d_block.tcl
GA2D_BLOCK_STA_REPORT := $(GA2D_BLOCK_STA_DIR)/$(GA2D_BLOCK_TOP)_sta.log
GA2D_BLOCK_STA_PATHS  := $(GA2D_BLOCK_STA_DIR)/$(GA2D_BLOCK_TOP)_paths.rpt

## Run OpenSTA on the isolated apb4_ga2d block netlist
sta-ga2d-block: $(GA2D_BLOCK_SUMMARY) $(GA2D_BLOCK_STA_SDC) $(GA2D_BLOCK_STA_TCL) | manifest
	@mkdir -p $(GA2D_BLOCK_STA_DIR)
	@for input in $(GA2D_BLOCK_NETLIST) $(OPENSTA_LIBERTY) $(GA2D_BLOCK_STA_SDC) $(GA2D_BLOCK_CONFIG); do \
		test -f "$$input" || { echo "OpenSTA block input missing: $$input" >&2; exit 1; }; \
	done
	@grep -qx 'PDK=$(PDK)' $(GA2D_BLOCK_CONFIG) || { \
		echo "OpenSTA block netlist configuration does not match PDK=$(PDK); rerun synthesis" >&2; \
		exit 1; \
		}
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool opensta \
		--log $(GA2D_BLOCK_STA_DIR)/opensta.log --result $(GA2D_BLOCK_STA_DIR)/result-sta.json \
		--env OPENSTA_NETLIST=$(GA2D_BLOCK_NETLIST) --env OPENSTA_LIBERTY=$(OPENSTA_LIBERTY) \
		--env OPENSTA_SDC=$(GA2D_BLOCK_STA_SDC) --env OPENSTA_REPORT=$(GA2D_BLOCK_STA_REPORT) \
		--env OPENSTA_TOP_PATHS=$(GA2D_BLOCK_STA_PATHS) \
		--env OPENSTA_METRICS=$(GA2D_BLOCK_STA_DIR)/timing_metrics.rpt -- \
		$(OPENSTA) -no_init -exit -threads $(OPENSTA_THREADS) $(GA2D_BLOCK_STA_TCL)

sta-ga2d-block-clean:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(GA2D_BLOCK_STA_DIR)

.PHONY: synth-ga2d-block synth-ga2d-block-clean netsim-ga2d-block netsim-ga2d-block-clean \
	sta-ga2d-block sta-ga2d-block-clean