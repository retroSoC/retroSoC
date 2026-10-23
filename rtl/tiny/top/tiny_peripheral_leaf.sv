// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

// The base clock and lifecycle registers never stop. A gate only stops its
// peripheral leaf, at a falling edge. Local reset asserts asynchronously;
// hold/release acknowledgements require five actual leaf clock edges.
module tiny_peripheral_leaf (
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic gate_i,
    input  logic reset_i,
    output logic clk_o,
    output logic rst_n_o,
    output logic gated_o,
    output logic held_o
);
  logic s_gate_sync, s_gate_q;
  logic [2:0] s_hold_d, s_hold_q;
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_gate_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (gate_i),
      .dat_o  (s_gate_sync)
  );
  ndffr #(
      .DATA_WIDTH(1)
  ) u_gate (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_gate_sync),
      .dat_o  (s_gate_q)
  );
  assign clk_o    = clk_i && !s_gate_q;
  assign gated_o  = s_gate_q;
  assign s_hold_d = s_hold_q < 5 ? s_hold_q + 3'd1 : s_hold_q;
  dffr #(
      .DATA_WIDTH(3)
  ) u_hold (
      .clk_i  (clk_o),
      .rst_n_i(rst_n_i && reset_i),
      .dat_i  (s_hold_d),
      .dat_o  (s_hold_q)
  );
  assign held_o = s_hold_q == 5;
  rst_sync #(
      .STAGE(5)
  ) u_local_reset (
      .clk_i  (clk_o),
      .rst_n_i(rst_n_i && !reset_i),
      .rst_n_o(rst_n_o)
  );
endmodule
