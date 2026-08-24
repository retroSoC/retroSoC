// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef CLINT_DEFINE_SVH
`define CLINT_DEFINE_SVH

// verilog_format: off -- preserve reviewed column alignment
`define APB4_CLINT_MSIP             16'h0000
`define APB4_CLINT_MTIMECMP         16'h4000
`define APB4_CLINT_MTIME            16'hBFF8
`define APB4_CLINT_MTIMEH           16'hBFFC

`define CLINT_MSIP_STRIDE           16'h0004
`define CLINT_MTIMECMP_STRIDE       16'h0008
// verilog_format: on

`endif
