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

# Directories
# directory of the path to the last called Makefile (this one)
YOSYS_DIR   := $(realpath $(dir $(realpath $(lastword $(MAKEFILE_LIST)))))
YOSYS_BUILD := $(SYN_BUILD_ROOT)
YOSYS_OUT   := $(YOSYS_BUILD)/out
YOSYS_TMP   := $(YOSYS_BUILD)/tmp
YOSYS_RPT   := $(YOSYS_BUILD)/rpt

include $(YOSYS_DIR)/synth_config.mk

TOP_DESIGN    ?= retrosoc_asic
RTL_NAME      ?= retrosoc_asic
SV_FLIST      := $(GENERATED_FL_DIR)/yosys.fl

NETLIST       := $(YOSYS_OUT)/$(RTL_NAME)_yosys.v
NETLIST_DEBUG := $(YOSYS_OUT)/$(RTL_NAME)_yosys_debug.v
NETLIST_CONFIG := $(YOSYS_OUT)/$(RTL_NAME)_yosys.config
YOSYS_DEPFILE := $(YOSYS_BUILD)/yosys.d
YOSYS_SCRIPTS := $(wildcard $(YOSYS_DIR)/script/*) $(YOSYS_DIR)/synth_config.mk $(YOSYS_DIR)/yosys.mk

-include $(YOSYS_DEPFILE)

$(SV_FLIST): $(MPW_VARIANT_STAMP) $(FILELIST_STAMP)
	@python3 $(RTL_PATH)/script/comb.py $(RTL_FLIST) --output $(SV_FLIST)
	@python3 $(RTL_PATH)/script/filelist_deps.py $(RTL_FLIST) --target $(NETLIST) \
		--output $(YOSYS_DEPFILE)

gen_synth_filelist: $(SV_FLIST)

## Synthesize netlist using Yosys
synth: $(NETLIST)

$(NETLIST): $(SV_FLIST) $(YOSYS_SCRIPTS)
	@mkdir -p $(YOSYS_OUT)
	@mkdir -p $(YOSYS_TMP)
	@mkdir -p $(YOSYS_RPT)
	python3 $(ROOT_PATH)/scripts/run_flow.py --tool yosys \
		--log $(YOSYS_BUILD)/$(RTL_NAME).log --result $(YOSYS_BUILD)/result-synth.json \
		--env PDK=$(PDK) --env SOC=$(SOC) --env CORE=$(CORE) --env IP=$(IP) \
		--env SV_FLIST=$(SV_FLIST) --env TOP_DESIGN=$(TOP_DESIGN) --env CONFIG=$(NETLIST_CONFIG) \
		--env PROJ_NAME=$(RTL_NAME) --env WORK=$(YOSYS_TMP) --env BUILD=$(YOSYS_OUT) \
		--env REPORTS=$(YOSYS_RPT) --env NETLIST=$(NETLIST) -- \
		yosys -c $(YOSYS_DIR)/script/synth.tcl

$(NETLIST_DEBUG): $(NETLIST)
	@test -f $@

synth_clean:
	python3 $(ROOT_PATH)/scripts/clean.py --root $(ROOT_PATH) --path $(YOSYS_BUILD)

.PHONY: gen_synth_filelist synth_clean synth

synth: | manifest
