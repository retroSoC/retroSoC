integer piolite_debug_cycle = 0;
always @(posedge s_clk) begin
  piolite_debug_cycle = piolite_debug_cycle + 1;
  if ($test$plusargs("piolite_p3_debug") && ((piolite_debug_cycle % 10000) == 0)) begin
    $display(
        "PIO_DEBUG cycle=%0d sm0=%0d/%0d sm1=%0d/%0d txlvl=%x rxlvl=%x rxv=%b/%b rxd=%08x pin=%08x dma2=%b/%0d/%0d/%08x",
        piolite_debug_cycle, u_dut.u_soc.u_piolite.u_ctrl.runtime[0].state,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[0].stall,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[1].state,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[1].stall, u_dut.u_soc.u_piolite.u_ctrl.tx_level[0],
        u_dut.u_soc.u_piolite.u_ctrl.rx_level[1], u_dut.u_soc.u_piolite_rx_axis_if.tvalid,
        u_dut.u_soc.u_piolite_rx_axis_if.tready, u_dut.u_soc.u_piolite_rx_axis_if.tdata,
        u_dut.u_soc.u_user_gpio_if.di_i, u_dut.u_soc.u_dma.u_dma_core.s_busy_q[2],
        u_dut.u_soc.u_dma.u_dma_core.s_err_code_q[2],
        u_dut.u_soc.u_dma.u_dma_core.s_stream_accepted_q[2],
        u_dut.u_soc.u_dma.u_dma_core.s_bytes_done_q[2]);
    $display("PIO_RX_STATE owned=%b admit=%b req=%0d kind=%0d len=%0d full=%b abort=%b err=%b",
             u_dut.u_soc.u_dma.u_dma_core.s_piolite_rx_owned_q[2],
             u_dut.u_soc.s_piolite_rx_admit[2], u_dut.u_soc.u_dma.u_dma_core.s_req_q[2],
             u_dut.u_soc.u_dma.u_dma_core.s_kind_q[2], u_dut.u_soc.u_dma.u_dma_core.s_len_q[2],
             u_dut.u_soc.u_dma.u_dma_core.s_fifo_full[2],
             u_dut.u_soc.u_dma.u_dma_core.s_abort_q[2], u_dut.u_soc.u_dma.u_dma_core.s_err_q[2]);
    $display(
        "PIO_BACKGROUND busy=%b err=%0d accepted=%0d bytes=%0d abort=%b",
        u_dut.u_soc.u_dma.u_dma_core.s_busy_q[1], u_dut.u_soc.u_dma.u_dma_core.s_err_code_q[1],
        u_dut.u_soc.u_dma.u_dma_core.s_stream_accepted_q[1],
        u_dut.u_soc.u_dma.u_dma_core.s_bytes_done_q[1], u_dut.u_soc.u_dma.u_dma_core.s_abort_q[1]);
    $display(
        "PIO_RX_GUARD guard=%b handoff=%08x filter=%08x closing=%b ready=%b status=%08x claim=%08x",
        u_dut.u_soc.u_piolite.u_ctrl.start_guard_ok[1], u_dut.u_soc.s_gpio_user_handoff,
        u_dut.u_soc.s_gpio_filter_enable, u_dut.u_soc.u_piolite.u_dma_adapter.rx_closing_o,
        u_dut.u_soc.u_piolite.gpio_ready_i, u_dut.u_soc.s_piolite_gpio_user_status,
        u_dut.u_soc.u_piolite.u_ctrl.cfg[1].claim_mask);
    $display(
        "PIO_CLEAN bind=%08x/%08x events=%02x/%02x imem=%08x txbusy=%b rxheld=%b rxjob=%b rxclosing=%b block=%b/%b",
        u_dut.u_soc.u_piolite.u_ctrl.tx_bind, u_dut.u_soc.u_piolite.u_ctrl.rx_bind,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[0].events,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[1].events, u_dut.u_soc.u_piolite.u_ctrl.imem_valid,
        u_dut.u_soc.u_dma.u_dma_core.s_busy_q[3], u_dut.u_soc.u_piolite.u_dma_adapter.rx_held_o,
        u_dut.u_soc.u_piolite.dma_rx_job_i, u_dut.u_soc.u_piolite.u_dma_adapter.rx_closing_o,
        u_dut.u_soc.u_piolite.u_reg.s_block_reset_ok, u_dut.u_soc.u_piolite.u_ctrl.cmd_block_reset);
  end
  if ($test$plusargs(
          "piolite_p3_debug"
      ) && u_dut.u_soc.u_piolite.u_reg.s_req_accept && u_dut.u_soc.u_piolite_apb4_if.pwrite &&
          (u_dut.u_soc.u_piolite.u_reg.s_offset inside {12'h02c, 12'h030, 12'h050, 12'h054,
                                                        12'h058})) begin
    $display(
        "PIO_CMD offset=%03x data=%08x err=%b bindok=%b state=%0d rxjob=%b held=%b closing=%b blockguard=%b",
        u_dut.u_soc.u_piolite.u_reg.s_offset, u_dut.u_soc.u_piolite_apb4_if.pwdata,
        u_dut.u_soc.u_piolite.u_reg.s_access_err, u_dut.u_soc.u_piolite.u_reg.s_bind_ok,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[1].state, u_dut.u_soc.u_piolite.dma_rx_job_i,
        u_dut.u_soc.u_piolite.u_dma_adapter.rx_held_o,
        u_dut.u_soc.u_piolite.u_dma_adapter.rx_closing_o,
        u_dut.u_soc.u_piolite.u_reg.s_block_reset_ok);
  end
  if ($test$plusargs(
          "piolite_p4_diagnose"
      ) && u_dut.u_soc.u_piolite.u_reg.s_req_accept && !u_dut.u_soc.u_piolite_apb4_if.pwrite &&
          (u_dut.u_soc.u_piolite.u_reg.s_offset inside {12'h200, 12'h280})) begin
    $display(
        "PIO_WAIT sm=%0d state=%0d stall=%0d pc=%0d fault=%02x fpc=%0d events=%02x tx=%0d rx=%0d isr=%0d osr=%0d retired=%0d dma=%b/%0d/%b",
        u_dut.u_soc.u_piolite.u_reg.s_sm_index,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[u_dut.u_soc.u_piolite.u_reg.s_sm_index].state,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[u_dut.u_soc.u_piolite.u_reg.s_sm_index].stall,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[u_dut.u_soc.u_piolite.u_reg.s_sm_index].pc,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[u_dut.u_soc.u_piolite.u_reg.s_sm_index].fault_code,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[u_dut.u_soc.u_piolite.u_reg.s_sm_index].fault_pc,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[u_dut.u_soc.u_piolite.u_reg.s_sm_index].events,
        u_dut.u_soc.u_piolite.u_ctrl.tx_level[u_dut.u_soc.u_piolite.u_reg.s_sm_index],
        u_dut.u_soc.u_piolite.u_ctrl.rx_level[u_dut.u_soc.u_piolite.u_reg.s_sm_index],
        u_dut.u_soc.u_piolite.u_ctrl.runtime[u_dut.u_soc.u_piolite.u_reg.s_sm_index].isr_count,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[u_dut.u_soc.u_piolite.u_reg.s_sm_index].osr_count,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[u_dut.u_soc.u_piolite.u_reg.s_sm_index].retired_count,
        u_dut.u_soc.u_dma.u_dma_core.s_busy_q[3], u_dut.u_soc.u_dma.u_dma_core.s_bytes_done_q[3],
        u_dut.u_soc.u_dma.u_dma_core.s_err_q[3]);
  end
end


logic s_p4_fault_reported_q = 1'b0;
always @(negedge s_clk) begin
  if ($test$plusargs(
          "piolite_p4_diagnose"
      ) && (u_dut.u_soc.u_piolite.u_ctrl.runtime[0].fault_code != 0) &&
          !s_p4_fault_reported_q) begin
    $display(
        "PIO_FAULT instruction=%04x opcode=%0d operand=%02x pc=%0d code=%02x set_width=%0d out_width=%0d claim=%08x output=%08x",
        u_dut.u_soc.u_piolite.u_core.gen_sm[0].u_sm.s_instruction,
        u_dut.u_soc.u_piolite.u_core.gen_sm[0].u_sm.s_instruction.opcode,
        u_dut.u_soc.u_piolite.u_core.gen_sm[0].u_sm.s_instruction.operand,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[0].fault_pc,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[0].fault_code,
        u_dut.u_soc.u_piolite.u_ctrl.cfg[0].set_pins.width,
        u_dut.u_soc.u_piolite.u_ctrl.cfg[0].out_pins.width,
        u_dut.u_soc.u_piolite.u_ctrl.cfg[0].claim_mask,
        u_dut.u_soc.u_piolite.u_ctrl.cfg[0].output_mask);
    $display("PIO_FAULT_CONFIG base=%0d entry=%0d imem0=%04x imem1=%04x imem2=%04x imem14=%04x",
             u_dut.u_soc.u_piolite.u_ctrl.cfg[0].base, u_dut.u_soc.u_piolite.u_ctrl.cfg[0].entry,
             u_dut.u_soc.u_piolite.u_core.u_imem.s_payload_q[0],
             u_dut.u_soc.u_piolite.u_core.u_imem.s_payload_q[1],
             u_dut.u_soc.u_piolite.u_core.u_imem.s_payload_q[2],
             u_dut.u_soc.u_piolite.u_core.u_imem.s_payload_q[14]);
    s_p4_fault_reported_q = 1'b1;
  end
end


always @(negedge s_clk) begin
  if ($test$plusargs(
          "piolite_p4_diagnose"
      ) && u_dut.u_soc.u_piolite.u_reg.s_req_accept && !u_dut.u_soc.u_piolite_apb4_if.pwrite &&
          (u_dut.u_soc.u_piolite.u_reg.s_offset inside {12'h244, 12'h2c4})) begin
    $display(
        "PIO_CAPTURE_READ sm=%0d data=%08x isr=%08x x=%0d pc=%0d retired=%0d",
        u_dut.u_soc.u_piolite.u_reg.s_sm_index,
        u_dut.u_soc.u_piolite.u_ctrl.cpu_rx_data[u_dut.u_soc.u_piolite.u_reg.s_sm_index],
        u_dut.u_soc.u_piolite.u_ctrl.runtime[u_dut.u_soc.u_piolite.u_reg.s_sm_index].isr,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[u_dut.u_soc.u_piolite.u_reg.s_sm_index].x,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[u_dut.u_soc.u_piolite.u_reg.s_sm_index].pc,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[u_dut.u_soc.u_piolite.u_reg.s_sm_index].retired_count);
  end
end

logic [31:0] s_p4_pulse_capture_retired_q = 0;
always @(negedge s_clk) begin
  if ($test$plusargs(
          "piolite_p4_scenario_PULSE"
      ) && $test$plusargs(
          "piolite_p4_diagnose"
      ) && (u_dut.u_soc.u_piolite.u_ctrl.runtime[1].retired_count != s_p4_pulse_capture_retired_q)
          && (u_dut.u_soc.u_piolite.u_ctrl.runtime[1].retired_count < 24)) begin
    $display(
        "P4_PULSE_CAPTURE pc=%0d state=%0d retired=%0d x=%0d pin=%b gpio2=%b gpio3=%b test=%0d",
        u_dut.u_soc.u_piolite.u_ctrl.runtime[1].pc, u_dut.u_soc.u_piolite.u_ctrl.runtime[1].state,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[1].retired_count,
        u_dut.u_soc.u_piolite.u_ctrl.runtime[1].x, u_dut.u_soc.u_piolite.u_core.pin_inputs_i[3],
        s_gpio_2, s_gpio_3, u_dut.u_soc.u_piolite.u_ctrl.cfg[1].test_pin);
  end
  s_p4_pulse_capture_retired_q = u_dut.u_soc.u_piolite.u_ctrl.runtime[1].retired_count;
end
