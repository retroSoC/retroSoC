// P7-only assertions over production paths. No DUT state is written.
logic s_p7_monitor = 0;
longint unsigned s_p7_gated_cycles = 0, s_p7_dma_gated_responses = 0;
integer       s_p7_warm_resets = 0;
logic   [3:0] s_p7_profiles = 0;
initial s_p7_monitor = $test$plusargs("p7_monitor");
initial begin
  if ($test$plusargs("p7_monitor") || $test$plusargs("p7_cold_reset_probe")) begin
    wait (s_rst_n === 1'b0);
    @(posedge s_rst_n);
    wait (u_dut.u_soc.s_cpu_boot_ready === 1'b1);
    repeat (2) @(negedge u_dut.u_soc.s_ref_clk);
    // Case comparisons require the exact known reset values in both simulators.
    if (u_dut.u_soc.u_sysctrl.s_reset_cause_q !== 32'd1 ||
        u_dut.u_soc.u_sysctrl.s_rcu_fault_q !== 32'd0 ||
        u_dut.u_soc.s_backend_current !== 2'd0 || u_dut.u_soc.s_gate_request !== 15'd0)
      $fatal(
          1,
          "SIM_TEST_FAIL P7 cold reset state cause=%h fault=%h profile=%h gates=%h",
          u_dut.u_soc.u_sysctrl.s_reset_cause_q,
          u_dut.u_soc.u_sysctrl.s_rcu_fault_q,
          u_dut.u_soc.s_backend_current,
          u_dut.u_soc.s_gate_request
      );
    if ($test$plusargs("p7_cold_reset_probe")) begin
      $display("P7_COLD_RESET_PASS");
      $finish;  // Diagnostic only; never emits the full Tiny acceptance marker.
    end
  end
end
always @(posedge u_dut.u_soc.s_exec_clk) begin
  if (s_p7_monitor && u_dut.u_soc.s_actual_gate[0]) begin
    s_p7_gated_cycles++;
    if (u_dut.u_soc.u_masters_axi4_if[1].bvalid && u_dut.u_soc.u_masters_axi4_if[1].bready)
      s_p7_dma_gated_responses++;
  end
end
always @(posedge u_dut.u_soc.s_ref_clk) begin
  if (s_p7_monitor && u_dut.u_soc.s_clock_done) begin
    s_p7_profiles[u_dut.u_soc.s_backend_current] = 1;
    $display("P7_CLOCK_COMMIT profile=%0d sys=%0d mem=%0d pclk=%0d", u_dut.u_soc.s_backend_current,
             u_dut.u_soc.s_backend_sys_hz, u_dut.u_soc.s_backend_mem_hz,
             u_dut.u_soc.s_backend_pclk_hz);
    $fflush();
  end
  if (s_p7_monitor && u_dut.u_soc.s_system_reset) begin
    s_p7_warm_resets++;
    $display("P7_SOFTWARE_RESET request=%0d", s_p7_warm_resets);
    $fflush();
  end
end
final begin
  if (s_p7_monitor && u_dut.s_test_done && u_dut.s_test_pass) begin
    if (s_p7_gated_cycles == 0 || s_p7_dma_gated_responses == 0 || s_p7_warm_resets != 1)
      $fatal(1, "SIM_TEST_FAIL P7 WFI/DMA/software-reset coverage");
`ifdef HAVE_PLL
    if ((s_p7_profiles & 4'b1101) != 4'b1101) $fatal(1, "SIM_TEST_FAIL P7 PLL profile coverage");
`else
    if ((s_p7_profiles & 4'b0011) != 4'b0011)
      $fatal(1, "SIM_TEST_FAIL P7 external profile coverage");
`endif
    $display("P7_LIFECYCLE_PASS gated_cycles=%0d dma_responses_while_gated=%0d warm_resets=%0d",
             s_p7_gated_cycles, s_p7_dma_gated_responses, s_p7_warm_resets);
  end
end
