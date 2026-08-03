// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
//
// The managed common FIFO source also declares stream_fifo, so Verilator's
// filename rule cannot hold for both modules. Keep that narrow tool waiver at
// the SoC integration boundary without modifying the managed dependency.

/* verilator lint_off DECLFILENAME */
`include "fifo.sv"
/* verilator lint_on DECLFILENAME */
