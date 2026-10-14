`timescale 1ns / 1ps
module tiny_apb_async_bridge_tb;
  logic clk_i = 0, dst_clk = 0, rst_n_i = 0, dst_rst_n = 0;
  logic run_dst = 1, disabled = 0, idle, ready;
  logic          respond = 1;
  integer        writes = 0;
  logic   [31:0] saved;
  logic   [31:0] value;
  always #5 clk_i = !clk_i;
  always #17 if (run_dst) dst_clk = !dst_clk;
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  apb4_if endpoint (
      .pclk   (dst_clk),
      .presetn(dst_rst_n)
  );
  tiny_apb_async_bridge u_dut (
      .src_clk_i  (clk_i),
      .src_rst_n_i(rst_n_i),
      .dst_clk_i  (dst_clk),
      .dst_rst_n_i(dst_rst_n),
      .disabled_i (disabled),
      .idle_o     (idle),
      .ready_o    (ready),
      .src_apb4   (apb4),
      .dst_apb4   (endpoint)
  );
  assign endpoint.pready  = endpoint.psel && endpoint.penable && respond;
  assign endpoint.pslverr = endpoint.paddr[8];
  assign endpoint.prdata  = saved ^ endpoint.paddr;
  always @(posedge dst_clk) begin
    if (dst_rst_n && endpoint.psel && endpoint.penable && endpoint.pready && endpoint.pwrite) begin
      writes = writes + 1;
      if (endpoint.pstrb != 4'h5 || endpoint.pprot != 0) $fatal(1, "APB payload changed");
      saved = endpoint.pwdata;
    end
  end
  `include "apb4_bfm.svh"
  initial begin
    apb4_idle();
    #2;
    rst_n_i   = 0;
    dst_rst_n = 0;
    repeat (6) @(negedge clk_i);
    rst_n_i   = 1;
    dst_rst_n = 1;
    wait (ready);
    repeat (5) @(negedge clk_i);
    apb4_write(32'h20, 32'h87654321, 4'h5, 0);
    apb4_read(32'h20, 0, value);
    if (value != 32'h87654301 || writes != 1) $fatal(1, "APB CDC data/duplicate");
    apb4_read(32'h100, 1, value);
    respond = 0;
    fork
      apb4_read(32'h20, 1, value);
      begin
        wait (endpoint.psel && endpoint.penable);
        #3 dst_rst_n = 0;
        repeat (15) @(negedge clk_i);
        dst_rst_n = 1;
      end
    join
    respond = 1;
    wait (ready);
    repeat (30) @(negedge clk_i);
    if (endpoint.psel) $fatal(1, "reset replayed an old APB request");
    disabled = 1;
    @(negedge dst_clk);
    run_dst = 0;
    apb4_read(32'h20, 1, value);
    apb4_write(32'h20, 32'hbad, 4'h5, 1);
    if (writes != 1) $fatal(1, "disabled APB side effect");
    run_dst  = 1;
    disabled = 0;
    repeat (30) @(negedge clk_i);
    apb4_read(32'h20, 0, value);
    if (value != 32'h87654301) $fatal(1, "CDC restart data");
    $display("SIM_TEST_PASS Tiny APB CDC");
    $finish;
  end
  initial begin
    #100000;
    $fatal(1, "SIM_TEST_TIMEOUT Tiny APB CDC");
  end
endmodule
