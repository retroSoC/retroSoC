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

# Directories
# directory of the path to the last called Makefile (this one)
YOSYS_DIR   := $(realpath $(dir $(realpath $(lastword $(MAKEFILE_LIST)))))
YOSYS_BUILD := $(YOSYS_DIR)/.synth_build
YOSYS_OUT   := $(YOSYS_BUILD)/out
YOSYS_TMP   := $(YOSYS_BUILD)/tmp
YOSYS_RPT   := $(YOSYS_BUILD)/rpt

include $(YOSYS_DIR)/synth_config.mk

TOP_DESIGN    ?= retrosoc_asic
RTL_NAME      ?= retrosoc_asic
SV_FLIST      := $(YOSYS_DIR)/../../rtl/$(shell echo $(SOC) | tr A-Z a-z )/filelist/yosys_syn.fl

$(info SV_FLIST: $(SV_FLIST))

NETLIST       := $(YOSYS_OUT)/$(RTL_NAME)_yosys.v
NETLIST_DEBUG := $(YOSYS_OUT)/$(RTL_NAME)_debug_yosys.v

## Synthesize netlist using Yosys
synth: $(NETLIST)

$(NETLIST) $(NETLIST_DEBUG):
	@mkdir -p $(YOSYS_OUT)
	@mkdir -p $(YOSYS_TMP)
	@mkdir -p $(YOSYS_RPT)
	PDK="$(PDK)" \
	SV_FLIST="$(SV_FLIST)" \
	TOP_DESIGN="$(TOP_DESIGN)" \
	PROJ_NAME="$(RTL_NAME)" \
	WORK="$(YOSYS_TMP)" \
	BUILD="$(YOSYS_OUT)" \
	REPORTS="$(YOSYS_RPT)" \
	NETLIST="$(NETLIST)" \
	yosys -c $(YOSYS_DIR)/script/synth.tcl \
		2>&1 | TZ=UTC-8 gawk '{ print strftime("[%Y-%m-%d %H:%M %Z]"), $$0 }' \
			 | tee "$(YOSYS_BUILD)/$(RTL_NAME).log" \
			 | gawk -f $(YOSYS_DIR)/script/filter_output.awk;

synth_clean:
	rm -rf $(YOSYS_OUT)
	rm -rf $(YOSYS_TMP)
	rm -rf $(YOSYS_RPT) 
	rm -f $(YOSYS_DIR)/$(RTL_NAME).log

.PHONY: synth_clean yosys synth $(NETLIST) $(NETLIST_DEBUG)
