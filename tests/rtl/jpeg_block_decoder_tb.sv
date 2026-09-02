// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module jpeg_block_decoder_tb;
  logic                 clk = 1'b0;
  logic                 rst_n = 1'b0;
  logic                 start;
  logic        [ 511:0] quant;
  logic        [1599:0] reciprocal;
  logic        [ 191:0] dc_code;
  logic        [  59:0] dc_length;
  logic        [4095:0] ac_code;
  logic        [1279:0] ac_length;
  logic        [  31:0] bit_window;
  logic        [   5:0] bit_count;
  logic        [   5:0] bit_consume;
  logic                 bit_consume_valid;
  logic        [ 511:0] block_out;
  logic signed [  23:0] dc_out;
  logic                 result_valid;
  logic                 result_ready;
  logic                 error_flag;

  always #5 clk = ~clk;

  jpeg_block_decoder u_dut (
      .clk_i              (clk),
      .rst_n_i            (rst_n),
      .start_i            (start),
      .previous_dc_i      (24'sd2),
      .quant_i            (quant),
      .reciprocal_i       (reciprocal),
      .dc_code_i          (dc_code),
      .dc_length_i        (dc_length),
      .ac_code_i          (ac_code),
      .ac_length_i        (ac_length),
      .bit_window_i       (bit_window),
      .bit_count_i        (bit_count),
      .bit_consume_o      (bit_consume),
      .bit_consume_valid_o(bit_consume_valid),
      .start_ready_o      (),
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
    quant                 = {64{8'd1}};
    reciprocal            = {64{25'd16777216}};
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
    if (error_flag || dc_out != 24'sd5 || bit_count != 6'd0) begin
      $fatal(1, "block decode status mismatch");
    end
    for (int index = 0; index < 64; index++) begin
      if (block_out[index*8+:8] != 8'd129) begin
        $fatal(1, "decoded sample mismatch at %0d: %0d", index, block_out[index*8+:8]);
      end
    end
    result_ready = 1'b1;
    @(negedge clk);
    $display("JPEG block decoder tests passed");
    $finish;
  end
endmodule
