// retroSoC controlled override of the vendored OpenC906 BUFGCE.v.
//
// Source: openc906 dependency (dependencies.lock.json "openc906"),
//   C906_RTL_FACTORY/gen_rtl/common/rtl/BUFGCE.v
//   revision b0c06eb1f8b3bae663bd8b87eac89ff48e68a57f
// License: Apache-2.0 (T-Head Semiconductor)
//
// retroSoC change (OpenC906 integration manual chapter 3 ICG swap): with a
// PDK define and without PDK_BEHAV, the clock buffer-gate feeding the
// PLIC/CLINT divide-by-2 domain (aq_mp_clk_top.v apb_clk_buf) uses the
// process integrated clock-gating cell (same selection as
// gated_clk_cell.v; there is no scan enable on this instance, so SCE/TE are
// tied off). PDK_BEHAV and PDK-less builds keep the upstream behavioral
// latch-based gate byte-identical. Keep in sync when the lock revision
// changes.

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

module BUFGCE(
  I,
  CE,
  O
);

input  I;
input  CE ;
output O;

`ifndef PDK_BEHAV
`ifdef PDK_IHP130
`define _AQ_BUFGCE_IHP130_
`endif
`ifdef PDK_ICS55
`define _AQ_BUFGCE_ICS55_
`endif
`ifdef PDK_SKY130
`define _AQ_BUFGCE_SKY130_
`endif
`ifdef PDK_GF180
`define _AQ_BUFGCE_GF180_
`endif
`endif

`ifdef _AQ_BUFGCE_IHP130_
sg13g2_slgcp_1  u_icg (
  .CLK  (I),
  .GATE (CE),
  .SCE  (1'b0),
  .GCLK (O)
);
`elsif _AQ_BUFGCE_ICS55_
ICGX1H7R  u_icg (
  .CK  (I),
  .E   (CE),
  .ECK (O)
);
`elsif _AQ_BUFGCE_SKY130_
sky130_fd_sc_hd__sdlclkp_1  u_icg (
  .CLK  (I),
  .GATE (CE),
  .SCE  (1'b0),
  .GCLK (O)
);
`elsif _AQ_BUFGCE_GF180_
gf180mcu_fd_sc_mcu7t5v0__icgtp_1  u_icg (
  .CLK      (I),
  .E        (CE),
  .TE       (1'b0),
  .Q        (O),
  .notifier (1'b0)
);
`else
reg    clk_en_af_latch;
always @(I or CE)
begin
  if(!I)
    clk_en_af_latch <= CE;
end

reg clk_en ;
always @ (clk_en_af_latch )
begin
    clk_en <= clk_en_af_latch;
end
assign O = I && clk_en ;
`endif

`ifdef _AQ_BUFGCE_IHP130_
`undef _AQ_BUFGCE_IHP130_
`endif
`ifdef _AQ_BUFGCE_ICS55_
`undef _AQ_BUFGCE_ICS55_
`endif
`ifdef _AQ_BUFGCE_SKY130_
`undef _AQ_BUFGCE_SKY130_
`endif
`ifdef _AQ_BUFGCE_GF180_
`undef _AQ_BUFGCE_GF180_
`endif

endmodule
