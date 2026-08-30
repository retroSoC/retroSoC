// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module soc_clock_gate (
    input  logic clk_i,
    input  logic en_i,
    input  logic test_en_i,
    output logic clk_o
);
  logic s_en_q;

  always_latch begin
    if (!clk_i) begin
      // Intentional low-phase latch for glitch-free clock gating.
      // verilator lint_off COMBDLY
      s_en_q <= en_i || test_en_i;
      // verilator lint_on COMBDLY
    end
  end

  assign clk_o = clk_i && s_en_q;
endmodule
