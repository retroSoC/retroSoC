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
// The managed common FIFO source also declares stream_fifo, so Verilator's
// filename rule cannot hold for both modules. Keep that narrow tool waiver at
// the SoC integration boundary without modifying the managed dependency.

/* verilator lint_off DECLFILENAME */
`include "fifo.sv"
/* verilator lint_on DECLFILENAME */
