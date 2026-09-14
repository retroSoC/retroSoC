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
    apb4_if.slave        apb4,
    output logic         idle_o,
    output logic         irq_o
    // verilog_format: on
);
  ga2d_pkg::ga2d_config_t s_config;
  logic [7:0] s_epoch_seen_d, s_epoch_seen_q;
  logic s_epoch_changed;
  logic s_quiesced;
  logic s_data_ready;
  logic s_recovery_required;
  logic s_soft_reset;
  logic s_abort;
  logic s_reg_idle;
  logic s_unused;

  assign s_epoch_seen_d = bridge_epoch_i;
  assign s_epoch_changed = bridge_epoch_i != s_epoch_seen_q;
  assign s_quiesced = (resource_quiesce_i || resource_reset_i) && source_stop_i &&
                      source_safe_idle_i && block_ack_i;
  assign s_data_ready = data_ready_i && !resource_quiesce_i && !resource_reset_i;
  assign s_recovery_required = bridge_clear_busy_i || !data_ready_i || s_epoch_changed;
  assign idle_o = s_reg_idle && source_safe_idle_i;
  assign s_unused = ^s_config ^ s_soft_reset ^ s_abort;

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
      .busy_i              (1'b0),
      .draining_i          (1'b0),
      .quiesced_i          (s_quiesced),
      .data_ready_i        (s_data_ready),
      .recovery_required_i (s_recovery_required),
      .idle_i              (source_safe_idle_i),
      .done_i              (1'b0),
      .aborted_i           (1'b0),
      .irq_event_i         (3'd0),
      .error_valid_i       (1'b0),
      .error_code_i        (7'd0),
      .error_stage_i       (4'd0),
      .error_axi_response_i(2'd0),
      .error_address_i     (32'd0),
      .apb4                (apb4),
      .config_o            (s_config),
      .soft_reset_o        (s_soft_reset),
      .abort_o             (s_abort),
      .idle_o              (s_reg_idle),
      .irq_o               (irq_o)
  );
endmodule
