// retroSoC controlled override of the vendored OpenC906 aq_spsram_128x8.v.
//
// Source: openc906 dependency (dependencies.lock.json "openc906"),
//   C906_RTL_FACTORY/gen_rtl/lsu/rtl/aq_spsram_128x8.v
//   revision b0c06eb1f8b3bae663bd8b87eac89ff48e68a57f
// License: Apache-2.0 (T-Head Semiconductor)
//
// retroSoC change (OpenC906 integration manual chapter 3 SRAM swap): with
// PDK_IHP130+HAVE_SRAM_MACRO and without PDK_BEHAV, the 128x8 DCache dirty
// RAM is built from two RM_IHPSG13_1P_64x64_c2_bm_bist macros in a depth
// stack: A[6] selects the bank, only the low 8 bits of each macro are used
// (upper mask bits tied off so they are never written), and the read-data
// mux uses the bank select registered on read transactions (manual section
// 3.1.5 stacking). Every other configuration keeps the upstream behavioral
// aq_f_spsram_128x8 instance byte-identical. Keep in sync when the lock
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
module aq_spsram_128x8(
  A,
  CEN,
  CLK,
  D,
  GWEN,
  Q,
  WEN
);

// &Ports; @23
input   [6:0]  A;
input          CEN;
input          CLK;
input   [7:0]  D;
input          GWEN;
input   [7:0]  WEN;
output  [7:0]  Q;

// &Regs; @24

// &Wires; @25
wire    [6:0]  A;
wire           CEN;
wire           CLK;
wire    [7:0]  D;
wire           GWEN;
wire    [7:0]  Q;
wire    [7:0]  WEN;


//**********************************************************
//                  Parameter Definition
//**********************************************************
parameter ADDR_WIDTH = 7;
parameter DATA_WIDTH = 8;
parameter WE_WIDTH   = 8;

// &Force("bus","Q",DATA_WIDTH-1,0); @34
// &Force("bus","WEN",WE_WIDTH-1,0); @35
// &Force("bus","A",ADDR_WIDTH-1,0); @36
// &Force("bus","D",DATA_WIDTH-1,0); @37

`ifdef PDK_IHP130
`ifdef HAVE_SRAM_MACRO
`ifndef PDK_BEHAV
`define _AQ_SPSRAM_128X8_IHP130_
`endif
`endif
`endif

`ifdef _AQ_SPSRAM_128X8_IHP130_
  //********************************************************
  //*                IHP130 SRAM macro                     *
  //********************************************************
// Two 64x64 macros are depth-stacked into 128x8: A[6] chip-selects the bank,
// the upper 56 data/mask bits of each macro are tied off so they are never
// written, and the read-data mux uses the bank select registered on reads.
wire   [63:0]  s_din;
wire   [63:0]  s_bm;
wire   [63:0]  s_q_lo;
wire   [63:0]  s_q_hi;
wire   [55:0]  s_q_lo_unused;
wire   [55:0]  s_q_hi_unused;
reg            s_rd_sel_q;

assign s_din = {56'b0, D};
assign s_bm  = {56'b0, ~WEN};

always @(posedge CLK) begin
  if (!CEN && GWEN) begin
    s_rd_sel_q <= A[6];
  end
end

assign Q = s_rd_sel_q ? s_q_hi[7:0] : s_q_lo[7:0];
assign s_q_lo_unused = s_q_lo[63:8];
assign s_q_hi_unused = s_q_hi[63:8];

RM_IHPSG13_1P_64x64_c2_bm_bist  u_mem_lo (
  .A_CLK      (CLK           ),
  .A_ADDR     (A[5:0]        ),
  .A_BM       (s_bm          ),
  .A_MEN      (~CEN & ~A[6]  ),
  .A_WEN      (~GWEN         ),
  .A_REN      (GWEN          ),
  .A_DIN      (s_din         ),
  .A_DOUT     (s_q_lo        ),
  .A_DLY      (1'b1          ),
  .A_BIST_CLK (1'b0          ),
  .A_BIST_EN  (1'b0          ),
  .A_BIST_MEN (1'b0          ),
  .A_BIST_WEN (1'b0          ),
  .A_BIST_REN (1'b0          ),
  .A_BIST_ADDR(6'b0          ),
  .A_BIST_DIN (64'b0         ),
  .A_BIST_BM  (64'b0         )
);

RM_IHPSG13_1P_64x64_c2_bm_bist  u_mem_hi (
  .A_CLK      (CLK           ),
  .A_ADDR     (A[5:0]        ),
  .A_BM       (s_bm          ),
  .A_MEN      (~CEN & A[6]   ),
  .A_WEN      (~GWEN         ),
  .A_REN      (GWEN          ),
  .A_DIN      (s_din         ),
  .A_DOUT     (s_q_hi        ),
  .A_DLY      (1'b1          ),
  .A_BIST_CLK (1'b0          ),
  .A_BIST_EN  (1'b0          ),
  .A_BIST_MEN (1'b0          ),
  .A_BIST_WEN (1'b0          ),
  .A_BIST_REN (1'b0          ),
  .A_BIST_ADDR(6'b0          ),
  .A_BIST_DIN (64'b0         ),
  .A_BIST_BM  (64'b0         )
);
`else
//  //********************************************************
//  //*                        FPGA memory                   *
//  //********************************************************
//   &Instance("aq_f_spsram_128x8"); @43
aq_f_spsram_128x8  x_aq_f_spsram_128x8 (
  .A    (A   ),
  .CEN  (CEN ),
  .CLK  (CLK ),
  .D    (D   ),
  .GWEN (GWEN),
  .Q    (Q   ),
  .WEN  (WEN )
);
`endif

`ifdef _AQ_SPSRAM_128X8_IHP130_
`undef _AQ_SPSRAM_128X8_IHP130_
`endif

//   &Instance("aq_umc_spsram_128x8"); @49
//   &Instance("aq_tsmc_spsram_128x8"); @55
// &ModuleEnd; @58
endmodule
