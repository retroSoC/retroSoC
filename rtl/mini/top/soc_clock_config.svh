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

`ifndef SOC_EXT_CLK_HZ
`define SOC_EXT_CLK_HZ 72000000
`endif

`ifndef SOC_CLINT_TIMEBASE_HZ
`define SOC_CLINT_TIMEBASE_HZ 1000000
`endif

`ifndef SOC_AUD_CLK_HZ
`define SOC_AUD_CLK_HZ 18432000
`endif

`endif
