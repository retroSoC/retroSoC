`timescale 1ns / 1ps

module tiny_clock_reset_pll_tb;
  logic       ref_clk_i = 1'b0;
  logic       rst_n_i = 1'b0;
  logic [1:0] profile = 2'd0;
  logic       apply = 1'b0;
  logic [1:0] current_profile;
  logic busy, fault;
  logic idle = 1, clients_idle = 1;
  logic reset_session_n, done, pll_selected;
  logic [4:0] fault_code;
  logic [4:0] observed_faults = 0;
  always @(posedge ref_clk_i) observed_faults <= observed_faults | fault_code;
  logic sys_clk, mem_clk, pclk;
  logic sys_rst_n, mem_rst_n, pclk_rst_n;
  logic [31:0] xin_hz, ref_hz, sys_hz, mem_hz, pclk_hz;

  // Match the selected 24 MHz reference expected by the ICS55 PLL model.
  always #20.833333 ref_clk_i = !ref_clk_i;

  tiny_clock_reset_subsystem #(
      .RefClkHz(24_000_000),
      .HavePll (1'b1)
  ) u_dut (
      .ref_clk_i        (ref_clk_i),
      .rst_n_i          (rst_n_i),
      .profile_i        (profile),
      .apply_i          (apply),
      .idle_i           (idle),
      .clients_idle_i   (clients_idle),
      .warm_reset_i     (1'b0),
      .system_request_i (1'b0),
      .command_ack_i    (1'b1),
`ifdef TINY_PLL_SUCCESS
      .timeout_i        (32'd10000),
`else
      .timeout_i        (32'd512),
`endif
      .fault_code_o     (fault_code),
      .done_o           (done),
      .block_o          (),
      .ref_clk_o        (),
      .ref_rst_n_o      (),
      .system_reset_n_o (reset_session_n),
      .pll_locked_o     (),
      .pll_selected_o   (pll_selected),
      .current_profile_o(current_profile),
      .busy_o           (busy),
      .fault_o          (fault),
      .sys_clk_o        (sys_clk),
      .mem_clk_o        (mem_clk),
      .pclk_o           (pclk),
      .sys_rst_n_o      (sys_rst_n),
      .mem_rst_n_o      (mem_rst_n),
      .pclk_rst_n_o     (pclk_rst_n),
      .xin_hz_o         (xin_hz),
      .ref_hz_o         (ref_hz),
      .sys_hz_o         (sys_hz),
      .mem_hz_o         (mem_hz),
      .pclk_hz_o        (pclk_hz)
  );

  task automatic apply_profile(input logic [1:0] requested);
    begin
      @(negedge ref_clk_i);
      profile = requested;
      apply   = 1'b1;
      @(negedge ref_clk_i);
      apply = 1'b0;
    end
  endtask

  task automatic wait_done;
    integer cycles;
    begin
      cycles = 0;
      while (!done && cycles < 12000) begin
        @(negedge ref_clk_i);
        cycles++;
      end
      if (!done || busy) $fatal(1, "backend did not finish with bounded handshake");
    end
  endtask

  task automatic check_periods(input real sys_period, input real mem_period,
                               input real pclk_period);
    realtime started, measured;
    begin
      @(posedge sys_clk);
      started = $realtime;
      repeat (100) @(posedge sys_clk);
      measured = ($realtime - started) / 100.0;
      if (measured < sys_period - 0.01 || measured > sys_period + 0.01)
        $fatal(1, "SYS measured period %f expected %f", measured, sys_period);
      @(posedge mem_clk);
      started = $realtime;
      repeat (100) @(posedge mem_clk);
      measured = ($realtime - started) / 100.0;
      if (measured < mem_period - 0.02 || measured > mem_period + 0.02)
        $fatal(1, "MEM measured period %f expected %f", measured, mem_period);
      @(posedge pclk);
      started = $realtime;
      repeat (100) @(posedge pclk);
      measured = ($realtime - started) / 100.0;
      if (measured < pclk_period - 0.04 || measured > pclk_period + 0.04)
        $fatal(1, "PCLK measured period %f expected %f", measured, pclk_period);
    end
  endtask

  initial begin
    #1 rst_n_i = 1;
    #1 rst_n_i = 0;
    repeat (5) @(negedge ref_clk_i);
    rst_n_i = 1'b1;
    repeat (32) @(negedge ref_clk_i);
    idle         = 0;
    clients_idle = 0;
    apply_profile(2'd2);
    repeat (30) @(negedge ref_clk_i);
    if (!busy || current_profile != 0 || pll_selected)
      $fatal(1, "profile changed before accepted work drained");
    idle         = 1;
    clients_idle = 1;
    wait_done();
`ifdef TINY_PLL_SUCCESS
    if (fault || current_profile != 2 || sys_hz != 192_000_000 ||
        mem_hz != 96_000_000 || pclk_hz != 48_000_000)
      $fatal(1, "PLL192 commit mismatch");
    check_periods(1000.0 / 192.0, 1000.0 / 96.0, 1000.0 / 48.0);
    apply_profile(2'd3);
    wait_done();
    if (fault || current_profile != 3 || sys_hz != 240_000_000 ||
        mem_hz != 120_000_000 || pclk_hz != 60_000_000)
      $fatal(1, "PLL240 commit mismatch");
    check_periods(1000.0 / 240.0, 1000.0 / 120.0, 1000.0 / 60.0);
    apply_profile(2'd0);
    wait_done();
    if (current_profile != 0 || sys_hz != 24_000_000) $fatal(1, "SAFE24 return failed");
    check_periods(1000.0 / 24.0, 1000.0 / 24.0, 1000.0 / 24.0);
`ifdef TINY_PLL_NATIVE
    // Real locked ICS55 monitor must detect either stopped polarity, reset
    // the affected session, and restart from REF24 without a PLL edge.
    apply_profile(2'd2);
    wait_done();
    force u_dut.u_pll.gen_ecos.u_backend.pll_clk_o = 1'b0;
    repeat (400) @(negedge ref_clk_i);
    if (!observed_faults[3] || current_profile != 0 || !reset_session_n)
      $fatal(1, "PLL stopped-low recovery failed");
    check_periods(1000.0 / 24.0, 1000.0 / 24.0, 1000.0 / 24.0);
    release u_dut.u_pll.gen_ecos.u_backend.pll_clk_o;
    apply_profile(2'd3);
    wait_done();
    force u_dut.u_pll.gen_ecos.u_backend.pll_clk_o = 1'b1;
    repeat (400) @(negedge ref_clk_i);
    if (current_profile != 0 || !reset_session_n) $fatal(1, "PLL stopped-high recovery failed");
    check_periods(1000.0 / 24.0, 1000.0 / 24.0, 1000.0 / 24.0);
    release u_dut.u_pll.gen_ecos.u_backend.pll_clk_o;
`endif
    $display("SIM_TEST_PASS Tiny PLL transitions and measured clocks");
`else
    if (!fault || current_profile != 0 || observed_faults != 5'b00100 ||
        sys_hz != 24_000_000 || mem_hz != 24_000_000 || pclk_hz != 24_000_000)
      $fatal(1, "PLL lock timeout was not fail-closed");
    check_periods(1000.0 / 24.0, 1000.0 / 24.0, 1000.0 / 24.0);
    $display("SIM_TEST_PASS Tiny PLL lock-timeout backend");
`endif
    $finish;
  end

  initial begin
    #3000000;
    $fatal(1, "SIM_TEST_TIMEOUT Tiny PLL clock/reset backend");
  end
endmodule
