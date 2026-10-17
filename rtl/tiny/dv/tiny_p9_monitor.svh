// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
// Passive acceptance progress. Unlike tiny_p9_diag, this never calls $finish.
// Counters are sampled on their native clocks. The REF report is a set of
// latest domain samples, not an atomic CDC snapshot or a retirement counter.
bit              s_p9_monitor_enabled = 0;
integer          s_p9_monitor_file = 0;
string           s_p9_monitor_path;
longint unsigned s_p9_monitor_ref = 0;
longint unsigned s_p9_monitor_fetch = 0, s_p9_monitor_data = 0;
longint unsigned s_p9_monitor_vsync = 0, s_p9_monitor_vsync_ref = 0;
longint unsigned s_p9_monitor_frame_start = 0, s_p9_monitor_frame_done = 0;
longint unsigned s_p9_monitor_aw = 0, s_p9_monitor_wbytes = 0;
longint unsigned s_p9_monitor_b = 0, s_p9_monitor_rbytes = 0;
longint unsigned s_p9_monitor_bus_errors = 0;
logic [31:0] s_p9_monitor_dma_bytes = 0, s_p9_monitor_dma_remaining = 0;
logic s_p9_monitor_dma_busy = 0, s_p9_monitor_dma_error = 0;
logic       s_p9_monitor_dvp_active = 0;
logic [5:0] s_p9_monitor_dvp_errors = 0;
longint unsigned s_p9_monitor_dma_ref = 0, s_p9_monitor_dvp_ref = 0;
longint unsigned s_p9_monitor_mem_ref = 0;

initial begin
  s_p9_monitor_enabled = $test$plusargs("tiny_p9_monitor");
  if (s_p9_monitor_enabled) begin
    if ($test$plusargs("tiny_p9_diag") || $test$plusargs("tiny_p9_progress"))
      $fatal(1, "SIM_TEST_FAIL P9 monitor conflicts with diagnostic or legacy progress mode");
    if (!$test$plusargs("tiny_p9_camera"))
      $fatal(1, "SIM_TEST_FAIL P9 monitor requires camera mode");
    if (!$value$plusargs("tiny_p9_monitor_log=%s", s_p9_monitor_path))
      $fatal(1, "SIM_TEST_FAIL P9 monitor requires log path");
    s_p9_monitor_file = $fopen(s_p9_monitor_path, "w");
    if (s_p9_monitor_file == 0) $fatal(1, "SIM_TEST_FAIL P9 monitor cannot open log");
    $fdisplay(s_p9_monitor_file,
              "P9_MONITOR_BEGIN version=1 ref_interval=100000 native_samples=1 early_stop=0");
    $fflush(s_p9_monitor_file);
  end
end

always @(posedge s_clk) if (s_p9_monitor_enabled) s_p9_monitor_ref++;
always @(posedge s_dvp_vsync) begin
  if (s_p9_monitor_enabled) begin
    s_p9_monitor_vsync++;
    s_p9_monitor_vsync_ref = s_p9_monitor_ref;
  end
end
always @(posedge u_dut.u_soc.s_exec_clk) begin
  if (s_p9_monitor_enabled && u_dut.u_soc.s_core_rst_n) begin
    if (u_dut.u_soc.u_cpu_mem.s_terminal[0]) s_p9_monitor_fetch++;
    if (u_dut.u_soc.u_cpu_mem.s_terminal[1]) s_p9_monitor_data++;
  end
end
always @(posedge u_dut.u_soc.s_dma_clk) begin
  if (s_p9_monitor_enabled && u_dut.u_soc.s_dma_rst_n) begin
    s_p9_monitor_dma_bytes     = u_dut.u_soc.u_dma.s_bytes_done[64+:32];
    s_p9_monitor_dma_remaining = u_dut.u_soc.u_dma.s_remaining[64+:32];
    s_p9_monitor_dma_busy      = u_dut.u_soc.u_dma.s_busy[2];
    s_p9_monitor_dma_error     = u_dut.u_soc.u_dma.s_error[2];
    s_p9_monitor_dma_ref       = s_p9_monitor_ref;
  end
