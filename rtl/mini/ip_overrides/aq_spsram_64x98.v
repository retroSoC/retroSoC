// retroSoC controlled override of the vendored OpenC906 aq_spsram_64x98.v.
//
// Source: openc906 dependency (dependencies.lock.json "openc906"),
//   C906_RTL_FACTORY/gen_rtl/mmu/rtl/aq_spsram_64x98.v
//   revision b0c06eb1f8b3bae663bd8b87eac89ff48e68a57f
// License: Apache-2.0 (T-Head Semiconductor)
//
// retroSoC change (OpenC906 integration manual chapter 3 SRAM swap): with
// PDK_IHP130+HAVE_SRAM_MACRO and without PDK_BEHAV, the 64x98 JTLB tag RAM
// is built from two RM_IHPSG13_1P_64x64_c2_bm_bist macros in a width stack:
// one macro holds the low 64 bits, the other the high 34 bits with its upper
// mask bits tied off so they are never written (manual section 3.1.5
// stacking). With PDK_ICS55+HAVE_SRAM_MACRO and without PDK_BEHAV, the
// exact-geometry ics55_ecos_sram_64x98_m4 macro replaces it directly
// (identical active-low polarity, no stacking or padding). With
// PDK_GF180+HAVE_SRAM_MACRO and without PDK_BEHAV, thirteen GF180
// gf180mcu_fd_ip_sram__sram64x8m8wm1 tiles width-stack it (the top tile's
// upper 6 bits are tied inactive; the repo-owned functional models live in
// rtl/tech/gf180_sram_sim_cells.sv). Every other configuration keeps the
// upstream behavioral aq_f_spsram_64x98 instance byte-identical. Keep in
// sync when the lock revision changes.

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
module aq_spsram_64x98(
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
input   [97:0]  D;
input           GWEN;
input   [97:0]  WEN;
output  [97:0]  Q;

// &Regs; @24

// &Wires; @25
wire    [5 :0]  A;
wire            CEN;
wire            CLK;
wire    [97:0]  D;
wire            GWEN;
wire    [97:0]  Q;
wire    [97:0]  WEN;


//**********************************************************
//                  Parameter Definition
//**********************************************************
parameter ADDR_WIDTH = 6;
parameter DATA_WIDTH = 98;
parameter WE_WIDTH   = 98;

// &Force("bus","Q",DATA_WIDTH-1,0); @34
// &Force("bus","WEN",WE_WIDTH-1,0); @35
// &Force("bus","A",ADDR_WIDTH-1,0); @36
// &Force("bus","D",DATA_WIDTH-1,0); @37

`ifdef PDK_IHP130
`ifdef HAVE_SRAM_MACRO
`ifndef PDK_BEHAV
`define _AQ_SPSRAM_64X98_IHP130_
`endif
`endif
`endif

`ifdef PDK_ICS55
`ifdef HAVE_SRAM_MACRO
`ifndef PDK_BEHAV
`define _AQ_SPSRAM_64X98_ICS55_
`endif
`endif
`endif

`ifdef PDK_GF180
`ifdef HAVE_SRAM_MACRO
`ifndef PDK_BEHAV
`define _AQ_SPSRAM_64X98_GF180_
`endif
`endif
`endif

`ifdef _AQ_SPSRAM_64X98_IHP130_
  //********************************************************
  //*                IHP130 SRAM macro                     *
  //********************************************************
// Two 64x64 macros are width-stacked into 64x98: the low 64 bits get one
// macro, the high 34 bits get another with its upper 30 mask bits tied off
// so they are never written; both share address and control.
wire   [63:0]  s_q_lo;
wire   [63:0]  s_q_hi;
wire   [29:0]  s_q_hi_unused;

assign Q = {s_q_hi[33:0], s_q_lo};
assign s_q_hi_unused = s_q_hi[63:34];

RM_IHPSG13_1P_64x64_c2_bm_bist  u_mem_lo (
  .A_CLK      (CLK           ),
  .A_ADDR     (A             ),
  .A_BM       (~WEN[63:0]    ),
  .A_MEN      (~CEN          ),
  .A_WEN      (~GWEN         ),
  .A_REN      (GWEN          ),
  .A_DIN      (D[63:0]       ),
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
  .A_CLK      (CLK                 ),
  .A_ADDR     (A                   ),
  .A_BM       ({30'b0, ~WEN[97:64]}),
  .A_MEN      (~CEN                ),
  .A_WEN      (~GWEN               ),
  .A_REN      (GWEN                ),
  .A_DIN      ({30'b0, D[97:64]}   ),
  .A_DOUT     (s_q_hi              ),
  .A_DLY      (1'b1                ),
  .A_BIST_CLK (1'b0                ),
  .A_BIST_EN  (1'b0                ),
  .A_BIST_MEN (1'b0                ),
  .A_BIST_WEN (1'b0                ),
  .A_BIST_REN (1'b0                ),
  .A_BIST_ADDR(6'b0                ),
  .A_BIST_DIN (64'b0               ),
  .A_BIST_BM  (64'b0               )
);
`elsif _AQ_SPSRAM_64X98_ICS55_
  //********************************************************
  //*                ICS55 SRAM macro                      *
  //********************************************************
// Exact-geometry macro; polarities match the wrapper, direct connection.
ics55_ecos_sram_64x98_m4  u_mem (
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
`elsif _AQ_SPSRAM_64X98_GF180_
  //********************************************************
  //*                GF180 SRAM macro                      *
  //********************************************************
// Thirteen 64x8 tiles width-stack the 98-bit word; the top tile's upper 6
// bits are tied inactive so they are never written.
`ifndef SYNTHESIS
wire           s_vdd;
wire           s_vss;

assign s_vdd = 1'b1;
assign s_vss = 1'b0;
`endif
wire   [103:0]  s_din_ext;
wire   [103:0]  s_wen_ext;
wire   [103:0]  s_q;
wire   [5:0]    s_q_unused;
genvar          g_w;

assign s_din_ext  = {6'b000000, D};
assign s_wen_ext  = {6'b111111, WEN};
assign Q          = s_q[97:0];
assign s_q_unused = s_q[103:98];

generate
  for (g_w = 0; g_w < 13; g_w = g_w + 1) begin : gen_width
    gf180mcu_fd_ip_sram__sram64x8m8wm1  u_mem (
      .CLK  (CLK                    ),
      .CEN  (CEN                    ),
      .GWEN (GWEN                   ),
      .WEN  (s_wen_ext[g_w*8 +: 8]  ),
      .A    (A                      ),
      .D    (s_din_ext[g_w*8 +: 8]  ),
`ifndef SYNTHESIS
      .Q    (s_q[g_w*8 +: 8]        ),
      .VDD  (s_vdd                  ),
      .VSS  (s_vss                  )
`else
      .Q    (s_q[g_w*8 +: 8]        )
`endif
    );
  end
endgenerate
`else
  //********************************************************
  //*                        FPGA memory                   *
  //********************************************************
  //{WEN[111:56],WEN[55:0]}
//   &Instance("aq_f_spsram_64x98"); @44
aq_f_spsram_64x98  x_aq_f_spsram_64x98 (
  .A    (A   ),
  .CEN  (CEN ),
  .CLK  (CLK ),
  .D    (D   ),
  .GWEN (GWEN),
  .Q    (Q   ),
  .WEN  (WEN )
);
`endif

`ifdef _AQ_SPSRAM_64X98_IHP130_
`undef _AQ_SPSRAM_64X98_IHP130_
`endif

`ifdef _AQ_SPSRAM_64X98_ICS55_
`undef _AQ_SPSRAM_64X98_ICS55_
`endif

`ifdef _AQ_SPSRAM_64X98_GF180_
`undef _AQ_SPSRAM_64X98_GF180_
`endif

//   &Instance("aq_tsmc_spsram_64x98"); @50
//   &Instance("aq_umc_spsram_64x98"); @62

// &ModuleEnd; @66
endmodule
