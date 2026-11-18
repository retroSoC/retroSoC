// verilog_syntax: parse-as-module-body
logic   [31:0] piolite_drive_value = 32'bz;
logic   [31:0] piolite_seen_mask = 0;
logic   [ 4:0] piolite_input_pin = 0;
logic          piolite_reset_program_seen = 0;
logic          piolite_reset_start_pending = 0;
logic          piolite_reset_seen = 0;
logic          piolite_reported = 0;
logic          piolite_output_seen = 0;
integer        piolite_reset_countdown = 0;
integer        piolite_progress_cycles = 0;
integer        piolite_observer_fd = 0;
string         piolite_observer_path;

initial begin
  if ($test$plusargs(
          "tiny_piolite_p3"
      ) || $test$plusargs(
          "tiny_piolite_progress"
      ) || $test$plusargs(
          "tiny_piolite_trace"
      )) begin
    if (!$value$plusargs("tiny_piolite_observer_log=%s", piolite_observer_path))
      $fatal(1, "SIM_TEST_FAIL missing +tiny_piolite_observer_log=<path>");
    piolite_observer_fd = $fopen(piolite_observer_path, "w");
    if (piolite_observer_fd == 0) $fatal(1, "SIM_TEST_FAIL cannot open PIOLITE observer log");
  end
end

final begin
  if (piolite_observer_fd != 0) $fclose(piolite_observer_fd);
end

logic piolite_output_release = 1'b0;

assign (strong1, strong0) s_gpio_0  = piolite_output_release ? 1'bz : piolite_drive_value[0];
assign (strong1, strong0) s_gpio_1  = piolite_output_release ? 1'bz : piolite_drive_value[1];
assign (strong1, strong0) s_gpio_2  = piolite_output_release ? 1'bz : piolite_drive_value[2];
assign (strong1, strong0) s_gpio_3  = piolite_output_release ? 1'bz : piolite_drive_value[3];
assign (strong1, strong0) s_gpio_4  = piolite_output_release ? 1'bz : piolite_drive_value[4];
assign (strong1, strong0) s_gpio_5  = piolite_output_release ? 1'bz : piolite_drive_value[5];
assign (strong1, strong0) s_gpio_6  = piolite_output_release ? 1'bz : piolite_drive_value[6];
assign (strong1, strong0) s_gpio_7  = piolite_output_release ? 1'bz : piolite_drive_value[7];
assign (strong1, strong0) s_gpio_8  = piolite_output_release ? 1'bz : piolite_drive_value[8];
assign (strong1, strong0) s_gpio_9  = piolite_output_release ? 1'bz : piolite_drive_value[9];
assign (strong1, strong0) s_gpio_10 = piolite_output_release ? 1'bz : piolite_drive_value[10];
assign (strong1, strong0) s_gpio_11 = piolite_output_release ? 1'bz : piolite_drive_value[11];
assign (strong1, strong0) s_gpio_12 = piolite_output_release ? 1'bz : piolite_drive_value[12];
assign (strong1, strong0) s_gpio_13 = piolite_output_release ? 1'bz : piolite_drive_value[13];
assign (strong1, strong0) s_gpio_14 = piolite_output_release ? 1'bz : piolite_drive_value[14];
assign (strong1, strong0) s_gpio_15 = piolite_output_release ? 1'bz : piolite_drive_value[15];
assign (strong1, strong0) s_gpio_16 = piolite_output_release ? 1'bz : piolite_drive_value[16];
assign (strong1, strong0) s_gpio_17 = piolite_output_release ? 1'bz : piolite_drive_value[17];
assign (strong1, strong0) s_gpio_18 = piolite_output_release ? 1'bz : piolite_drive_value[18];
assign (strong1, strong0) s_gpio_19 = piolite_output_release ? 1'bz : piolite_drive_value[19];
assign (strong1, strong0) s_gpio_20 = piolite_output_release ? 1'bz : piolite_drive_value[20];
assign (strong1, strong0) s_gpio_21 = piolite_output_release ? 1'bz : piolite_drive_value[21];
assign (strong1, strong0) s_gpio_22 = piolite_output_release ? 1'bz : piolite_drive_value[22];
assign (strong1, strong0) s_gpio_23 = piolite_output_release ? 1'bz : piolite_drive_value[23];
assign (strong1, strong0) s_gpio_24 = piolite_output_release ? 1'bz : piolite_drive_value[24];
assign (strong1, strong0) s_gpio_25 = piolite_output_release ? 1'bz : piolite_drive_value[25];
assign (strong1, strong0) s_gpio_26 = piolite_output_release ? 1'bz : piolite_drive_value[26];
assign (strong1, strong0) s_gpio_27 = piolite_output_release ? 1'bz : piolite_drive_value[27];
assign (strong1, strong0) s_gpio_28 = piolite_output_release ? 1'bz : piolite_drive_value[28];
assign (strong1, strong0) s_gpio_29 = piolite_output_release ? 1'bz : piolite_drive_value[29];
assign (strong1, strong0) s_gpio_30 = piolite_output_release ? 1'bz : piolite_drive_value[30];
assign (strong1, strong0) s_gpio_31 = piolite_output_release ? 1'bz : piolite_drive_value[31];
logic [31:0] piolite_negedge_source = 0;
logic [31:0] piolite_negedge_filtered = 0;
logic [10:0] piolite_negedge_in_cfg = 0;
logic [ 3:0] piolite_uart_ctrl_q = 0;
logic        piolite_uart_rst_q = 1;

