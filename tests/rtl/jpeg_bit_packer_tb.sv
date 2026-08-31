// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module jpeg_bit_packer_tb;
  logic         clk;
  logic         rst_n;
  logic [127:0] token_bits;
  logic [ 23:0] token_length;
  logic [  2:0] token_count;
  logic         token_valid;
  logic         token_ready;
  logic         flush;
  logic         flush_ready;
  logic         flush_done;
  logic [ 63:0] byte_data;
  logic [  7:0] byte_keep;
  logic         byte_valid;
  logic         byte_last;
  logic         byte_ready;
  logic         error_flag;

  jpeg_bit_packer u_dut (
      .clk_i         (clk),
      .rst_n_i       (rst_n),
      .token_bits_i  (token_bits),
      .token_length_i(token_length),
      .token_count_i (token_count),
      .token_valid_i (token_valid),
      .token_ready_o (token_ready),
      .flush_i       (flush),
      .flush_ready_o (flush_ready),
      .flush_done_o  (flush_done),
      .byte_data_o   (byte_data),
      .byte_keep_o   (byte_keep),
      .byte_valid_o  (byte_valid),
      .byte_last_o   (byte_last),
      .byte_ready_i  (byte_ready),
      .error_o       (error_flag)
  );

  always #5 clk = ~clk;

  initial begin
    clk          = 1'b0;
    rst_n        = 1'b0;
    token_bits   = '0;
    token_length = '0;
    token_count  = 3'd0;
    token_valid  = 1'b0;
    flush        = 1'b0;
    byte_ready   = 1'b0;
    repeat (3) @(negedge clk);
    rst_n              = 1'b1;

    token_bits[0+:32]  = 32'hff;
    token_length[0+:6] = 6'd8;
    token_bits[32+:32] = 32'ha;
    token_length[6+:6] = 6'd4;
    token_count        = 3'd2;
    token_valid        = 1'b1;
    @(negedge clk);
    if (!token_ready) $fatal(1, "token input was not accepted");
    token_valid = 1'b0;
    while (!flush_ready) @(negedge clk);
    flush = 1'b1;
    @(negedge clk);
    flush = 1'b0;
    while (!byte_valid) @(negedge clk);
    repeat (2) begin
      @(negedge clk);
      if (byte_data[23:0] != 24'haf00ff || byte_keep != 8'h07 || !byte_last) begin
        $fatal(1, "stuffed output changed under backpressure");
      end
    end
    byte_ready = 1'b1;
    #1;
    if (!flush_done || error_flag) $fatal(1, "flush completion mismatch");
    @(negedge clk);
    byte_ready = 1'b0;
    if (!flush_ready) $fatal(1, "packer did not return to running state");
    flush = 1'b1;
    @(negedge clk);
    flush = 1'b0;
    if (!flush_done || byte_valid) $fatal(1, "empty flush completion mismatch");
    @(negedge clk);
    $display("JPEG bit packer tests passed");
    $finish;
  end
endmodule
