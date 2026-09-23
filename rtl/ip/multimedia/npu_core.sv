// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// NPU HP-domain job execution core. With ExecutionReady=1'b0 this is exactly
// the Phase 2 lifecycle endpoint: it terminates the launch, result, and
// snapshot mailboxes of npu_control_cdc, participates in the epoch
// reconciliation handshake, answers idle snapshots with a zero counter bank,
// sinks the (shell-unreachable) launch, and produces no result. With
// ExecutionReady=1'b1 it is the Phase 3 job controller: an accepted launch
// latches {JOB_BASE, JOB_ID, TIMEOUT_CYCLES, JOB_COUNT}, resets the private
// DMA and the per-job counters, and runs npu_job_decoder (fetch + ABI-1.0
// validation) feeding npu_scheduler (transport) record by record until every
// descriptor retires (DONE), the first fault drains (ERROR), software abort
// or resource quiesce cancels (ABORTED), or a reset/flush epoch recovery
// cancels (RESET_CANCELLED, published after the fresh epoch is
// re-acknowledged). The npu_dma engine itself lives in apb4_npu (the Phase 2
// control-CDC testbench instantiates this module without an AXI fabric, so
// the engine interface is a discrete signal boundary); the P2 branch never
// references the P3 ports.
//
// Lifecycle invariants (both configurations): an epoch restart forces the
// endpoint to a safe state before re-acknowledging (at P3 the drain completes
// first: no new work, accepted transport obligations retire, presented but
// unaccepted VALID stays stable); the quiesce acknowledge is a registered
// round trip and at P3 additionally requires the terminal result latched for
// delivery; a flushed or cancelled job never reports DONE; busy_o/draining_o
// are truthful. The first-fault record follows the spec's deterministic
// same-cycle priority AXI_PROTOCOL > AXI_READ > AXI_WRITE > LOCAL_STATE >
// ARITHMETIC > DESCRIPTOR > UNSUPPORTED > RANGE > NO_PROGRESS; reset
// cancellation never overwrites a captured earlier fault.
`include "npu_define.svh"

module npu_core #(
    parameter int unsigned LaunchPayloadWidth   = `APB4_NPU__LAUNCH_PAYLOAD_WIDTH,
    parameter int unsigned ResultPayloadWidth   = `APB4_NPU__RESULT_PAYLOAD_WIDTH,
    parameter int unsigned SnapshotPayloadWidth = `APB4_NPU__SNAPSHOT_PAYLOAD_WIDTH,
    parameter int unsigned EpochWidth           = `APB4_NPU__EPOCH_WIDTH,
    // Phase 3 execution compile switch: the PCLK shell keeps START rejected at
    // P3, so apb4_npu instantiates the live job controller while the software
    // launch path stays closed; the P2 shell testbench elaborates the default
    // (ExecutionReady=0) endpoint.
    parameter bit          ExecutionReady       = 1'b0
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
    output logic                            idle_o,
    // Phase 3: software abort pulse (HP domain, toggle-synchronized in
    // apb4_npu) and the discrete npu_dma engine interface
    input  logic                            abort_i,
    output logic                            dma_clear_o,
    output logic                            dma_read_req_valid_o,
    input  logic                            dma_read_req_ready_i,
    output logic [31:0]                     dma_read_addr_o,
    output logic [31:0]                     dma_read_bytes_o,
    input  logic                            dma_read_data_valid_i,
    output logic                            dma_read_data_ready_o,
    input  logic [63:0]                     dma_read_data_i,
    input  logic [ 7:0]                     dma_read_keep_i,
    input  logic                            dma_read_last_i,
    output logic                            dma_write_req_valid_o,
    input  logic                            dma_write_req_ready_i,
    output logic [31:0]                     dma_write_addr_o,
    output logic [31:0]                     dma_write_bytes_o,
    output logic                            dma_write_data_valid_o,
    input  logic                            dma_write_data_ready_i,
    output logic [63:0]                     dma_write_data_o,
    output logic [ 7:0]                     dma_write_keep_o,
    output logic                            dma_write_last_o,
    input  logic                            dma_write_done_i,
    input  logic                            dma_busy_i,
    input  logic                            dma_read_busy_i,
    input  logic                            dma_write_busy_i,
    input  logic                            dma_pause_ack_i,
    input  logic                            dma_fault_i,
    input  logic [ 3:0]                     dma_fault_code_i,
    input  logic [31:0]                     dma_fault_addr_i,
    input  logic [ 1:0]                     dma_fault_resp_i,
    input  logic [63:0]                     dma_read_bytes_i,
    input  logic [63:0]                     dma_write_bytes_i,
    input  logic [63:0]                     dma_stall_cycles_i,
    input  logic                            dma_read_cmd_err_i,
    input  logic                            dma_write_cmd_err_i
    // verilog_format: on
);
  typedef enum logic [0:0] {
    SnapIdle,
    SnapRespond
  } snap_state_e;

`ifndef SYNTHESIS
  initial begin
    if ((EpochWidth < 2) || (LaunchPayloadWidth < 1) || (ResultPayloadWidth < 1) ||
        (SnapshotPayloadWidth < 1)) begin
      $fatal(1, "npu_core: invalid payload or epoch geometry");
    end
  end
