// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
// Authors:
//
// -Thomas Benz <tbenz@iis.ee.ethz.ch>
// -Tobias Senti <tsenti@student.ethz.ch>
module ihp_clk_inverter (
    input  clk_i,
    output clk_o
);

  (* keep *) (* dont_touch = "true" *)
  sg13g2_inv_1 i_inv (
      .A(clk_i),
      .Y(clk_o)
  );

endmodule

module ihp_clk_buffer (
    input  clk_i,
    output clk_o
);

  (* keep *) (* dont_touch = "true" *)
  sg13g2_buf_1 i_buf (
      .A(clk_i),
      .X(clk_o)
  );

endmodule

module ihp_clk_mux2 (
    input  clk0_i,
    input  clk1_i,
    input  clk_sel_i,
    output clk_o
);
  (* keep *) (* dont_touch = "true" *)
  sg13g2_mux2_1 i_mux (
      .A0(clk0_i),
      .A1(clk1_i),
      .S (clk_sel_i),
      .X (clk_o)
  );
endmodule

module ihp_clk_xor2 (
    input  clk0_i,
    input  clk1_i,
    output clk_o
);

  (* keep *) (* dont_touch = "true" *)
  sg13g2_xor2_1 i_mux (
      .A(clk0_i),
      .B(clk1_i),
      .X(clk_o)
  );
endmodule

module ihp_clk_gating #(
    parameter [0:0] IS_FUNCTIONAL = 1'b1
) (
    input  clk_i,
    input  en_i,
    input  test_en_i,
    output clk_o
);

  //   if (IS_FUNCTIONAL || `ifdef USE_CLKGATE 1 `else 0 `endif) begin
  //     (* keep *)(* dont_touch = "true" *)
  //     sg13g2_slgcp_1 i_clkgate (
  //       .GATE ( en_i  ),
  //       .SCE  ( test_en_i ),
  //       .CLK  ( clk_i ),
  //       .GCLK ( clk_o )
  //     );
  //   end else begin
  assign clk_o = clk_i;
  //   end

endmodule
