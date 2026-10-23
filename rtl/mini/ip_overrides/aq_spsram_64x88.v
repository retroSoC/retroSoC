// retroSoC controlled override of the vendored OpenC906 aq_spsram_64x88.v.
//
// Source: openc906 dependency (dependencies.lock.json "openc906"),
//   C906_RTL_FACTORY/gen_rtl/mmu/rtl/aq_spsram_64x88.v
//   revision b0c06eb1f8b3bae663bd8b87eac89ff48e68a57f
// License: Apache-2.0 (T-Head Semiconductor)
//
// retroSoC change (OpenC906 integration manual chapter 3 SRAM swap): with
// PDK_IHP130+HAVE_SRAM_MACRO and without PDK_BEHAV, the 64x88 JTLB data RAM
// is built from two RM_IHPSG13_1P_64x64_c2_bm_bist macros in a width stack:
// one macro holds the low 64 bits, the other the high 24 bits with its upper
// mask bits tied off so they are never written (manual section 3.1.5
// stacking). With PDK_ICS55+HAVE_SRAM_MACRO and without PDK_BEHAV, the
// exact-geometry ics55_ecos_sram_64x88_m4 macro replaces it directly
// (identical active-low polarity, no stacking or padding). With
// PDK_GF180+HAVE_SRAM_MACRO and without PDK_BEHAV, eleven GF180
// gf180mcu_fd_ip_sram__sram64x8m8wm1 tiles width-stack it exactly (the
// repo-owned functional models live in rtl/tech/gf180_sram_sim_cells.sv).
// Every other configuration keeps the upstream behavioral
// aq_f_spsram_64x88 instance byte-identical. Keep in sync when the lock
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
module aq_spsram_64x88(
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
input   [87:0]  D;
input           GWEN;
input   [87:0]  WEN;
output  [87:0]  Q;

// &Regs; @24

// &Wires; @25
wire    [5 :0]  A;
wire            CEN;
wire            CLK;
wire    [87:0]  D;
wire            GWEN;
wire    [87:0]  Q;
wire    [87:0]  WEN;


//**********************************************************
//                  Parameter Definition
//**********************************************************
parameter ADDR_WIDTH = 6;
parameter DATA_WIDTH = 88;
parameter WE_WIDTH   = 88;

// &Force("bus","Q",DATA_WIDTH-1,0); @34
// &Force("bus","WEN",WE_WIDTH-1,0); @35
// &Force("bus","A",ADDR_WIDTH-1,0); @36
// &Force("bus","D",DATA_WIDTH-1,0); @37

`ifdef PDK_IHP130
`ifdef HAVE_SRAM_MACRO
`ifndef PDK_BEHAV
`define _AQ_SPSRAM_64X88_IHP130_
`endif
`endif
`endif

`ifdef PDK_ICS55
`ifdef HAVE_SRAM_MACRO
`ifndef PDK_BEHAV
`define _AQ_SPSRAM_64X88_ICS55_
`endif
`endif
`endif

`ifdef PDK_GF180
`ifdef HAVE_SRAM_MACRO
`ifndef PDK_BEHAV
`define _AQ_SPSRAM_64X88_GF180_
`endif
`endif
`endif

`ifdef _AQ_SPSRAM_64X88_IHP130_
  //********************************************************
  //*                IHP130 SRAM macro                     *
  //********************************************************
// Two 64x64 macros are width-stacked into 64x88: the low 64 bits get one
// macro, the high 24 bits get another with its upper 40 mask bits tied off
// so they are never written; both share address and control.
wire   [63:0]  s_q_lo;
wire   [63:0]  s_q_hi;
wire   [39:0]  s_q_hi_unused;

assign Q = {s_q_hi[23:0], s_q_lo};
assign s_q_hi_unused = s_q_hi[63:24];

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
  .A_BM       ({40'b0, ~WEN[87:64]}),
  .A_MEN      (~CEN                ),
  .A_WEN      (~GWEN               ),
  .A_REN      (GWEN                ),
  .A_DIN      ({40'b0, D[87:64]}   ),
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
`elsif _AQ_SPSRAM_64X88_ICS55_
  //********************************************************
  //*                ICS55 SRAM macro                      *
  //********************************************************
// Exact-geometry macro; polarities match the wrapper, direct connection.
ics55_ecos_sram_64x88_m4  u_mem (
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
`elsif _AQ_SPSRAM_64X88_GF180_
  //********************************************************
  //*                GF180 SRAM macro                      *
  //********************************************************
// Eleven 64x8 tiles width-stack the 88-bit word exactly.
`ifndef SYNTHESIS
wire           s_vdd;
wire           s_vss;

assign s_vdd = 1'b1;
assign s_vss = 1'b0;
`endif
wire   [87:0]  s_q;
genvar         g_w;

assign Q = s_q;

generate
  for (g_w = 0; g_w < 11; g_w = g_w + 1) begin : gen_width
    gf180mcu_fd_ip_sram__sram64x8m8wm1  u_mem (
      .CLK  (CLK              ),
      .CEN  (CEN              ),
      .GWEN (GWEN             ),
      .WEN  (WEN[g_w*8 +: 8]  ),
      .A    (A                ),
      .D    (D[g_w*8 +: 8]    ),
`ifndef SYNTHESIS
      .Q    (s_q[g_w*8 +: 8]  ),
      .VDD  (s_vdd            ),
      .VSS  (s_vss            )
`else
      .Q    (s_q[g_w*8 +: 8]  )
`endif
    );
  end
endgenerate
`else
  //********************************************************
  //*                        FPGA memory                   *
  //********************************************************
  //{WEN[135:132],WEN[131:99],WEN[98:66],WEN[65:33],WEN[32:0]}
//   &Instance("aq_f_spsram_64x88"); @44
aq_f_spsram_64x88  x_aq_f_spsram_64x88 (
  .A    (A   ),
  .CEN  (CEN ),
  .CLK  (CLK ),
  .D    (D   ),
  .GWEN (GWEN),
  .Q    (Q   ),
  .WEN  (WEN )
);
`endif

`ifdef _AQ_SPSRAM_64X88_IHP130_
`undef _AQ_SPSRAM_64X88_IHP130_
`endif

`ifdef _AQ_SPSRAM_64X88_ICS55_
`undef _AQ_SPSRAM_64X88_ICS55_
`endif

`ifdef _AQ_SPSRAM_64X88_GF180_
`undef _AQ_SPSRAM_64X88_GF180_
`endif

//   &Instance("aq_tsmc_spsram_64x88"); @50
//   &Instance("aq_umc_spsram_64x88"); @62

// &ModuleEnd; @66
endmodule
