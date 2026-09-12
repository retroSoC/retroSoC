// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_codec_controller #(
    parameter bit EnableP7 = 1'b0
) (
    // verilog_format: off -- preserve direct, ring, sequencer, and result columns
    input  logic                   clk_i,
    input  logic                   rst_n_i,
    input  logic                   soft_reset_i,
    input  logic                   resource_reset_request_i,
    input  logic                   resource_reset_apply_i,
    input  logic                   abort_i,
    input  logic                   quiesce_i,
    input  logic                   block_new_i,
    input  logic                   ring_enabled_i,
    input  logic [31:0]            ring_base_i,
    input  logic [31:0]            read_base_i,
    input  logic [31:0]            read_limit_i,
    input  logic [31:0]            write_base_i,
    input  logic [31:0]            write_limit_i,
    input  logic                   direct_start_i,
    input  logic [1023:0]          direct_descriptor_i,
    output logic                   direct_allowed_o,
    input  logic                   ring_job_valid_i,
    output logic                   ring_job_ready_o,
    input  logic [1023:0]          ring_descriptor_i,
    input  logic [7:0]             ring_index_i,
    output logic                   ring_result_valid_o,
    input  logic                   ring_result_ready_i,
    output logic                   ring_result_error_o,
    output logic [5:0]             ring_result_code_o,
    output logic [3:0]             ring_result_stage_o,
    output logic [1:0]             ring_result_resp_o,
    output logic [31:0]            ring_result_input_used_o,
    output logic [31:0]            ring_result_output_bytes_o,
    output logic [31:0]            ring_result_frames_o,
    output logic [31:0]            ring_result_source_info_o,
    output logic [31:0]            ring_result_cycles_o,
    output logic [31:0]            ring_result_detail_o,
    output logic [31:0]            ring_result_kws_o,
    input  logic                   microcode_valid_i,
    input  logic                   microcode_lock_i,
    input  logic                   kws_model_valid_i,
    input  logic                   kws_model_lock_i,
    input  logic                   kws_memory_armed_i,
    input  logic [2:0][16:0]       entry_scratch_base_i,
    input  logic [2:0][16:0]       entry_scratch_bytes_i,
    output logic                   sequencer_launch_o,
    output logic [1:0]             sequencer_entry_o,
    input  logic                   sequencer_idle_i,
    input  logic                   sequencer_end_i,
    input  logic                   sequencer_trap_i,
    input  logic [5:0]             sequencer_fault_code_i,
    input  logic [3:0]             sequencer_fault_stage_i,
    input  logic [1:0]             sequencer_fault_resp_i,
    input  logic [31:0]            sequencer_fault_detail_i,
    output logic                   transport_job_start_o,
    output logic                   transport_job_finish_o,
    output logic                   transport_cancel_o,
    output logic [1023:0]          active_descriptor_o,
    output logic [16:0]            active_scratch_base_o,
    output logic [16:0]            active_scratch_bytes_o,
    output logic [7:0]             active_index_o,
    input  logic                   transport_context_ready_i,
    input  logic                   transport_job_done_i,
    input  logic                   transport_frame_commit_i,
    input  logic [31:0]            transport_input_used_i,
    input  logic [31:0]            transport_output_bytes_i,
    input  logic [31:0]            transport_frames_i,
    input  logic [31:0]            transport_source_info_i,
    input  logic [31:0]            transport_cycles_i,
    input  logic [31:0]            transport_detail_i,
    input  logic [31:0]            transport_diagnostic_offset_i,
    input  logic [5:0]             transport_result_code_i,
    input  logic [3:0]             transport_result_stage_i,
    input  logic [1:0]             transport_result_resp_i,
    output logic                   kws_start_o,
    input  logic                   kws_start_ready_i,
    output logic                   kws_config_valid_o,
    output logic [15:0]            kws_config_o,
    input  logic                   kws_done_i,
    input  logic                   kws_error_i,
    input  logic [5:0]             kws_error_code_i,
    input  logic [3:0]             kws_error_stage_i,
    input  logic [1:0]             kws_error_resp_i,
    input  logic [31:0]            kws_error_address_i,
    input  logic [31:0]            kws_error_detail_i,
    input  logic [31:0]             kws_input_used_i,
    input  logic [31:0]             kws_result_i,
    output logic [31:0]            job_status_o,
    output logic [31:0]            job_input_used_o,
    output logic [31:0]            job_output_bytes_o,
    output logic [31:0]            job_frames_o,
    output logic [31:0]            job_source_info_o,
    output logic [31:0]            job_cycles_o,
    output logic [31:0]            job_detail_o,
    output logic                   direct_done_o,
    output logic                   fault_valid_o,
    output logic [5:0]             fault_code_o,
    output logic [3:0]             fault_stage_o,
    output logic [1:0]             fault_resp_o,
    output logic [7:0]             fault_index_o,
    output logic [31:0]            fault_addr_o,
    output logic [31:0]            fault_detail_o,
    output logic                   busy_o,
    output logic                   ring_job_o,
    output logic                   idle_o
    // verilog_format: on
);
  typedef enum logic [3:0] {
    Idle,
    StartTransport,
    WaitContext,
    Running,
    FinishTransport,
    CancelTransport,
    RingResult,
    KwsStart,
    KwsWait
  } state_e;

  state_e          s_state_q;
  logic   [1023:0] s_descriptor_q;
  logic   [   7:0] s_index_q;
  logic   [   1:0] s_entry_q;
  logic            s_ring_q;
  logic s_terminal_err_q, s_terminal_aborted_q;
  logic [ 5:0] s_terminal_code_q;
  logic [ 3:0] s_terminal_stage_q;
  logic [ 1:0] s_terminal_resp_q;
  logic [31:0] s_terminal_detail_q;
  logic        s_transport_done_q;
  logic [31:0] s_job_stat_q, s_job_input_q, s_job_output_q;
  logic [31:0] s_job_frames_q, s_job_source_q, s_job_cycles_q, s_job_detail_q;
  logic [31:0] s_job_kws_q;
  logic [31:0] s_kws_cycles_q;
  logic s_direct_valid, s_ring_valid;
  logic [5:0] s_direct_reject_code, s_ring_reject_code;
  logic [3:0] s_direct_reject_stage, s_ring_reject_stage;
  logic [31:0] s_direct_reject_detail, s_ring_reject_detail;
  logic [16:0] s_direct_scratch_bytes, s_ring_scratch_bytes;
  logic [42:0] s_direct_check, s_ring_check;
  logic [32:0] s_ring_descriptor_base, s_ring_descriptor_last;
  logic s_ring_descriptor_acl_valid;
  logic s_direct_kws_allowed, s_ring_kws_allowed;

  function automatic logic [42:0] descriptor_check(
      input logic [31:0] control_i, input logic [255:0] job_fields_i,
      input logic [255:0] reserved_i, input logic ring_i, input logic [31:0] read_base_value_i,
      input logic [31:0] read_limit_value_i, input logic [31:0] write_base_value_i,
      input logic [31:0] write_limit_value_i);
    logic [31:0] s_control, s_input_addr, s_input_bytes, s_output_addr, s_output_capacity;
    logic [31:0] s_input_cfg, s_output_cfg, s_flags, s_kws;
    logic [31:0] s_control_payload;
    logic [32:0] s_input_end, s_input_last, s_output_end, s_output_last;
    logic [31:0] detail_o;
    logic [ 5:0] code_o;
    logic [ 3:0] stage_o;
    logic [ 4:0] s_reserved_word_index;
    logic s_memory_output, valid_o;
    begin
      s_control = control_i;
      s_input_addr = job_fields_i[(0*32)+:32];
      s_input_bytes = job_fields_i[(1*32)+:32];
      s_output_addr = job_fields_i[(2*32)+:32];
      s_output_capacity = job_fields_i[(3*32)+:32];
      s_input_cfg = job_fields_i[(4*32)+:32];
      s_output_cfg = job_fields_i[(5*32)+:32];
      s_flags = job_fields_i[(6*32)+:32];
      s_kws = job_fields_i[(7*32)+:32];
      s_control_payload = ring_i ? {2'd0, s_control[29:0]} : s_control;
      s_input_end = {1'b0, s_input_addr} + {1'b0, s_input_bytes};
      s_input_last = s_input_end - 1'b1;
      s_output_end = {1'b0, s_output_addr} + {1'b0, s_output_capacity};
      s_output_last = s_output_end - 1'b1;
      s_memory_output = s_control[9:8] == 2'd0;
      code_o = ring_i ? `APB4_APU__ERROR_CODE_INVALID_RING : `APB4_APU__ERROR_CODE_INVALID_CONFIG;
      stage_o = `APB4_APU__ERROR_STAGE_RING;
      detail_o = 32'h0000_0001;
      valid_o = 1'b0;
      s_reserved_word_index = 5'd24;
      if (reserved_i[31:0] != 32'd0) begin
        s_reserved_word_index = 5'd24;
      end else if (reserved_i[63:32] != 32'd0) begin
        s_reserved_word_index = 5'd25;
      end else if (reserved_i[95:64] != 32'd0) begin
        s_reserved_word_index = 5'd26;
      end else if (reserved_i[127:96] != 32'd0) begin
        s_reserved_word_index = 5'd27;
      end else if (reserved_i[159:128] != 32'd0) begin
        s_reserved_word_index = 5'd28;
      end else if (reserved_i[191:160] != 32'd0) begin
        s_reserved_word_index = 5'd29;
      end else if (reserved_i[223:192] != 32'd0) begin
        s_reserved_word_index = 5'd30;
      end else if (reserved_i[255:224] != 32'd0) begin
        s_reserved_word_index = 5'd31;
      end
      if (EnableP7 && (s_control[3:0] == 4'd1)) begin
        code_o = ring_i ? `APB4_APU__ERROR_CODE_INVALID_RING : `APB4_APU__ERROR_CODE_INVALID_CONFIG;
        detail_o = 32'h0700_0200;
        if (s_control_payload != 32'd1) begin
          detail_o = 32'h0700_0200;
        end else if ((s_input_addr[1:0] != 2'd0) ||
                     (s_input_addr < read_base_value_i) ||
                     (s_input_addr > read_limit_value_i)) begin
          detail_o = 32'h0700_0202;
        end else if ((s_input_bytes != 32'd32000) || s_input_end[32] ||
                     (s_input_last[31:0] > read_limit_value_i)) begin
          detail_o = 32'h0700_0203;
        end else if (s_output_addr != 32'd0) begin
          detail_o = 32'h0700_0204;
        end else if (s_output_capacity != 32'd0) begin
          detail_o = 32'h0700_0205;
        end else if (s_input_cfg != 32'h0102_3e80) begin
          detail_o = 32'h0700_0206;
        end else if (s_output_cfg != 32'd0) begin
          detail_o = 32'h0700_0207;
        end else if (s_flags != 32'd0) begin
          detail_o = 32'h0700_0208;
        end else if ((s_kws[31:16] != 16'd0) || (s_kws[15:8] == 8'd0)) begin
          detail_o = 32'h0700_0209;
        end else if (reserved_i != 256'd0) begin
          detail_o = 32'h0700_0200 | {27'd0, s_reserved_word_index};
        end else begin
          valid_o  = 1'b1;
          code_o   = 6'd0;
          stage_o  = 4'd0;
          detail_o = 32'd0;
        end
      end else if ((reserved_i != 256'd0) ||
          (s_control & 32'h3fff_f000) != 32'd0 ||
          ((s_control[3:0] != 4'd0) && !(EnableP7 && (s_control[3:0] == 4'd1))) ||
          !(s_control[7:4] inside {4'd0, 4'd2}) || s_control[9:8] > 2'd1) begin
        code_o   = `APB4_APU__ERROR_CODE_UNSUPPORTED;
        detail_o = {4'd0, s_control[7:4], 8'd0, 16'h0001};
      end else if ((s_input_bytes == 32'd0) || (s_input_bytes > 32'h7fff_ffff) ||
                   (s_input_addr[1:0] != 2'd0) || s_input_last[32] ||
                   (s_input_addr < read_base_value_i) ||
                   (s_input_last[31:0] > read_limit_value_i)) begin
        detail_o = 32'h0000_0011;
      end else if ((s_input_cfg[31:26] != 6'd0) || s_input_cfg[19] ||
                   (s_input_cfg[18:17] > 2'd2) ||
                   !((s_input_cfg[16:0] == 17'd0) ||
                     ((s_input_cfg[16:0] >= 17'd8000) &&
                      (s_input_cfg[16:0] <= 17'd96000))) ||
                   !(s_input_cfg[25:20] inside {6'd0, 6'd8, 6'd16, 6'd24, 6'd32}) ||
                   ((s_control[7:4] == 4'd2) &&
                    !(s_input_cfg[25:20] inside {6'd0, 6'd16, 6'd24}))) begin
        detail_o = 32'h0000_0002;
      end else if ((s_output_cfg[31:21] != 11'd0) ||
                   (s_output_cfg[18:17] > 2'd2) || (s_output_cfg[20:19] > 2'd1) ||
                   !((s_output_cfg[16:0] == 17'd0) ||
                     ((s_output_cfg[16:0] >= 17'd8000) &&
                      (s_output_cfg[16:0] <= 17'd96000))) ||
                   (s_flags != {31'd0, s_flags[0]}) ||
                   ((s_control[3:0] != 4'd1) && (s_kws != 32'd0))) begin
        detail_o = 32'h0000_0050;
      end else if ((s_control[10] && !((s_input_cfg[18:17] == 2'd2) &&
                                       (s_output_cfg[18:17] == 2'd1))) ||
                   (!s_control[10] && (s_input_cfg[18:17] == 2'd2) &&
                    (s_output_cfg[18:17] == 2'd1)) ||
                   (s_control[11] &&
                    !(s_output_cfg[16:0] inside {17'd48000, 17'd96000})) ||
                   (!s_control[11] && (s_output_cfg[16:0] != 17'd0) &&
                    (s_input_cfg[16:0] != 17'd0) &&
                    (s_output_cfg[16:0] != s_input_cfg[16:0]))) begin
        code_o   = `APB4_APU__ERROR_CODE_UNSUPPORTED;
        detail_o = 32'h0000_0050;
      end else if (s_memory_output && (s_control[3:0] != 4'd1) && ((s_output_addr[1:0] != 2'd0) ||
                                       (s_output_capacity == 32'd0) || s_output_last[32] ||
                                       (s_output_addr < write_base_value_i) ||
                                       (s_output_last[31:0] > write_limit_value_i))) begin
        detail_o = 32'h0000_0051;
      end else if (!s_memory_output && ((s_output_addr != 32'd0) ||
                                        (s_output_capacity != 32'd0))) begin
        detail_o = 32'h0000_0050;
      end else if (s_memory_output &&
                   !((s_input_end <= {1'b0, s_output_addr}) ||
                     (s_output_end <= {1'b0, s_input_addr}))) begin
        detail_o = 32'h0000_0011;
      end else begin
        valid_o  = 1'b1;
        code_o   = 6'd0;
        stage_o  = 4'd0;
        detail_o = 32'd0;
      end
      descriptor_check = {valid_o, code_o, stage_o, detail_o};
    end
  endfunction

  always_comb begin
    s_direct_check = descriptor_check(
      direct_descriptor_i[31:0],
      direct_descriptor_i[319:64],
      direct_descriptor_i[1023:768],
      1'b0,
      read_base_i,
      read_limit_i,
      write_base_i,
      write_limit_i
    );
    s_ring_check = descriptor_check(
      ring_descriptor_i[31:0],
      ring_descriptor_i[319:64],
      ring_descriptor_i[1023:768],
      1'b1,
      read_base_i,
      read_limit_i,
      write_base_i,
      write_limit_i
    );
    s_direct_valid = s_direct_check[42];
    s_direct_reject_code = s_direct_check[41:36];
    s_direct_reject_stage = s_direct_check[35:32];
    s_direct_reject_detail = s_direct_check[31:0];
    s_ring_valid = s_ring_check[42];
    s_ring_reject_code = s_ring_check[41:36];
    s_ring_reject_stage = s_ring_check[35:32];
    s_ring_reject_detail = s_ring_check[31:0];
    s_direct_scratch_bytes = (direct_descriptor_i[7:4] == 4'd0) ?
        entry_scratch_bytes_i[0] :
        ((direct_descriptor_i[7:4] == 4'd2) ? entry_scratch_bytes_i[2] : 17'd0);
    s_ring_scratch_bytes = (ring_descriptor_i[7:4] == 4'd0) ?
        entry_scratch_bytes_i[0] :
        ((ring_descriptor_i[7:4] == 4'd2) ? entry_scratch_bytes_i[2] : 17'd0);
    s_ring_descriptor_base = {1'b0, ring_base_i} + {17'd0, ring_index_i, 7'd0};
    s_ring_descriptor_last = s_ring_descriptor_base + 33'd127;
    s_ring_descriptor_acl_valid = !s_ring_descriptor_base[32] && !s_ring_descriptor_last[32] &&
        (s_ring_descriptor_base[31:0] >= read_base_i) &&
        (s_ring_descriptor_last[31:0] <= read_limit_i) &&
        (s_ring_descriptor_base[31:0] >= write_base_i) &&
        (s_ring_descriptor_last[31:0] <= write_limit_i);
  end

  assign s_direct_kws_allowed = EnableP7 && (direct_descriptor_i[3:0] == 4'd1) &&
      microcode_valid_i && microcode_lock_i &&
      kws_model_valid_i && kws_model_lock_i && kws_memory_armed_i;
  assign s_ring_kws_allowed = EnableP7 && (ring_descriptor_i[3:0] == 4'd1) &&
      microcode_valid_i && microcode_lock_i &&
      kws_model_valid_i && kws_model_lock_i && kws_memory_armed_i;
  assign direct_allowed_o = (s_state_q == Idle) && !block_new_i && !ring_enabled_i &&
      ((s_direct_kws_allowed && s_direct_valid) ||
       (microcode_valid_i && microcode_lock_i && s_direct_valid &&
        (s_direct_reject_code == 6'd0) && (s_direct_reject_stage == 4'd0) &&
        (s_direct_reject_detail == 32'd0) && (s_direct_scratch_bytes >= 17'd64)));
  assign ring_job_ready_o = (s_state_q == Idle) && !block_new_i;
  assign sequencer_entry_o = s_entry_q;
  assign active_descriptor_o = s_descriptor_q;
  assign active_scratch_base_o = entry_scratch_base_i[s_entry_q];
  assign active_scratch_bytes_o = entry_scratch_bytes_i[s_entry_q];
  assign active_index_o = s_ring_q ? s_index_q : 8'd0;
  assign transport_job_start_o = s_state_q == StartTransport;
  assign transport_job_finish_o = s_state_q == FinishTransport;
  assign transport_cancel_o = s_state_q == CancelTransport;
  assign kws_start_o = s_state_q == KwsStart;
  assign kws_config_valid_o = (s_state_q == KwsStart) || (s_state_q == KwsWait);
  assign kws_config_o = s_descriptor_q[(9*32)+:16];
  assign sequencer_launch_o = (s_state_q == WaitContext) && transport_context_ready_i;
  assign ring_result_valid_o = s_state_q == RingResult;
  assign ring_result_error_o = s_terminal_err_q;
  assign ring_result_code_o = s_terminal_code_q;
  assign ring_result_stage_o = s_terminal_stage_q;
  assign ring_result_resp_o = s_terminal_resp_q;
  assign ring_result_input_used_o = s_job_input_q;
  assign ring_result_output_bytes_o = s_job_output_q;
  assign ring_result_frames_o = s_job_frames_q;
  assign ring_result_source_info_o = s_job_source_q;
  assign ring_result_cycles_o = s_job_cycles_q;
  assign ring_result_detail_o = s_job_detail_q;
  assign ring_result_kws_o = s_job_kws_q;
  assign job_status_o = s_job_stat_q;
  assign job_input_used_o = s_job_input_q;
  assign job_output_bytes_o = s_job_output_q;
  assign job_frames_o = s_job_frames_q;
  assign job_source_info_o = s_job_source_q;
  assign job_cycles_o = s_job_cycles_q;
  assign job_detail_o = s_job_detail_q;
  assign busy_o = s_state_q != Idle;
  assign ring_job_o = s_ring_q && (s_state_q != Idle);
  assign idle_o = s_state_q == Idle;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q            <= Idle;
      s_descriptor_q       <= '0;
      s_index_q            <= 8'd0;
      s_entry_q            <= 2'd0;
      s_ring_q             <= 1'b0;
      s_terminal_err_q     <= 1'b0;
      s_terminal_aborted_q <= 1'b0;
      s_terminal_code_q    <= 6'd0;
      s_terminal_stage_q   <= 4'd0;
      s_terminal_resp_q    <= 2'd0;
      s_terminal_detail_q  <= 32'd0;
      s_transport_done_q   <= 1'b0;
      s_job_stat_q         <= 32'd0;
      s_job_input_q        <= 32'd0;
      s_job_output_q       <= 32'd0;
      s_job_frames_q       <= 32'd0;
      s_job_source_q       <= 32'd0;
      s_job_cycles_q       <= 32'd0;
      s_job_detail_q       <= 32'd0;
      s_job_kws_q          <= 32'd0;
      s_kws_cycles_q       <= 32'd0;
      direct_done_o        <= 1'b0;
      fault_valid_o        <= 1'b0;
      fault_code_o         <= 6'd0;
      fault_stage_o        <= 4'd0;
      fault_resp_o         <= 2'd0;
      fault_index_o        <= 8'd0;
      fault_addr_o         <= 32'd0;
      fault_detail_o       <= 32'd0;
    end else begin
      direct_done_o <= 1'b0;
      fault_valid_o <= 1'b0;
      if (transport_job_done_i) s_transport_done_q <= 1'b1;
      if (soft_reset_i || resource_reset_apply_i) begin
        s_state_q          <= Idle;
        s_job_stat_q       <= 32'd0;
        s_transport_done_q <= 1'b0;
        s_kws_cycles_q     <= 32'd0;
      end else begin
        unique case (s_state_q)
          Idle: begin
            if (direct_start_i && direct_allowed_o) begin
              s_descriptor_q <= direct_descriptor_i;
              s_index_q <= 8'd0;
              s_entry_q <= direct_descriptor_i[7:4] == 4'd2 ? 2'd2 : 2'd0;
              s_ring_q <= 1'b0;
              s_terminal_err_q <= 1'b0;
              s_terminal_aborted_q <= 1'b0;
              s_terminal_code_q <= 6'd0;
              s_terminal_stage_q <= 4'd0;
              s_terminal_resp_q <= 2'd0;
              s_terminal_detail_q <= 32'd0;
              s_transport_done_q <= 1'b0;
              s_job_input_q <= 32'd0;
              s_job_output_q <= 32'd0;
              s_job_frames_q <= 32'd0;
              s_job_source_q <= 32'd0;
              s_job_cycles_q <= 32'd0;
              s_job_detail_q <= 32'd0;
              s_job_kws_q <= 32'd0;
              s_kws_cycles_q <= 32'd0;
              s_job_stat_q       <= (32'd1 << `APB4_APU__JOB_STATUS_BUSY) |
                  (32'd1 << `APB4_APU__JOB_STATUS_DIRECT_ACTIVE);
              if (EnableP7 && (direct_descriptor_i[3:0] == 4'd1)) begin
                s_state_q <= KwsStart;
              end else begin
                s_state_q <= StartTransport;
              end
            end else if (ring_job_valid_i && ring_job_ready_o) begin
              s_descriptor_q <= ring_descriptor_i;
              s_index_q <= ring_index_i;
              s_entry_q <= ring_descriptor_i[7:4] == 4'd2 ? 2'd2 : 2'd0;
              s_ring_q <= 1'b1;
              s_terminal_err_q <= !s_ring_valid || !s_ring_descriptor_acl_valid ||
                  ((ring_descriptor_i[3:0] == 4'd1) ? !s_ring_kws_allowed :
                   (!microcode_valid_i || !microcode_lock_i ||
                    (s_ring_scratch_bytes < 17'd64)));
              s_terminal_aborted_q <= 1'b0;
              s_terminal_code_q <= 6'd0;
              s_terminal_stage_q <= 4'd0;
              s_terminal_resp_q <= 2'd0;
              s_terminal_detail_q <= 32'd0;
              s_transport_done_q <= 1'b0;
              if (!s_ring_valid || !s_ring_descriptor_acl_valid ||
                  ((ring_descriptor_i[3:0] == 4'd1) ? !s_ring_kws_allowed :
                   (!microcode_valid_i || !microcode_lock_i ||
                    (s_ring_scratch_bytes < 17'd64)))) begin
                s_terminal_code_q   <= s_ring_valid ?
                    (!s_ring_descriptor_acl_valid ? `APB4_APU__ERROR_CODE_INVALID_RING :
                     ((ring_descriptor_i[3:0] == 4'd1) ? `APB4_APU__ERROR_CODE_UNSUPPORTED :
                      `APB4_APU__ERROR_CODE_UNSUPPORTED)) : s_ring_reject_code;
                s_terminal_stage_q  <= s_ring_valid ?
                    `APB4_APU__ERROR_STAGE_RING : s_ring_reject_stage;
                s_terminal_resp_q <= 2'd0;
                s_terminal_detail_q <= s_ring_valid ?
                    (!s_ring_descriptor_acl_valid ? 32'h0000_0011 : 32'h0700_0200) :
                    s_ring_reject_detail;
                s_job_input_q <= 32'd0;
                s_job_output_q <= 32'd0;
                s_job_frames_q <= 32'd0;
                s_job_source_q <= 32'd0;
                s_job_cycles_q <= 32'd0;
                s_job_detail_q <= s_ring_valid ?
                    (!s_ring_descriptor_acl_valid ? 32'h0000_0011 : 32'h0700_0200) :
                    s_ring_reject_detail;
                s_job_kws_q <= 32'd0;
                s_state_q <= RingResult;
                fault_valid_o <= 1'b1;
                fault_code_o <= s_ring_valid ?
                    (!s_ring_descriptor_acl_valid ? `APB4_APU__ERROR_CODE_INVALID_RING :
                     `APB4_APU__ERROR_CODE_UNSUPPORTED) : s_ring_reject_code;
                fault_stage_o <= `APB4_APU__ERROR_STAGE_RING;
                fault_resp_o <= 2'd0;
                fault_index_o <= ring_index_i;
                fault_addr_o <= ring_base_i + {17'd0, ring_index_i, 7'd0};
                fault_detail_o <= s_ring_valid ?
                    (!s_ring_descriptor_acl_valid ? 32'h0000_0011 : 32'h0700_0200) :
                    s_ring_reject_detail;
              end else begin
                s_job_stat_q   <= 32'd1 << `APB4_APU__JOB_STATUS_BUSY;
                s_job_kws_q    <= 32'd0;
                s_kws_cycles_q <= 32'd0;
                if (EnableP7 && (ring_descriptor_i[3:0] == 4'd1)) begin
                  s_state_q <= KwsStart;
                end else begin
                  s_state_q <= StartTransport;
                end
              end
            end
          end
          StartTransport: s_state_q <= WaitContext;
          WaitContext: begin
            if (quiesce_i || resource_reset_request_i || abort_i) begin
              s_terminal_err_q <= 1'b1;
              s_terminal_aborted_q <= !resource_reset_request_i;
              s_terminal_code_q <= resource_reset_request_i ?
                  `APB4_APU__ERROR_CODE_RESOURCE_RESET : `APB4_APU__ERROR_CODE_ABORT;
              s_terminal_stage_q <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
              s_terminal_resp_q <= 2'd0;
              s_terminal_detail_q <= 32'd0;
              s_state_q <= CancelTransport;
            end else if (transport_context_ready_i) begin
              s_state_q <= Running;
            end
          end
          Running: begin
            if (sequencer_trap_i) begin
              s_terminal_err_q    <= 1'b1;
              s_terminal_code_q   <= sequencer_fault_code_i;
              s_terminal_stage_q  <= sequencer_fault_stage_i;
              s_terminal_resp_q   <= sequencer_fault_resp_i;
              s_terminal_detail_q <= sequencer_fault_detail_i;
              s_state_q           <= CancelTransport;
            end else if (resource_reset_request_i || abort_i) begin
              s_terminal_err_q <= 1'b1;
              s_terminal_aborted_q <= abort_i && !resource_reset_request_i;
              s_terminal_code_q    <= resource_reset_request_i ?
                  `APB4_APU__ERROR_CODE_RESOURCE_RESET : `APB4_APU__ERROR_CODE_ABORT;
              s_terminal_stage_q <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
              s_terminal_resp_q <= 2'd0;
              s_terminal_detail_q <= 32'd0;
              s_state_q <= CancelTransport;
            end else if (quiesce_i && transport_frame_commit_i) begin
              s_terminal_err_q     <= 1'b1;
              s_terminal_aborted_q <= 1'b1;
              s_terminal_code_q    <= `APB4_APU__ERROR_CODE_ABORT;
              s_terminal_stage_q   <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
              s_terminal_resp_q    <= 2'd0;
              s_terminal_detail_q  <= 32'd0;
              s_state_q            <= CancelTransport;
            end else if (sequencer_end_i) begin
              s_state_q <= FinishTransport;
            end
          end
          FinishTransport: begin
            if ((resource_reset_request_i || abort_i) &&
                !(transport_job_done_i && (transport_result_code_i != 6'd0))) begin
              s_terminal_err_q <= 1'b1;
              s_terminal_aborted_q <= abort_i && !resource_reset_request_i;
              s_terminal_code_q <= resource_reset_request_i ?
                  `APB4_APU__ERROR_CODE_RESOURCE_RESET : `APB4_APU__ERROR_CODE_ABORT;
              s_terminal_stage_q <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
              s_terminal_resp_q <= 2'd0;
              s_terminal_detail_q <= 32'd0;
              s_state_q <= CancelTransport;
            end else if (transport_job_done_i) begin
              s_job_input_q <= transport_input_used_i;
              s_job_output_q <= transport_output_bytes_i;
              s_job_frames_q <= transport_frames_i;
              s_job_source_q <= transport_source_info_i;
              s_job_cycles_q <= transport_cycles_i;
              s_job_detail_q <= transport_detail_i;
              s_terminal_code_q <= transport_result_code_i;
              s_terminal_stage_q <= transport_result_stage_i;
              s_terminal_resp_q <= transport_result_resp_i;
              s_terminal_err_q <= transport_result_code_i != 6'd0;
              s_job_stat_q <= ((transport_result_code_i == 6'd0) ?
                  (32'd1 << `APB4_APU__JOB_STATUS_DONE) :
                  ((32'd1 << `APB4_APU__JOB_STATUS_ERROR) |
                   (32'(transport_result_code_i) << `APB4_APU__JOB_STATUS_ERROR_CODE) |
                   (32'(transport_result_stage_i) << `APB4_APU__JOB_STATUS_STAGE) |
                   (32'(transport_result_resp_i) << `APB4_APU__JOB_STATUS_AXI_RESPONSE)));
              if (transport_result_code_i != 6'd0) begin
                fault_valid_o  <= 1'b1;
                fault_code_o   <= transport_result_code_i;
                fault_stage_o  <= transport_result_stage_i;
                fault_resp_o   <= transport_result_resp_i;
                fault_index_o  <= s_ring_q ? s_index_q : 8'd0;
                fault_addr_o   <= s_descriptor_q[(2*32)+:32] + transport_diagnostic_offset_i;
                fault_detail_o <= transport_detail_i;
              end
              if (s_ring_q) begin
                s_state_q <= RingResult;
              end else begin
                direct_done_o <= 1'b1;
                s_state_q     <= Idle;
              end
            end
          end
          CancelTransport: begin
            if ((s_transport_done_q || transport_job_done_i) && sequencer_idle_i) begin
              s_job_input_q <= transport_input_used_i;
              s_job_output_q <= transport_output_bytes_i;
              s_job_frames_q <= transport_frames_i;
              s_job_source_q <= transport_source_info_i;
              s_job_cycles_q <= transport_cycles_i;
              s_job_detail_q <= s_terminal_detail_q;
              s_job_stat_q <= (32'd1 << `APB4_APU__JOB_STATUS_ERROR) |
                  (s_terminal_aborted_q ? (32'd1 << `APB4_APU__JOB_STATUS_ABORTED) : 32'd0) |
                  (32'(s_terminal_code_q) << `APB4_APU__JOB_STATUS_ERROR_CODE) |
                  (32'(s_terminal_stage_q) << `APB4_APU__JOB_STATUS_STAGE) |
                  (32'(s_terminal_resp_q) << `APB4_APU__JOB_STATUS_AXI_RESPONSE);
              if (s_ring_q) begin
                s_state_q <= RingResult;
              end else begin
                direct_done_o <= 1'b1;
                s_state_q     <= Idle;
              end
              s_transport_done_q <= 1'b0;
            end
          end
          KwsStart: begin
            if (abort_i || resource_reset_request_i) begin
              s_terminal_err_q <= 1'b1;
              s_terminal_aborted_q <= abort_i && !resource_reset_request_i;
              s_terminal_code_q <= resource_reset_request_i ?
                  `APB4_APU__ERROR_CODE_RESOURCE_RESET : `APB4_APU__ERROR_CODE_ABORT;
              s_terminal_stage_q <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
              s_terminal_resp_q <= 2'd0;
              s_terminal_detail_q <= 32'd0;
              s_job_input_q <= 32'd0;
              s_job_output_q <= 32'd0;
              s_job_frames_q <= 32'd0;
              s_job_source_q <= 32'd0;
              s_job_cycles_q <= (&s_kws_cycles_q) ? s_kws_cycles_q : s_kws_cycles_q + 1'b1;
              s_job_detail_q <= 32'd0;
              s_job_kws_q <= 32'd0;
              s_job_stat_q <= (32'd1 << `APB4_APU__JOB_STATUS_ERROR) |
                  ((abort_i && !resource_reset_request_i) ?
                       (32'd1 << `APB4_APU__JOB_STATUS_ABORTED) : 32'd0) |
                  (32'(resource_reset_request_i ? `APB4_APU__ERROR_CODE_RESOURCE_RESET :
                                                  `APB4_APU__ERROR_CODE_ABORT)
                   << `APB4_APU__JOB_STATUS_ERROR_CODE) |
                  (32'(`APB4_APU__ERROR_STAGE_LIFECYCLE)
                   << `APB4_APU__JOB_STATUS_STAGE);
              if (s_ring_q) begin
                s_state_q <= RingResult;
              end else begin
                direct_done_o <= 1'b1;
                s_state_q     <= Idle;
              end
            end else begin
              s_kws_cycles_q <= (&s_kws_cycles_q) ? s_kws_cycles_q : s_kws_cycles_q + 1'b1;
              if (kws_start_ready_i) s_state_q <= KwsWait;
            end
          end
          KwsWait: begin
            if (kws_done_i) begin
              s_job_input_q <= kws_input_used_i;
              s_job_output_q <= 32'd0;
              s_job_frames_q <= kws_input_used_i >> 1;
              s_job_source_q <= kws_error_i ? 32'd0 : 32'h0082_3e80;
              s_job_cycles_q <= (&s_kws_cycles_q) ? s_kws_cycles_q : s_kws_cycles_q + 1'b1;
              s_job_detail_q <= kws_error_i ? kws_error_detail_i : 32'd0;
              s_job_kws_q <= kws_error_i ? 32'd0 : kws_result_i;
              s_terminal_code_q <= kws_error_i ? kws_error_code_i : 6'd0;
              s_terminal_stage_q <= kws_error_i ? kws_error_stage_i : 4'd0;
              s_terminal_resp_q <= kws_error_i ? kws_error_resp_i : 2'd0;
              s_terminal_err_q <= kws_error_i;
              s_job_stat_q <= kws_error_i ?
                  ((32'd1 << `APB4_APU__JOB_STATUS_ERROR) |
                   (32'(kws_error_code_i) << `APB4_APU__JOB_STATUS_ERROR_CODE) |
                   (32'(kws_error_stage_i) << `APB4_APU__JOB_STATUS_STAGE) |
                   (32'(kws_error_resp_i) << `APB4_APU__JOB_STATUS_AXI_RESPONSE)) :
                  (32'd1 << `APB4_APU__JOB_STATUS_DONE);
              if (kws_error_i) begin
                fault_valid_o  <= 1'b1;
                fault_code_o   <= kws_error_code_i;
                fault_stage_o  <= kws_error_stage_i;
                fault_resp_o   <= kws_error_resp_i;
                fault_index_o  <= s_ring_q ? s_index_q : 8'd0;
                fault_addr_o   <= kws_error_address_i;
                fault_detail_o <= kws_error_detail_i;
              end
              if (s_ring_q) begin
                s_state_q <= RingResult;
              end else begin
                direct_done_o <= 1'b1;
                s_state_q     <= Idle;
              end
            end else if (abort_i || resource_reset_request_i) begin
              s_terminal_err_q <= 1'b1;
              s_terminal_aborted_q <= abort_i;
              s_terminal_code_q <= resource_reset_request_i ?
                  `APB4_APU__ERROR_CODE_RESOURCE_RESET : `APB4_APU__ERROR_CODE_ABORT;
              s_terminal_stage_q <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
              s_terminal_resp_q <= 2'd0;
              s_terminal_detail_q <= 32'd0;
              s_job_input_q <= kws_input_used_i;
              s_job_output_q <= 32'd0;
              s_job_frames_q <= kws_input_used_i >> 1;
              s_job_source_q <= 32'd0;
              s_job_cycles_q <= (&s_kws_cycles_q) ? s_kws_cycles_q : s_kws_cycles_q + 1'b1;
              s_job_detail_q <= 32'd0;
              s_job_kws_q <= 32'd0;
              s_job_stat_q <= (32'd1 << `APB4_APU__JOB_STATUS_ERROR) |
                  (abort_i ? (32'd1 << `APB4_APU__JOB_STATUS_ABORTED) : 32'd0) |
                  (32'(resource_reset_request_i ? `APB4_APU__ERROR_CODE_RESOURCE_RESET :
                                                  `APB4_APU__ERROR_CODE_ABORT)
                   << `APB4_APU__JOB_STATUS_ERROR_CODE) |
                  (32'(`APB4_APU__ERROR_STAGE_LIFECYCLE)
                   << `APB4_APU__JOB_STATUS_STAGE);
              if (s_ring_q) begin
                s_state_q <= RingResult;
              end else begin
                direct_done_o <= 1'b1;
                s_state_q     <= Idle;
              end
            end else begin
              s_kws_cycles_q <= (&s_kws_cycles_q) ? s_kws_cycles_q : s_kws_cycles_q + 1'b1;
            end
          end
          RingResult: begin
            if (ring_result_ready_i) s_state_q <= Idle;
          end
          default:        s_state_q <= Idle;
        endcase
      end
    end
  end
endmodule
