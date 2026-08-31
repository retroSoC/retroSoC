// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module jpeg_block_encoder_tb;
  logic                 clk = 1'b0;
  logic                 rst_n = 1'b0;
  logic                 start;
  logic        [ 511:0] block_in;
  logic        [ 511:0] quant;
  logic        [1599:0] reciprocal;
  logic        [ 191:0] dc_code;
  logic        [  59:0] dc_length;
  logic        [4095:0] ac_code;
  logic        [1279:0] ac_length;
  logic        [ 127:0] token_bits;
  logic        [  23:0] token_length;
  logic        [   2:0] token_count;
  logic                 token_valid;
  logic                 token_last;
  logic signed [  23:0] dc_out;
  logic                 result_valid;
  logic                 result_ready;
  logic                 error_flag;
  int                   token_index;

  always #5 clk = ~clk;

  jpeg_block_encoder u_dut (
      .clk_i         (clk),
      .rst_n_i       (rst_n),
      .start_i       (start),
      .block_i       (block_in),
      .previous_dc_i (24'sd0),
      .quant_i       (quant),
      .reciprocal_i  (reciprocal),
      .dc_code_i     (dc_code),
      .dc_length_i   (dc_length),
      .ac_code_i     (ac_code),
      .ac_length_i   (ac_length),
      .start_ready_o (),
      .token_bits_o  (token_bits),
      .token_length_o(token_length),
      .token_count_o (token_count),
      .token_valid_o (token_valid),
      .token_last_o  (token_last),
      .token_ready_i (1'b1),
      .dc_o          (dc_out),
      .result_valid_o(result_valid),
      .result_ready_i(result_ready),
      .error_o       (error_flag)
  );

  always @(posedge clk) begin
    if (rst_n && token_valid) begin
      if (token_index == 0) begin
        if (token_count != 3'd1 || token_bits[0+:32] != 32'd88 ||
            token_length[0+:6] != 6'd7 || token_last) begin
          $fatal(1, "DC token mismatch");
        end
      end else if (token_index == 1) begin
        if (token_count != 3'd1 || token_bits[0+:32] != 32'd3 ||
            token_length[0+:6] != 6'd2 || !token_last) begin
          $fatal(1, "EOB token mismatch: count=%0d bits=%0d len=%0d last=%0d", token_count,
                 token_bits[0+:32], token_length[0+:6], token_last);
        end
      end else begin
        $fatal(1, "unexpected token beat");
      end
      token_index <= token_index + 1;
    end
  end

  initial begin
    start             = 1'b0;
    block_in          = {64{8'd129}};
    quant             = {64{8'd1}};
    reciprocal        = {64{25'd16777216}};
    dc_code           = '0;
    dc_length         = '0;
    ac_code           = '0;
    ac_length         = '0;
    dc_code[4*16+:16] = 16'b101;
    dc_length[4*5+:5] = 5'd3;
    ac_code[0+:16]    = 16'b11;
    ac_length[0+:5]   = 5'd2;
    result_ready      = 1'b0;
    token_index       = 0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    while (!result_valid) @(negedge clk);
    if (error_flag || dc_out != 24'sd8 || token_index != 2) begin
      $fatal(1, "block encode status mismatch: err=%0d dc=%0d tokens=%0d", error_flag, dc_out,
             token_index);
    end
    result_ready = 1'b1;
    @(negedge clk);
    $display("JPEG block encoder tests passed");
    $finish;
  end
endmodule
