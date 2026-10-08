# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

# retroSoC Mini product policy for the commercial flow. Non-sensitive design
# intent only; site values live in the ignored local configuration.

SOC := MINI
TOP := retrosoc_asic

# Canonical clock domains, mirrored by tcl/common/products/mini.tcl and
# validated against rtl/mini/integration/clock_reset_domains.json when the
# commercial timing contract is generated.
COMMERCIAL_CLOCK_DOMAINS := aon lp hp pclk memory audio jtag dvp usb2_ulpi

# Qualified-I/O interface groups and the budget variables each group requires.
COMMERCIAL_IO_INTERFACES := JTAG DVP ULPI SDRAM SDIO XPI ASYNC
COMMERCIAL_IO_BUDGET_VARIABLES := \
	JTAG_INPUT_DELAY_MAX_NS JTAG_INPUT_DELAY_MIN_NS \
	JTAG_INPUT_TRANSITION_NS JTAG_OUTPUT_DELAY_MAX_NS \
	JTAG_OUTPUT_DELAY_MIN_NS JTAG_OUTPUT_LOAD_PF \
	DVP_INPUT_DELAY_MAX_NS DVP_INPUT_DELAY_MIN_NS \
	DVP_INPUT_TRANSITION_NS \
	ULPI_INPUT_DELAY_MAX_NS ULPI_INPUT_DELAY_MIN_NS \
	ULPI_INPUT_TRANSITION_NS ULPI_OUTPUT_DELAY_MAX_NS \
	ULPI_OUTPUT_DELAY_MIN_NS ULPI_OUTPUT_LOAD_PF \
	SDRAM_CLOCK_PERIOD_NS SDRAM_INPUT_DELAY_MAX_NS \
	SDRAM_INPUT_DELAY_MIN_NS SDRAM_INPUT_TRANSITION_NS \
	SDRAM_OUTPUT_DELAY_MAX_NS SDRAM_OUTPUT_DELAY_MIN_NS \
	SDRAM_OUTPUT_LOAD_PF \
	SDIO_CLOCK_PERIOD_NS SDIO_INPUT_DELAY_MAX_NS \
	SDIO_INPUT_DELAY_MIN_NS SDIO_INPUT_TRANSITION_NS \
	SDIO_OUTPUT_DELAY_MAX_NS SDIO_OUTPUT_DELAY_MIN_NS \
	SDIO_OUTPUT_LOAD_PF \
	XPI_CLOCK_PERIOD_NS XPI_INPUT_DELAY_MAX_NS \
	XPI_INPUT_DELAY_MIN_NS XPI_INPUT_TRANSITION_NS \
	XPI_OUTPUT_DELAY_MAX_NS XPI_OUTPUT_DELAY_MIN_NS \
	XPI_OUTPUT_LOAD_PF \
	ASYNC_CLOCK_PERIOD_NS ASYNC_INPUT_DELAY_MAX_NS \
	ASYNC_INPUT_DELAY_MIN_NS ASYNC_INPUT_TRANSITION_NS \
	ASYNC_OUTPUT_DELAY_MAX_NS ASYNC_OUTPUT_DELAY_MIN_NS \
	ASYNC_OUTPUT_LOAD_PF

# Qualified Mini I/O requires a reviewed pad-mode hook that selects the
# GPIO10-20 DVP input mode and cuts invalid bidirectional-pad feedback arcs.
PRODUCT_REQUIRES_IO_MODE_HOOK := YES

# The Mini RCU clocks the system from PLL_TOP in the qualified production
# mode; doctor enforces the reviewed SEL/N/OD values below.
PRODUCT_PLL_MODE := qualified
ICS55_PLL_SUPPORTED_SEL ?= 0
ICS55_PLL_N ?= 2
ICS55_PLL_OD ?= 2

# Non-sensitive floorplan/timing defaults; the local configuration may
# override them.
DIE_WIDTH ?= 2400
DIE_HEIGHT ?= 2400
CORE_MARGIN_LEFT ?= 258
CORE_MARGIN_BOTTOM ?= 258
CORE_MARGIN_RIGHT ?= 258
CORE_MARGIN_TOP ?= 258
CORE_UTILIZATION ?= 0.60
PLL_OUTPUT_PERIOD_NS ?= 13.888888889
CLOCK_SETUP_UNCERTAINTY_NS ?= 0.20
CLOCK_HOLD_UNCERTAINTY_NS ?= 0.10
CLOCK_TRANSITION_NS ?= 0.10
MAX_TRANSITION_NS ?= 0.50
MAX_FANOUT ?= 32