end
always @(posedge u_dut.u_soc.s_dvp_clk) begin
  if (s_p9_monitor_enabled && u_dut.u_soc.s_dvp_rst_n) begin
    if (u_dut.u_soc.u_dvp.s_frame_start_event) s_p9_monitor_frame_start++;
    if (u_dut.u_soc.u_dvp.s_frame_done_event) s_p9_monitor_frame_done++;
    s_p9_monitor_dvp_active = u_dut.u_soc.u_dvp.s_active;
    s_p9_monitor_dvp_errors = u_dut.u_soc.u_dvp.s_err_flags_sys;
    s_p9_monitor_dvp_ref    = s_p9_monitor_ref;
  end
end
`define _P9_MON_AXI u_dut.u_soc.u_xpi_mem_axi4_if
always @(posedge u_dut.u_soc.s_backend_mem_clk) begin
  if (s_p9_monitor_enabled && u_dut.u_soc.s_xpi_rst_n) begin
    s_p9_monitor_mem_ref = s_p9_monitor_ref;
    if (`_P9_MON_AXI.awvalid && `_P9_MON_AXI.awready) s_p9_monitor_aw++;
    if (`_P9_MON_AXI.wvalid && `_P9_MON_AXI.wready)
      s_p9_monitor_wbytes += $countones(`_P9_MON_AXI.wstrb);
    if (`_P9_MON_AXI.bvalid && `_P9_MON_AXI.bready) begin
      s_p9_monitor_b++;
      if (`_P9_MON_AXI.bresp != 0) s_p9_monitor_bus_errors++;
    end
    if (`_P9_MON_AXI.rvalid && `_P9_MON_AXI.rready) begin
      s_p9_monitor_rbytes += 4;
      if (`_P9_MON_AXI.rresp != 0) s_p9_monitor_bus_errors++;
    end
  end
end
`undef _P9_MON_AXI

always @(negedge s_clk) begin
  if (s_p9_monitor_enabled && s_p9_monitor_ref % 100000 == 0) begin
    // Firmware UART is emitted character-by-character; a separate stream
    // prevents progress records from splitting strict P9 acceptance lines.
    $fdisplay(
        s_p9_monitor_file,
        "P9_PROGRESS ref=%0d vsync=%0d vsync_ref=%0d frames_started=%0d frames_done=%0d accepted_words=%0d delivered_words=%0d fifo_high_water=%0d backpressure=%0d dvp_active=%b dvp_errors=%h dma_busy=%b dma_bytes=%0d dma_remaining=%0d dma_error=%b xpi_aw=%0d xpi_wbytes=%0d xpi_b=%0d xpi_rbytes=%0d xpi_errors=%0d fetch_done=%0d data_done=%0d dma_ref=%0d dvp_ref=%0d mem_ref=%0d",
        s_p9_monitor_ref, s_p9_monitor_vsync, s_p9_monitor_vsync_ref, s_p9_monitor_frame_start,
        s_p9_monitor_frame_done, p9_accepted_words, p9_delivered_words, p9_fifo_high_water,
        p9_backpressure, s_p9_monitor_dvp_active, s_p9_monitor_dvp_errors, s_p9_monitor_dma_busy,
        s_p9_monitor_dma_bytes, s_p9_monitor_dma_remaining, s_p9_monitor_dma_error,
        s_p9_monitor_aw, s_p9_monitor_wbytes, s_p9_monitor_b, s_p9_monitor_rbytes,
        s_p9_monitor_bus_errors, s_p9_monitor_fetch, s_p9_monitor_data, s_p9_monitor_dma_ref,
        s_p9_monitor_dvp_ref, s_p9_monitor_mem_ref);
    $fflush(s_p9_monitor_file);
  end
end
