`timescale 1ns / 1ps
module tiny_watchdog_reset_tb;
  import wdg_pkg::*;
  logic xin = 0, reset_n = 1;
  always #20.833 xin = !xin;
  logic ref_clk, sys_clk, pclk, backend_reset_n, por_n, system_n, ready;
  logic [1:0] leaf_n;
  logic wdg_reset_n, request;
  logic   [ 1:0] current_profile;
  logic   [ 4:0] clock_fault;
  logic          clock_done;
  integer        reset_events = 0;
  logic   [31:0] value;
  wire           clk_i = sys_clk;
  apb4_if apb4 (
      .pclk   (sys_clk),
      .presetn(leaf_n[0])
  );
  apb4_if wdg_source (
      .pclk   (sys_clk),
      .presetn(leaf_n[0])
  );
  apb4_if wdg_apb (
      .pclk   (pclk),
      .presetn(leaf_n[1])
  );
  wdg_if wdg (
      .wdg_clk_i  (ref_clk),
      .wdg_rst_n_i(wdg_reset_n)
  );
  assign wdg.debug_halted_i = 1'b0;
  assign request            = wdg.reset_req_o;
  tiny_apb_async_bridge u_wdg_cdc (
      .src_clk_i  (sys_clk),
      .src_rst_n_i(leaf_n[0]),
      .dst_clk_i  (pclk),
      .dst_rst_n_i(leaf_n[1]),
      .disabled_i (1'b0),
      .src_apb4   (wdg_source),
      .dst_apb4   (wdg_apb)
  );
  tiny_clock_reset_subsystem u_backend (
      .ref_clk_i        (xin),
      .rst_n_i          (reset_n),
      .profile_i        (2'd0),
      .apply_i          (1'b0),
      .idle_i           (1'b1),
      .clients_idle_i   (1'b1),
      .warm_reset_i     (request),
      .system_request_i (1'b0),
      .command_ack_i    (1'b1),
      .timeout_i        (32'd240000),
      .current_profile_o(current_profile),
      .ref_clk_o        (ref_clk),
      .sys_clk_o        (sys_clk),
      .pclk_o           (pclk),
      .system_reset_n_o (backend_reset_n),
      .fault_code_o     (clock_fault),
      .done_o           (clock_done)
  );
  tiny_reset_tree #(
      .LeafCount   (2),
      .SplitDomains(1)
  ) u_tree (
      .clk_i               (sys_clk),
      .por_clk_i           (ref_clk),
      .leaf_clk_i          ({pclk, sys_clk}),
      .backend_reset_n_i   (backend_reset_n),
      .rst_n_i             (reset_n),
      .watchdog_reset_req_i(request),
      .por_rst_n_o         (por_n),
      .system_rst_n_o      (system_n),
      .leaf_rst_n_o        (leaf_n),
      .cpu_ready_rst_n_o   (ready)
  );
  // Same functional-reset dependency as the production Tiny integration.
  rst_sync #(
      .STAGE(5)
  ) u_wdg_functional_reset (
      .clk_i  (ref_clk),
      .rst_n_i(por_n && backend_reset_n),
      .rst_n_o(wdg_reset_n)
  );
  apb4_wdg #(
      .WDG_CLOCK_HZ(24000000)
  ) u_wdg (
      .apb4(wdg_apb),
      .wdg (wdg)
  );
  tiny_sysctrl u_rcu (
      .clk_i           (sys_clk),
      .rst_n_i         (leaf_n[0]),
      .clk_ref_i       (ref_clk),
      .rst_ref_n_i     (por_n),
      .apb4            (apb4),
      .fault_valid_i   (1'b0),
      .fault_count_i   (4'd0),
      .fault_addr_i    (32'd0),
      .fault_write_i   (1'b0),
      .fault_master_i  (2'd0),
      .fault_resp_i    (2'd0),
      .cpu_wait_i      (64'd0),
      .dma_wait_i      (64'd0),
      .rtc_wake_i      (1'b0),
      .clock_done_i    (clock_done),
      .clock_fault_i   (clock_fault),
      .clock_current_i (current_profile),
      .pll_locked_i    (1'b0),
      .pll_selected_i  (1'b0),
      .warm_reset_i    (!backend_reset_n),
      .watchdog_reset_i(request),
      .hart_reset_i    (1'b0),
      .periph_done_i   (1'b0),
      .periph_fault_i  (5'd0),
      .gate_actual_i   (14'd0),
      .reset_done_i    (14'd0),
      .clkout_idle_i   (1'b1)
  );
  always @(posedge request) if (reset_n) reset_events++;
  task automatic watchdog_access(input logic [31:0] address, input logic write_access,
                                 input logic [31:0] data, output logic [31:0] observed);
    integer budget;
    @(negedge clk_i);
    wdg_source.paddr  = address;
    wdg_source.pwrite = write_access;
    wdg_source.pwdata = data;
    wdg_source.pstrb  = write_access ? 4'hf : 4'h0;
    wdg_source.psel   = 1;
    @(negedge clk_i);
    wdg_source.penable = 1;
    budget             = 0;
    while (wdg_source.pready !== 1'b1 && budget < 512) begin
      @(negedge clk_i);
      budget++;
    end
    if (budget == 512 || wdg_source.pslverr !== 0) $fatal(1, "watchdog APB failed");
    observed = wdg_source.prdata;
    @(negedge clk_i);
    wdg_source.psel    = 0;
    wdg_source.penable = 0;
  endtask
  `include "apb4_bfm.svh"
  initial begin
    wdg_source.paddr   = 0;
    wdg_source.pwrite  = 0;
    wdg_source.pwdata  = 0;
    wdg_source.pstrb   = 0;
    wdg_source.psel    = 0;
    wdg_source.penable = 0;
    wdg_source.pprot   = 0;
    apb4_idle();
    #1 reset_n = 0;
    repeat (20) @(negedge xin);
    reset_n = 1;
    wait (ready);
    repeat (30) @(negedge ref_clk);
    for (integer iteration = 1; iteration <= 2; iteration++) begin
      watchdog_access(32'h008, 1, 1, value);
      watchdog_access(32'h00c, 1, 64, value);
      watchdog_access(32'h018, 1, 4, value);
      watchdog_access(32'h000, 1, 1, value);
      wait (request);
      wait (!backend_reset_n);
      #1;
      if (system_n !== 0 || leaf_n !== 0 || wdg_reset_n !== 0)
        $fatal(1, "watchdog did not reset all functional endpoints");
      wait (backend_reset_n);
      wait (ready && wdg_reset_n);
      repeat (30) @(negedge ref_clk);
      apb4_read(32'h130, 0, value);
      if (value !== 32'd5 || request || reset_events != iteration ||
          u_wdg.u_wdg_core.s_reset_count_q !== 0 || current_profile !== 0)
        $fatal(1, "watchdog warm-reset cause/functional state mismatch cause=%h", value);
      watchdog_access(32'h000, 1, 2, value);
      repeat (30) @(negedge clk_i);
      watchdog_access(32'h024, 0, 0, value);
      if ((value & 3) !== 1) $fatal(1, "post-reset watchdog snapshot did not complete");
      watchdog_access(32'h040, 0, 0, value);
      if (value !== 0) $fatal(1, "watchdog functional reset counter did not clear");
    end
    $display("SIM_TEST_PASS Tiny watchdog reset cause retained and functional state reset twice");
    $finish;
  end
  initial begin
    #200000;
    $fatal(1, "SIM_TEST_TIMEOUT Tiny watchdog reset");
  end
endmodule
