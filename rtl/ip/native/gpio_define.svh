// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef NMI_GPIO_DEF_SV
`define NMI_GPIO_DEF_SV

// verilog_format: off
`define NMI_GPIO_NUM 8
`define NMI_GPIO_OE  8'h00 // rw
`define NMI_GPIO_CS  8'h04 // rw
`define NMI_GPIO_PU  8'h08 // rw
`define NMI_GPIO_PD  8'h0C // rw
`define NMI_GPIO_DO  8'h10 // rw
`define NMI_GPIO_DI  8'h14 // ro
// verilog_format: on
`endif