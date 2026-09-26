// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
`timescale 1ns / 1ps
module crypto_concurrent_tb;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  apb4_if apb4 (
      .pclk   (clk),
      .presetn(rst_n)
  );
  axi4_stream_if in_axis (
      .aclk   (clk),
      .aresetn(rst_n)
  );
  axi4_stream_if out_axis (
      .aclk   (clk),
      .aresetn(rst_n)
  );
  logic [  31:0] constants[0:2047];
  logic [2047:0] rsa      [   0:5];
  string constant_path, rsa_path;
  apb4_crypto u_dut (
      .clk_i            (clk),
      .rst_n_i          (rst_n),
      .dma_input_proc_o (),
      .dma_output_proc_o(),
      .irq_o            (),
      .apb4             (apb4),
      .crypto_in_axis   (in_axis),
      .crypto_out_axis  (out_axis)
  );
  task automatic access (input logic write, input logic [11:0] address, input logic [31:0] data,
                         output logic [31:0] value);
    int waits;
    @(negedge clk);
    apb4.psel    = 1;
    apb4.penable = 0;
    apb4.pwrite  = write;
    apb4.paddr   = {20'd0, address};
    apb4.pwdata  = data;
    apb4.pstrb   = 15;
    @(negedge clk);
    apb4.penable = 1;
    waits        = 0;
    #1;
    while (!apb4.pready) begin
      @(negedge clk);
      #1;
      waits++;
      if (waits > 4) $fatal(1, "APB wait");
    end
    if (apb4.pslverr) $fatal(1, "APB failure %h", address);
    value = apb4.prdata;
    @(negedge clk);
    apb4.psel    = 0;
    apb4.penable = 0;
  endtask
  task automatic put(input logic [11:0] address, input logic [31:0] data);
    logic [31:0] value;
    access (1, address, data, value);
  endtask
  task automatic poll(input logic [11:0] address, input logic [31:0] mask,
                      input logic [31:0] expected);
    logic [31:0] value;
    for (int count = 0; count < 1400000; count++) begin
      access (0, address, 0, value);
      if ((value & mask) == expected) return;
    end
    $fatal(1, "poll timeout %h", address);
  endtask
  initial begin
    logic [ 31:0] value;
    logic [127:0] cipher;
    logic [255:0] digest;
    apb4.psel       = 0;
    apb4.penable    = 0;
    apb4.pwrite     = 0;
    apb4.paddr      = 0;
    apb4.pwdata     = 0;
    apb4.pstrb      = 0;
    apb4.pprot      = 0;
    in_axis.tvalid  = 0;
    in_axis.tdata   = 0;
    in_axis.tkeep   = 0;
    in_axis.tstrb   = 0;
    in_axis.tlast   = 0;
    in_axis.tid     = 0;
    in_axis.tdest   = 0;
    in_axis.tuser   = 0;
    out_axis.tready = 0;
    if (!$value$plusargs("constants=%s", constant_path) || !$value$plusargs("rsa=%s", rsa_path))
      $fatal(1, "missing vectors");
    $readmemh(constant_path, constants);
    $readmemh(rsa_path, rsa);
    repeat (3) @(negedge clk);
    rst_n = 1;
    poll(12'h028, 4, 0);
    put(12'h02c, 1);
    for (int index = 0; index < 2048; index++) put(12'h038, constants[index]);
    put(12'h02c, 2);
    poll(12'h028, 127, 35);
    put(12'h140, 32'h03020100);
    put(12'h144, 32'h07060504);
    put(12'h148, 32'h0b0a0908);
    put(12'h14c, 32'h0f0e0d0c);
    put(12'h128, 1);
    poll(12'h12c, 3, 1);
    for (int index = 0; index < 64; index++) put(12'h400 + 12'(index * 4), rsa[0][index*32+:32]);
    put(12'h10c, 16);
    put(12'h204, 1);
    put(12'h20c, 0);
    put(12'h300, 1);
    put(12'h200, 1);
    put(12'h100, 1);
    access (0, 12'h014, 0, value);
    if ((value & 7) != 7) $fatal(1, "all three engines did not overlap");
    put(12'h110, 32'h33221100);
    put(12'h110, 32'h77665544);
    put(12'h110, 32'hbbaa9988);
    put(12'h110, 32'hffeeddcc);
    for (int index = 0; index < 4; index++) begin
      poll(12'h118, 2, 2);
      access (0, 12'h114, 0, value);
      cipher[127-index*32-:32] = crypto_mem_pkg::byte_reverse(value);
    end
    if (cipher !== 128'h69c4e0d86a7b0430d8cdb78070b4c55a) $fatal(1, "concurrent AES");
    poll(12'h208, 9, 8);
    for (int index = 0; index < 8; index++) begin
      access (0, 12'h240 + 12'(index * 4), 0, value);
      digest[255-index*32-:32] = value;
    end
    if (digest !== 256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855)
      $fatal(1, "concurrent SHA");
    poll(12'h308, 13, 8);
    access (0, 12'h30c, 0, value);
    if (value != 2887941) $fatal(1, "RSA was stalled by unrelated engine %0d", value);
    $display("CRYPTO_V2_CONCURRENT_PASS");
    $finish;
  end
  initial begin
    #50000000;
    $fatal(1, "concurrency watchdog");
  end
endmodule
