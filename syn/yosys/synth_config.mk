# Copyright (c) 2022 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>

# target clock-period in pico-seconds
export YOSYS_TARGET_PERIOD_PS := 10000

# modules Yosys will treat as blackboxes
export YOSYS_BLACKBOX_MODULES := "*tc_sram_blackbox*"

# flatten hierarchy (except for below selections)
export YOSYS_FLATTEN_HIER := 1

# a list of yosys selection strings, all selected instances will be 
# kept as a seperate hierarchical element, all others will be flattened
# https://yosyshq.readthedocs.io/projects/yosys/en/latest/cmd/select.html
export YOSYS_KEEP_HIER_INST :=  "t:tc_clk*$$*" \
								"t:tc_sram*$$*" \
								"t:core_*$$*" \
								"t:bus*$$*" \
								"t:ip_natv_wrapper*$$*" \
								"t:ip_apb_wrapper*$$*" \
								"t:apb_spi_master*$$*" \
                                "t:spi_flash*$$*" \
								"t:mem2apb*$$*" \
								"t:apb4_archinfo*$$*" \
								"t:apb4_rng*$$*" \
								"t:apb4_uart*$$*" \
								"t:apb4_pwm*$$*" \
								"t:apb4_ps2*$$*" \
								"t:apb4_i2c*$$*" \
								"t:psram_top*$$*" \

# the paths (full names) of all instances matching these strings is reported
# for floorplaning or writing constraints
export YOSYS_REPORT_INSTS :=	"t:*core_wrapper*"
