# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

# Tiny/ICS55 local configuration template. Copy this file to
# ../local/ics55-tiny.mk and replace every REQUIRED value there. The local
# copy is ignored by Git. Product and technology policy defaults come from
# ../config/products/tiny.mk and ../config/technology/ics55.mk.
#
# Tiny boots SAFE24: the PLL_TOP macro is instantiated in the netlist but
# parked off (EN=0) and is not a clock source. Its DB/LEF/GDS/CDL views are
# still required below because the macro must link, place, and verify.

RTL_ARCHIVE := REQUIRED
BUILD_ROOT  := $(ROOT_PATH)/build

FLOW_PYTHON      := python
TCLSH            := tclsh
LSF_COMMAND      := bsub
LSF_MODE         := batch
LSF_COMMON_ARGS  :=
LSF_SYN_ARGS     := REQUIRED
LSF_FM_ARGS      := REQUIRED
LSF_APR_ARGS     := REQUIRED
LSF_EXTRACT_ARGS := REQUIRED
LSF_STA_ARGS     := REQUIRED
LSF_ECO_ARGS     := REQUIRED
LSF_PV_ARGS      := REQUIRED

DC_SHELL   := dc_shell
FM_SHELL   := fm_shell
INNOVUS    := innovus
STARRC     := StarXtract
PT_SHELL   := pt_shell
CALIBRE    := calibre
CALIBREDRV := calibredrv
V2LVS      := v2lvs

# Synopsys DB views. Every list must be explicit; wildcards are rejected.
STD_DB_MAX := REQUIRED
STD_DB_WCL := REQUIRED
STD_DB_TYP := REQUIRED
STD_DB_MIN := REQUIRED
STD_DB_ML  := REQUIRED
# DC target subset: H7CR (SVT) and H7CL (LVT) TYP DBs only.
SYN_STD_DB_TYP := REQUIRED
IO_DB_MAX      := REQUIRED
IO_DB_WCL      := REQUIRED
IO_DB_TYP      := REQUIRED
IO_DB_MIN      := REQUIRED
IO_DB_ML       := REQUIRED
SRAM_DB_MAX    := REQUIRED
SRAM_DB_WCL    := REQUIRED
SRAM_DB_TYP    := REQUIRED
SRAM_DB_MIN    := REQUIRED
SRAM_DB_ML     := REQUIRED
PLL_DB         := REQUIRED

# Liberty views consumed by Innovus MMMC.
STD_LIB_MAX  := REQUIRED
STD_LIB_WCL  := REQUIRED
STD_LIB_TYP  := REQUIRED
STD_LIB_MIN  := REQUIRED
STD_LIB_ML   := REQUIRED
IO_LIB_MAX   := REQUIRED
IO_LIB_WCL   := REQUIRED
IO_LIB_TYP   := REQUIRED
IO_LIB_MIN   := REQUIRED
IO_LIB_ML    := REQUIRED
SRAM_LIB_MAX := REQUIRED
SRAM_LIB_WCL := REQUIRED
SRAM_LIB_TYP := REQUIRED
SRAM_LIB_MIN := REQUIRED
SRAM_LIB_ML  := REQUIRED
PLL_LIB      := REQUIRED

# Exact internal name from the selected H7CR TYP DB.
SYN_OPERATING_CONDITION_LIBRARY := REQUIRED
SYN_OPERATING_CONDITION         := REQUIRED

# Innovus physical inputs.
TECH_LEF          := REQUIRED
STD_LEFS          := REQUIRED
IO_LEFS           := REQUIRED
MACRO_LEFS        := REQUIRED
CAP_TABLE_CWORST  := REQUIRED
CAP_TABLE_RCWORST := REQUIRED
CAP_TABLE_CBEST   := REQUIRED
CAP_TABLE_RCBEST  := REQUIRED
CAP_TABLE_TYP     := REQUIRED
STREAM_MAP        := REQUIRED

# StarRC technology inputs.
NXTGRD_CWORST  := REQUIRED
NXTGRD_RCWORST := REQUIRED
NXTGRD_CBEST   := REQUIRED
NXTGRD_RCBEST  := REQUIRED
NXTGRD_TYP     := REQUIRED
STARRC_MAP     := REQUIRED

# Calibre and merge inputs.
STD_GDS          := REQUIRED
IO_GDS           := REQUIRED
MACRO_GDS        := REQUIRED
OTHER_GDS        :=
STD_CDL          := REQUIRED
IO_CDL           := REQUIRED
MACRO_CDL        := REQUIRED
CALIBRE_DRC_DECK := REQUIRED
CALIBRE_ANT_DECK := REQUIRED
CALIBRE_LVS_DECK := REQUIRED
STARRC_CORES     := 8

