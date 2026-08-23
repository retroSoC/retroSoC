# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

SHELL := /bin/sh
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:

FLOW_ROOT := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
ROOT_PATH := $(abspath $(FLOW_ROOT)/../..)

LOCAL_CONFIG ?= $(FLOW_ROOT)/local/ics55-production.mk
-include $(LOCAL_CONFIG)

TOP         ?= retrosoc_asic
TECHNOLOGY  ?= ICS55
FLOW_PYTHON ?= python
TCLSH       ?= tclsh
RUN_ID      ?= current
BUILD_ROOT  ?= $(ROOT_PATH)/build
RUN_ROOT    ?= $(abspath $(BUILD_ROOT))/commercial/ics55/$(RUN_ID)

INPUT_DIR := $(RUN_ROOT)/input
META_DIR  := $(RUN_ROOT)/meta
STAMP_DIR := $(META_DIR)/stamps

INPUT_STAMP      := $(STAMP_DIR)/input.stamp
SYN_STAMP        := $(STAMP_DIR)/syn.stamp
FM_RTL2SYN_STAMP := $(STAMP_DIR)/fm-rtl2syn.stamp
APR_INIT_STAMP   := $(STAMP_DIR)/apr-initialize.stamp
APR_FP_STAMP     := $(STAMP_DIR)/apr-floorplan.stamp
APR_PRE_STAMP    := $(STAMP_DIR)/apr-preplace.stamp
APR_PLACE_STAMP  := $(STAMP_DIR)/apr-place.stamp
APR_CTS_STAMP    := $(STAMP_DIR)/apr-cts.stamp
APR_ROUTE_STAMP  := $(STAMP_DIR)/apr-route.stamp
FM_SYN2PR_STAMP  := $(STAMP_DIR)/fm-syn2pr.stamp
EXTRACT_STAMP    := $(STAMP_DIR)/extract.stamp
STA_STAMP        := $(STAMP_DIR)/sta.stamp
ECO_STAMP        := $(STAMP_DIR)/eco.stamp
APR_ECO_STAMP    := $(STAMP_DIR)/apr-eco.stamp
REEXTRACT_STAMP  := $(STAMP_DIR)/reextract.stamp
RESTA_STAMP      := $(STAMP_DIR)/resta.stamp
PV_MERGE_STAMP   := $(STAMP_DIR)/pv-merge.stamp
PV_DRC_STAMP     := $(STAMP_DIR)/pv-drc.stamp
PV_ANT_STAMP     := $(STAMP_DIR)/pv-antenna.stamp
PV_LVS_STAMP     := $(STAMP_DIR)/pv-lvs.stamp

RUN_STAGE  := $(FLOW_PYTHON) $(FLOW_ROOT)/scripts/run_stage.py
SUBMIT_JOB := $(FLOW_PYTHON) $(FLOW_ROOT)/scripts/submit_job.py

define submit-job
$(SUBMIT_JOB) --mode $(LSF_MODE) --bsub-command "$(LSF_COMMAND)" \
	--bsub-args "$(strip $(LSF_COMMON_ARGS) $($(1)))" --tool-log $(2) --
endef

# Export the ignored local configuration and the derived run locations to LSF.
export

.PHONY: help check-config doctor boundary-check input syn fm-rtl2syn \
	apr-initialize apr-floorplan apr-preplace apr-place apr-cts apr-route \
	fm-syn2pr extract sta eco apr-eco reextract resta pv-merge pv-drc \
	pv-antenna pv-lvs signoff clean-stage list-stages

help:
	@printf '%s\n' \
	  'retroSoC ICS55 commercial flow:' \
	  '  doctor          validate EDA tools, local collateral, and RTL input' \
	  '  input           safely stage the development-zone RTL archive' \
	  '  syn             run Design Compiler synthesis' \
	  '  fm-rtl2syn      prove RTL-to-synthesis equivalence' \
	  '  apr-*           run resumable Innovus implementation stages' \
	  '  fm-syn2pr       prove synthesis-to-routed-netlist equivalence' \
	  '  extract | sta   run StarRC extraction and PrimeTime signoff' \
	  '  eco             generate PrimeTime ECO changes' \
	  '  apr-eco         apply ECO changes and incrementally route' \
	  '  reextract       extract the ECO design' \
	  '  resta           sign off the ECO design' \
	  '  pv-*            merge GDS and run Calibre DRC/antenna/LVS' \
	  '  signoff         run the complete strict stage graph' \
	  '  clean-stage     remove STAGE and all downstream stage results' \
	  '' \
	  'Set LOCAL_CONFIG=local/ics55-production.mk and optionally RUN_ID=<id>.'

