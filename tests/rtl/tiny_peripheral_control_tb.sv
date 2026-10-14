`timescale 1ns / 1ps
module tiny_peripheral_control_tb;
  logic clk = 0, leaf_clk = 0, rst_n = 0, run_leaf = 1;
  logic apply = 0, reset_cmd = 0, bus_idle = 1;
  logic [13:0] request_mask = 0, idle_mask = '1;
  logic [13:0] gates, resets, actual, held, ready, completed;
  logic block_new, done;
  logic [4:0] fault;
  logic ip_clk, ip_rst_n;
  integer hold_edges = 0, release_edges = 0;
  always #5 clk = !clk;
  always #7 if (run_leaf) leaf_clk = !leaf_clk;
  tiny_peripheral_control u_control (
      .clk_i          (clk),
      .rst_n_i        (rst_n),
      .warm_reset_i   (1'b0),
      .apply_i        (apply),
      .reset_command_i(reset_cmd),
      .request_i      (request_mask),
      .idle_i         (idle_mask),
      .bus_idle_i     (bus_idle),
      .gate_actual_i  (actual),
      .reset_held_i   (held),
      .reset_ready_i  (ready),
      .timeout_i      (32'd128),
      .gate_o         (gates),
      .reset_o        (resets),
      .block_o        (block_new),
      .done_o         (done),
      .fault_o        (fault),
      .reset_done_o   (completed)
  );
  tiny_peripheral_leaf u_leaf (
      .clk_i  (leaf_clk),
      .rst_n_i(rst_n),
      .gate_i (gates[2]),
      .reset_i(resets[2]),
      .clk_o  (ip_clk),
      .rst_n_o(ip_rst_n),
      .gated_o(actual[2]),
      .held_o (held[2])
  );
  assign actual[13:3] = 0;
  assign actual[1:0]  = 0;
  assign held[13:3]   = 0;
  assign held[1:0]    = 0;
  assign ready        = {11'd0, ip_rst_n, 2'd0};
  always @(posedge ip_clk) begin
    if (resets[2]) hold_edges++;
    if (!resets[2] && !ip_rst_n && hold_edges != 0) release_edges++;
  end
  task automatic command(input logic resetting, input logic [13:0] mask);
    @(negedge clk);
    reset_cmd    = resetting;
    request_mask = mask;
    apply        = 1;
    @(negedge clk);
    apply = 0;
  endtask
  task automatic completion(input logic [4:0] expected_fault);
    integer count;
    count = 0;
    while (!done && count < 200) begin
      @(negedge clk);
      count++;
    end
    if (!done || block_new || fault != expected_fault)
      $fatal(1, "lifecycle completion fault=%h expected=%h", fault, expected_fault);
  endtask
  initial begin
    #1 rst_n = 1;
    #1 rst_n = 0;
    repeat (8) @(negedge clk);
    rst_n = 1;
    repeat (20) @(negedge clk);
    // CPU WFI permission must complete without pausing an unrelated DMA job.
    idle_mask[9] = 0;
    bus_idle     = 0;
    command(0, 14'h1);
    while (!done) begin
      @(negedge clk);
      if (block_new) $fatal(1, "CPU-only gate arm blocked independent traffic");
    end
    completion(0);
    if (gates != 1) $fatal(1, "CPU WFI arm waited for unrelated DMA");
    command(0, 0);
    completion(0);
    idle_mask[9] = 1;
    bus_idle     = 1;
    idle_mask[2] = 0;
    command(0, 14'h4);
    completion(5'b00010);
    if (gates != 0 || actual != 0) $fatal(1, "busy timeout changed gates");
    idle_mask[2] = 1;
    command(0, 14'h4);
    completion(0);
    if (!actual[2]) $fatal(1, "gate completed before leaf stopped");
    repeat (10) @(negedge clk);
    if (ip_clk) $fatal(1, "gated clock high");
    command(1, 14'h4);
    completion(5'b00001);
    if (resets != 0 || completed != 0) $fatal(1, "reset accepted for gated IP");
    command(0, 0);
    completion(0);
    command(1, 14'h4);
    completion(0);
    if (completed != 14'h4 || hold_edges < 5 || release_edges < 5 || !ip_rst_n)
      $fatal(1, "reset acknowledged before five hold/release edges");
    @(negedge leaf_clk);
    run_leaf = 0;
    command(1, 14'h4);
    completion(5'b10000);
    if (completed != 0 || !resets[2] || ip_rst_n)
      $fatal(1, "missing clock acknowledged reset or removed isolation");
    $display("SIM_TEST_PASS Tiny peripheral lifecycle");
    $finish;
  end
  initial begin
    #100000;
    $fatal(1, "SIM_TEST_TIMEOUT Tiny peripheral lifecycle");
  end
endmodule
