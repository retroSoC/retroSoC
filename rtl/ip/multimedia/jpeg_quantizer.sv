// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_quantizer #(
    parameter int unsigned ElementWidth    = 24,
    parameter int unsigned ReciprocalWidth = 25,
    parameter int unsigned ReciprocalShift = 24
) (
    // verilog_format: off -- preserve the block and table interface columns
    input  logic                            clk_i,
    input  logic                            rst_n_i,
    input  logic                            start_i,
    input  logic                            dequantize_i,
    input  logic [64*ElementWidth-1:0]      block_i,
    input  logic [64*8-1:0]                 quant_i,
    input  logic [64*ReciprocalWidth-1:0]   reciprocal_i,
    output logic                            start_ready_o,
    output logic [64*ElementWidth-1:0]      block_o,
    output logic                            result_valid_o,
    input  logic                            result_ready_i,
    output logic                            table_err_o,
    output logic                            overflow_o
    // verilog_format: on
);
  typedef enum logic [1:0] {
    Idle,
    Process,
    Result
  } state_e;

  state_e                          s_state_d;
  state_e                          s_state_q;
  logic   [                   1:0] s_state_bits_q;
  logic   [                   2:0] s_group_d;
  logic   [                   2:0] s_group_q;
  logic                            s_dequantize_d;
  logic                            s_dequantize_q;
  logic   [   64*ElementWidth-1:0] s_input_d;
  logic   [   64*ElementWidth-1:0] s_input_q;
  logic   [              64*8-1:0] s_quant_d;
  logic   [              64*8-1:0] s_quant_q;
  logic   [64*ReciprocalWidth-1:0] s_reciprocal_d;
  logic   [64*ReciprocalWidth-1:0] s_reciprocal_q;
  logic   [   64*ElementWidth-1:0] s_result_d;
  logic   [   64*ElementWidth-1:0] s_result_q;
  logic                            s_table_err_d;
  logic                            s_table_err_q;
  logic                            s_overflow_d;
  logic                            s_overflow_q;

  function automatic logic signed [ElementWidth-1:0] quantize_value(
      input logic signed [ElementWidth-1:0] value_i, input logic [7:0] quant_i,
      input logic [ReciprocalWidth-1:0] reciprocal_i);
    logic [                ElementWidth:0] s_magnitude;
    logic [                ElementWidth:0] s_numerator;
    logic [ElementWidth+ReciprocalWidth:0] s_scaled;
    logic [                ElementWidth:0] s_estimate;
    logic [              ElementWidth+8:0] s_product;
    begin
      if (value_i < 0) begin
        s_magnitude = {1'b0, ElementWidth'(-value_i)};
      end else begin
        s_magnitude = {1'b0, value_i};
      end
      s_numerator = s_magnitude + (ElementWidth + 1)'({1'b0, quant_i[7:1]});
      s_scaled    = s_numerator * reciprocal_i;
      s_estimate  = (ElementWidth + 1)'(s_scaled >> ReciprocalShift);
      s_product   = s_estimate * quant_i;
      if (s_product > (ElementWidth + 9)'(s_numerator)) begin
        s_estimate -= 1'b1;
      end else if (((s_estimate + 1'b1) * quant_i) <= s_numerator) begin
        s_estimate += 1'b1;
      end
      quantize_value = (value_i < 0) ? -ElementWidth'(s_estimate) : ElementWidth'(s_estimate);
    end
  endfunction

  function automatic logic signed [ElementWidth-1:0] dequantize_value(
      input logic signed [ElementWidth-1:0] value_i, input logic [7:0] quant_i);
    logic signed [ElementWidth+8-1:0] s_product;
    begin
      s_product = value_i * $signed({1'b0, quant_i});
      return ElementWidth'(s_product);
    end
  endfunction

  function automatic logic product_overflows(input logic signed [ElementWidth-1:0] value_i,
                                             input logic [7:0] quant_i);
    logic signed [ElementWidth+8-1:0] s_product;
    logic signed [  ElementWidth-1:0] s_truncated;
    begin
      s_product   = value_i * $signed({1'b0, quant_i});
      s_truncated = ElementWidth'(s_product);
      return s_product != {{8{s_truncated[ElementWidth-1]}}, s_truncated};
    end
  endfunction

  assign s_state_q      = state_e'(s_state_bits_q);
  assign start_ready_o  = s_state_q == Idle;
  assign block_o        = s_result_q;
  assign result_valid_o = s_state_q == Result;
  assign table_err_o    = s_table_err_q;
  assign overflow_o     = s_overflow_q;

  always_comb begin
    s_state_d      = s_state_q;
    s_group_d      = s_group_q;
    s_dequantize_d = s_dequantize_q;
    s_input_d      = s_input_q;
    s_quant_d      = s_quant_q;
    s_reciprocal_d = s_reciprocal_q;
    s_result_d     = s_result_q;
    s_table_err_d  = s_table_err_q;
    s_overflow_d   = s_overflow_q;

    unique case (s_state_q)
      Idle: begin
        s_group_d = 3'd0;
        if (start_i) begin
          s_dequantize_d = dequantize_i;
          s_input_d      = block_i;
          s_quant_d      = quant_i;
          s_reciprocal_d = reciprocal_i;
          s_result_d     = '0;
          s_table_err_d  = 1'b0;
          s_overflow_d   = 1'b0;
          s_state_d      = Process;
        end
      end
      Process: begin
        for (int unsigned lane = 0; lane < 8; lane++) begin
          if (s_quant_q[((s_group_q*8)+lane)*8+:8] == 8'd0) begin
            s_table_err_d = 1'b1;
          end else if (s_dequantize_q) begin
            s_result_d[((s_group_q*8)+lane)*ElementWidth+:ElementWidth] = dequantize_value(
              s_input_q[((s_group_q*8)+lane)*ElementWidth+:ElementWidth],
              s_quant_q[((s_group_q*8)+lane)*8+:8]
            );
            if (product_overflows(
                    s_input_q[((s_group_q*8)+lane)*ElementWidth+:ElementWidth],
                    s_quant_q[((s_group_q*8)+lane)*8+:8]
                )) begin
              s_overflow_d = 1'b1;
            end
          end else begin
            s_result_d[((s_group_q*8)+lane)*ElementWidth+:ElementWidth] = quantize_value(
              s_input_q[((s_group_q*8)+lane)*ElementWidth+:ElementWidth],
              s_quant_q[((s_group_q*8)+lane)*8+:8],
              s_reciprocal_q[((s_group_q*8)+lane)*ReciprocalWidth+:ReciprocalWidth]
            );
          end
        end
        if (s_group_q == 3'd7) begin
          s_group_d = 3'd0;
          s_state_d = Result;
        end else begin
          s_group_d = s_group_q + 1'b1;
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
  ) u_group_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_group_d),
      .dat_o  (s_group_q)
  );
  dffr u_dequantize_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dequantize_d),
      .dat_o  (s_dequantize_q)
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
      .DATA_WIDTH(64 * 8)
  ) u_quant_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_quant_d),
      .dat_o  (s_quant_q)
  );
  dffr #(
      .DATA_WIDTH(64 * ReciprocalWidth)
  ) u_reciprocal_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_reciprocal_d),
      .dat_o  (s_reciprocal_q)
  );
  dffr #(
      .DATA_WIDTH(64 * ElementWidth)
  ) u_result_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_result_d),
      .dat_o  (s_result_q)
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

`ifndef SYNTHESIS
  initial begin
    if (ElementWidth < 16 || ReciprocalWidth <= ReciprocalShift) begin
      $fatal(1, "jpeg_quantizer: invalid arithmetic widths");
    end
  end
`endif
endmodule