list-stages:
	@printf '%s\n' input syn fm-rtl2syn apr-initialize apr-floorplan \
	  apr-preplace apr-place apr-cts apr-route fm-syn2pr extract sta eco \
	  apr-eco reextract resta pv-merge pv-drc pv-antenna pv-lvs

check-config:
	@test -f '$(LOCAL_CONFIG)' || { \
	  echo "missing ignored local configuration: $(LOCAL_CONFIG)" >&2; \
	  echo "copy config/ics55.example.mk to local/ics55-production.mk" >&2; \
	  exit 2; \
	  }
	@test '$(TECHNOLOGY)' = ICS55
	@test '$(TOP)' = retrosoc_asic

doctor: check-config
	@mkdir -p $(META_DIR)
	$(FLOW_PYTHON) $(FLOW_ROOT)/scripts/doctor.py --output $(META_DIR)/doctor.json

boundary-check:
	python3 $(FLOW_ROOT)/scripts/audit_boundary.py --root $(ROOT_PATH)

$(INPUT_STAMP): $(RTL_ARCHIVE) | check-config
	@mkdir -p $(STAMP_DIR) $(META_DIR)
	$(RUN_STAGE) --stage input --cwd $(RUN_ROOT) \
	  --log $(META_DIR)/input.log --result $(META_DIR)/input.result.json \
	  --stamp $@ --expect $(INPUT_DIR)/rtl/filelist.fl \
	  --expect $(META_DIR)/input.json -- \
	  $(FLOW_PYTHON) $(FLOW_ROOT)/scripts/prepare_input.py \
	  --archive $(RTL_ARCHIVE) --output-dir $(INPUT_DIR) \
	  --manifest $(META_DIR)/input.json

input: $(INPUT_STAMP)

$(SYN_STAMP): $(INPUT_STAMP)
	@mkdir -p $(RUN_ROOT)/syn/work $(RUN_ROOT)/syn/log $(RUN_ROOT)/syn/reports $(RUN_ROOT)/syn/output
	$(RUN_STAGE) --stage syn --cwd $(RUN_ROOT)/syn/work \
	  --log $(RUN_ROOT)/syn/log/lsf.log --result $(RUN_ROOT)/syn/result.json \
	  --stamp $@ \
	  --expect $(RUN_ROOT)/syn/output/$(TOP).syn.v \
	  --expect $(RUN_ROOT)/syn/output/$(TOP).ddc \
	  --expect $(RUN_ROOT)/syn/output/verdict.pass -- \
	  $(call submit-job,LSF_SYN_ARGS,$(RUN_ROOT)/syn/log/tool.log) \
	  $(DC_SHELL) -64 -f $(FLOW_ROOT)/tcl/syn/main.tcl

syn: $(SYN_STAMP)

$(FM_RTL2SYN_STAMP): $(SYN_STAMP)
	@mkdir -p $(RUN_ROOT)/formality/rtl2syn/work $(RUN_ROOT)/formality/rtl2syn/log $(RUN_ROOT)/formality/rtl2syn/reports $(RUN_ROOT)/formality/rtl2syn/output
	FM_MODE=RTL2SYN $(RUN_STAGE) --stage fm-rtl2syn \
	  --cwd $(RUN_ROOT)/formality/rtl2syn/work \
	  --log $(RUN_ROOT)/formality/rtl2syn/log/lsf.log \
	  --result $(RUN_ROOT)/formality/rtl2syn/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/formality/rtl2syn/output/verdict.pass -- \
	  $(call submit-job,LSF_FM_ARGS,$(RUN_ROOT)/formality/rtl2syn/log/tool.log) \
	  $(FM_SHELL) -64 -f $(FLOW_ROOT)/tcl/formality/main.tcl

