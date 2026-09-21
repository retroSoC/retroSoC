// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// NPU top shell: the PCLK register file (npu_reg), the shell/HP control CDC
// with epoch reconciliation (npu_control_cdc), the HP job controller
// (npu_core), and the production AXI4 DMA engine (npu_dma) driving the private
// master directly (HP-native, no payload CDC or width conversion). At Phase 3
// the APB shell still rejects START (EXECUTION_READY stays 0), so the master
// issues nothing from software; the engine runs only through the production
// launch interface exercised by directed testbenches.
`include "npu_define.svh"

module apb4_npu (
    // verilog_format: off -- preserve the shell lifecycle boundary columns
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        clk_hp_i,
    input  logic        rst_hp_n_i,
    input  logic [1:0]  resource_owner_i,
    input  logic        resource_owner_lock_i,
    input  logic        resource_quiesce_i,
    input  logic        resource_reset_i,
    apb4_if.slave       apb4,
    output logic        idle_o,
    output logic        block_ack_o,
    output logic        irq_o,
    input  logic        hp_block_new_i,
    output logic        hp_pause_ack_o,
    input  logic        hp_flush_i,
    output logic        hp_flush_busy_o,
    output logic        hp_idle_o,
    axi4_if.master      npu_axi4
    // verilog_format: on
);
  localparam int unsigned LaunchPayloadWidth = `APB4_NPU__LAUNCH_PAYLOAD_WIDTH;
  localparam int unsigned ResultPayloadWidth = `APB4_NPU__RESULT_PAYLOAD_WIDTH;
  localparam int unsigned SnapshotPayloadWidth = `APB4_NPU__SNAPSHOT_PAYLOAD_WIDTH;
  localparam int unsigned EpochWidth = `APB4_NPU__EPOCH_WIDTH;

  logic                            s_reg_idle;
  logic                            s_abort;
  logic                            s_soft_reset;
  logic                            s_launch_req_valid;
  logic                            s_launch_req_ready;
  logic [  LaunchPayloadWidth-1:0] s_launch_req_payload;
  logic                            s_result_valid;
  logic                            s_result_ready;
  logic [  ResultPayloadWidth-1:0] s_result_payload;
  logic                            s_snap_req_valid;
  logic                            s_snap_req_ready;
  logic                            s_snap_resp_valid;
  logic                            s_snap_resp_ready;
  logic [SnapshotPayloadWidth-1:0] s_snap_resp_payload;
  logic                            s_link_up;
  logic                            s_flush_active;
  logic [                    31:0] s_recovery_generation;
  logic                            s_hp_launch_valid;
  logic                            s_hp_launch_ready;
  logic [  LaunchPayloadWidth-1:0] s_hp_launch_payload;
  logic                            s_hp_result_valid;
  logic                            s_hp_result_ready;
  logic [  ResultPayloadWidth-1:0] s_hp_result_payload;
  logic                            s_hp_snap_req_valid;
  logic                            s_hp_snap_req_ready;
  logic                            s_hp_snap_resp_valid;
  logic                            s_hp_snap_resp_ready;
  logic [SnapshotPayloadWidth-1:0] s_hp_snap_resp_payload;
  logic [          EpochWidth-1:0] s_hp_epoch_req;
  logic [          EpochWidth-1:0] s_hp_epoch_ack;
  logic                            s_hp_quiesce_req;
  logic                            s_hp_quiesce_ack;
  logic                            s_hp_busy;
  logic                            s_hp_draining;
  logic                            s_hp_pause_active;
  logic                            s_hp_busy_pclk;
  logic                            s_hp_draining_pclk;
  logic                            s_clock_paused;
  // software ABORT (PCLK pulse) crosses into the HP domain as a toggle
  logic                            s_abort_toggle_d;
  logic                            s_abort_toggle_q;
  logic                            s_abort_toggle_hp;
  logic                            s_abort_hp_d;
  logic                            s_abort_hp_q;
  logic                            s_abort_hp_pulse;
  // discrete npu_dma engine interface of the job controller
  logic                            s_dma_clear;
  logic                            s_dma_read_req_valid;
  logic                            s_dma_read_req_ready;
  logic [                    31:0] s_dma_read_addr;
  logic [                    31:0] s_dma_read_bytes;
  logic                            s_dma_read_data_valid;
  logic                            s_dma_read_data_ready;
  logic [                    63:0] s_dma_read_data;
  logic [                     7:0] s_dma_read_keep;
  logic                            s_dma_read_last;
  logic                            s_dma_write_req_valid;
  logic                            s_dma_write_req_ready;
  logic [                    31:0] s_dma_write_addr;
  logic [                    31:0] s_dma_write_bytes;
  logic                            s_dma_write_data_valid;
  logic                            s_dma_write_data_ready;
  logic [                    63:0] s_dma_write_data;
  logic [                     7:0] s_dma_write_keep;
  logic                            s_dma_write_last;
  logic                            s_dma_write_done;
  logic                            s_dma_busy;
  logic                            s_dma_read_busy;
  logic                            s_dma_write_busy;
  logic                            s_dma_pause_ack;
  logic                            s_dma_fault;
  logic [                     3:0] s_dma_fault_code;
  logic [                    31:0] s_dma_fault_addr;
  logic [                     1:0] s_dma_fault_resp;
  logic [                    63:0] s_dma_read_bytes_cnt;
  logic [                    63:0] s_dma_write_bytes_cnt;
  logic [                    63:0] s_dma_stall_cycles;
  logic                            s_dma_read_cmd_err;
  logic                            s_dma_write_cmd_err;

  // PCLK shell idle for the resource controller: no launch slot or snapshot
  // handshake pending, the link reconciled, and the HP side quiet.
  assign idle_o = s_reg_idle && s_link_up && !s_hp_busy_pclk && !s_hp_draining_pclk;

  npu_reg u_npu_reg (
      .clk_i                  (clk_i),
      .rst_n_i                (rst_n_i),
      .apb4                   (apb4),
      .resource_owner_i       (resource_owner_i),
      .resource_owner_lock_i  (resource_owner_lock_i),
      .resource_quiesce_i     (resource_quiesce_i),
      .resource_reset_i       (resource_reset_i),
      .hp_busy_i              (s_hp_busy_pclk),
      .hp_draining_i          (s_hp_draining_pclk),
      .clock_paused_i         (s_clock_paused),
      .link_up_i              (s_link_up),
      .flush_active_i         (s_flush_active),
      .recovery_generation_i  (s_recovery_generation),
      .launch_req_valid_o     (s_launch_req_valid),
      .launch_req_ready_i     (s_launch_req_ready),
      .launch_req_payload_o   (s_launch_req_payload),
      .result_valid_i         (s_result_valid),
      .result_ready_o         (s_result_ready),
      .result_payload_i       (s_result_payload),
      .snapshot_req_valid_o   (s_snap_req_valid),
      .snapshot_req_ready_i   (s_snap_req_ready),
      .snapshot_resp_valid_i  (s_snap_resp_valid),
      .snapshot_resp_ready_o  (s_snap_resp_ready),
      .snapshot_resp_payload_i(s_snap_resp_payload),
      .abort_o                (s_abort),
      .soft_reset_o           (s_soft_reset),
      .idle_o                 (s_reg_idle),
      .irq_o                  (irq_o)
  );

  npu_control_cdc u_npu_control_cdc (
      .clk_i                     (clk_i),
      .rst_n_i                   (rst_n_i),
      .clk_hp_i                  (clk_hp_i),
      .rst_hp_n_i                (rst_hp_n_i),
      .launch_req_valid_i        (s_launch_req_valid),
      .launch_req_ready_o        (s_launch_req_ready),
      .launch_req_payload_i      (s_launch_req_payload),
      .result_valid_o            (s_result_valid),
      .result_ready_i            (s_result_ready),
      .result_payload_o          (s_result_payload),
      .snapshot_req_valid_i      (s_snap_req_valid),
      .snapshot_req_ready_o      (s_snap_req_ready),
      .snapshot_resp_valid_o     (s_snap_resp_valid),
      .snapshot_resp_ready_i     (s_snap_resp_ready),
      .snapshot_resp_payload_o   (s_snap_resp_payload),
      .soft_reset_i              (s_soft_reset),
      .shell_idle_i              (s_reg_idle),
      .resource_quiesce_i        (resource_quiesce_i),
      .resource_reset_i          (resource_reset_i),
      .link_up_o                 (s_link_up),
      .flush_active_o            (s_flush_active),
      .recovery_generation_o     (s_recovery_generation),
      .block_ack_o               (block_ack_o),
      .hp_launch_valid_o         (s_hp_launch_valid),
      .hp_launch_ready_i         (s_hp_launch_ready),
      .hp_launch_payload_o       (s_hp_launch_payload),
      .hp_result_valid_i         (s_hp_result_valid),
      .hp_result_ready_o         (s_hp_result_ready),
      .hp_result_payload_i       (s_hp_result_payload),
      .hp_snapshot_req_valid_o   (s_hp_snap_req_valid),
      .hp_snapshot_req_ready_i   (s_hp_snap_req_ready),
      .hp_snapshot_resp_valid_i  (s_hp_snap_resp_valid),
      .hp_snapshot_resp_ready_o  (s_hp_snap_resp_ready),
      .hp_snapshot_resp_payload_i(s_hp_snap_resp_payload),
      .hp_epoch_req_o            (s_hp_epoch_req),
      .hp_epoch_ack_i            (s_hp_epoch_ack),
      .hp_quiesce_req_o          (s_hp_quiesce_req),
      .hp_quiesce_ack_i          (s_hp_quiesce_ack),
      .hp_busy_i                 (s_hp_busy),
      .hp_draining_i             (s_hp_draining),
      .hp_pause_active_i         (s_hp_pause_active),
      .hp_flush_i                (hp_flush_i),
      .hp_busy_o                 (s_hp_busy_pclk),
      .hp_draining_o             (s_hp_draining_pclk),
      .clock_paused_o            (s_clock_paused)
  );

  npu_core #(
      .ExecutionReady(1'b1)
  ) u_npu_core (
      .clk_hp_i              (clk_hp_i),
      .rst_hp_n_i            (rst_hp_n_i),
      .launch_valid_i        (s_hp_launch_valid),
      .launch_ready_o        (s_hp_launch_ready),
      .launch_data_i         (s_hp_launch_payload),
      .result_valid_o        (s_hp_result_valid),
      .result_ready_i        (s_hp_result_ready),
      .result_data_o         (s_hp_result_payload),
      .snapshot_req_valid_i  (s_hp_snap_req_valid),
      .snapshot_req_ready_o  (s_hp_snap_req_ready),
      .snapshot_resp_valid_o (s_hp_snap_resp_valid),
      .snapshot_resp_ready_i (s_hp_snap_resp_ready),
      .snapshot_resp_data_o  (s_hp_snap_resp_payload),
      .epoch_req_i           (s_hp_epoch_req),
      .epoch_ack_o           (s_hp_epoch_ack),
      .quiesce_req_i         (s_hp_quiesce_req),
      .quiesce_ack_o         (s_hp_quiesce_ack),
      .busy_o                (s_hp_busy),
      .draining_o            (s_hp_draining),
      .block_new_i           (hp_block_new_i),
      .clock_pause_ack_o     (hp_pause_ack_o),
      .flush_i               (hp_flush_i),
      .flush_busy_o          (hp_flush_busy_o),
      .pause_active_o        (s_hp_pause_active),
      .idle_o                (hp_idle_o),
      .abort_i               (s_abort_hp_pulse),
      .dma_clear_o           (s_dma_clear),
      .dma_read_req_valid_o  (s_dma_read_req_valid),
      .dma_read_req_ready_i  (s_dma_read_req_ready),
      .dma_read_addr_o       (s_dma_read_addr),
      .dma_read_bytes_o      (s_dma_read_bytes),
      .dma_read_data_valid_i (s_dma_read_data_valid),
      .dma_read_data_ready_o (s_dma_read_data_ready),
      .dma_read_data_i       (s_dma_read_data),
      .dma_read_keep_i       (s_dma_read_keep),
      .dma_read_last_i       (s_dma_read_last),
      .dma_write_req_valid_o (s_dma_write_req_valid),
      .dma_write_req_ready_i (s_dma_write_req_ready),
      .dma_write_addr_o      (s_dma_write_addr),
      .dma_write_bytes_o     (s_dma_write_bytes),
      .dma_write_data_valid_o(s_dma_write_data_valid),
      .dma_write_data_ready_i(s_dma_write_data_ready),
      .dma_write_data_o      (s_dma_write_data),
      .dma_write_keep_o      (s_dma_write_keep),
      .dma_write_last_o      (s_dma_write_last),
      .dma_write_done_i      (s_dma_write_done),
      .dma_busy_i            (s_dma_busy),
      .dma_read_busy_i       (s_dma_read_busy),
      .dma_write_busy_i      (s_dma_write_busy),
      .dma_pause_ack_i       (s_dma_pause_ack),
      .dma_fault_i           (s_dma_fault),
      .dma_fault_code_i      (s_dma_fault_code),
      .dma_fault_addr_i      (s_dma_fault_addr),
      .dma_fault_resp_i      (s_dma_fault_resp),
      .dma_read_bytes_i      (s_dma_read_bytes_cnt),
      .dma_write_bytes_i     (s_dma_write_bytes_cnt),
      .dma_stall_cycles_i    (s_dma_stall_cycles),
      .dma_read_cmd_err_i    (s_dma_read_cmd_err),
      .dma_write_cmd_err_i   (s_dma_write_cmd_err)
  );

  // The P3 AXI4 data plane: the production npu_dma engine drives the master
  // port directly (HP-native, no payload CDC or width conversion). Its
  // receivers are live whenever an accepted obligation exists, and presented
  // but unaccepted requests stay stable through pause and abort per the
  // frozen contract.
  // PRODUCT memory targets use a 64-to-32 downsizer: eight AXI64 beats expand
  // to the frontends' frozen sixteen-AXI32-beat maximum.
  npu_dma #(
      .MaxBurstBeats(8)
  ) u_npu_dma (
      .clk_hp_i          (clk_hp_i),
      .rst_hp_n_i        (rst_hp_n_i),
      .clear_i           (hp_flush_i || s_dma_clear),
      .block_new_i       (hp_block_new_i),
      .pause_ack_o       (s_dma_pause_ack),
      .read_req_valid_i  (s_dma_read_req_valid),
      .read_req_ready_o  (s_dma_read_req_ready),
      .read_addr_i       (s_dma_read_addr),
      .read_bytes_i      (s_dma_read_bytes),
      .read_data_valid_o (s_dma_read_data_valid),
      .read_data_ready_i (s_dma_read_data_ready),
      .read_data_o       (s_dma_read_data),
      .read_keep_o       (s_dma_read_keep),
      .read_last_o       (s_dma_read_last),
      .write_req_valid_i (s_dma_write_req_valid),
      .write_req_ready_o (s_dma_write_req_ready),
      .write_addr_i      (s_dma_write_addr),
      .write_bytes_i     (s_dma_write_bytes),
      .write_data_valid_i(s_dma_write_data_valid),
      .write_data_ready_o(s_dma_write_data_ready),
      .write_data_i      (s_dma_write_data),
      .write_keep_i      (s_dma_write_keep),
      .write_last_i      (s_dma_write_last),
      .write_done_o      (s_dma_write_done),
      .busy_o            (s_dma_busy),
      .read_busy_o       (s_dma_read_busy),
      .write_busy_o      (s_dma_write_busy),
      .read_bytes_o      (s_dma_read_bytes_cnt),
      .write_bytes_o     (s_dma_write_bytes_cnt),
      .stall_cycles_o    (s_dma_stall_cycles),
      .fault_o           (s_dma_fault),
      .fault_code_o      (s_dma_fault_code),
      .fault_addr_o      (s_dma_fault_addr),
      .fault_resp_o      (s_dma_fault_resp),
      .read_cmd_err_o    (s_dma_read_cmd_err),
      .write_cmd_err_o   (s_dma_write_cmd_err),
      .axi4              (npu_axi4)
  );

  // Software ABORT route: the PCLK pulse toggles a shell register that crosses
  // through cdc_sync; the HP edge detector produces the abort pulse. A second
  // ABORT arriving within the synchronization window is idempotent (the job is
  // already cancelling), so no toggle can be lost that matters.
  assign s_abort_toggle_d = s_abort ? !s_abort_toggle_q : s_abort_toggle_q;
  dffr #(
      .DATA_WIDTH(1)
  ) u_abort_toggle (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_abort_toggle_d),
      .dat_o  (s_abort_toggle_q)
  );
  cdc_sync #(
      .STAGE(2)
  ) u_abort_sync (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  (s_abort_toggle_q),
      .dat_o  (s_abort_toggle_hp)
  );
  assign s_abort_hp_d = s_abort_toggle_hp;
  dffr #(
      .DATA_WIDTH(1)
  ) u_abort_hp (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  (s_abort_hp_d),
      .dat_o  (s_abort_hp_q)
  );
  assign s_abort_hp_pulse = s_abort_toggle_hp ^ s_abort_hp_q;

`ifndef SV_ASSRT_DISABLE
  logic s_p2_idle_master_q;

  // The shell-level Phase 2 contract that the software-visible master stays
  // silent while no job can be launched (START is still rejected at P3).
  always_ff @(posedge clk_hp_i or negedge rst_hp_n_i) begin
    if (!rst_hp_n_i) begin
      s_p2_idle_master_q <= 1'b1;
    end else begin
      s_p2_idle_master_q <= !s_hp_busy;
      if (s_p2_idle_master_q) begin
        assert (!npu_axi4.awvalid && !npu_axi4.wvalid && !npu_axi4.arvalid);
      end
    end
  end
`endif
endmodule
