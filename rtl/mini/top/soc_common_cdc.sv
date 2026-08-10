// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
//
// These managed Common CDC sources declare multiple modules, so Verilator's
// filename rule cannot hold for every declaration. Keep that narrow tool
// waiver at the SoC integration boundary without modifying the dependency.

/* verilator lint_off DECLFILENAME */
`include "cdc_fifo.sv"
`include "async_reqack.sv"
/* verilator lint_on DECLFILENAME */
