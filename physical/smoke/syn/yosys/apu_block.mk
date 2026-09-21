# Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

# APU block-level IHP130 synthesis + STA evidence flow (docs/ip/apu.md P8).
#
# Top: apb4_apu with parameter EnableP7 selected by APU_BLOCK_ENABLE_P7=0|1.
# Synthesis mirrors the whole-SoC Yosys flow (same script passes, same locked
# tools) with measured ABC deviations: the block recipe drops the "&fraig -x"
# SAT-sweeping pass (script/abc_balanced_apu_block.script), which does not
# terminate on the APU multiplier-dominated AIGs (14+ h on apu_kernel_engine
# alone with the stock recipe), and the giant KWS register-file window module
# is mapped in a second ABC phase with script/abc_balanced_apu_block_kws.script
# (block recipe minus "&dch -f", which likewise does not terminate on its
# 36.7M-AND network; measured 20.4 GB peak RSS, versus ~208 GB orphans with
# the stock recipe). STA runs OpenSTA at the 20.833 ns PCLK target
# with the block SDC in physical/smoke/sta/opensta/apu_block.sdc.
#
# Standalone use (until the root Makefile wires the include):
#   make -f physical/smoke/syn/yosys/apu_block.mk CONFIG=configs/ci/ihp130.mk \
#       apu-block-evidence
# Root-Makefile integration: include this file after yosys.mk/opensta.mk.

ifeq ($(origin ROOT_PATH),undefined)
ROOT_PATH := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../../..)
SYNTH     := YOSYS
STA       := OPENSTA
include $(ROOT_PATH)/Makefile
endif

# Sub-makes must reload this file in standalone mode, or the root Makefile
# once this file is wired into it.
APU_BLOCK_SELF := $(firstword $(MAKEFILE_LIST))

ifeq ($(origin OPENSTA_LIBERTY),undefined)
include $(ROOT_PATH)/physical/smoke/sta/opensta/pdk_timing.mk
endif

APU_BLOCK_ENABLE_P7 ?= 1
APU_BLOCK_TOP    := apb4_apu
APU_BLOCK_TAG    := p$(APU_BLOCK_ENABLE_P7)-$(SYNTH_RECIPE)
APU_BLOCK_SYN    := $(VARIANT_ROOT)/syn/apu-block-$(APU_BLOCK_TAG)
APU_BLOCK_STA    := $(VARIANT_ROOT)/sta/apu-block-$(APU_BLOCK_TAG)
APU_BLOCK_OUT    := $(APU_BLOCK_SYN)/out
APU_BLOCK_TMP    := $(APU_BLOCK_SYN)/tmp
APU_BLOCK_RPT    := $(APU_BLOCK_SYN)/rpt
APU_BLOCK_FL_DIR := $(APU_BLOCK_SYN)/filelists
APU_BLOCK_FL     := $(APU_BLOCK_FL_DIR)/apu_block.fl

APU_BLOCK_NETLIST   := $(APU_BLOCK_OUT)/$(APU_BLOCK_TOP)_yosys.v
APU_BLOCK_CONFIG    := $(APU_BLOCK_OUT)/$(APU_BLOCK_TOP)_yosys.config
APU_BLOCK_EXPORTER  := $(ROOT_PATH)/physical/smoke/syn/tools/export_apu_block_filelist.py
APU_BLOCK_SYNTH_TCL := $(ROOT_PATH)/physical/smoke/syn/yosys/script/apu_block_synth.tcl
APU_BLOCK_STA_TCL   := $(ROOT_PATH)/physical/smoke/sta/opensta/apu_block_opensta.tcl
APU_BLOCK_SDC       := $(ROOT_PATH)/physical/smoke/sta/opensta/apu_block.sdc
APU_BLOCK_REPORT_PY := $(ROOT_PATH)/physical/smoke/syn/yosys/report_apu_block.py
APU_BLOCK_REPORT_DIR := $(VARIANT_ROOT)/syn/apu-block-$(SYNTH_RECIPE)

APU_BLOCK_YOSYS_SCRIPTS := $(APU_BLOCK_SYNTH_TCL) \
	$(ROOT_PATH)/physical/smoke/syn/yosys/script/common.tcl \
	$(ROOT_PATH)/physical/smoke/syn/yosys/script/init_tech.tcl \
	$(ROOT_PATH)/physical/smoke/syn/yosys/script/abc_$(SYNTH_RECIPE).script \
	$(ROOT_PATH)/physical/smoke/syn/yosys/script/abc_$(SYNTH_RECIPE)_apu_block_kws.script \
	$(wildcard $(ROOT_PATH)/physical/smoke/syn/yosys/script/abc_$(SYNTH_RECIPE)_apu_block.script) \
	$(wildcard $(ROOT_PATH)/physical/smoke/syn/yosys/script/abc_$(SYNTH_RECIPE)_apu_block.script)

