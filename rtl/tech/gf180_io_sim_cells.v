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

// The upstream GF180 IO Verilog models use rnmos primitives unsupported by the
// active simulator. These pin-compatible functional models are simulation-only;
// synthesis preserves the corresponding GF180 PDK cell instances.
module gf180mcu_fd_io__in_c (
    PU,
    PD,
    PAD,
    Y,
    DVDD,
    DVSS,
    VDD,
    VSS
);
  input PU;
  input PD;
  inout PAD;
  output Y;
  input DVDD;
  input DVSS;
  input VDD;
  input VSS;

  assign PAD = (!PU && PD) ? 1'b0 : ((PU && !PD) ? 1'b1 : 1'bz);
  assign Y   = PAD;
endmodule

module gf180mcu_fd_io__bi_t (
    CS,
    SL,
    IE,
    OE,
    PU,
    PD,
    A,
    PDRV0,
    PDRV1,
    PAD,
    Y,
    DVDD,
    DVSS,
    VDD,
    VSS
);
  input CS;
  input SL;
  input IE;
  input OE;
  input PU;
  input PD;
  input A;
  input PDRV0;
  input PDRV1;
  inout PAD;
  output Y;
  input DVDD;
  input DVSS;
  input VDD;
  input VSS;

  assign PAD = OE ? A : ((!PU && PD) ? 1'b0 : ((PU && !PD) ? 1'b1 : 1'bz));
  assign Y   = IE ? PAD : 1'b0;
endmodule
