`timescale 1ns / 1ps
`include "sysctrl_define.svh"

module tiny_sysctrl_tb;
  logic clk_i = 0;
  logic rst_n_i = 0;
  always #5 clk_i = !clk_i;
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  logic        fault_valid = 0;
  logic [ 3:0] fault_count = 1;
  logic [ 1:0] fault_master = 1;
  logic [31:0] fault_addr = 32'h38000000;
  logic [63:0] cpu_wait = 64'h123456789abcdef0;
  logic [63:0] dma_wait = 64'h1122334455667788;
  logic        wake = 0;
  logic perf_enable, perf_clear, done, pass;
  logic [ 7:0] code;
  logic [31:0] value;
  logic [31:0] xin_hz, ref_hz, sys_hz, mem_hz, pclk_hz, clint_hz;
  logic [1:0] rcu_current;
  logic       rcu_busy;
  logic       clock_apply;
  logic [1:0] clock_profile;
  logic       clock_done = 0;
  logic [1:0] clock_current = 0;
  logic       clock_apply_seen = 0;
  logic [4:0] rcu_fault_event = 0;
  logic warm_reset = 0, rcu_irq;
  always @(posedge clk_i) if (clock_apply) clock_apply_seen <= 1;
  tiny_sysctrl u_dut (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .clk_ref_i       (clk_i),
      .rst_ref_n_i     (rst_n_i),
      .rcu_link_ready_o(),
      .apb4            (apb4),
      .fault_valid_i   (fault_valid),
      .fault_count_i   (fault_count),
      .fault_addr_i    (fault_addr),
      .fault_write_i   (1'b1),
      .fault_master_i  (fault_master),
      .fault_resp_i    (2'b11),
      .cpu_wait_i      (cpu_wait),
      .dma_wait_i      (dma_wait),
      .rtc_wake_i      (wake),
      .clock_done_i    (clock_done),
      .clock_fault_i   (rcu_fault_event),
      .clock_current_i (clock_current),
      .periph_done_i   (1'b0),
      .periph_fault_i  (5'd0),
      .gate_actual_i   (14'd0),
      .reset_done_i    (14'd0),
      .periph_apply_o  (),
      .periph_reset_o  (),
      .periph_request_o(),
      .clkout_control_o(),
      .clkout_idle_i   (1'b1),
      .pll_locked_i    (1'b0),
      .pll_selected_i  (1'b0),
      .warm_reset_i    (warm_reset),
      .watchdog_reset_i(1'b0),
      .hart_reset_i    (1'b0),
      .system_reset_o  (),
      .rcu_irq_o       (rcu_irq),
      .clock_timeout_o (),
      .perf_enable_o   (perf_enable),
      .perf_clear_o    (perf_clear),
      .test_done_o     (done),
      .test_pass_o     (pass),
      .test_code_o     (code),
      .xin_hz_o        (xin_hz),
      .ref_hz_o        (ref_hz),
      .sys_hz_o        (sys_hz),
      .mem_hz_o        (mem_hz),
      .pclk_hz_o       (pclk_hz),
      .clint_hz_o      (clint_hz),
      .rcu_current_o   (rcu_current),
      .rcu_busy_o      (rcu_busy),
      .clock_apply_o   (clock_apply),
      .clock_profile_o (clock_profile)
  );
  `include "apb4_bfm.svh"
  initial begin
    apb4_idle();
    repeat (5) @(negedge clk_i);
    rst_n_i = 1;
    repeat (40) @(negedge clk_i);
    apb4_read(32'h100, 0, value);
    if (value != 32'h54524355) $fatal(1, "RCU identity mismatch");
    apb4_read(32'h104, 0, value);
    if (value != 32'h00010000) $fatal(1, "RCU version mismatch");
    apb4_read(32'h108, 0, value);
    if (value != 32'h00000203) $fatal(1, "RCU capability mismatch");
    apb4_read(32'h158, 0, value);
    if (value != 0) $fatal(1, "unsupported target capability was advertised");
    apb4_read(32'h148, 0, value);
    if (value != 24_000_000 || sys_hz != 24_000_000 || mem_hz != 24_000_000 ||
        pclk_hz != 24_000_000 || clint_hz != 1_000_000)
      $fatal(1, "SAFE24 rates mismatch");
    apb4_write(32'h10c, 2, 4'hf, 0);
    apb4_write(32'h114, 1, 4'hf, 1);
    apb4_read(32'h134, 0, value);
    if (!value[0] || rcu_current != 0) $fatal(1, "unsupported PLL request was accepted");
    apb4_write(32'h134, 1, 4'hf, 0);
    apb4_write(32'h10c, 1, 4'hf, 0);
    apb4_write(32'h114, 1, 4'hf, 0);
    if (!clock_apply_seen || clock_profile != 1) $fatal(1, "clock apply handshake missing");
    // APB acknowledgement is not clock completion. BUSY/current persist
    // until the actual backend supplies its committed result.
    apb4_read(32'h118, 0, value);
    if (!value[0] || rcu_current != 0) $fatal(1, "RCU completed before backend");
    apb4_write(32'h10c, 0, 4'hf, 1);
    apb4_write(32'h11c, 1, 4'hf, 1);
    apb4_write(32'h120, 0, 4'hf, 1);
    apb4_write(32'h128, 0, 4'hf, 1);
    apb4_write(32'h114, 8, 4'hf, 1);
    apb4_read(32'h10c, 0, value);
    if (value != 1) $fatal(1, "BUSY write changed staged profile");
    apb4_read(32'h11c, 0, value);
    if (value != 240000) $fatal(1, "BUSY write changed timeout");
    apb4_write(32'h134, 1, 4'hf, 0);
    @(negedge clk_i);
    clock_current = 1;
    clock_done    = 1;
    @(negedge clk_i);
    clock_done = 0;
    apb4_read(32'h110, 0, value);
    if (value != 1 || rcu_current != 1 || sys_hz != 24_000_000)
      $fatal(1, "external profile commit mismatch");
    apb4_read(32'h118, 0, value);
    if (value[1] || value[4]) begin
      $display("RCU status=%h fault=%h current=%h", value, u_dut.s_rcu_fault_q, rcu_current);
      $fatal(1, "RCU status mismatch");
    end
    apb4_write(32'h120, 1, 4'hf, 1);
    apb4_write(32'h114, 2, 4'hf, 1);
    apb4_read(32'h134, 0, value);
    if (!value[0]) $fatal(1, "unsupported gate request was accepted");
    apb4_write(32'h134, 1, 4'hf, 0);
    apb4_write(32'h10c, 4, 4'hf, 1);
    apb4_write(32'h11c, 0, 4'hf, 1);
    apb4_write(32'h13c, 4, 4'hf, 1);
    apb4_write(32'h130, 64, 4'hf, 1);
    apb4_write(32'h134, 32, 4'hf, 1);
    apb4_write(32'h138, 4, 4'hf, 1);
    apb4_write(32'h114, 3, 4'hf, 1);
    apb4_write(32'h15c, 1, 4'hf, 1);
    apb4_write(32'h15c, 32'h105, 4'hf, 1);
    apb4_write(32'h15c, 32'h101, 4'hf, 0);
    apb4_write(32'h15c, 32'h201, 4'hf, 1);
    apb4_write(32'h114, 1, 4'hf, 1);
    apb4_read(32'h15c, 0, value);
    if (value != 32'h101) $fatal(1, "live CLKOUT change was accepted");
    apb4_write(32'h15c, 0, 4'hf, 0);
    apb4_write(32'h134, 31, 4'hf, 0);
    apb4_write(32'h138, 3, 4'hf, 0);
    apb4_write(32'h13c, 3, 4'hf, 0);
    if (rcu_irq) $fatal(1, "cleared RCU IRQ remains asserted");
    @(negedge clk_i);
    rcu_fault_event = 8;
    apb4_write(32'h134, 8, 4'hf, 0);
    apb4_write(32'h138, 2, 4'hf, 0);
    apb4_write(32'h130, 8, 4'hf, 0);
    @(negedge clk_i);
    rcu_fault_event = 0;
    apb4_read(32'h134, 0, value);
    if (value != 8 || !rcu_irq) $fatal(1, "RCU W1C lost simultaneous fault/IRQ");
    apb4_read(32'h130, 0, value);
    if (!value[3]) $fatal(1, "RCU W1C lost simultaneous reset cause");
    @(negedge clk_i);
    warm_reset = 1;
    @(negedge clk_i);
    warm_reset = 0;
    apb4_read(32'h138, 0, value);
    if (value != 2 || rcu_irq) $fatal(1, "warm reset IRQ retention/enable mismatch");
    apb4_read(32'h134, 0, value);
    if (value != 8 || rcu_current != 0) $fatal(1, "warm reset fault/profile mismatch");
    apb4_read(32'h114, 1, value);
    apb4_write(`APB4_SYSCTRL__HP_CTRL, 1, 4'hf, 1);
    apb4_write(`APB4_SYSCTRL__PLL_CMD, 1, 4'hf, 1);
    apb4_read(32'hfff, 1, value);
    apb4_write(`APB4_SYSCTRL__TEST_STATUS, 32'h80001201, 4'h1, 1);
    if (done) $fatal(1, "partial terminal write changed state");
    apb4_write(`APB4_SYSCTRL__TEST_STATUS, 32'h00001201, 4'hf, 0);
    if (done) $fatal(1, "invalid terminal write changed state");
    apb4_write(`APB4_SYSCTRL__TEST_STATUS, 32'h80001201, 4'hf, 0);
    apb4_write(`APB4_SYSCTRL__TEST_STATUS, 32'h80009900, 4'hf, 0);
    if (!done || !pass || code != 8'h12) $fatal(1, "terminal status is not sticky");
    apb4_write(`APB4_SYSCTRL__PERF_CTRL, 5, 4'hf, 0);
    cpu_wait = 0;
    dma_wait = 0;
    apb4_read(`APB4_SYSCTRL__PERF_MGMT_WAIT_LO, 0, value);
    if (!perf_enable || value != 32'h9abcdef0) $fatal(1, "CPU snapshot changed");
    apb4_read(`APB4_SYSCTRL__PERF_DMA_WAIT_HI, 0, value);
    if (value != 32'h11223344) $fatal(1, "DMA snapshot changed");
    @(negedge clk_i);
    fault_valid = 1;
    @(negedge clk_i);
    fault_valid = 0;
    fault_addr  = 32'hffffffff;
    @(negedge clk_i);
    fault_valid = 1;
    @(negedge clk_i);
    fault_valid = 0;
    apb4_read(`APB4_SYSCTRL__FAULT_ADDR, 0, value);
    if (value != 32'h38000000) $fatal(1, "first fault overwritten");
    apb4_read(`APB4_SYSCTRL__FAULT_COUNT, 0, value);
    if (value != 2) $fatal(1, "fault count mismatch");
    apb4_write(`APB4_SYSCTRL__FAULT_STATUS, 1, 4'hf, 0);
    apb4_read(`APB4_SYSCTRL__FAULT_STATUS, 0, value);
    if (value[0]) $fatal(1, "fault W1C failed");
    // Multiple terminal events count independently. A hardware event on the
    // clear edge wins and records the new first owner without clearing count.
    fork
      apb4_write(`APB4_SYSCTRL__FAULT_STATUS, 1, 4'hf, 0);
      begin
        wait (apb4.psel && apb4.penable && apb4.pwrite);
        fault_count  = 5;
        fault_master = 2;
        fault_addr   = 32'h30018004;
        fault_valid  = 1;
        @(posedge clk_i);
        @(negedge clk_i);
        fault_valid = 0;
      end
    join
    apb4_read(`APB4_SYSCTRL__FAULT_COUNT, 0, value);
    if (value != 7) $fatal(1, "concurrent fault count lost");
    apb4_read(`APB4_SYSCTRL__FAULT_MASTER, 0, value);
    if (value != 2) $fatal(1, "third owner truncated");
    apb4_read(`APB4_SYSCTRL__FAULT_DETAIL, 0, value);
    if (value != 3) $fatal(1, "raw AXI response changed");
    apb4_read(`APB4_SYSCTRL__FAULT_STATUS, 0, value);
    if (!value[0]) $fatal(1, "W1C defeated simultaneous hardware event");
    // Seed only the counter corner, then exercise the actual wide adder and
    // register update. Billions of event pulses are not useful simulation.
    @(negedge clk_i);
    force u_dut.u_fault_count_reg.dat_o = 32'hfffffffc;
    fault_count = 8;
    fault_valid = 1;
    @(posedge clk_i);
    @(negedge clk_i);
    release u_dut.u_fault_count_reg.dat_o;
    @(posedge clk_i);
    @(negedge clk_i);
    fault_valid = 0;
    apb4_read(`APB4_SYSCTRL__FAULT_COUNT, 0, value);
    if (value != 32'hffffffff) $fatal(1, "multi-event saturation wrapped");
    @(negedge clk_i);
    wake = 1;
    @(negedge clk_i);
    wake = 0;
    apb4_read(`APB4_SYSCTRL__RTC_WAKE_STATUS, 0, value);
    if (value != 2) $fatal(1, "RTC sticky wake missing");
    apb4_write(`APB4_SYSCTRL__RTC_WAKE_STATUS, 2, 4'hf, 0);
    apb4_read(`APB4_SYSCTRL__RTC_WAKE_STATUS, 0, value);
    if (value != 0) $fatal(1, "RTC wake W1C failed");
    @(negedge clk_i);
    rst_n_i = 0;
    repeat (3) @(negedge clk_i);
    if (done || perf_enable) $fatal(1, "reset failed");
    $display("SIM_TEST_PASS Tiny SYSCTRL");
    $finish;
  end
  initial begin
    #100000;
    $fatal(1, "SIM_TEST_TIMEOUT Tiny SYSCTRL");
  end
endmodule