# APU hierarchy accounting keep list: SoC-style slang variant patterns plus
# the plain type patterns; union keeps every apu_* submodule and tc_sram
# wrapper hierarchical for per-block cell/macro accounting.
APU_BLOCK_KEEP_HIER := "t:tc_sram*$$*" "t:apu_*$$*" "t:tc_sram*" "t:apu_*"

# The block runs at the PCLK target only; derive 20833 ps from the locked
# clock/reset inventory instead of typing the number here.
ifeq ($(origin APU_BLOCK_TARGET_PERIOD_PS),undefined)
APU_BLOCK_TARGET_PERIOD_PS := $(shell python3 $(ROOT_PATH)/scripts/yosys_period.py \
	--domains $(ROOT_PATH)/rtl/mini/integration/clock_reset_domains.json --domain pclk)
ifeq ($(strip $(APU_BLOCK_TARGET_PERIOD_PS)),)
$(error Failed to derive APU_BLOCK_TARGET_PERIOD_PS from the clock/reset inventory)
endif
endif

OPENSTA           ?= sta
OPENSTA_THREADS   ?= $(JOBS)
APU_BLOCK_REPORT      := $(APU_BLOCK_STA)/apu_block_sta_max.log
APU_BLOCK_REPORT_MIN  := $(APU_BLOCK_STA)/apu_block_sta_min.log
APU_BLOCK_WORST       := $(APU_BLOCK_STA)/apu_block_worst.log
APU_BLOCK_CHECK       := $(APU_BLOCK_STA)/unconstrained.rpt
APU_BLOCK_CHECK_TYPES := $(APU_BLOCK_STA)/check_types.rpt
APU_BLOCK_METRICS     := $(APU_BLOCK_STA)/timing_metrics.rpt
APU_BLOCK_STA_LOG     := $(APU_BLOCK_STA)/opensta.log
APU_BLOCK_STA_RESULT  := $(APU_BLOCK_STA)/result-sta.json
APU_BLOCK_SYN_RESULT  := $(APU_BLOCK_SYN)/result-synth.json

$(APU_BLOCK_FL): $(APU_BLOCK_EXPORTER) $(FILELIST_TEMPLATES) \
		$(RTL_PATH)/script/generate_filelist.py $(RTL_PATH)/script/filelist.py
	@mkdir -p $(APU_BLOCK_FL_DIR)
	python3 $(APU_BLOCK_EXPORTER) --output-dir $(APU_BLOCK_FL_DIR) \
		$(foreach define,$(DEF_LIST),--define $(define))

apu-block-filelist: $(APU_BLOCK_FL)

$(APU_BLOCK_NETLIST): $(APU_BLOCK_FL) $(APU_BLOCK_YOSYS_SCRIPTS)
	@mkdir -p $(APU_BLOCK_OUT)
	@mkdir -p $(APU_BLOCK_TMP)
	@mkdir -p $(APU_BLOCK_RPT)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool yosys \
		--log $(APU_BLOCK_SYN)/$(APU_BLOCK_TOP).log --result $(APU_BLOCK_SYN_RESULT) \
		--env PDK=$(PDK) --env SOC=$(SOC) --env SYNTH_RECIPE=$(SYNTH_RECIPE) \
		--env HAVE_SRAM_MACRO=$(HAVE_SRAM_MACRO) --env SRAM_SIZE_KIB=$(SRAM_SIZE_KIB) \
		--env YOSYS_TARGET_PERIOD_PS=$(APU_BLOCK_TARGET_PERIOD_PS) \
		--env SV_FLIST=$(APU_BLOCK_FL) --env TOP_DESIGN=$(APU_BLOCK_TOP) \
		--env CONFIG=$(APU_BLOCK_CONFIG) --env APU_ENABLE_P7=$(APU_BLOCK_ENABLE_P7) \
		--env YOSYS_FLATTEN_HIER=1 --env 'YOSYS_KEEP_HIER_INST=$(APU_BLOCK_KEEP_HIER)' \
		--env PROJ_NAME=$(APU_BLOCK_TOP) --env WORK=$(APU_BLOCK_TMP) \
		--env BUILD=$(APU_BLOCK_OUT) --env REPORTS=$(APU_BLOCK_RPT) \
		--env NETLIST=$(APU_BLOCK_NETLIST) -- \
		yosys -c $(APU_BLOCK_SYNTH_TCL)

