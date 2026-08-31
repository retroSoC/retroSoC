// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_transform #(
    parameter int unsigned ElementWidth = 24
) (
    // verilog_format: off -- preserve the block-transform interface columns
    input  logic          clk_i,
    input  logic          rst_n_i,
    input  logic          start_i,
    input  logic          inverse_i,
    input  logic [64*ElementWidth-1:0] block_i,
    output logic          start_ready_o,
    output logic [64*ElementWidth-1:0] block_o,
    output logic          result_valid_o,
    input  logic          result_ready_i
    // verilog_format: on
);
  typedef enum logic [1:0] {
    Idle,
    FirstPass,
    SecondPass,
    Result
  } state_e;

  state_e                       s_state_d;
  state_e                       s_state_q;
  logic   [                1:0] s_state_bits_q;
  logic   [                2:0] s_index_d;
  logic   [                2:0] s_index_q;
  logic                         s_inverse_d;
  logic                         s_inverse_q;
  logic   [64*ElementWidth-1:0] s_input_d;
  logic   [64*ElementWidth-1:0] s_input_q;
  logic   [64*ElementWidth-1:0] s_temp_d;
  logic   [64*ElementWidth-1:0] s_temp_q;
  logic   [64*ElementWidth-1:0] s_result_d;
  logic   [64*ElementWidth-1:0] s_result_q;
  logic   [ 8*ElementWidth-1:0] s_vector;

  function automatic logic signed [15:0] cosine_value(input logic [2:0] frequency_i,
                                                      input logic [2:0] sample_i);
    begin
      unique case ({
        frequency_i, sample_i
      })
        6'o00, 6'o01, 6'o02, 6'o03, 6'o04, 6'o05, 6'o06, 6'o07: cosine_value = 16'sd11585;
        6'o10:                                                  cosine_value = 16'sd16069;
        6'o11:                                                  cosine_value = 16'sd13623;
        6'o12:                                                  cosine_value = 16'sd9102;
        6'o13:                                                  cosine_value = 16'sd3196;
        6'o14:                                                  cosine_value = -16'sd3196;
        6'o15:                                                  cosine_value = -16'sd9102;
        6'o16:                                                  cosine_value = -16'sd13623;
        6'o17:                                                  cosine_value = -16'sd16069;
        6'o20:                                                  cosine_value = 16'sd15137;
        6'o21:                                                  cosine_value = 16'sd6270;
        6'o22:                                                  cosine_value = -16'sd6270;
        6'o23:                                                  cosine_value = -16'sd15137;
        6'o24:                                                  cosine_value = -16'sd15137;
        6'o25:                                                  cosine_value = -16'sd6270;
        6'o26:                                                  cosine_value = 16'sd6270;
        6'o27:                                                  cosine_value = 16'sd15137;
        6'o30:                                                  cosine_value = 16'sd13623;
        6'o31:                                                  cosine_value = -16'sd3196;
        6'o32:                                                  cosine_value = -16'sd16069;
        6'o33:                                                  cosine_value = -16'sd9102;
        6'o34:                                                  cosine_value = 16'sd9102;
        6'o35:                                                  cosine_value = 16'sd16069;
        6'o36:                                                  cosine_value = 16'sd3196;
        6'o37:                                                  cosine_value = -16'sd13623;
        6'o40, 6'o43, 6'o44, 6'o47:                             cosine_value = 16'sd11585;
        6'o41, 6'o42, 6'o45, 6'o46:                             cosine_value = -16'sd11585;
        6'o50:                                                  cosine_value = 16'sd9102;
        6'o51:                                                  cosine_value = -16'sd16069;
        6'o52:                                                  cosine_value = 16'sd3196;
        6'o53:                                                  cosine_value = 16'sd13623;
        6'o54:                                                  cosine_value = -16'sd13623;
        6'o55:                                                  cosine_value = -16'sd3196;
        6'o56:                                                  cosine_value = 16'sd16069;
        6'o57:                                                  cosine_value = -16'sd9102;
        6'o60:                                                  cosine_value = 16'sd6270;
        6'o61:                                                  cosine_value = -16'sd15137;
        6'o62:                                                  cosine_value = 16'sd15137;
        6'o63:                                                  cosine_value = -16'sd6270;
        6'o64:                                                  cosine_value = -16'sd6270;
        6'o65:                                                  cosine_value = 16'sd15137;
        6'o66:                                                  cosine_value = -16'sd15137;
        6'o67:                                                  cosine_value = 16'sd6270;
        6'o70:                                                  cosine_value = 16'sd3196;
        6'o71:                                                  cosine_value = -16'sd9102;
        6'o72:                                                  cosine_value = 16'sd13623;
        6'o73:                                                  cosine_value = -16'sd16069;
        6'o74:                                                  cosine_value = 16'sd16069;
        6'o75:                                                  cosine_value = -16'sd13623;
        6'o76:                                                  cosine_value = 16'sd9102;
        6'o77:                                                  cosine_value = -16'sd3196;
        default:                                                cosine_value = 16'sd0;
      endcase
    end
  endfunction

  function automatic logic signed [ElementWidth-1:0] rounded_scale(
      input logic signed [47:0] value_i);
    logic signed [47:0] s_magnitude;
    logic signed [47:0] s_scaled;
    begin
      if (value_i < 48'sd0) begin
        s_magnitude   = -value_i;
        s_scaled      = (s_magnitude + 48'sd16384) >>> 15;
        rounded_scale = -ElementWidth'(s_scaled);
      end else begin
        s_scaled      = (value_i + 48'sd16384) >>> 15;
        rounded_scale = ElementWidth'(s_scaled);
      end
    end
  endfunction

  function automatic logic signed [ElementWidth-1:0] transform_1d(
      input logic [8*ElementWidth-1:0] vector_i, input logic [2:0] output_i, input logic inverse_i);
    logic signed [            47:0] s_accumulator;
    logic signed [ElementWidth-1:0] s_sample;
    logic signed [            15:0] s_cosine;
    begin
      s_accumulator = 48'sd0;
      for (int unsigned index = 0; index < 8; index++) begin
        s_sample = vector_i[index*ElementWidth+:ElementWidth];
        s_cosine = inverse_i ? cosine_value(3'(index), output_i) :
            cosine_value(output_i, 3'(index));
        s_accumulator += s_sample * s_cosine;
      end
      return rounded_scale(s_accumulator);
    end
  endfunction

  assign s_state_q      = state_e'(s_state_bits_q);
  assign start_ready_o  = s_state_q == Idle;
  assign block_o        = s_result_q;
  assign result_valid_o = s_state_q == Result;

  always_comb begin
    s_state_d   = s_state_q;
    s_index_d   = s_index_q;
    s_inverse_d = s_inverse_q;
    s_input_d   = s_input_q;
    s_temp_d    = s_temp_q;
    s_result_d  = s_result_q;
    s_vector    = '0;

    unique case (s_state_q)
      Idle: begin
        s_index_d = 3'd0;
        if (start_i) begin
          s_input_d   = block_i;
          s_inverse_d = inverse_i;
          s_temp_d    = '0;
          s_result_d  = '0;
          s_state_d   = FirstPass;
        end
      end
      FirstPass: begin
        for (int unsigned index = 0; index < 8; index++) begin
          s_vector[index*ElementWidth+:ElementWidth] =
              s_input_q[((s_index_q*8)+index)*ElementWidth+:ElementWidth];
        end
        for (int unsigned output_index = 0; output_index < 8; output_index++) begin
          s_temp_d[((s_index_q*8)+output_index)*ElementWidth+:ElementWidth] =
              transform_1d(s_vector, 3'(output_index), s_inverse_q);
        end
        if (s_index_q == 3'd7) begin
          s_index_d = 3'd0;
          s_state_d = SecondPass;
        end else begin
          s_index_d = s_index_q + 1'b1;
        end
      end
      SecondPass: begin
        for (int unsigned index = 0; index < 8; index++) begin
          s_vector[index*ElementWidth+:ElementWidth] =
              s_temp_q[((index*8)+int'(s_index_q))*ElementWidth+:ElementWidth];
        end
        for (int unsigned output_index = 0; output_index < 8; output_index++) begin
          s_result_d[((output_index*8)+int'(s_index_q))*ElementWidth+:ElementWidth] =
              transform_1d(s_vector, 3'(output_index), s_inverse_q);
        end
        if (s_index_q == 3'd7) begin
          s_index_d = 3'd0;
          s_state_d = Result;
        end else begin
          s_index_d = s_index_q + 1'b1;
        end
      end
      Result: begin
        if (result_ready_i) begin
          s_state_d = Idle;
        end
      end
      default: begin
        s_state_d = Idle;
      end
    endcase
  end

  dffr #(
      .DATA_WIDTH(2)
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_index_d),
      .dat_o  (s_index_q)
  );
  dffr u_inverse_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_inverse_d),
      .dat_o  (s_inverse_q)
  );
  dffr #(
      .DATA_WIDTH(64 * ElementWidth)
  ) u_input_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_input_d),
      .dat_o  (s_input_q)
  );
  dffr #(
      .DATA_WIDTH(64 * ElementWidth)
  ) u_temp_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_temp_d),
      .dat_o  (s_temp_q)
  );
  dffr #(
      .DATA_WIDTH(64 * ElementWidth)
  ) u_result_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_result_d),
      .dat_o  (s_result_q)
  );

`ifndef SV_ASSRT_DISABLE
  always_ff @(posedge clk_i) begin
    if (rst_n_i) begin
      assert (!(start_i && !start_ready_o));
      if (result_valid_o && !result_ready_i) begin
        assert ($stable(block_o));
      end
    end
  end
`endif
endmodule
