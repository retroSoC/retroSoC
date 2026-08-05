`timescale 1ns / 1ps

module mgmt_debug_reset_tb;
  logic s_clk;
  logic s_rst_n;
  logic s_reset_req;
  logic s_bridge_idle;
  logic s_core_rst_n;
  logic s_reset_done;

  always #5 s_clk = ~s_clk;

  mgmt_debug_reset u_mgmt_debug_reset (
      .clk_i        (s_clk),
      .rst_n_i      (s_rst_n),
      .reset_req_i  (s_reset_req),
      .bridge_idle_i(s_bridge_idle),
      .core_rst_n_o (s_core_rst_n),
      .reset_done_o (s_reset_done)
  );

  initial begin
    s_clk         = 1'b0;
    s_rst_n       = 1'b0;
    s_reset_req   = 1'b0;
    s_bridge_idle = 1'b1;

    repeat (2) @(posedge s_clk);
    s_rst_n = 1'b1;
    repeat (4) @(posedge s_clk);
    #1;
    assert (s_core_rst_n && s_reset_done)
    else $fatal(1, "initial reset release failed");

    s_bridge_idle = 1'b0;
    s_reset_req   = 1'b1;
    @(posedge s_clk);
    s_reset_req = 1'b0;
    repeat (2) @(posedge s_clk);
    #1;
    assert (s_core_rst_n && !s_reset_done)
    else $fatal(1, "request did not wait for idle");

    s_bridge_idle = 1'b1;
    @(posedge s_clk);
    #1;
    assert (!s_core_rst_n && !s_reset_done)
    else $fatal(1, "core reset did not assert");
    repeat (4) @(posedge s_clk);
    #1;
    assert (s_core_rst_n && s_reset_done)
    else $fatal(1, "core reset did not release");

    s_reset_req = 1'b1;
    repeat (2) @(posedge s_clk);
    #1;
    assert (!s_core_rst_n && !s_reset_done)
    else $fatal(1, "held reset did not assert");
    repeat (3) @(posedge s_clk);
    #1;
    assert (!s_core_rst_n && !s_reset_done)
    else $fatal(1, "held reset released too early");

    s_reset_req = 1'b0;
    repeat (4) @(posedge s_clk);
    #1;
    assert (s_core_rst_n && s_reset_done)
    else $fatal(1, "held reset did not release");

    $display("management debug reset test passed");
    $finish;
  end
endmodule
