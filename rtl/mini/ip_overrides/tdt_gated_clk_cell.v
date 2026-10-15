// retroSoC controlled override of the vendored OpenC906 tdt_gated_clk_cell.v.
//
// Source: openc906 dependency (dependencies.lock.json "openc906"),
//   C906_RTL_FACTORY/gen_rtl/tdt/rtl/common/tdt_gated_clk_cell.v
//   revision b0c06eb1f8b3bae663bd8b87eac89ff48e68a57f
// License: Apache-2.0 (T-Head Semiconductor)
//
// retroSoC change (OpenC906 integration manual chapter 3 ICG swap): the
// upstream `ifdef TDT_GATED_CELL branch is preserved verbatim; with a PDK
// define and without PDK_BEHAV the debug module clock gate uses the process
// integrated clock-gating cell (same selection as gated_clk_cell.v;
// ICGX1H7R has no test-enable pin, so the scan enable is ORed into E).
// PDK_BEHAV and PDK-less builds keep the upstream pass-through
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

module tdt_gated_clk_cell(
  clk_in,
  global_en,
  module_en,
  local_en,
  external_en,
  pad_yy_icg_scan_en,
  clk_out
);

input  clk_in;
input  global_en;
input  module_en;
input  local_en;
input  external_en;
input  pad_yy_icg_scan_en;
output clk_out;

wire   clk_en_bf_latch;
wire   SE;

assign clk_en_bf_latch = (global_en && (module_en || local_en)) || external_en ;

// SE driven from primary input, held constant
assign SE       = pad_yy_icg_scan_en;

`ifndef PDK_BEHAV
`ifdef PDK_IHP130
`define _TDT_GATED_CLK_CELL_IHP130_
`endif
`ifdef PDK_ICS55
`define _TDT_GATED_CLK_CELL_ICS55_
`endif
`ifdef PDK_SKY130
`define _TDT_GATED_CLK_CELL_SKY130_
`endif
`ifdef PDK_GF180
`define _TDT_GATED_CLK_CELL_GF180_
`endif
`endif

`ifdef TDT_GATED_CELL
tdt_gated_cell x_tdt_gated_cell(
  .clk_in        (clk_in),
  .external_en   (clk_en_bf_latch),
  .SE            (SE),
  .clk_out       (clk_out)
  );
//`ifdef TDT_SMIC
//  `ifdef TDT_PROCESS55LL
//HVT_CLKLANQHDV8 x_gated_clk_cell(
//.CK(clk_in),
//  `endif
//.TE(SE),
//.E(clk_en_bf_latch),
//.Q(clk_out));
//`endif
//`ifdef TDT_TSMC
//  `ifdef TDT_PROCESS40LP
//CKLNQD1BWP x_gated_clk_cell(
//.CP(clk_in),
//.TE(SE),
//.E(clk_en_bf_latch),
//.Q(clk_out));
//  `endif
//  `ifdef TDT_PROCESS28HPC
//    CKLNQD8BWP35P140  x_gated_clk_cell (
//                .CP     (clk_in),
//                .TE     (SE),
//                .E      (clk_en_bf_latch),
//                .Q      (clk_out)
//                );
//  `endif
//`endif
//`ifdef TDT_GSMC
//  `ifdef TDT_PROCESS130
//CLKGTPHD8X x_gated_clk_cell(
//.CK(clk_in),
//  `endif
//.TE(SE),
//.E(clk_en_bf_latch),
//.Z(clk_out));
//`endif
//
//`ifdef TDT_UMC
//  `ifdef TDT_PROCESS28HDE
//    PREICG_X4B_A9PP140ZTR_C30 x_gated_clk_cell (
//    .CK(clk_in),
//    .SE(SE),
//    .E(clk_en_bf_latch),
//    .ECK(clk_out)
//  );
//    `endif
//   `ifdef TDT_PROCESS22HDE
//    PREICG_X4B_A9PP140ZTS_C30 x_gated_clk_cell (
//    .CK(clk_in),
//    .SE(SE),
//    .E(clk_en_bf_latch),
//    .ECK(clk_out)
//  );
//
//  `endif
//`endif
`elsif _TDT_GATED_CLK_CELL_IHP130_
sg13g2_slgcp_1  u_icg (
  .CLK  (clk_in),
  .GATE (clk_en_bf_latch),
  .SCE  (SE),
  .GCLK (clk_out)
);
`elsif _TDT_GATED_CLK_CELL_ICS55_
// ICGX1H7R has no test-enable pin; OR the scan enable into the enable input.
wire   s_en_se;

assign s_en_se = clk_en_bf_latch | SE;

ICGX1H7R  u_icg (
  .CK  (clk_in),
  .E   (s_en_se),
  .ECK (clk_out)
);
`elsif _TDT_GATED_CLK_CELL_SKY130_
sky130_fd_sc_hd__sdlclkp_1  u_icg (
  .CLK  (clk_in),
  .GATE (clk_en_bf_latch),
  .SCE  (SE),
  .GCLK (clk_out)
);
`elsif _TDT_GATED_CLK_CELL_GF180_
gf180mcu_fd_sc_mcu7t5v0__icgtp_1  u_icg (
  .CLK      (clk_in),
  .E        (clk_en_bf_latch),
  .TE       (SE),
  .Q        (clk_out),
  .notifier (1'b0)
);
`else
//STN_CKGTPLT_V5_1  x_gated_clk_cell (
//  .CK           (clk_in),
//  .SE               (SE),
//  .EN      (clk_en_bf_latch),
//  .Q          (clk_out)
//);
assign clk_out = clk_in;
`endif

`ifdef _TDT_GATED_CLK_CELL_IHP130_
`undef _TDT_GATED_CLK_CELL_IHP130_
`endif
`ifdef _TDT_GATED_CLK_CELL_ICS55_
`undef _TDT_GATED_CLK_CELL_ICS55_
`endif
`ifdef _TDT_GATED_CLK_CELL_SKY130_
`undef _TDT_GATED_CLK_CELL_SKY130_
`endif
`ifdef _TDT_GATED_CLK_CELL_GF180_
`undef _TDT_GATED_CLK_CELL_GF180_
`endif

endmodule
