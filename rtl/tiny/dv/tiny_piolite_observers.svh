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
end
