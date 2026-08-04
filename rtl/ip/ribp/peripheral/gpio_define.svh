// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RIBP_GPIO_DEF_SV
`define RIBP_GPIO_DEF_SV

// verilog_format: off
`define RIBP_GPIO_NUM         32
`define RIBP_GPIO_OE          8'h00 // rw
`define RIBP_GPIO_CS          8'h04 // rw
`define RIBP_GPIO_PU          8'h08 // rw
`define RIBP_GPIO_PD          8'h0C // rw
`define RIBP_GPIO_DO          8'h10 // rw
`define RIBP_GPIO_DI          8'h14 // ro
`define RIBP_GPIO_IEN         8'h18 // rw
`define RIBP_GPIO_ITYPE0      8'h1c // rw
`define RIBP_GPIO_ITYPE1      8'h20 // rw
`define RIBP_GPIO_ISTAT       8'h24 // ro
`define RIBP_GPIO_IOFCFG      8'h28 // rw
`define RIBP_GPIO_PINMUX      8'h2c // rw
`define RIBP_GPIO_USER_SEL    8'h30 // rw
`define RIBP_GPIO_USER_LOCK 8'h34 // rw1s
`define RIBP_GPIO_USER_STATUS 8'h38 // ro
// verilog_format: on
`endif
