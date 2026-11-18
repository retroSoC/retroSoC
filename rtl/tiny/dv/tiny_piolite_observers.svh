// verilog_syntax: parse-as-module-body
logic   [31:0] piolite_drive_value = 32'bz;
logic   [31:0] piolite_seen_mask = 0;
logic   [ 4:0] piolite_input_pin = 0;
logic          piolite_reset_program_seen = 0;
logic          piolite_reset_seen = 0;
logic          piolite_reported = 0;
logic          piolite_output_seen = 0;
integer        piolite_reset_countdown = 0;
integer        piolite_progress_cycles = 0;

assign s_gpio = piolite_drive_value;

always @(posedge s_clk) begin
  if ($test$plusargs("tiny_piolite_p3")) begin
    if (u_dut.u_soc.u_piolite_apb4_if.psel && u_dut.u_soc.u_piolite_apb4_if.penable &&
        u_dut.u_soc.u_piolite_apb4_if.pready && u_dut.u_soc.u_piolite_apb4_if.pwrite &&
        ((u_dut.u_soc.u_piolite_apb4_if.paddr[11:0] == 12'h214) ||
         (u_dut.u_soc.u_piolite_apb4_if.paddr[11:0] == 12'h294))) begin
      piolite_input_pin   = u_dut.u_soc.u_piolite_apb4_if.pwdata[4:0];
      piolite_drive_value = piolite_input_pin[0] ? (32'b1 << piolite_input_pin) : 32'b0;
    end
    if (u_dut.u_soc.u_piolite_apb4_if.psel && u_dut.u_soc.u_piolite_apb4_if.penable &&
        u_dut.u_soc.u_piolite_apb4_if.pready && !u_dut.u_soc.u_piolite_apb4_if.pwrite &&
        ((u_dut.u_soc.u_piolite_apb4_if.paddr[11:0] == 12'h244) ||
         (u_dut.u_soc.u_piolite_apb4_if.paddr[11:0] == 12'h2c4))) begin
      piolite_seen_mask[piolite_input_pin] = 1'b1;
      if (u_dut.u_soc.u_piolite_apb4_if.prdata[0] !== piolite_input_pin[0])
        $fatal(
            1,
            "SIM_TEST_FAIL PIOLITE_P3_OBSERVER input pin=%0d value=%b",
            piolite_input_pin,
            u_dut.u_soc.u_piolite_apb4_if.prdata[0]
        );
    end
    if (u_dut.u_soc.u_piolite.u_ctrl.imem_write &&
        (u_dut.u_soc.u_piolite.u_ctrl.imem_write_data == 16'h9000)) begin
      piolite_reset_program_seen = 1'b1;
    end
    if (piolite_reset_program_seen && u_dut.u_soc.u_piolite.u_ctrl.cmd_start[0] &&
        (u_dut.u_soc.s_gpio_user_select == 32'h8000_0000) && !piolite_reset_seen &&
        (piolite_reset_countdown == 0)) begin
      piolite_reset_countdown = 1;
    end
    if (piolite_reset_countdown != 0) begin
      piolite_reset_countdown = piolite_reset_countdown + 1;
      if (piolite_reset_countdown == 4) begin
        force u_dut.u_soc.s_gpio_rst_n = 1'b0;
        piolite_reset_seen = 1'b1;
      end
      if (piolite_reset_countdown == 5) begin
        release u_dut.u_soc.s_gpio_rst_n;
        piolite_reset_countdown = 0;
        $display("PIOLITE_P3_RESET seen=1");
      end
    end
    if (u_dut.u_soc.u_user_gpio_if.oe_o[4] && s_gpio[4] && !piolite_output_seen) begin
      piolite_output_seen = 1'b1;
      $display("PIOLITE_P3_OUTPUT pin=4 value=%b oe=%b", s_gpio[4],
               u_dut.u_soc.u_user_gpio_if.oe_o[4]);
    end
    if (u_dut.s_test_done && !piolite_reported) begin
      piolite_reported = 1'b1;
      $display("PIOLITE_P3_OBSERVATION mask=%08x reset_seen=%b output_oe=%08x", piolite_seen_mask,
               piolite_reset_seen, u_dut.u_soc.u_user_gpio_if.oe_o);
    end
  end
  if ($test$plusargs("tiny_piolite_progress")) begin
    piolite_progress_cycles = piolite_progress_cycles + 1;
    if ((piolite_progress_cycles % 100000) == 0) begin
      $display(
          "PIOLITE_P3_PROGRESS cycles=%0d live=%b idle=%b held=%b%b closing=%b%b dma_jobs=%b rcu_idle=%05x",
          piolite_progress_cycles, u_dut.u_soc.u_piolite.s_session_live,
          u_dut.u_soc.s_piolite_lifecycle_idle, u_dut.u_soc.u_piolite.s_tx_held,
          u_dut.u_soc.u_piolite.s_rx_held, u_dut.u_soc.u_piolite.s_tx_closing,
          u_dut.u_soc.u_piolite.s_rx_closing, u_dut.u_soc.s_piolite_dma_job,
          u_dut.u_soc.s_periph_idle_ref);
      if ($test$plusargs("tiny_piolite_trap")) begin
        $display("PIOLITE_P3_TRAP cycles=%0d cause_irq=%b cause=%x epc=%x", piolite_progress_cycles,
                 u_dut.u_soc.u_cpu.u_hazard3_cpu_2port.core.csr_u.mcause_irq,
                 u_dut.u_soc.u_cpu.u_hazard3_cpu_2port.core.csr_u.mcause_code,
                 u_dut.u_soc.u_cpu.u_hazard3_cpu_2port.core.csr_u.mepc);
        $display(
            "PIOLITE_P3_GUARD cycles=%0d start_ok=%b guard=%b handoff=%x filter=%x ready=%b imem=%x region=%x rx=%x",
            piolite_progress_cycles, u_dut.u_soc.u_piolite.u_reg.s_start_ok,
            u_dut.u_soc.u_piolite.u_ctrl.start_guard_ok, u_dut.u_soc.s_gpio_user_handoff,
            u_dut.u_soc.u_user_gpio_if.filter_enable_i, u_dut.u_soc.u_piolite.gpio_ready_i,
            u_dut.u_soc.u_piolite.u_ctrl.imem_valid, u_dut.u_soc.u_piolite.u_reg.s_region,
            u_dut.u_soc.u_piolite.u_ctrl.rx_level[0]);
        $display("PIOLITE_P3_CFG cycles=%0d cfg=%x", piolite_progress_cycles,
                 u_dut.u_soc.u_piolite.u_reg.s_cfg_q[0]);
      end
    end
  end
end
