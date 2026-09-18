// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// NPU Phase 2 shell/HP control CDC: launch, result, and snapshot
// async_reqack mailboxes, lifecycle scalar synchronizers, and epoch
// reconciliation. An either-domain reset, a coordinated fabric flush, a
// resource reset, or an accepted SOFT_RESET flushes the mailboxes and holds
// the link down until the HP endpoint acknowledges a fresh Gray-coded epoch;
// every completed recovery after the initial reconcile increments the
// PCLK-visible RECOVERY_GENERATION counter (soft reset and the initial
// reconcile rezero it instead). The one-entry Common mailboxes also flush
// themselves on either endpoint reset through their internal reset barrier.
`include "npu_define.svh"

module npu_control_cdc #(
    parameter int unsigned LaunchPayloadWidth   = `APB4_NPU__LAUNCH_PAYLOAD_WIDTH,
    parameter int unsigned ResultPayloadWidth   = `APB4_NPU__RESULT_PAYLOAD_WIDTH,
    parameter int unsigned SnapshotPayloadWidth = `APB4_NPU__SNAPSHOT_PAYLOAD_WIDTH,
    parameter int unsigned EpochWidth           = `APB4_NPU__EPOCH_WIDTH,
    parameter int unsigned SyncStages           = 2
) (
    // verilog_format: off -- preserve the PCLK/HP mailbox boundary columns
    input  logic                            clk_i,
    input  logic                            rst_n_i,
    input  logic                            clk_hp_i,
    input  logic                            rst_hp_n_i,
    input  logic                            launch_req_valid_i,
    output logic                            launch_req_ready_o,
    input  logic [LaunchPayloadWidth-1:0]   launch_req_payload_i,
    output logic                            result_valid_o,
    input  logic                            result_ready_i,
    output logic [ResultPayloadWidth-1:0]   result_payload_o,
    input  logic                            snapshot_req_valid_i,
    output logic                            snapshot_req_ready_o,
    output logic                            snapshot_resp_valid_o,
    input  logic                            snapshot_resp_ready_i,
    output logic [SnapshotPayloadWidth-1:0] snapshot_resp_payload_o,
    input  logic                            soft_reset_i,
    input  logic                            shell_idle_i,
    input  logic                            resource_quiesce_i,
    input  logic                            resource_reset_i,
    output logic                            link_up_o,
    output logic                            flush_active_o,
    output logic [31:0]                     recovery_generation_o,
    output logic                            block_ack_o,
    output logic                            hp_launch_valid_o,
    input  logic                            hp_launch_ready_i,
    output logic [LaunchPayloadWidth-1:0]   hp_launch_payload_o,
    input  logic                            hp_result_valid_i,
    output logic                            hp_result_ready_o,
    input  logic [ResultPayloadWidth-1:0]   hp_result_payload_i,
    output logic                            hp_snapshot_req_valid_o,
    input  logic                            hp_snapshot_req_ready_i,
    input  logic                            hp_snapshot_resp_valid_i,
    output logic                            hp_snapshot_resp_ready_o,
    input  logic [SnapshotPayloadWidth-1:0] hp_snapshot_resp_payload_i,
    output logic [EpochWidth-1:0]           hp_epoch_req_o,
    input  logic [EpochWidth-1:0]           hp_epoch_ack_i,
    output logic                            hp_quiesce_req_o,
    input  logic                            hp_quiesce_ack_i,
    input  logic                            hp_busy_i,
    input  logic                            hp_draining_i,
    input  logic                            hp_pause_active_i,
    input  logic                            hp_flush_i,
    output logic                            hp_busy_o,
    output logic                            hp_draining_o,
    output logic                            clock_paused_o
    // verilog_format: on
);
  // The epoch is a PCLK counter crossed as reflected Gray code. A fresh epoch
  // is never toggled blindly: the request is derived from the observed
  // acknowledgement as bin(ack)+1, so every new epoch is one the HP endpoint
  // has never acknowledged and a match is always genuine round-trip evidence.
  // One synchronizer bit changes per Gray transition, including the wrap.
  typedef enum logic [0:0] {
    LinkDown,
    LinkUp
  } state_e;

  // The acknowledgement and HP-reset synchronizers flush on a PCLK reset and
  // then briefly replay stale samples; reconciliation waits out this refill
  // margin (SYNC_STAGES plus two edges) before evaluating any crossing.
  localparam int unsigned RefillCycles = 4;

  state_e s_state_d, s_state_q;
  logic [EpochWidth-1:0] s_epoch_d, s_epoch_q;
  logic [EpochWidth-1:0] s_epoch_gray;
  logic [EpochWidth-1:0] s_epoch_next;
  logic [EpochWidth-1:0] s_hp_epoch_ack_gray;
  logic [31:0] s_generation_d, s_generation_q;
  logic s_init_done_d, s_init_done_q;
  logic s_soft_pending_d, s_soft_pending_q;
  logic s_block_ack_d, s_block_ack_q;
  logic s_hold_link_d, s_hold_link_q;
  logic [2:0] s_refill_cnt_d, s_refill_cnt_q;
  logic s_epoch_armed_d, s_epoch_armed_q;
  logic s_hp_rst_n_sync;
  logic s_hp_flush_sync;
  logic s_hp_quiesce_ack_sync;
  logic s_hold_link;
  logic s_hold_link_rise;
  logic s_resource_hold;
  logic s_epoch_matched;
  logic s_refill_done;
  logic s_link_up;
  logic s_mbox_pclk_rst_n;

  function automatic logic [EpochWidth-1:0] gray_decode(input logic [EpochWidth-1:0] gray_i);
    logic [EpochWidth-1:0] decoded;
    begin
      decoded = '0;
      for (int unsigned bit_index = 0; bit_index < EpochWidth; bit_index++) begin
        decoded[bit_index] = ^(gray_i >> bit_index);
      end
      return decoded;
    end
  endfunction

`ifndef SYNTHESIS
  initial begin
    if ((EpochWidth < 2) || (SyncStages < 2) || (LaunchPayloadWidth < 1) ||
        (ResultPayloadWidth < 1) || (SnapshotPayloadWidth < 1)) begin
      $fatal(1, "npu_control_cdc: invalid payload, epoch, or synchronizer geometry");
    end
  end
