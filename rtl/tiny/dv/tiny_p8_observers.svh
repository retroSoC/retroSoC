// Verification-only MEM-clock observations. No DUT state is driven.
`define _P8_AXI u_dut.u_soc.u_xpi_mem_axi4_if
logic s_p8_previous_enable = 0;
logic s_p8_finished = 0;
longint unsigned s_p8_cycles = 0, s_p8_write_bytes = 0, s_p8_read_bytes = 0;
longint unsigned s_p8_stall_run[5], s_p8_stall_max[5];
longint unsigned s_p8_all_writes = 0;
integer s_p8_window = 0;
wire [4:0] s_p8_stalls = {
  `_P8_AXI.awvalid && !`_P8_AXI.awready,
  `_P8_AXI.wvalid && !`_P8_AXI.wready,
  `_P8_AXI.arvalid && !`_P8_AXI.arready,
  `_P8_AXI.bvalid && !`_P8_AXI.bready,
  `_P8_AXI.rvalid && !`_P8_AXI.rready
};
always @(posedge u_dut.u_soc.s_backend_mem_clk) begin
  if ($test$plusargs("tiny_p8_psram") && u_dut.u_soc.s_xpi_rst_n) begin
    if (`_P8_AXI.wvalid && `_P8_AXI.wready) s_p8_all_writes++;
    if (u_dut.u_soc.s_perf_enable) begin
      if (!s_p8_previous_enable) begin
        s_p8_cycles      = 0;
        s_p8_write_bytes = 0;
        s_p8_read_bytes  = 0;
        for (int i = 0; i < 5; i++) begin
          s_p8_stall_run[i] = 0;
          s_p8_stall_max[i] = 0;
        end
      end
      s_p8_cycles++;
      if (`_P8_AXI.wvalid && `_P8_AXI.wready) s_p8_write_bytes += $countones(`_P8_AXI.wstrb);
      if (`_P8_AXI.rvalid && `_P8_AXI.rready) s_p8_read_bytes += 4;
      for (int i = 0; i < 5; i++) begin
        s_p8_stall_run[i] = s_p8_stalls[i] ? s_p8_stall_run[i] + 1 : 0;
        if (s_p8_stall_run[i] > s_p8_stall_max[i]) s_p8_stall_max[i] = s_p8_stall_run[i];
      end
    end else if (s_p8_previous_enable) begin
      $display(
          "P8_XPI_WINDOW index=%0d mem_cycles=%0d write_bytes=%0d read_bytes=%0d cs_max=%0d aw_max=%0d w_max=%0d ar_max=%0d b_max=%0d r_max=%0d",
          s_p8_window, s_p8_cycles, s_p8_write_bytes, s_p8_read_bytes, s_p8_cs_max,
          s_p8_stall_max[0], s_p8_stall_max[1], s_p8_stall_max[2], s_p8_stall_max[3],
          s_p8_stall_max[4]);
      s_p8_window++;
    end
    s_p8_previous_enable = u_dut.u_soc.s_perf_enable;
    if (u_dut.s_test_done && !s_p8_finished) begin
      s_p8_finished = 1;
      if (!$test$plusargs("p8_absent") && (s_p8_window < 4 || s_p8_all_writes == 0))
        $fatal(1, "SIM_TEST_FAIL P8 missing mapped transport evidence");
      if ($test$plusargs("p8_absent") && s_p8_all_writes != 0)
        $fatal(1, "SIM_TEST_FAIL P8 absent device exposed mapped writes");
    end
  end
end
`undef _P8_AXI

time s_p8_cs_start, s_p8_cs_max = 0;
always @(negedge s_psram_csn) s_p8_cs_start = $time;
always @(posedge s_psram_csn) begin
  if ($test$plusargs("tiny_p8_psram") && s_p8_cs_start != 0) begin
    if ($time - s_p8_cs_start > 8000) $fatal(1, "SIM_TEST_FAIL P8 active CS exceeds 8 us");
    if ($time - s_p8_cs_start > s_p8_cs_max) s_p8_cs_max = $time - s_p8_cs_start;
  end
end
