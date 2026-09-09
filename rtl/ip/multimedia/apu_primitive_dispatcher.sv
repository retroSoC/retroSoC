// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_primitive_dispatcher (
    // verilog_format: off -- preserve request, result, memory, and FIFO columns
    input  logic                  clk_i,
    input  logic                  rst_n_i,
    input  logic                  flush_i,
    input  logic                  req_valid_i,
    output logic                  req_ready_o,
    input  logic [63:0]           instruction_i,
    input  logic [31:0]           source0_i,
    input  logic [31:0]           source1_i,
    input  logic [31:0]           destination_i,
    input  logic [16:0]           scratch_base_i,
    input  logic [16:0]           scratch_bytes_i,
    input  logic [15:0]           table_offset_i,
    input  logic [15:0]           table_bytes_i,
    output logic                  result_valid_o,
    output logic [ 3:0]           result_dst_o,
    output logic [ 3:0][31:0]     result_data_o,
    output logic [ 2:0]           result_words_o,
    output logic                  result_kernel_o,
    output logic                  error_o,
    output logic [ 5:0]           error_code_o,
    output logic [ 3:0]           error_stage_o,
    output logic [ 7:0]           error_reason_o,
    output logic [31:0]           cycles_o,
    output logic                  kernel_done_o,
    output logic                  busy_o,
    output logic                  input_exhausted_o,
    output logic                  input_ready_o,
    output logic                  output_ready_o,
    output logic [ 6:0]           input_count_o,
    output logic [ 6:0]           output_count_o,
    output logic                  kernel_busy_o,
    output logic                  memory_req_o,
    output logic                  memory_write_o,
    output logic [16:0]           memory_addr_o,
    output logic [31:0]           memory_data_o,
    output logic [ 3:0]           memory_strb_o,
    input  logic                  memory_valid_i,
    input  logic [31:0]           memory_data_i,
    input  logic                  memory_error_i,
    input  logic                  input_valid_i,
    input  logic [40:0]           input_data_i,
    output logic                  input_accept_o,
    output logic                  output_valid_o,
    output logic [40:0]           output_data_o,
    input  logic                  output_accept_i,
    input  logic                  transport_output_valid_i,
    input  logic [40:0]           transport_output_data_i,
    output logic                  transport_output_accept_o,
    input  logic                  transport_output_owned_i
    // verilog_format: on
);
  typedef enum logic [3:0] {
    Idle,
    BitRequest,
    BitWait,
    FrameAlignRequest,
    FrameAlignWait,
    FramePeekRequest,
    FramePeekWait,
    FrameSkipRequest,
    FrameSkipWait,
    EntropyRequest,
    EntropyWait,
    LocalRequest,
    LocalWait
  } state_e;

  state_e        s_state_q;
  logic   [63:0] s_instruction_q;
  logic [31:0] s_source0_q, s_source1_q;
  logic [16:0] s_scratch_base_q, s_scratch_bytes_q;
  logic [15:0] s_table_offset_q, s_table_bytes_q;
  logic [15:0] s_frame_skipped_q;
  logic [16:0] s_local_addr_q;
  logic [ 1:0] s_local_lane_q;
  logic [ 2:0] s_local_size_q;
  logic [31:0] s_cycles_q;

  logic [3:0] s_class, s_opcode, s_dst;
  logic [ 7:0] s_aux;
  logic [31:0] s_immediate;
  logic s_input_full, s_input_empty, s_output_full, s_output_empty;
  logic [6:0] s_input_count, s_output_count;
  logic [40:0] s_input_fifo_data, s_output_fifo_data;
  logic s_input_fifo_push, s_input_fifo_pop, s_output_fifo_push, s_output_fifo_pop;
  logic [40:0] s_output_fifo_write_data;
  logic        s_fifo_metadata_ok;

  logic s_bit_req_valid, s_bit_req_ready, s_direct_bit_req, s_direct_frame_align;
  logic s_frame_match, s_frame_can_skip;
  logic [2:0] s_bit_req_op;
  logic [5:0] s_bit_req_width;
  logic s_bit_result_valid, s_bit_err, s_bit_fifo_pop;
  logic [31:0] s_bit_result_data;
  logic [ 6:0] s_available_bits;
  logic        s_reservoir_eof;

  logic s_entropy_req_valid, s_entropy_req_ready;
  logic s_direct_entropy_req;
  logic s_entropy_memory_req, s_entropy_bit_req_valid, s_entropy_bit_req_ready;
  logic [16:0] s_entropy_memory_addr;
  logic [ 2:0] s_entropy_bit_req_op;
  logic [ 5:0] s_entropy_bit_req_width;
  logic s_entropy_result_valid, s_entropy_err;
  logic [ 3:0]       s_entropy_result_dst;
  logic [ 3:0][31:0] s_entropy_result_data;
  logic [ 2:0]       s_entropy_result_words;
  logic [ 5:0]       s_entropy_err_code;
  logic [ 3:0]       s_entropy_err_stage;
  logic [31:0]       s_entropy_cycles;

  logic s_kernel_req_valid, s_kernel_req_ready, s_kernel_memory_req, s_kernel_memory_write;
  logic [16:0] s_kernel_memory_addr;
  logic [31:0] s_kernel_memory_data;
  logic [ 3:0] s_kernel_memory_strb;
  logic s_kernel_done, s_kernel_err, s_kernel_busy;
  logic [5:0] s_kernel_err_code;
  logic [3:0] s_kernel_err_stage, s_kernel_result_dst;
  logic [7:0] s_kernel_err_reason;
  logic [31:0] s_kernel_result_count, s_kernel_cycles;

  logic [32:0] s_scratch_end, s_local_end, s_table_end;
  logic [32:0] s_entropy_table_end;
  logic        s_entropy_range_ok;
  logic [34:0] s_local_addr_full;
  logic        s_local_addr_overflow_q;
  logic s_local_range_ok, s_local_access_ok, s_local_write;
  logic [31:0] s_crc_result;

  assign s_class = instruction_i[63:60];
  assign s_opcode = instruction_i[59:56];
  assign s_dst = instruction_i[51:48];
  assign s_aux = instruction_i[39:32];
  assign s_immediate = instruction_i[31:0];

  assign req_ready_o = (s_state_q == Idle) &&
      (((s_class == `APB4_APU__MC_CLASS_KERNEL) && s_kernel_req_ready) ||
       (!s_kernel_busy &&
        ((s_class inside {`APB4_APU__MC_CLASS_BITSTREAM, `APB4_APU__MC_CLASS_ENTROPY}) ||
         ((s_class == `APB4_APU__MC_CLASS_LOCAL) &&
        (((s_opcode == `APB4_APU__MC_LOCAL_FIFO_POP) && !s_input_empty) ||
         ((s_opcode == `APB4_APU__MC_LOCAL_FIFO_PUSH) && !s_output_full &&
          !transport_output_owned_i) ||
          (s_opcode < `APB4_APU__MC_LOCAL_FIFO_POP))))));
  assign busy_o = (s_state_q != Idle) || s_kernel_busy;
  assign kernel_done_o = result_valid_o && result_kernel_o && !error_o;
  assign input_exhausted_o = s_reservoir_eof;
  assign input_ready_o = !s_input_empty;
  assign output_ready_o = !s_output_full;
  assign input_count_o = s_input_count;
  assign output_count_o = s_output_count;
  assign kernel_busy_o = s_kernel_busy;

  assign input_accept_o = input_valid_i && !s_input_full;
  assign s_input_fifo_push = input_accept_o;
  assign s_input_fifo_pop = s_bit_fifo_pop ||
      (req_valid_i && req_ready_o && (s_class == `APB4_APU__MC_CLASS_LOCAL) &&
       (s_opcode == `APB4_APU__MC_LOCAL_FIFO_POP));
  assign s_fifo_metadata_ok = ((source1_i & ~32'h0000_0107) == 32'd0) &&
      (source1_i[2:0] != 3'd0) && (source1_i[2:0] <= 3'd4);
  assign transport_output_accept_o = transport_output_valid_i && !s_output_full;
  assign s_output_fifo_push = transport_output_accept_o ||
      (req_valid_i && req_ready_o && s_fifo_metadata_ok && !transport_output_owned_i &&
       (s_class == `APB4_APU__MC_CLASS_LOCAL) &&
       (s_opcode == `APB4_APU__MC_LOCAL_FIFO_PUSH));
  assign s_output_fifo_write_data = transport_output_valid_i ? transport_output_data_i :
      {source1_i[8], 5'd0, source1_i[2:0], source0_i};
  assign output_valid_o = !s_output_empty;
  assign output_data_o = s_output_fifo_data;
  assign s_output_fifo_pop = output_accept_i && output_valid_o;

  stream_fifo #(
      .DATA_WIDTH      (41),
      .BUFFER_DEPTH    (64),
      .LOG_BUFFER_DEPTH(6)
  ) u_input_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(flush_i),
      .full_o (s_input_full),
      .empty_o(s_input_empty),
      .cnt_o  (s_input_count),
      .dat_i  (input_data_i),
      .push_i (s_input_fifo_push),
      .dat_o  (s_input_fifo_data),
      .pop_i  (s_input_fifo_pop)
  );

  stream_fifo #(
      .DATA_WIDTH      (41),
      .BUFFER_DEPTH    (64),
      .LOG_BUFFER_DEPTH(6)
  ) u_output_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(flush_i),
      .full_o (s_output_full),
      .empty_o(s_output_empty),
      .cnt_o  (s_output_count),
      .dat_i  (s_output_fifo_write_data),
      .push_i (s_output_fifo_push),
      .dat_o  (s_output_fifo_data),
      .pop_i  (s_output_fifo_pop)
  );

  assign s_direct_bit_req = (s_state_q == Idle) && req_valid_i && req_ready_o &&
      (s_class == `APB4_APU__MC_CLASS_BITSTREAM) &&
      (s_opcode <= `APB4_APU__MC_BITSTREAM_ALIGN);
  assign s_direct_frame_align = (s_state_q == Idle) && req_valid_i && req_ready_o &&
      (s_class == `APB4_APU__MC_CLASS_BITSTREAM) &&
      (s_opcode == `APB4_APU__MC_BITSTREAM_FRAME_SYNC);
  assign s_frame_match = (s_bit_result_data[15:0] & s_source1_q[15:0]) ==
      (s_source0_q[15:0] & s_source1_q[15:0]);
  assign s_frame_can_skip = !s_bit_err && !s_frame_match &&
      (s_frame_skipped_q < s_instruction_q[15:0] - 1'b1);
  assign s_bit_req_valid = s_direct_bit_req || s_direct_frame_align ||
      ((s_state_q == FrameAlignWait) && s_bit_result_valid && !s_bit_err) ||
      ((s_state_q == FramePeekWait) && s_bit_result_valid && s_frame_can_skip) ||
      ((s_state_q == FrameSkipWait) && s_bit_result_valid && !s_bit_err) ||
      (s_state_q inside {
    BitRequest, FrameAlignRequest, FramePeekRequest, FrameSkipRequest
  }) || s_entropy_bit_req_valid;
  assign s_bit_req_op = s_entropy_bit_req_valid ? s_entropy_bit_req_op :
      (s_direct_bit_req ? s_opcode[2:0] :
       ((s_direct_frame_align || (s_state_q == FrameAlignRequest)) ? 3'd4 :
        ((s_state_q inside {FrameAlignWait, FramePeekRequest, FrameSkipWait}) ? 3'd1 :
         ((s_state_q inside {FramePeekWait, FrameSkipRequest}) ?
          3'd2 : s_instruction_q[58:56]))));
  assign s_bit_req_width = s_entropy_bit_req_valid ? s_entropy_bit_req_width :
      (s_direct_bit_req ? s_immediate[5:0] :
       ((s_direct_frame_align || (s_state_q == FrameAlignRequest)) ? 6'd0 :
        ((s_state_q inside {FrameAlignWait, FramePeekRequest, FrameSkipWait}) ?
         {1'b0, s_instruction_q[36:32]} :
         ((s_state_q inside {FramePeekWait, FrameSkipRequest}) ?
          6'd8 : s_instruction_q[5:0]))));
  assign s_entropy_bit_req_ready = s_bit_req_ready && s_entropy_bit_req_valid;

  apu_bitstream_engine u_bitstream_engine (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .flush_i         (flush_i),
      .req_valid_i     (s_bit_req_valid),
      .req_ready_o     (s_bit_req_ready),
      .req_op_i        (s_bit_req_op),
      .req_width_i     (s_bit_req_width),
      .result_valid_o  (s_bit_result_valid),
      .result_data_o   (s_bit_result_data),
      .available_bits_o(s_available_bits),
      .eof_o           (s_reservoir_eof),
      .error_o         (s_bit_err),
      .fifo_empty_i    (s_input_empty),
      .fifo_data_i     (s_input_fifo_data),
      .fifo_pop_o      (s_bit_fifo_pop)
  );

  assign s_direct_entropy_req = (s_state_q == Idle) && req_valid_i && req_ready_o &&
      (s_class == `APB4_APU__MC_CLASS_ENTROPY);
  assign s_entropy_req_valid = (s_state_q == EntropyRequest) || s_direct_entropy_req;
  assign s_kernel_req_valid = (s_state_q == Idle) && req_valid_i &&
      (s_class == `APB4_APU__MC_CLASS_KERNEL) && !s_kernel_done &&
      !(result_valid_o && result_kernel_o);

  apu_entropy_engine u_entropy_engine (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .flush_i           (flush_i),
      .req_valid_i       (s_entropy_req_valid),
      .req_ready_o       (s_entropy_req_ready),
      .opcode_i          (s_direct_entropy_req ? s_opcode : s_instruction_q[59:56]),
      .dst_i             (s_direct_entropy_req ? s_dst : s_instruction_q[51:48]),
      .aux_i             (s_direct_entropy_req ? s_aux : s_instruction_q[39:32]),
      .immediate_i       (s_direct_entropy_req ? s_immediate : s_instruction_q[31:0]),
      .source0_i         (s_direct_entropy_req ? source0_i : s_source0_q),
      .source1_i         (s_direct_entropy_req ? source1_i : s_source1_q),
      .table_offset_i    (s_direct_entropy_req ? table_offset_i : s_table_offset_q),
      .memory_req_o      (s_entropy_memory_req),
      .memory_addr_o     (s_entropy_memory_addr),
      .memory_valid_i    (memory_valid_i),
      .memory_data_i     (memory_data_i),
      .memory_error_i    (memory_error_i),
      .bit_req_valid_o   (s_entropy_bit_req_valid),
      .bit_req_ready_i   (s_entropy_bit_req_ready),
      .bit_req_op_o      (s_entropy_bit_req_op),
      .bit_req_width_o   (s_entropy_bit_req_width),
      .bit_result_valid_i(s_bit_result_valid),
      .bit_result_data_i (s_bit_result_data),
      .bit_error_i       (s_bit_err),
      .result_valid_o    (s_entropy_result_valid),
      .result_dst_o      (s_entropy_result_dst),
      .result_data_o     (s_entropy_result_data),
      .result_words_o    (s_entropy_result_words),
      .error_o           (s_entropy_err),
      .error_code_o      (s_entropy_err_code),
      .error_stage_o     (s_entropy_err_stage),
      .cycles_o          (s_entropy_cycles)
  );

  apu_kernel_engine u_kernel_engine (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .flush_i           (flush_i),
      .req_valid_i       (s_kernel_req_valid),
      .req_ready_o       (s_kernel_req_ready),
      .opcode_i          (s_opcode),
      .aux_i             (s_aux),
      .count_i           (s_immediate[15:0]),
      .dst_i             (s_dst),
      .input_offset_i    (source0_i),
      .parameter_offset_i(source1_i),
      .output_offset_i   (destination_i),
      .scratch_base_i    (scratch_base_i),
      .scratch_bytes_i   (scratch_bytes_i),
      .table_offset_i    (table_offset_i),
      .table_bytes_i     (table_bytes_i),
      .memory_req_o      (s_kernel_memory_req),
      .memory_write_o    (s_kernel_memory_write),
      .memory_addr_o     (s_kernel_memory_addr),
      .memory_data_o     (s_kernel_memory_data),
      .memory_strb_o     (s_kernel_memory_strb),
      .memory_valid_i    (memory_valid_i),
      .memory_data_i     (memory_data_i),
      .memory_error_i    (memory_error_i),
      .done_o            (s_kernel_done),
      .error_o           (s_kernel_err),
      .error_code_o      (s_kernel_err_code),
      .error_stage_o     (s_kernel_err_stage),
      .error_reason_o    (s_kernel_err_reason),
      .result_dst_o      (s_kernel_result_dst),
      .result_count_o    (s_kernel_result_count),
      .cycles_o          (s_kernel_cycles),
      .busy_o            (s_kernel_busy)
  );

  assign memory_req_o = s_kernel_busy ? s_kernel_memory_req :
      (s_entropy_memory_req || ((s_state_q == LocalRequest) && s_local_access_ok));
  assign memory_write_o = s_kernel_busy ? s_kernel_memory_write :
      ((s_state_q == LocalRequest) && s_local_access_ok && s_local_write);
  assign memory_addr_o = s_kernel_busy ? s_kernel_memory_addr :
      (s_entropy_memory_req ? s_entropy_memory_addr : {s_local_addr_q[16:2], 2'd0});
  assign memory_data_o = s_kernel_busy ? s_kernel_memory_data : s_source1_q;
  assign memory_strb_o = s_kernel_busy ? s_kernel_memory_strb : 4'hf;

  always_comb begin
    logic [15:0] s_crc8;
    s_crc8 = (s_opcode == `APB4_APU__MC_BITSTREAM_CRC8) ? {8'd0, source0_i[7:0]} : source0_i[15:0];
    for (int bit_index = 0; bit_index < 8; bit_index++) begin
      if (s_opcode == `APB4_APU__MC_BITSTREAM_CRC8) begin
        s_crc8[7:0] = {s_crc8[6:0], 1'b0} ^ ({8{(s_crc8[7] ^ source1_i[7-bit_index])}} & 8'h07);
      end else begin
        s_crc8 = {s_crc8[14:0], 1'b0} ^ ({16{(s_crc8[15] ^ source1_i[7-bit_index])}} & 16'h8005);
      end
    end
    s_crc_result = (s_opcode == `APB4_APU__MC_BITSTREAM_CRC8) ?
        {24'd0, s_crc8[7:0]} : {16'd0, s_crc8};
  end

  assign s_scratch_end = {16'd0, s_scratch_base_q} + {16'd0, s_scratch_bytes_q};
  assign s_local_end = {16'd0, s_local_addr_q} + {30'd0, s_local_size_q};
  assign s_table_end = {17'd0, s_table_offset_q} + {17'd0, s_table_bytes_q};
  assign s_entropy_table_end = {1'b0, source0_i} + ({1'b0, source1_i} << 2);
  assign s_entropy_range_ok = (source0_i[1:0] == 2'd0) && !s_entropy_table_end[32] &&
      (s_entropy_table_end <= {17'd0, table_bytes_i});
  assign s_local_range_ok = !s_local_addr_overflow_q &&
      ((s_instruction_q[59:56] inside {
    `APB4_APU__MC_LOCAL_TABLE8, `APB4_APU__MC_LOCAL_TABLE16,
      `APB4_APU__MC_LOCAL_TABLE32
      }) ? (({16'd0, s_local_addr_q} >= {17'd0, s_table_offset_q}) && (s_local_end <= s_table_end))
          : (({16'd0, s_local_addr_q} >= {16'd0, s_scratch_base_q}) &&
             (s_local_end <= s_scratch_end)));
  assign s_local_access_ok = s_local_range_ok &&
      ((s_local_size_q == 3'd1) ||
       ((s_local_addr_q & ({14'd0, s_local_size_q} - 17'd1)) == 17'd0));

  always_comb begin
    unique case (s_opcode)
      `APB4_APU__MC_LOCAL_LD32, `APB4_APU__MC_LOCAL_ST32:
      s_local_addr_full = {18'd0, scratch_base_i} + {3'd0, source0_i} +
          {{19{instruction_i[15]}}, instruction_i[15:0]};
      `APB4_APU__MC_LOCAL_TABLE8:
      s_local_addr_full = {19'd0, table_offset_i} + {3'd0, source0_i} + {3'd0, source1_i};
      `APB4_APU__MC_LOCAL_TABLE16:
      s_local_addr_full = {19'd0, table_offset_i} + {3'd0, source0_i} + ({3'd0, source1_i} << 1);
      default:
      s_local_addr_full = {19'd0, table_offset_i} + {3'd0, source0_i} + ({3'd0, source1_i} << 2);
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q               <= Idle;
      s_instruction_q         <= 64'd0;
      s_source0_q             <= 32'd0;
      s_source1_q             <= 32'd0;
      s_scratch_base_q        <= 17'd0;
      s_scratch_bytes_q       <= 17'd0;
      s_table_offset_q        <= 16'd0;
      s_table_bytes_q         <= 16'd0;
      s_frame_skipped_q       <= 16'd0;
      s_local_addr_q          <= 17'd0;
      s_local_lane_q          <= 2'd0;
      s_local_size_q          <= 3'd0;
      s_local_write           <= 1'b0;
      s_local_addr_overflow_q <= 1'b0;
      s_cycles_q              <= 32'd0;
      result_valid_o          <= 1'b0;
      result_dst_o            <= 4'd0;
      result_data_o           <= '0;
      result_words_o          <= 3'd0;
      result_kernel_o         <= 1'b0;
      error_o                 <= 1'b0;
      error_code_o            <= 6'd0;
      error_stage_o           <= 4'd0;
      error_reason_o          <= 8'd0;
      cycles_o                <= 32'd0;
    end else if (flush_i) begin
      s_state_q       <= Idle;
      result_valid_o  <= 1'b0;
      result_kernel_o <= 1'b0;
      error_o         <= 1'b0;
      s_cycles_q      <= 32'd0;
    end else begin
      result_valid_o  <= 1'b0;
      result_kernel_o <= 1'b0;
      error_o         <= 1'b0;
      if (s_kernel_done) begin
        result_valid_o  <= 1'b1;
        result_kernel_o <= 1'b1;
        result_dst_o    <= s_kernel_result_dst;
        result_data_o   <= s_kernel_err ? '0 : {96'd0, s_kernel_result_count};
        result_words_o  <= s_kernel_err ? 3'd0 : 3'd1;
        cycles_o        <= s_kernel_cycles;
        error_o         <= s_kernel_err;
        error_code_o    <= s_kernel_err_code;
        error_stage_o   <= s_kernel_err_stage;
        error_reason_o  <= s_kernel_err_reason;
      end
      if (s_state_q != Idle) s_cycles_q <= s_cycles_q + 1'b1;
      unique case (s_state_q)
        Idle: begin
          if (req_valid_i && req_ready_o && (s_class != `APB4_APU__MC_CLASS_KERNEL)) begin
            s_instruction_q         <= instruction_i;
            s_source0_q             <= source0_i;
            s_source1_q             <= source1_i;
            s_scratch_base_q        <= scratch_base_i;
            s_scratch_bytes_q       <= scratch_bytes_i;
            s_table_offset_q        <= table_offset_i;
            s_table_bytes_q         <= table_bytes_i;
            s_cycles_q              <= 32'd1;
            s_local_addr_overflow_q <= s_local_addr_full[34:17] != 18'd0;
            result_dst_o            <= instruction_i[51:48];
            result_data_o           <= '0;
            result_words_o          <= 3'd0;
            if (s_class == `APB4_APU__MC_CLASS_BITSTREAM) begin
              if (s_opcode == `APB4_APU__MC_BITSTREAM_FRAME_SYNC) begin
                s_frame_skipped_q <= 16'd0;
                s_state_q         <= s_direct_frame_align ? FrameAlignWait : FrameAlignRequest;
              end else if (s_opcode inside {`APB4_APU__MC_BITSTREAM_CRC8,
                                             `APB4_APU__MC_BITSTREAM_CRC16}) begin
                result_valid_o   <= 1'b1;
                result_words_o   <= 3'd1;
                result_data_o[0] <= s_crc_result;
                cycles_o         <= 32'd1;
              end else begin
                s_state_q <= s_direct_bit_req ? BitWait : BitRequest;
              end
            end else if (s_class == `APB4_APU__MC_CLASS_ENTROPY) begin
              if ((s_opcode <= `APB4_APU__MC_ENTROPY_HUFF_QUAD) &&
                  (source1_i >= 32'd1) && (source1_i <= 32'd4096) &&
                  !s_entropy_range_ok) begin
                result_valid_o <= 1'b1;
                result_words_o <= 3'd0;
                error_o        <= 1'b1;
                error_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;
                error_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
                error_reason_o <= 8'd5;
                cycles_o       <= 32'd1;
              end else begin
                s_state_q <= s_direct_entropy_req ? EntropyWait : EntropyRequest;
              end
            end else if (s_opcode == `APB4_APU__MC_LOCAL_FIFO_POP) begin
              result_valid_o   <= 1'b1;
              result_words_o   <= 3'd2;
              result_data_o[0] <= s_input_fifo_data[31:0];
              result_data_o[1] <= {23'd0, s_input_fifo_data[40], 5'd0, s_input_fifo_data[34:32]};
              cycles_o         <= 32'd1;
            end else if (s_opcode == `APB4_APU__MC_LOCAL_FIFO_PUSH) begin
              result_valid_o <= 1'b1;
              result_words_o <= 3'd0;
              cycles_o       <= 32'd1;
              if ((source1_i & ~32'h0000_0107) != 32'd0 ||
                  (source1_i[2:0] == 3'd0) || (source1_i[2:0] > 3'd4)) begin
                error_o        <= 1'b1;
                error_code_o   <= `APB4_APU__ERROR_CODE_OVERFLOW;
                error_stage_o  <= `APB4_APU__ERROR_STAGE_RESAMPLER;
                error_reason_o <= 8'd9;
              end
            end else begin
              s_local_write  <= s_opcode == `APB4_APU__MC_LOCAL_ST32;
              s_local_addr_q <= s_local_addr_full[16:0];
              s_local_lane_q <= s_local_addr_full[1:0];
              unique case (s_opcode)
                `APB4_APU__MC_LOCAL_LD32, `APB4_APU__MC_LOCAL_ST32: begin
                  s_local_size_q <= 3'd4;
                end
                `APB4_APU__MC_LOCAL_TABLE8: begin
                  s_local_size_q <= 3'd1;
                end
                `APB4_APU__MC_LOCAL_TABLE16: begin
                  s_local_size_q <= 3'd2;
                end
                default: begin
                  s_local_size_q <= 3'd4;
                end
              endcase
              s_state_q <= LocalRequest;
            end
          end
        end
        BitRequest: begin
          if (s_bit_req_ready) s_state_q <= BitWait;
        end
        BitWait: begin
          if (s_bit_result_valid) begin
            s_state_q <= Idle;
            result_valid_o <= 1'b1;
            result_words_o <= (s_instruction_q[59:56] inside {`APB4_APU__MC_BITSTREAM_SKIP,
            `APB4_APU__MC_BITSTREAM_ALIGN
            }) ? 3'd0 : 3'd1;
            result_data_o[0] <= s_bit_result_data;
            cycles_o <= (s_instruction_q[59:56] == `APB4_APU__MC_BITSTREAM_REFILL) ? 32'd3 : 32'd1;
            if (s_bit_err && (s_instruction_q[59:56] != `APB4_APU__MC_BITSTREAM_REFILL)) begin
              result_data_o  <= '0;
              result_words_o <= 3'd0;
              error_o        <= 1'b1;
              error_code_o   <= `APB4_APU__ERROR_CODE_TRUNCATED;
              error_stage_o  <= `APB4_APU__ERROR_STAGE_BITSTREAM;
              error_reason_o <= 8'd9;
            end
          end
        end
        FrameAlignRequest: begin
          if (s_bit_req_ready) s_state_q <= FrameAlignWait;
        end
        FrameAlignWait: begin
          if (s_bit_result_valid) begin
            if (s_bit_err) begin
              s_state_q      <= Idle;
              result_valid_o <= 1'b1;
              result_data_o  <= '0;
              result_words_o <= 3'd0;
              error_o        <= 1'b1;
              error_code_o   <= `APB4_APU__ERROR_CODE_TRUNCATED;
              error_stage_o  <= `APB4_APU__ERROR_STAGE_BITSTREAM;
              error_reason_o <= 8'd9;
            end else begin
              s_state_q <= FramePeekWait;
            end
          end
        end
        FramePeekRequest: begin
          if (s_bit_req_ready) s_state_q <= FramePeekWait;
        end
        FramePeekWait: begin
          if (s_bit_result_valid) begin
            if (s_bit_err) begin
              s_state_q      <= Idle;
              result_valid_o <= 1'b1;
              result_data_o  <= '0;
              result_words_o <= 3'd0;
              error_o        <= 1'b1;
              error_code_o   <= `APB4_APU__ERROR_CODE_MALFORMED;
              error_stage_o  <= `APB4_APU__ERROR_STAGE_BITSTREAM;
              error_reason_o <= 8'd9;
              cycles_o       <= 32'd2 + ({16'd0, s_instruction_q[15:0]} << 1);
            end else if (s_frame_match) begin
              s_state_q        <= Idle;
              result_valid_o   <= 1'b1;
              result_words_o   <= 3'd1;
              result_data_o[0] <= {16'd0, s_frame_skipped_q};
              cycles_o         <= 32'd2 + ({16'd0, s_frame_skipped_q} << 1);
            end else if (s_frame_skipped_q >= s_instruction_q[15:0] - 1'b1) begin
              s_state_q      <= Idle;
              result_valid_o <= 1'b1;
              result_data_o  <= '0;
              result_words_o <= 3'd0;
              error_o        <= 1'b1;
              error_code_o   <= `APB4_APU__ERROR_CODE_MALFORMED;
              error_stage_o  <= `APB4_APU__ERROR_STAGE_BITSTREAM;
              error_reason_o <= 8'd9;
              cycles_o       <= 32'd2 + ({16'd0, s_instruction_q[15:0]} << 1);
            end else begin
              s_state_q <= FrameSkipWait;
            end
          end
        end
        FrameSkipRequest: begin
          if (s_bit_req_ready) s_state_q <= FrameSkipWait;
        end
        FrameSkipWait: begin
          if (s_bit_result_valid) begin
            if (s_bit_err) begin
              s_state_q      <= Idle;
              result_valid_o <= 1'b1;
              result_data_o  <= '0;
              result_words_o <= 3'd0;
              error_o        <= 1'b1;
              error_code_o   <= `APB4_APU__ERROR_CODE_MALFORMED;
              error_stage_o  <= `APB4_APU__ERROR_STAGE_BITSTREAM;
              error_reason_o <= 8'd9;
            end else begin
              s_frame_skipped_q <= s_frame_skipped_q + 1'b1;
              s_state_q         <= FramePeekWait;
            end
          end
        end
        EntropyRequest: begin
          if (s_entropy_req_ready) s_state_q <= EntropyWait;
        end
        EntropyWait: begin
          if (s_entropy_result_valid) begin
            s_state_q      <= Idle;
            result_valid_o <= 1'b1;
            result_dst_o   <= s_entropy_result_dst;
            result_data_o  <= s_entropy_result_data;
            result_words_o <= s_entropy_result_words;
            cycles_o       <= s_entropy_cycles;
            if (s_entropy_err) begin
              result_data_o <= '0;
              result_words_o <= 3'd0;
              error_o <= 1'b1;
              error_code_o <= s_entropy_err_code;
              error_stage_o <= s_entropy_err_stage;
              error_reason_o <= (s_entropy_err_code == `APB4_APU__ERROR_CODE_SEQUENCER) ?
                  8'd5 : 8'd9;
            end
          end
        end
        LocalRequest: begin
          if (!s_local_access_ok) begin
            s_state_q      <= Idle;
            result_valid_o <= 1'b1;
            result_data_o  <= '0;
            result_words_o <= 3'd0;
            error_o        <= 1'b1;
            error_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;
            error_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
            error_reason_o <= 8'd5;
            cycles_o       <= 32'd1;
          end else if (s_local_write) begin
            s_state_q      <= Idle;
            result_valid_o <= 1'b1;
            result_words_o <= 3'd0;
            cycles_o       <= 32'd1;
          end else begin
            s_state_q <= LocalWait;
          end
        end
        LocalWait: begin
          if (memory_error_i) begin
            s_state_q      <= Idle;
            result_valid_o <= 1'b1;
            result_data_o  <= '0;
            result_words_o <= 3'd0;
            error_o        <= 1'b1;
            error_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;
            error_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
            error_reason_o <= 8'd5;
            cycles_o       <= 32'd2;
          end else if (memory_valid_i) begin
            s_state_q      <= Idle;
            result_valid_o <= 1'b1;
            result_words_o <= 3'd1;
            cycles_o       <= 32'd2;
            unique case (s_local_size_q)
              3'd1:    result_data_o[0] <= {24'd0, memory_data_i[s_local_lane_q*8+:8]};
              3'd2:    result_data_o[0] <= {16'd0, memory_data_i[s_local_lane_q[1]*16+:16]};
              default: result_data_o[0] <= memory_data_i;
            endcase
          end
        end
        default: s_state_q <= Idle;
      endcase
    end
  end

  logic s_unused;
  assign s_unused = s_reservoir_eof ^ ^s_available_bits ^ ^s_input_count ^ ^s_output_count ^
      ^s_instruction_q[63:60] ^ ^s_instruction_q[55:40] ^ ^s_immediate[31:16];
endmodule
