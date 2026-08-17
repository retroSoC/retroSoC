`timescale 1ns / 1ps

`include "i2s_define.svh"

module i2s_tb;
  logic        clk_i = 1'b0;
  logic        clk_aud_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        rst_aud_n_i = 1'b0;
  logic        dma_tx_stall;
  logic        dma_rx_stall;
  logic [31:0] value;
  int          sclk_edges;
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .DEST_WIDTH(1),
      .USER_WIDTH(1)
  ) tx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .DEST_WIDTH(1),
      .USER_WIDTH(1)
  ) rx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  i2s_if i2s ();

  assign i2s.adcdat_i   = i2s.dacdat_o;
  assign tx_axis.tvalid = 1'b0;
  assign tx_axis.tdata  = '0;
  assign tx_axis.tkeep  = '1;
  assign tx_axis.tstrb  = '1;
  assign tx_axis.tlast  = 1'b0;
  assign tx_axis.tid    = '0;
  assign tx_axis.tdest  = '0;
  assign tx_axis.tuser  = '0;
  assign rx_axis.tready = 1'b1;
  always #5 clk_i = ~clk_i;
  always #8 clk_aud_i = ~clk_aud_i;

  apb4_i2s u_dut (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .clk_aud_i     (clk_aud_i),
      .rst_aud_n_i   (rst_aud_n_i),
      .dma_tx_stall_o(dma_tx_stall),
      .dma_rx_stall_o(dma_rx_stall),
      .apb4          (apb4),
      .tx_axis       (tx_axis),
      .rx_axis       (rx_axis),
      .i2s           (i2s)
  );

  task automatic write(input logic [31:0] address, input logic [31:0] data);
    begin
      @(negedge clk_i);
      apb4.paddr   = address;
      apb4.pwdata  = data;
      apb4.pstrb   = 4'hF;
      apb4.pwrite  = 1'b1;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
    end
  endtask

  task automatic read(input logic [31:0] address, output logic [31:0] data);
    begin
      @(negedge clk_i);
      apb4.paddr   = address;
      apb4.pwdata  = '0;
      apb4.pstrb   = '0;
      apb4.pwrite  = 1'b0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      data         = apb4.prdata;
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  always @(posedge i2s.sclk_o) sclk_edges = sclk_edges + 1;

  initial begin
    apb4.psel   = 1'b0;
    apb4.paddr  = '0;
    apb4.pwdata = '0;
    apb4.pstrb  = '0;
    sclk_edges  = 0;
    repeat (8) @(posedge clk_i);
    rst_n_i     = 1'b1;
    rst_aud_n_i = 1'b1;
    read(32'h0000_00f8, value);
    if (value != 32'h0001_0000) $fatal(1, "bad I2S version %h", value);
    read(32'h0000_00fc, value);
    if (value != 32'h0030_0707) $fatal(1, "bad I2S capability %h", value);
    read(32'h0000_0100, value);
    if (!apb4.pslverr) $fatal(1, "invalid I2S access was accepted");
    write(32'h0000_0000, 32'h0000_0001);
    write(32'h0000_0010, 32'h0000_0001);
    if (!apb4.pslverr) $fatal(1, "enabled FORMAT write was accepted");
    write(32'h0000_0000, 32'h0000_0000);
    write(32'h0000_0010, 32'h0000_0000);
    write(32'h0000_0018, 32'h0020_0078);
    write(32'h0000_0028, 32'h0000_0004);
    write(32'h0000_0030, 32'h0000_0004);
    read(32'h0000_0024, value);
    if ((value & 32'h0000_0004) == 0) $fatal(1, "I2S interrupt test failed");
    if (!i2s.irq_o) $fatal(1, "I2S IRQ was not raised");
    write(32'h0000_0024, 32'h0000_000F);
    write(32'h0000_001c, 32'hA5A5_5A5A);
    write(32'h0000_0000, 32'h0000_0007);
    repeat (4000) @(posedge clk_aud_i);
    if (sclk_edges == 0) $fatal(1, "I2S SCLK did not toggle");
    read(32'h0000_0008, value);
    write(32'h0000_0000, 32'h0000_0008);
    write(32'h0000_0000, 32'h0000_0009);
    repeat (2000) @(posedge clk_aud_i);
    write(32'h0000_0004, 32'h0000_0003);
    repeat (200) @(posedge clk_i);
    read(32'h0000_0008, value);
    if ((value & 32'h0300_0000) != 0) $fatal(1, "I2S flush stayed busy %h", value);
    $display("APB4 I2S controller test passed");
    $finish;
  end
endmodule
