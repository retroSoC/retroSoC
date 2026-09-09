// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_resampler (
    input  logic [ 3:0] profile_i,
    input  logic [63:0] next_output_num_i,
    output logic [15:0] ratio_l_o,
    output logic [15:0] ratio_m_o,
    output logic [ 5:0] phase_o,
    output logic [63:0] source_index_o
);
  logic [69:0] s_phase_numerator;
  logic [63:0] s_source_remainder;
  logic [ 5:0] s_phase_quotient;
  logic [15:0] s_phase_remainder;
  logic [16:0] s_phase_remainder_twice;

  always_comb begin
    unique case (profile_i)
      4'd0: begin
        ratio_l_o = 16'd1;
        ratio_m_o = 16'd1;
      end
      4'd1: begin
        ratio_l_o = 16'd1;
        ratio_m_o = 16'd2;
      end
      4'd2: begin
        ratio_l_o = 16'd80;
        ratio_m_o = 16'd147;
      end
      4'd3: begin
        ratio_l_o = 16'd160;
        ratio_m_o = 16'd147;
      end
      4'd4: begin
        ratio_l_o = 16'd3;
        ratio_m_o = 16'd2;
      end
      4'd5: begin
        ratio_l_o = 16'd2;
        ratio_m_o = 16'd1;
      end
      4'd6: begin
        ratio_l_o = 16'd3;
        ratio_m_o = 16'd1;
      end
      4'd7: begin
        ratio_l_o = 16'd4;
        ratio_m_o = 16'd1;
      end
      4'd8: begin
        ratio_l_o = 16'd6;
        ratio_m_o = 16'd1;
      end
      4'd9: begin
        ratio_l_o = 16'd8;
        ratio_m_o = 16'd1;
      end
      4'd10: begin
        ratio_l_o = 16'd12;
        ratio_m_o = 16'd1;
      end
      4'd11: begin
        ratio_l_o = 16'd320;
        ratio_m_o = 16'd147;
      end
      4'd12: begin
        ratio_l_o = 16'd640;
        ratio_m_o = 16'd147;
      end
      4'd13: begin
        ratio_l_o = 16'd1280;
        ratio_m_o = 16'd147;
      end
      4'd14: begin
        ratio_l_o = 16'd2;
        ratio_m_o = 16'd3;
      end
      default: begin
        ratio_l_o = 16'd4;
        ratio_m_o = 16'd3;
      end
    endcase
    source_index_o          = next_output_num_i / {48'd0, ratio_l_o};
    s_source_remainder      = next_output_num_i % {48'd0, ratio_l_o};
    s_phase_numerator       = {6'd0, s_source_remainder} * 70'd32;
    s_phase_quotient        = 6'(s_phase_numerator / {54'd0, ratio_l_o});
    s_phase_remainder       = 16'(s_phase_numerator % {54'd0, ratio_l_o});
    s_phase_remainder_twice = {1'b0, s_phase_remainder} << 1;
    phase_o                 = s_phase_quotient;
    if ((s_phase_remainder_twice > {1'b0, ratio_l_o}) ||
        ((s_phase_remainder_twice == {1'b0, ratio_l_o}) && s_phase_quotient[0])) begin
      phase_o = phase_o + 1'b1;
    end
    if (phase_o == 6'd32) begin
      phase_o        = 6'd0;
      source_index_o = source_index_o + 1'b1;
    end
  end
endmodule
