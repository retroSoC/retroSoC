// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
//
// These managed Common CDC sources declare multiple modules, so Verilator's
// filename rule cannot hold for every declaration. Keep that narrow tool
// waiver at the SoC integration boundary without modifying the dependency.

/* verilator lint_off DECLFILENAME */
/* verilator lint_off SYNCASYNCNET */
`include "cdc_fifo.sv"
`include "async_reqack.sv"
`include "cdc_warm_flush.sv"
`include "cdc_advanced.sv"
/* verilator lint_on SYNCASYNCNET */
/* verilator lint_on DECLFILENAME */
