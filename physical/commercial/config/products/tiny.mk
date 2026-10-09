# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

# retroSoC Tiny product policy for the commercial flow. Non-sensitive design
# intent only; site values live in the ignored local configuration.

SOC := TINY
TOP := retrosoc_tiny_asic

# Canonical clock domains, mirrored by tcl/common/products/tiny.tcl and
# validated against rtl/tiny/integration/clock_reset_domains.json when the
# commercial timing contract is generated. Tiny boots SAFE24: the PLL_TOP
# macro is present in the netlist but parked off and is not a clock source.
COMMERCIAL_CLOCK_DOMAINS := system jtag

# Qualified-I/O interface groups and the budget variables each group requires.
COMMERCIAL_IO_INTERFACES       := JTAG XPI ASYNC
COMMERCIAL_IO_BUDGET_VARIABLES := \
	JTAG_INPUT_DELAY_MAX_NS JTAG_INPUT_DELAY_MIN_NS \
	JTAG_INPUT_TRANSITION_NS JTAG_OUTPUT_DELAY_MAX_NS \
	JTAG_OUTPUT_DELAY_MIN_NS JTAG_OUTPUT_LOAD_PF \
	XPI_CLOCK_PERIOD_NS XPI_INPUT_DELAY_MAX_NS \
	XPI_INPUT_DELAY_MIN_NS XPI_INPUT_TRANSITION_NS \
	XPI_OUTPUT_DELAY_MAX_NS XPI_OUTPUT_DELAY_MIN_NS \
	XPI_OUTPUT_LOAD_PF \
	ASYNC_CLOCK_PERIOD_NS ASYNC_INPUT_DELAY_MAX_NS \
	ASYNC_INPUT_DELAY_MIN_NS ASYNC_INPUT_TRANSITION_NS \
	ASYNC_OUTPUT_DELAY_MAX_NS ASYNC_OUTPUT_DELAY_MIN_NS \
	ASYNC_OUTPUT_LOAD_PF

# Tiny has no bidirectional pad-mode selection requirement.
PRODUCT_REQUIRES_IO_MODE_HOOK := NO

# The Tiny PLL_TOP macro is parked (EN=0) and has no characterized timing
# arcs; doctor skips the qualified PLL-mode checks for this product. See
# docs/ip/tiny-soc.md (TINY-055) for the qualification boundary.
PRODUCT_PLL_MODE := parked

CLOCK_SETUP_UNCERTAINTY_NS ?= 0.20
CLOCK_HOLD_UNCERTAINTY_NS  ?= 0.10
CLOCK_TRANSITION_NS        ?= 0.10
MAX_TRANSITION_NS          ?= 0.50
MAX_FANOUT                 ?= 32