fm-rtl2syn: $(FM_RTL2SYN_STAMP)

$(APR_INIT_STAMP): $(FM_RTL2SYN_STAMP)
	@mkdir -p $(RUN_ROOT)/apr/initialize/work $(RUN_ROOT)/apr/initialize/log $(RUN_ROOT)/apr/initialize/reports $(RUN_ROOT)/apr/initialize/output
	APR_STAGE=initialize $(RUN_STAGE) --stage apr-initialize \
	  --cwd $(RUN_ROOT)/apr/initialize/work \
	  --log $(RUN_ROOT)/apr/initialize/log/lsf.log \
	  --result $(RUN_ROOT)/apr/initialize/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/apr/initialize/output/$(TOP).initialize.enc.dat \
	  --expect $(RUN_ROOT)/apr/initialize/output/verdict.pass -- \
	  $(call submit-job,LSF_APR_ARGS,$(RUN_ROOT)/apr/initialize/log/tool.log) \
	  $(INNOVUS) -64 -nowin -init $(FLOW_ROOT)/tcl/apr/main.tcl

apr-initialize: $(APR_INIT_STAMP)

$(APR_FP_STAMP): $(APR_INIT_STAMP)
	@mkdir -p $(RUN_ROOT)/apr/floorplan/work $(RUN_ROOT)/apr/floorplan/log $(RUN_ROOT)/apr/floorplan/reports $(RUN_ROOT)/apr/floorplan/output
	APR_STAGE=floorplan $(RUN_STAGE) --stage apr-floorplan \
	  --cwd $(RUN_ROOT)/apr/floorplan/work \
	  --log $(RUN_ROOT)/apr/floorplan/log/lsf.log \
	  --result $(RUN_ROOT)/apr/floorplan/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/apr/floorplan/output/$(TOP).floorplan.enc.dat \
	  --expect $(RUN_ROOT)/apr/floorplan/output/verdict.pass -- \
	  $(call submit-job,LSF_APR_ARGS,$(RUN_ROOT)/apr/floorplan/log/tool.log) \
	  $(INNOVUS) -64 -nowin -init $(FLOW_ROOT)/tcl/apr/main.tcl

apr-floorplan: $(APR_FP_STAMP)

$(APR_PRE_STAMP): $(APR_FP_STAMP)
	@mkdir -p $(RUN_ROOT)/apr/preplace/work $(RUN_ROOT)/apr/preplace/log $(RUN_ROOT)/apr/preplace/reports $(RUN_ROOT)/apr/preplace/output
	APR_STAGE=preplace $(RUN_STAGE) --stage apr-preplace \
	  --cwd $(RUN_ROOT)/apr/preplace/work \
	  --log $(RUN_ROOT)/apr/preplace/log/lsf.log \
	  --result $(RUN_ROOT)/apr/preplace/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/apr/preplace/output/$(TOP).preplace.enc.dat \
	  --expect $(RUN_ROOT)/apr/preplace/output/verdict.pass -- \
	  $(call submit-job,LSF_APR_ARGS,$(RUN_ROOT)/apr/preplace/log/tool.log) \
	  $(INNOVUS) -64 -nowin -init $(FLOW_ROOT)/tcl/apr/main.tcl

apr-preplace: $(APR_PRE_STAMP)

$(APR_PLACE_STAMP): $(APR_PRE_STAMP)
	@mkdir -p $(RUN_ROOT)/apr/place/work $(RUN_ROOT)/apr/place/log $(RUN_ROOT)/apr/place/reports $(RUN_ROOT)/apr/place/output
	APR_STAGE=place $(RUN_STAGE) --stage apr-place \
	  --cwd $(RUN_ROOT)/apr/place/work \
	  --log $(RUN_ROOT)/apr/place/log/lsf.log \
	  --result $(RUN_ROOT)/apr/place/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/apr/place/output/$(TOP).place.enc.dat \
	  --expect $(RUN_ROOT)/apr/place/output/verdict.pass -- \
	  $(call submit-job,LSF_APR_ARGS,$(RUN_ROOT)/apr/place/log/tool.log) \
	  $(INNOVUS) -64 -nowin -init $(FLOW_ROOT)/tcl/apr/main.tcl

