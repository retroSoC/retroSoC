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
  logic [31:0] fault_addr = 32'h38000000;
  logic [63:0] cpu_wait = 64'h123456789abcdef0;
  logic [63:0] dma_wait = 64'h1122334455667788;
  logic        wake = 0;
  logic perf_enable, perf_clear, done, pass;
  logic [ 7:0] code;
  logic [31:0] value;
  tiny_sysctrl u_dut (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .apb4          (apb4),
      .fault_valid_i (fault_valid),
      .fault_addr_i  (fault_addr),
      .fault_write_i (1'b1),
      .fault_master_i(1'b1),
      .fault_resp_i  (2'b11),
      .cpu_wait_i    (cpu_wait),
      .dma_wait_i    (dma_wait),
      .rtc_wake_i    (wake),
      .perf_enable_o (perf_enable),
      .perf_clear_o  (perf_clear),
      .test_done_o   (done),
      .test_pass_o   (pass),
      .test_code_o   (code)
  );
  `include "apb4_bfm.svh"
  initial begin
    apb4_idle();
    repeat (5) @(negedge clk_i);
    rst_n_i = 1;
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
