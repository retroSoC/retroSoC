// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_reconstruction_engine (
    // verilog_format: off -- preserve arithmetic operand columns
    input  logic [ 3:0]        opcode_i,
    input  logic [ 7:0]        aux_i,
    input  logic signed [31:0] value0_i,
    input  logic signed [31:0] value1_i,
    input  logic signed [31:0] scale_i,
    input  logic signed [31:0] residual_i,
    input  logic signed [31:0] predictor_shift_i,
    input  logic signed [31:0] history_i [0:31],
    input  logic signed [31:0] coefficient_i [0:31],
    output logic signed [31:0] result0_o,
    output logic signed [31:0] result1_o,
    output logic               overflow_o
    // verilog_format: on
);
  logic signed [71:0] s_accumulator;
  logic signed [63:0] s_value0, s_value1;
  logic signed [63:0] s_product;
  logic signed [63:0] s_predictor;
  logic signed [63:0] s_shifted;
  logic signed [63:0] s_value0_ext, s_value1_ext, s_residual_ext;
  logic signed [71:0] s_lpc_shifted;
  logic signed [72:0] s_lpc_value;
  logic               s_lpc_shift_overflow;
  logic        [ 5:0] s_order;

  function automatic logic signed [63:0] rne(input logic signed [63:0] value_i,
                                             input logic [5:0] shift_i);
    logic signed [63:0] s_magnitude;
    logic signed [63:0] s_quotient;
    logic        [63:0] s_remainder;
    logic        [63:0] s_half;
    begin
      if (shift_i == 6'd0) return value_i;
      s_magnitude = (value_i < 0) ? -value_i : value_i;
      s_quotient  = s_magnitude >>> shift_i;
      s_remainder = s_magnitude & ((64'd1 << shift_i) - 1'b1);
      s_half      = 64'd1 << (shift_i - 1'b1);
      if ((s_remainder > s_half) || ((s_remainder == s_half) && s_quotient[0])) begin
        s_quotient = s_quotient + 1'b1;
      end
      return (value_i < 0) ? -s_quotient : s_quotient;
    end
  endfunction

  function automatic logic signed [31:0] sat32(input logic signed [63:0] value_i);
    if (value_i > 64'sh0000_0000_7fff_ffff) return 32'sh7fff_ffff;
    if (value_i < -64'sh0000_0000_8000_0000) return -32'sh8000_0000;
    return value_i[31:0];
  endfunction

  function automatic logic signed [31:0] sat_width(input logic signed [63:0] value_i,
                                                   input logic [1:0] width_i);
    logic signed [63:0] s_minimum, s_maximum;
    begin
      unique case (width_i)
        2'd0: begin
          s_minimum = -64'sd32768;
          s_maximum = 64'sd32767;
        end
        2'd1: begin
          s_minimum = -64'sd8388608;
          s_maximum = 64'sd8388607;
        end
        default: begin
          s_minimum = -64'sh0000_0000_8000_0000;
          s_maximum = 64'sh0000_0000_7fff_ffff;
        end
      endcase
      if (value_i < s_minimum) return s_minimum[31:0];
      if (value_i > s_maximum) return s_maximum[31:0];
      return value_i[31:0];
    end
  endfunction

  always_comb begin
    s_order       = aux_i[5:0];
    s_accumulator = 72'sd0;
    for (int index = 0; index < 32; index++) begin
      if (index < s_order) begin
        s_accumulator += $signed(coefficient_i[index]) * $signed(history_i[index]);
      end
    end
    s_product      = $signed(value0_i) * $signed(scale_i);
    s_value0_ext   = {{32{value0_i[31]}}, value0_i};
    s_value1_ext   = {{32{value1_i[31]}}, value1_i};
    s_residual_ext = {{32{residual_i[31]}}, residual_i};
    s_predictor    = 64'sd0;
    unique case (aux_i[2:0])
      3'd1: s_predictor = {{32{history_i[0][31]}}, history_i[0]};
      3'd2:
      s_predictor = 64'sd2 * {{32{history_i[0][31]}}, history_i[0]} -
          {{32{history_i[1][31]}}, history_i[1]};
      3'd3:
      s_predictor = 64'sd3 * {{32{history_i[0][31]}}, history_i[0]} -
          64'sd3 * {{32{history_i[1][31]}}, history_i[1]} +
          {{32{history_i[2][31]}}, history_i[2]};
      3'd4:
      s_predictor = 64'sd4 * {{32{history_i[0][31]}}, history_i[0]} -
          64'sd6 * {{32{history_i[1][31]}}, history_i[1]} +
          64'sd4 * {{32{history_i[2][31]}}, history_i[2]} -
          {{32{history_i[3][31]}}, history_i[3]};
      default: s_predictor = 64'sd0;
    endcase
    s_value0 = s_value0_ext;
    s_value1 = s_value1_ext;
    if (predictor_shift_i >= 0) begin
      s_lpc_shifted        = s_accumulator >>> predictor_shift_i[5:0];
      s_lpc_shift_overflow = 1'b0;
    end else begin
      s_lpc_shifted        = s_accumulator <<< (-predictor_shift_i);
      s_lpc_shift_overflow = (s_lpc_shifted >>> (-predictor_shift_i)) != s_accumulator;
    end
    s_shifted   = s_lpc_shifted[63:0];
    s_lpc_value = {s_lpc_shifted[71], s_lpc_shifted} + {{41{residual_i[31]}}, residual_i};
    result0_o   = value0_i;
    result1_o   = value1_i;
    overflow_o  = (s_accumulator[71:63] != {9{s_accumulator[63]}});
    unique case (opcode_i)
      `APB4_APU__MC_KERNEL_REQUANT: begin
        s_shifted = aux_i[5] ?
            rne(s_product, 6'(30 + aux_i[4:0])) : (s_product >>> (30 + aux_i[4:0]));
        result0_o = sat_width(s_shifted, aux_i[7:6]);
      end
      `APB4_APU__MC_KERNEL_STEREO, `APB4_APU__MC_KERNEL_DECORRELATE: begin
        unique case (aux_i[1:0])
          2'd0: begin
            s_value0 = s_value0_ext;
            s_value1 = s_value1_ext;
          end
          2'd1: begin
            s_value0 = s_value0_ext;
            s_value1 = s_value0_ext - s_value1_ext;
          end
          2'd2: begin
            s_value0 = s_value0_ext + s_value1_ext;
            s_value1 = s_value1_ext;
          end
          default: begin
            s_predictor = s_value0_ext * 64'sd2 + (s_value1_ext & 64'sd1);
            s_value0    = (s_predictor + s_value1_ext) >>> 1;
            s_value1    = (s_predictor - s_value1_ext) >>> 1;
          end
        endcase
        overflow_o = (s_value0 > 64'sh0000_0000_7fff_ffff) ||
            (s_value0 < -64'sh0000_0000_8000_0000) ||
            (s_value1 > 64'sh0000_0000_7fff_ffff) ||
            (s_value1 < -64'sh0000_0000_8000_0000);
        result0_o = sat32(s_value0);
        result1_o = sat32(s_value1);
      end
      `APB4_APU__MC_KERNEL_FIXED: begin
        s_value0 = s_predictor + s_residual_ext;
        overflow_o = (s_value0 > 64'sh0000_0000_7fff_ffff) ||
            (s_value0 < -64'sh0000_0000_8000_0000);
        result0_o = s_value0[31:0];
      end
      `APB4_APU__MC_KERNEL_LPC: begin
        overflow_o = overflow_o || s_lpc_shift_overflow ||
            (s_lpc_value > 73'sh0000_0000_7fff_ffff) ||
            (s_lpc_value < -73'sh0000_0000_8000_0000);
        result0_o = s_lpc_value[31:0];
      end
      default: begin
      end
    endcase
  end
endmodule