apr-place: $(APR_PLACE_STAMP)

$(APR_CTS_STAMP): $(APR_PLACE_STAMP)
	@mkdir -p $(RUN_ROOT)/apr/cts/work $(RUN_ROOT)/apr/cts/log $(RUN_ROOT)/apr/cts/reports $(RUN_ROOT)/apr/cts/output
	APR_STAGE=cts $(RUN_STAGE) --stage apr-cts \
	  --cwd $(RUN_ROOT)/apr/cts/work \
	  --log $(RUN_ROOT)/apr/cts/log/lsf.log \
	  --result $(RUN_ROOT)/apr/cts/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/apr/cts/output/$(TOP).cts.enc.dat \
	  --expect $(RUN_ROOT)/apr/cts/output/verdict.pass -- \
	  $(call submit-job,LSF_APR_ARGS,$(RUN_ROOT)/apr/cts/log/tool.log) \
	  $(INNOVUS) -64 -nowin -init $(FLOW_ROOT)/tcl/apr/main.tcl

apr-cts: $(APR_CTS_STAMP)

$(APR_ROUTE_STAMP): $(APR_CTS_STAMP)
	@mkdir -p $(RUN_ROOT)/apr/route/work $(RUN_ROOT)/apr/route/log $(RUN_ROOT)/apr/route/reports $(RUN_ROOT)/apr/route/output
	APR_STAGE=route $(RUN_STAGE) --stage apr-route \
	  --cwd $(RUN_ROOT)/apr/route/work \
	  --log $(RUN_ROOT)/apr/route/log/lsf.log \
	  --result $(RUN_ROOT)/apr/route/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/apr/route/output/$(TOP).route.enc.dat \
	  --expect $(RUN_ROOT)/apr/route/output/$(TOP).route.v \
	  --expect $(RUN_ROOT)/apr/route/output/$(TOP).route.def \
	  --expect $(RUN_ROOT)/apr/route/output/$(TOP).route.gds \
	  --expect $(RUN_ROOT)/apr/route/output/verdict.pass -- \
	  $(call submit-job,LSF_APR_ARGS,$(RUN_ROOT)/apr/route/log/tool.log) \
	  $(INNOVUS) -64 -nowin -init $(FLOW_ROOT)/tcl/apr/main.tcl

apr-route: $(APR_ROUTE_STAMP)

$(FM_SYN2PR_STAMP): $(APR_ROUTE_STAMP)
	@mkdir -p $(RUN_ROOT)/formality/syn2pr/work $(RUN_ROOT)/formality/syn2pr/log $(RUN_ROOT)/formality/syn2pr/reports $(RUN_ROOT)/formality/syn2pr/output
	FM_MODE=SYN2PR $(RUN_STAGE) --stage fm-syn2pr \
	  --cwd $(RUN_ROOT)/formality/syn2pr/work \
	  --log $(RUN_ROOT)/formality/syn2pr/log/lsf.log \
	  --result $(RUN_ROOT)/formality/syn2pr/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/formality/syn2pr/output/verdict.pass -- \
	  $(call submit-job,LSF_FM_ARGS,$(RUN_ROOT)/formality/syn2pr/log/tool.log) \
	  $(FM_SHELL) -64 -f $(FLOW_ROOT)/tcl/formality/main.tcl

fm-syn2pr: $(FM_SYN2PR_STAMP)

