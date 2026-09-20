// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// NPU Phase 2 PCLK register shell: the complete APB4 register ABI, the launch
// slot, the result/IRQ mirror, and the PERF snapshot bank. Phase 2 compiles in
// no executable implementation: STATUS.READY is always 0, CONTROL.START always
// completes with PSLVERR and no side effect, and hardware terminal events
// never occur (only IRQ_TEST sets IRQ_STATE bits). The launch slot and result
// mirror logic exists and participates in the lifecycle protocol so the
// Phase 3 execution path drops in without a shell redesign.
`include "npu_define.svh"

module npu_reg #(
    parameter int unsigned LaunchPayloadWidth   = `APB4_NPU__LAUNCH_PAYLOAD_WIDTH,
    parameter int unsigned ResultPayloadWidth   = `APB4_NPU__RESULT_PAYLOAD_WIDTH,
    parameter int unsigned SnapshotPayloadWidth = `APB4_NPU__SNAPSHOT_PAYLOAD_WIDTH
) (
    // verilog_format: off -- preserve the APB, lifecycle, and mailbox boundary columns
    input  logic                            clk_i,
    input  logic                            rst_n_i,
    apb4_if.slave                           apb4,
    input  logic [1:0]                      resource_owner_i,
    input  logic                            resource_owner_lock_i,
    input  logic                            resource_quiesce_i,
    input  logic                            resource_reset_i,
    input  logic                            hp_busy_i,
    input  logic                            hp_draining_i,
    input  logic                            clock_paused_i,
    input  logic                            link_up_i,
    input  logic                            flush_active_i,
    input  logic [31:0]                     recovery_generation_i,
    output logic                            launch_req_valid_o,
    input  logic                            launch_req_ready_i,
    output logic [LaunchPayloadWidth-1:0]   launch_req_payload_o,
    input  logic                            result_valid_i,
    output logic                            result_ready_o,
    input  logic [ResultPayloadWidth-1:0]   result_payload_i,
    output logic                            snapshot_req_valid_o,
    input  logic                            snapshot_req_ready_i,
    input  logic                            snapshot_resp_valid_i,
    output logic                            snapshot_resp_ready_o,
    input  logic [SnapshotPayloadWidth-1:0] snapshot_resp_payload_i,
    output logic                            abort_o,
    output logic                            soft_reset_o,
    output logic                            idle_o,
    output logic                            irq_o
    // verilog_format: on
);
  // Phase 4 truthfulness: the complete MVP operator pipeline is compiled in
  // and the full supported operator mask passed its differential evidence, so
  // READY/START are enabled (still gated by the live status rules below).
  localparam logic ExecutionReady = 1'b1;
  localparam int unsigned CounterBankWidth = 8 * `APB4_NPU__PERF_COUNTER_COUNT * 8;

  logic s_apb4_ready_d, s_apb4_ready_q;
  logic s_access_seen_d, s_access_seen_q;
  logic [31:0] s_apb4_rdata_d, s_apb4_rdata_q;
  logic s_apb4_resp_err_d, s_apb4_resp_err_q;
  logic [2:0] s_irq_state_d, s_irq_state_q;
  logic [2:0] s_irq_en_d, s_irq_en_q;
  logic [31:0] s_job_base_d, s_job_base_q;
  logic [15:0] s_job_count_d, s_job_count_q;
  logic [31:0] s_job_id_d, s_job_id_q;
  logic [31:0] s_timeout_d, s_timeout_q;
  logic s_launch_busy_d, s_launch_busy_q;
  logic s_launch_req_valid_d, s_launch_req_valid_q;
  logic s_result_valid_d, s_result_valid_q;
  logic [31:0] s_result_job_id_d, s_result_job_id_q;
  logic [2:0] s_result_code_d, s_result_code_q;
  logic [31:0] s_completed_d, s_completed_q;
  logic [31:0] s_fault_desc_d, s_fault_desc_q;
  logic [3:0] s_fault_code_d, s_fault_code_q;
  logic [31:0] s_fault_addr_d, s_fault_addr_q;
  logic [31:0] s_fault_info_d, s_fault_info_q;
  logic s_snap_req_valid_d, s_snap_req_valid_q;
  logic s_snap_busy_d, s_snap_busy_q;
  logic s_snap_valid_d, s_snap_valid_q;
  logic [CounterBankWidth-1:0] s_perf_bank_d, s_perf_bank_q;
  logic [31:0] s_perf_job_id_d, s_perf_job_id_q;
  logic [31:0] s_perf_generation_d, s_perf_generation_q;
  logic        s_req_accept;
  logic        s_write;
  logic [11:0] s_offset;
  logic [31:0] s_write_value;
  logic [31:0] s_read_data;
  logic        s_read_valid;
  logic        s_read_err;
  logic        s_write_err;
  logic        s_perf_range;
  logic [ 5:0] s_perf_word;
  logic [ 9:0] s_perf_bit;
  logic [ 2:0] s_irq_clear;
  logic [ 2:0] s_irq_test;
  logic [ 2:0] s_result_irq_events;
  logic        s_cmd_start;
  logic        s_cmd_abort;
  logic        s_cmd_soft_reset;
  logic        s_cmd_snapshot;
  logic        s_result_accept;
  logic        s_snap_resp_accept;
  logic        s_ready;
  logic        s_shell_busy;

`ifndef SYNTHESIS
  initial begin
    if ((LaunchPayloadWidth != 128) || (ResultPayloadWidth != 170) ||
        (SnapshotPayloadWidth != CounterBankWidth + 32)) begin
      $fatal(1, "npu_reg: payload widths must match the npu_define.svh layouts");
    end
  end
