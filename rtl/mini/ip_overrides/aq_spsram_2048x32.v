// retroSoC controlled override of the vendored OpenC906 aq_spsram_2048x32.v.
//
// Source: openc906 dependency (dependencies.lock.json "openc906"),
//   C906_RTL_FACTORY/gen_rtl/ifu/rtl/aq_spsram_2048x32.v
//   revision b0c06eb1f8b3bae663bd8b87eac89ff48e68a57f
// License: Apache-2.0 (T-Head Semiconductor)
//
// retroSoC change (OpenC906 integration manual chapter 3 SRAM swap): with
// PDK_IHP130+HAVE_SRAM_MACRO and without PDK_BEHAV, the 2048x32 ICache data
// RAM is built from two RM_IHPSG13_1P_1024x32_c2_bm_bist macros in a depth
// stack: A[10] selects the bank and the read-data mux uses the bank select
// registered on read transactions (manual section 3.1.5 stacking). With
// PDK_ICS55+HAVE_SRAM_MACRO and without PDK_BEHAV, the exact-geometry
// ics55_ecos_sram_2048x32_m8 macro replaces it directly (identical
// active-low polarity, no stacking or padding). With PDK_GF180+
// HAVE_SRAM_MACRO and without PDK_BEHAV, GF180
// gf180mcu_fd_ip_sram__sram512x8m8wm1 tiles build it (four deep selected by
// A[10:9] with a registered read mux, times four wide; the repo-owned
// functional models live in rtl/tech/gf180_sram_sim_cells.sv). Every other
// configuration keeps the upstream behavioral aq_f_spsram_2048x32 instance
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
module aq_spsram_2048x32(
  A,
  CEN,
  CLK,
  D,
  GWEN,
  Q,
  WEN
);

// &Ports; @23
input   [10:0]  A;
input           CEN;
input           CLK;
input   [31:0]  D;
input           GWEN;
input   [31:0]  WEN;
output  [31:0]  Q;

// &Regs; @24

// &Wires; @25
wire    [10:0]  A;
wire            CEN;
wire            CLK;
wire    [31:0]  D;
wire            GWEN;
wire    [31:0]  Q;
wire    [31:0]  WEN;


//**********************************************************
//                  Parameter Definition
//**********************************************************
parameter ADDR_WIDTH = 11;
parameter DATA_WIDTH = 32;
parameter WE_WIDTH   = 32;

// &Force("bus","Q",DATA_WIDTH-1,0); @34
// &Force("bus","WEN",WE_WIDTH-1,0); @35
// &Force("bus","A",ADDR_WIDTH-1,0); @36
// &Force("bus","D",DATA_WIDTH-1,0); @37

`ifdef PDK_IHP130
`ifdef HAVE_SRAM_MACRO
`ifndef PDK_BEHAV
`define _AQ_SPSRAM_2048X32_IHP130_
`endif
`endif
`endif

`ifdef PDK_ICS55
`ifdef HAVE_SRAM_MACRO
`ifndef PDK_BEHAV
`define _AQ_SPSRAM_2048X32_ICS55_
`endif
`endif
`endif

`ifdef PDK_GF180
`ifdef HAVE_SRAM_MACRO
`ifndef PDK_BEHAV
`define _AQ_SPSRAM_2048X32_GF180_
`endif
`endif
`endif

`ifdef _AQ_SPSRAM_2048X32_IHP130_
  //********************************************************
  //*                IHP130 SRAM macro                     *
  //********************************************************
// Two 1024x32 macros are depth-stacked into 2048x32: A[10] chip-selects the
// bank, and the read-data mux uses the bank select registered on reads.
wire           s_en_lo;
wire           s_en_hi;
wire   [31:0]  s_q_lo;
wire   [31:0]  s_q_hi;
reg            s_rd_sel_q;

assign s_en_lo = ~CEN & ~A[10];
assign s_en_hi = ~CEN &  A[10];

always @(posedge CLK) begin
  if (!CEN && GWEN) begin
    s_rd_sel_q <= A[10];
  end
end

assign Q = s_rd_sel_q ? s_q_hi : s_q_lo;

