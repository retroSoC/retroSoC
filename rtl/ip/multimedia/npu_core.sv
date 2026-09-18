// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// NPU Phase 2 HP-domain lifecycle endpoint. It terminates the launch, result,
// and snapshot mailboxes of npu_control_cdc, participates in the epoch
// reconciliation handshake, and answers idle snapshots with a zero counter
// bank. Phase 2 has no jobs and no DMA: launches can never be accepted by the
// PCLK shell (START never passes), the sink below exists only to keep the
// mailbox protocol complete, no result is ever produced, and there is no AXI
// work to pause, drain, or flush.
`include "npu_define.svh"

module npu_core #(
    parameter int unsigned LaunchPayloadWidth   = `APB4_NPU__LAUNCH_PAYLOAD_WIDTH,
    parameter int unsigned ResultPayloadWidth   = `APB4_NPU__RESULT_PAYLOAD_WIDTH,
    parameter int unsigned SnapshotPayloadWidth = `APB4_NPU__SNAPSHOT_PAYLOAD_WIDTH,
    parameter int unsigned EpochWidth           = `APB4_NPU__EPOCH_WIDTH
) (
    // verilog_format: off -- preserve the HP lifecycle boundary columns
    input  logic                            clk_hp_i,
    input  logic                            rst_hp_n_i,
    input  logic                            launch_valid_i,
    output logic                            launch_ready_o,
    input  logic [LaunchPayloadWidth-1:0]   launch_data_i,
    output logic                            result_valid_o,
    input  logic                            result_ready_i,
    output logic [ResultPayloadWidth-1:0]   result_data_o,
    input  logic                            snapshot_req_valid_i,
    output logic                            snapshot_req_ready_o,
    output logic                            snapshot_resp_valid_o,
    input  logic                            snapshot_resp_ready_i,
    output logic [SnapshotPayloadWidth-1:0] snapshot_resp_data_o,
    input  logic [EpochWidth-1:0]           epoch_req_i,
    output logic [EpochWidth-1:0]           epoch_ack_o,
    input  logic                            quiesce_req_i,
    output logic                            quiesce_ack_o,
    output logic                            busy_o,
    output logic                            draining_o,
    input  logic                            block_new_i,
    output logic                            clock_pause_ack_o,
    input  logic                            flush_i,
    output logic                            flush_busy_o,
    output logic                            pause_active_o,
    output logic                            idle_o
    // verilog_format: on
);
  typedef enum logic [0:0] {
    SnapIdle,
    SnapRespond
  } state_e;

  state_e s_state_d, s_state_q;
  logic [EpochWidth-1:0] s_epoch_ack_d, s_epoch_ack_q;
  logic s_quiesce_ack_d, s_quiesce_ack_q;
  logic s_epoch_restart;
  logic s_unused;

`ifndef SYNTHESIS
  initial begin
    if ((EpochWidth < 2) || (LaunchPayloadWidth < 1) || (ResultPayloadWidth < 1) ||
        (SnapshotPayloadWidth < 1)) begin
      $fatal(1, "npu_core: invalid payload or epoch geometry");
    end
  end
`endif

  // Phase 2 protocol-complete sinks and constant sources: a launch is sunk
  // (unreachable), no terminal result exists, the idle snapshot returns the
  // zero bank with a zero job token, and no AXI activity ever needs draining.
  assign launch_ready_o       = 1'b1;
  assign result_valid_o       = 1'b0;
  assign result_data_o        = '0;
  assign busy_o               = 1'b0;
  assign draining_o           = 1'b0;
  assign flush_busy_o         = 1'b0;
  assign snapshot_resp_data_o = '0;

  // With zero accepted AXI obligations and no internal work, the clock-pause
  // acknowledge is immediate and the HP idle contribution follows the
  // platform formula !block_new_i || clock_pause_ack_o.
  assign clock_pause_ack_o    = block_new_i;
  assign pause_active_o       = block_new_i && clock_pause_ack_o;
  assign idle_o               = !block_new_i || clock_pause_ack_o;

  assign epoch_ack_o          = s_epoch_ack_q;
  assign quiesce_ack_o        = s_quiesce_ack_q;

  assign s_epoch_restart      = (epoch_req_i != s_epoch_ack_q);
  assign s_unused             = ^{launch_data_i, result_ready_i, flush_i, 1'b0};

  always_comb begin
    s_state_d             = s_state_q;
    s_epoch_ack_d         = s_epoch_ack_q;
    s_quiesce_ack_d       = quiesce_req_i;
    snapshot_req_ready_o  = 1'b0;
    snapshot_resp_valid_o = 1'b0;
    unique case (s_state_q)
      SnapIdle: begin
        snapshot_req_ready_o = 1'b1;
        if (snapshot_req_valid_i) begin
          s_state_d = SnapRespond;
        end
      end
      SnapRespond: begin
        snapshot_resp_valid_o = 1'b1;
        if (snapshot_resp_ready_i) begin
          s_state_d = SnapIdle;
        end
      end
      default: s_state_d = SnapIdle;
    endcase
    // A fresh epoch restarts the endpoint bookkeeping before it is
    // acknowledged: any in-flight mailbox item is being flushed by the link
    // reset held for the whole reconciliation, so the endpoint returns to
    // SnapIdle first and only then publishes the new epoch.
    if (s_epoch_restart) begin
      s_state_d     = SnapIdle;
      s_epoch_ack_d = epoch_req_i;
    end
  end

  always_ff @(posedge clk_hp_i or negedge rst_hp_n_i) begin
    if (!rst_hp_n_i) begin
      s_state_q <= SnapIdle;
    end else begin
      s_state_q <= s_state_d;
    end
  end

  dffr #(
      .DATA_WIDTH(EpochWidth)
  ) u_epoch_ack (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  (s_epoch_ack_d),
      .dat_o  (s_epoch_ack_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_quiesce_ack (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  (s_quiesce_ack_d),
      .dat_o  (s_quiesce_ack_q)
  );

`ifndef SV_ASSRT_DISABLE
  logic s_resp_wait_q;
  logic s_epoch_restart_q;

  always_ff @(posedge clk_hp_i or negedge rst_hp_n_i) begin
    if (!rst_hp_n_i) begin
      s_resp_wait_q     <= 1'b0;
      s_epoch_restart_q <= 1'b0;
    end else begin
      s_resp_wait_q     <= snapshot_resp_valid_o && !snapshot_resp_ready_i;
      s_epoch_restart_q <= s_epoch_restart;
      // The snapshot response holds valid and its payload stable until the
      // mailbox accepts it; only an epoch restart may withdraw it.
      if (s_resp_wait_q) begin
        assert ((snapshot_resp_valid_o && $stable(snapshot_resp_data_o)) || s_epoch_restart_q);
      end
      // No terminal result can ever appear at Phase 2.
      assert (!result_valid_o);
    end
  end
`endif
endmodule
