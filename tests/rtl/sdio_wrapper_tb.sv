`timescale 1ns / 1ps
`include "axi4_define.svh"

module sdio_wrapper_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) dma_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  sdio_if sdio ();

  always #5 clk_i = ~clk_i;

  assign dma_axi4.awready = 1'b1;
  assign dma_axi4.wready  = 1'b1;
  assign dma_axi4.bid     = '0;
  assign dma_axi4.bresp   = `AXI4_RESP_OKAY;
  assign dma_axi4.buser   = '0;
  assign dma_axi4.bvalid  = 1'b0;
  assign dma_axi4.arready = 1'b1;
  assign dma_axi4.rid     = '0;
  assign dma_axi4.rdata   = '0;
  assign dma_axi4.rresp   = `AXI4_RESP_OKAY;
  assign dma_axi4.rlast   = 1'b1;
  assign dma_axi4.ruser   = '0;
  assign dma_axi4.rvalid  = 1'b0;

  apb4_sdio #(
      .InputClockHz(72_000_000),
      .AddrWidth   (32),
      .DataWidth   (32),
      .DescCount   (16)
  ) u_apb4_sdio (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .apb4    (apb4),
      .dma_axi4(dma_axi4),
      .sdio    (sdio)
  );

  initial begin
    apb4.paddr   = '0;
    apb4.pprot   = '0;
    apb4.psel    = 1'b0;
    apb4.penable = 1'b0;
    apb4.pwrite  = 1'b0;
    apb4.pwdata  = '0;
    apb4.pstrb   = '0;
    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    apb4.paddr = 32'h0000_0000;
    apb4.psel  = 1'b1;
    @(negedge clk_i);
    apb4.penable = 1'b1;
    @(posedge clk_i);
    #1;
    if (!apb4.pready || apb4.pslverr || (apb4.prdata != 32'h5344_494F)) begin
      $fatal(1, "wrapper APB identification failed");
    end
    $display("SDIO wrapper elaboration and APB smoke test passed");
    $finish;
  end
endmodule
