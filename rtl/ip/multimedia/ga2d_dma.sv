// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "ga2d_define.svh"
module ga2d_dma (
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 clear_i,
    input  logic                 start_i,
    input  logic                 stop_i,
    input  logic                 fill_i,
    input  logic          [15:0] width_i,
    input  logic          [15:0] height_i,
    input  logic          [ 2:0] bytes_per_pixel_i,
    input  logic          [31:0] foreground_address_i,
    input  logic          [31:0] foreground_pitch_i,
    input  logic          [31:0] destination_address_i,
    input  logic          [31:0] destination_pitch_i,
    input  logic          [31:0] fill_pixel_i,
    output logic                 busy_o,
    output logic                 draining_o,
    output logic                 idle_o,
    output logic                 done_o,
    output logic                 aborted_o,
    output logic                 error_valid_o,
    output logic          [ 6:0] error_code_o,
    output logic          [ 3:0] error_stage_o,
    output logic          [ 1:0] error_response_o,
    output logic          [31:0] error_address_o,
    output logic                 progress_o,
    output logic          [ 7:0] read_bytes_o,
    output logic          [ 7:0] write_bytes_o,
    output logic                 line_done_o,
    output logic                 read_stall_o,
    output logic                 write_stall_o,
    output logic                 pipe_stall_o,
           axi4_if.master        axi4
);
  typedef enum logic [3:0] {
    Idle,
    FillPlan,
    FillPrepare,
    CopyPlanWrite,
    CopyPlanRead,
    CopyReadRequest,
    CopyReadReceive,
    CopyTransform,
    WriteRequest,
    WriteWait,
    Drain
  } state_e;

  state_e        s_state_q;
  logic          s_stop_pending_q;
  logic          s_fill_q;
  logic   [15:0] s_height_q;
  logic   [ 2:0] s_bytes_per_pixel_q;
  logic   [31:0] s_foreground_addr_q;
  logic   [31:0] s_foreground_pitch_q;
  logic   [31:0] s_destination_addr_q;
  logic   [31:0] s_destination_pitch_q;
  logic   [31:0] s_fill_pixel_q;
  logic   [31:0] s_row_bytes_q;
  logic   [15:0] s_row_index_q;
  logic   [31:0] s_row_byte_q;
  logic   [31:0] s_write_burst_addr_q;
  logic   [ 4:0] s_write_burst_beats_q;
  logic   [ 7:0] s_write_burst_bytes_q;
  logic          s_write_ends_row_q;
  logic   [ 4:0] s_fill_prepare_beat_q;
  logic   [ 7:0] s_copy_bytes_staged_q;
  logic   [63:0] s_copy_build_data_q;
  logic   [ 7:0] s_copy_build_strobe_q;
  logic          s_read_reserved_q;
  logic          s_rd_cmd_owned_q;
  logic   [ 4:0] s_read_beats_q;
  logic   [ 3:0] s_read_word_bytes_q;
  logic   [ 3:0] s_read_word_bytes_left_q;
  logic   [ 4:0] s_read_words_left_q;
  logic   [ 2:0] s_read_word_lane_q;
  logic          s_read_full_q;
  logic          s_read_err_seen_q;
  logic          s_write_reserved_q;
  logic   [ 4:0] s_write_reserved_beats_q;
  logic   [ 7:0] s_write_reserved_bytes_q;
  logic   [ 7:0] s_write_inflight_bytes_q;
  logic          s_wr_cmd_owned_q;
  logic   [ 4:0] s_output_strobe_wr_q;
  logic   [ 4:0] s_output_strobe_rd_q;
  logic   [ 7:0] s_output_strobe_mem        [0:31];
  logic          s_done_q;
  logic          s_aborted_q;
  logic          s_err_seen_q;
  logic          s_err_valid_q;
  logic   [ 6:0] s_err_code_q;
  logic   [ 3:0] s_err_stage_q;
  logic   [ 1:0] s_err_rsp_q;
  logic   [31:0] s_err_addr_q;
  logic   [31:0] s_source_byte_addr;
  logic   [31:0] s_destination_byte_addr;
  logic   [31:0] s_row_remaining;
  logic   [31:0] s_write_plan_addr;
  logic   [ 4:0] s_write_plan_beats;
  logic   [ 7:0] s_write_plan_bytes;
  logic          s_write_plan_ends_row;
  logic   [31:0] s_copy_source_addr;
  logic   [31:0] s_copy_read_remaining;
  logic   [ 4:0] s_read_plan_beats;
  logic   [ 3:0] s_read_plan_word_bytes;
  logic   [ 2:0] s_read_plan_size;
  logic   [ 2:0] s_read_plan_lane;
  logic          s_read_plan_full;
  logic   [ 3:0] s_addr_read_bytes;
  logic   [ 2:0] s_addr_read_size;
  logic          s_fg_fifo_full;
  logic          s_fg_fifo_empty;
  logic   [63:0] s_fg_fifo_data;
  logic   [ 5:0] s_fg_fifo_count;
  logic   [ 5:0] unused_fg_fifo_count;
  logic          unused_bg_fifo_full;
  logic          unused_bg_fifo_empty;
  logic   [63:0] unused_bg_fifo_data;
  logic   [ 5:0] unused_bg_fifo_count;
  logic          s_output_fifo_full;
  logic          s_output_fifo_empty;
  logic   [63:0] s_output_fifo_data;
  logic   [ 5:0] s_output_fifo_count;
  logic   [ 5:0] unused_output_fifo_count;
  logic          s_fg_fifo_push;
  logic          s_fg_fifo_pop;
  logic          s_output_fifo_push;
  logic          s_output_fifo_pop;
  logic   [63:0] s_output_push_data;
  logic   [ 7:0] s_output_push_strobe;
  logic          s_read_req_valid;
  logic          unused_read_req_ready;
  logic          s_read_req_accept;
  logic          s_rd_ar_presented;
  logic          s_rd_req_cancel;
  logic          s_read_rsp_valid;
  logic          s_read_rsp_ready;
  logic   [63:0] s_read_data;
  logic   [ 1:0] s_read_rsp;
  logic          s_read_protocol_err;
  logic          s_read_rsp_terminal;
  logic   [31:0] s_read_rsp_addr;
  logic          s_write_req_valid;
  logic          s_write_req_accept;
  logic          s_wr_aw_presented;
  logic          s_write_req_cancel;
  logic   [ 4:0] s_write_req_beats;
  logic          s_write_payload_accept;
  logic          s_write_rsp_valid;
  logic          s_write_rsp_ready;
  logic   [ 1:0] s_write_rsp;
  logic          s_write_protocol_err;
  logic   [31:0] s_write_rsp_addr;
  logic          s_master_read_busy;
  logic          s_master_write_busy;
  logic          s_master_idle;
  logic          s_master_read_stall;
  logic          s_master_write_stall;
  logic          s_read_rsp_accept;
  logic          s_read_rsp_err;
  logic          s_write_rsp_accept;
  logic          s_write_rsp_err;
  logic          s_fill_prepare_fire;
  logic          s_copy_transform_fire;
  logic          s_copy_transform_end_word;
  logic          s_copy_transform_end_read;
  logic          s_copy_transform_end_burst;
  logic   [ 2:0] s_copy_destination_lane;
  logic   [ 7:0] s_copy_byte;
  logic   [63:0] s_copy_build_data_next;
  logic   [ 7:0] s_copy_build_strobe_next;
  logic   [63:0] s_fill_push_data;
  logic   [ 7:0] s_fill_push_strobe;
  logic          s_fill_valid_lane;
  logic   [31:0] s_fill_byte_index;
  logic   [ 7:0] s_fill_byte;
  logic   [31:0] unused_addr_write_address;
  logic   [63:0] unused_addr_write_data;
  logic   [ 7:0] unused_addr_write_strobe;
  logic          unused_write_req_ready;

  function automatic logic [7:0] fill_byte_at(input logic [31:0] pixel_i, input logic [2:0] bytes_i,
                                              input logic [31:0] index_i);
    logic [ 1:0] s_lane;
    logic [31:0] s_remainder;
    begin
      unique case (bytes_i)
        3'd2:    s_lane = {1'b0, index_i[0]};
        3'd3: begin
          s_remainder = index_i % 32'd3;
          unique case (s_remainder)
            32'd0:   s_lane = 2'd0;
            32'd1:   s_lane = 2'd1;
            default: s_lane = 2'd2;
          endcase
        end
        default: s_lane = index_i[1:0];
      endcase
      return pixel_i[s_lane*8+:8];
    end
  endfunction

  assign s_source_byte_addr = s_foreground_addr_q +
      (s_row_index_q * s_foreground_pitch_q) + s_row_byte_q;
  assign s_destination_byte_addr = s_destination_addr_q +
      (s_row_index_q * s_destination_pitch_q) + s_row_byte_q;
  assign s_row_remaining = s_row_bytes_q - s_row_byte_q;
  assign s_copy_source_addr = s_source_byte_addr + {24'd0, s_copy_bytes_staged_q};
  assign s_copy_read_remaining = {24'd0, s_write_burst_bytes_q} - {24'd0, s_copy_bytes_staged_q};

  ga2d_addr_gen u_addr_gen (
      .read_address_lsb_i(s_copy_source_addr[2:0]),
      .read_remaining_i  (s_copy_read_remaining),
      .write_address_i   (32'd0),
      .write_byte_i      (8'd0),
      .read_bytes_o      (s_addr_read_bytes),
      .read_size_o       (s_addr_read_size),
      .write_address_o   (unused_addr_write_address),
      .write_data_o      (unused_addr_write_data),
      .write_strobe_o    (unused_addr_write_strobe)
  );

  always_comb begin
    logic [12:0] s_bytes_to_4k;
    logic [12:0] s_beats_to_4k;
    logic [31:0] s_full_beats;
    s_bytes_to_4k      = '0;
    s_beats_to_4k      = '0;
    s_full_beats       = '0;
    s_write_plan_addr  = {s_destination_byte_addr[31:3], 3'b000};
    s_bytes_to_4k      = 13'd4096 - {1'b0, s_write_plan_addr[11:0]};
    s_beats_to_4k      = s_bytes_to_4k >> 3;
    s_full_beats       = s_row_remaining >> 3;
    s_write_plan_beats = 5'd1;
    s_write_plan_bytes = s_row_remaining[7:0];
    if (s_destination_byte_addr[2:0] != 3'd0) begin
      if (s_row_remaining < (32'd8 - {29'd0, s_destination_byte_addr[2:0]})) begin
        s_write_plan_bytes = s_row_remaining[7:0];
      end else begin
        s_write_plan_bytes = 8'd8 - {5'd0, s_destination_byte_addr[2:0]};
      end
    end else if (s_row_remaining >= 32'd8) begin
      if (s_full_beats > 5'd16) begin
        s_write_plan_beats = 5'd16;
      end else begin
        s_write_plan_beats = s_full_beats[4:0];
      end
      if (s_beats_to_4k < {8'd0, s_write_plan_beats}) begin
        s_write_plan_beats = s_beats_to_4k[4:0];
      end
      s_write_plan_bytes = {s_write_plan_beats, 3'b000};
    end
    s_write_plan_ends_row = {24'd0, s_write_plan_bytes} == s_row_remaining;
  end

  always_comb begin
    logic [12:0] s_bytes_to_4k;
    logic [12:0] s_beats_to_4k;
    logic [31:0] s_full_beats;
    s_bytes_to_4k          = '0;
    s_beats_to_4k          = '0;
    s_full_beats           = '0;
    s_read_plan_beats      = 5'd1;
    s_read_plan_word_bytes = s_addr_read_bytes;
    s_read_plan_size       = s_addr_read_size;
    s_read_plan_lane       = s_copy_source_addr[2:0];
    s_read_plan_full       = 1'b0;
    if ((s_copy_source_addr[2:0] == 3'd0) && (s_copy_read_remaining >= 32'd8)) begin
      s_bytes_to_4k = 13'd4096 - {1'b0, s_copy_source_addr[11:0]};
      s_beats_to_4k = s_bytes_to_4k >> 3;
      s_full_beats  = s_copy_read_remaining >> 3;
      if (s_full_beats > 5'd16) begin
        s_read_plan_beats = 5'd16;
      end else begin
        s_read_plan_beats = s_full_beats[4:0];
      end
      if (s_beats_to_4k < {8'd0, s_read_plan_beats}) begin
        s_read_plan_beats = s_beats_to_4k[4:0];
      end
      s_read_plan_word_bytes = 4'd8;
      s_read_plan_size       = 3'd3;
      s_read_plan_lane       = 3'd0;
      s_read_plan_full       = 1'b1;
    end
  end

  always_comb begin
    s_fill_push_data   = '0;
    s_fill_push_strobe = '0;
    for (int unsigned lane = 0; lane < 8; lane++) begin
      s_fill_byte_index = ({27'd0, s_fill_prepare_beat_q} << 3) +
                          {29'd0, lane[2:0]} -
                          {29'd0, s_destination_byte_addr[2:0]};
      s_fill_valid_lane = (lane >= s_destination_byte_addr[2:0]) &&
                          (s_fill_byte_index < s_write_burst_bytes_q);
      s_fill_byte =
          fill_byte_at(s_fill_pixel_q, s_bytes_per_pixel_q, s_row_byte_q + s_fill_byte_index);
      if (s_fill_valid_lane) begin
        s_fill_push_data[lane*8+:8] = s_fill_byte;
        s_fill_push_strobe[lane]    = 1'b1;
      end
    end
  end

  assign s_copy_destination_lane = s_destination_byte_addr[2:0] + s_copy_bytes_staged_q[2:0];
  assign s_copy_byte = s_fg_fifo_data[s_read_word_lane_q*8+:8];
  assign s_copy_build_data_next = s_copy_build_data_q |
      ({56'd0, s_copy_byte} << {s_copy_destination_lane, 3'b000});
  assign s_copy_build_strobe_next = s_copy_build_strobe_q |
      (8'b0000_0001 << s_copy_destination_lane);
  assign s_copy_transform_end_word = (s_copy_destination_lane == 3'd7) ||
                                     ((s_copy_bytes_staged_q + 1'b1) ==
                                      s_write_burst_bytes_q);
  assign s_copy_transform_end_read = (s_read_word_bytes_left_q == 4'd1) &&
                                     (s_read_words_left_q == 5'd1);
  assign s_copy_transform_end_burst = (s_copy_bytes_staged_q + 1'b1) == s_write_burst_bytes_q;
  assign s_copy_transform_fire = (s_state_q == CopyTransform) && !s_fg_fifo_empty &&
                                 !s_output_fifo_full && !stop_i;
  assign s_fill_prepare_fire = (s_state_q == FillPrepare) && !s_output_fifo_full && !stop_i;

  assign s_output_fifo_push = s_fill_prepare_fire ||
                              (s_copy_transform_fire && s_copy_transform_end_word);
  assign s_output_push_data = s_fill_prepare_fire ? s_fill_push_data : s_copy_build_data_next;
  assign s_output_push_strobe = s_fill_prepare_fire ? s_fill_push_strobe : s_copy_build_strobe_next;
  assign s_output_fifo_pop = s_write_payload_accept ||
                             ((s_state_q == Drain) && !s_output_fifo_empty &&
                              !s_master_write_busy);
  assign s_fg_fifo_push = (s_state_q == CopyReadReceive) && s_read_rsp_accept && !s_read_rsp_err;
  assign s_fg_fifo_pop = (s_copy_transform_fire && (s_read_word_bytes_left_q == 4'd1)) ||
                         ((s_state_q == Drain) && !s_fg_fifo_empty);

  fifo #(
      .DATA_WIDTH      (64),
      .BUFFER_DEPTH    (32),
      .LOG_BUFFER_DEPTH(5)
  ) u_foreground_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(clear_i),
      .push_i (s_fg_fifo_push),
      .full_o (s_fg_fifo_full),
      .dat_i  (s_read_data),
      .pop_i  (s_fg_fifo_pop),
      .empty_o(s_fg_fifo_empty),
      .dat_o  (s_fg_fifo_data),
      .cnt_o  (s_fg_fifo_count)
  );
  fifo #(
      .DATA_WIDTH      (64),
      .BUFFER_DEPTH    (32),
      .LOG_BUFFER_DEPTH(5)
  ) u_background_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(clear_i),
      .push_i (1'b0),
      .full_o (unused_bg_fifo_full),
      .dat_i  ('0),
      .pop_i  (1'b0),
      .empty_o(unused_bg_fifo_empty),
      .dat_o  (unused_bg_fifo_data),
      .cnt_o  (unused_bg_fifo_count)
  );
  fifo #(
      .DATA_WIDTH      (64),
      .BUFFER_DEPTH    (32),
      .LOG_BUFFER_DEPTH(5)
  ) u_output_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(clear_i),
      .push_i (s_output_fifo_push),
      .full_o (s_output_fifo_full),
      .dat_i  (s_output_push_data),
      .pop_i  (s_output_fifo_pop),
      .empty_o(s_output_fifo_empty),
      .dat_o  (s_output_fifo_data),
      .cnt_o  (s_output_fifo_count)
  );

  // Stable formal observation aliases for the three P4 payload FIFO counts.
  assign unused_fg_fifo_count = s_fg_fifo_count;
  assign unused_output_fifo_count = s_output_fifo_count;

  assign s_read_req_valid = (s_state_q == CopyReadRequest) && s_read_reserved_q && !stop_i;
  assign s_read_rsp_ready = s_state_q == CopyReadReceive;
  assign s_read_rsp_accept = s_read_rsp_valid && s_read_rsp_ready;
  assign s_read_rsp_err = s_read_protocol_err || (s_read_rsp != 2'd0);
  assign s_write_req_beats = s_write_reserved_beats_q;
  assign s_write_req_valid = (s_state_q == WriteRequest) && !stop_i &&
                             s_write_reserved_q &&
                             (s_output_fifo_count >= {1'b0, s_write_req_beats}) &&
                             (s_write_req_beats != 5'd0);
  assign s_write_rsp_ready = s_state_q == WriteWait;
  assign s_write_rsp_accept = s_write_rsp_valid && s_write_rsp_ready;
  assign s_write_rsp_err = s_write_protocol_err || (s_write_rsp != 2'd0);

  assign busy_o = s_state_q != Idle;
  assign draining_o = s_stop_pending_q && (s_state_q != Idle);
  assign idle_o = (s_state_q == Idle) && s_master_idle && !s_master_read_busy &&
                  !s_master_write_busy && s_fg_fifo_empty && s_output_fifo_empty &&
                  !s_read_reserved_q && !s_rd_cmd_owned_q && !s_write_reserved_q &&
                  !s_wr_cmd_owned_q;
  assign done_o = s_done_q;
  assign aborted_o = s_aborted_q;
  assign error_valid_o = s_err_valid_q;
  assign error_code_o = s_err_code_q;
  assign error_stage_o = s_err_stage_q;
  assign error_response_o = s_err_rsp_q;
  assign error_address_o = s_err_addr_q;
  assign progress_o = s_read_req_accept || s_read_rsp_accept || s_write_req_accept ||
                      s_write_payload_accept || s_write_rsp_accept || s_output_fifo_push ||
                      s_copy_transform_fire;
  assign read_bytes_o = (s_read_rsp_accept && !s_read_rsp_err) ?
                        (s_read_full_q ? 8'd8 : {4'd0, s_read_word_bytes_q}) : 8'd0;
  assign write_bytes_o = (s_write_rsp_accept && !s_write_rsp_err) ? s_write_inflight_bytes_q : 8'd0;
  assign line_done_o = s_write_rsp_accept && !s_write_rsp_err && s_write_ends_row_q;
  assign read_stall_o = s_master_read_stall;
  assign write_stall_o = s_master_write_stall;
  assign pipe_stall_o = ((s_state_q == FillPrepare) && s_output_fifo_full) ||
                        ((s_state_q == CopyPlanRead) && s_fg_fifo_full) ||
                        ((s_state_q == CopyTransform) &&
                         (s_fg_fifo_empty || s_output_fifo_full)) ||
                        ((s_state_q == WriteRequest) && !unused_write_req_ready);

  ga2d_axi4_master u_axi4_master (
      .clk_i                    (clk_i),
      .rst_n_i                  (rst_n_i),
      .clear_i                  (clear_i),
      .read_request_valid_i     (s_read_req_valid),
      .read_request_ready_o     (unused_read_req_ready),
      .read_address_i           (s_copy_source_addr),
      .read_size_i              (s_read_plan_size),
      .read_beats_i             (s_read_beats_q),
      .read_stop_i              (stop_i),
      .read_request_accept_o    (s_read_req_accept),
      .read_address_presented_o (s_rd_ar_presented),
      .read_request_cancel_o    (s_rd_req_cancel),
      .read_response_valid_o    (s_read_rsp_valid),
      .read_response_ready_i    (s_read_rsp_ready),
      .read_data_o              (s_read_data),
      .read_response_o          (s_read_rsp),
      .read_protocol_error_o    (s_read_protocol_err),
      .read_response_terminal_o (s_read_rsp_terminal),
      .read_response_address_o  (s_read_rsp_addr),
      .write_request_valid_i    (s_write_req_valid),
      .write_request_ready_o    (unused_write_req_ready),
      .write_address_i          (s_write_burst_addr_q),
      .write_beats_i            (s_write_req_beats),
      .write_stop_i             (stop_i),
      .write_request_accept_o   (s_write_req_accept),
      .write_address_presented_o(s_wr_aw_presented),
      .write_request_cancel_o   (s_write_req_cancel),
      .write_payload_valid_i    (!s_output_fifo_empty),
      .write_data_i             (s_output_fifo_data),
      .write_strobe_i           (s_output_strobe_mem[s_output_strobe_rd_q]),
      .write_payload_accept_o   (s_write_payload_accept),
      .write_response_valid_o   (s_write_rsp_valid),
      .write_response_ready_i   (s_write_rsp_ready),
      .write_response_o         (s_write_rsp),
      .write_protocol_error_o   (s_write_protocol_err),
      .write_response_address_o (s_write_rsp_addr),
      .read_busy_o              (s_master_read_busy),
      .write_busy_o             (s_master_write_busy),
      .idle_o                   (s_master_idle),
      .read_stall_o             (s_master_read_stall),
      .write_stall_o            (s_master_write_stall),
      .axi4                     (axi4)
  );

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_output_strobe_wr_q <= '0;
      s_output_strobe_rd_q <= '0;
    end else if (clear_i) begin
      s_output_strobe_wr_q <= '0;
      s_output_strobe_rd_q <= '0;
    end else begin
      if (s_output_fifo_push) begin
        s_output_strobe_mem[s_output_strobe_wr_q] <= s_output_push_strobe;
        s_output_strobe_wr_q                      <= s_output_strobe_wr_q + 1'b1;
      end
      if (s_output_fifo_pop) begin
        s_output_strobe_rd_q <= s_output_strobe_rd_q + 1'b1;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q                <= Idle;
      s_stop_pending_q         <= 1'b0;
      s_fill_q                 <= 1'b0;
      s_height_q               <= '0;
      s_bytes_per_pixel_q      <= '0;
      s_foreground_addr_q      <= '0;
      s_foreground_pitch_q     <= '0;
      s_destination_addr_q     <= '0;
      s_destination_pitch_q    <= '0;
      s_fill_pixel_q           <= '0;
      s_row_bytes_q            <= '0;
      s_row_index_q            <= '0;
      s_row_byte_q             <= '0;
      s_write_burst_addr_q     <= '0;
      s_write_burst_beats_q    <= '0;
      s_write_burst_bytes_q    <= '0;
      s_write_ends_row_q       <= 1'b0;
      s_fill_prepare_beat_q    <= '0;
      s_copy_bytes_staged_q    <= '0;
      s_copy_build_data_q      <= '0;
      s_copy_build_strobe_q    <= '0;
      s_read_reserved_q        <= 1'b0;
      s_rd_cmd_owned_q         <= 1'b0;
      s_read_beats_q           <= '0;
      s_read_word_bytes_q      <= '0;
      s_read_word_bytes_left_q <= '0;
      s_read_words_left_q      <= '0;
      s_read_word_lane_q       <= '0;
      s_read_full_q            <= 1'b0;
      s_read_err_seen_q        <= 1'b0;
      s_write_reserved_q       <= 1'b0;
      s_write_reserved_beats_q <= '0;
      s_write_reserved_bytes_q <= '0;
      s_write_inflight_bytes_q <= '0;
      s_wr_cmd_owned_q         <= 1'b0;
      s_done_q                 <= 1'b0;
      s_aborted_q              <= 1'b0;
      s_err_seen_q             <= 1'b0;
      s_err_valid_q            <= 1'b0;
      s_err_code_q             <= '0;
      s_err_stage_q            <= '0;
      s_err_rsp_q              <= '0;
      s_err_addr_q             <= '0;
    end else if (clear_i) begin
      s_state_q                <= Idle;
      s_stop_pending_q         <= 1'b0;
      s_read_reserved_q        <= 1'b0;
      s_rd_cmd_owned_q         <= 1'b0;
      s_write_reserved_q       <= 1'b0;
      s_write_reserved_beats_q <= '0;
      s_write_reserved_bytes_q <= '0;
      s_wr_cmd_owned_q         <= 1'b0;
      s_done_q                 <= 1'b0;
      s_aborted_q              <= 1'b0;
      s_err_seen_q             <= 1'b0;
      s_err_valid_q            <= 1'b0;
    end else begin
      s_done_q      <= 1'b0;
      s_aborted_q   <= 1'b0;
      s_err_valid_q <= 1'b0;
      if (stop_i && (s_state_q != Idle)) begin
        s_stop_pending_q <= 1'b1;
      end

      unique case (s_state_q)
        Idle: begin
          s_stop_pending_q         <= 1'b0;
          s_read_reserved_q        <= 1'b0;
          s_rd_cmd_owned_q         <= 1'b0;
          s_write_reserved_q       <= 1'b0;
          s_write_reserved_beats_q <= '0;
          s_write_reserved_bytes_q <= '0;
          s_wr_cmd_owned_q         <= 1'b0;
          s_err_seen_q             <= 1'b0;
          if (start_i && !stop_i) begin
            s_fill_q              <= fill_i;
            s_height_q            <= height_i;
            s_bytes_per_pixel_q   <= bytes_per_pixel_i;
            s_foreground_addr_q   <= foreground_address_i;
            s_foreground_pitch_q  <= foreground_pitch_i;
            s_destination_addr_q  <= destination_address_i;
            s_destination_pitch_q <= destination_pitch_i;
            s_fill_pixel_q        <= fill_pixel_i;
            s_row_bytes_q         <= width_i * bytes_per_pixel_i;
            s_row_index_q         <= '0;
            s_row_byte_q          <= '0;
            s_state_q             <= fill_i ? FillPlan : CopyPlanWrite;
          end
        end
        FillPlan, CopyPlanWrite: begin
          if (stop_i) begin
            s_state_q <= Drain;
          end else begin
            s_write_burst_addr_q  <= s_write_plan_addr;
            s_write_burst_beats_q <= s_write_plan_beats;
            s_write_burst_bytes_q <= s_write_plan_bytes;
            s_write_ends_row_q    <= s_write_plan_ends_row;
            s_fill_prepare_beat_q <= '0;
            s_copy_bytes_staged_q <= '0;
            s_copy_build_data_q   <= '0;
            s_copy_build_strobe_q <= '0;
            s_state_q             <= (s_state_q == FillPlan) ? FillPrepare : CopyPlanRead;
          end
        end
        FillPrepare: begin
          if (stop_i) begin
            s_state_q <= Drain;
          end else if (s_fill_prepare_fire) begin
            if (s_fill_prepare_beat_q == (s_write_burst_beats_q - 1'b1)) begin
              s_write_reserved_q       <= 1'b1;
              s_write_reserved_beats_q <= s_write_burst_beats_q;
              s_write_reserved_bytes_q <= s_write_burst_bytes_q;
              s_state_q                <= WriteRequest;
            end else begin
              s_fill_prepare_beat_q <= s_fill_prepare_beat_q + 1'b1;
            end
          end
        end
        CopyPlanRead: begin
          if (stop_i) begin
            s_state_q <= Drain;
          end else if (!s_fg_fifo_full && ((s_fg_fifo_count + s_read_plan_beats) <= 6'd32)) begin
            s_read_beats_q      <= s_read_plan_beats;
            s_read_word_bytes_q <= s_read_plan_word_bytes;
            s_read_word_lane_q  <= s_read_plan_lane;
            s_read_full_q       <= s_read_plan_full;
            s_read_reserved_q   <= 1'b1;
            s_read_err_seen_q   <= 1'b0;
            s_state_q           <= CopyReadRequest;
          end
        end
        CopyReadRequest: begin
          if (stop_i) begin
            s_read_reserved_q <= 1'b0;
            s_state_q         <= Drain;
          end else if (s_read_req_accept) begin
            s_rd_cmd_owned_q <= 1'b1;
            s_state_q        <= CopyReadReceive;
          end
        end
        CopyReadReceive: begin
          if (s_rd_req_cancel && s_rd_cmd_owned_q && !s_rd_ar_presented) begin
            s_rd_cmd_owned_q <= 1'b0;
            s_state_q        <= Drain;
          end else if (s_read_rsp_accept) begin
            if (s_read_rsp_err && !s_err_seen_q) begin
              s_err_seen_q <= 1'b1;
              s_err_valid_q <= 1'b1;
              s_err_code_q <= s_read_protocol_err ? `APB4_GA2D__ERROR_AXI_PROTOCOL :
                                                     `APB4_GA2D__ERROR_AXI_READ;
              s_err_stage_q <= `APB4_GA2D__ERROR_STAGE_FOREGROUND;
              s_err_rsp_q <= s_read_protocol_err ? 2'd0 : s_read_rsp;
              s_err_addr_q <= s_read_rsp_addr;
            end
            if (s_read_protocol_err) begin
              // The AXI owner remains live until the existing bridge clear/epoch
              // boundary contains a malformed response and any late residual beat.
              s_state_q <= Drain;
            end else if (s_read_rsp_terminal) begin
              s_read_reserved_q <= 1'b0;
              s_rd_cmd_owned_q  <= 1'b0;
              if (s_read_err_seen_q || s_read_rsp_err || stop_i) begin
                s_state_q <= Drain;
              end else begin
                s_read_words_left_q      <= s_read_beats_q;
                s_read_word_bytes_left_q <= s_read_word_bytes_q;
                s_state_q                <= CopyTransform;
              end
            end
            if (s_read_rsp_err) begin
              s_read_err_seen_q <= 1'b1;
            end
          end
        end
        CopyTransform: begin
          if (stop_i) begin
            s_state_q <= Drain;
          end else if (s_copy_transform_fire) begin
            s_copy_bytes_staged_q <= s_copy_bytes_staged_q + 1'b1;
            if (s_copy_transform_end_word) begin
              s_copy_build_data_q   <= '0;
              s_copy_build_strobe_q <= '0;
            end else begin
              s_copy_build_data_q   <= s_copy_build_data_next;
              s_copy_build_strobe_q <= s_copy_build_strobe_next;
            end
            if (s_read_word_bytes_left_q == 4'd1) begin
              s_read_words_left_q <= s_read_words_left_q - 1'b1;
              if (s_read_words_left_q != 5'd1) begin
                s_read_word_bytes_left_q <= s_read_full_q ? 4'd8 : s_read_word_bytes_q;
                s_read_word_lane_q       <= s_read_full_q ? 3'd0 : s_read_word_lane_q;
              end
            end else begin
              s_read_word_bytes_left_q <= s_read_word_bytes_left_q - 1'b1;
              s_read_word_lane_q       <= s_read_word_lane_q + 1'b1;
            end
            if (s_copy_transform_end_read) begin
              if (s_copy_transform_end_burst) begin
                s_write_reserved_q       <= 1'b1;
                s_write_reserved_beats_q <= s_write_burst_beats_q;
                s_write_reserved_bytes_q <= s_write_burst_bytes_q;
                s_state_q                <= WriteRequest;
              end else begin
                s_state_q <= CopyPlanRead;
              end
            end
          end
        end
        WriteRequest: begin
          if (stop_i) begin
            s_state_q <= Drain;
          end else if (s_write_req_accept) begin
            s_write_inflight_bytes_q <= s_write_reserved_bytes_q;
            s_wr_cmd_owned_q         <= 1'b1;
            s_state_q                <= WriteWait;
          end
        end
        WriteWait: begin
          if (s_write_req_cancel && s_wr_cmd_owned_q && !s_wr_aw_presented) begin
            s_wr_cmd_owned_q <= 1'b0;
            s_state_q        <= Drain;
          end else if (s_write_rsp_accept) begin
            if (s_write_rsp_err && !s_err_seen_q) begin
              s_err_seen_q <= 1'b1;
              s_err_valid_q <= 1'b1;
              s_err_code_q <= s_write_protocol_err ? `APB4_GA2D__ERROR_AXI_PROTOCOL :
                                                       `APB4_GA2D__ERROR_AXI_WRITE;
              s_err_stage_q <= `APB4_GA2D__ERROR_STAGE_DESTINATION;
              s_err_rsp_q <= s_write_protocol_err ? 2'd0 : s_write_rsp;
              s_err_addr_q <= s_write_rsp_addr;
            end
            if (s_write_protocol_err) begin
              // Do not release the write reservation or owner on a malformed B.
              // clear_i is the only safe containment boundary for local ID 0.
              s_state_q <= Drain;
            end else begin
              s_wr_cmd_owned_q         <= 1'b0;
              s_write_reserved_q       <= 1'b0;
              s_write_reserved_beats_q <= '0;
              s_write_reserved_bytes_q <= '0;
              if (s_write_rsp_err || stop_i) begin
                s_state_q <= Drain;
              end else if (s_write_ends_row_q) begin
                s_row_byte_q <= '0;
                if (s_row_index_q == (s_height_q - 1'b1)) begin
                  s_done_q  <= 1'b1;
                  s_state_q <= Idle;
                end else begin
                  s_row_index_q <= s_row_index_q + 1'b1;
                  s_state_q     <= s_fill_q ? FillPlan : CopyPlanWrite;
                end
              end else begin
                s_row_byte_q <= s_row_byte_q + {24'd0, s_write_burst_bytes_q};
                s_state_q    <= s_fill_q ? FillPlan : CopyPlanWrite;
              end
            end
          end
        end
        Drain: begin
          if (!s_fg_fifo_empty || !s_output_fifo_empty) begin
            s_state_q <= Drain;
          end else if (s_master_idle) begin
            s_state_q                <= Idle;
            s_aborted_q              <= 1'b1;
            s_read_reserved_q        <= 1'b0;
            s_write_reserved_q       <= 1'b0;
            s_write_reserved_beats_q <= '0;
            s_write_reserved_bytes_q <= '0;
          end
        end
        default: begin
          s_state_q        <= Drain;
          s_stop_pending_q <= 1'b1;
          if (!s_err_seen_q) begin
            s_err_seen_q  <= 1'b1;
            s_err_valid_q <= 1'b1;
            s_err_code_q  <= `APB4_GA2D__ERROR_INTERNAL;
            s_err_stage_q <= `APB4_GA2D__ERROR_STAGE_LIFECYCLE;
            s_err_rsp_q   <= '0;
            s_err_addr_q  <= '0;
          end
        end
      endcase
    end
  end
endmodule
