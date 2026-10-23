`timescale 1ns / 1ps
module tiny_r2_p6_bridge_tb;
  logic clk_i = 0, rst_n_i = 0;
  always #5 clk_i = !clk_i;
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  apb4_if apb (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  tiny_axi42apb4 u_dut (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (axi),
      .apb4   (apb)
  );
  assign apb.pready  = apb.psel && apb.penable;
  assign apb.prdata  = 32'h13579bdf;
  // A strict APB4 receiver rejects nonzero read strobes independently of PWRITE.
  assign apb.pslverr = apb.psel && apb.penable && !apb.pwrite && apb.pstrb != 0;
  task automatic write_read(input logic [3:0] mask);
    @(negedge clk_i);
    axi.awvalid = 1;
    do @(posedge clk_i); while (!axi.awready);
    @(negedge clk_i);
    axi.awvalid = 0;
    axi.wvalid  = 1;
    axi.wstrb   = mask;
    do @(posedge clk_i); while (!axi.wready);
    @(negedge clk_i);
    axi.wvalid = 0;
    do @(posedge clk_i); while (!apb.penable);
    if (!apb.pwrite || apb.pstrb !== mask) $fatal(1, "SIM_TEST_FAIL lost write byte lanes");
    do @(posedge clk_i); while (!axi.bvalid);
    if (axi.bresp != 0) $fatal(1, "SIM_TEST_FAIL APB write response");
    @(negedge clk_i);
    axi.arvalid = 1;
    do @(posedge clk_i); while (!axi.arready);
    @(negedge clk_i);
    axi.arvalid = 0;
    do @(posedge clk_i); while (!axi.rvalid);
    if (axi.rresp != 0 || axi.rdata !== 32'h13579bdf || !axi.rlast)
      $fatal(1, "SIM_TEST_FAIL stale write strobes corrupted APB read");
    @(negedge clk_i);
  endtask
  initial begin
    axi.awvalid = 0;
    axi.awaddr  = 'h10007000;
    axi.awlen   = 0;
    axi.awsize  = 2;
    axi.awburst = 1;
    axi.awlock  = 0;
    axi.awid    = 0;
    axi.wvalid  = 0;
    axi.wdata   = 'h12345678;
    axi.wstrb   = 0;
    axi.wlast   = 1;
    axi.bready  = 1;
    axi.arvalid = 0;
    axi.araddr  = 'h10007008;
    axi.arlen   = 0;
    axi.arsize  = 2;
    axi.arburst = 1;
    axi.arlock  = 0;
    axi.arid    = 0;
    axi.rready  = 1;
    repeat (4) @(negedge clk_i);
    rst_n_i = 1;
    write_read(15);
    write_read(1);
    write_read(3);
    write_read(10);
    $display("SIM_TEST_PASS Tiny P6 APB read strobes");
    $finish;
  end
  initial begin
    #100000;
    $fatal(1, "SIM_TEST_TIMEOUT P6 APB strobes");
  end
endmodule