$(EXTRACT_STAMP): $(FM_SYN2PR_STAMP)
	@mkdir -p $(RUN_ROOT)/extract/route/work $(RUN_ROOT)/extract/route/log $(RUN_ROOT)/extract/route/reports $(RUN_ROOT)/extract/route/output
	EXTRACT_TAG=route $(TCLSH) $(FLOW_ROOT)/tcl/extract/generate.tcl
	EXTRACT_TAG=route $(RUN_STAGE) --stage extract \
	  --cwd $(RUN_ROOT)/extract/route/work \
	  --log $(RUN_ROOT)/extract/route/log/lsf.log \
	  --result $(RUN_ROOT)/extract/route/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/extract/route/output/verdict.pass -- \
	  $(call submit-job,LSF_EXTRACT_ARGS,$(RUN_ROOT)/extract/route/log/tool.log) \
	  $(FLOW_PYTHON) $(FLOW_ROOT)/scripts/run_checked.py \
	  --kind spef --root $(RUN_ROOT)/extract/route/output \
	  --top $(TOP) \
	  --verdict $(RUN_ROOT)/extract/route/output/verdict.pass -- \
	  $(STARRC) -64 $(RUN_ROOT)/extract/route/work/$(TOP).star

extract: $(EXTRACT_STAMP)

$(STA_STAMP): $(EXTRACT_STAMP)
	@mkdir -p $(RUN_ROOT)/sta/route/work $(RUN_ROOT)/sta/route/log $(RUN_ROOT)/sta/route/reports $(RUN_ROOT)/sta/route/output
	STA_TAG=route $(RUN_STAGE) --stage sta \
	  --cwd $(RUN_ROOT)/sta/route/work \
	  --log $(RUN_ROOT)/sta/route/log/lsf.log \
	  --result $(RUN_ROOT)/sta/route/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/sta/route/output/verdict.pass -- \
	  $(call submit-job,LSF_STA_ARGS,$(RUN_ROOT)/sta/route/log/tool.log) \
	  $(FLOW_PYTHON) $(FLOW_ROOT)/scripts/run_pt_scenarios.py \
	  --pt-command "$(PT_SHELL)" --tcl-command "$(TCLSH)" \
	  --scenario-script $(FLOW_ROOT)/tcl/common/list_scenarios.tcl \
	  --main $(FLOW_ROOT)/tcl/sta/main.tcl --tag route

sta: $(STA_STAMP)

$(ECO_STAMP): $(STA_STAMP)
	@mkdir -p $(RUN_ROOT)/eco/work $(RUN_ROOT)/eco/log $(RUN_ROOT)/eco/reports $(RUN_ROOT)/eco/output
	$(RUN_STAGE) --stage eco --cwd $(RUN_ROOT)/eco/work \
	  --log $(RUN_ROOT)/eco/log/lsf.log --result $(RUN_ROOT)/eco/result.json \
	  --stamp $@ --expect $(RUN_ROOT)/eco/output/eco.tcl \
	  --expect $(RUN_ROOT)/eco/output/verdict.pass -- \
	  $(call submit-job,LSF_ECO_ARGS,$(RUN_ROOT)/eco/log/tool.log) \
	  $(PT_SHELL) -multi_scenario -f $(FLOW_ROOT)/tcl/eco/main.tcl

eco: $(ECO_STAMP)

$(APR_ECO_STAMP): $(ECO_STAMP)
	@mkdir -p $(RUN_ROOT)/apr/eco/work $(RUN_ROOT)/apr/eco/log $(RUN_ROOT)/apr/eco/reports $(RUN_ROOT)/apr/eco/output
	APR_STAGE=eco $(RUN_STAGE) --stage apr-eco \
	  --cwd $(RUN_ROOT)/apr/eco/work --log $(RUN_ROOT)/apr/eco/log/lsf.log \
	  --result $(RUN_ROOT)/apr/eco/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/apr/eco/output/$(TOP).eco.enc.dat \
	  --expect $(RUN_ROOT)/apr/eco/output/$(TOP).eco.v \
	  --expect $(RUN_ROOT)/apr/eco/output/$(TOP).eco.def \
	  --expect $(RUN_ROOT)/apr/eco/output/$(TOP).eco.gds \
	  --expect $(RUN_ROOT)/apr/eco/output/verdict.pass -- \
	  $(call submit-job,LSF_APR_ARGS,$(RUN_ROOT)/apr/eco/log/tool.log) \
	  $(INNOVUS) -64 -nowin -init $(FLOW_ROOT)/tcl/apr/main.tcl

