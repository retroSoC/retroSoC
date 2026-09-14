// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apb4_ga2d (
    // verilog_format: off -- preserve the shell lifecycle boundary columns
    input  logic         clk_i,
    input  logic         rst_n_i,
    input  logic         resource_quiesce_i,
    input  logic         resource_reset_i,
    input  logic         source_stop_i,
    input  logic         source_safe_idle_i,
    input  logic         block_ack_i,
    input  logic         bridge_clear_busy_i,
    input  logic [7:0]   bridge_epoch_i,
    input  logic         data_ready_i,
    input  logic [1:0]   mem_pad_mode_i,
    apb4_if.slave        apb4,
    axi4_if.master       ga2d_axi4,
    output logic         idle_o,
    output logic         core_safe_idle_o,
    output logic         irq_o
    // verilog_format: on
);
  ga2d_pkg::ga2d_config_t s_config;
  logic [7:0] s_epoch_seen_d, s_epoch_seen_q;
  logic        s_epoch_changed;
  logic        s_quiesced;
  logic        s_data_ready;
  logic        s_recovery_required;
  logic        s_soft_reset;
  logic        s_abort;
  logic        s_start;
  logic        unused_snapshot;
  logic        s_reg_idle;
  logic        s_core_busy;
  logic        s_core_draining;
  logic        s_core_done;
  logic        s_core_aborted;
  logic        s_core_err;
  logic        s_core_recovery_required;
  logic        s_core_safe_idle;
  logic [ 2:0] s_core_irq_event;
  logic        s_core_err_valid;
  logic [ 6:0] s_core_err_code;
  logic [ 3:0] s_core_err_stage;
  logic [ 1:0] s_core_err_axi_response;
  logic [31:0] s_core_err_address;
  logic [63:0] s_core_cycles;
  logic [63:0] s_core_read_bytes;
  logic [63:0] s_core_write_bytes;
  logic [63:0] s_core_read_stalls;
  logic [63:0] s_core_write_stalls;
  logic [63:0] s_core_pipe_stalls;
  logic [15:0] s_core_lines_done;

  assign s_epoch_seen_d = bridge_epoch_i;
  assign s_epoch_changed = bridge_epoch_i != s_epoch_seen_q;
  assign s_quiesced = (resource_quiesce_i || resource_reset_i) && source_stop_i &&
                      source_safe_idle_i && block_ack_i;
  assign s_data_ready = data_ready_i && !resource_quiesce_i && !resource_reset_i;
  assign s_recovery_required = s_core_recovery_required || bridge_clear_busy_i ||
                               !data_ready_i || s_epoch_changed;
  assign idle_o = s_reg_idle && source_safe_idle_i;
  assign core_safe_idle_o = s_core_safe_idle;

  dffr #(
      .DATA_WIDTH(8)
  ) u_epoch_seen (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_epoch_seen_d),
      .dat_o  (s_epoch_seen_q)
  );

  ga2d_reg u_ga2d_reg (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .busy_i              (s_core_busy),
      .draining_i          (s_core_draining),
      .quiesced_i          (s_quiesced),
      .data_ready_i        (s_data_ready),
      .recovery_required_i (s_recovery_required),
      .idle_i              (s_core_safe_idle && source_safe_idle_i),
      .done_i              (s_core_done),
      .aborted_i           (s_core_aborted),
      .error_i             (s_core_err),
      .irq_event_i         (s_core_irq_event),
      .error_valid_i       (s_core_err_valid),
      .error_code_i        (s_core_err_code),
      .error_stage_i       (s_core_err_stage),
      .error_axi_response_i(s_core_err_axi_response),
      .error_address_i     (s_core_err_address),
      .cycles_i            (s_core_cycles),
      .read_bytes_i        (s_core_read_bytes),
      .write_bytes_i       (s_core_write_bytes),
      .read_stalls_i       (s_core_read_stalls),
      .write_stalls_i      (s_core_write_stalls),
      .pipe_stalls_i       (s_core_pipe_stalls),
      .lines_done_i        (s_core_lines_done),
      .apb4                (apb4),
      .config_o            (s_config),
      .start_o             (s_start),
      .soft_reset_o        (s_soft_reset),
      .abort_o             (s_abort),
      .snapshot_o          (unused_snapshot),
      .idle_o              (s_reg_idle),
      .irq_o               (irq_o)
  );

  ga2d_core u_ga2d_core (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .start_i             (s_start),
      .abort_i             (s_abort),
      .soft_reset_i        (s_soft_reset),
      .resource_stop_i     (resource_quiesce_i || resource_reset_i || source_stop_i),
      .bridge_clear_busy_i (bridge_clear_busy_i),
      .bridge_epoch_i      (bridge_epoch_i),
      .data_ready_i        (s_data_ready),
      .mem_pad_mode_i      (mem_pad_mode_i),
      .config_i            (s_config),
      .busy_o              (s_core_busy),
      .draining_o          (s_core_draining),
      .done_o              (s_core_done),
      .aborted_o           (s_core_aborted),
      .error_o             (s_core_err),
      .recovery_required_o (s_core_recovery_required),
      .safe_idle_o         (s_core_safe_idle),
      .irq_event_o         (s_core_irq_event),
      .error_valid_o       (s_core_err_valid),
      .error_code_o        (s_core_err_code),
      .error_stage_o       (s_core_err_stage),
      .error_axi_response_o(s_core_err_axi_response),
      .error_address_o     (s_core_err_address),
      .cycles_o            (s_core_cycles),
      .read_bytes_o        (s_core_read_bytes),
      .write_bytes_o       (s_core_write_bytes),
      .read_stalls_o       (s_core_read_stalls),
      .write_stalls_o      (s_core_write_stalls),
      .pipe_stalls_o       (s_core_pipe_stalls),
      .lines_done_o        (s_core_lines_done),
      .axi4                (ga2d_axi4)
  );
endmodule
