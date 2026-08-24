// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
// You may use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// Yosys needs the macro interfaces even though PDK simulation models are excluded
// from the synthesis file list. The technology cells remain black boxes.
`ifdef SYNTHESIS
`ifdef PDK_GF180
(* blackbox *)
module gf180mcu_fd_io__in_c (
    input  wire PU,
    input  wire PD,
    inout  wire PAD,
    output wire Y,
    input  wire DVDD,
    input  wire DVSS,
    input  wire VDD,
    input  wire VSS
);
endmodule

(* blackbox *)
module gf180mcu_fd_io__bi_t (
    input  wire CS,
    input  wire SL,
    input  wire IE,
    input  wire OE,
    input  wire PU,
    input  wire PD,
    input  wire A,
    input  wire PDRV0,
    input  wire PDRV1,
    inout  wire PAD,
    output wire Y,
    input  wire DVDD,
    input  wire DVSS,
    input  wire VDD,
    input  wire VSS
);
endmodule
`endif
`endif
