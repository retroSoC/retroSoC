// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// NPU Phase 2 top shell: the PCLK register file (npu_reg), the shell/HP
// control CDC with epoch reconciliation (npu_control_cdc), and the minimal HP
// lifecycle endpoint (npu_core). The private AXI4 master is tied safely idle:
// no AW/W/AR request is ever issued, the R/B receivers stay ready as required
// by the reserved-burst rule, and W never precedes AW by construction. The
// production DMA that will drive this master is Phase 3 scope.
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
  logic                            s_abort_unused;

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

  npu_core u_npu_core (
      .clk_hp_i             (clk_hp_i),
      .rst_hp_n_i           (rst_hp_n_i),
      .launch_valid_i       (s_hp_launch_valid),
      .launch_ready_o       (s_hp_launch_ready),
      .launch_data_i        (s_hp_launch_payload),
      .result_valid_o       (s_hp_result_valid),
      .result_ready_i       (s_hp_result_ready),
      .result_data_o        (s_hp_result_payload),
      .snapshot_req_valid_i (s_hp_snap_req_valid),
      .snapshot_req_ready_o (s_hp_snap_req_ready),
      .snapshot_resp_valid_o(s_hp_snap_resp_valid),
      .snapshot_resp_ready_i(s_hp_snap_resp_ready),
      .snapshot_resp_data_o (s_hp_snap_resp_payload),
      .epoch_req_i          (s_hp_epoch_req),
      .epoch_ack_o          (s_hp_epoch_ack),
      .quiesce_req_i        (s_hp_quiesce_req),
      .quiesce_ack_o        (s_hp_quiesce_ack),
      .busy_o               (s_hp_busy),
      .draining_o           (s_hp_draining),
      .block_new_i          (hp_block_new_i),
      .clock_pause_ack_o    (hp_pause_ack_o),
      .flush_i              (hp_flush_i),
      .flush_busy_o         (hp_flush_busy_o),
      .pause_active_o       (s_hp_pause_active),
      .idle_o               (hp_idle_o)
  );

  // Phase 2: the AXI4 master is tied safely idle. No request is ever issued
  // and the response receivers remain ready; production DMA is Phase 3.
  assign npu_axi4.awid     = '0;
  assign npu_axi4.awaddr   = '0;
  assign npu_axi4.awlen    = '0;
  assign npu_axi4.awsize   = '0;
  assign npu_axi4.awburst  = '0;
  assign npu_axi4.awlock   = 1'b0;
  assign npu_axi4.awcache  = '0;
  assign npu_axi4.awprot   = '0;
  assign npu_axi4.awqos    = '0;
  assign npu_axi4.awregion = '0;
  assign npu_axi4.awuser   = '0;
  assign npu_axi4.awvalid  = 1'b0;
  assign npu_axi4.wdata    = '0;
  assign npu_axi4.wstrb    = '0;
  assign npu_axi4.wlast    = 1'b0;
  assign npu_axi4.wuser    = '0;
  assign npu_axi4.wvalid   = 1'b0;
  assign npu_axi4.bready   = 1'b1;
  assign npu_axi4.arid     = '0;
  assign npu_axi4.araddr   = '0;
  assign npu_axi4.arlen    = '0;
  assign npu_axi4.arsize   = '0;
  assign npu_axi4.arburst  = '0;
  assign npu_axi4.arlock   = 1'b0;
  assign npu_axi4.arcache  = '0;
  assign npu_axi4.arprot   = '0;
  assign npu_axi4.arqos    = '0;
  assign npu_axi4.arregion = '0;
  assign npu_axi4.aruser   = '0;
  assign npu_axi4.arvalid  = 1'b0;
  assign npu_axi4.rready   = 1'b1;

  // The HP abort route is Phase 3 scope; the Phase 2 ABORT command on an idle
  // NPU is a successful no-op and the busy path is unreachable.
  assign s_abort_unused    = s_abort;

`ifndef SV_ASSRT_DISABLE
  always_ff @(posedge clk_hp_i) begin
    if (rst_hp_n_i) begin
      // The tied-off master never issues a request and stays ready to drain.
      assert (!npu_axi4.awvalid && !npu_axi4.wvalid && !npu_axi4.arvalid);
      assert (npu_axi4.bready && npu_axi4.rready);
    end
  end
`endif
endmodule