always @(negedge s_clk) begin
  if ($test$plusargs("tiny_piolite_trace")) begin
    piolite_negedge_source   = u_dut.u_soc.u_piolite.u_core.gen_sm[0].u_sm.s_source_value;
    piolite_negedge_filtered = u_dut.u_soc.u_gpio.u_gpio_core.s_input_filtered_q;
    piolite_negedge_in_cfg   = u_dut.u_soc.u_piolite.u_core.gen_sm[0].u_sm.s_in_pins;
  end
end

always @(posedge s_clk) begin
  if ($test$plusargs("tiny_piolite_p3")) begin
    if (u_dut.u_soc.u_piolite_apb4_if.psel && u_dut.u_soc.u_piolite_apb4_if.penable &&
        u_dut.u_soc.u_piolite_apb4_if.pready && u_dut.u_soc.u_piolite_apb4_if.pwrite &&
        ((u_dut.u_soc.u_piolite_apb4_if.paddr[11:0] == 12'h214) ||
         (u_dut.u_soc.u_piolite_apb4_if.paddr[11:0] == 12'h294))) begin
      piolite_input_pin   = u_dut.u_soc.u_piolite_apb4_if.pwdata[4:0];
      piolite_drive_value = piolite_input_pin[0] ? (32'b1 << piolite_input_pin) : 32'b0;
      $fdisplay(piolite_observer_fd, "PIOLITE_P3_BFM pin=%0d drive=%x pads=%x input=%x",
                piolite_input_pin, piolite_drive_value, s_gpio, u_dut.u_soc.u_piolite.gpio_input_i);
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
        (u_dut.u_soc.u_piolite.u_ctrl.imem_write_data == 16'h1001)) begin
      piolite_output_release = 1'b1;
    end
    if (piolite_output_seen && !u_dut.u_soc.s_gpio_user_select[4] &&
        !u_dut.u_soc.u_user_gpio_if.oe_o[4]) begin
      piolite_output_release = 1'b0;
    end
    if (u_dut.u_soc.u_piolite.u_ctrl.imem_write &&
        (u_dut.u_soc.u_piolite.u_ctrl.imem_write_data == 16'h9000)) begin
      piolite_reset_program_seen = 1'b1;
    end
    if (piolite_reset_program_seen && u_dut.u_soc.u_piolite.u_ctrl.cmd_start[0] &&
        (u_dut.u_soc.s_gpio_user_select == 32'h8000_0000) && !piolite_reset_seen &&
        (piolite_reset_countdown == 0)) begin
      piolite_reset_start_pending = 1'b1;
    end
    if (piolite_reset_start_pending && u_dut.u_soc.u_piolite_apb4_if.psel &&
        u_dut.u_soc.u_piolite_apb4_if.penable && u_dut.u_soc.u_piolite_apb4_if.pready &&
        !u_dut.u_soc.u_piolite_apb4_if.pwrite &&
        (u_dut.u_soc.u_piolite_apb4_if.paddr[11:0] == 12'h200)) begin
      piolite_reset_start_pending = 1'b0;
      $fdisplay(piolite_observer_fd, "PIOLITE_P3_RESET_START status=%x pc=%x",
                u_dut.u_soc.u_piolite_apb4_if.prdata,
                u_dut.u_soc.u_cpu.u_hazard3_cpu_2port.core.d_pc);
      if (u_dut.u_soc.u_piolite_apb4_if.prdata[2:0] == 3'd1) piolite_reset_countdown = 1;
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
        $fdisplay(piolite_observer_fd, "PIOLITE_P3_RESET seen=1");
      end
    end
    if (piolite_reset_seen && u_dut.u_soc.u_piolite_apb4_if.psel &&
        u_dut.u_soc.u_piolite_apb4_if.penable && u_dut.u_soc.u_piolite_apb4_if.pready) begin
      $fdisplay(
          piolite_observer_fd,
          "PIOLITE_P3_RECOVERY_APB cycles=%0d addr=%x write=%b wdata=%x rdata=%x error=%b select=%x owned=%x ready=%b pc=%x",
          piolite_progress_cycles, u_dut.u_soc.u_piolite_apb4_if.paddr,
          u_dut.u_soc.u_piolite_apb4_if.pwrite, u_dut.u_soc.u_piolite_apb4_if.pwdata,
          u_dut.u_soc.u_piolite_apb4_if.prdata, u_dut.u_soc.u_piolite_apb4_if.pslverr,
          u_dut.u_soc.s_gpio_user_select, u_dut.u_soc.u_piolite.user_select_i,
          u_dut.u_soc.u_piolite.gpio_ready_i, u_dut.u_soc.u_cpu.u_hazard3_cpu_2port.core.d_pc);
    end
    if (piolite_reset_seen && u_dut.u_soc.u_gpio_apb4_if.psel &&
        u_dut.u_soc.u_gpio_apb4_if.penable && u_dut.u_soc.u_gpio_apb4_if.pready) begin
      $fdisplay(
          piolite_observer_fd,
          "PIOLITE_P3_RECOVERY_GPIO cycles=%0d addr=%x write=%b wdata=%x rdata=%x error=%b select=%x handoff=%x alt=%x oe=%x pc=%x",
          piolite_progress_cycles, u_dut.u_soc.u_gpio_apb4_if.paddr,
          u_dut.u_soc.u_gpio_apb4_if.pwrite, u_dut.u_soc.u_gpio_apb4_if.pwdata,
          u_dut.u_soc.u_gpio_apb4_if.prdata, u_dut.u_soc.u_gpio_apb4_if.pslverr,
          u_dut.u_soc.s_gpio_user_select, u_dut.u_soc.s_gpio_user_handoff,
          u_dut.u_soc.s_gpio_alt_enable, u_dut.u_soc.s_gpio_output_enable,
          u_dut.u_soc.u_cpu.u_hazard3_cpu_2port.core.d_pc);
    end
    if (piolite_reset_seen && u_dut.u_soc.u_sysctrl_apb4_if.psel &&
        u_dut.u_soc.u_sysctrl_apb4_if.penable && u_dut.u_soc.u_sysctrl_apb4_if.pready &&
        (u_dut.u_soc.u_sysctrl_apb4_if.paddr[11:8] == 4'h1)) begin
      $fdisplay(
          piolite_observer_fd,
          "PIOLITE_P3_RECOVERY_RCU cycles=%0d addr=%x write=%b wdata=%x rdata=%x error=%b pc=%x",
          piolite_progress_cycles, u_dut.u_soc.u_sysctrl_apb4_if.paddr,
          u_dut.u_soc.u_sysctrl_apb4_if.pwrite, u_dut.u_soc.u_sysctrl_apb4_if.pwdata,
          u_dut.u_soc.u_sysctrl_apb4_if.prdata, u_dut.u_soc.u_sysctrl_apb4_if.pslverr,
          u_dut.u_soc.u_cpu.u_hazard3_cpu_2port.core.d_pc);
    end
    if (u_dut.u_soc.u_user_gpio_if.oe_o[4] && s_gpio[4] && !piolite_output_seen) begin
      piolite_output_seen = 1'b1;
      $fdisplay(piolite_observer_fd, "PIOLITE_P3_OUTPUT pin=4 value=%b oe=%b", s_gpio[4],
                u_dut.u_soc.u_user_gpio_if.oe_o[4]);
    end
    if (u_dut.s_test_done && !piolite_reported) begin
      piolite_reported = 1'b1;
      $fdisplay(piolite_observer_fd,
                "PIOLITE_P3_OBSERVATION mask=%08x reset_seen=%b output_oe=%08x", piolite_seen_mask,
                piolite_reset_seen, u_dut.u_soc.u_user_gpio_if.oe_o);
    end
    if (piolite_reset_seen) $fflush(piolite_observer_fd);
  end
  if ($test$plusargs("tiny_piolite_progress") || $test$plusargs("tiny_piolite_trace")) begin
    piolite_progress_cycles = piolite_progress_cycles + 1;
    if ((piolite_progress_cycles % 100000) == 0) begin
      if ($test$plusargs("tiny_piolite_progress")) begin
        $fdisplay(
            piolite_observer_fd,
            "PIOLITE_P3_PROGRESS cycles=%0d live=%b idle=%b held=%b%b closing=%b%b dma_jobs=%b rcu_idle=%05x pc=%x",
            piolite_progress_cycles, u_dut.u_soc.u_piolite.s_session_live,
            u_dut.u_soc.s_piolite_lifecycle_idle, u_dut.u_soc.u_piolite.s_tx_held,
            u_dut.u_soc.u_piolite.s_rx_held, u_dut.u_soc.u_piolite.s_tx_closing,
            u_dut.u_soc.u_piolite.s_rx_closing, u_dut.u_soc.s_piolite_dma_job,
            u_dut.u_soc.s_periph_idle_ref, u_dut.u_soc.u_cpu.u_hazard3_cpu_2port.core.d_pc);
        if ($test$plusargs("tiny_piolite_trap")) begin
          $fdisplay(piolite_observer_fd, "PIOLITE_P3_TRAP cycles=%0d cause_irq=%b cause=%x epc=%x",
                    piolite_progress_cycles,
                    u_dut.u_soc.u_cpu.u_hazard3_cpu_2port.core.csr_u.mcause_irq,
                    u_dut.u_soc.u_cpu.u_hazard3_cpu_2port.core.csr_u.mcause_code,
                    u_dut.u_soc.u_cpu.u_hazard3_cpu_2port.core.csr_u.mepc);
          $fdisplay(
              piolite_observer_fd,
              "PIOLITE_P3_GUARD cycles=%0d start_ok=%b guard=%b handoff=%x filter=%x ready=%b imem=%x region=%x rx=%x select=%x status=%x",
              piolite_progress_cycles, u_dut.u_soc.u_piolite.u_reg.s_start_ok,
              u_dut.u_soc.u_piolite.u_ctrl.start_guard_ok, u_dut.u_soc.s_gpio_user_handoff,
              u_dut.u_soc.u_user_gpio_if.filter_enable_i, u_dut.u_soc.u_piolite.gpio_ready_i,
              u_dut.u_soc.u_piolite.u_ctrl.imem_valid, u_dut.u_soc.u_piolite.u_reg.s_region,
              u_dut.u_soc.u_piolite.u_ctrl.rx_level[0], u_dut.u_soc.s_gpio_user_select,
              u_dut.u_soc.s_gpio_user_select & ~u_dut.u_soc.s_gpio_user_handoff);
          $fdisplay(piolite_observer_fd, "PIOLITE_P3_CFG cycles=%0d cfg=%x",
                    piolite_progress_cycles, u_dut.u_soc.u_piolite.u_reg.s_cfg_q[0]);
          $fdisplay(
              piolite_observer_fd,
              "PIOLITE_P3_RCU_STATE cycles=%0d ctrl=%x affected=%05x gates=%05x resets=%05x reset_done=%05x busy=%b command=%x fault=%x done=%b select=%x",
              piolite_progress_cycles, u_dut.u_soc.u_peripheral_control.s_ctrl_q,
              u_dut.u_soc.u_peripheral_control.s_affected, u_dut.u_soc.u_peripheral_control.gate_o,
              u_dut.u_soc.u_peripheral_control.reset_o,
              u_dut.u_soc.u_peripheral_control.reset_done_o, u_dut.u_soc.u_sysctrl.s_rcu_busy_q,
              u_dut.u_soc.u_sysctrl.s_active_cmd_q, u_dut.u_soc.u_sysctrl.s_rcu_fault_q,
              u_dut.u_soc.s_periph_done, u_dut.u_soc.s_gpio_user_select);
          $fdisplay(
              piolite_observer_fd,
              "PIOLITE_P3_DMA_STATE cycles=%0d busy32=%b%b abort32=%b%b stop32=%b%b valid32=%b%b fire32=%b%b tcd_left32=%x%x",
              piolite_progress_cycles, u_dut.u_soc.u_dma.u_dma_core.s_busy_q[3],
              u_dut.u_soc.u_dma.u_dma_core.s_busy_q[2], u_dut.u_soc.u_dma.u_dma_core.s_abort_q[3],
              u_dut.u_soc.u_dma.u_dma_core.s_abort_q[2],
              u_dut.u_soc.u_dma.u_dma_core.s_stream_tx_stop_q[3],
              u_dut.u_soc.u_dma.u_dma_core.s_stream_tx_stop_q[2],
              u_dut.u_soc.u_dma.u_dma_core.s_stream_tx_valid[3],
              u_dut.u_soc.u_dma.u_dma_core.s_stream_tx_valid[2],
              u_dut.u_soc.u_dma.u_dma_core.s_piolite_tx_fire,
              u_dut.u_soc.u_dma.u_dma_core.s_piolite_rx_fire,
              u_dut.u_soc.u_dma.u_dma_core.s_tcd_words_left_q[3],
              u_dut.u_soc.u_dma.u_dma_core.s_tcd_words_left_q[2]);
        end
      end
      $fflush(piolite_observer_fd);
    end
  end
  if ($test$plusargs(
          "tiny_piolite_p3"
      ) && u_dut.u_soc.u_sysctrl_apb4_if.psel && u_dut.u_soc.u_sysctrl_apb4_if.penable &&
          u_dut.u_soc.u_sysctrl_apb4_if.pready && u_dut.u_soc.u_sysctrl_apb4_if.pwrite &&
          (u_dut.u_soc.u_sysctrl_apb4_if.paddr[11:8] == 4'h1)) begin
    $fdisplay(piolite_observer_fd, "PIOLITE_P3_RCU_APB cycles=%0d addr=%x wdata=%x error=%b pc=%x",
              piolite_progress_cycles, u_dut.u_soc.u_sysctrl_apb4_if.paddr,
              u_dut.u_soc.u_sysctrl_apb4_if.pwdata, u_dut.u_soc.u_sysctrl_apb4_if.pslverr,
              u_dut.u_soc.u_cpu.u_hazard3_cpu_2port.core.d_pc);
  end
  if ($test$plusargs("tiny_piolite_trace")) begin
    if ((u_dut.u_soc.u_uart0.u_uart_reg.s_ctrl_q != piolite_uart_ctrl_q) ||
        (u_dut.u_soc.s_uart0_rst_n != piolite_uart_rst_q)) begin
      $fdisplay(piolite_observer_fd,
                "PIOLITE_P3_UART_STATE cycles=%0d ctrl=%x rst=%b count=%0d tick=%b pc=%x",
                piolite_progress_cycles, u_dut.u_soc.u_uart0.u_uart_reg.s_ctrl_q,
                u_dut.u_soc.s_uart0_rst_n, u_dut.u_soc.u_uart0.u_uart_reg.s_tx_count,
                u_dut.u_soc.u_uart0.u_uart_core.s_sample_tick,
                u_dut.u_soc.u_cpu.u_hazard3_cpu_2port.core.d_pc);
    end
    piolite_uart_ctrl_q = u_dut.u_soc.u_uart0.u_uart_reg.s_ctrl_q;
    piolite_uart_rst_q  = u_dut.u_soc.s_uart0_rst_n;
    if (u_dut.u_soc.u_piolite.u_core.gen_sm[0].u_sm.s_commit) begin
      $fdisplay(
          piolite_observer_fd,
          "PIOLITE_P3_EXEC cycles=%0d need_push=%b push=%b accept=%b data=%x count=%0d result=%0d fault=%b rx=%x pins=%x pads=%x filtered=%x in_cfg=%x source=%x fifo_data=%x q=%x sync=%x negedge_cfg=%x negedge_source=%x negedge_filtered=%x",
          piolite_progress_cycles, u_dut.u_soc.u_piolite.u_core.gen_sm[0].u_sm.s_need_rx_push,
          u_dut.u_soc.u_piolite.u_core.gen_sm[0].u_sm.rx_push_o,
          u_dut.u_soc.u_piolite.u_core.gen_sm[0].u_rx_fifo.push_accept_o,
          u_dut.u_soc.u_piolite.u_core.gen_sm[0].u_sm.rx_data_o,
          u_dut.u_soc.u_piolite.u_core.gen_sm[0].u_sm.s_count,
          u_dut.u_soc.u_piolite.u_core.gen_sm[0].u_sm.s_result_count,
          u_dut.u_soc.u_piolite.u_core.gen_sm[0].u_sm.s_fault,
          u_dut.u_soc.u_piolite.u_ctrl.rx_level[0], u_dut.u_soc.u_piolite.gpio_input_i, s_gpio,
          u_dut.u_soc.u_user_gpio_if.di_i, u_dut.u_soc.u_piolite.u_core.gen_sm[0].u_sm.s_in_pins,
          u_dut.u_soc.u_piolite.u_core.gen_sm[0].u_sm.s_source_value,
          u_dut.u_soc.u_piolite.u_core.gen_sm[0].u_rx_fifo.push_data_i,
          u_dut.u_soc.u_gpio.u_gpio_core.s_input_filtered_q,
          u_dut.u_soc.u_gpio.u_gpio_core.s_input_sync, piolite_negedge_in_cfg,
          piolite_negedge_source, piolite_negedge_filtered);
    end
    if (u_dut.u_soc.u_gpio_apb4_if.psel && u_dut.u_soc.u_gpio_apb4_if.penable &&
        u_dut.u_soc.u_gpio_apb4_if.pready) begin
      $fdisplay(
          piolite_observer_fd,
          "PIOLITE_P3_GPIO_APB cycles=%0d addr=%x write=%b wdata=%x rdata=%x error=%b select=%x status=%x",
          piolite_progress_cycles, u_dut.u_soc.u_gpio_apb4_if.paddr,
          u_dut.u_soc.u_gpio_apb4_if.pwrite, u_dut.u_soc.u_gpio_apb4_if.pwdata,
          u_dut.u_soc.u_gpio_apb4_if.prdata, u_dut.u_soc.u_gpio_apb4_if.pslverr,
          u_dut.u_soc.s_gpio_user_select,
          u_dut.u_soc.s_gpio_user_select & ~u_dut.u_soc.s_gpio_user_handoff);
    end
    if (u_dut.u_soc.u_piolite_apb4_if.psel && u_dut.u_soc.u_piolite_apb4_if.penable &&
        u_dut.u_soc.u_piolite_apb4_if.pready) begin
      $fdisplay(piolite_observer_fd,
                "PIOLITE_P3_APB cycles=%0d addr=%x write=%b wdata=%x rdata=%x error=%b",
                piolite_progress_cycles, u_dut.u_soc.u_piolite_apb4_if.paddr,
                u_dut.u_soc.u_piolite_apb4_if.pwrite, u_dut.u_soc.u_piolite_apb4_if.pwdata,
                u_dut.u_soc.u_piolite_apb4_if.prdata, u_dut.u_soc.u_piolite_apb4_if.pslverr);
    end
    if (u_dut.u_soc.u_uart0_apb4_if.psel && u_dut.u_soc.u_uart0_apb4_if.penable &&
        u_dut.u_soc.u_uart0_apb4_if.pready) begin
      $fdisplay(piolite_observer_fd,
                "PIOLITE_P3_UART_APB cycles=%0d addr=%x write=%b wdata=%x rdata=%x error=%b pc=%x",
                piolite_progress_cycles, u_dut.u_soc.u_uart0_apb4_if.paddr,
                u_dut.u_soc.u_uart0_apb4_if.pwrite, u_dut.u_soc.u_uart0_apb4_if.pwdata,
                u_dut.u_soc.u_uart0_apb4_if.prdata, u_dut.u_soc.u_uart0_apb4_if.pslverr,
                u_dut.u_soc.u_cpu.u_hazard3_cpu_2port.core.d_pc);
    end
  end
end
