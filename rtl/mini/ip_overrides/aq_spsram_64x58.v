// retroSoC controlled override of the vendored OpenC906 aq_spsram_64x58.v.
//
// Source: openc906 dependency (dependencies.lock.json "openc906"),
//   C906_RTL_FACTORY/gen_rtl/lsu/rtl/aq_spsram_64x58.v
//   revision b0c06eb1f8b3bae663bd8b87eac89ff48e68a57f
// License: Apache-2.0 (T-Head Semiconductor)
//
// retroSoC change (OpenC906 integration manual chapter 3 SRAM swap): with
// PDK_IHP130+HAVE_SRAM_MACRO and without PDK_BEHAV, the 64x58 DCache tag RAM
// is built from one RM_IHPSG13_1P_64x64_c2_bm_bist macro; only the low 58
// bits are used and the upper mask bits are tied off so they are never
// written. Every other configuration keeps the upstream behavioral
// aq_f_spsram_64x58 instance byte-identical. Keep in sync when the lock
// revision changes.

/*Copyright 2020-2021 T-Head Semiconductor Co., Ltd.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// &ModuleBeg; @22
module aq_spsram_64x58(
  A,
  CEN,
  CLK,
  D,
  GWEN,
  Q,
  WEN
);

// &Ports; @23
input   [5 :0]  A;
input           CEN;
input           CLK;
input   [57:0]  D;
input           GWEN;
input   [57:0]  WEN;
output  [57:0]  Q;

// &Regs; @24

// &Wires; @25
wire    [5 :0]  A;
wire            CEN;
wire            CLK;
wire    [57:0]  D;
wire            GWEN;
wire    [57:0]  Q;
wire    [57:0]  WEN;


//**********************************************************
//                  Parameter Definition
//**********************************************************
parameter ADDR_WIDTH = 6;
parameter DATA_WIDTH = 58;
parameter WE_WIDTH   = 58;

// &Force("bus","Q",DATA_WIDTH-1,0); @34
// &Force("bus","WEN",WE_WIDTH-1,0); @35
// &Force("bus","A",ADDR_WIDTH-1,0); @36
// &Force("bus","D",DATA_WIDTH-1,0); @37

`ifdef PDK_IHP130
`ifdef HAVE_SRAM_MACRO
`ifndef PDK_BEHAV
`define _AQ_SPSRAM_64X58_IHP130_
`endif
`endif
`endif

`ifdef _AQ_SPSRAM_64X58_IHP130_
  //********************************************************
  //*                IHP130 SRAM macro                     *
  //********************************************************
// One 64x64 macro supplies the 64x58 DCache tag RAM; the upper 6 bits are
// masked off so they are never written.
wire   [63:0]  s_dout;
wire   [5:0]   s_dout_unused;

assign Q = s_dout[57:0];
assign s_dout_unused = s_dout[63:58];

RM_IHPSG13_1P_64x64_c2_bm_bist  u_mem (
  .A_CLK      (CLK          ),
  .A_ADDR     (A            ),
  .A_BM       ({6'b0, ~WEN} ),
  .A_MEN      (~CEN         ),
  .A_WEN      (~GWEN        ),
  .A_REN      (GWEN         ),
  .A_DIN      ({6'b0, D}    ),
  .A_DOUT     (s_dout       ),
  .A_DLY      (1'b1         ),
  .A_BIST_CLK (1'b0         ),
  .A_BIST_EN  (1'b0         ),
  .A_BIST_MEN (1'b0         ),
  .A_BIST_WEN (1'b0         ),
  .A_BIST_REN (1'b0         ),
  .A_BIST_ADDR(6'b0         ),
  .A_BIST_DIN (64'b0        ),
  .A_BIST_BM  (64'b0        )
);
`else
//  //********************************************************
//  //*                        FPGA memory                   *
//  //********************************************************
//   &Instance("aq_f_spsram_64x58"); @43
aq_f_spsram_64x58  x_aq_f_spsram_64x58 (
  .A    (A   ),
  .CEN  (CEN ),
  .CLK  (CLK ),
  .D    (D   ),
  .GWEN (GWEN),
  .Q    (Q   ),
  .WEN  (WEN )
);
`endif

`ifdef _AQ_SPSRAM_64X58_IHP130_
`undef _AQ_SPSRAM_64X58_IHP130_
`endif

//   &Instance("aq_umc_spsram_64x58"); @49
//   &Instance("aq_tsmc_spsram_64x58"); @55
// &ModuleEnd; @58
endmodule
