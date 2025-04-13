// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
// Authors:
//
// -Thomas Benz <tbenz@iis.ee.ethz.ch>
// -Tobias Senti <tsenti@student.ethz.ch>
// module tc_clk_inv (
//     input  clk_i,
//     output clk_o
// );

// `ifdef RTL_BEHAV
//   assign clk_o = ~clk_i;
// `else
//   (* keep *) (* dont_touch = "true" *)
//   sg13g2_inv_1 i_inv (
//       .A(clk_i),
//       .Y(clk_o)
//   );
// `endif

// endmodule

module tc_clk_buf (
    input  clk_i,
    output clk_o
);

`ifdef RTL_BEHAV
  assign clk_o = clk_i;
`else
  (* keep *) (* dont_touch = "true" *)
  // sg13g2_buf_1 i_buf (
  //     .A(clk_i),
  //     .X(clk_o)
  // );
  LVT_CLKBUFHDV12 i_buf (
      .I(clk_i),
      .Z(clk_o)
  );
`endif
endmodule

module tc_clk_mux2 (
    input  clk0_i,
    input  clk1_i,
    input  clk_sel_i,
    output clk_o
);

`ifdef RTL_BEHAV
  assign clk_o = clk_sel_i ? clk1_i : clk0_i;
`else
  (* keep *) (* dont_touch = "true" *)
  // sg13g2_mux2_1 i_mux (
  //     .A0(clk0_i),
  //     .A1(clk1_i),
  //     .S (clk_sel_i),
  //     .X (clk_o)
  // );
  LVT_CKMUX2HDV4 u_LVT_CKMUX2HDV4 (
      .S (clk_sel_i),
      .I0(clk0_i),
      .I1(clk1_i),
      .Z (clk_o)
  );

`endif
endmodule

// module tc_clk_xor2 (
//     input  clk0_i,
//     input  clk1_i,
//     output clk_o
// );

// `ifdef RTL_BEHAV
//   assign clk_o = clk0_i ^ clk1_i;
// `else
//   (* keep *) (* dont_touch = "true" *)
//   sg13g2_xor2_1 i_mux (
//       .A(clk0_i),
//       .B(clk1_i),
//       .X(clk_o)
//   );
// `endif
// endmodule