`endif

  if (!ExecutionReady) begin : gen_p2_endpoint
    // Phase 2 protocol-complete sinks and constant sources: a launch is sunk
    // (unreachable), no terminal result exists, the idle snapshot returns the
    // zero bank with a zero job token, and no AXI activity ever needs
    // draining. The P3 engine interface is tied off and its inputs are
    // unread by construction.
    snap_state_e s_state_d, s_state_q;
    logic [EpochWidth-1:0] s_epoch_ack_d, s_epoch_ack_q;
    logic s_quiesce_ack_d, s_quiesce_ack_q;
    logic s_epoch_restart;
    logic s_unused;

    assign launch_ready_o       = 1'b1;
    assign result_valid_o       = 1'b0;
    assign result_data_o        = '0;
    assign busy_o               = 1'b0;
    assign draining_o           = 1'b0;
    assign flush_busy_o         = 1'b0;
    assign snapshot_resp_data_o = '0;

    // With zero accepted AXI obligations and no internal work, the
    // clock-pause acknowledge is immediate and the HP idle contribution
    // follows the platform formula !block_new_i || clock_pause_ack_o.
    assign clock_pause_ack_o    = block_new_i;
    assign pause_active_o       = block_new_i && clock_pause_ack_o;
    assign idle_o               = !block_new_i || clock_pause_ack_o;

    assign epoch_ack_o          = s_epoch_ack_q;
    assign quiesce_ack_o        = s_quiesce_ack_q;

    assign s_epoch_restart      = (epoch_req_i != s_epoch_ack_q);
    assign s_unused             = ^{launch_data_i, result_ready_i, flush_i, 1'b0};

    assign dma_clear_o            = 1'b0;
    assign dma_read_req_valid_o   = 1'b0;
    assign dma_read_addr_o        = '0;
    assign dma_read_bytes_o       = '0;
    assign dma_read_data_ready_o  = 1'b0;
    assign dma_write_req_valid_o  = 1'b0;
    assign dma_write_addr_o       = '0;
    assign dma_write_bytes_o      = '0;
    assign dma_write_data_valid_o = 1'b0;
    assign dma_write_data_o       = '0;
    assign dma_write_keep_o       = '0;
    assign dma_write_last_o       = 1'b0;

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
  end else begin : gen_p3_core
    // -----------------------------------------------------------------
    // Phase 3 job controller
    // -----------------------------------------------------------------
    typedef enum logic [2:0] {
      CoreIdle,
      CoreRun,
      CoreDrainFault,
      CoreDrainAbort,
      CoreDrainReset,
      CorePublish
    } core_state_e;

    core_state_e s_state_d, s_state_q;
    snap_state_e s_snap_state_d, s_snap_state_q;
    logic [EpochWidth-1:0] s_epoch_ack_d, s_epoch_ack_q;
    logic s_quiesce_ack_d, s_quiesce_ack_q;
    logic s_epoch_restart;
    // job context
    logic [31:0] s_job_base_q;
    logic [31:0] s_job_id_q;
    logic [31:0] s_timeout_q;
    logic [15:0] s_job_count_q;
    logic [31:0] s_term_job_id_q;
    // first-fault record
    logic        s_fault_seen_d, s_fault_seen_q;
    logic [ 3:0] s_fault_code_d, s_fault_code_q;
    logic [31:0] s_fault_addr_d, s_fault_addr_q;
    logic [31:0] s_fault_info_d, s_fault_info_q;
    logic [31:0] s_fault_desc_d, s_fault_desc_q;
    // terminal record
    logic [ 2:0] s_res_code_d, s_res_code_q;
    logic [ 2:0] s_res_irq_d, s_res_irq_q;
    logic [31:0] s_res_completed_d, s_res_completed_q;
    // snapshot capture
    logic [SnapshotPayloadWidth-1:0] s_snap_payload_d, s_snap_payload_q;
    logic s_launch_accept;
    logic s_job_busy;
    logic s_dec_busy;
    logic s_sch_busy;
    logic s_sch_drained;
    logic s_drained;
    logic s_compose_terminal;
    logic s_stop;
    logic s_clear;
    // decoder wires
    logic        s_dec_job_start;
    logic        s_dec_read_req_valid;
    logic        s_dec_read_req_ready;
    logic [31:0] s_dec_read_addr;
    logic [31:0] s_dec_read_bytes;
    logic        s_dec_read_data_valid;
    logic        s_dec_read_data_ready;
    logic        s_dec_pause_ok;
    logic        s_dec_all_done;
    logic        s_all_done_q;
    logic        s_dec_progress;
    logic        s_dec_fault_req;
    logic [ 3:0] s_dec_fault_code;
    logic [31:0] s_dec_fault_addr;
    logic [31:0] s_dec_fault_info;
    logic [31:0] s_dec_fault_desc;
    logic [15:0] s_dec_cur_index;
    logic        s_dec_retired;
    // record wires decoder -> scheduler
    logic        s_rec_valid;
    logic        s_rec_ready;
    logic [ 3:0] s_rec_opcode;
    logic [12:0] s_rec_h, s_rec_w, s_rec_cin, s_rec_cout, s_rec_oh, s_rec_ow;
    logic [31:0] s_rec_input0_base, s_rec_output_base;
    logic [31:0] s_rec_weight_base, s_rec_param_base;
    logic [31:0] s_rec_irow, s_rec_orow;
    logic [ 7:0] s_rec_kh, s_rec_kw, s_rec_sh, s_rec_sw;
    logic [ 7:0] s_rec_pad_top, s_rec_pad_left, s_rec_in0_zero;
    logic [ 7:0] s_rec_tile_h, s_rec_tile_w;
    logic [15:0] s_rec_k_slice;
    logic [31:0] s_rec_input1_base, s_rec_input1_row_bytes;
    logic [ 7:0] s_rec_in1_zero, s_rec_out_zero, s_rec_act_min, s_rec_act_max;
    logic [31:0] s_rec_weight_bytes, s_rec_param_bytes;
    logic [15:0] s_rec_desc_index;
    // scheduler wires
    logic        s_sch_launch;
    logic        s_sch_retired;
    logic [31:0] s_sch_completed;
    logic        s_sch_read_req_valid;
    logic        s_sch_read_req_ready;
    logic [31:0] s_sch_read_addr;
    logic [31:0] s_sch_read_bytes;
    logic        s_sch_read_data_valid;
    logic        s_sch_read_data_ready;
    logic        s_sch_write_req_valid;
    logic [31:0] s_sch_write_addr;
    logic [31:0] s_sch_write_bytes;
    logic        s_sch_write_data_valid;
    logic [63:0] s_sch_write_data;
    logic [ 7:0] s_sch_write_keep;
    logic        s_sch_write_last;
    logic        s_sch_pause_ok;
    logic        s_sch_terminal;
    logic [639:0] s_sch_counters;
    logic [639:0] s_sch_term_counters;
    logic        s_sch_fault_req;
    logic [ 3:0] s_sch_fault_code;
    logic [31:0] s_sch_fault_addr;
    logic [31:0] s_sch_fault_info;
    logic [31:0] s_sch_fault_desc;
    // fault arbitration
    logic        s_evt_dec;
    logic        s_evt_sch;
    logic        s_evt_cmd_err;
    logic [ 3:0] s_evt_code;
    logic [31:0] s_evt_addr;
    logic [31:0] s_evt_info;
    logic [31:0] s_evt_desc;
    logic        s_evt_any;

    // Deterministic same-cycle first-fault priority: lower rank wins.
    function automatic logic [3:0] fault_rank(input logic [3:0] code_i);
      logic [3:0] rank;
      begin
        unique case (code_i)
          `APB4_NPU__FAULT_CODE_AXI_PROTOCOL:    rank = 4'd0;
          `APB4_NPU__FAULT_CODE_AXI_READ:        rank = 4'd1;
          `APB4_NPU__FAULT_CODE_AXI_WRITE:       rank = 4'd2;
          `APB4_NPU__FAULT_CODE_LOCAL_STATE:     rank = 4'd3;
          `APB4_NPU__FAULT_CODE_ARITHMETIC:      rank = 4'd4;
          `APB4_NPU__FAULT_CODE_DESCRIPTOR:      rank = 4'd5;
          `APB4_NPU__FAULT_CODE_UNSUPPORTED:     rank = 4'd6;
          `APB4_NPU__FAULT_CODE_RANGE:           rank = 4'd7;
          `APB4_NPU__FAULT_CODE_NO_PROGRESS:     rank = 4'd8;
          default:                               rank = 4'd9;
        endcase
        return rank;
      end
    endfunction

    assign s_evt_dec = s_dec_fault_req;
    assign s_evt_sch = s_sch_fault_req;
    // A rejected DMA command means a scheduler/decoder programming bug.
    assign s_evt_cmd_err = (dma_read_cmd_err_i || dma_write_cmd_err_i) && s_job_busy &&
        !dma_fault_i && !s_fault_seen_q;

    always_comb begin
      s_evt_any  = s_evt_dec || s_evt_sch || s_evt_cmd_err;
      s_evt_code = `APB4_NPU__FAULT_CODE_LOCAL_STATE;
      s_evt_addr = 32'd0;
      s_evt_info = {16'd0, 8'd255, 4'd0, 2'd0, 2'd0};
      s_evt_desc = 32'hffff_ffff;
      if (s_evt_dec) begin
        s_evt_code = s_dec_fault_code;
        s_evt_addr = s_dec_fault_addr;
        s_evt_info = s_dec_fault_info;
        s_evt_desc = s_dec_fault_desc;
      end
      if (s_evt_sch && (!s_evt_dec ||
                        (fault_rank(s_sch_fault_code) <= fault_rank(s_dec_fault_code)))) begin
        s_evt_code = s_sch_fault_code;
        s_evt_addr = s_sch_fault_addr;
        s_evt_info = s_sch_fault_info;
        // A scheduler fault while it is idle (watchdog during the fetch
        // phase) belongs to the descriptor the decoder holds.
        s_evt_desc = s_dec_busy ? {16'd0, s_dec_cur_index} : s_sch_fault_desc;
      end
      if (s_evt_cmd_err && (!s_evt_dec && !s_evt_sch ||
                            (fault_rank(`APB4_NPU__FAULT_CODE_LOCAL_STATE) <=
                             fault_rank(s_evt_code)))) begin
        s_evt_code = `APB4_NPU__FAULT_CODE_LOCAL_STATE;
        s_evt_addr = 32'd0;
        s_evt_info = {16'd0, 8'd255, 4'd0, 2'd0, 2'd0};
        s_evt_desc = s_dec_busy ? {16'd0, s_dec_cur_index} : s_sch_fault_desc;
      end
    end

    assign s_job_busy = (s_state_q != CoreIdle);
    assign s_drained = !s_dec_busy && s_sch_drained && !dma_busy_i;

    assign s_epoch_restart = (epoch_req_i != s_epoch_ack_q);
    assign s_launch_accept = launch_valid_i && launch_ready_o;
    assign s_stop = (s_state_q == CoreDrainFault) || (s_state_q == CoreDrainAbort) ||
        (s_state_q == CoreDrainReset) || flush_i;
    assign s_clear = flush_i ||
        ((s_state_q == CorePublish) && result_valid_o && result_ready_i) ||
        ((s_state_q == CoreDrainReset) && s_drained);
    assign s_compose_terminal = ((s_state_q == CoreRun) && s_all_done_q) ||
        (((s_state_q == CoreDrainFault) || (s_state_q == CoreDrainAbort) ||
          (s_state_q == CoreDrainReset)) && s_drained);

    // -------------------------------------------------------------
    // Mailbox-facing outputs
    // -------------------------------------------------------------
    assign launch_ready_o = (s_state_q == CoreIdle) && !s_epoch_restart && !quiesce_req_i &&
        !flush_i;
    assign busy_o = s_job_busy;
    assign draining_o = (s_state_q == CoreDrainFault) || (s_state_q == CoreDrainAbort) ||
        (s_state_q == CoreDrainReset);
    assign flush_busy_o = 1'b0;
    assign idle_o = !block_new_i || clock_pause_ack_o;
    assign clock_pause_ack_o = block_new_i && dma_pause_ack_i && s_dec_pause_ok &&
        s_sch_pause_ok;
    assign pause_active_o = block_new_i && clock_pause_ack_o;
    assign epoch_ack_o = s_epoch_ack_q;
    assign quiesce_ack_o = s_quiesce_ack_q;

    assign dma_clear_o = flush_i || s_launch_accept;

    // Read-channel ownership alternates fetch (decoder) and execute
    // (scheduler) phases, which never overlap.
    assign dma_read_req_valid_o = s_sch_busy ? s_sch_read_req_valid : s_dec_read_req_valid;
    assign dma_read_addr_o = s_sch_busy ? s_sch_read_addr : s_dec_read_addr;
    assign dma_read_bytes_o = s_sch_busy ? s_sch_read_bytes : s_dec_read_bytes;
    assign s_dec_read_req_ready = !s_sch_busy && dma_read_req_ready_i;
    assign s_sch_read_req_ready = s_sch_busy && dma_read_req_ready_i;
    assign s_dec_read_data_valid = !s_sch_busy && dma_read_data_valid_i;
    assign s_sch_read_data_valid = s_sch_busy && dma_read_data_valid_i;
    assign dma_read_data_ready_o = s_sch_busy ? s_sch_read_data_ready : s_dec_read_data_ready;

    assign dma_write_req_valid_o = s_sch_write_req_valid;
    assign dma_write_addr_o = s_sch_write_addr;
    assign dma_write_bytes_o = s_sch_write_bytes;
    assign dma_write_data_valid_o = s_sch_write_data_valid;
    assign dma_write_data_o = s_sch_write_data;
    assign dma_write_keep_o = s_sch_write_keep;
    assign dma_write_last_o = s_sch_write_last;

    assign s_dec_job_start = s_launch_accept;
    assign s_sch_launch = s_launch_accept;
    assign s_dec_retired = s_sch_retired;
    assign s_sch_terminal = s_compose_terminal;

    // -------------------------------------------------------------
    // Core FSM
    // -------------------------------------------------------------
    always_comb begin
      s_state_d = s_state_q;
      s_epoch_ack_d = s_epoch_ack_q;
      s_quiesce_ack_d = s_quiesce_ack_q;
      s_snap_state_d = s_snap_state_q;
      s_snap_payload_d = s_snap_payload_q;
      s_fault_seen_d = s_fault_seen_q;
      s_fault_code_d = s_fault_code_q;
      s_fault_addr_d = s_fault_addr_q;
      s_fault_info_d = s_fault_info_q;
      s_fault_desc_d = s_fault_desc_q;
      s_res_code_d = s_res_code_q;
      s_res_irq_d = s_res_irq_q;
      s_res_completed_d = s_res_completed_q;
      snapshot_req_ready_o = 1'b0;
      snapshot_resp_valid_o = 1'b0;

      // snapshot endpoint: atomic capture of the live or retained bank
      unique case (s_snap_state_q)
        SnapIdle: begin
          snapshot_req_ready_o = 1'b1;
          if (snapshot_req_valid_i) begin
            s_snap_payload_d = s_job_busy ? {s_sch_counters, s_job_id_q} :
                {s_sch_term_counters, s_term_job_id_q};
            s_snap_state_d = SnapRespond;
          end
        end
        SnapRespond: begin
          snapshot_resp_valid_o = 1'b1;
          if (snapshot_resp_ready_i) begin
            s_snap_state_d = SnapIdle;
          end
        end
        default: s_snap_state_d = SnapIdle;
      endcase

      // first-fault capture (also during abort/reset drains: a fault during
      // cancellation converts the terminal record to ERROR)
      if (s_evt_any && !s_fault_seen_q &&
          ((s_state_q == CoreRun) || (s_state_q == CoreDrainAbort) ||
           (s_state_q == CoreDrainReset))) begin
        s_fault_seen_d = 1'b1;
        s_fault_code_d = s_evt_code;
        s_fault_addr_d = s_evt_addr;
        s_fault_info_d = s_evt_info;
        s_fault_desc_d = s_evt_desc;
      end

      unique case (s_state_q)
        CoreIdle: begin
          if (s_launch_accept) begin
            s_state_d = CoreRun;
          end
        end
        CoreRun: begin
          if (s_evt_any && !s_fault_seen_q) begin
            s_state_d = CoreDrainFault;
          end else if (s_all_done_q) begin
            s_res_code_d = 3'(`APB4_NPU__RESULT_CODE_DONE);
            s_res_irq_d = 3'b001;
            s_res_completed_d = {16'd0, s_job_count_q};
            s_fault_code_d = 4'(`APB4_NPU__FAULT_CODE_NONE);
            s_fault_desc_d = 32'hffff_ffff;
            s_fault_addr_d = 32'd0;
            s_fault_info_d = 32'd0;
            s_state_d = CorePublish;
          end else if (abort_i) begin
            s_state_d = CoreDrainAbort;
          end else if (quiesce_req_i) begin
            s_state_d = CoreDrainAbort;
          end
        end
        CoreDrainFault, CoreDrainAbort: begin
          if (s_drained) begin
            if (s_fault_seen_q) begin
              s_res_code_d = 3'(`APB4_NPU__RESULT_CODE_ERROR);
              s_res_irq_d = 3'b010;
            end else begin
              s_res_code_d = 3'(`APB4_NPU__RESULT_CODE_ABORTED);
              s_res_irq_d = 3'b100;
              s_fault_code_d = 4'(`APB4_NPU__FAULT_CODE_NONE);
              s_fault_desc_d = 32'hffff_ffff;
              s_fault_addr_d = 32'd0;
              s_fault_info_d = 32'd0;
            end
            s_res_completed_d = s_sch_completed;
            s_state_d = CorePublish;
          end
        end
        CoreDrainReset: begin
          if (s_drained) begin
            // stop/drain completed: re-acknowledge the fresh epoch, then
            // deliver the retained cancellation record
            s_epoch_ack_d = epoch_req_i;
            if (s_fault_seen_q) begin
              s_res_code_d = 3'(`APB4_NPU__RESULT_CODE_ERROR);
              s_res_irq_d = 3'b010;
            end else begin
              s_res_code_d = 3'(`APB4_NPU__RESULT_CODE_RESET_CANCELLED);
              s_res_irq_d = 3'b010;
              s_fault_code_d = 4'(`APB4_NPU__FAULT_CODE_RESET_CANCELLED);
              s_fault_desc_d = 32'hffff_ffff;
              s_fault_addr_d = 32'd0;
              s_fault_info_d = 32'd0;
            end
            s_res_completed_d = s_sch_completed;
            s_state_d = CorePublish;
          end
        end
        CorePublish: begin
          if (result_ready_i) begin
            s_state_d = CoreIdle;
          end
        end
        default: s_state_d = CoreIdle;
      endcase

      // Quiesce acknowledge: idle endpoint answers immediately; an active one
      // answers once the terminal result is latched in the result mailbox.
      if (quiesce_req_i) begin
        s_quiesce_ack_d = (s_state_q == CoreIdle) || (s_state_q == CorePublish);
      end else begin
        s_quiesce_ack_d = 1'b0;
      end

      // Epoch restart (link loss, resource reset, coordinated flush): force a
      // safe state; idle is re-acknowledged immediately, an active or
      // terminating job is cancelled and reconciled through the drain.
      if (s_epoch_restart) begin
        s_snap_state_d = SnapIdle;
        if (s_state_q == CoreIdle) begin
          s_epoch_ack_d = epoch_req_i;
        end else begin
          s_state_d = CoreDrainReset;
        end
      end
      // Coordinated fabric flush cancels transport immediately; the epoch
      // restart that follows reconciles the endpoint.
      if (flush_i && (s_state_q != CoreIdle)) begin
        s_state_d = CoreDrainReset;
      end
    end

    assign result_valid_o = (s_state_q == CorePublish);
    assign result_data_o = {s_res_irq_q, s_fault_code_q, s_res_code_q, s_fault_info_q,
                            s_fault_addr_q, s_fault_desc_q, s_res_completed_q, s_job_id_q};
    assign snapshot_resp_data_o = s_snap_payload_q;

    always_ff @(posedge clk_hp_i or negedge rst_hp_n_i) begin
      if (!rst_hp_n_i) begin
        s_state_q <= CoreIdle;
        s_snap_state_q <= SnapIdle;
        s_job_base_q <= '0;
        s_job_id_q <= '0;
        s_timeout_q <= '0;
        s_job_count_q <= '0;
        s_term_job_id_q <= '0;
        s_fault_seen_q <= 1'b0;
        s_fault_code_q <= '0;
        s_fault_addr_q <= '0;
        s_fault_info_q <= '0;
        s_fault_desc_q <= `APB4_NPU__FAULT_DESCRIPTOR_RESET;
        s_res_code_q <= '0;
        s_res_irq_q <= '0;
        s_res_completed_q <= '0;
        s_snap_payload_q <= '0;
        s_all_done_q <= 1'b0;
      end else begin
        s_state_q <= s_state_d;
        s_snap_state_q <= s_snap_state_d;
        s_snap_payload_q <= s_snap_payload_d;
        s_fault_seen_q <= s_fault_seen_d;
        s_fault_code_q <= s_fault_code_d;
        s_fault_addr_q <= s_fault_addr_d;
        s_fault_info_q <= s_fault_info_d;
        s_fault_desc_q <= s_fault_desc_d;
        s_res_code_q <= s_res_code_d;
        s_res_irq_q <= s_res_irq_d;
        s_res_completed_q <= s_res_completed_d;
        if (s_launch_accept) begin
          s_job_base_q <= launch_data_i[`APB4_NPU__LAUNCH_JOB_BASE+:32];
          s_job_id_q <= launch_data_i[`APB4_NPU__LAUNCH_JOB_ID+:32];
          s_timeout_q <= launch_data_i[`APB4_NPU__LAUNCH_TIMEOUT_CYCLES+:32];
          s_job_count_q <= launch_data_i[`APB4_NPU__LAUNCH_JOB_COUNT+:16];
          s_fault_seen_q <= 1'b0;
          s_fault_desc_q <= `APB4_NPU__FAULT_DESCRIPTOR_RESET;
        end
        if (s_compose_terminal) begin
          s_term_job_id_q <= s_job_id_q;
        end
        if ((s_state_q == CoreIdle) || (s_state_q == CorePublish)) begin
          s_all_done_q <= 1'b0;
        end else if (s_dec_all_done) begin
          s_all_done_q <= 1'b1;
        end
        if (s_state_q == CoreIdle) begin
          s_fault_seen_q <= 1'b0;
        end
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

    npu_job_decoder u_job_decoder (
        .clk_hp_i          (clk_hp_i),
        .rst_hp_n_i        (rst_hp_n_i),
        .clear_i           (s_stop),
        .block_new_i       (block_new_i),
        .pause_ok_o        (s_dec_pause_ok),
        .job_start_i       (s_dec_job_start),
        .job_base_i        (launch_data_i[`APB4_NPU__LAUNCH_JOB_BASE+:32]),
        .job_count_i       (launch_data_i[`APB4_NPU__LAUNCH_JOB_COUNT+:16]),
        .read_req_valid_o  (s_dec_read_req_valid),
        .read_req_ready_i  (s_dec_read_req_ready),
        .read_addr_o       (s_dec_read_addr),
        .read_bytes_o      (s_dec_read_bytes),
        .read_data_valid_i (s_dec_read_data_valid),
        .read_data_ready_o (s_dec_read_data_ready),
        .read_data_i       (dma_read_data_i),
        .read_last_i       (dma_read_last_i),
        .dma_read_busy_i   (dma_read_busy_i),
        .dma_fault_i       (dma_fault_i),
        .dma_fault_code_i  (dma_fault_code_i),
        .dma_fault_addr_i  (dma_fault_addr_i),
        .dma_fault_resp_i  (dma_fault_resp_i),
        .rec_valid_o       (s_rec_valid),
        .rec_ready_i       (s_rec_ready),
        .rec_opcode_o      (s_rec_opcode),
        .rec_h_o           (s_rec_h),
        .rec_w_o           (s_rec_w),
        .rec_cin_o         (s_rec_cin),
        .rec_cout_o        (s_rec_cout),
        .rec_oh_o          (s_rec_oh),
        .rec_ow_o          (s_rec_ow),
        .rec_input0_base_o (s_rec_input0_base),
        .rec_output_base_o (s_rec_output_base),
        .rec_weight_base_o (s_rec_weight_base),
        .rec_param_base_o  (s_rec_param_base),
        .rec_input0_row_bytes_o(s_rec_irow),
        .rec_output_row_bytes_o(s_rec_orow),
        .rec_kh_o          (s_rec_kh),
        .rec_kw_o          (s_rec_kw),
        .rec_sh_o          (s_rec_sh),
        .rec_sw_o          (s_rec_sw),
        .rec_pad_top_o     (s_rec_pad_top),
        .rec_pad_left_o    (s_rec_pad_left),
        .rec_input0_zero_o (s_rec_in0_zero),
        .rec_tile_h_o      (s_rec_tile_h),
        .rec_tile_w_o      (s_rec_tile_w),
        .rec_k_slice_o     (s_rec_k_slice),
        .rec_input1_base_o (s_rec_input1_base),
        .rec_input1_row_bytes_o(s_rec_input1_row_bytes),
        .rec_input1_zero_o (s_rec_in1_zero),
        .rec_output_zero_o (s_rec_out_zero),
        .rec_act_min_o     (s_rec_act_min),
        .rec_act_max_o     (s_rec_act_max),
        .rec_weight_bytes_o(s_rec_weight_bytes),
        .rec_param_bytes_o (s_rec_param_bytes),
        .rec_desc_index_o  (s_rec_desc_index),
        .retired_i         (s_dec_retired),
        .all_done_o        (s_dec_all_done),
        .busy_o            (s_dec_busy),
        .cur_desc_index_o  (s_dec_cur_index),
        .progress_o        (s_dec_progress),
        .fault_req_o       (s_dec_fault_req),
        .fault_code_o      (s_dec_fault_code),
        .fault_addr_o      (s_dec_fault_addr),
        .fault_info_o      (s_dec_fault_info),
        .fault_desc_o      (s_dec_fault_desc)
    );

    npu_scheduler u_scheduler (
        .clk_hp_i            (clk_hp_i),
        .rst_hp_n_i          (rst_hp_n_i),
        .clear_i             (s_clear),
        .stop_i              (s_stop),
        .block_new_i         (block_new_i),
        .pause_ok_o          (s_sch_pause_ok),
        .launch_i            (s_sch_launch),
        .timeout_cycles_i    (launch_data_i[`APB4_NPU__LAUNCH_TIMEOUT_CYCLES+:32]),
        .job_active_i        (s_state_q == CoreRun),
        .pause_active_i      (pause_active_o),
        .rec_valid_i         (s_rec_valid),
        .rec_ready_o         (s_rec_ready),
        .rec_opcode_i        (s_rec_opcode),
        .rec_h_i             (s_rec_h),
        .rec_w_i             (s_rec_w),
        .rec_cin_i           (s_rec_cin),
        .rec_cout_i          (s_rec_cout),
        .rec_oh_i            (s_rec_oh),
        .rec_ow_i            (s_rec_ow),
        .rec_input0_base_i   (s_rec_input0_base),
        .rec_output_base_i   (s_rec_output_base),
        .rec_weight_base_i   (s_rec_weight_base),
        .rec_param_base_i    (s_rec_param_base),
        .rec_input0_row_bytes_i(s_rec_irow),
        .rec_output_row_bytes_i(s_rec_orow),
        .rec_kh_i            (s_rec_kh),
        .rec_kw_i            (s_rec_kw),
        .rec_sh_i            (s_rec_sh),
        .rec_sw_i            (s_rec_sw),
        .rec_pad_top_i       (s_rec_pad_top),
        .rec_pad_left_i      (s_rec_pad_left),
        .rec_input0_zero_i   (s_rec_in0_zero),
        .rec_tile_h_i        (s_rec_tile_h),
        .rec_tile_w_i        (s_rec_tile_w),
        .rec_k_slice_i       (s_rec_k_slice),
        .rec_input1_base_i   (s_rec_input1_base),
        .rec_input1_row_bytes_i(s_rec_input1_row_bytes),
        .rec_input1_zero_i   (s_rec_in1_zero),
        .rec_output_zero_i   (s_rec_out_zero),
        .rec_act_min_i       (s_rec_act_min),
        .rec_act_max_i       (s_rec_act_max),
        .rec_weight_bytes_i  (s_rec_weight_bytes),
        .rec_param_bytes_i   (s_rec_param_bytes),
        .rec_desc_index_i    (s_rec_desc_index),
        .retired_o           (s_sch_retired),
        .completed_o         (s_sch_completed),
        .read_req_valid_o    (s_sch_read_req_valid),
        .read_req_ready_i    (s_sch_read_req_ready),
        .read_addr_o         (s_sch_read_addr),
        .read_bytes_o        (s_sch_read_bytes),
        .read_data_valid_i   (s_sch_read_data_valid),
        .read_data_ready_o   (s_sch_read_data_ready),
        .read_data_i         (dma_read_data_i),
        .read_keep_i         (dma_read_keep_i),
        .read_last_i         (dma_read_last_i),
        .write_req_valid_o   (s_sch_write_req_valid),
        .write_req_ready_i   (dma_write_req_ready_i),
        .write_addr_o        (s_sch_write_addr),
        .write_bytes_o       (s_sch_write_bytes),
        .write_data_valid_o  (s_sch_write_data_valid),
        .write_data_ready_i  (dma_write_data_ready_i),
        .write_data_o        (s_sch_write_data),
        .write_keep_o        (s_sch_write_keep),
        .write_last_o        (s_sch_write_last),
        .write_done_i        (dma_write_done_i),
        .dma_read_busy_i     (dma_read_busy_i),
        .dma_write_busy_i    (dma_write_busy_i),
        .dma_pause_ack_i     (dma_pause_ack_i),
        .dma_fault_i         (dma_fault_i),
        .dma_fault_code_i    (dma_fault_code_i),
        .dma_fault_addr_i    (dma_fault_addr_i),
        .dma_fault_resp_i    (dma_fault_resp_i),
        .dma_read_bytes_i    (dma_read_bytes_i),
        .dma_write_bytes_i   (dma_write_bytes_i),
        .dma_stall_cycles_i  (dma_stall_cycles_i),
        .progress_i          (s_dec_progress),
        .terminal_i          (s_sch_terminal),
        .counters_o          (s_sch_counters),
        .term_counters_o     (s_sch_term_counters),
        .fault_req_o         (s_sch_fault_req),
        .fault_code_o        (s_sch_fault_code),
        .fault_addr_o        (s_sch_fault_addr),
        .fault_info_o        (s_sch_fault_info),
        .fault_desc_o        (s_sch_fault_desc),
        .busy_o              (s_sch_busy),
        .drained_o           (s_sch_drained)
    );
  end
endmodule
