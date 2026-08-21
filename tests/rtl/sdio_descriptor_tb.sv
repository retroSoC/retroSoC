`timescale 1ns / 1ps

module sdio_descriptor_tb;
  logic [31:0] buffer_addr_i = 32'h4000_0000;
  logic [31:0] byte_count_i = 32'd16;
  logic [31:0] next_addr_i = '0;
  logic [31:0] control_status_i = 32'h0001_0005;
  logic [15:0] desc_index_i = 16'd0;
  logic        own_o;
  logic        chain_o;
  logic        end_o;
  logic        irq_o;
  logic        valid_o;
  logic        error_o;
  logic        address_error_o;
  logic        length_error_o;
  logic        chain_error_o;

  sdio_dma_descriptor #(
      .DescCount(4)
  ) u_sdio_dma_descriptor (
      .buffer_addr_i   (buffer_addr_i),
      .byte_count_i    (byte_count_i),
      .next_addr_i     (next_addr_i),
      .control_status_i(control_status_i),
      .desc_index_i    (desc_index_i),
      .own_o           (own_o),
      .chain_o         (chain_o),
      .end_o           (end_o),
      .irq_o           (irq_o),
      .valid_o         (valid_o),
      .error_o         (error_o),
      .address_error_o (address_error_o),
      .length_error_o  (length_error_o),
      .chain_error_o   (chain_error_o)
  );

  initial begin
    #1;
    if (!valid_o || error_o || !own_o || !end_o) begin
      $fatal(1, "valid terminal descriptor rejected");
    end
    control_status_i = 32'h0000_0003;
    next_addr_i      = 32'h4000_0100;
    #1;
    if (!valid_o || error_o || !chain_o || end_o) begin
      $fatal(1, "valid chained descriptor rejected");
    end
    next_addr_i = 32'h4000_0FF0;
    #1;
    if (!error_o || !address_error_o) $fatal(1, "crossing descriptor chain not rejected");
    buffer_addr_i = 32'h4000_0002;
    #1;
    if (!error_o || !address_error_o) $fatal(1, "unaligned buffer not rejected");
    buffer_addr_i = 32'h4000_0000;
    byte_count_i  = 32'd0;
    #1;
    if (!error_o || !length_error_o) $fatal(1, "zero length not rejected");
    byte_count_i     = 32'd16;
    control_status_i = 32'h0000_0001;
    next_addr_i      = 32'h4000_0100;
    desc_index_i     = 16'd3;
    #1;
    if (!error_o || !chain_error_o) $fatal(1, "chain bound not rejected");
    $display("SDIO descriptor validation test passed");
    $finish;
  end
endmodule
