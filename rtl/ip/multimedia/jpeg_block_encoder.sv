// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_block_encoder #(
    parameter int unsigned ElementWidth = 24,
    parameter int unsigned TokenSlots   = 4,
    parameter int unsigned TokenWidth   = 32
) (
    // verilog_format: off -- preserve command, table, token, and block columns
    input  logic                                  clk_i,
    input  logic                                  rst_n_i,
    input  logic                                  start_i,
    input  logic [64*8-1:0]                       block_i,
    input  logic signed [ElementWidth-1:0]         previous_dc_i,
    input  logic [64*8-1:0]                       quant_i,
    input  logic [64*25-1:0]                      reciprocal_i,
    input  logic [12*16-1:0]                      dc_code_i,
    input  logic [12*5-1:0]                       dc_length_i,
    input  logic [256*16-1:0]                     ac_code_i,
    input  logic [256*5-1:0]                      ac_length_i,
    output logic                                  start_ready_o,
    output logic [TokenSlots*TokenWidth-1:0]      token_bits_o,
    output logic [TokenSlots*6-1:0]               token_length_o,
    output logic [$clog2(TokenSlots+1)-1:0]        token_count_o,
    output logic                                  token_valid_o,
    output logic                                  token_last_o,
    input  logic                                  token_ready_i,
    output logic signed [ElementWidth-1:0]         dc_o,
    output logic                                  result_valid_o,
    input  logic                                  result_ready_i,
    output logic                                  error_o
    // verilog_format: on
);
  typedef enum logic [2:0] {
    Idle,
    Transform,
    Quantize,
    Entropy,
    Result
  } state_e;

  state_e                            s_state_d;
  state_e                            s_state_q;
  logic        [                2:0] s_state_bits_q;
  logic signed [   ElementWidth-1:0] s_dc_d;
  logic signed [   ElementWidth-1:0] s_dc_q;
  logic                              s_err_d;
  logic                              s_err_q;
  logic        [64*ElementWidth-1:0] s_level_shifted;
  logic                              s_transform_start;
  logic                              s_transform_ready;
  logic        [64*ElementWidth-1:0] s_transform_block;
  logic                              s_transform_valid;
  logic                              s_quant_start;
  logic                              s_quant_ready;
  logic        [64*ElementWidth-1:0] s_quant_block;
  logic                              s_quant_valid;
  logic                              s_quant_err;
  logic                              s_quant_overflow;
  logic                              s_entropy_start;
  logic signed [   ElementWidth-1:0] s_entropy_dc;
  logic                              s_entropy_err;
  logic                              s_entropy_last_accept;

  always_comb begin
    for (int unsigned index = 0; index < 64; index++) begin
      s_level_shifted[index*ElementWidth+:ElementWidth] =
          $signed(ElementWidth'({1'b0, block_i[index*8+:8]})) - ElementWidth'(128);
    end
  end

  assign s_state_q = state_e'(s_state_bits_q);
  assign start_ready_o = s_state_q == Idle;
  assign result_valid_o = s_state_q == Result;
  assign dc_o = s_dc_q;
  assign error_o = s_err_q;
  assign s_transform_start = (s_state_q == Idle) && start_i;
  assign s_transform_ready = s_state_q == Transform;
  assign s_quant_start = (s_state_q == Transform) && s_transform_valid;
  assign s_quant_ready = s_state_q == Quantize;
  assign s_entropy_start = (s_state_q == Quantize) && s_quant_valid;
  assign s_entropy_last_accept = (s_state_q == Entropy) && token_valid_o && token_ready_i &&
                                 token_last_o;

  always_comb begin
    s_state_d = s_state_q;
    s_dc_d    = s_dc_q;
    s_err_d   = s_err_q;
    unique case (s_state_q)
      Idle: begin
        if (start_i) begin
          s_err_d   = 1'b0;
          s_state_d = Transform;
        end
      end
      Transform: begin
        if (s_transform_valid) begin
          s_state_d = Quantize;
        end
      end
      Quantize: begin
        if (s_quant_valid) begin
          s_err_d |= s_quant_err || s_quant_overflow;
          s_state_d = Entropy;
        end
      end
      Entropy: begin
        if (s_entropy_last_accept) begin
          s_dc_d = s_entropy_dc;
          s_err_d |= s_entropy_err;
          s_state_d = Result;
        end
      end
      Result: begin
        if (result_ready_i) begin
          s_state_d = Idle;
        end
      end
      default: s_state_d = Idle;
    endcase
  end

  jpeg_transform #(
      .ElementWidth(ElementWidth)
  ) u_forward_transform (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .start_i       (s_transform_start),
      .inverse_i     (1'b0),
      .block_i       (s_level_shifted),
      .start_ready_o (),
      .block_o       (s_transform_block),
      .result_valid_o(s_transform_valid),
      .result_ready_i(s_transform_ready)
  );

  jpeg_quantizer #(
      .ElementWidth(ElementWidth)
  ) u_quantizer (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .start_i       (s_quant_start),
      .dequantize_i  (1'b0),
      .block_i       (s_transform_block),
      .quant_i       (quant_i),
      .reciprocal_i  (reciprocal_i),
      .start_ready_o (),
      .block_o       (s_quant_block),
      .result_valid_o(s_quant_valid),
      .result_ready_i(s_quant_ready),
      .table_err_o   (s_quant_err),
      .overflow_o    (s_quant_overflow)
  );

  jpeg_entropy_encoder #(
      .ElementWidth(ElementWidth),
      .TokenSlots  (TokenSlots),
      .TokenWidth  (TokenWidth)
  ) u_entropy_encoder (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .start_i       (s_entropy_start),
      .block_i       (s_quant_block),
      .previous_dc_i (previous_dc_i),
      .dc_code_i     (dc_code_i),
      .dc_length_i   (dc_length_i),
      .ac_code_i     (ac_code_i),
      .ac_length_i   (ac_length_i),
      .start_ready_o (),
      .dc_o          (s_entropy_dc),
      .token_bits_o  (token_bits_o),
      .token_length_o(token_length_o),
      .token_count_o (token_count_o),
      .token_valid_o (token_valid_o),
      .token_last_o  (token_last_o),
      .token_ready_i (token_ready_i),
      .error_o       (s_entropy_err)
  );

  dffr #(
      .DATA_WIDTH(3)
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(ElementWidth)
  ) u_dc_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dc_d),
      .dat_o  (s_dc_q)
  );
  dffr u_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
endmodule