apr-eco: $(APR_ECO_STAMP)

$(REEXTRACT_STAMP): $(APR_ECO_STAMP)
	@mkdir -p $(RUN_ROOT)/extract/eco/work $(RUN_ROOT)/extract/eco/log $(RUN_ROOT)/extract/eco/reports $(RUN_ROOT)/extract/eco/output
	EXTRACT_TAG=eco $(TCLSH) $(FLOW_ROOT)/tcl/extract/generate.tcl
	EXTRACT_TAG=eco $(RUN_STAGE) --stage reextract \
	  --cwd $(RUN_ROOT)/extract/eco/work \
	  --log $(RUN_ROOT)/extract/eco/log/lsf.log \
	  --result $(RUN_ROOT)/extract/eco/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/extract/eco/output/verdict.pass -- \
	  $(call submit-job,LSF_EXTRACT_ARGS,$(RUN_ROOT)/extract/eco/log/tool.log) \
	  $(FLOW_PYTHON) $(FLOW_ROOT)/scripts/run_checked.py \
	  --kind spef --root $(RUN_ROOT)/extract/eco/output \
	  --top $(TOP) \
	  --verdict $(RUN_ROOT)/extract/eco/output/verdict.pass -- \
	  $(STARRC) -64 $(RUN_ROOT)/extract/eco/work/$(TOP).star

reextract: $(REEXTRACT_STAMP)

$(RESTA_STAMP): $(REEXTRACT_STAMP)
	@mkdir -p $(RUN_ROOT)/sta/eco/work $(RUN_ROOT)/sta/eco/log $(RUN_ROOT)/sta/eco/reports $(RUN_ROOT)/sta/eco/output
	STA_TAG=eco $(RUN_STAGE) --stage resta \
	  --cwd $(RUN_ROOT)/sta/eco/work --log $(RUN_ROOT)/sta/eco/log/lsf.log \
	  --result $(RUN_ROOT)/sta/eco/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/sta/eco/output/verdict.pass -- \
	  $(call submit-job,LSF_STA_ARGS,$(RUN_ROOT)/sta/eco/log/tool.log) \
	  $(FLOW_PYTHON) $(FLOW_ROOT)/scripts/run_pt_scenarios.py \
	  --pt-command "$(PT_SHELL)" --tcl-command "$(TCLSH)" \
	  --scenario-script $(FLOW_ROOT)/tcl/common/list_scenarios.tcl \
	  --main $(FLOW_ROOT)/tcl/sta/main.tcl --tag eco

resta: $(RESTA_STAMP)

$(PV_MERGE_STAMP): $(RESTA_STAMP)
	@mkdir -p $(RUN_ROOT)/pv/merge/work $(RUN_ROOT)/pv/merge/log $(RUN_ROOT)/pv/merge/reports $(RUN_ROOT)/pv/merge/output
	PV_MODE=merge $(TCLSH) $(FLOW_ROOT)/tcl/pv/generate.tcl
	$(RUN_STAGE) --stage pv-merge --cwd $(RUN_ROOT)/pv/merge/work \
	  --log $(RUN_ROOT)/pv/merge/log/lsf.log \
	  --result $(RUN_ROOT)/pv/merge/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/pv/merge/output/$(TOP).merged.gds \
	  --expect $(RUN_ROOT)/pv/merge/output/verdict.pass -- \
	  $(call submit-job,LSF_PV_ARGS,$(RUN_ROOT)/pv/merge/log/tool.log) \
	  $(CALIBREDRV) -64 $(RUN_ROOT)/pv/merge/work/merge.tcl

pv-merge: $(PV_MERGE_STAMP)

