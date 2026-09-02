`timescale 1ns / 1ps

module axi4_address_gate_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  logic block_new_i = 1'b0;
  logic idle_o;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) source (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) sink (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  axi4_address_gate u_dut (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .block_new_i(block_new_i),
      .source     (source),
      .sink       (sink),
      .idle_o     (idle_o)
  );

  initial begin
    source.awid     = '0;
    source.awaddr   = 32'h1000_1000;
    source.awlen    = '0;
    source.awsize   = 3'd2;
    source.awburst  = 2'd1;
    source.awlock   = 1'b0;
    source.awcache  = '0;
    source.awprot   = '0;
    source.awqos    = '0;
    source.awregion = '0;
    source.awuser   = '0;
    source.awvalid  = 1'b0;
    source.wdata    = 32'hA5A5_5A5A;
    source.wstrb    = 4'hF;
    source.wlast    = 1'b1;
    source.wuser    = '0;
    source.wvalid   = 1'b0;
    source.bready   = 1'b1;
    source.arid     = '0;
    source.araddr   = 32'h1000_2000;
    source.arlen    = '0;
    source.arsize   = 3'd2;
    source.arburst  = 2'd1;
    source.arlock   = 1'b0;
    source.arcache  = '0;
    source.arprot   = '0;
    source.arqos    = '0;
    source.arregion = '0;
    source.aruser   = '0;
    source.arvalid  = 1'b0;
    source.rready   = 1'b1;

    sink.awready    = 1'b1;
    sink.wready     = 1'b1;
    sink.bid        = '0;
    sink.bresp      = '0;
    sink.buser      = '0;
    sink.bvalid     = 1'b0;
    sink.arready    = 1'b1;
    sink.rid        = '0;
    sink.rdata      = 32'h1234_5678;
    sink.rresp      = '0;
    sink.rlast      = 1'b1;
    sink.ruser      = '0;
    sink.rvalid     = 1'b0;

    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    if (!idle_o) $fatal(1, "gate did not reset idle");

    block_new_i    = 1'b1;
    source.awvalid = 1'b1;
    #1;
    if (source.awready || sink.awvalid || idle_o) begin
      $fatal(1, "blocked write address was accepted or reported idle");
    end

    block_new_i   = 1'b0;
    source.wvalid = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    source.awvalid = 1'b0;
    source.wvalid  = 1'b0;
    block_new_i    = 1'b1;
    if (idle_o) $fatal(1, "accepted write was not tracked");
    sink.bvalid = 1'b1;
    #1;
    if (!source.bvalid) $fatal(1, "write response was blocked during quiesce");
    @(posedge clk_i);
    @(negedge clk_i);
    sink.bvalid = 1'b0;
    if (!idle_o) $fatal(1, "write completion did not restore idle");

    block_new_i    = 1'b0;
    source.arvalid = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    source.arvalid = 1'b0;
    block_new_i    = 1'b1;
    if (idle_o) $fatal(1, "accepted read was not tracked");
    sink.rvalid = 1'b1;
    #1;
    if (!source.rvalid || source.rdata != 32'h1234_5678) begin
      $fatal(1, "read response was blocked during quiesce");
    end
    @(posedge clk_i);
    @(negedge clk_i);
    sink.rvalid = 1'b0;
    if (!idle_o) $fatal(1, "read completion did not restore idle");

    $display("AXI4 address gate quiesce test passed");
    $finish;
  end
endmodule
