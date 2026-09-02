// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RETROSOC_SOC_CLOCK_CONFIG_SVH
`define RETROSOC_SOC_CLOCK_CONFIG_SVH

// verilog_format: off -- preserve reviewed clock-contract macro columns
`ifndef SOC_EXT_CLK_HZ
`define SOC_EXT_CLK_HZ                     72000000
`endif

`ifndef SOC_CLINT_TIMEBASE_HZ
`define SOC_CLINT_TIMEBASE_HZ               1000000
`endif

`ifndef SOC_AUD_CLK_HZ
`define SOC_AUD_CLK_HZ                     18432000
`endif

`define RETROSOC_CLOCK__REF24_HZ           24000000
`define RETROSOC_CLOCK__EXT72_HZ           72000000
`define RETROSOC_CLOCK__HP_PSTATE0_HZ      72000000
`define RETROSOC_CLOCK__HP_PSTATE1_HZ      96000000
`define RETROSOC_CLOCK__HP_PSTATE2_HZ     120000000
`define RETROSOC_CLOCK__HP_PSTATE3_HZ     144000000
`define RETROSOC_CLOCK__HP_PSTATE4_HZ     168000000
`define RETROSOC_CLOCK__HP_PSTATE5_HZ     192000000
`define RETROSOC_CLOCK__HP_PSTATE6_HZ     216000000
`define RETROSOC_CLOCK__HP_PSTATE7_HZ     240000000
`define RETROSOC_CLOCK__LP_MAX_HZ          72000000
`define RETROSOC_CLOCK__PCLK_MAX_HZ        48000000
`define RETROSOC_CLOCK__LP_DIV_MASK        3'b111
`define RETROSOC_CLOCK__PCLK_DIV_MASK      5'b11111
// verilog_format: on

`endif
