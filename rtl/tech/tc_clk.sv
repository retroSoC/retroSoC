// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
// Authors:
//
// -Thomas Benz <tbenz@iis.ee.ethz.ch>
// -Tobias Senti <tsenti@student.ethz.ch>



module tc_clk_inv (
    input  logic clk_i,
    output logic clk_o
);

`ifdef PDK_BEHAV
  assign clk_o = ~clk_i;

`elsif PDK_IHP130
  (* keep *) (* dont_touch = "true" *)
  sg13g2_inv_1 u_sg13g2_inv_1 (
      .A(clk_i),
      .Y(clk_o)
  );

`elsif PDK_S110
  (* keep *) (* dont_touch = "true" *)
  assign clk_o = ~clk_i;  // HACK:

`elsif PDK_CX55
  (* keep *) (* dont_touch = "true" *)
  INVX0P5H9L u_INVX0P5H9L (
      .A(clk_i),
      .Y(clk_o)
  );
`endif

endmodule

module tc_clk_buf (
    input  logic clk_i,
    output logic clk_o
);

`ifdef PDK_BEHAV
  assign clk_o = clk_i;

`elsif PDK_IHP130
  (* keep *) (* dont_touch = "true" *)
  sg13g2_buf_1 u_sg13g2_buf_1 (
      .A(clk_i),
      .X(clk_o)
  );

`elsif PDK_S110
  (* keep *) (* dont_touch = "true" *)
  LVT_CLKBUFHDV12 u_LVT_CLKBUFHDV12 (
      .I(clk_i),
      .Z(clk_o)
  );

`elsif PDK_CX55
  (* keep *) (* dont_touch = "true" *)
  BUFX0P7H9L u_BUFX0P7H9L (
      .A(clk_i),
      .Y(clk_o)
  );
`endif
endmodule

module tc_clk_mux2 (
    input  logic clk0_i,
    input  logic clk1_i,
    input  logic clk_sel_i,
    output logic clk_o
);

`ifdef PDK_BEHAV
  assign clk_o = clk_sel_i ? clk1_i : clk0_i;

`elsif PDK_IHP130
  (* keep *) (* dont_touch = "true" *)
  sg13g2_mux2_1 u_sg13g2_mux2_1 (
      .A0(clk0_i),
      .A1(clk1_i),
      .S (clk_sel_i),
      .X (clk_o)
  );

`elsif PDK_S110
  (* keep *) (* dont_touch = "true" *)
  LVT_CKMUX2HDV4 u_LVT_CKMUX2HDV4 (
      .S (clk_sel_i),
      .I0(clk0_i),
      .I1(clk1_i),
      .Z (clk_o)
  );

`elsif PDK_CX55
  (* keep *) (* dont_touch = "true" *)
  MUX2X0P5H9L u_MUX2X0P5H9L (
      .S0(clk_sel_i),
      .A (clk0_i),
      .B (clk1_i),
      .Y (clk_o)
  );
`endif
endmodule

module tc_clk_xor2 (
    input  logic clk0_i,
    input  logic clk1_i,
    output logic clk_o
);

`ifdef PDK_BEHAV
  assign clk_o = clk0_i ^ clk1_i;

`elsif PDK_IHP130
  (* keep *) (* dont_touch = "true" *)
  sg13g2_xor2_1 i_mux (
      .A(clk0_i),
      .B(clk1_i),
      .X(clk_o)
  );
`endif
endmodule
