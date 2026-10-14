// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
module tiny_clock_gate (
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic gate_i,
    output logic clk_o,
    output logic gated_o
);
  logic s_gate_q;
  ndffr #(
      .DATA_WIDTH(1)
  ) u_gate (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (gate_i),
      .dat_o  (s_gate_q)
  );
  assign clk_o   = clk_i && !s_gate_q;
  assign gated_o = s_gate_q;
endmodule
