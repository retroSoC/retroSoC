// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_quantizer #(
    parameter int unsigned ElementWidth    = 24,
    parameter int unsigned ReciprocalWidth = 25,
    parameter int unsigned ReciprocalShift = 24,
    parameter int unsigned LaneCount       = 4
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

  state_e                       s_state_d;
  state_e                       s_state_q;
  logic   [                1:0] s_state_bits_q;
  logic   [                5:0] s_index_d;
  logic   [                5:0] s_index_q;
  logic   [                5:0] s_process_index;
  logic                         s_dequantize_d;
  logic                         s_dequantize_q;
  logic   [64*ElementWidth-1:0] s_result_q;
  logic   [64*ElementWidth-1:0] s_result_write_data;
  logic   [               63:0] s_result_write_en;
  logic                         s_table_err_d;
  logic                         s_table_err_q;
  logic                         s_overflow_d;
  logic                         s_overflow_q;

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
    s_state_d           = s_state_q;
    s_index_d           = s_index_q;
    s_dequantize_d      = s_dequantize_q;
    s_table_err_d       = s_table_err_q;
    s_overflow_d        = s_overflow_q;
    s_process_index     = s_index_q;
    s_result_write_data = '0;
    s_result_write_en   = '0;

    unique case (s_state_q)
      Idle: begin
        s_index_d = 6'd0;
        if (start_i) begin
          s_index_d       = 6'(LaneCount);
          s_process_index = 6'd0;
          s_dequantize_d  = dequantize_i;
          s_table_err_d   = 1'b0;
          s_overflow_d    = 1'b0;
          s_state_d       = Process;
        end
      end
      Process: begin
        if ((int'(s_index_q) + LaneCount) >= 64) begin
          s_index_d = 6'd0;
          s_state_d = Result;
        end else begin
          s_index_d = s_index_q + 6'(LaneCount);
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

    if ((s_state_q == Process) || ((s_state_q == Idle) && start_i)) begin
      for (int unsigned lane = 0; lane < LaneCount; lane++) begin
        if ((int'(s_process_index) + lane) < 64) begin
          if (quant_i[(int'(s_process_index)+lane)*8+:8] == 8'd0) begin
            s_table_err_d = 1'b1;
          end else if ((s_state_q == Idle) ? dequantize_i : s_dequantize_q) begin
            s_result_write_data[(int'(s_process_index)+lane)*ElementWidth+:ElementWidth] =
                dequantize_value(
              block_i[(int'(s_process_index)+lane)*ElementWidth+:ElementWidth],
              quant_i[(int'(s_process_index)+lane)*8+:8]
            );
            s_result_write_en[int'(s_process_index)+lane] = 1'b1;
            if (product_overflows(
                    block_i[(int'(s_process_index)+lane)*ElementWidth+:ElementWidth],
                    quant_i[(int'(s_process_index)+lane)*8+:8]
                )) begin
              s_overflow_d = 1'b1;
            end
          end else begin
            s_result_write_data[(int'(s_process_index)+lane)*ElementWidth+:ElementWidth] =
                quantize_value(
              block_i[(int'(s_process_index)+lane)*ElementWidth+:ElementWidth],
              quant_i[(int'(s_process_index)+lane)*8+:8],
              reciprocal_i[(int'(s_process_index)+lane)*ReciprocalWidth+:ReciprocalWidth]
            );
            s_result_write_en[int'(s_process_index)+lane] = 1'b1;
          end
        end
      end
    end
  end

  // Every coefficient is overwritten before Result, so the output bank needs no reset.
  for (genvar coefficient = 0; coefficient < 64; coefficient++) begin : gen_result_register
    dffl #(
        .DATA_WIDTH(ElementWidth)
    ) u_result_dffl (
        .clk_i(clk_i),
        .en_i (s_result_write_en[coefficient]),
        .dat_i(s_result_write_data[coefficient*ElementWidth+:ElementWidth]),
        .dat_o(s_result_q[coefficient*ElementWidth+:ElementWidth])
    );
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
      .DATA_WIDTH(6)
  ) u_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_index_d),
      .dat_o  (s_index_q)
  );
  dffr u_dequantize_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dequantize_d),
      .dat_o  (s_dequantize_q)
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
    if (ElementWidth < 16 || ReciprocalWidth <= ReciprocalShift || LaneCount < 1 ||
        LaneCount > 8) begin
      $fatal(1, "jpeg_quantizer: invalid arithmetic widths");
    end
  end
`endif

`ifndef SV_ASSRT_DISABLE
  always_ff @(posedge clk_i) begin
    if (rst_n_i && (s_state_q != Idle)) begin
      assert ($stable(block_i));
      assert ($stable(quant_i));
      assert ($stable(reciprocal_i));
    end
  end
`endif
endmodule
