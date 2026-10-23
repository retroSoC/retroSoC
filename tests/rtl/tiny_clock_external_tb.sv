`timescale 1ns / 1ps
module tiny_clock_external_tb;
  localparam integer XinHz = `TINY_TEST_XIN_HZ;
  logic xin = 0, run_xin = 1, rst_n = 0, apply = 0;
  logic [1:0] profile = 0, current_profile;
  logic ref_clk, sys_clk, mem_clk, pclk, done, busy, fault;
  logic [31:0] xin_hz, ref_hz, sys_hz, mem_hz, pclk_hz;
  logic por_reset_n, old_por_reset_n;
  logic [2:0] reset_outputs, old_reset_outputs;
  integer ref_edges = 0;
  always #(500000000.0 / XinHz) if (run_xin) xin = !xin;
  tiny_reset_tree #(
      .LeafCount   (1),
      .SplitDomains(1)
  ) u_reset_tree (
      .clk_i               (sys_clk),
      .por_clk_i           (ref_clk),
      .leaf_clk_i          (sys_clk),
      .backend_reset_n_i   (1'b1),
      .rst_n_i             (rst_n),
      .watchdog_reset_req_i(1'b0),
      .por_rst_n_o         (por_reset_n),
      .system_rst_n_o      (reset_outputs[0]),
      .leaf_rst_n_o        (reset_outputs[1]),
      .cpu_ready_rst_n_o   (reset_outputs[2])
  );
  tiny_reset_tree #(
      .LeafCount   (1),
      .SplitDomains(1)
  ) u_old_reset_tree (
      .clk_i               (sys_clk),
      .por_clk_i           (xin),
      .leaf_clk_i          (sys_clk),
      .backend_reset_n_i   (1'b1),
      .rst_n_i             (rst_n),
      .watchdog_reset_req_i(1'b0),
      .por_rst_n_o         (old_por_reset_n),
      .system_rst_n_o      (old_reset_outputs[0]),
      .leaf_rst_n_o        (old_reset_outputs[1]),
      .cpu_ready_rst_n_o   (old_reset_outputs[2])
  );
  always @(posedge ref_clk or negedge rst_n) begin
    if (!rst_n) ref_edges = 0;
    else ref_edges++;
  end
  always @(posedge por_reset_n) begin
    if (ref_edges < 5) $fatal(1, "AON reset released before five REF24 edges");
  end
  always @(negedge xin) begin
    if (XinHz == 24000000 && rst_n &&
        ({por_reset_n, reset_outputs} !== {old_por_reset_n, old_reset_outputs}))
      $fatal(1, "24 MHz reset connection correction changed behavior");
  end
  tiny_clock_reset_subsystem #(
      .RefClkHz(XinHz),
      .HavePll (1'b0)
  ) u_dut (
      .ref_clk_i        (xin),
      .rst_n_i          (rst_n),
      .profile_i        (profile),
      .apply_i          (apply),
      .idle_i           (1'b1),
      .clients_idle_i   (1'b1),
      .warm_reset_i     (1'b0),
      .system_request_i (1'b0),
      .command_ack_i    (1'b1),
      .timeout_i        (32'd512),
      .current_profile_o(current_profile),
      .busy_o           (busy),
      .fault_o          (fault),
      .fault_code_o     (),
      .done_o           (done),
      .block_o          (),
      .ref_clk_o        (ref_clk),
      .ref_rst_n_o      (),
      .system_reset_n_o (),
      .pll_locked_o     (),
      .pll_selected_o   (),
      .sys_clk_o        (sys_clk),
      .mem_clk_o        (mem_clk),
      .pclk_o           (pclk),
      .sys_rst_n_o      (),
      .mem_rst_n_o      (),
      .pclk_rst_n_o     (),
      .xin_hz_o         (xin_hz),
      .ref_hz_o         (ref_hz),
      .sys_hz_o         (sys_hz),
      .mem_hz_o         (mem_hz),
      .pclk_hz_o        (pclk_hz)
  );
  task automatic command(input logic [1:0] requested);
    @(negedge ref_clk);
    profile = requested;
    apply   = 1;
    @(negedge ref_clk);
    apply = 0;
    repeat (600) @(negedge ref_clk);
    if (busy) $fatal(1, "external clock command stuck");
  endtask
  task automatic measure(input real expected_sys, input real expected_pclk);
    realtime start_time, period;
    @(posedge sys_clk);
    start_time = $realtime;
    repeat (100) @(posedge sys_clk);
    period = ($realtime - start_time) / 100.0;
    if (period < expected_sys - 0.01 || period > expected_sys + 0.01)
      $fatal(1, "external SYS frequency mismatch");
    @(posedge mem_clk);
    start_time = $realtime;
    repeat (100) @(posedge mem_clk);
    period = ($realtime - start_time) / 100.0;
    if (period < expected_sys - 0.01 || period > expected_sys + 0.01)
      $fatal(1, "external MEM frequency mismatch");
    @(posedge pclk);
    start_time = $realtime;
    repeat (100) @(posedge pclk);
    period = ($realtime - start_time) / 100.0;
    if (period < expected_pclk - 0.02 || period > expected_pclk + 0.02)
      $fatal(1, "external PCLK frequency mismatch");
  endtask
  initial begin
    #1 rst_n = 1;
    #1 rst_n = 0;
    repeat (20) @(negedge xin);
    rst_n = 1;
    repeat (200) @(negedge xin);
    if (xin_hz != XinHz || ref_hz != 24000000 || sys_hz != 24000000)
      $fatal(1, "external SAFE24 normalization failed");
    measure(1000.0 / 24.0, 1000.0 / 24.0);
    command(1);
    if (fault || current_profile != 1 || sys_hz != XinHz || mem_hz != XinHz ||
        pclk_hz != (XinHz > 60000000 ? XinHz / 2 : XinHz))
      $fatal(1, "external profile commit failed");
    measure(1000000000.0 / XinHz, (XinHz > 60000000 ? 2000000000.0 : 1000000000.0) / XinHz);
    command(0);
    measure(1000.0 / 24.0, 1000.0 / 24.0);
    command(2);
    if (!fault || current_profile != 0) $fatal(1, "no-PLL profile accepted a PLL request");
    @(negedge xin);
    run_xin = 0;
    #1000;
    // XIN loss has no independent safety clock. Recovery is external reset.
    rst_n = 0;
    #100;
    if (por_reset_n || reset_outputs != 0) $fatal(1, "stopped-clock reset did not assert");
    run_xin = 1;
    repeat (20) @(negedge xin);
    rst_n = 1;
    repeat (200) @(negedge xin);
    if (fault || current_profile != 0) $fatal(1, "external reset recovery failed");
    measure(1000.0 / 24.0, 1000.0 / 24.0);
    $display("SIM_TEST_PASS Tiny external XIN=%0d", XinHz);
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1, "SIM_TEST_TIMEOUT Tiny external clock");
  end
endmodule
