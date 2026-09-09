`timescale 1ns / 1ps

module axi4_async_bridge_tb;
  logic       src_clk_i = 1'b0;
  logic       dst_clk_i = 1'b0;
  logic       src_rst_n_i = 1'b0;
  logic       dst_rst_n_i = 1'b0;
  logic       clear_i = 1'b0;
  logic       clear_busy_o;
  logic [7:0] epoch_o;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) source (
      .aclk   (src_clk_i),
      .aresetn(src_rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) sink (
      .aclk   (dst_clk_i),
      .aresetn(dst_rst_n_i)
  );

  always #5 src_clk_i = ~src_clk_i;
  always #7 dst_clk_i = ~dst_clk_i;

  axi4_async_bridge u_dut (
      .src_clk_i   (src_clk_i),
      .src_rst_n_i (src_rst_n_i),
      .dst_clk_i   (dst_clk_i),
      .dst_rst_n_i (dst_rst_n_i),
      .clear_i     (clear_i),
      .clear_busy_o(clear_busy_o),
      .epoch_o     (epoch_o),
      .src_axi4    (source),
      .dst_axi4    (sink)
  );

  initial begin
    source.awid     = 0;
    source.awaddr   = 0;
    source.awlen    = 0;
    source.awsize   = 2;
    source.awburst  = 1;
    source.awlock   = 0;
    source.awcache  = 0;
    source.awprot   = 0;
    source.awqos    = 0;
    source.awregion = 0;
    source.awuser   = 0;
    source.awvalid  = 0;
    source.wdata    = 0;
    source.wstrb    = 0;
    source.wlast    = 1;
    source.wuser    = 0;
    source.wvalid   = 0;
    source.bready   = 1;
    source.arid     = 0;
    source.araddr   = 0;
    source.arlen    = 0;
    source.arsize   = 2;
    source.arburst  = 1;
    source.arlock   = 0;
    source.arcache  = 0;
    source.arprot   = 0;
    source.arqos    = 0;
    source.arregion = 0;
    source.aruser   = 0;
    source.arvalid  = 0;
    source.rready   = 1;
    sink.awready    = 1;
    sink.wready     = 1;
    sink.bid        = 0;
    sink.bresp      = 0;
    sink.buser      = 0;
    sink.bvalid     = 0;
    sink.arready    = 1;
    sink.rid        = 0;
    sink.rdata      = 32'hCAFE_BABE;
    sink.rresp      = 0;
    sink.rlast      = 1;
    sink.ruser      = 0;
    sink.rvalid     = 0;

    repeat (3) @(posedge src_clk_i);
    src_rst_n_i = 1;
    dst_rst_n_i = 1;
    repeat (8) @(posedge src_clk_i);
    @(negedge src_clk_i);
    source.araddr  = 32'h5000_0040;
    source.arvalid = 1;
    do @(posedge src_clk_i); while (!source.arready);
    @(negedge src_clk_i);
    source.arvalid = 0;
    wait (sink.arvalid);
    if (sink.araddr != 32'h5000_0040) $fatal(1, "async bridge address mismatch");
    @(posedge dst_clk_i);
    @(negedge dst_clk_i);
    sink.rvalid = 1;
    do @(posedge dst_clk_i); while (!sink.rready);
    @(negedge dst_clk_i);
    sink.rvalid = 0;
    wait (source.rvalid);
    if (source.rdata != 32'hCAFE_BABE) $fatal(1, "async bridge response mismatch");
    @(posedge src_clk_i);

    @(negedge src_clk_i);
    clear_i = 1;
    wait (clear_busy_o);
    clear_i = 0;
    wait (!clear_busy_o);
    if (epoch_o != 8'd1) $fatal(1, "async bridge epoch did not advance");

    @(negedge dst_clk_i);
    dst_rst_n_i = 1'b0;
    repeat (3) @(posedge src_clk_i);
    @(negedge dst_clk_i);
    dst_rst_n_i = 1'b1;
    wait (epoch_o == 8'd2);

    $display("AXI4 async bridge transfer and warm flush test passed; unilateral reset passed");
    $finish;
  end

  initial begin
    #20000;
    $fatal(1, "AXI4 async bridge test timed out");
  end
endmodule