# PDK cell/site/layer names belong in this ignored local configuration.
APR_SITE                 := REQUIRED
APR_CORE_FILLERS         := REQUIRED
APR_IO_FILLERS           := REQUIRED
APR_SIGNAL_PAD_CELLS     := REQUIRED
APR_IO_CORNER_CELL       := REQUIRED
APR_IO_POWER_CELLS       := REQUIRED
APR_IO_OFFSET            := REQUIRED
APR_IO_PITCH             := REQUIRED
APR_ENDCAP_CELLS         := REQUIRED
APR_TIE_HIGH_CELL        := REQUIRED
APR_TIE_LOW_CELL         := REQUIRED
APR_CTS_BUFFER_CELLS     := REQUIRED
APR_CTS_INVERTER_CELLS   := REQUIRED
APR_CLOCK_ROUTING_LAYERS := REQUIRED
APR_SIGNAL_MIN_LAYER     := REQUIRED
APR_SIGNAL_MAX_LAYER     := REQUIRED
APR_POWER_NET            := REQUIRED
APR_GROUND_NET           := REQUIRED
APR_POWER_PINS           := REQUIRED
APR_GROUND_PINS          := REQUIRED
APR_RING_LAYERS          := REQUIRED
APR_STRIPE_LAYER         := REQUIRED
APR_RING_WIDTH           := REQUIRED
APR_RING_SPACING         := REQUIRED
APR_RING_OFFSET          := REQUIRED
APR_STRIPE_WIDTH         := REQUIRED
APR_STRIPE_SPACING       := REQUIRED
APR_STRIPE_PITCH         := REQUIRED
SYN_DONT_USE             := REQUIRED
ECO_SETUP_BUFFERS        := REQUIRED
ECO_HOLD_BUFFERS         := REQUIRED
ECO_SETUP_MARGIN_NS      := 0.0
ECO_HOLD_MARGIN_NS       := 0.0
ECO_MAX_PROCESSES        := 8
ECO_PHYSICAL_MODE        := open_site

# Tiny has no tracked die defaults yet; size the pad ring and core from the
# product floorplan review before implementation.
DIE_WIDTH          := REQUIRED
DIE_HEIGHT         := REQUIRED
CORE_MARGIN_LEFT   := REQUIRED
CORE_MARGIN_BOTTOM := REQUIRED
CORE_MARGIN_RIGHT  := REQUIRED
CORE_MARGIN_TOP    := REQUIRED
CORE_UTILIZATION   := REQUIRED
# CLOCK_SETUP_UNCERTAINTY_NS := 0.20
# CLOCK_HOLD_UNCERTAINTY_NS  := 0.10
# CLOCK_TRANSITION_NS        := 0.10
# MAX_TRANSITION_NS          := 0.50
# MAX_FANOUT                 := 32

# Board/device timing is local qualification data. Set YES only when every
# interface budget below is taken from reviewed board and component timing.
IO_TIMING_QUALIFIED := NO

JTAG_INPUT_DELAY_MAX_NS  := REQUIRED
JTAG_INPUT_DELAY_MIN_NS  := REQUIRED
JTAG_INPUT_TRANSITION_NS := REQUIRED
JTAG_OUTPUT_DELAY_MAX_NS := REQUIRED
JTAG_OUTPUT_DELAY_MIN_NS := REQUIRED
JTAG_OUTPUT_LOAD_PF      := REQUIRED

XPI_CLOCK_PERIOD_NS     := REQUIRED
XPI_INPUT_DELAY_MAX_NS  := REQUIRED
XPI_INPUT_DELAY_MIN_NS  := REQUIRED
XPI_INPUT_TRANSITION_NS := REQUIRED
XPI_OUTPUT_DELAY_MAX_NS := REQUIRED
XPI_OUTPUT_DELAY_MIN_NS := REQUIRED
XPI_OUTPUT_LOAD_PF      := REQUIRED

ASYNC_CLOCK_PERIOD_NS     := REQUIRED
ASYNC_INPUT_DELAY_MAX_NS  := REQUIRED
ASYNC_INPUT_DELAY_MIN_NS  := REQUIRED
ASYNC_INPUT_TRANSITION_NS := REQUIRED
ASYNC_OUTPUT_DELAY_MAX_NS := REQUIRED
ASYNC_OUTPUT_DELAY_MIN_NS := REQUIRED
ASYNC_OUTPUT_LOAD_PF      := REQUIRED

# Optional hooks.
APR_FLOORPLAN_HOOK    :=
APR_POWER_HOOK        :=
APR_PLACE_HOOK        :=
APR_CTS_HOOK          :=
APR_ROUTE_HOOK        :=
TIMING_IO_MODE_HOOK   :=
TIMING_EXCEPTION_HOOK :=

# Optional flow behavior slots (technology defaults live in
# ../config/technology/ics55.mk; see README.md for the full reference).
# STA_SAIF_FILE                 :=   # SAIF for per-scenario report_power
# STA_SDF_SCENARIO              := func_TYP_TYP_25
# SYN_CLOCK_GATING_EXCLUDE_PATTERNS := # clock-gating exclusion name globs
# APR_IO_ORDER_FILE             :=   # reviewed pad order; default round-robin
# APR_MACRO_LOC_FILE            :=   # fixed macro coordinates (place_macro)
# APR_MACRO_HALO_UM             := 5
# APR_NETLIST_EXCLUDE_CELLS     :=   # e.g. seal-ring cells excluded from netlist
# APR_POWER_PIN_MAP             :=   # "PLL_AVDD:AVDD" (PLL parked: tie to VDD)
# APR_GROUND_PIN_MAP            :=   # "PLL_AVSS:AVSS"
# APR_EARLY_GLOBAL_MIN_LAYER    :=
# APR_EARLY_GLOBAL_MAX_LAYER    :=
# ECO_ENABLE_VT_SWAP            := NO
# ECO_VT_PATTERN_PRIORITY       :=   # required when ECO_ENABLE_VT_SWAP=YES
# ECO_ENABLE_SIZE_DOWN          := NO
# ECO_ENABLE_REMOVE_BUFFER      := NO
# ECO_PBA_MODE                  := none
# MACRO_LVS_CELLS               :=   # e.g. PLL_TOP for macro-level LVS/ERC
# CALIBRE_LVS_ARGS              := -turbo -hyper

# Required strict thresholds.
MAX_SETUP_VIOLATIONS := 0
MAX_HOLD_VIOLATIONS  := 0
MAX_DRV_VIOLATIONS   := 0
MAX_DRC_RESULTS      := 0
MAX_ANTENNA_RESULTS  := 0