apu-block-synth: $(APU_BLOCK_NETLIST)

apu-block-sta: $(APU_BLOCK_NETLIST) $(APU_BLOCK_SDC) $(APU_BLOCK_STA_TCL)
	@mkdir -p $(APU_BLOCK_STA)
	@for input in $(APU_BLOCK_NETLIST) $(OPENSTA_LIBERTY) $(OPENSTA_SRAM_LIBS) \
		$(APU_BLOCK_SDC) $(APU_BLOCK_CONFIG); do \
		test -f "$$input" || { echo "OpenSTA input missing: $$input" >&2; exit 1; }; \
	done
	@grep -qx 'PDK=$(PDK)' $(APU_BLOCK_CONFIG) || { \
		echo "OpenSTA netlist configuration does not match PDK=$(PDK); rerun synthesis" >&2; \
		exit 1; }
	@grep -qx 'APU_ENABLE_P7=$(APU_BLOCK_ENABLE_P7)' $(APU_BLOCK_CONFIG) || { \
		echo "OpenSTA netlist APU_ENABLE_P7=$(APU_BLOCK_ENABLE_P7) mismatch; rerun synthesis" >&2; \
		exit 1; }
	@grep -qx 'HAVE_SRAM_MACRO=$(HAVE_SRAM_MACRO)' $(APU_BLOCK_CONFIG) || { \
		echo "OpenSTA netlist SRAM macro configuration mismatch; rerun synthesis" >&2; \
		exit 1; }
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool opensta --log $(APU_BLOCK_STA_LOG) \
		--result $(APU_BLOCK_STA_RESULT) \
		--env OPENSTA_NETLIST=$(APU_BLOCK_NETLIST) --env OPENSTA_LIBERTY=$(OPENSTA_LIBERTY) \
		--env 'OPENSTA_SRAM_LIBS=$(OPENSTA_SRAM_LIBS)' \
		--env OPENSTA_SDC=$(APU_BLOCK_SDC) --env OPENSTA_REPORT=$(APU_BLOCK_REPORT) \
		--env OPENSTA_REPORT_MIN=$(APU_BLOCK_REPORT_MIN) --env OPENSTA_WORST=$(APU_BLOCK_WORST) \
		--env OPENSTA_METRICS=$(APU_BLOCK_METRICS) --env OPENSTA_CHECK_TIMING=$(APU_BLOCK_CHECK) \
		--env OPENSTA_CHECK_TYPES=$(APU_BLOCK_CHECK_TYPES) -- \
		$(OPENSTA) -no_init -exit -threads $(OPENSTA_THREADS) $(APU_BLOCK_STA_TCL)

apu-block-report:
	python3 $(APU_BLOCK_REPORT_PY) \
		--baseline-synth $(VARIANT_ROOT)/syn/apu-block-p0-$(SYNTH_RECIPE) \
		--expanded-synth $(VARIANT_ROOT)/syn/apu-block-p1-$(SYNTH_RECIPE) \
		--baseline-sta $(VARIANT_ROOT)/sta/apu-block-p0-$(SYNTH_RECIPE) \
		--expanded-sta $(VARIANT_ROOT)/sta/apu-block-p1-$(SYNTH_RECIPE) \
		--output-dir $(APU_BLOCK_REPORT_DIR) --recipe $(SYNTH_RECIPE)

apu-block-evidence:
	$(MAKE) -f $(APU_BLOCK_SELF) APU_BLOCK_ENABLE_P7=0 apu-block-synth apu-block-sta
	$(MAKE) -f $(APU_BLOCK_SELF) APU_BLOCK_ENABLE_P7=1 apu-block-synth apu-block-sta
	$(MAKE) -f $(APU_BLOCK_SELF) apu-block-report

apu-block-clean:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(VARIANT_ROOT)/syn/apu-block-p0-$(SYNTH_RECIPE)
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(VARIANT_ROOT)/syn/apu-block-p1-$(SYNTH_RECIPE)
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(VARIANT_ROOT)/sta/apu-block-p0-$(SYNTH_RECIPE)
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(VARIANT_ROOT)/sta/apu-block-p1-$(SYNTH_RECIPE)
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(APU_BLOCK_REPORT_DIR)

.PHONY: apu-block-filelist apu-block-synth apu-block-sta apu-block-report \
	apu-block-evidence apu-block-clean
