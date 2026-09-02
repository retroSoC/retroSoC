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
  logic   [64*ElementWidth-1:0] s_data_d;
  logic   [64*ElementWidth-1:0] s_data_q;
  logic   [64*ElementWidth-1:0] s_temp_d;
  logic   [64*ElementWidth-1:0] s_temp_q;
  logic   [ 8*ElementWidth-1:0] s_vector;
  logic   [ 8*ElementWidth-1:0] s_transformed_vector;

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

  function automatic logic [8*ElementWidth-1:0] transform_vector(
      input logic [8*ElementWidth-1:0] vector_i, input logic inverse_i);
    logic signed [  ElementWidth-1:0] s_x      [0:7];
    logic signed [    ElementWidth:0] s_pair   [0:3];
    logic signed [              47:0] s_even   [0:3];
    logic signed [              47:0] s_odd    [0:3];
    logic signed [              47:0] s_value  [0:7];
    logic        [8*ElementWidth-1:0] s_result;
    begin
      for (int unsigned index = 0; index < 8; index++) begin
        s_x[index]     = vector_i[index*ElementWidth+:ElementWidth];
        s_value[index] = 48'sd0;
      end
      if (inverse_i) begin
        s_even[0] = (s_x[0] * 16'sd11585) + (s_x[2] * 16'sd15137) +
                    (s_x[4] * 16'sd11585) + (s_x[6] * 16'sd6270);
        s_even[1] = (s_x[0] * 16'sd11585) + (s_x[2] * 16'sd6270) -
                    (s_x[4] * 16'sd11585) - (s_x[6] * 16'sd15137);
        s_even[2] = (s_x[0] * 16'sd11585) - (s_x[2] * 16'sd6270) -
                    (s_x[4] * 16'sd11585) + (s_x[6] * 16'sd15137);
        s_even[3] = (s_x[0] * 16'sd11585) - (s_x[2] * 16'sd15137) +
                    (s_x[4] * 16'sd11585) - (s_x[6] * 16'sd6270);
        s_odd[0] = (s_x[1] * 16'sd16069) + (s_x[3] * 16'sd13623) +
                   (s_x[5] * 16'sd9102) + (s_x[7] * 16'sd3196);
        s_odd[1] = (s_x[1] * 16'sd13623) - (s_x[3] * 16'sd3196) -
                   (s_x[5] * 16'sd16069) - (s_x[7] * 16'sd9102);
        s_odd[2] = (s_x[1] * 16'sd9102) - (s_x[3] * 16'sd16069) +
                   (s_x[5] * 16'sd3196) + (s_x[7] * 16'sd13623);
        s_odd[3] = (s_x[1] * 16'sd3196) - (s_x[3] * 16'sd9102) +
                   (s_x[5] * 16'sd13623) - (s_x[7] * 16'sd16069);
        for (int unsigned index = 0; index < 4; index++) begin
          s_value[index]   = s_even[index] + s_odd[index];
          s_value[7-index] = s_even[index] - s_odd[index];
        end
      end else begin
        for (int unsigned index = 0; index < 4; index++) begin
          s_pair[index] = s_x[index] + s_x[7-index];
        end
        s_value[0] = (s_pair[0] + s_pair[1] + s_pair[2] + s_pair[3]) * 16'sd11585;
        s_value[2] = ((s_pair[0] - s_pair[3]) * 16'sd15137) + ((s_pair[1] - s_pair[2]) * 16'sd6270);
        s_value[4] = (s_pair[0] - s_pair[1] - s_pair[2] + s_pair[3]) * 16'sd11585;
        s_value[6] = ((s_pair[0] - s_pair[3]) * 16'sd6270) - ((s_pair[1] - s_pair[2]) * 16'sd15137);
        for (int unsigned index = 0; index < 4; index++) begin
          s_pair[index] = s_x[index] - s_x[7-index];
        end
        s_value[1] = (s_pair[0] * 16'sd16069) + (s_pair[1] * 16'sd13623) +
                     (s_pair[2] * 16'sd9102) + (s_pair[3] * 16'sd3196);
        s_value[3] = (s_pair[0] * 16'sd13623) - (s_pair[1] * 16'sd3196) -
                     (s_pair[2] * 16'sd16069) - (s_pair[3] * 16'sd9102);
        s_value[5] = (s_pair[0] * 16'sd9102) - (s_pair[1] * 16'sd16069) +
                     (s_pair[2] * 16'sd3196) + (s_pair[3] * 16'sd13623);
        s_value[7] = (s_pair[0] * 16'sd3196) - (s_pair[1] * 16'sd9102) +
                     (s_pair[2] * 16'sd13623) - (s_pair[3] * 16'sd16069);
      end
      s_result = '0;
      for (int unsigned index = 0; index < 8; index++) begin
        s_result[index*ElementWidth+:ElementWidth] = rounded_scale(s_value[index]);
      end
      return s_result;
    end
  endfunction

  assign s_state_q      = state_e'(s_state_bits_q);
  assign start_ready_o  = s_state_q == Idle;
  assign block_o        = s_data_q;
  assign result_valid_o = s_state_q == Result;

  always_comb begin
    s_state_d            = s_state_q;
    s_index_d            = s_index_q;
    s_inverse_d          = s_inverse_q;
    s_data_d             = s_data_q;
    s_temp_d             = s_temp_q;
    s_vector             = '0;
    s_transformed_vector = transform_vector(s_vector, s_inverse_q);

    unique case (s_state_q)
      Idle: begin
        s_index_d = 3'd0;
        if (start_i) begin
          s_data_d    = block_i;
          s_inverse_d = inverse_i;
          s_temp_d    = '0;
          s_state_d   = FirstPass;
        end
      end
      FirstPass: begin
        for (int unsigned index = 0; index < 8; index++) begin
          s_vector[index*ElementWidth+:ElementWidth] =
              s_data_q[((s_index_q*8)+index)*ElementWidth+:ElementWidth];
        end
        s_transformed_vector = transform_vector(s_vector, s_inverse_q);
        for (int unsigned output_index = 0; output_index < 8; output_index++) begin
          s_temp_d[((s_index_q*8)+output_index)*ElementWidth+:ElementWidth] =
              s_transformed_vector[output_index*ElementWidth+:ElementWidth];
        end
        if (s_index_q == 3'd7) begin
          s_index_d = 3'd0;
          s_data_d  = '0;
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
        s_transformed_vector = transform_vector(s_vector, s_inverse_q);
        for (int unsigned output_index = 0; output_index < 8; output_index++) begin
          s_data_d[((output_index*8)+int'(s_index_q))*ElementWidth+:ElementWidth] =
              s_transformed_vector[output_index*ElementWidth+:ElementWidth];
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
  ) u_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_data_d),
      .dat_o  (s_data_q)
  );
  dffr #(
      .DATA_WIDTH(64 * ElementWidth)
  ) u_temp_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_temp_d),
      .dat_o  (s_temp_q)
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
