// retroSoC controlled override of the vendored OpenC906 aq_spsram_1024x16.v.
//
// Source: openc906 dependency (dependencies.lock.json "openc906"),
//   C906_RTL_FACTORY/gen_rtl/ifu/rtl/aq_spsram_1024x16.v
//   revision b0c06eb1f8b3bae663bd8b87eac89ff48e68a57f
// License: Apache-2.0 (T-Head Semiconductor)
//
// retroSoC change (OpenC906 integration manual chapter 3 SRAM swap): with
// PDK_IHP130+HAVE_SRAM_MACRO and without PDK_BEHAV, the 1024x16 BHT RAM is
// built from one RM_IHPSG13_1P_1024x32_c2_bm_bist macro; only the low 16
// bits are used and the upper mask bits are tied off so they are never
// written. With PDK_ICS55+HAVE_SRAM_MACRO and without PDK_BEHAV, the
// exact-geometry ics55_ecos_sram_1024x16_m8 macro replaces it directly
// (identical active-low polarity, no stacking or padding). Every other
// configuration keeps the upstream behavioral aq_f_spsram_1024x16 instance
// byte-identical. Keep in sync when the lock revision changes.

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
module aq_spsram_1024x16(
  A,
  CEN,
  CLK,
  D,
  GWEN,
  Q,
  WEN
);

// &Ports; @23
input   [9 :0]  A;
input           CEN;
input           CLK;
input   [15:0]  D;
input           GWEN;
input   [15:0]  WEN;
output  [15:0]  Q;

// &Regs; @24

// &Wires; @25
wire    [9 :0]  A;
wire            CEN;
wire            CLK;
wire    [15:0]  D;
wire            GWEN;
wire    [15:0]  Q;
wire    [15:0]  WEN;


//**********************************************************
//                  Parameter Definition
//**********************************************************
parameter ADDR_WIDTH = 10;
parameter DATA_WIDTH = 16;
parameter WE_WIDTH   = 16;

// &Force("bus","Q",DATA_WIDTH-1,0); @34
// &Force("bus","WEN",WE_WIDTH-1,0); @35
// &Force("bus","A",ADDR_WIDTH-1,0); @36
// &Force("bus","D",DATA_WIDTH-1,0); @37

`ifdef PDK_IHP130
`ifdef HAVE_SRAM_MACRO
`ifndef PDK_BEHAV
`define _AQ_SPSRAM_1024X16_IHP130_
`endif
`endif
`endif

`ifdef PDK_ICS55
`ifdef HAVE_SRAM_MACRO
`ifndef PDK_BEHAV
`define _AQ_SPSRAM_1024X16_ICS55_
`endif
`endif
`endif

`ifdef _AQ_SPSRAM_1024X16_IHP130_
  //********************************************************
  //*                IHP130 SRAM macro                     *
  //********************************************************
// One 1024x32 macro supplies the 1024x16 BHT RAM; the upper 16 bits are
// masked off so they are never written.
wire   [31:0]  s_dout;
wire   [15:0]  s_dout_unused;

assign Q = s_dout[15:0];
assign s_dout_unused = s_dout[31:16];

RM_IHPSG13_1P_1024x32_c2_bm_bist  u_mem (
  .A_CLK      (CLK           ),
  .A_ADDR     (A             ),
  .A_BM       ({16'b0, ~WEN} ),
  .A_MEN      (~CEN          ),
  .A_WEN      (~GWEN         ),
  .A_REN      (GWEN          ),
  .A_DIN      ({16'b0, D}    ),
  .A_DOUT     (s_dout        ),
  .A_DLY      (1'b1          ),
  .A_BIST_CLK (1'b0          ),
  .A_BIST_EN  (1'b0          ),
  .A_BIST_MEN (1'b0          ),
  .A_BIST_WEN (1'b0          ),
  .A_BIST_REN (1'b0          ),
  .A_BIST_ADDR(10'b0         ),
  .A_BIST_DIN (32'b0         ),
  .A_BIST_BM  (32'b0         )
);
`elsif _AQ_SPSRAM_1024X16_ICS55_
  //********************************************************
  //*                ICS55 SRAM macro                      *
  //********************************************************
// Exact-geometry macro; polarities match the wrapper, direct connection.
ics55_ecos_sram_1024x16_m8  u_mem (
  .A    (A   ),
  .CEB  (CEN ),
  .CLK  (CLK ),
  .D    (D   ),
  .GWEB (GWEN),
  .MARE (1'b0),
  .MAR  (4'b0),
  .WEB  (WEN ),
  .Q    (Q   )
);
`else
  //********************************************************
  //*                        FPGA memory                   *
  //********************************************************
//   &Instance("aq_f_spsram_1024x16"); @43
aq_f_spsram_1024x16  x_aq_f_spsram_1024x16 (
  .A    (A   ),
  .CEN  (CEN ),
  .CLK  (CLK ),
  .D    (D   ),
  .GWEN (GWEN),
  .Q    (Q   ),
  .WEN  (WEN )
);
`endif

`ifdef _AQ_SPSRAM_1024X16_IHP130_
`undef _AQ_SPSRAM_1024X16_IHP130_
`endif

`ifdef _AQ_SPSRAM_1024X16_ICS55_
`undef _AQ_SPSRAM_1024X16_ICS55_
`endif

//   &Instance("aq_tsmc_spsram_1024x16"); @49
//   &Instance("aq_umc_spsram_1024x16"); @61

// &ModuleEnd; @65
endmodule
