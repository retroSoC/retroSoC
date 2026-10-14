`timescale 1ns / 1ps
module tiny_axi4_admission_tb;
  logic clk = 0, rst_n = 0, block_new = 0, idle;
  always #5 clk = !clk;
  axi4_if source (
      .aclk   (clk),
      .aresetn(rst_n)
  );
  axi4_if sink (
      .aclk   (clk),
      .aresetn(rst_n)
  );
  tiny_axi4_admission u_dut (
      .clk_i  (clk),
      .rst_n_i(rst_n),
      .block_i(block_new),
      .idle_o (idle),
      .source (source),
      .sink   (sink)
  );
  task automatic tick;
    @(posedge clk);
    #1;
    @(negedge clk);
  endtask
  initial begin
    source.awvalid  = 0;
    source.arvalid  = 0;
    source.wvalid   = 0;
    source.awid     = 1;
    source.awaddr   = 'h30001234;
    source.awlen    = 1;
    source.awsize   = 2;
    source.awburst  = 1;
    source.awlock   = 0;
    source.awcache  = 0;
    source.awprot   = 0;
    source.awqos    = 0;
    source.awregion = 0;
    source.awuser   = 0;
    source.arid     = 0;
    source.araddr   = 'h30005678;
    source.arlen    = 1;
    source.arsize   = 2;
    source.arburst  = 1;
    source.arlock   = 0;
    source.arcache  = 0;
    source.arprot   = 0;
    source.arqos    = 0;
    source.arregion = 0;
    source.aruser   = 0;
    source.wdata    = 'h12345678;
    source.wstrb    = 15;
    source.wlast    = 0;
    source.wuser    = 0;
    source.bready   = 0;
    source.rready   = 0;
    sink.awready    = 0;
    sink.arready    = 0;
    sink.wready     = 1;
    sink.bid        = 1;
    sink.bresp      = 0;
    sink.buser      = 0;
    sink.bvalid     = 0;
    sink.rid        = 0;
    sink.rdata      = 'hdeadbeef;
    sink.rresp      = 0;
    sink.rlast      = 0;
    sink.ruser      = 0;
    sink.rvalid     = 0;
    repeat (3) tick();
    rst_n = 1;
    tick();
    source.awvalid = 1;
    source.arvalid = 1;
    source.wvalid  = 1;
    tick();
    block_new      = 1;
    source.awvalid = 0;
    source.arvalid = 0;
    source.awaddr  = 0;
    source.araddr  = 0;
    repeat (5) begin
      tick();
      if (idle || !sink.awvalid || !sink.arvalid || source.wready ||
          sink.awaddr != 'h30001234 || sink.araddr != 'h30005678)
        $fatal(1, "accepted stalled address lost when admission blocked");
    end
    sink.awready = 1;
    sink.arready = 1;
    tick();
    sink.awready = 0;
    sink.arready = 0;
    source.wlast = 1;
    tick();
    source.wvalid = 0;
    sink.bvalid   = 1;
    sink.rvalid   = 1;
    repeat (3) begin
      tick();
      if (idle || !source.bvalid || !source.rvalid || source.rdata != 'hdeadbeef)
        $fatal(1, "response backpressure lost outstanding work");
    end
    source.bready = 1;
    source.rready = 1;
    tick();
    sink.bvalid = 0;
    sink.rlast  = 1;
    if (idle) $fatal(1, "read retired before RLAST");
    tick();
    sink.rvalid    = 0;
    source.awvalid = 1;
    source.arvalid = 1;
    repeat (3) begin
      tick();
      if (!idle || source.awready || source.arready || sink.awvalid || sink.arvalid)
        $fatal(1, "unaccepted blocked request counted as outstanding");
    end
    block_new = 0;
    tick();
    source.awvalid = 0;
    source.arvalid = 0;
    if (idle || !sink.awvalid || !sink.arvalid)
      $fatal(1, "retained upstream requests did not resume");
    rst_n = 0;
    tick();
    if (!idle || sink.awvalid || sink.arvalid) $fatal(1, "reset replayed old session");
    $display("SIM_TEST_PASS Tiny AXI admission drain/backpressure/resume");
    $finish;
  end
  initial begin
    #10000;
    $fatal(1, "SIM_TEST_TIMEOUT admission");
  end
endmodule