RM_IHPSG13_1P_1024x32_c2_bm_bist  u_mem_lo (
  .A_CLK      (CLK     ),
  .A_ADDR     (A[9:0]  ),
  .A_BM       (~WEN    ),
  .A_MEN      (s_en_lo ),
  .A_WEN      (~GWEN   ),
  .A_REN      (GWEN    ),
  .A_DIN      (D       ),
  .A_DOUT     (s_q_lo  ),
  .A_DLY      (1'b1    ),
  .A_BIST_CLK (1'b0    ),
  .A_BIST_EN  (1'b0    ),
  .A_BIST_MEN (1'b0    ),
  .A_BIST_WEN (1'b0    ),
  .A_BIST_REN (1'b0    ),
  .A_BIST_ADDR(10'b0   ),
  .A_BIST_DIN (32'b0   ),
  .A_BIST_BM  (32'b0   )
);

RM_IHPSG13_1P_1024x32_c2_bm_bist  u_mem_hi (
  .A_CLK      (CLK     ),
  .A_ADDR     (A[9:0]  ),
  .A_BM       (~WEN    ),
  .A_MEN      (s_en_hi ),
  .A_WEN      (~GWEN   ),
  .A_REN      (GWEN    ),
  .A_DIN      (D       ),
  .A_DOUT     (s_q_hi  ),
  .A_DLY      (1'b1    ),
  .A_BIST_CLK (1'b0    ),
  .A_BIST_EN  (1'b0    ),
  .A_BIST_MEN (1'b0    ),
  .A_BIST_WEN (1'b0    ),
  .A_BIST_REN (1'b0    ),
  .A_BIST_ADDR(10'b0   ),
  .A_BIST_DIN (32'b0   ),
  .A_BIST_BM  (32'b0   )
);
`elsif _AQ_SPSRAM_2048X32_ICS55_
  //********************************************************
  //*                ICS55 SRAM macro                      *
  //********************************************************
// Exact-geometry macro; polarities match the wrapper, direct connection.
ics55_ecos_sram_2048x32_m8  u_mem (
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
`elsif _AQ_SPSRAM_2048X32_GF180_
  //********************************************************
  //*                GF180 SRAM macro                      *
  //********************************************************
// Sixteen 512x8 tiles: four deep selected by A[10:9] with the bank select
// registered on read transactions, times four wide.
`ifndef SYNTHESIS
wire           s_vdd;
wire           s_vss;

assign s_vdd = 1'b1;
assign s_vss = 1'b0;
`endif
wire   [127:0]  s_q;
reg    [1:0]    s_rd_sel_q;
genvar          g_d;
genvar          g_w;

always @(posedge CLK) begin
  if (!CEN && GWEN) begin
    s_rd_sel_q <= A[10:9];
  end
end

assign Q = s_q[s_rd_sel_q*32 +: 32];

generate
  for (g_d = 0; g_d < 4; g_d = g_d + 1) begin : gen_depth
    for (g_w = 0; g_w < 4; g_w = g_w + 1) begin : gen_width
      gf180mcu_fd_ip_sram__sram512x8m8wm1  u_mem (
        .CLK  (CLK                       ),
        .CEN  (~(~CEN & (A[10:9] == g_d))),
        .GWEN (GWEN                      ),
        .WEN  (WEN[g_w*8 +: 8]           ),
        .A    (A[8:0]                    ),
        .D    (D[g_w*8 +: 8]             ),
`ifndef SYNTHESIS
        .Q    (s_q[g_d*32 + g_w*8 +: 8]  ),
        .VDD  (s_vdd                     ),
        .VSS  (s_vss                     )
`else
        .Q    (s_q[g_d*32 + g_w*8 +: 8]  )
`endif
      );
    end
  end
endgenerate
`else
  //********************************************************
  //*                        FPGA memory                   *
  //********************************************************
//   &Instance("aq_f_spsram_2048x32"); @43
aq_f_spsram_2048x32  x_aq_f_spsram_2048x32 (
  .A    (A   ),
  .CEN  (CEN ),
  .CLK  (CLK ),
  .D    (D   ),
  .GWEN (GWEN),
  .Q    (Q   ),
  .WEN  (WEN )
);
`endif

`ifdef _AQ_SPSRAM_2048X32_IHP130_
`undef _AQ_SPSRAM_2048X32_IHP130_
`endif

`ifdef _AQ_SPSRAM_2048X32_ICS55_
`undef _AQ_SPSRAM_2048X32_ICS55_
`endif

`ifdef _AQ_SPSRAM_2048X32_GF180_
`undef _AQ_SPSRAM_2048X32_GF180_
`endif

//   &Instance("aq_tsmc_spsram_2048x32"); @49
//   &Instance("aq_umc_spsram_2048x32"); @61

// &ModuleEnd; @65
endmodule
