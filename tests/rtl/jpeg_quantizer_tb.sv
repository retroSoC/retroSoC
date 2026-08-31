// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module jpeg_quantizer_tb;
  logic          clk;
  logic          rst_n;
  logic          start;
  logic          dequantize;
  logic [1535:0] block_in;
  logic [ 511:0] quant;
  logic [1599:0] reciprocal;
  logic          start_ready;
  logic [1535:0] block_out;
  logic          result_valid;
  logic          result_ready;
  logic          table_err;
  logic          overflow;

  jpeg_quantizer u_dut (
      .clk_i         (clk),
      .rst_n_i       (rst_n),
      .start_i       (start),
      .dequantize_i  (dequantize),
      .block_i       (block_in),
      .quant_i       (quant),
      .reciprocal_i  (reciprocal),
      .start_ready_o (start_ready),
      .block_o       (block_out),
      .result_valid_o(result_valid),
      .result_ready_i(result_ready),
      .table_err_o   (table_err),
      .overflow_o    (overflow)
  );

  always #5 clk = ~clk;

  function automatic logic [7:0] luma_quant(input int index_i);
    logic [7:0] values[0:63];
    begin
      values = '{
          16,
          11,
          10,
          16,
          24,
          40,
          51,
          61,
          12,
          12,
          14,
          19,
          26,
          58,
          60,
          55,
          14,
          13,
          16,
          24,
          40,
          57,
          69,
          56,
          14,
          17,
          22,
          29,
          51,
          87,
          80,
          62,
          18,
          22,
          37,
          56,
          68,
          109,
          103,
          77,
          24,
          35,
          55,
          64,
          81,
          104,
          113,
          92,
          49,
          64,
          78,
          87,
          103,
          121,
          120,
          101,
          72,
          92,
          95,
          98,
          112,
          100,
          103,
          99
      };
      return values[index_i];
    end
  endfunction

  function automatic logic signed [23:0] coefficient(input int index_i);
    begin
      case (index_i)
        0:       coefficient = -24'sd4;
        1:       coefficient = -24'sd17;
        3:       coefficient = -24'sd3;
        8:       coefficient = -24'sd146;
        24:      coefficient = -24'sd15;
        40:      coefficient = -24'sd5;
        56:      coefficient = -24'sd1;
        default: coefficient = 24'sd0;
      endcase
    end
  endfunction

  function automatic logic signed [23:0] quantized(input int index_i);
    begin
      case (index_i)
        1:       quantized = -24'sd2;
        8:       quantized = -24'sd12;
        24:      quantized = -24'sd1;
        default: quantized = 24'sd0;
      endcase
    end
  endfunction

  task automatic run_operation(input logic dequantize_i);
    begin
      @(negedge clk);
      dequantize = dequantize_i;
      start      = 1'b1;
      @(negedge clk);
      start = 1'b0;
      while (!result_valid) @(negedge clk);
    end
  endtask

  initial begin
    clk          = 1'b0;
    rst_n        = 1'b0;
    start        = 1'b0;
    dequantize   = 1'b0;
    block_in     = '0;
    quant        = '0;
    reciprocal   = '0;
    result_ready = 1'b0;
    for (int index = 0; index < 64; index++) begin
      block_in[index*24+:24]   = coefficient(index);
      quant[index*8+:8]        = luma_quant(index);
      reciprocal[index*25+:25] = (25'd16777216 + luma_quant(index) - 1'b1) / luma_quant(index);
    end
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    run_operation(1'b0);
    if (table_err || overflow) $fatal(1, "unexpected quantizer error");
    for (int index = 0; index < 64; index++) begin
      if ($signed(block_out[index*24+:24]) != quantized(index)) begin
        $fatal(1, "quantized mismatch at %0d: %0d", index, $signed(block_out[index*24+:24]));
      end
    end

    block_in     = block_out;
    result_ready = 1'b1;
    @(negedge clk);
    result_ready = 1'b0;
    run_operation(1'b1);
    if ($signed(
            block_out[1*24+:24]
        ) != -24'sd22 || $signed(
            block_out[8*24+:24]
        ) != -24'sd144 || $signed(
            block_out[24*24+:24]
        ) != -24'sd14) begin
      $fatal(1, "dequantized output mismatch");
    end
    result_ready = 1'b1;
    @(negedge clk);
    $display("JPEG quantizer tests passed");
    $finish;
  end
endmodule
