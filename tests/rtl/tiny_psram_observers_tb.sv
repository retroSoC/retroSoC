// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
`timescale 1ns / 1ps
// Mock only observer inputs; execute the real included acceptance checks.
module tiny_psram_observers_tb;
  logic s_clk = 0;
  logic s_psram_csn = 1;
  logic s_dvp_vsync = 0;
  integer p9_accepted_words = 0, p9_delivered_words = 0;
  integer p9_fifo_high_water = 0, p9_backpressure = 0;
  tiny_psram_observer_dut u_dut (.clk_i(s_clk));
  always #5 s_clk = !s_clk;
  `include "tiny_p8_observers.svh"
  `include "tiny_p9_monitor.svh"

  initial begin
    repeat (3) @(negedge s_clk);
    if ($test$plusargs("cs_violation")) begin
      s_psram_csn = 0;
      #8010;
      s_psram_csn = 1;
      #20;
    end else begin
      s_psram_csn = 0;
      #100;
      s_psram_csn = 1;
      @(negedge s_clk);
    end
    if ($test$plusargs("windows") || $test$plusargs("short_windows")) begin
      repeat ($test$plusargs(
          "short_windows"
      ) ? 3 : 4) begin
        u_dut.u_soc.s_perf_enable = 1;
        repeat (2) @(negedge s_clk);
        u_dut.u_soc.s_perf_enable = 0;
        repeat (2) @(negedge s_clk);
      end
    end
    if ($test$plusargs("write")) begin
      u_dut.u_soc.u_xpi_mem_axi4_if.wvalid = 1;
      u_dut.u_soc.u_xpi_mem_axi4_if.wready = 1;
      u_dut.u_soc.u_xpi_mem_axi4_if.wstrb  = 4'hf;
      @(negedge s_clk);
      u_dut.u_soc.u_xpi_mem_axi4_if.wvalid = 0;
    end
    if ($test$plusargs("monitor_duration")) begin
      s_dvp_vsync                            = 1;
      u_dut.u_soc.u_cpu_mem.s_terminal       = 2'b11;
      u_dut.u_soc.u_dma.s_bytes_done[64+:32] = 16;
      u_dut.u_soc.u_dma.s_remaining[64+:32]  = 32;
      u_dut.u_soc.u_dma.s_busy[2]            = 1;
      repeat (5000010) @(negedge s_clk);
      if (s_p9_monitor_ref <= 5000000 || s_p9_monitor_fetch < 5000000 ||
          s_p9_monitor_data < 5000000 || s_p9_monitor_vsync != 1 ||
          s_p9_monitor_dma_bytes != 16 || s_p9_monitor_dma_remaining != 32 ||
          s_p9_monitor_wbytes != 4)
        $fatal(1, "SIM_TEST_FAIL observer counters or duration");
      $display("MONITOR_SURVIVED ref=%0d", s_p9_monitor_ref);
    end
    u_dut.s_test_done = 1;
    repeat (4) @(negedge s_clk);
    $display("SIM_TEST_PASS Tiny PSRAM observer fixture");
    $finish;
  end
endmodule

module tiny_psram_observer_dut (
    input logic clk_i
);
  logic s_test_done = 0;
  tiny_psram_observer_soc u_soc (.clk_i(clk_i));
endmodule

module tiny_psram_observer_soc (
    input logic clk_i
);
  wire s_backend_mem_clk = clk_i;
  wire s_exec_clk = clk_i;
  wire s_dma_clk = clk_i;
  wire s_dvp_clk = clk_i;
  logic s_xpi_rst_n = 1, s_core_rst_n = 1, s_dma_rst_n = 1, s_dvp_rst_n = 1;
  logic s_perf_enable = 0;
  tiny_psram_observer_bus u_xpi_mem_axi4_if ();
  tiny_psram_observer_cpu u_cpu_mem ();
  tiny_psram_observer_dma u_dma ();
  tiny_psram_observer_dvp u_dvp ();
endmodule

module tiny_psram_observer_bus;
  logic awvalid = 0, awready = 0, wvalid = 0, wready = 0;
  logic bvalid = 0, bready = 0, arvalid = 0, arready = 0, rvalid = 0, rready = 0;
  logic [3:0] wstrb = 0;
  logic [1:0] bresp = 0, rresp = 0;
endmodule

module tiny_psram_observer_cpu;
  logic [1:0] s_terminal = 0;
endmodule

module tiny_psram_observer_dma;
  logic [255:0] s_bytes_done = 0, s_remaining = 0;
  logic [7:0] s_busy = 0, s_error = 0;
endmodule

module tiny_psram_observer_dvp;
  logic s_frame_start_event = 0, s_frame_done_event = 0, s_active = 0;
  logic [5:0] s_err_flags_sys = 0;
endmodule
