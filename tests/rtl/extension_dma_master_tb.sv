`timescale 1ns / 1ps

module extension_dma_master_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        start_i = 1'b0;
  logic        abort_i = 1'b0;
  logic        quiesce_i = 1'b0;
  logic [31:0] src_addr_i = 32'h3000_0000;
  logic [31:0] dst_addr_i = 32'h3000_0100;
  logic [31:0] len_i = 32'd12;
  logic [31:0] timeout_i = 32'd16;
  logic        busy_o;
  logic        done_o;
  logic        err_o;
  logic [31:0] fault_addr_o;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  extension_dma_master u_dut (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .start_i     (start_i),
      .abort_i     (abort_i),
      .quiesce_i   (quiesce_i),
      .src_addr_i  (src_addr_i),
      .dst_addr_i  (dst_addr_i),
      .len_i       (len_i),
      .timeout_i   (timeout_i),
      .busy_o      (busy_o),
      .done_o      (done_o),
      .err_o       (err_o),
      .fault_addr_o(fault_addr_o),
      .axi4        (axi4)
  );

  task automatic start_dma;
    begin
      @(negedge clk_i);
      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
    end
  endtask

  task automatic serve_beat(input logic [31:0] expected_src, input logic [31:0] expected_dst,
                            input logic [63:0] data, input logic [7:0] expected_strobe);
    begin
      wait (axi4.arvalid);
      if (axi4.araddr != expected_src) $fatal(1, "DMA read address mismatch");
      @(posedge clk_i);
      @(negedge clk_i);
      axi4.rid    = 3'd0;
      axi4.rdata  = data;
      axi4.rresp  = 2'b00;
      axi4.rlast  = 1'b1;
      axi4.rvalid = 1'b1;
      do @(posedge clk_i); while (!axi4.rready);
      @(negedge clk_i);
      axi4.rvalid = 1'b0;
      wait (axi4.awvalid);
      if (axi4.awaddr != expected_dst) $fatal(1, "DMA write address mismatch");
      @(posedge clk_i);
      wait (axi4.wvalid);
      if ((axi4.wdata != data) || (axi4.wstrb != expected_strobe) || !axi4.wlast) begin
        $fatal(1, "DMA write data or tail strobe mismatch");
      end
      @(posedge clk_i);
      @(negedge clk_i);
      axi4.bid    = 3'd0;
      axi4.bresp  = 2'b00;
      axi4.bvalid = 1'b1;
      do @(posedge clk_i); while (!axi4.bready);
      @(negedge clk_i);
      axi4.bvalid = 1'b0;
    end
  endtask

  initial begin
    axi4.awready = 1'b1;
    axi4.wready  = 1'b1;
    axi4.bid     = '0;
    axi4.bresp   = '0;
    axi4.buser   = '0;
    axi4.bvalid  = 1'b0;
    axi4.arready = 1'b1;
    axi4.rid     = '0;
    axi4.rdata   = '0;
    axi4.rresp   = '0;
    axi4.rlast   = 1'b1;
    axi4.ruser   = '0;
    axi4.rvalid  = 1'b0;

    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;
    start_dma();
    serve_beat(32'h3000_0000, 32'h3000_0100, 64'h1122_3344_5566_7788, 8'hFF);
    serve_beat(32'h3000_0008, 32'h3000_0108, 64'hAABB_CCDD_EEFF_0011, 8'h0F);
    wait (done_o);
    if (err_o || busy_o) $fatal(1, "successful DMA copy reported an error");

    @(negedge clk_i);
    timeout_i    = 32'd4;
    len_i        = 32'd8;
    axi4.arready = 1'b0;
    start_dma();
    wait (done_o);
    if (!err_o || (fault_addr_o != src_addr_i)) begin
      $fatal(1, "DMA no-progress timeout was not attributed to the source address");
    end

    $display("Extension DMA copy, tail strobe, and timeout test passed");
    $finish;
  end
endmodule
