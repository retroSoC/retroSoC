// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_block_decoder #(
    parameter int unsigned ElementWidth              = 24,
    parameter int unsigned WindowWidth               = 32,
    parameter bit          ExternalCoefficientEngine = 1'b0
) (
    // verilog_format: off -- preserve command, table, bit-window, and block columns
    input  logic                                  clk_i,
    input  logic                                  rst_n_i,
    input  logic                                  start_i,
    input  logic signed [ElementWidth-1:0]         previous_dc_i,
    input  logic [64*8-1:0]                       quant_i,
    input  logic [64*25-1:0]                      reciprocal_i,
    input  logic [12*16-1:0]                      dc_code_i,
    input  logic [12*5-1:0]                       dc_length_i,
    input  logic [256*16-1:0]                     ac_code_i,
    input  logic [256*5-1:0]                      ac_length_i,
    input  logic [WindowWidth-1:0]                bit_window_i,
    input  logic [$clog2(WindowWidth+1)-1:0]      bit_count_i,
    output logic                                  coefficient_start_o,
    output logic [64*ElementWidth-1:0]            coefficient_block_o,
    input  logic                                  coefficient_start_ready_i,
    input  logic [64*ElementWidth-1:0]            coefficient_result_i,
    input  logic                                  coefficient_result_valid_i,
    output logic                                  coefficient_result_ready_o,
    input  logic                                  coefficient_table_err_i,
    input  logic                                  coefficient_overflow_i,
    output logic [$clog2(WindowWidth+1)-1:0]      bit_consume_o,
    output logic                                  bit_consume_valid_o,
    output logic                                  start_ready_o,
    output logic [64*8-1:0]                       block_o,
    output logic signed [ElementWidth-1:0]         dc_o,
    output logic                                  result_valid_o,
    input  logic                                  result_ready_i,
    output logic                                  error_o
    // verilog_format: on
);
  typedef enum logic [2:0] {
    Idle,
    Entropy,
    Dequantize,
    Transform,
    Result
  } state_e;

  state_e                            s_state_d;
  state_e                            s_state_q;
  logic        [                2:0] s_state_bits_q;
  logic signed [   ElementWidth-1:0] s_dc_d;
  logic signed [   ElementWidth-1:0] s_dc_q;
  logic        [           64*8-1:0] s_block_d;
  logic        [           64*8-1:0] s_block_q;
  logic                              s_err_d;
  logic                              s_err_q;
  logic                              s_entropy_start;
  logic                              s_entropy_ready;
  logic        [64*ElementWidth-1:0] s_entropy_block;
  logic signed [   ElementWidth-1:0] s_entropy_dc;
  logic                              s_entropy_valid;
  logic                              s_entropy_err;
  logic                              s_quant_start;
  logic                              s_quant_ready;
  logic        [64*ElementWidth-1:0] s_quant_block;
  logic                              s_quant_valid;
  logic                              s_quant_err;
  logic                              s_quant_overflow;
  logic                              s_transform_start;
  logic                              s_transform_ready;
  logic        [64*ElementWidth-1:0] s_transform_block;
  logic                              s_transform_valid;
  logic        [           64*8-1:0] s_clamped_block;

  function automatic logic [7:0] clamp_sample(input logic signed [ElementWidth-1:0] value_i);
    logic signed [ElementWidth:0] s_shifted;
    begin
      s_shifted = value_i + 128;
      if (s_shifted < 0) begin
        return 8'd0;
      end
      if (s_shifted > 255) begin
        return 8'd255;
      end
      return s_shifted[7:0];
    end
  endfunction

  assign s_state_q = state_e'(s_state_bits_q);
  assign start_ready_o = s_state_q == Idle;
  assign block_o = s_block_q;
  assign dc_o = s_dc_q;
  assign result_valid_o = s_state_q == Result;
  assign error_o = s_err_q;
  assign s_entropy_start = (s_state_q == Idle) && start_i;
  assign s_entropy_ready = (s_state_q == Entropy) &&
                           (!ExternalCoefficientEngine || coefficient_start_ready_i);
  assign s_quant_start = (s_state_q == Entropy) && s_entropy_valid;
  assign s_quant_ready = s_state_q == Dequantize;
  assign s_transform_start = (s_state_q == Dequantize) && s_quant_valid;
  assign s_transform_ready = s_state_q == Transform;
  assign coefficient_start_o = ExternalCoefficientEngine && (s_state_q == Entropy) &&
                               s_entropy_valid;
  assign coefficient_block_o = s_entropy_block;
  assign coefficient_result_ready_o = ExternalCoefficientEngine && (s_state_q == Transform);

  always_comb begin
    for (int unsigned index = 0; index < 64; index++) begin
      s_clamped_block[index*8+:8] =
          clamp_sample(s_transform_block[index*ElementWidth+:ElementWidth]);
    end
  end

  always_comb begin
    s_state_d = s_state_q;
    s_dc_d    = s_dc_q;
    s_block_d = s_block_q;
    s_err_d   = s_err_q;
    unique case (s_state_q)
      Idle: begin
        if (start_i) begin
          s_err_d   = 1'b0;
          s_state_d = Entropy;
        end
      end
      Entropy: begin
        if (s_entropy_valid && (!ExternalCoefficientEngine || coefficient_start_ready_i)) begin
          s_dc_d = s_entropy_dc;
          s_err_d |= s_entropy_err;
          s_state_d = ExternalCoefficientEngine ? Transform : Dequantize;
        end
      end
      Dequantize: begin
        if (s_quant_valid) begin
          s_err_d |= s_quant_err || s_quant_overflow;
          s_state_d = Transform;
        end
      end
      Transform: begin
        if (s_transform_valid) begin
          s_block_d = s_clamped_block;
          if (ExternalCoefficientEngine) begin
            s_err_d |= coefficient_table_err_i || coefficient_overflow_i;
          end
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

  jpeg_entropy_decoder #(
      .ElementWidth(ElementWidth),
      .WindowWidth (WindowWidth)
  ) u_entropy_decoder (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .start_i            (s_entropy_start),
      .previous_dc_i      (previous_dc_i),
      .dc_code_i          (dc_code_i),
      .dc_length_i        (dc_length_i),
      .ac_code_i          (ac_code_i),
      .ac_length_i        (ac_length_i),
      .bit_window_i       (bit_window_i),
      .bit_count_i        (bit_count_i),
      .bit_consume_o      (bit_consume_o),
      .bit_consume_valid_o(bit_consume_valid_o),
      .start_ready_o      (),
      .block_o            (s_entropy_block),
      .dc_o               (s_entropy_dc),
      .result_valid_o     (s_entropy_valid),
      .result_ready_i     (s_entropy_ready),
      .error_o            (s_entropy_err)
  );

  if (ExternalCoefficientEngine) begin : gen_external_coefficient_engine
    assign s_quant_block     = '0;
    assign s_quant_valid     = 1'b0;
    assign s_quant_err       = 1'b0;
    assign s_quant_overflow  = 1'b0;
    assign s_transform_block = coefficient_result_i;
    assign s_transform_valid = coefficient_result_valid_i;
  end else begin : gen_internal_coefficient_engine
    jpeg_quantizer #(
        .ElementWidth(ElementWidth)
    ) u_dequantizer (
        .clk_i         (clk_i),
        .rst_n_i       (rst_n_i),
        .start_i       (s_quant_start),
        .dequantize_i  (1'b1),
        .block_i       (s_entropy_block),
        .quant_i       (quant_i),
        .reciprocal_i  (reciprocal_i),
        .start_ready_o (),
        .block_o       (s_quant_block),
        .result_valid_o(s_quant_valid),
        .result_ready_i(s_quant_ready),
        .table_err_o   (s_quant_err),
        .overflow_o    (s_quant_overflow)
    );

    jpeg_transform #(
        .ElementWidth(ElementWidth)
    ) u_inverse_transform (
        .clk_i         (clk_i),
        .rst_n_i       (rst_n_i),
        .start_i       (s_transform_start),
        .inverse_i     (1'b1),
        .block_i       (s_quant_block),
        .start_ready_o (),
        .block_o       (s_transform_block),
        .result_valid_o(s_transform_valid),
        .result_ready_i(s_transform_ready)
    );
  end

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
  dffr #(
      .DATA_WIDTH(64 * 8)
  ) u_block_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_block_d),
      .dat_o  (s_block_q)
  );
  dffr u_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
endmodule
