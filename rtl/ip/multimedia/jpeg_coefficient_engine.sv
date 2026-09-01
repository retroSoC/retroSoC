// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_coefficient_engine #(
    parameter int unsigned ElementWidth = 24
) (
    // verilog_format: off -- preserve request, table, and result interface columns
    input  logic                             clk_i,
    input  logic                             rst_n_i,
    input  logic                             start_i,
    input  logic                             decode_i,
    input  logic [64*ElementWidth-1:0]       block_i,
    input  logic [64*8-1:0]                  quant_i,
    input  logic [64*25-1:0]                 reciprocal_i,
    output logic                             start_ready_o,
    output logic [64*ElementWidth-1:0]       block_o,
    output logic                             result_valid_o,
    input  logic                             result_ready_i,
    output logic                             table_err_o,
    output logic                             overflow_o
    // verilog_format: on
);
  typedef enum logic [2:0] {
    Idle,
    EncodeTransform,
    EncodeQuantize,
    DecodeDequantize,
    DecodeTransform,
    Result
  } state_e;

  state_e                       s_state_d;
  state_e                       s_state_q;
  logic   [                2:0] s_state_bits_q;
  logic                         s_decode_d;
  logic                         s_decode_q;
  logic                         s_active_decode;
  logic                         s_table_err_d;
  logic                         s_table_err_q;
  logic                         s_overflow_d;
  logic                         s_overflow_q;
  logic                         s_transform_start;
  logic                         s_transform_ready;
  logic   [64*ElementWidth-1:0] s_transform_input;
  logic   [64*ElementWidth-1:0] s_transform_result;
  logic                         s_transform_valid;
  logic                         s_quant_start;
  logic                         s_quant_ready;
  logic   [64*ElementWidth-1:0] s_quant_input;
  logic   [64*ElementWidth-1:0] s_quant_result;
  logic                         s_quant_valid;
  logic                         s_quant_table_err;
  logic                         s_quant_overflow;

  assign s_state_q = state_e'(s_state_bits_q);
  assign start_ready_o = s_state_q == Idle;
  assign result_valid_o = s_state_q == Result;
  assign block_o = s_decode_q ? s_transform_result : s_quant_result;
  assign table_err_o = s_table_err_q;
  assign overflow_o = s_overflow_q;
  assign s_active_decode = (s_state_q == Idle) ? decode_i : s_decode_q;
  assign s_transform_start = ((s_state_q == Idle) && start_i && !decode_i) ||
                             ((s_state_q == DecodeDequantize) && s_quant_valid);
  assign s_transform_ready = (s_state_q == EncodeTransform) || (s_state_q == DecodeTransform);
  assign s_transform_input = s_active_decode ? s_quant_result : block_i;
  assign s_quant_start = ((s_state_q == Idle) && start_i && decode_i) ||
                         ((s_state_q == EncodeTransform) && s_transform_valid);
  assign s_quant_ready = (s_state_q == EncodeQuantize) || (s_state_q == DecodeDequantize);
  assign s_quant_input = s_active_decode ? block_i : s_transform_result;

  always_comb begin
    s_state_d     = s_state_q;
    s_decode_d    = s_decode_q;
    s_table_err_d = s_table_err_q;
    s_overflow_d  = s_overflow_q;
    unique case (s_state_q)
      Idle: begin
        if (start_i) begin
          s_decode_d    = decode_i;
          s_table_err_d = 1'b0;
          s_overflow_d  = 1'b0;
          if (decode_i) begin
            s_state_d = DecodeDequantize;
          end else begin
            s_state_d = EncodeTransform;
          end
        end
      end
      EncodeTransform: begin
        if (s_transform_valid) begin
          s_state_d = EncodeQuantize;
        end
      end
      EncodeQuantize: begin
        if (s_quant_valid) begin
          s_table_err_d |= s_quant_table_err;
          s_overflow_d |= s_quant_overflow;
          s_state_d = Result;
        end
      end
      DecodeDequantize: begin
        if (s_quant_valid) begin
          s_table_err_d |= s_quant_table_err;
          s_overflow_d |= s_quant_overflow;
          s_state_d = DecodeTransform;
        end
      end
      DecodeTransform: begin
        if (s_transform_valid) begin
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
  ) u_transform (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .start_i       (s_transform_start),
      .inverse_i     (s_decode_q),
      .block_i       (s_transform_input),
      .start_ready_o (),
      .block_o       (s_transform_result),
      .result_valid_o(s_transform_valid),
      .result_ready_i(s_transform_ready)
  );

  jpeg_quantizer #(
      .ElementWidth(ElementWidth)
  ) u_quantizer (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .start_i       (s_quant_start),
      .dequantize_i  (s_active_decode),
      .block_i       (s_quant_input),
      .quant_i       (quant_i),
      .reciprocal_i  (reciprocal_i),
      .start_ready_o (),
      .block_o       (s_quant_result),
      .result_valid_o(s_quant_valid),
      .result_ready_i(s_quant_ready),
      .table_err_o   (s_quant_table_err),
      .overflow_o    (s_quant_overflow)
  );

  dffr #(
      .DATA_WIDTH(3)
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr u_decode_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_decode_d),
      .dat_o  (s_decode_q)
  );
  dffr u_table_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_table_err_d),
      .dat_o  (s_table_err_q)
  );
  dffr u_overflow_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_overflow_d),
      .dat_o  (s_overflow_q)
  );

`ifndef SV_ASSRT_DISABLE
  always_ff @(posedge clk_i) begin
    if (rst_n_i && (s_state_q != Idle)) begin
      assert ($stable(quant_i));
      assert ($stable(reciprocal_i));
    end
  end
`endif
endmodule
