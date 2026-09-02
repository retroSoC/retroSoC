// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module jpeg_entropy_encoder_tb;
  logic                 clk;
  logic                 rst_n;
  logic                 start;
  logic        [1535:0] block_in;
  logic signed [  23:0] previous_dc;
  logic        [ 191:0] dc_code;
  logic        [  59:0] dc_length;
  logic        [4095:0] ac_code;
  logic        [1279:0] ac_length;
  logic                 start_ready;
  logic signed [  23:0] dc_out;
  logic        [ 127:0] token_bits;
  logic        [  23:0] token_length;
  logic        [   2:0] token_count;
  logic                 token_valid;
  logic                 token_last;
  logic                 token_ready;
  logic                 error_flag;
  logic        [  31:0] captured_bits  [0:4];
  logic        [   5:0] captured_length[0:4];
  int                   capture_count;

  jpeg_entropy_encoder u_dut (
      .clk_i         (clk),
      .rst_n_i       (rst_n),
      .start_i       (start),
      .block_i       (block_in),
      .previous_dc_i (previous_dc),
      .dc_code_i     (dc_code),
      .dc_length_i   (dc_length),
      .ac_code_i     (ac_code),
      .ac_length_i   (ac_length),
      .start_ready_o (start_ready),
      .dc_o          (dc_out),
      .token_bits_o  (token_bits),
      .token_length_o(token_length),
      .token_count_o (token_count),
      .token_valid_o (token_valid),
      .token_last_o  (token_last),
      .token_ready_i (token_ready),
      .error_o       (error_flag)
  );

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (rst_n && token_valid && token_ready) begin
      for (int index = 0; index < token_count; index++) begin
        captured_bits[capture_count]   = token_bits[index*32+:32];
        captured_length[capture_count] = token_length[index*6+:6];
        capture_count                  = capture_count + 1;
      end
    end
  end

  initial begin
    clk                   = 1'b0;
    rst_n                 = 1'b0;
    start                 = 1'b0;
    block_in              = '0;
    previous_dc           = 24'sd2;
    dc_code               = '0;
    dc_length             = '0;
    ac_code               = '0;
    ac_length             = '0;
    token_ready           = 1'b0;
    capture_count         = 0;
    block_in[0+:24]       = 24'sd5;
    block_in[63*24+:24]   = 24'sd1;
    dc_code[2*16+:16]     = 16'b101;
    dc_length[2*5+:5]     = 5'd3;
    ac_code[8'hf0*16+:16] = 16'b1110;
    ac_length[8'hf0*5+:5] = 5'd4;
    ac_code[8'he1*16+:16] = 16'b10101;
    ac_length[8'he1*5+:5] = 5'd5;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    while (!token_valid) @(negedge clk);
    repeat (2) begin
      @(negedge clk);
      if (token_bits[0+:32] != 32'd23 || token_length[0+:6] != 6'd5) begin
        $fatal(1, "token changed under backpressure");
      end
    end
    token_ready = 1'b1;
    while (!start_ready) @(negedge clk);
    @(negedge clk);
    if (error_flag) $fatal(1, "unexpected entropy error");
    if (dc_out != 24'sd5 || capture_count != 5) begin
      $fatal(1, "entropy completion mismatch: dc=%0d tokens=%0d", dc_out, capture_count);
    end
    if (captured_bits[0] != 32'd23 || captured_length[0] != 6'd5) begin
      $fatal(1, "DC token mismatch");
    end
    for (int index = 1; index < 4; index++) begin
      if (captured_bits[index] != 32'd14 || captured_length[index] != 6'd4) begin
        $fatal(1, "ZRL token mismatch at %0d", index);
      end
    end
    if (captured_bits[4] != 32'd43 || captured_length[4] != 6'd6) begin
      $fatal(1, "final AC token mismatch");
    end
    $display("JPEG entropy encoder tests passed");
    $finish;
  end
endmodule
