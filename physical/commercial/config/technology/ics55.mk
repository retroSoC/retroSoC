# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

# ICS55 (ICsprout 55LLULP1233) technology policy: non-sensitive naming and
# corner conventions shared by every product on this technology. Library
# paths, cell lists, and deck locations remain in the ignored local
# configuration.

# PVT corner set used across synthesis, extraction, STA, and ECO.
COMMERCIAL_PVT_CORNERS := MAX WCL TYP MIN ML

# StarRC extraction corners written by the extract stage; check_outputs.py
# requires one SPEF per entry.
COMMERCIAL_EXTRACTION_CORNERS := \
	Cworst_m40 Cworst_125 \
	RCworst_m40 RCworst_125 \
	Cbest_m40 Cbest_125 \
	RCbest_m40 RCbest_125 \
	TYP_25

# H7C standard-cell family naming policy: cell-name suffix tokens feed the
# synthesis VT utilization report, and library-name glob patterns bind the
# threshold-voltage groups in the TYP link set.
SYN_VT_SUFFIX_MAP  := HVT H7H LVT H7L SVT H7R
SYN_VT_LIBRARY_MAP := HVT *H7CH* LVT *H7CL* SVT *H7CR*

# OCV derate policy (legacy bes_data/common/signoff_table.tcl, CX55 section;
# PrimeTime-only — legacy DC synthesis applied no derate):
TIMING_DERATE_SETUP_CELL_CLOCK_EARLY := 0.95
TIMING_DERATE_SETUP_NET_CLOCK_EARLY  := 0.95
TIMING_DERATE_HOLD_CELL_CLOCK_EARLY  := 0.90
TIMING_DERATE_HOLD_NET_CLOCK_EARLY   := 0.90
TIMING_DERATE_DEFAULT_EARLY          := 0.95

# Innovus derate and per-stage setup uncertainty (legacy
# pd_data/pr/scr/CL1/set_derate_uncertainty.tcl).
APR_DERATE_CLOCK_EARLY := 0.95
APR_DERATE_CLOCK_LATE  := 1.10
APR_DERATE_DATA_LATE   := 1.10
APR_SETUP_UNCERTAINTY_PLACE_NS := 0.25
APR_SETUP_UNCERTAINTY_CTS_NS   := 0.225
APR_SETUP_UNCERTAINTY_ROUTE_NS := 0.20

# Innovus per-stage DRV limits (legacy pd_data/pr/scr/CL1/update_sdc.tcl) and
# CTS targets (legacy pd_data/pr/scr/setting/cts_setting.tcl).
APR_DESIGN_PROCESS               ?= 55
APR_MAX_FANOUT                   ?= 32
APR_MAX_TRANSITION_NS            ?= 0.08
APR_MAX_CAPACITANCE_PF           ?= 0.15
APR_CTS_NDR_WIDTH_UM             ?= 0.2
APR_CTS_NDR_SPACING_UM           ?= 0.2
APR_CTS_TARGET_SKEW_NS           ?= 0.08
APR_CTS_TARGET_MAX_TRANS_LEAF_NS ?= 0.78
APR_CTS_TARGET_MAX_TRANS_TRUNK_NS ?= 0.78
APR_CTS_TARGET_INSERTION_DELAY_NS ?= 0.05
APR_CTS_MAX_FANOUT               ?= 4

# Synthesis compile policy (legacy bes_data/syn/scr/flow_com/
# syn_common_flow.tcl).
SYN_CRITICAL_RANGE_NS ?= 0.2
SYN_COMPILE_CORES     ?= 16
