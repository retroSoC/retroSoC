// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_codec_transport (
    // verilog_format: off -- preserve job, sequencer, DMA, SRAM, and FIFO columns
    input  logic                   clk_i,
    input  logic                   rst_n_i,
    input  logic                   flush_i,
    input  logic                   abort_i,
    input  logic                   block_new_i,
    input  logic                   job_start_i,
    input  logic                   job_finish_i,
    input  logic [1023:0]          descriptor_i,
    input  logic [16:0]            scratch_base_i,
    input  logic [16:0]            scratch_bytes_i,
    output logic                   context_ready_o,
    input  logic                   request_valid_i,
    output logic                   request_ready_o,
    input  logic [4:0]             request_detail_aux_i,
    input  logic [10:0]            request_pc_i,
    input  logic [ 3:0]            request_opcode_i,
    input  logic [ 3:0]            request_dst_i,
    input  logic [ 3:0]            request_aux_i,
    input  logic [ 1:0]            request_event_i,
    input  logic [31:0]            request_source0_i,
    input  logic [31:0]            request_source1_i,
    output logic                   result_valid_o,
    output logic [3:0]             result_dst_o,
    output logic [31:0]            result_data_o,
    output logic                   dma_request_valid_o,
    input  logic                   dma_request_ready_i,
    output logic                   dma_request_write_o,
    output logic [31:0]            dma_request_addr_o,
    output logic [31:0]            dma_request_bytes_o,
    axi4_stream_if.sink            dma_read_axis,
    axi4_stream_if.source          dma_write_axis,
    output logic                   memory_claim_o,
    output logic                   memory_req_o,
    output logic                   memory_write_o,
    output logic [16:0]            memory_addr_o,
    output logic [31:0]            memory_data_o,
    output logic [3:0]             memory_strb_o,
    input  logic                   memory_ready_i,
    input  logic                   memory_valid_i,
    input  logic [31:0]            memory_data_i,
    input  logic                   memory_error_i,
    output logic                   input_fifo_valid_o,
    output logic [40:0]            input_fifo_data_o,
    input  logic                   input_fifo_ready_i,
    input  logic [6:0]             input_fifo_count_i,
    input  logic                   output_fifo_valid_i,
    input  logic [40:0]            output_fifo_data_i,
    output logic                   output_fifo_accept_o,
    input  logic [6:0]             output_fifo_count_i,
    output logic                   output_fifo_push_valid_o,
    output logic [40:0]            output_fifo_push_data_o,
    input  logic                   output_fifo_push_ready_i,
    axi4_stream_if.source          tx_axis,
    input  logic                   tx_empty_i,
    input  logic                   dma_done_i,
    input  logic                   dma_error_i,
    input  logic [5:0]             dma_error_code_i,
    input  logic [3:0]             dma_error_stage_i,
    input  logic [1:0]             dma_error_resp_i,
    input  logic [31:0]            dma_error_addr_i,
    input  logic                   dma_write_burst_done_i,
    input  logic [31:0]            dma_write_burst_bytes_i,
    output logic                   fault_valid_o,
    output logic [5:0]             fault_code_o,
    output logic [3:0]             fault_stage_o,
    output logic [1:0]             fault_resp_o,
    output logic [31:0]            fault_addr_o,
    output logic [31:0]            fault_detail_o,
    output logic [31:0]            input_used_o,
    output logic [31:0]            output_bytes_o,
    output logic [31:0]            frames_o,
    output logic [31:0]            source_info_o,
    output logic [31:0]            cycles_o,
    output logic [31:0]            detail_o,
    output logic [31:0]            diagnostic_offset_o,
    output logic [5:0]             result_code_o,
    output logic [3:0]             result_stage_o,
    output logic [1:0]             result_resp_o,
    output logic                   event_input_o,
    output logic                   event_output_o,
    output logic                   frame_commit_o,
    output logic                   tx_session_active_o,
    output logic                   input_pending_o,
    output logic                   output_pending_o,
    output logic                   job_done_o,
    output logic                   idle_o
    // verilog_format: on
);
  typedef enum logic [4:0] {
    Idle,
    ContextWrite,
    InputDmaRequest,
    InputDmaData,
    InputStageWrite,
    InputDmaWait,
    InputScratchWrite,
    InputFifoPush,
    InputContextWrite,
    OutputMarkerRead,
    OutputMarkerWait,
    OutputMarkerClear,
    OutputSourceRead,
    OutputSourceWait,
    OutputScratchRead,
    OutputScratchWait,
    OutputStageWrite,
    OutputFifoPush,
    OutputDmaRequest,
    OutputDmaData,
    OutputDmaWait,
    OutputStream,
    OutputStreamDrain,
    OutputContextWrite,
    ImmediateResult,
    Drain,
    FinishContextRead,
    FinishContextWait
  } state_e;

  state_e        s_state_q;
  logic   [10:0] s_pc_q;
  logic   [31:0] s_descriptor_q[0:31];
  logic   [31:0] s_buffer_q    [0:63];
  logic [16:0] s_scratch_base_q, s_scratch_bytes_q, s_context_base_q;
  logic [31:0] s_input_addr_q, s_input_len_q, s_output_addr_q, s_output_capacity_q;
  logic [31:0] s_input_cursor_q, s_output_cursor_q;
  logic [31:0] s_logical_input_q, s_logical_output_q, s_frames_q;
  logic [31:0] s_source_info_q, s_cycles_q, s_detail_q;
  logic [31:0] s_diagnostic_offset_q;
  logic [ 3:0] s_frame_bytes_q;
  logic        s_source_valid_q;
  logic        s_queued_valid_q;
  logic [10:0] s_queued_pc_q;
  logic [3:0] s_queued_opcode_q, s_queued_dst_q, s_queued_aux_q;
  logic [1:0] s_queued_event_q;
  logic [31:0] s_queued_source0_q, s_queued_source1_q;
  logic [5:0] s_result_code_q;
  logic [3:0] s_result_stage_q;
  logic [1:0] s_result_resp_q;
  logic [5:0] s_context_word_q, s_word_q, s_word_count_q;
  logic [2:0] s_last_bytes_q;
  logic [3:0] s_opcode_q, s_dst_q;
  logic [3:0] s_req_aux_q;
  logic [1:0] s_req_event_q;
  logic [31:0] s_offset_q, s_bytes_q, s_actual_q;
  logic [31:0] s_read_data_q;
  logic [31:0] s_buffer_read;
  logic s_final_q, s_final_seen_q, s_dma_seen_q, s_dma_active_q, s_dma_err_q;
  logic s_abort_q, s_job_active_q;
  logic [ 5:0] s_dma_err_code_q;
  logic [ 3:0] s_dma_err_stage_q;
  logic [ 1:0] s_dma_err_resp_q;
  logic [31:0] s_dma_err_addr_q;
  logic [32:0] s_range_end, s_output_end;
  logic [31:0] s_req_actual;
  logic [31:0] s_req_actual_words;
  logic [31:0] s_queued_input_actual;
  logic [ 2:0] s_fifo_bytes;
  logic s_req_fire, s_mem_fire, s_output_handshake;
  logic s_output_fifo_metadata_ok;
  logic s_input_contract_ok, s_input_reservation_ok;
  logic s_output_contract_ok, s_output_capacity_error, s_output_cursor_overflow;
  logic s_job_result_contract_ok, s_frame_commit_contract_ok;
  logic s_source_info_valid;
  logic [1:0] s_output_channels;
  logic [3:0] s_output_frame_bytes;
  logic s_active_input, s_active_output, s_opposite_async_request;
  logic [31:0] s_req_trap_detail1, s_req_trap_detail5, s_req_trap_detail9;
  logic [31:0] s_active_trap_detail5, s_active_trap_detail9;

  function automatic logic source_info_valid(input logic [31:0] source_info_i);
    logic [16:0] s_rate;
    logic [ 1:0] s_channels;
    logic [ 5:0] s_bits;
    begin
      s_rate = source_info_i[16:0];
      s_channels = source_info_i[18:17];
      s_bits = source_info_i[24:19];
      return (source_info_i[31:25] == 7'd0) &&
          (s_rate >= 17'd8000) && (s_rate <= 17'd96000) &&
          (s_channels inside {2'd1, 2'd2}) &&
          (s_bits inside {6'd8, 6'd16, 6'd24, 6'd32});
    end
  endfunction

  function automatic logic [31:0] physical_frames(input logic [31:0] bytes_i,
                                                  input logic [3:0] frame_bytes_i);
    unique case (frame_bytes_i)
      4'd2:    return bytes_i >> 1;
      4'd4:    return bytes_i >> 2;
      4'd8:    return bytes_i >> 3;
      default: return 32'hffff_ffff;
    endcase
  endfunction

  function automatic logic [31:0] context_word(input logic [5:0] word_i);
    unique case (word_i)
      6'd0:    context_word = s_descriptor_q[0] & 32'h3fff_ffff;
      6'd1:    context_word = s_descriptor_q[6];
      6'd2:    context_word = s_descriptor_q[7];
      6'd3:    context_word = s_descriptor_q[8];
      6'd8:    context_word = s_input_len_q;
      6'd9:    context_word = s_output_capacity_q;
      6'd10:   context_word = s_input_addr_q + s_input_cursor_q;
      6'd11:   context_word = s_output_cursor_q;
      default: context_word = 32'd0;
    endcase
  endfunction

  assign s_range_end = {1'b0, request_source0_i} + {1'b0, request_source1_i};
  assign s_output_end = {1'b0, s_output_cursor_q} + {1'b0, request_source1_i};
  assign s_req_actual = ((s_input_len_q - s_input_cursor_q) < request_source1_i) ?
      (s_input_len_q - s_input_cursor_q) : request_source1_i;
  assign s_req_actual_words = (s_req_actual + 32'd3) >> 2;
  assign s_queued_input_actual = ((s_input_len_q - s_input_cursor_q) < s_queued_source1_q) ?
      (s_input_len_q - s_input_cursor_q) : s_queued_source1_q;
  assign s_fifo_bytes = ((s_word_q + 1'b1) == s_word_count_q) ? s_last_bytes_q : 3'd4;
  assign s_buffer_read = s_buffer_q[s_word_q];
  assign s_req_fire = request_valid_i && request_ready_o;
  assign s_mem_fire = memory_req_o && memory_ready_i;
  assign s_output_handshake = ((s_state_q == OutputDmaData) && dma_write_axis.tvalid &&
                               dma_write_axis.tready) ||
      ((s_state_q == OutputStream) && tx_axis.tvalid && tx_axis.tready);
  assign s_output_fifo_metadata_ok = (output_fifo_data_i[39:35] == 5'd0) &&
      (output_fifo_data_i[34:32] >= 3'd1) && (output_fifo_data_i[34:32] <= 3'd4) &&
      (output_fifo_data_i[40] ==
       (s_final_q && ((s_word_q + 1'b1) == s_word_count_q)));
  assign s_input_contract_ok = (request_source1_i >= 32'd4) &&
      (request_source1_i <= 32'd256) && (request_source1_i[1:0] == 2'd0) &&
      (request_source0_i[1:0] == 2'd0) && !s_range_end[32] &&
      (s_range_end <= {16'd0, s_scratch_bytes_q});
  assign s_input_reservation_ok = s_req_actual_words <= (32'd64 - {25'd0, input_fifo_count_i});
  assign s_output_cursor_overflow = s_output_end[32];
  assign s_output_capacity_error = (s_descriptor_q[0][9:8] == 2'd0) &&
      !s_output_cursor_overflow && (s_output_end[31:0] > s_output_capacity_q);
  assign s_output_contract_ok = (request_source1_i >= 32'd1) &&
      (request_source1_i <= 32'd256) && (request_source0_i[1:0] == 2'd0) &&
      !s_range_end[32] && (s_range_end <= {16'd0, s_scratch_bytes_q}) &&
      (output_fifo_count_i == 7'd0) && !s_final_seen_q &&
      (((request_opcode_i == `APB4_APU__MC_TRANSPORT_OUTPUT_COMMIT) &&
        (s_descriptor_q[0][9:8] == 2'd0)) ||
       ((request_opcode_i == `APB4_APU__MC_TRANSPORT_OUTPUT_STREAM) &&
        (s_descriptor_q[0][9:8] == 2'd1))) &&
      !s_output_cursor_overflow && !s_output_capacity_error;
  assign s_job_result_contract_ok = (request_source0_i[31:6] == 26'd0) &&
      (request_source0_i[5:0] <= `APB4_APU__ERROR_CODE_OVERFLOW);
  assign s_frame_commit_contract_ok = (s_frame_bytes_q inside {4'd2, 4'd4, 4'd8}) &&
      (request_source1_i == {28'd0, s_frame_bytes_q}) &&
      ({1'b0, s_logical_input_q} + {1'b0, request_source0_i} <=
       {1'b0, s_input_cursor_q}) &&
      ({1'b0, s_logical_output_q} + {1'b0, request_source1_i} <=
       {1'b0, s_output_cursor_q});
  assign s_source_info_valid = source_info_valid(memory_data_i);
  assign s_req_trap_detail1 = {
    request_detail_aux_i,
    request_opcode_i,
    4'd6,
    request_pc_i,
    8'd1
  };
  assign s_req_trap_detail5 = {
    request_detail_aux_i,
    request_opcode_i,
    4'd6,
    request_pc_i,
    8'd5
  };
  assign s_req_trap_detail9 = {
    request_detail_aux_i,
    request_opcode_i,
    4'd6,
    request_pc_i,
    8'd9
  };
  assign s_active_trap_detail5 = {1'b0, s_req_aux_q, s_opcode_q, 4'd6, s_pc_q, 8'd5};
  assign s_active_trap_detail9 = {1'b0, s_req_aux_q, s_opcode_q, 4'd6, s_pc_q, 8'd9};
  assign s_output_channels = (s_descriptor_q[0][9:8] == 2'd1) ? 2'd2 :
      ((s_descriptor_q[7][18:17] != 2'd0) ?
       s_descriptor_q[7][18:17] : memory_data_i[18:17]);
  assign s_output_frame_bytes = (s_descriptor_q[7][20:19] == 2'd0) ?
      ({2'd0, s_output_channels} << 1) : ({2'd0, s_output_channels} << 2);

  assign s_active_input = s_state_q inside {InputDmaRequest, InputDmaData, InputStageWrite,
                                            InputDmaWait, InputScratchWrite, InputFifoPush,
                                            InputContextWrite};
  assign s_active_output = s_state_q inside {OutputMarkerRead, OutputMarkerWait,
                                             OutputMarkerClear, OutputSourceRead,
                                             OutputSourceWait, OutputScratchRead,
                                             OutputScratchWait, OutputStageWrite,
                                             OutputFifoPush, OutputDmaRequest,
                                             OutputDmaData, OutputDmaWait, OutputStream,
                                             OutputStreamDrain, OutputContextWrite};
  assign s_opposite_async_request =
      (s_active_input &&
       (request_opcode_i inside {`APB4_APU__MC_TRANSPORT_OUTPUT_COMMIT,
                                 `APB4_APU__MC_TRANSPORT_OUTPUT_STREAM})) ||
      (s_active_output && (request_opcode_i == `APB4_APU__MC_TRANSPORT_INPUT_REFILL));
  assign context_ready_o = s_job_active_q && (s_state_q == Idle) && !s_queued_valid_q;
  assign idle_o = (s_state_q == Idle) && !s_job_active_q && !s_queued_valid_q;
  assign input_pending_o = s_active_input ||
      (s_queued_valid_q && (s_queued_opcode_q == `APB4_APU__MC_TRANSPORT_INPUT_REFILL));
  assign output_pending_o = s_active_output ||
      (s_queued_valid_q &&
       (s_queued_opcode_q inside {`APB4_APU__MC_TRANSPORT_OUTPUT_COMMIT,
                                  `APB4_APU__MC_TRANSPORT_OUTPUT_STREAM}));
  assign tx_session_active_o = s_job_active_q &&
      ((s_descriptor_q[0][9:8] == 2'd1) || (s_state_q == OutputStream));
  assign input_used_o = s_logical_input_q;
  assign output_bytes_o = s_output_cursor_q;
  assign frames_o = s_frames_q;
  assign source_info_o = s_source_info_q;
  assign cycles_o = s_cycles_q;
  assign detail_o = s_detail_q;
  assign diagnostic_offset_o = s_diagnostic_offset_q;
  assign result_code_o = s_result_code_q;
  assign result_stage_o = s_result_stage_q;
  assign result_resp_o = s_result_resp_q;

  always_comb begin
    request_ready_o = 1'b0;
    if (s_job_active_q && !block_new_i && !abort_i &&
        ((s_state_q == Idle) || (!s_queued_valid_q && s_opposite_async_request))) begin
      unique case (request_opcode_i)
        `APB4_APU__MC_TRANSPORT_INPUT_REFILL:
        request_ready_o = !s_input_contract_ok || s_input_reservation_ok;
        `APB4_APU__MC_TRANSPORT_OUTPUT_COMMIT, `APB4_APU__MC_TRANSPORT_OUTPUT_STREAM:
        request_ready_o = 1'b1;
        `APB4_APU__MC_TRANSPORT_DMA_WAIT: request_ready_o = !input_pending_o && !output_pending_o;
        `APB4_APU__MC_TRANSPORT_FRAME_COMMIT,
        `APB4_APU__MC_TRANSPORT_JOB_RESULT,
        `APB4_APU__MC_TRANSPORT_EVENT:
        request_ready_o = 1'b1;
        default: request_ready_o = 1'b0;
      endcase
    end
  end

  always_comb begin
    memory_claim_o = 1'b0;
    memory_req_o   = 1'b0;
    memory_write_o = 1'b0;
    memory_addr_o  = 17'd0;
    memory_data_o  = 32'd0;
    memory_strb_o  = 4'hf;
    unique case (s_state_q)
      ContextWrite: begin
        memory_claim_o = 1'b1;
        memory_req_o   = 1'b1;
        memory_write_o = 1'b1;
        memory_addr_o  = s_context_base_q + {9'd0, s_context_word_q, 2'd0};
        memory_data_o  = context_word(s_context_word_q);
      end
      InputStageWrite: begin
        memory_claim_o = 1'b1;
        memory_req_o   = 1'b1;
        memory_write_o = 1'b1;
        memory_addr_o  = `APB4_APU__LOCAL_INPUT_BASE + {9'd0, s_word_q, 2'd0};
        memory_data_o  = s_buffer_read;
      end
      InputScratchWrite: begin
        memory_claim_o = 1'b1;
        memory_req_o = 1'b1;
        memory_write_o = 1'b1;
        memory_addr_o = s_scratch_base_q + s_offset_q[16:0] + {9'd0, s_word_q, 2'd0};
        memory_data_o = s_buffer_read;
        memory_strb_o  = ((s_word_q + 1'b1) == s_word_count_q) ?
            ((4'b0001 << s_last_bytes_q) - 1'b1) : 4'hf;
      end
      InputContextWrite: begin
        memory_claim_o = 1'b1;
        memory_req_o   = 1'b1;
        memory_write_o = 1'b1;
        memory_addr_o  = s_context_base_q + 17'd40;
        memory_data_o  = s_input_addr_q + s_input_cursor_q;
      end
      OutputMarkerRead: begin
        memory_claim_o = 1'b1;
        memory_req_o   = 1'b1;
        memory_addr_o  = s_context_base_q + 17'd28;
      end
      OutputMarkerWait:  memory_claim_o = 1'b1;
      OutputMarkerClear: begin
        memory_claim_o = 1'b1;
        memory_req_o   = 1'b1;
        memory_write_o = 1'b1;
        memory_addr_o  = s_context_base_q + 17'd28;
        memory_data_o  = 32'd0;
      end
      OutputSourceRead: begin
        memory_claim_o = 1'b1;
        memory_req_o   = 1'b1;
        memory_addr_o  = s_context_base_q + 17'd24;
      end
      OutputSourceWait:  memory_claim_o = 1'b1;
      OutputScratchRead: begin
        memory_claim_o = 1'b1;
        memory_req_o   = 1'b1;
        memory_addr_o  = s_scratch_base_q + s_offset_q[16:0] + {9'd0, s_word_q, 2'd0};
      end
      OutputScratchWait: memory_claim_o = 1'b1;
      OutputStageWrite: begin
        memory_claim_o = 1'b1;
        memory_req_o = 1'b1;
        memory_write_o = 1'b1;
        memory_addr_o = `APB4_APU__LOCAL_OUTPUT_BASE + {9'd0, s_word_q, 2'd0};
        memory_data_o = s_read_data_q;
        memory_strb_o  = ((s_word_q + 1'b1) == s_word_count_q) ?
            ((4'b0001 << s_last_bytes_q) - 1'b1) : 4'hf;
      end
      OutputContextWrite: begin
        memory_claim_o = 1'b1;
        memory_req_o   = 1'b1;
        memory_write_o = 1'b1;
        memory_addr_o  = s_context_base_q + 17'd44;
        memory_data_o  = s_output_cursor_q;
      end
      FinishContextRead: begin
        memory_claim_o = 1'b1;
        memory_req_o   = 1'b1;
        memory_addr_o  = s_context_base_q + {9'd0, s_context_word_q, 2'd0};
      end
      FinishContextWait: memory_claim_o = 1'b1;
      default: begin
      end
    endcase
  end

  assign input_fifo_valid_o = s_state_q == InputFifoPush;
  assign input_fifo_data_o = {
    (s_input_cursor_q + s_actual_q == s_input_len_q) && ((s_word_q + 1'b1) == s_word_count_q),
    5'd0,
    s_fifo_bytes,
    s_buffer_read
  };
  assign output_fifo_accept_o = s_output_handshake ||
      ((s_state_q == Drain) && output_fifo_valid_i && !s_dma_active_q);
  assign output_fifo_push_valid_o = s_state_q == OutputFifoPush;
  assign output_fifo_push_data_o = {
    s_final_q && ((s_word_q + 1'b1) == s_word_count_q), 5'd0, s_fifo_bytes, s_buffer_read
  };

  assign dma_request_valid_o = s_state_q inside {InputDmaRequest, OutputDmaRequest};
  assign dma_request_write_o = s_state_q == OutputDmaRequest;
  assign dma_request_addr_o = (s_state_q == InputDmaRequest) ?
      (s_input_addr_q + s_input_cursor_q) : (s_output_addr_q + s_output_cursor_q);
  assign dma_request_bytes_o = s_actual_q;
  assign dma_read_axis.tready = s_state_q == InputDmaData;

  assign dma_write_axis.tdata = output_fifo_data_i[31:0];
  assign dma_write_axis.tkeep = (output_fifo_data_i[34:32] == 3'd4) ?
      4'hf : ((4'b0001 << output_fifo_data_i[34:32]) - 1'b1);
  assign dma_write_axis.tstrb = dma_write_axis.tkeep;
  assign dma_write_axis.tlast = (s_word_q + 1'b1) == s_word_count_q;
  assign dma_write_axis.tid = '0;
  assign dma_write_axis.tdest = '0;
  assign dma_write_axis.tuser = '0;
  assign dma_write_axis.tvalid = (s_state_q == OutputDmaData) && output_fifo_valid_i &&
      s_output_fifo_metadata_ok;

  assign tx_axis.tdata = output_fifo_data_i[31:0];
  assign tx_axis.tkeep = 4'hf;
  assign tx_axis.tstrb = 4'hf;
  assign tx_axis.tlast = s_final_q && ((s_word_q + 1'b1) == s_word_count_q);
  assign tx_axis.tid = '0;
  assign tx_axis.tdest = '0;
  assign tx_axis.tuser = '0;
  assign tx_axis.tvalid = (s_state_q == OutputStream) && output_fifo_valid_i &&
      s_output_fifo_metadata_ok;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q             <= Idle;
      s_pc_q                <= 11'd0;
      s_scratch_base_q      <= 17'd0;
      s_scratch_bytes_q     <= 17'd0;
      s_context_base_q      <= 17'd0;
      s_input_addr_q        <= 32'd0;
      s_input_len_q         <= 32'd0;
      s_output_addr_q       <= 32'd0;
      s_output_capacity_q   <= 32'd0;
      s_input_cursor_q      <= 32'd0;
      s_output_cursor_q     <= 32'd0;
      s_logical_input_q     <= 32'd0;
      s_logical_output_q    <= 32'd0;
      s_frames_q            <= 32'd0;
      s_source_info_q       <= 32'd0;
      s_cycles_q            <= 32'd0;
      s_detail_q            <= 32'd0;
      s_diagnostic_offset_q <= 32'd0;
      s_frame_bytes_q       <= 4'd0;
      s_source_valid_q      <= 1'b0;
      s_queued_valid_q      <= 1'b0;
      s_queued_pc_q         <= 11'd0;
      s_queued_opcode_q     <= 4'd0;
      s_queued_dst_q        <= 4'd0;
      s_queued_aux_q        <= 4'd0;
      s_queued_event_q      <= 2'd0;
      s_queued_source0_q    <= 32'd0;
      s_queued_source1_q    <= 32'd0;
      s_result_code_q       <= 6'd0;
      s_result_stage_q      <= 4'd0;
      s_result_resp_q       <= 2'd0;
      s_context_word_q      <= 6'd0;
      s_word_q              <= 6'd0;
      s_word_count_q        <= 6'd0;
      s_last_bytes_q        <= 3'd0;
      s_opcode_q            <= 4'd0;
      s_dst_q               <= 4'd0;
      s_req_aux_q           <= 4'd0;
      s_req_event_q         <= 2'd0;
      s_offset_q            <= 32'd0;
      s_bytes_q             <= 32'd0;
      s_actual_q            <= 32'd0;
      s_read_data_q         <= 32'd0;
      s_final_q             <= 1'b0;
      s_final_seen_q        <= 1'b0;
      s_dma_seen_q          <= 1'b0;
      s_dma_active_q        <= 1'b0;
      s_dma_err_q           <= 1'b0;
      s_dma_err_code_q      <= 6'd0;
      s_dma_err_stage_q     <= 4'd0;
      s_dma_err_resp_q      <= 2'd0;
      s_dma_err_addr_q      <= 32'd0;
      s_abort_q             <= 1'b0;
      s_job_active_q        <= 1'b0;
      result_valid_o        <= 1'b0;
      result_dst_o          <= 4'd0;
      result_data_o         <= 32'd0;
      fault_valid_o         <= 1'b0;
      fault_code_o          <= 6'd0;
      fault_stage_o         <= 4'd0;
      fault_resp_o          <= 2'd0;
      fault_addr_o          <= 32'd0;
      fault_detail_o        <= 32'd0;
      event_input_o         <= 1'b0;
      event_output_o        <= 1'b0;
      frame_commit_o        <= 1'b0;
      job_done_o            <= 1'b0;
    end else begin
      result_valid_o <= 1'b0;
      fault_valid_o  <= 1'b0;
      event_input_o  <= 1'b0;
      event_output_o <= 1'b0;
      frame_commit_o <= 1'b0;
      job_done_o     <= 1'b0;
      if (s_job_active_q && !(&s_cycles_q)) s_cycles_q <= s_cycles_q + 1'b1;
      if (dma_done_i) begin
        s_dma_seen_q      <= 1'b1;
        s_dma_err_q       <= dma_error_i;
        s_dma_err_code_q  <= dma_error_code_i;
        s_dma_err_stage_q <= dma_error_stage_i;
        s_dma_err_resp_q  <= dma_error_resp_i;
        s_dma_err_addr_q  <= dma_error_addr_i;
      end
      if (dma_request_valid_o && dma_request_ready_i) s_dma_active_q <= 1'b1;
      if (dma_done_i) s_dma_active_q <= 1'b0;
      if (dma_write_burst_done_i && s_job_active_q) begin
        s_output_cursor_q <= s_output_cursor_q + dma_write_burst_bytes_i;
      end
      if (abort_i) begin
        s_abort_q        <= 1'b1;
        s_queued_valid_q <= 1'b0;
      end

      if (flush_i && !input_pending_o && !output_pending_o) begin
        s_state_q        <= Idle;
        s_job_active_q   <= 1'b0;
        s_abort_q        <= 1'b0;
        s_queued_valid_q <= 1'b0;
      end else if (job_start_i && (s_state_q == Idle) && !s_job_active_q) begin
        for (int word = 0; word < 32; word++) begin
          s_descriptor_q[word] <= descriptor_i[(word*32)+:32];
        end
        s_scratch_base_q      <= scratch_base_i;
        s_scratch_bytes_q     <= scratch_bytes_i;
        s_context_base_q      <= scratch_base_i + scratch_bytes_i - 17'd64;
        s_input_addr_q        <= descriptor_i[(2*32)+:32];
        s_input_len_q         <= descriptor_i[(3*32)+:32];
        s_output_addr_q       <= descriptor_i[(4*32)+:32];
        s_output_capacity_q   <= descriptor_i[(5*32)+:32];
        s_input_cursor_q      <= 32'd0;
        s_output_cursor_q     <= 32'd0;
        s_logical_input_q     <= 32'd0;
        s_logical_output_q    <= 32'd0;
        s_frames_q            <= 32'd0;
        s_source_info_q       <= 32'd0;
        s_cycles_q            <= 32'd0;
        s_detail_q            <= 32'd0;
        s_diagnostic_offset_q <= 32'd0;
        s_frame_bytes_q       <= 4'd0;
        s_source_valid_q      <= 1'b0;
        s_queued_valid_q      <= 1'b0;
        s_result_code_q       <= 6'd0;
        s_result_stage_q      <= 4'd0;
        s_result_resp_q       <= 2'd0;
        s_final_seen_q        <= 1'b0;
        s_context_word_q      <= 6'd0;
        s_abort_q             <= 1'b0;
        s_dma_active_q        <= 1'b0;
        s_job_active_q        <= 1'b1;
        s_state_q             <= ContextWrite;
      end else if (fault_valid_o && s_job_active_q) begin
        s_queued_valid_q <= 1'b0;
        s_state_q        <= Drain;
      end else begin
        if (s_req_fire && (s_state_q != Idle)) begin
          if ((request_opcode_i == `APB4_APU__MC_TRANSPORT_INPUT_REFILL) &&
              !s_input_contract_ok) begin
            fault_valid_o  <= 1'b1;
            fault_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;
            fault_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
            fault_addr_o   <= {18'd0, request_pc_i, 3'd0};
            fault_detail_o <= s_req_trap_detail5;
          end else if ((request_opcode_i inside {`APB4_APU__MC_TRANSPORT_OUTPUT_COMMIT,
                                                 `APB4_APU__MC_TRANSPORT_OUTPUT_STREAM}) &&
                       !s_output_contract_ok) begin
            fault_valid_o <= 1'b1;
            if (s_output_cursor_overflow) begin
              fault_code_o   <= `APB4_APU__ERROR_CODE_OVERFLOW;
              fault_stage_o  <= `APB4_APU__ERROR_STAGE_DMA_WRITE;
              fault_addr_o   <= 32'hffff_ffff;
              fault_detail_o <= s_req_trap_detail9;
            end else if (s_output_capacity_error) begin
              fault_code_o   <= `APB4_APU__ERROR_CODE_RECONSTRUCTION;
              fault_stage_o  <= `APB4_APU__ERROR_STAGE_DMA_WRITE;
              fault_addr_o   <= s_output_addr_q + s_output_cursor_q;
              fault_detail_o <= {4'd0, s_descriptor_q[0][7:4], s_detail_q[23:16], 16'h0051};
            end else begin
              fault_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;
              fault_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
              fault_addr_o   <= {18'd0, request_pc_i, 3'd0};
              fault_detail_o <= s_final_seen_q ? s_req_trap_detail9 : s_req_trap_detail5;
            end
          end else begin
            s_queued_valid_q   <= 1'b1;
            s_queued_pc_q      <= request_pc_i;
            s_queued_opcode_q  <= request_opcode_i;
            s_queued_dst_q     <= request_dst_i;
            s_queued_aux_q     <= request_aux_i;
            s_queued_event_q   <= request_event_i;
            s_queued_source0_q <= request_source0_i;
            s_queued_source1_q <= request_source1_i;
          end
        end
        unique case (s_state_q)
          Idle: begin
            if (s_abort_q && s_job_active_q) begin
              s_job_active_q <= 1'b0;
              s_abort_q      <= 1'b0;
              job_done_o     <= 1'b1;
            end else if (s_queued_valid_q) begin
              s_pc_q           <= s_queued_pc_q;
              s_opcode_q       <= s_queued_opcode_q;
              s_dst_q          <= s_queued_dst_q;
              s_req_aux_q      <= s_queued_aux_q;
              s_req_event_q    <= s_queued_event_q;
              s_offset_q       <= s_queued_source0_q;
              s_bytes_q        <= s_queued_source1_q;
              s_word_q         <= 6'd0;
              s_queued_valid_q <= 1'b0;
              if (s_queued_opcode_q == `APB4_APU__MC_TRANSPORT_INPUT_REFILL) begin
                s_actual_q <= s_queued_input_actual;
                s_word_count_q <= 6'((s_queued_input_actual + 32'd3) >> 2);
                s_last_bytes_q <= ((s_queued_input_actual & 32'd3) == 32'd0) ?
                    3'd4 : 3'(s_queued_input_actual & 32'd3);
                if (s_input_cursor_q == s_input_len_q) begin
                  result_valid_o <= 1'b1;
                  result_dst_o   <= s_queued_dst_q;
                  result_data_o  <= 32'd0;
                end else begin
                  s_dma_seen_q <= 1'b0;
                  s_dma_err_q  <= 1'b0;
                  s_state_q    <= InputDmaRequest;
                end
              end else begin
                s_actual_q <= s_queued_source1_q;
                s_word_count_q <= 6'((s_queued_source1_q + 32'd3) >> 2);
                s_last_bytes_q <= ((s_queued_source1_q & 32'd3) == 32'd0) ?
                    3'd4 : 3'(s_queued_source1_q & 32'd3);
                s_state_q <= OutputMarkerRead;
              end
            end else if (job_finish_i && s_job_active_q) begin
              s_context_word_q <= 6'd4;
              s_state_q        <= FinishContextRead;
            end else if (s_req_fire) begin
              s_opcode_q    <= request_opcode_i;
              s_pc_q        <= request_pc_i;
              s_dst_q       <= request_dst_i;
              s_req_aux_q   <= request_aux_i;
              s_req_event_q <= request_event_i;
              s_offset_q    <= request_source0_i;
              s_bytes_q     <= request_source1_i;
              s_word_q      <= 6'd0;
              if (request_opcode_i == `APB4_APU__MC_TRANSPORT_INPUT_REFILL) begin
                if (!s_input_contract_ok) begin
                  fault_valid_o  <= 1'b1;
                  fault_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;
                  fault_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                  fault_addr_o   <= {18'd0, request_pc_i, 3'd0};
                  fault_detail_o <= s_req_trap_detail5;
                end else begin
                  s_actual_q <= s_req_actual;
                  s_word_count_q <= 6'((s_req_actual + 32'd3) >> 2);
                  s_last_bytes_q <= ((s_req_actual & 32'd3) == 32'd0) ?
                      3'd4 : 3'(s_req_actual & 32'd3);
                  if (s_input_cursor_q == s_input_len_q) begin
                    result_valid_o <= 1'b1;
                    result_dst_o   <= request_dst_i;
                    result_data_o  <= 32'd0;
                  end else begin
                    s_dma_seen_q <= 1'b0;
                    s_dma_err_q  <= 1'b0;
                    s_state_q    <= InputDmaRequest;
                  end
                end
              end else if (request_opcode_i inside {`APB4_APU__MC_TRANSPORT_OUTPUT_COMMIT,
                  `APB4_APU__MC_TRANSPORT_OUTPUT_STREAM
                  }) begin
                if (!s_output_contract_ok) begin
                  fault_valid_o <= 1'b1;
                  if (s_output_cursor_overflow) begin
                    fault_code_o   <= `APB4_APU__ERROR_CODE_OVERFLOW;
                    fault_stage_o  <= `APB4_APU__ERROR_STAGE_DMA_WRITE;
                    fault_addr_o   <= 32'hffff_ffff;
                    fault_detail_o <= s_req_trap_detail9;
                  end else if (s_output_capacity_error) begin
                    fault_code_o   <= `APB4_APU__ERROR_CODE_RECONSTRUCTION;
                    fault_stage_o  <= `APB4_APU__ERROR_STAGE_DMA_WRITE;
                    fault_addr_o   <= s_output_addr_q + s_output_cursor_q;
                    fault_detail_o <= {4'd0, s_descriptor_q[0][7:4], s_detail_q[23:16], 16'h0051};
                  end else begin
                    fault_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;
                    fault_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                    fault_addr_o   <= {18'd0, request_pc_i, 3'd0};
                    fault_detail_o <= s_final_seen_q ? s_req_trap_detail9 : s_req_trap_detail5;
                  end
                end else begin
                  s_actual_q <= request_source1_i;
                  s_word_count_q <= 6'((request_source1_i + 32'd3) >> 2);
                  s_last_bytes_q <= ((request_source1_i & 32'd3) == 32'd0) ?
                      3'd4 : 3'(request_source1_i & 32'd3);
                  s_state_q <= OutputMarkerRead;
                end
              end else if ((request_opcode_i == `APB4_APU__MC_TRANSPORT_JOB_RESULT) &&
                           !s_job_result_contract_ok) begin
                fault_valid_o  <= 1'b1;
                fault_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;
                fault_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                fault_addr_o   <= {18'd0, request_pc_i, 3'd0};
                fault_detail_o <= s_req_trap_detail1;
              end else if ((request_opcode_i == `APB4_APU__MC_TRANSPORT_FRAME_COMMIT) &&
                           !s_frame_commit_contract_ok) begin
                fault_valid_o  <= 1'b1;
                fault_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;
                fault_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                fault_addr_o   <= {18'd0, request_pc_i, 3'd0};
                fault_detail_o <= s_req_trap_detail9;
              end else if (request_opcode_i > `APB4_APU__MC_TRANSPORT_EVENT) begin
                fault_valid_o  <= 1'b1;
                fault_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;
                fault_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                fault_addr_o   <= {18'd0, request_pc_i, 3'd0};
                fault_detail_o <= s_req_trap_detail1;
              end else begin
                s_state_q <= ImmediateResult;
              end
            end
          end
          ContextWrite: begin
            if (s_abort_q) begin
              s_state_q <= Drain;
            end else if (s_mem_fire) begin
              if (s_context_word_q == 6'd15) begin
                s_state_q <= Idle;
              end else begin
                s_context_word_q <= s_context_word_q + 1'b1;
              end
            end
          end
          InputDmaRequest: begin
            if (s_abort_q) s_state_q <= Drain;
            else if (dma_request_ready_i) s_state_q <= InputDmaData;
          end
          InputDmaData: begin
            if (dma_done_i && dma_error_i) begin
              fault_valid_o    <= 1'b1;
              fault_code_o     <= dma_error_code_i;
              fault_stage_o    <= dma_error_stage_i;
              fault_resp_o     <= dma_error_resp_i;
              fault_addr_o     <= dma_error_addr_i;
              s_result_code_q  <= dma_error_code_i;
              s_result_stage_q <= dma_error_stage_i;
              s_result_resp_q  <= dma_error_resp_i;
              s_state_q        <= Drain;
            end else if (s_abort_q && (dma_done_i || !s_dma_active_q)) begin
              s_state_q <= Drain;
            end else if (dma_read_axis.tvalid && dma_read_axis.tready) begin
              s_buffer_q[s_word_q] <= dma_read_axis.tdata;
              s_state_q            <= InputStageWrite;
            end
          end
          InputStageWrite: begin
            if (dma_done_i && dma_error_i) begin
              fault_valid_o    <= 1'b1;
              fault_code_o     <= dma_error_code_i;
              fault_stage_o    <= dma_error_stage_i;
              fault_resp_o     <= dma_error_resp_i;
              fault_addr_o     <= dma_error_addr_i;
              s_result_code_q  <= dma_error_code_i;
              s_result_stage_q <= dma_error_stage_i;
              s_result_resp_q  <= dma_error_resp_i;
              s_state_q        <= Drain;
            end else if (s_abort_q && (dma_done_i || !s_dma_active_q)) begin
              s_state_q <= Drain;
            end else if (s_mem_fire) begin
              if ((s_word_q + 1'b1) == s_word_count_q) begin
                s_state_q <= InputDmaWait;
              end else begin
                s_word_q  <= s_word_q + 1'b1;
                s_state_q <= InputDmaData;
              end
            end
          end
          InputDmaWait: begin
            if (s_dma_seen_q || dma_done_i) begin
              if (s_abort_q) begin
                s_state_q <= Drain;
              end else if (s_dma_err_q || dma_error_i) begin
                fault_valid_o    <= 1'b1;
                fault_code_o     <= s_dma_err_q ? s_dma_err_code_q : dma_error_code_i;
                fault_stage_o    <= s_dma_err_q ? s_dma_err_stage_q : dma_error_stage_i;
                fault_resp_o     <= s_dma_err_q ? s_dma_err_resp_q : dma_error_resp_i;
                fault_addr_o     <= s_dma_err_q ? s_dma_err_addr_q : dma_error_addr_i;
                fault_detail_o   <= 32'd0;
                s_result_code_q  <= s_dma_err_q ? s_dma_err_code_q : dma_error_code_i;
                s_result_stage_q <= s_dma_err_q ? s_dma_err_stage_q : dma_error_stage_i;
                s_result_resp_q  <= s_dma_err_q ? s_dma_err_resp_q : dma_error_resp_i;
                s_state_q        <= Drain;
              end else begin
                s_word_q  <= 6'd0;
                s_state_q <= InputScratchWrite;
              end
            end
          end
          InputScratchWrite: begin
            if (s_abort_q) s_state_q <= Drain;
            else if (s_mem_fire) s_state_q <= InputFifoPush;
          end
          InputFifoPush: begin
            if (s_abort_q) begin
              s_state_q <= Drain;
            end else if (input_fifo_ready_i) begin
              if ((s_word_q + 1'b1) == s_word_count_q) begin
                s_input_cursor_q <= s_input_cursor_q + s_actual_q;
                s_state_q        <= InputContextWrite;
              end else begin
                s_word_q  <= s_word_q + 1'b1;
                s_state_q <= InputScratchWrite;
              end
            end
          end
          InputContextWrite: begin
            if (s_abort_q) begin
              s_state_q <= Drain;
            end else if (s_mem_fire) begin
              result_valid_o <= 1'b1;
              result_dst_o   <= s_dst_q;
              result_data_o  <= s_actual_q;
              s_state_q      <= Idle;
            end
          end
          OutputMarkerRead: begin
            if (s_abort_q) s_state_q <= Drain;
            else if (s_mem_fire) s_state_q <= OutputMarkerWait;
          end
          OutputMarkerWait: begin
            if (s_abort_q) begin
              s_state_q <= Drain;
            end else if (memory_valid_i) begin
              if (memory_error_i || (memory_data_i & 32'hffff_fffe) != 32'd0) begin
                fault_valid_o  <= 1'b1;
                fault_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;
                fault_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                fault_detail_o <= 32'h0000_0009;
                s_state_q      <= Drain;
              end else begin
                s_final_q <= memory_data_i[0];
                if (memory_data_i[0]) s_final_seen_q <= 1'b1;
                s_state_q <= OutputMarkerClear;
              end
            end
          end
          OutputMarkerClear: begin
            if (s_abort_q) s_state_q <= Drain;
            else if (s_mem_fire) s_state_q <= OutputSourceRead;
          end
          OutputSourceRead: begin
            if (s_abort_q) s_state_q <= Drain;
            else if (s_mem_fire) s_state_q <= OutputSourceWait;
          end
          OutputSourceWait: begin
            if (s_abort_q) begin
              s_state_q <= Drain;
            end else if (memory_valid_i) begin
              if (memory_error_i || !s_source_info_valid ||
                  (s_source_valid_q && (memory_data_i != s_source_info_q))) begin
                fault_valid_o  <= 1'b1;
                fault_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;
                fault_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                fault_addr_o   <= {18'd0, s_pc_q, 3'd0};
                fault_detail_o <= s_active_trap_detail9;
                s_state_q      <= Idle;
              end else if (!((s_output_frame_bytes == 4'd2 && !s_bytes_q[0]) ||
                             (s_output_frame_bytes == 4'd4 && (s_bytes_q[1:0] == 2'd0)) ||
                             (s_output_frame_bytes == 4'd8 && (s_bytes_q[2:0] == 3'd0)))) begin
                fault_valid_o  <= 1'b1;
                fault_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;
                fault_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                fault_addr_o   <= {18'd0, s_pc_q, 3'd0};
                fault_detail_o <= s_active_trap_detail5;
                s_state_q      <= Idle;
              end else begin
                s_source_info_q  <= memory_data_i;
                s_source_valid_q <= 1'b1;
                s_frame_bytes_q  <= s_output_frame_bytes;
                s_state_q        <= OutputScratchRead;
              end
            end
          end
          OutputScratchRead: begin
            if (s_abort_q) s_state_q <= Drain;
            else if (s_mem_fire) s_state_q <= OutputScratchWait;
          end
          OutputScratchWait: begin
            if (s_abort_q) begin
              s_state_q <= Drain;
            end else if (memory_valid_i) begin
              if (memory_error_i) begin
                fault_valid_o  <= 1'b1;
                fault_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;
                fault_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                fault_detail_o <= 32'h0000_0009;
                s_state_q      <= Drain;
              end else begin
                s_read_data_q        <= memory_data_i;
                s_buffer_q[s_word_q] <= memory_data_i;
                s_state_q            <= OutputStageWrite;
              end
            end
          end
          OutputStageWrite: begin
            if (s_abort_q) begin
              s_state_q <= Drain;
            end else if (s_mem_fire) begin
              if ((s_word_q + 1'b1) == s_word_count_q) begin
                s_word_q  <= 6'd0;
                s_state_q <= OutputFifoPush;
              end else begin
                s_word_q  <= s_word_q + 1'b1;
                s_state_q <= OutputScratchRead;
              end
            end
          end
          OutputFifoPush: begin
            if (s_abort_q) begin
              s_state_q <= Drain;
            end else if (output_fifo_push_ready_i) begin
              if ((s_word_q + 1'b1) == s_word_count_q) begin
                s_word_q <= 6'd0;
                if (s_opcode_q == `APB4_APU__MC_TRANSPORT_OUTPUT_COMMIT) begin
                  s_dma_seen_q <= 1'b0;
                  s_dma_err_q  <= 1'b0;
                  s_state_q    <= OutputDmaRequest;
                end else begin
                  s_state_q <= OutputStream;
                end
              end else begin
                s_word_q <= s_word_q + 1'b1;
              end
            end
          end
          OutputDmaRequest: begin
            if (s_abort_q) s_state_q <= Drain;
            else if (dma_request_ready_i) s_state_q <= OutputDmaData;
          end
          OutputDmaData: begin
            if (dma_done_i && dma_error_i) begin
              fault_valid_o    <= 1'b1;
              fault_code_o     <= dma_error_code_i;
              fault_stage_o    <= dma_error_stage_i;
              fault_resp_o     <= dma_error_resp_i;
              fault_addr_o     <= dma_error_addr_i;
              s_result_code_q  <= dma_error_code_i;
              s_result_stage_q <= dma_error_stage_i;
              s_result_resp_q  <= dma_error_resp_i;
              s_state_q        <= Drain;
            end else if (s_abort_q && (dma_done_i || !s_dma_active_q)) begin
              s_state_q <= Drain;
            end else if (output_fifo_valid_i && !s_output_fifo_metadata_ok) begin
              fault_valid_o    <= 1'b1;
              fault_code_o     <= `APB4_APU__ERROR_CODE_OVERFLOW;
              fault_stage_o    <= `APB4_APU__ERROR_STAGE_DMA_WRITE;
              fault_detail_o   <= 32'h0000_0009;
              s_result_code_q  <= `APB4_APU__ERROR_CODE_OVERFLOW;
              s_result_stage_q <= `APB4_APU__ERROR_STAGE_DMA_WRITE;
              s_state_q        <= Drain;
            end else if (s_output_handshake) begin
              if ((s_word_q + 1'b1) == s_word_count_q) begin
                s_state_q <= OutputDmaWait;
              end else begin
                s_word_q <= s_word_q + 1'b1;
              end
            end
          end
          OutputDmaWait: begin
            if (s_dma_seen_q || dma_done_i) begin
              if (s_dma_err_q || dma_error_i) begin
                fault_valid_o    <= 1'b1;
                fault_code_o     <= s_dma_err_q ? s_dma_err_code_q : dma_error_code_i;
                fault_stage_o    <= s_dma_err_q ? s_dma_err_stage_q : dma_error_stage_i;
                fault_resp_o     <= s_dma_err_q ? s_dma_err_resp_q : dma_error_resp_i;
                fault_addr_o     <= s_dma_err_q ? s_dma_err_addr_q : dma_error_addr_i;
                s_result_code_q  <= s_dma_err_q ? s_dma_err_code_q : dma_error_code_i;
                s_result_stage_q <= s_dma_err_q ? s_dma_err_stage_q : dma_error_stage_i;
                s_result_resp_q  <= s_dma_err_q ? s_dma_err_resp_q : dma_error_resp_i;
                s_state_q        <= Drain;
              end else if (s_abort_q) begin
                s_state_q <= Drain;
              end else begin
                s_state_q <= OutputContextWrite;
              end
            end
          end
          OutputStream: begin
            if (output_fifo_valid_i && !s_output_fifo_metadata_ok) begin
              fault_valid_o    <= 1'b1;
              fault_code_o     <= `APB4_APU__ERROR_CODE_OVERFLOW;
              fault_stage_o    <= `APB4_APU__ERROR_STAGE_DMA_WRITE;
              fault_detail_o   <= 32'h0000_0009;
              s_result_code_q  <= `APB4_APU__ERROR_CODE_OVERFLOW;
              s_result_stage_q <= `APB4_APU__ERROR_STAGE_DMA_WRITE;
              s_state_q        <= Drain;
            end else if (s_abort_q) begin
              if (!tx_axis.tvalid || s_output_handshake) begin
                if (s_output_handshake) begin
                  s_output_cursor_q <= s_output_cursor_q + {29'd0, output_fifo_data_i[34:32]};
                end
                s_state_q <= Drain;
              end
            end else if (s_output_handshake) begin
              s_output_cursor_q <= s_output_cursor_q + {29'd0, output_fifo_data_i[34:32]};
              if ((s_word_q + 1'b1) == s_word_count_q) begin
                s_state_q <= OutputStreamDrain;
              end else begin
                s_word_q <= s_word_q + 1'b1;
              end
            end
          end
          OutputStreamDrain: begin
            if (tx_empty_i) s_state_q <= s_abort_q ? Drain : OutputContextWrite;
          end
          OutputContextWrite: begin
            if (s_abort_q) begin
              s_state_q <= Drain;
            end else if (s_mem_fire) begin
              result_valid_o <= 1'b1;
              result_dst_o   <= s_dst_q;
              result_data_o  <= s_actual_q;
              s_state_q      <= Idle;
            end
          end
          ImmediateResult: begin
            if (s_abort_q) begin
              s_state_q <= Drain;
            end else begin
              result_valid_o <= 1'b1;
              result_dst_o   <= s_dst_q;
              result_data_o  <= 32'd0;
              unique case (s_opcode_q)
                `APB4_APU__MC_TRANSPORT_FRAME_COMMIT: begin
                  s_logical_input_q <= (&s_logical_input_q ||
                                      (32'hffff_ffff - s_logical_input_q < s_offset_q)) ?
                    32'hffff_ffff : s_logical_input_q + s_offset_q;
                  s_logical_output_q <= (&s_logical_output_q ||
                                       (32'hffff_ffff - s_logical_output_q < s_bytes_q)) ?
                    32'hffff_ffff : s_logical_output_q + s_bytes_q;
                  if (!(&s_frames_q)) s_frames_q <= s_frames_q + 1'b1;
                  frame_commit_o <= 1'b1;
                end
                `APB4_APU__MC_TRANSPORT_JOB_RESULT: begin
                  s_result_code_q  <= s_offset_q[5:0];
                  s_detail_q       <= s_bytes_q;
                  s_result_stage_q <= s_req_aux_q;
                end
                `APB4_APU__MC_TRANSPORT_EVENT: begin
                  event_input_o  <= s_req_event_q[0];
                  event_output_o <= s_req_event_q[1];
                end
                default: begin
                end
              endcase
              s_state_q <= Idle;
            end
          end
          Drain: begin
            if (!s_dma_active_q && !dma_read_axis.tvalid && !output_fifo_valid_i) begin
              if (s_abort_q && (s_result_code_q == 6'd0)) begin
                s_result_code_q  <= `APB4_APU__ERROR_CODE_ABORT;
                s_result_stage_q <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                s_result_resp_q  <= 2'd0;
              end
              s_job_active_q <= 1'b0;
              s_abort_q      <= 1'b0;
              s_state_q      <= Idle;
              job_done_o     <= 1'b1;
            end
          end
          FinishContextRead: begin
            if (s_abort_q) s_state_q <= Drain;
            else if (s_mem_fire) s_state_q <= FinishContextWait;
          end
          FinishContextWait: begin
            if (s_abort_q) begin
              s_state_q <= Drain;
            end else if (memory_valid_i) begin
              if (memory_error_i) begin
                fault_valid_o    <= 1'b1;
                fault_code_o     <= `APB4_APU__ERROR_CODE_SEQUENCER;
                fault_stage_o    <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                fault_detail_o   <= 32'h0000_0009;
                s_result_code_q  <= `APB4_APU__ERROR_CODE_SEQUENCER;
                s_result_stage_q <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                s_job_active_q   <= 1'b0;
                s_state_q        <= Idle;
                job_done_o       <= 1'b1;
              end else if (s_context_word_q == 6'd4) begin
                if ((memory_data_i > s_input_len_q) || (memory_data_i < s_logical_input_q)) begin
                  fault_valid_o    <= 1'b1;
                  fault_code_o     <= `APB4_APU__ERROR_CODE_SEQUENCER;
                  fault_stage_o    <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                  fault_addr_o     <= {18'd0, request_pc_i, 3'd0};
                  fault_detail_o   <= s_req_trap_detail9;
                  s_result_code_q  <= `APB4_APU__ERROR_CODE_SEQUENCER;
                  s_result_stage_q <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                  s_detail_q       <= s_req_trap_detail9;
                  s_job_active_q   <= 1'b0;
                  s_state_q        <= Idle;
                  job_done_o       <= 1'b1;
                end else begin
                  s_logical_input_q <= memory_data_i;
                  s_context_word_q  <= 6'd5;
                  s_state_q         <= FinishContextRead;
                end
              end else if (s_context_word_q == 6'd5) begin
                if (memory_data_i > s_input_len_q) begin
                  fault_valid_o    <= 1'b1;
                  fault_code_o     <= `APB4_APU__ERROR_CODE_SEQUENCER;
                  fault_stage_o    <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                  fault_addr_o     <= {18'd0, request_pc_i, 3'd0};
                  fault_detail_o   <= s_req_trap_detail9;
                  s_result_code_q  <= `APB4_APU__ERROR_CODE_SEQUENCER;
                  s_result_stage_q <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                  s_detail_q       <= s_req_trap_detail9;
                  s_job_active_q   <= 1'b0;
                  s_state_q        <= Idle;
                  job_done_o       <= 1'b1;
                end else begin
                  s_diagnostic_offset_q <= memory_data_i;
                  s_context_word_q      <= 6'd6;
                  s_state_q             <= FinishContextRead;
                end
              end else begin
                if ((s_result_code_q == 6'd0) &&
                    (!s_source_info_valid ||
                     (s_source_valid_q && (memory_data_i != s_source_info_q)) ||
                     (s_logical_output_q != s_output_cursor_q) ||
                     ((s_output_cursor_q != 32'd0) &&
                      (!(s_frame_bytes_q inside {4'd2, 4'd4, 4'd8}) ||
                       (s_frames_q != physical_frames(
                        s_output_cursor_q, s_frame_bytes_q
                    )))) || ((s_descriptor_q[0][9:8] == 2'd1) && (s_output_cursor_q != 32'd0) &&
                             !s_final_seen_q))) begin
                  fault_valid_o    <= 1'b1;
                  fault_code_o     <= `APB4_APU__ERROR_CODE_SEQUENCER;
                  fault_stage_o    <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                  fault_addr_o     <= {18'd0, request_pc_i, 3'd0};
                  fault_detail_o   <= s_req_trap_detail9;
                  s_result_code_q  <= `APB4_APU__ERROR_CODE_SEQUENCER;
                  s_result_stage_q <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                  s_detail_q       <= s_req_trap_detail9;
                end
                s_source_info_q <= memory_data_i;
                s_job_active_q  <= 1'b0;
                s_state_q       <= Idle;
                job_done_o      <= 1'b1;
              end
            end
          end
          default: s_state_q <= Idle;
        endcase
      end
    end
  end
endmodule