$(PV_DRC_STAMP): $(PV_MERGE_STAMP)
	@mkdir -p $(RUN_ROOT)/pv/drc/work $(RUN_ROOT)/pv/drc/log $(RUN_ROOT)/pv/drc/reports $(RUN_ROOT)/pv/drc/output
	PV_MODE=drc $(TCLSH) $(FLOW_ROOT)/tcl/pv/generate.tcl
	$(RUN_STAGE) --stage pv-drc --cwd $(RUN_ROOT)/pv/drc/work \
	  --log $(RUN_ROOT)/pv/drc/log/lsf.log \
	  --result $(RUN_ROOT)/pv/drc/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/pv/drc/output/verdict.pass -- \
	  $(call submit-job,LSF_PV_ARGS,$(RUN_ROOT)/pv/drc/log/tool.log) \
	  $(FLOW_PYTHON) $(FLOW_ROOT)/scripts/run_checked.py \
	  --kind calibre-drc --root $(RUN_ROOT)/pv/drc/reports \
	  --limit $(MAX_DRC_RESULTS) \
	  --verdict $(RUN_ROOT)/pv/drc/output/verdict.pass -- \
	  $(CALIBRE) -64 -drc -hier $(RUN_ROOT)/pv/drc/work/drc.runset

pv-drc: $(PV_DRC_STAMP)

$(PV_ANT_STAMP): $(PV_DRC_STAMP)
	@mkdir -p $(RUN_ROOT)/pv/antenna/work $(RUN_ROOT)/pv/antenna/log $(RUN_ROOT)/pv/antenna/reports $(RUN_ROOT)/pv/antenna/output
	PV_MODE=antenna $(TCLSH) $(FLOW_ROOT)/tcl/pv/generate.tcl
	$(RUN_STAGE) --stage pv-antenna --cwd $(RUN_ROOT)/pv/antenna/work \
	  --log $(RUN_ROOT)/pv/antenna/log/lsf.log \
	  --result $(RUN_ROOT)/pv/antenna/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/pv/antenna/output/verdict.pass -- \
	  $(call submit-job,LSF_PV_ARGS,$(RUN_ROOT)/pv/antenna/log/tool.log) \
	  $(FLOW_PYTHON) $(FLOW_ROOT)/scripts/run_checked.py \
	  --kind calibre-antenna --root $(RUN_ROOT)/pv/antenna/reports \
	  --limit $(MAX_ANTENNA_RESULTS) \
	  --verdict $(RUN_ROOT)/pv/antenna/output/verdict.pass -- \
	  $(CALIBRE) -64 -drc -hier $(RUN_ROOT)/pv/antenna/work/antenna.runset

pv-antenna: $(PV_ANT_STAMP)

$(PV_LVS_STAMP): $(PV_ANT_STAMP)
	@mkdir -p $(RUN_ROOT)/pv/lvs/work $(RUN_ROOT)/pv/lvs/log $(RUN_ROOT)/pv/lvs/reports $(RUN_ROOT)/pv/lvs/output
	PV_MODE=lvs $(TCLSH) $(FLOW_ROOT)/tcl/pv/generate.tcl
	$(RUN_STAGE) --stage pv-lvs --cwd $(RUN_ROOT)/pv/lvs/work \
	  --log $(RUN_ROOT)/pv/lvs/log/lsf.log \
	  --result $(RUN_ROOT)/pv/lvs/result.json --stamp $@ \
	  --expect $(RUN_ROOT)/pv/lvs/output/verdict.pass -- \
	  $(call submit-job,LSF_PV_ARGS,$(RUN_ROOT)/pv/lvs/log/tool.log) \
	  $(TCLSH) $(RUN_ROOT)/pv/lvs/work/lvs_driver.tcl

pv-lvs: $(PV_LVS_STAMP)

signoff: $(PV_LVS_STAMP)
	@printf 'commercial signoff passed: %s\n' '$(RUN_ROOT)'

clean-stage:
	@test -n '$(STAGE)' || { echo 'set STAGE=<stage>' >&2; exit 2; }
	$(FLOW_PYTHON) $(FLOW_ROOT)/scripts/clean_stage.py \
	  --build-root $(BUILD_ROOT) --run-root $(RUN_ROOT) --from-stage $(STAGE)

force-%:
	$(MAKE) clean-stage STAGE=$* LOCAL_CONFIG=$(LOCAL_CONFIG) RUN_ID=$(RUN_ID)
	$(MAKE) $* LOCAL_CONFIG=$(LOCAL_CONFIG) RUN_ID=$(RUN_ID)