`endif

  assign s_epoch_gray          = s_epoch_q ^ (s_epoch_q >> 1);
  assign s_epoch_next          = gray_decode(s_hp_epoch_ack_gray) + EpochWidth'(1);
  assign s_hold_link           = resource_reset_i || !s_hp_rst_n_sync || s_hp_flush_sync;
  assign s_hold_link_rise      = s_hold_link && !s_hold_link_q;
  assign s_resource_hold       = resource_quiesce_i || resource_reset_i;
  assign s_epoch_matched       = (s_hp_epoch_ack_gray == s_epoch_gray);
  assign s_refill_done         = (s_refill_cnt_q == 3'(RefillCycles));
  assign s_link_up             = (s_state_q == LinkUp);
  assign link_up_o             = s_link_up;
  assign flush_active_o        = !s_link_up;
  assign recovery_generation_o = s_generation_q;
  assign block_ack_o           = s_block_ack_q;
  // The mailbox PCLK-side reset flushes both domains through the mailbox
  // internal reset barrier whenever the link is down.
  assign s_mbox_pclk_rst_n     = rst_n_i && s_link_up;

  always_comb begin
    s_state_d        = s_state_q;
    s_epoch_d        = s_epoch_q;
    s_generation_d   = s_generation_q;
    s_init_done_d    = s_init_done_q;
    s_soft_pending_d = s_soft_pending_q;
    s_block_ack_d    = s_block_ack_q;
    s_hold_link_d    = s_hold_link;
    s_refill_cnt_d   = s_refill_cnt_q;
    s_epoch_armed_d  = s_epoch_armed_q;

    // The resource quiesce/reset acknowledgement is a genuine round trip:
    // the HP endpoint must register the request and the current epoch must be
    // acknowledged after the hold began, with the PCLK shell launch slot and
    // snapshot handshake idle (a pending shell launch still participates here
    // even though Phase 2 never accepts one). A hold that invalidates the
    // link enters LinkDown and derives a fresh epoch first, so a matched
    // epoch in LinkDown is always fresh; a quiesce-only hold keeps the link
    // up. Epoch or request evidence lost mid-hold (for example an HP reset
    // during a quiesce) revokes the acknowledgement until reconciled again.
    if (!s_resource_hold) begin
      s_block_ack_d = 1'b0;
    end else if (!s_epoch_matched || !s_hp_quiesce_ack_sync) begin
      s_block_ack_d = 1'b0;
    end else if (shell_idle_i && ((s_state_q == LinkDown) || !s_hold_link)) begin
      s_block_ack_d = 1'b1;
    end

    unique case (s_state_q)
      LinkDown: begin
        if (!s_refill_done) begin
          s_refill_cnt_d = s_refill_cnt_q + 3'd1;
        end
        if (soft_reset_i) begin
          s_soft_pending_d = 1'b1;
        end
        // The first epoch after a shell reset is armed only after the
        // synchronizers refilled; a fresh hold condition arriving after the
        // current epoch already reconciled forces another acknowledged epoch
        // before rearm.
        if (s_refill_done && !s_epoch_armed_q) begin
          s_epoch_d       = s_epoch_next;
          s_epoch_armed_d = 1'b1;
        end else if (s_hold_link_rise && s_epoch_matched) begin
          s_epoch_d = s_epoch_next;
        end
        if (s_refill_done && s_epoch_armed_q && s_epoch_matched && !s_hold_link) begin
          s_state_d        = LinkUp;
          s_init_done_d    = 1'b1;
          s_soft_pending_d = 1'b0;
          if (s_soft_pending_q || soft_reset_i || !s_init_done_q) begin
            s_generation_d = 32'd0;
          end else begin
            s_generation_d = s_generation_q + 32'd1;
          end
        end
      end
      LinkUp: begin
        if (s_hold_link || soft_reset_i) begin
          s_state_d        = LinkDown;
          s_soft_pending_d = soft_reset_i;
          s_epoch_d        = s_epoch_next;
        end
      end
      default: begin
        s_state_d        = LinkDown;
        s_epoch_d        = '0;
        s_generation_d   = 32'd0;
        s_init_done_d    = 1'b0;
        s_soft_pending_d = 1'b0;
        s_block_ack_d    = 1'b0;
        s_refill_cnt_d   = 3'd0;
        s_epoch_armed_d  = 1'b0;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q <= LinkDown;
    end else begin
      s_state_q <= s_state_d;
    end
  end

  dffr #(
      .DATA_WIDTH(EpochWidth)
  ) u_epoch (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_epoch_d),
      .dat_o  (s_epoch_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_generation (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_generation_d),
      .dat_o  (s_generation_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_init_done (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_init_done_d),
      .dat_o  (s_init_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_soft_pending (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_soft_pending_d),
      .dat_o  (s_soft_pending_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_block_ack (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_block_ack_d),
      .dat_o  (s_block_ack_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_hold_link (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_hold_link_d),
      .dat_o  (s_hold_link_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_refill_cnt (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_refill_cnt_d),
      .dat_o  (s_refill_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_epoch_armed (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_epoch_armed_d),
      .dat_o  (s_epoch_armed_q)
  );

  // Launch mailbox, PCLK shell to HP endpoint.
  async_reqack #(
      .DATA_WIDTH (LaunchPayloadWidth),
      .SYNC_STAGES(SyncStages)
  ) u_launch_mailbox (
      .src_clk_i  (clk_i),
      .src_rst_n_i(s_mbox_pclk_rst_n),
      .src_valid_i(launch_req_valid_i),
      .src_ready_o(launch_req_ready_o),
      .src_data_i (launch_req_payload_i),
      .dst_clk_i  (clk_hp_i),
      .dst_rst_n_i(rst_hp_n_i),
      .dst_valid_o(hp_launch_valid_o),
      .dst_ready_i(hp_launch_ready_i),
      .dst_data_o (hp_launch_payload_o)
  );

  // Result mailbox, HP endpoint to PCLK shell.
  async_reqack #(
      .DATA_WIDTH (ResultPayloadWidth),
      .SYNC_STAGES(SyncStages)
  ) u_result_mailbox (
      .src_clk_i  (clk_hp_i),
      .src_rst_n_i(rst_hp_n_i),
      .src_valid_i(hp_result_valid_i),
      .src_ready_o(hp_result_ready_o),
      .src_data_i (hp_result_payload_i),
      .dst_clk_i  (clk_i),
      .dst_rst_n_i(s_mbox_pclk_rst_n),
      .dst_valid_o(result_valid_o),
      .dst_ready_i(result_ready_i),
      .dst_data_o (result_payload_o)
  );

  // Snapshot request mailbox, PCLK shell to HP endpoint.
  async_reqack #(
      .DATA_WIDTH (1),
      .SYNC_STAGES(SyncStages)
  ) u_snapshot_req_mailbox (
      .src_clk_i  (clk_i),
      .src_rst_n_i(s_mbox_pclk_rst_n),
      .src_valid_i(snapshot_req_valid_i),
      .src_ready_o(snapshot_req_ready_o),
      .src_data_i (1'b0),
      .dst_clk_i  (clk_hp_i),
      .dst_rst_n_i(rst_hp_n_i),
      .dst_valid_o(hp_snapshot_req_valid_o),
      .dst_ready_i(hp_snapshot_req_ready_i),
      .dst_data_o ()
  );

  // Snapshot response mailbox, HP endpoint to PCLK shell. The whole counter
  // bank and job token cross as one mailbox item; independent synchronizers
  // for counter bits are prohibited by the ABI.
  async_reqack #(
      .DATA_WIDTH (SnapshotPayloadWidth),
      .SYNC_STAGES(SyncStages)
  ) u_snapshot_resp_mailbox (
      .src_clk_i  (clk_hp_i),
      .src_rst_n_i(rst_hp_n_i),
      .src_valid_i(hp_snapshot_resp_valid_i),
      .src_ready_o(hp_snapshot_resp_ready_o),
      .src_data_i (hp_snapshot_resp_payload_i),
      .dst_clk_i  (clk_i),
      .dst_rst_n_i(s_mbox_pclk_rst_n),
      .dst_valid_o(snapshot_resp_valid_o),
      .dst_ready_i(snapshot_resp_ready_i),
      .dst_data_o (snapshot_resp_payload_o)
  );

  // Lifecycle scalar crossings. cdc_sync is restricted to these
  // independently encoded controls; multi-bit payloads use the mailboxes.
  cdc_sync #(
      .STAGE(SyncStages)
  ) u_hp_reset_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (rst_hp_n_i),
      .dat_o  (s_hp_rst_n_sync)
  );
  cdc_sync #(
      .STAGE(SyncStages)
  ) u_hp_flush_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (hp_flush_i),
      .dat_o  (s_hp_flush_sync)
  );
  cdc_sync #(
      .STAGE     (SyncStages),
      .DATA_WIDTH(EpochWidth)
  ) u_epoch_req_sync (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  (s_epoch_gray),
      .dat_o  (hp_epoch_req_o)
  );
  cdc_sync #(
      .STAGE     (SyncStages),
      .DATA_WIDTH(EpochWidth)
  ) u_epoch_ack_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (hp_epoch_ack_i),
      .dat_o  (s_hp_epoch_ack_gray)
  );
  cdc_sync #(
      .STAGE(SyncStages)
  ) u_quiesce_req_sync (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  (s_resource_hold),
      .dat_o  (hp_quiesce_req_o)
  );
  cdc_sync #(
      .STAGE(SyncStages)
  ) u_quiesce_ack_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (hp_quiesce_ack_i),
      .dat_o  (s_hp_quiesce_ack_sync)
  );
  cdc_sync #(
      .STAGE(SyncStages)
  ) u_hp_busy_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (hp_busy_i),
      .dat_o  (hp_busy_o)
  );
  cdc_sync #(
      .STAGE(SyncStages)
  ) u_hp_draining_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (hp_draining_i),
      .dat_o  (hp_draining_o)
  );
  cdc_sync #(
      .STAGE(SyncStages)
  ) u_hp_pause_active_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (hp_pause_active_i),
      .dat_o  (clock_paused_o)
  );

`ifndef SV_ASSRT_DISABLE
  logic s_launch_wait_q;
  logic s_link_down_q;
  logic s_hold_prev_q;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_launch_wait_q <= 1'b0;
      s_link_down_q   <= 1'b0;
      s_hold_prev_q   <= 1'b0;
    end else begin
      s_launch_wait_q <= launch_req_valid_i && !launch_req_ready_o;
      s_link_down_q   <= !s_link_up;
      s_hold_prev_q   <= s_resource_hold;
      // A launch request holds valid and payload until accepted; only the
      // mailbox flush of a link-down event may withdraw it.
      if (s_launch_wait_q) begin
        assert ((launch_req_valid_i && $stable(launch_req_payload_i)) || s_link_down_q);
      end
      // An operational link always runs on an acknowledged current epoch.
      if (s_link_up && !s_hold_link) begin
        assert (s_epoch_matched);
      end
      // The registered acknowledgement trails the request by one cycle;
      // outside that trailing edge it is impossible without a request.
      if (block_ack_o) begin
        assert (s_resource_hold || s_hold_prev_q);
      end
    end
  end
`endif
endmodule
