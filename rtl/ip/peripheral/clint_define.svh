// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`ifndef CLINT_DEFINE_SVH
`define CLINT_DEFINE_SVH

// verilog_format: off
`define RIBP_CLINT_MSIP             16'h0000
`define RIBP_CLINT_MTIMECMP         16'h4000
`define RIBP_CLINT_MTIME            16'hBFF8
`define RIBP_CLINT_MTIMEH           16'hBFFC

`define CLINT_MSIP_STRIDE           16'h0004
`define CLINT_MTIMECMP_STRIDE       16'h0008
// verilog_format: on

`endif
