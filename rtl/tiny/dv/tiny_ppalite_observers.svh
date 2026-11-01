bit              ppalite_diag_route_seen = 0;
bit              ppalite_diag_fault_seen = 0;
longint unsigned ppalite_diag_cycles = 0;

always @(posedge s_clk) begin
  if ($test$plusargs("tiny_ppalite_diag")) begin
    ppalite_diag_cycles++;
    if ((ppalite_diag_cycles % 100000) == 0) begin
      $display(
          "PPALITE_DIAG_PROGRESS ref=%0d status=%h input=%0d/%0d/%0d output=%0d/%0d src_done=%b dma=%b/%b/%h/%h dvp_active=%b",
          ppalite_diag_cycles, u_dut.u_soc.u_ppalite.u_reg.s_status,
          u_dut.u_soc.u_ppalite.u_ctrl.input_words, u_dut.u_soc.u_ppalite.u_ctrl.input_pixels,
          u_dut.u_soc.u_ppalite.u_ctrl.input_lines, u_dut.u_soc.u_ppalite.u_ctrl.output_words,
          u_dut.u_soc.u_ppalite.u_ctrl.output_lines, u_dut.u_soc.s_ppa_source_done,
          u_dut.u_soc.s_dvp_dma_busy, u_dut.u_soc.s_dvp_dma_done, u_dut.u_soc.s_dvp_dma_bytes_done,
          u_dut.u_soc.s_dvp_dma_err_stat, u_dut.u_soc.s_dvp_source_active);
    end
    if (u_dut.u_soc.s_clock_apply) begin
      $display(
          "PPALITE_DIAG_RCU_APPLY profile=%0d idle_ref=%h idle17=%b route=%b route_idle=%b source_quiet=%b dma_idle=%b transport_idle=%b processor_idle=%b",
          u_dut.u_soc.s_clock_profile, u_dut.u_soc.s_periph_idle_ref,
          u_dut.u_soc.s_periph_idle_ref[17], u_dut.u_soc.s_ppa_route, u_dut.u_soc.s_ppa_route_idle,
          u_dut.u_soc.s_ppa_source_quiet, u_dut.u_soc.s_ppa_dma_idle,
          u_dut.u_soc.s_ppa_transport_idle, u_dut.u_soc.s_ppa_processor_idle);
      $display(
          "PPALITE_DIAG_RCU_SOURCE status_valid=%b enabled=%b active=%b capture_idle=%b fifo_empty=%b lifecycle_idle=%b stats_valid=%b",
          u_dut.u_soc.s_dvp_source_stat_valid, u_dut.u_soc.s_dvp_source_enabled,
          u_dut.u_soc.s_dvp_source_active, u_dut.u_soc.s_dvp_source_capture_idle,
          u_dut.u_soc.s_dvp_source_fifo_empty, u_dut.u_soc.s_dvp_idle,
          u_dut.u_soc.s_dvp_source_frame_stats_valid);
    end
    if (u_dut.u_soc.s_clock_done) begin
      $display("PPALITE_DIAG_RCU_DONE profile=%0d fault=%h idle_ref=%h",
               u_dut.u_soc.s_backend_current, u_dut.u_soc.s_clock_fault,
               u_dut.u_soc.s_periph_idle_ref);
    end
    if (u_dut.u_soc.s_ppa_route_write && !ppalite_diag_route_seen) begin
      ppalite_diag_route_seen = 1;
      $display(
          "PPALITE_DIAG_ROUTE value=%b change=%b route=%b source_quiet=%b dma_idle=%b transport_idle=%b processor_idle=%b dma_start=%b source_update=%b dvp_valid=%b processed_valid=%b",
          u_dut.u_soc.s_ppa_route_value, u_dut.u_soc.s_ppa_route_change, u_dut.u_soc.s_ppa_route,
          u_dut.u_soc.s_ppa_source_quiet,
          u_dut.u_soc.s_dma_admission_idle && u_dut.u_soc.s_dma_idle_pclk,
          u_dut.u_soc.s_ppa_transport_idle, u_dut.u_soc.s_ppa_processor_idle,
          u_dut.u_soc.s_ppa_dma_start, u_dut.u_soc.u_ppalite_route.s_source_update,
          u_dut.u_soc.u_dvp_rx_axis_if.tvalid, u_dut.u_soc.s_ppa_processed_valid);
      $display(
          "PPALITE_DIAG_SOURCE status_valid=%b lifecycle_idle=%b cfg_pending=%b cmd_pending=%b flush_pending=%b enabled=%b active=%b capture_idle=%b fifo_empty=%b stats_valid=%b",
          u_dut.u_soc.s_dvp_source_stat_valid, u_dut.u_soc.s_dvp_idle,
          u_dut.u_soc.s_dvp_source_cfg_pending, u_dut.u_soc.s_dvp_source_cmd_pending,
          u_dut.u_soc.s_dvp_source_flush_pending, u_dut.u_soc.s_dvp_source_enabled,
          u_dut.u_soc.s_dvp_source_active, u_dut.u_soc.s_dvp_source_capture_idle,
          u_dut.u_soc.s_dvp_source_fifo_empty, u_dut.u_soc.s_dvp_source_frame_stats_valid);
    end
    if (u_dut.u_soc.u_dvp_apb4_if.psel && u_dut.u_soc.u_dvp_apb4_if.penable &&
        u_dut.u_soc.u_dvp_apb4_if.pready && u_dut.u_soc.u_dvp_apb4_if.pwrite &&
        (u_dut.u_soc.u_dvp_apb4_if.paddr[11:0] == 12'd0)) begin
      $display("PPALITE_DIAG_DVP_CTRL time=%0t data=%h error=%b state=%0d token=%b exact=%b",
               $time, u_dut.u_soc.u_dvp_apb4_if.pwdata, u_dut.u_soc.u_dvp_apb4_if.pslverr,
               u_dut.u_soc.s_ppa_capture_state, u_dut.u_soc.s_ppa_transport_admitted,
               u_dut.u_soc.u_ppalite_dma_guard.s_exact_shadow);
    end
    if ((u_dut.u_soc.s_fault_count != 0) && !ppalite_diag_fault_seen) begin
      ppalite_diag_fault_seen = 1;
      $display("PPALITE_DIAG_FAULT address=%h count=%h route=%b pslverr=%b",
               u_dut.u_soc.s_fault_addr, u_dut.u_soc.s_fault_count, u_dut.u_soc.s_ppa_route,
               u_dut.u_soc.u_ppalite_apb4_if.pslverr);
      $display("PPALITE_DIAG_DMA token=%b exact=%b cfg=%h dst=%h len=%h req=%h burst=%h state=%0d",
               u_dut.u_soc.s_ppa_transport_admitted, u_dut.u_soc.u_ppalite_dma_guard.s_exact_shadow,
               u_dut.u_soc.u_ppalite_dma_guard.s_cfg_shadow_q,
               u_dut.u_soc.u_ppalite_dma_guard.s_dst_shadow_q,
               u_dut.u_soc.u_ppalite_dma_guard.s_len_shadow_q,
               u_dut.u_soc.u_ppalite_dma_guard.s_req_shadow_q[95:64],
               u_dut.u_soc.u_ppalite_dma_guard.s_burst_shadow_q, u_dut.u_soc.s_ppa_capture_state);
    end
  end
end
