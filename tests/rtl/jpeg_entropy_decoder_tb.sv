// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module jpeg_entropy_decoder_tb;
  logic                 clk = 1'b0;
  logic                 rst_n = 1'b0;
  logic                 start;
  logic signed [  23:0] previous_dc;
  logic        [ 191:0] dc_code;
  logic        [  59:0] dc_length;
  logic        [4095:0] ac_code;
  logic        [1279:0] ac_length;
  logic        [  31:0] bit_window;
  logic        [   5:0] bit_count;
  logic        [   5:0] bit_consume;
  logic                 bit_consume_valid;
  logic                 start_ready;
  logic        [1535:0] block_out;
  logic signed [  23:0] dc_out;
  logic                 result_valid;
  logic                 result_ready;
  logic                 error_flag;

  always #5 clk = ~clk;

  jpeg_entropy_decoder u_dut (
      .clk_i              (clk),
      .rst_n_i            (rst_n),
      .start_i            (start),
      .previous_dc_i      (previous_dc),
      .dc_code_i          (dc_code),
      .dc_length_i        (dc_length),
      .ac_code_i          (ac_code),
      .ac_length_i        (ac_length),
      .bit_window_i       (bit_window),
      .bit_count_i        (bit_count),
      .bit_consume_o      (bit_consume),
      .bit_consume_valid_o(bit_consume_valid),
      .start_ready_o      (start_ready),
      .block_o            (block_out),
      .dc_o               (dc_out),
      .result_valid_o     (result_valid),
      .result_ready_i     (result_ready),
      .error_o            (error_flag)
  );

  always @(posedge clk) begin
    if (rst_n && bit_consume_valid) begin
      bit_window <= bit_window << bit_consume;
      bit_count  <= bit_count - bit_consume;
    end
  end

  initial begin
    start                 = 1'b0;
    previous_dc           = 24'sd2;
    dc_code               = '0;
    dc_length             = '0;
    ac_code               = '0;
    ac_length             = '0;
    bit_window            = {23'b10111_1110_1110_1110_101011, 9'd0};
    bit_count             = 6'd23;
    result_ready          = 1'b0;
    dc_code[2*16+:16]     = 16'b101;
    dc_length[2*5+:5]     = 5'd3;
    ac_code[8'hf0*16+:16] = 16'b1110;
    ac_length[8'hf0*5+:5] = 5'd4;
    ac_code[8'he1*16+:16] = 16'b10101;
    ac_length[8'he1*5+:5] = 5'd5;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    while (!result_valid) @(negedge clk);
    if (error_flag || dc_out != 24'sd5 || $signed(
            block_out[0+:24]
        ) != 24'sd5 || $signed(
            block_out[63*24+:24]
        ) != 24'sd1 || bit_count != 6'd0) begin
      $fatal(1, "entropy decode mismatch: err=%0d dc=%0d last=%0d bits=%0d", error_flag, dc_out,
             $signed(block_out[63*24+:24]), bit_count);
    end
    for (int index = 1; index < 63; index++) begin
      if ($signed(block_out[index*24+:24]) != 24'sd0) begin
        $fatal(1, "unexpected coefficient at %0d", index);
      end
    end
    result_ready = 1'b1;
    @(negedge clk);
    $display("JPEG entropy decoder tests passed");
    $finish;
  end
endmodule