`endif

  assign s_req_accept = apb4.psel && apb4.penable && !s_access_seen_q;
  assign s_write = s_req_accept && apb4.pwrite;
  assign s_offset = apb4.paddr[11:0];
  assign s_write_value = apb4.pwdata;

  assign apb4.pready = s_apb4_ready_q;
  assign apb4.prdata = s_apb4_rdata_q;
  assign apb4.pslverr = s_apb4_resp_err_q;

  assign s_shell_busy = s_launch_busy_q || hp_busy_i;
  // READY also requires a reconciled link, no resource/reset/pause request, no
  // pending terminal IRQ, and no active snapshot handshake; at Phase 2 the
  // missing executable implementation keeps it permanently low.
  assign s_ready = ExecutionReady && link_up_i && !s_launch_busy_q && !hp_busy_i &&
                   !hp_draining_i && !resource_quiesce_i && !resource_reset_i &&
                   !clock_paused_i && (s_irq_state_q == 3'd0) && !s_snap_busy_q &&
                   !s_snap_req_valid_q;

  assign launch_req_valid_o = s_launch_req_valid_q;
  assign launch_req_payload_o = {16'd0, s_job_count_q, s_timeout_q, s_job_id_q, s_job_base_q};
  assign result_ready_o = 1'b1;
  assign s_result_accept = result_valid_i && result_ready_o;
  assign s_result_irq_events  = s_result_accept ?
      result_payload_i[`APB4_NPU__RESULT_PAYLOAD_IRQ_EVENTS+:3] : 3'd0;
  assign snapshot_req_valid_o = s_snap_req_valid_q;
  assign snapshot_resp_ready_o = s_snap_busy_q;
  assign s_snap_resp_accept = snapshot_resp_valid_i && snapshot_resp_ready_o;
  assign abort_o = s_cmd_abort;
  assign soft_reset_o = s_cmd_soft_reset;
  assign idle_o = !s_launch_busy_q && !s_launch_req_valid_q && !s_snap_busy_q &&
                  !s_snap_req_valid_q;
  assign irq_o = (s_irq_state_q & s_irq_en_q) != 3'd0;

  always_comb begin
    s_perf_range = (s_offset >= `APB4_NPU__PERF_ACTIVE_CYCLES_LO) &&
                   (s_offset <= `APB4_NPU__PERF_RETIRED_DESCRIPTORS_HI) &&
                   (s_offset[1:0] == 2'b00);
    s_perf_word = s_offset[7:2] - 6'h20;
    s_perf_bit = {s_perf_word[4:0], 5'b00000};
  end

  always_comb begin
    s_read_data  = 32'd0;
    s_read_valid = 1'b1;
    if (s_perf_range) begin
      s_read_data = s_perf_bank_q[s_perf_bit+:32];
    end else begin
      unique case (s_offset)
        `APB4_NPU__IP_ID: s_read_data = `APB4_NPU__IP_ID_VALUE;
        `APB4_NPU__IP_VERSION: s_read_data = `APB4_NPU__IP_VERSION_VALUE;
        `APB4_NPU__CAPABILITY: s_read_data = `APB4_NPU__CAPABILITY_P4;
        `APB4_NPU__STATUS:
        s_read_data = {
          26'd0, s_result_valid_q, !link_up_i, clock_paused_i, hp_draining_i, s_shell_busy, s_ready
        };
        `APB4_NPU__IRQ_STATE: s_read_data = {29'd0, s_irq_state_q};
        `APB4_NPU__IRQ_ENABLE: s_read_data = {29'd0, s_irq_en_q};
        `APB4_NPU__JOB_BASE: s_read_data = s_job_base_q;
        `APB4_NPU__JOB_COUNT: s_read_data = {16'd0, s_job_count_q};
        `APB4_NPU__JOB_ID: s_read_data = s_job_id_q;
        `APB4_NPU__TIMEOUT_CYCLES: s_read_data = s_timeout_q;
        `APB4_NPU__RESULT_JOB_ID: s_read_data = s_result_job_id_q;
        `APB4_NPU__RESULT_CODE: s_read_data = {29'd0, s_result_code_q};
        `APB4_NPU__COMPLETED_DESCRIPTORS: s_read_data = s_completed_q;
        `APB4_NPU__FAULT_DESCRIPTOR: s_read_data = s_fault_desc_q;
        `APB4_NPU__FAULT_CODE: s_read_data = {28'd0, s_fault_code_q};
        `APB4_NPU__FAULT_ADDRESS: s_read_data = s_fault_addr_q;
        `APB4_NPU__FAULT_INFO: s_read_data = s_fault_info_q;
        `APB4_NPU__NUMERIC_PROFILE: s_read_data = `APB4_NPU__NUMERIC_PROFILE_VALUE;
        // Phase 2 advertises no instantiated storage, compute, or operators.
        `APB4_NPU__LOCAL_BYTES: s_read_data = `APB4_NPU__LOCAL_BYTES_VALUE;
        `APB4_NPU__MAC_CONFIG: s_read_data = `APB4_NPU__MAC_CONFIG_VALUE;
        `APB4_NPU__MAX_K_SLICE: s_read_data = `APB4_NPU__MAX_K_SLICE_VALUE;
        `APB4_NPU__MAX_DIMENSION: s_read_data = `APB4_NPU__MAX_DIMENSION_VALUE;
        `APB4_NPU__OP_CAPABILITY: s_read_data = `APB4_NPU__OP_CAPABILITY_VALUE;
        `APB4_NPU__OWNER_STATUS:
        s_read_data = {
          21'd0, resource_reset_i, resource_quiesce_i, resource_owner_lock_i, 6'd0, resource_owner_i
        };
        `APB4_NPU__RECOVERY_GENERATION: s_read_data = recovery_generation_i;
        `APB4_NPU__PERF_STATUS: s_read_data = {30'd0, s_snap_valid_q, s_snap_busy_q};
        `APB4_NPU__PERF_JOB_ID: s_read_data = s_perf_job_id_q;
        `APB4_NPU__PERF_GENERATION: s_read_data = s_perf_generation_q;
        `APB4_NPU__DESCRIPTOR_BYTES: s_read_data = `APB4_NPU__DESCRIPTOR_BYTES_VALUE;
        `APB4_NPU__CONTROL, `APB4_NPU__IRQ_TEST, `APB4_NPU__PERF_CONTROL: begin
          s_read_valid = 1'b0;
        end
        default: s_read_valid = 1'b0;
      endcase
    end
  end

  always_comb begin
    s_read_err = (s_offset[1:0] != 2'b00) || !s_read_valid;
  end

  always_comb begin
    s_write_err      = 1'b0;
    s_irq_clear      = 3'd0;
    s_irq_test       = 3'd0;
    s_cmd_start      = 1'b0;
    s_cmd_abort      = 1'b0;
    s_cmd_soft_reset = 1'b0;
    s_cmd_snapshot   = 1'b0;
    if (s_write) begin
      if ((s_offset[1:0] != 2'b00) || (apb4.pstrb != 4'hf)) begin
        s_write_err = 1'b1;
      end else begin
        unique case (s_offset)
          `APB4_NPU__CONTROL: begin
            unique case (s_write_value)
              32'h0000_0001: begin
                // An unavailable START is a local APB error, not a job fault.
                if (!s_ready) begin
                  s_write_err = 1'b1;
                end else begin
                  s_cmd_start = 1'b1;
                end
              end
              32'h0000_0002: begin
                // ABORT on an idle NPU is a successful no-op.
                if (s_shell_busy) begin
                  s_cmd_abort = 1'b1;
                end
              end
              32'h0000_0004: begin
                if (s_shell_busy || hp_draining_i || s_snap_busy_q || s_snap_req_valid_q) begin
                  s_write_err = 1'b1;
                end else begin
                  s_cmd_soft_reset = 1'b1;
                end
              end
              default: s_write_err = 1'b1;
            endcase
          end
          `APB4_NPU__IRQ_STATE: begin
            if (s_write_value[31:3] != 29'd0) begin
              s_write_err = 1'b1;
            end else begin
              s_irq_clear = s_write_value[2:0];
            end
          end
          `APB4_NPU__IRQ_ENABLE: begin
            if (s_write_value[31:3] != 29'd0) begin
              s_write_err = 1'b1;
            end
          end
          `APB4_NPU__IRQ_TEST: begin
            if (s_write_value[31:3] != 29'd0) begin
              s_write_err = 1'b1;
            end else begin
              s_irq_test = s_write_value[2:0];
            end
          end
          `APB4_NPU__JOB_BASE: begin
            if (s_shell_busy) begin
              s_write_err = 1'b1;
            end
          end
          `APB4_NPU__JOB_COUNT: begin
            if (s_shell_busy || (s_write_value[31:16] != 16'd0)) begin
              s_write_err = 1'b1;
            end
          end
          `APB4_NPU__JOB_ID: begin
            if (s_shell_busy) begin
              s_write_err = 1'b1;
            end
          end
          `APB4_NPU__TIMEOUT_CYCLES: begin
            if (s_shell_busy || (s_write_value == 32'd0)) begin
              s_write_err = 1'b1;
            end
          end
          `APB4_NPU__PERF_CONTROL: begin
            if ((s_write_value != 32'h0000_0001) || s_snap_busy_q || s_snap_req_valid_q ||
                !link_up_i || resource_quiesce_i || resource_reset_i) begin
              s_write_err = 1'b1;
            end else begin
              s_cmd_snapshot = 1'b1;
            end
          end
          default: s_write_err = 1'b1;
        endcase
      end
    end
  end

  always_comb begin
    s_apb4_ready_d  = s_req_accept;
    s_access_seen_d = s_access_seen_q;
    if (!apb4.psel || !apb4.penable) begin
      s_access_seen_d = 1'b0;
    end else if (s_req_accept) begin
      s_access_seen_d = 1'b1;
    end
    s_apb4_rdata_d    = s_apb4_rdata_q;
    s_apb4_resp_err_d = s_req_accept && (s_write ? s_write_err : s_read_err);
    if (s_req_accept) begin
      s_apb4_rdata_d = (!s_write && !s_read_err) ? s_read_data : 32'd0;
    end

    // Hardware/test set wins a same-cycle W1C clear; reads never clear.
    s_irq_state_d        = (s_irq_state_q & ~s_irq_clear) | s_irq_test | s_result_irq_events;
    s_irq_en_d           = s_irq_en_q;
    s_job_base_d         = s_job_base_q;
    s_job_count_d        = s_job_count_q;
    s_job_id_d           = s_job_id_q;
    s_timeout_d          = s_timeout_q;

    s_launch_busy_d      = s_launch_busy_q;
    s_launch_req_valid_d = s_launch_req_valid_q;
    // An accepted START latches the launch slot and raises the mailbox
    // request; the slot releases only on terminal result or epoch recovery.
    // RESULT_VALID clears here on acceptance (not on IRQ W1C), so a stale
    // terminal record can never be mistaken for the new job's completion.
    if (s_cmd_start) begin
      s_launch_busy_d      = 1'b1;
      s_launch_req_valid_d = 1'b1;
      s_result_valid_d     = 1'b0;
    end
    if (s_launch_req_valid_q && launch_req_ready_i) begin
      s_launch_req_valid_d = 1'b0;
    end

    s_result_valid_d  = s_result_valid_q && !s_cmd_start;
    s_result_job_id_d = s_result_job_id_q;
    s_result_code_d   = s_result_code_q;
    s_completed_d     = s_completed_q;
    s_fault_desc_d    = s_fault_desc_q;
    s_fault_code_d    = s_fault_code_q;
    s_fault_addr_d    = s_fault_addr_q;
    s_fault_info_d    = s_fault_info_q;
    // Terminal result mirror; no result source exists at Phase 2.
    if (s_result_accept) begin
      s_launch_busy_d   = 1'b0;
      s_result_valid_d  = 1'b1;
      s_result_job_id_d = result_payload_i[`APB4_NPU__RESULT_PAYLOAD_JOB_ID+:32];
      s_result_code_d   = result_payload_i[`APB4_NPU__RESULT_PAYLOAD_CODE+:3];
      s_completed_d     = result_payload_i[`APB4_NPU__RESULT_PAYLOAD_COMPLETED+:32];
      s_fault_desc_d    = result_payload_i[`APB4_NPU__RESULT_PAYLOAD_FAULT_DESC+:32];
      s_fault_code_d    = result_payload_i[`APB4_NPU__RESULT_PAYLOAD_FAULT_CODE+:4];
      s_fault_addr_d    = result_payload_i[`APB4_NPU__RESULT_PAYLOAD_FAULT_ADDR+:32];
      s_fault_info_d    = result_payload_i[`APB4_NPU__RESULT_PAYLOAD_FAULT_INFO+:32];
    end

    s_snap_req_valid_d  = s_snap_req_valid_q;
    s_snap_busy_d       = s_snap_busy_q;
    s_snap_valid_d      = s_snap_valid_q;
    s_perf_bank_d       = s_perf_bank_q;
    s_perf_job_id_d     = s_perf_job_id_q;
    s_perf_generation_d = s_perf_generation_q;
    if (s_cmd_snapshot) begin
      s_snap_req_valid_d = 1'b1;
      s_snap_busy_d      = 1'b1;
      s_snap_valid_d     = 1'b0;
    end
    if (s_snap_req_valid_q && snapshot_req_ready_i) begin
      s_snap_req_valid_d = 1'b0;
    end
    // Capture completion replaces the whole bank and job/generation together,
    // so a low/high counter tear can never be observed.
    if (s_snap_resp_accept) begin
      s_perf_bank_d       = snapshot_resp_payload_i[SnapshotPayloadWidth-1:32];
      s_perf_job_id_d     = snapshot_resp_payload_i[31:0];
      s_perf_generation_d = recovery_generation_i;
      s_snap_busy_d       = 1'b0;
      s_snap_valid_d      = 1'b1;
    end

    // Epoch recovery releases the launch slot and cancels a pending capture.
    if (flush_active_i) begin
      s_launch_busy_d      = 1'b0;
      s_launch_req_valid_d = 1'b0;
      s_snap_req_valid_d   = 1'b0;
      s_snap_busy_d        = 1'b0;
      s_snap_valid_d       = 1'b0;
    end

    if (s_write && !s_write_err) begin
      unique case (s_offset)
        `APB4_NPU__IRQ_ENABLE:     s_irq_en_d = s_write_value[2:0];
        `APB4_NPU__JOB_BASE:       s_job_base_d = s_write_value;
        `APB4_NPU__JOB_COUNT:      s_job_count_d = s_write_value[15:0];
        `APB4_NPU__JOB_ID:         s_job_id_d = s_write_value;
        `APB4_NPU__TIMEOUT_CYCLES: s_timeout_d = s_write_value;
        default: begin
        end
      endcase
    end

    // Idle SOFT_RESET clears programmable, IRQ, and result state; the CDC
    // reconciliation it triggers runs before READY could return.
    if (s_cmd_soft_reset) begin
      s_irq_state_d        = 3'd0;
      s_irq_en_d           = 3'd0;
      s_job_base_d         = 32'd0;
      s_job_count_d        = 16'd0;
      s_job_id_d           = 32'd0;
      s_timeout_d          = 32'd0;
      s_launch_busy_d      = 1'b0;
      s_launch_req_valid_d = 1'b0;
      s_result_valid_d     = 1'b0;
      s_result_job_id_d    = 32'd0;
      s_result_code_d      = 3'd0;
      s_completed_d        = 32'd0;
      s_fault_desc_d       = `APB4_NPU__FAULT_DESCRIPTOR_RESET;
      s_fault_code_d       = 4'd0;
      s_fault_addr_d       = 32'd0;
      s_fault_info_d       = 32'd0;
      s_snap_req_valid_d   = 1'b0;
      s_snap_busy_d        = 1'b0;
      s_snap_valid_d       = 1'b0;
      s_perf_bank_d        = '0;
      s_perf_job_id_d      = 32'd0;
      s_perf_generation_d  = 32'd0;
    end
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_apb4_ready (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_ready_d),
      .dat_o  (s_apb4_ready_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_access_seen (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_access_seen_d),
      .dat_o  (s_access_seen_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_apb4_rdata (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_rdata_d),
      .dat_o  (s_apb4_rdata_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_apb4_resp_err (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_resp_err_d),
      .dat_o  (s_apb4_resp_err_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_irq_state (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_irq_state_d),
      .dat_o  (s_irq_state_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_irq_enable (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_irq_en_d),
      .dat_o  (s_irq_en_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_job_base (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_job_base_d),
      .dat_o  (s_job_base_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_job_count (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_job_count_d),
      .dat_o  (s_job_count_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_job_id (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_job_id_d),
      .dat_o  (s_job_id_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_timeout (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timeout_d),
      .dat_o  (s_timeout_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_launch_busy (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_launch_busy_d),
      .dat_o  (s_launch_busy_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_launch_req_valid (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_launch_req_valid_d),
      .dat_o  (s_launch_req_valid_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_result_valid (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_result_valid_d),
      .dat_o  (s_result_valid_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_result_job_id (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_result_job_id_d),
      .dat_o  (s_result_job_id_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_result_code (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_result_code_d),
      .dat_o  (s_result_code_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_completed (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_completed_d),
      .dat_o  (s_completed_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (`APB4_NPU__FAULT_DESCRIPTOR_RESET)
  ) u_fault_desc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_desc_d),
      .dat_o  (s_fault_desc_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_fault_code (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_code_d),
      .dat_o  (s_fault_code_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_fault_addr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_addr_d),
      .dat_o  (s_fault_addr_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_fault_info (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_info_d),
      .dat_o  (s_fault_info_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_snap_req_valid (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_snap_req_valid_d),
      .dat_o  (s_snap_req_valid_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_snap_busy (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_snap_busy_d),
      .dat_o  (s_snap_busy_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_snap_valid (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_snap_valid_d),
      .dat_o  (s_snap_valid_q)
  );
  dffr #(
      .DATA_WIDTH(CounterBankWidth)
  ) u_perf_bank (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_bank_d),
      .dat_o  (s_perf_bank_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_job_id (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_job_id_d),
      .dat_o  (s_perf_job_id_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_generation (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_generation_d),
      .dat_o  (s_perf_generation_q)
  );

`ifndef SV_ASSRT_DISABLE
  logic s_apb_setup_q;
  logic s_apb_wait_q;
  logic s_launch_wait_q;
  logic s_snap_req_wait_q;
  logic s_req_cancel_q;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_apb_setup_q     <= 1'b0;
      s_apb_wait_q      <= 1'b0;
      s_launch_wait_q   <= 1'b0;
      s_snap_req_wait_q <= 1'b0;
      s_req_cancel_q    <= 1'b0;
    end else begin
      s_apb_setup_q     <= apb4.psel && !apb4.penable;
      s_apb_wait_q      <= apb4.psel && apb4.penable && !apb4.pready;
      s_launch_wait_q   <= launch_req_valid_o && !launch_req_ready_i;
      s_snap_req_wait_q <= snapshot_req_valid_o && !snapshot_req_ready_i;
      s_req_cancel_q    <= flush_active_i || s_cmd_soft_reset;
      // APB payload is stable from setup through every wait state.
      if (s_apb_setup_q || s_apb_wait_q) begin
        assert (apb4.psel && $stable(
            apb4.paddr
        ) && $stable(
            apb4.pwrite
        ) && $stable(
            apb4.pwdata
        ) && $stable(
            apb4.pstrb
        ));
        assert (s_apb_setup_q || apb4.penable);
      end
      // START can never be accepted without READY (never, at Phase 2).
      if (s_cmd_start) begin
        assert (s_ready);
      end
      // irq_o is exactly the enabled pending events.
      assert (irq_o == ((s_irq_state_q & s_irq_en_q) != 3'd0));
      // Mailbox requests hold valid and payload until accepted; only an epoch
      // flush or a soft reset may withdraw them.
      if (s_launch_wait_q) begin
        assert ((launch_req_valid_o && $stable(launch_req_payload_o)) || s_req_cancel_q);
      end
      if (s_snap_req_wait_q) begin
        assert (snapshot_req_valid_o || s_req_cancel_q);
      end
    end
  end
`endif
endmodule
