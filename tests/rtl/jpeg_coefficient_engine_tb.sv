`timescale 1ns / 1ps

module jpeg_coefficient_engine_tb;
  logic          clk = 1'b0;
  logic          rst_n = 1'b0;
  logic          start;
  logic          decode;
  logic [1535:0] block_in;
  logic [ 511:0] quant;
  logic [1599:0] reciprocal;
  logic          start_ready;
  logic [1535:0] block_out;
  logic          result_valid;
  logic          result_ready;
  logic          table_err;
  logic          overflow;

  always #5 clk = ~clk;

  jpeg_coefficient_engine u_dut (
      .clk_i         (clk),
      .rst_n_i       (rst_n),
      .start_i       (start),
      .decode_i      (decode),
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

  function automatic logic signed [23:0] expected_quantized(input int index_i);
    begin
      unique case (index_i)
        1:       return -24'sd2;
        8:       return -24'sd12;
        24:      return -24'sd1;
        default: return 24'sd0;
      endcase
    end
  endfunction

  initial begin
    start        = 1'b0;
    decode       = 1'b0;
    block_in     = '0;
    quant        = '0;
    reciprocal   = '0;
    result_ready = 1'b0;
    for (int index = 0; index < 64; index++) begin
      block_in[index*24+:24]   = 24'(index - 32);
      quant[index*8+:8]        = luma_quant(index);
      reciprocal[index*25+:25] = (25'd16777216 + luma_quant(index) - 1'b1) / luma_quant(index);
    end
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    if (!start_ready) $fatal(1, "coefficient engine not ready");
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    while (!result_valid) @(negedge clk);
    if (table_err || overflow) $fatal(1, "unexpected coefficient engine error");
    for (int index = 0; index < 64; index++) begin
      if ($signed(block_out[index*24+:24]) != expected_quantized(index)) begin
        $fatal(1, "coefficient mismatch at %0d: %0d", index, $signed(block_out[index*24+:24]));
      end
    end
    result_ready = 1'b1;
    @(negedge clk);
    $display("JPEG coefficient engine test passed");
    $finish;
  end
endmodule
