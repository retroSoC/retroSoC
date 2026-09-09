// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_transform_engine (
    input  logic        [ 5:0] order_i,
    input  logic signed [31:0] sample_i     [0:31],
    input  logic signed [31:0] coefficient_i[0:31],
    output logic signed [31:0] result_o,
    output logic               overflow_o
);
  logic signed [71:0] s_accumulator;
  logic signed [71:0] s_magnitude;
  logic signed [71:0] s_rounded;

  always_comb begin
    s_accumulator = 72'sd0;
    for (int index = 0; index < 32; index++) begin
      if (index < order_i) begin
        s_accumulator += $signed(sample_i[index]) * $signed(coefficient_i[index]);
      end
    end
    s_magnitude = (s_accumulator < 0) ? -s_accumulator : s_accumulator;
    s_rounded = (s_magnitude >>> 30) +
        (((s_magnitude[29:0] > 30'h2000_0000) ||
          ((s_magnitude[29:0] == 30'h2000_0000) && s_magnitude[30])) ? 72'd1 : 72'd0);
    if (s_accumulator < 0) s_rounded = -s_rounded;
    overflow_o = 1'b0;
    if (s_rounded > 72'sh0000_0000_7fff_ffff) result_o = 32'sh7fff_ffff;
    else if (s_rounded < -72'sh0000_0000_8000_0000) result_o = -32'sh8000_0000;
    else result_o = s_rounded[31:0];
  end
endmodule
