// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "ga2d_define.svh"

module ga2d_dma (
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 clear_i,
    input  logic                 start_i,
    input  logic                 stop_i,
    input  logic          [ 1:0] operation_i,
    input  logic          [15:0] width_i,
    input  logic          [15:0] height_i,
    input  logic          [ 2:0] foreground_format_i,
    input  logic          [31:0] foreground_address_i,
    input  logic          [31:0] foreground_pitch_i,
    input  logic          [ 2:0] background_format_i,
    input  logic          [31:0] background_address_i,
    input  logic          [31:0] background_pitch_i,
    input  logic          [ 2:0] destination_format_i,
    input  logic          [31:0] destination_address_i,
    input  logic          [31:0] destination_pitch_i,
    input  logic          [31:0] color_i,
    input  logic          [ 7:0] global_alpha_i,
    input  logic                 inplace_background_i,
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
  import ga2d_pkg::ga2d_read_owner_e;

  typedef enum logic [3:0] {
    Idle,
    PlanOutput,
    Process,
    ReadPlan,
    ReadRequest,
    ReadReceive,
    WriteRequest,
    WriteWait,
    Drain
  } state_e;

  state_e                  s_state_q;
  ga2d_read_owner_e        s_read_owner_q;
  ga2d_read_owner_e        s_next_read_owner_q;
  ga2d_read_owner_e        s_read_owner_choice;
  logic                    s_stop_pending_q;
  logic             [ 1:0] s_operation_q;
  logic             [15:0] s_width_q;
  logic             [15:0] s_height_q;
  logic             [ 2:0] s_foreground_format_q;
  logic             [ 2:0] s_background_format_q;
  logic             [ 2:0] s_destination_format_q;
  logic             [ 2:0] s_foreground_bpp_q;
  logic             [ 2:0] s_background_bpp_q;
  logic             [ 2:0] s_destination_bpp_q;
  logic             [31:0] s_foreground_addr_q;
  logic             [31:0] s_foreground_pitch_q;
  logic             [31:0] s_background_addr_q;
  logic             [31:0] s_background_pitch_q;
  logic             [31:0] s_destination_addr_q;
  logic             [31:0] s_destination_pitch_q;
  logic             [31:0] s_color_q;
  logic             [ 7:0] s_global_alpha_q;
  logic                    s_inplace_background_q;
  logic             [31:0] s_row_bytes_q;
  logic             [15:0] s_row_index_q;
  logic             [31:0] s_row_byte_q;

  logic             [31:0] s_foreground_fetch_addr_q;
  logic             [31:0] s_foreground_fetch_remaining_q;
  logic             [31:0] s_background_fetch_addr_q;
  logic             [31:0] s_background_fetch_remaining_q;
  logic             [31:0] s_read_source_addr;
  logic             [31:0] s_read_source_remaining;
  logic                    s_foreground_read_needed;
  logic                    s_background_read_needed;
  logic                    s_read_candidate_valid;
  logic             [ 4:0] s_read_beats_q;
  logic             [ 3:0] s_read_word_bytes_q;
  logic             [ 2:0] s_read_word_lane_q;
  logic                    s_read_full_q;
  logic             [ 7:0] s_read_total_bytes_q;
  logic                    s_read_reserved_q;
  logic                    s_rd_cmd_owned_q;
  logic                    s_read_err_seen_q;

  logic             [31:0] s_write_burst_addr_q;
  logic             [ 4:0] s_write_burst_beats_q;
  logic             [ 7:0] s_write_burst_bytes_q;
  logic                    s_write_ends_row_q;
  logic             [ 7:0] s_output_bytes_staged_q;
  logic             [63:0] s_output_build_data_q;
  logic             [ 7:0] s_output_build_strobe_q;
  logic                    s_write_reserved_q;
  logic             [ 4:0] s_write_reserved_beats_q;
  logic             [ 7:0] s_write_reserved_bytes_q;
  logic             [ 7:0] s_write_inflight_bytes_q;
  logic                    s_wr_cmd_owned_q;

  logic             [31:0] s_foreground_pixel_q;
  logic             [31:0] s_background_pixel_q;
  logic             [31:0] s_foreground_pixel_d;
  logic             [31:0] s_background_pixel_d;
  logic             [ 2:0] s_foreground_pixel_bytes_q;
  logic             [ 2:0] s_background_pixel_bytes_q;
  logic                    s_pixel_valid_q;
  logic             [ 2:0] s_pixel_output_byte_q;
  logic             [31:0] s_processed_pixel;
  logic             [ 2:0] s_processed_bpp;
  logic                    unused_processed_format_valid;
  logic             [31:0] s_bg_captured_pixels_q;
  logic             [32:0] s_write_cover_end_pixel;

  logic                    unused_fg_fifo_full;
  logic                    s_fg_fifo_empty;
  logic             [63:0] s_fg_fifo_data;
  logic             [ 5:0] s_fg_fifo_count;
  logic                    unused_bg_fifo_full;
  logic                    s_bg_fifo_empty;
  logic             [63:0] s_bg_fifo_data;
  logic             [ 5:0] s_bg_fifo_count;
  logic                    s_output_fifo_full;
  logic                    s_output_fifo_empty;
  logic             [63:0] s_output_fifo_data;
  logic             [ 5:0] s_output_fifo_count;
  logic             [ 5:0] unused_fg_fifo_count;
  logic             [ 5:0] unused_bg_fifo_count;
  logic             [ 5:0] unused_output_fifo_count;
  logic                    s_fg_fifo_push;
  logic                    s_fg_fifo_pop;
  logic                    s_bg_fifo_push;
  logic                    s_bg_fifo_pop;
  logic                    s_output_fifo_push;
  logic                    s_output_fifo_pop;
  logic             [63:0] s_output_push_data;
  logic             [ 7:0] s_output_push_strobe;
  logic             [ 7:0] s_fg_meta_mem                  [0:31];
  logic             [ 7:0] s_bg_meta_mem                  [0:31];
  logic             [ 7:0] s_output_strobe_mem            [0:31];
  logic             [ 4:0] s_fg_meta_wr_q;
  logic             [ 4:0] s_fg_meta_rd_q;
  logic             [ 4:0] s_bg_meta_wr_q;
  logic             [ 4:0] s_bg_meta_rd_q;
  logic             [ 4:0] s_output_strobe_wr_q;
  logic             [ 4:0] s_output_strobe_rd_q;
  logic                    s_fg_word_valid_q;
  logic             [63:0] s_fg_word_q;
  logic             [ 3:0] s_fg_word_bytes_left_q;
  logic             [ 2:0] s_fg_word_lane_q;
  logic                    s_bg_word_valid_q;
  logic             [63:0] s_bg_word_q;
  logic             [ 3:0] s_bg_word_bytes_left_q;
  logic             [ 2:0] s_bg_word_lane_q;

  logic             [31:0] s_destination_byte_addr;
  logic             [31:0] s_row_remaining;
  logic             [31:0] s_write_plan_addr;
  logic             [ 4:0] s_write_plan_beats;
  logic             [ 7:0] s_write_plan_bytes;
  logic                    s_write_plan_ends_row;
  logic             [ 3:0] s_addr_read_bytes;
  logic             [ 2:0] s_addr_read_size;
  logic             [ 4:0] s_read_plan_beats;
  logic             [ 3:0] s_read_plan_word_bytes;
  logic             [ 2:0] s_read_plan_size;
  logic             [ 2:0] s_read_plan_lane;
  logic                    s_read_plan_full;
  logic             [ 7:0] s_read_plan_total_bytes;
  logic             [ 2:0] s_output_lane;
  logic             [ 7:0] s_output_byte;
  logic             [63:0] s_output_build_data_next;
  logic             [ 7:0] s_output_build_strobe_next;
  logic                    s_pixel_emit_fire;
  logic                    s_pixel_emit_end_word;
  logic                    s_pixel_emit_end_burst;
  logic                    s_pixel_emit_end_pixel;
  logic                    s_need_foreground_pixel;
  logic                    s_need_background_pixel;

  logic                    s_read_req_valid;
  logic                    unused_read_req_ready;
  logic                    s_read_req_accept;
  logic                    s_rd_ar_presented;
  logic                    s_rd_req_cancel;
  logic                    s_read_rsp_valid;
  logic                    s_read_rsp_ready;
  logic             [63:0] s_read_data;
  logic             [ 1:0] s_read_rsp;
  logic                    s_read_protocol_err;
  logic                    s_read_rsp_terminal;
  logic             [31:0] s_read_rsp_addr;
  logic                    s_write_req_valid;
  logic                    unused_write_req_ready;
  logic                    s_write_req_accept;
  logic                    s_wr_aw_presented;
  logic                    s_write_req_cancel;
  logic                    s_write_payload_accept;
  logic                    s_write_rsp_valid;
  logic                    s_write_rsp_ready;
  logic             [ 1:0] s_write_rsp;
  logic                    s_write_protocol_err;
  logic             [31:0] s_write_rsp_addr;
  logic                    s_master_read_busy;
  logic                    s_master_write_busy;
  logic                    s_master_idle;
  logic                    s_master_read_stall;
  logic                    s_master_write_stall;
  logic                    s_read_rsp_accept;
  logic                    s_read_rsp_err;
  logic                    s_write_rsp_accept;
  logic                    s_write_rsp_err;

  logic                    s_done_q;
  logic                    s_aborted_q;
  logic                    s_err_seen_q;
  logic                    s_err_valid_q;
  logic             [ 6:0] s_err_code_q;
  logic             [ 3:0] s_err_stage_q;
  logic             [ 1:0] s_err_rsp_q;
  logic             [31:0] s_err_addr_q;

  function automatic logic [2:0] bytes_per_pixel(input logic [2:0] format_i);
    unique case (format_i)
      `APB4_GA2D__FORMAT_RGB565:                                return 3'd2;
      `APB4_GA2D__FORMAT_RGB888:                                return 3'd3;
      `APB4_GA2D__FORMAT_XRGB8888, `APB4_GA2D__FORMAT_ARGB8888: return 3'd4;
      `APB4_GA2D__FORMAT_A8:                                    return 3'd1;
      default:                                                  return '0;
    endcase
  endfunction

  assign s_destination_byte_addr = s_destination_addr_q +
                                   (s_row_index_q * s_destination_pitch_q) + s_row_byte_q;
  assign s_row_remaining = s_row_bytes_q - s_row_byte_q;
  assign s_need_foreground_pixel = (s_operation_q != `APB4_GA2D__OP_FILL) &&
                                   (s_foreground_pixel_bytes_q < s_foreground_bpp_q);
  assign s_need_background_pixel = (s_operation_q == `APB4_GA2D__OP_BLEND) &&
                                   (s_background_pixel_bytes_q < s_background_bpp_q);
  assign s_foreground_read_needed = s_need_foreground_pixel && !s_fg_word_valid_q &&
                                    s_fg_fifo_empty &&
                                    (s_foreground_fetch_remaining_q != 32'd0);
  assign s_background_read_needed = s_need_background_pixel && !s_bg_word_valid_q &&
                                    s_bg_fifo_empty &&
                                    (s_background_fetch_remaining_q != 32'd0);
  assign s_read_candidate_valid = s_foreground_read_needed || s_background_read_needed;

  always_comb begin
    if (s_foreground_read_needed && s_background_read_needed) begin
      s_read_owner_choice = s_next_read_owner_q;
    end else if (s_foreground_read_needed) begin
      s_read_owner_choice = ga2d_pkg::ForegroundOwner;
    end else begin
      s_read_owner_choice = ga2d_pkg::BackgroundOwner;
    end
    if (s_read_reserved_q) begin
      s_read_owner_choice = s_read_owner_q;
    end
    if (s_read_owner_choice == ga2d_pkg::ForegroundOwner) begin
      s_read_source_addr      = s_foreground_fetch_addr_q;
      s_read_source_remaining = s_foreground_fetch_remaining_q;
    end else begin
      s_read_source_addr      = s_background_fetch_addr_q;
      s_read_source_remaining = s_background_fetch_remaining_q;
    end
  end

  ga2d_addr_gen u_addr_gen (
      .read_address_lsb_i(s_read_source_addr[2:0]),
      .read_remaining_i  (s_read_source_remaining),
      .write_address_i   (32'd0),
      .write_byte_i      (8'd0),
      .read_bytes_o      (s_addr_read_bytes),
      .read_size_o       (s_addr_read_size),
      .write_address_o   (),
      .write_data_o      (),
      .write_strobe_o    ()
  );

  always_comb begin
    logic [12:0] s_bytes_to_4k;
    logic [12:0] s_beats_to_4k;
    logic [31:0] s_full_beats;
    s_bytes_to_4k      = 13'd4096 - {1'b0, s_destination_byte_addr[11:0]};
    s_beats_to_4k      = s_bytes_to_4k >> 3;
    s_full_beats       = s_row_remaining >> 3;
    s_write_plan_addr  = {s_destination_byte_addr[31:3], 3'b000};
    s_write_plan_beats = 5'd1;
    s_write_plan_bytes = s_row_remaining[7:0];
    if (s_destination_byte_addr[2:0] != 3'd0) begin
      if (s_row_remaining >= (32'd8 - {29'd0, s_destination_byte_addr[2:0]})) begin
        s_write_plan_bytes = 8'd8 - {5'd0, s_destination_byte_addr[2:0]};
      end
    end else if (s_row_remaining >= 32'd8) begin
      s_write_plan_beats = (s_full_beats > 32'd16) ? 5'd16 : s_full_beats[4:0];
      if (s_beats_to_4k < {8'd0, s_write_plan_beats}) begin
        s_write_plan_beats = s_beats_to_4k[4:0];
      end
      s_write_plan_bytes = {s_write_plan_beats, 3'b000};
    end
    s_write_plan_ends_row = ({24'd0, s_write_plan_bytes} == s_row_remaining);
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
    s_read_plan_lane       = s_read_source_addr[2:0];
    s_read_plan_full       = 1'b0;
    if ((s_read_source_addr[2:0] == 3'd0) && (s_read_source_remaining >= 32'd8)) begin
      s_bytes_to_4k     = 13'd4096 - {1'b0, s_read_source_addr[11:0]};
      s_beats_to_4k     = s_bytes_to_4k >> 3;
      s_full_beats      = s_read_source_remaining >> 3;
      s_read_plan_beats = (s_full_beats > 32'd16) ? 5'd16 : s_full_beats[4:0];
      if (s_beats_to_4k < {8'd0, s_read_plan_beats}) begin
        s_read_plan_beats = s_beats_to_4k[4:0];
      end
      s_read_plan_word_bytes = 4'd8;
      s_read_plan_size       = 3'd3;
      s_read_plan_lane       = 3'd0;
      s_read_plan_full       = 1'b1;
    end
    s_read_plan_total_bytes = s_read_plan_full ? {s_read_plan_beats, 3'b000} :
                                                   {4'd0, s_read_plan_word_bytes};
  end

  assign s_output_lane = s_destination_byte_addr[2:0] + s_output_bytes_staged_q[2:0];
  assign s_output_byte = s_processed_pixel[s_pixel_output_byte_q*8+:8];
  assign s_output_build_data_next = s_output_build_data_q |
                                    ({56'd0, s_output_byte} << {s_output_lane, 3'b000});
  assign s_output_build_strobe_next = s_output_build_strobe_q | (8'b0000_0001 << s_output_lane);
  assign s_pixel_emit_fire = (s_state_q == Process) && s_pixel_valid_q &&
                             !s_output_fifo_full && !stop_i;
  assign s_pixel_emit_end_word = (s_output_lane == 3'd7) ||
                                 ((s_output_bytes_staged_q + 1'b1) ==
                                  s_write_burst_bytes_q);
  assign s_pixel_emit_end_burst = (s_output_bytes_staged_q + 1'b1) == s_write_burst_bytes_q;
  assign s_pixel_emit_end_pixel = (s_pixel_output_byte_q + 1'b1) == s_processed_bpp;
  assign s_output_fifo_push = s_pixel_emit_fire && s_pixel_emit_end_word;
  assign s_output_push_data = s_output_build_data_next;
  assign s_output_push_strobe = s_output_build_strobe_next;

  always_comb begin
    s_foreground_pixel_d = s_foreground_pixel_q;
    s_background_pixel_d = s_background_pixel_q;
    if ((s_state_q == Process) && s_need_foreground_pixel && s_fg_word_valid_q) begin
      s_foreground_pixel_d = s_foreground_pixel_q |
                             ({24'd0, s_fg_word_q[s_fg_word_lane_q*8+:8]} <<
                              {s_foreground_pixel_bytes_q, 3'b000});
    end
    if ((s_state_q == Process) && !s_need_foreground_pixel &&
        s_need_background_pixel && s_bg_word_valid_q) begin
      s_background_pixel_d = s_background_pixel_q |
                             ({24'd0, s_bg_word_q[s_bg_word_lane_q*8+:8]} <<
                              {s_background_pixel_bytes_q, 3'b000});
    end
    if ((s_state_q == Process) && s_pixel_emit_fire && s_pixel_emit_end_pixel) begin
      s_foreground_pixel_d = '0;
      s_background_pixel_d = '0;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_foreground_pixel_q <= '0;
      s_background_pixel_q <= '0;
    end else if (clear_i) begin
      s_foreground_pixel_q <= '0;
      s_background_pixel_q <= '0;
    end else begin
      s_foreground_pixel_q <= s_foreground_pixel_d;
      s_background_pixel_q <= s_background_pixel_d;
    end
  end

  assign s_fg_fifo_push = (s_state_q == ReadReceive) && s_read_rsp_accept &&
                          !s_read_rsp_err &&
                          (s_read_owner_q == ga2d_pkg::ForegroundOwner);
  assign s_bg_fifo_push = (s_state_q == ReadReceive) && s_read_rsp_accept &&
                          !s_read_rsp_err &&
                          (s_read_owner_q == ga2d_pkg::BackgroundOwner);
  assign s_fg_fifo_pop = ((s_state_q == Process) && s_need_foreground_pixel &&
                          !s_fg_word_valid_q && !s_fg_fifo_empty && !stop_i) ||
                         ((s_state_q == Drain) && !s_fg_fifo_empty && !s_master_read_busy);
  assign s_bg_fifo_pop = ((s_state_q == Process) && s_need_background_pixel &&
                          !s_bg_word_valid_q && !s_bg_fifo_empty && !stop_i) ||
                         ((s_state_q == Drain) && !s_bg_fifo_empty && !s_master_read_busy);
  assign s_output_fifo_pop = s_write_payload_accept ||
                             ((s_state_q == Drain) && !s_output_fifo_empty &&
                              !s_master_write_busy);

  fifo #(
      .DATA_WIDTH      (64),
      .BUFFER_DEPTH    (32),
      .LOG_BUFFER_DEPTH(5)
  ) u_foreground_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(clear_i),
      .push_i (s_fg_fifo_push),
      .full_o (unused_fg_fifo_full),
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
      .push_i (s_bg_fifo_push),
      .full_o (unused_bg_fifo_full),
      .dat_i  (s_read_data),
      .pop_i  (s_bg_fifo_pop),
      .empty_o(s_bg_fifo_empty),
      .dat_o  (s_bg_fifo_data),
      .cnt_o  (s_bg_fifo_count)
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

  // These aliases are intentionally retained as stable formal observations.
  assign unused_fg_fifo_count     = s_fg_fifo_count;
  assign unused_bg_fifo_count     = s_bg_fifo_count;
  assign unused_output_fifo_count = s_output_fifo_count;

  ga2d_pixel u_pixel (
      .operation_i         (s_operation_q),
      .foreground_pixel_i  (s_foreground_pixel_q),
      .background_pixel_i  (s_background_pixel_q),
      .color_i             (s_color_q),
      .global_alpha_i      (s_global_alpha_q),
      .foreground_format_i (s_foreground_format_q),
      .background_format_i (s_background_format_q),
      .destination_format_i(s_destination_format_q),
      .pixel_o             (s_processed_pixel),
      .bytes_per_pixel_o   (s_processed_bpp),
      .format_valid_o      (unused_processed_format_valid)
  );

  assign s_read_req_valid = (s_state_q == ReadRequest) && s_read_reserved_q && !stop_i;
  assign s_read_rsp_ready = s_state_q == ReadReceive;
  assign s_read_rsp_accept = s_read_rsp_valid && s_read_rsp_ready;
  assign s_read_rsp_err = s_read_protocol_err || (s_read_rsp != 2'd0);
  assign s_write_req_valid = (s_state_q == WriteRequest) && !stop_i &&
                             s_write_reserved_q &&
                             (s_output_fifo_count >= {1'b0, s_write_reserved_beats_q}) &&
                             (!s_inplace_background_q ||
                              ({1'b0, s_bg_captured_pixels_q} >= s_write_cover_end_pixel));
  assign s_write_rsp_ready = s_state_q == WriteWait;
  assign s_write_rsp_accept = s_write_rsp_valid && s_write_rsp_ready;
  assign s_write_rsp_err = s_write_protocol_err || (s_write_rsp != 2'd0);

  // A write burst covers all pixels touching its enabled destination lanes.
  // This is the observable in-place safety boundary required by GA2D-P5.
  always_comb begin
    logic [32:0] s_pixels_before;
    logic [32:0] s_bytes_through_burst;
    s_pixels_before = {17'd0, s_row_index_q} * {17'd0, s_width_q};
    s_bytes_through_burst = {1'b0, s_row_byte_q} + {25'd0, s_write_burst_bytes_q};
    s_write_cover_end_pixel = s_pixels_before +
                               ((s_bytes_through_burst + {30'd0, s_destination_bpp_q} - 1'b1) /
                                {30'd0, s_destination_bpp_q});
  end

  ga2d_axi4_master u_axi4_master (
      .clk_i                    (clk_i),
      .rst_n_i                  (rst_n_i),
      .clear_i                  (clear_i),
      .read_request_valid_i     (s_read_req_valid),
      .read_request_ready_o     (unused_read_req_ready),
      .read_address_i           (s_read_source_addr),
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
      .write_beats_i            (s_write_reserved_beats_q),
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

  assign busy_o = s_state_q != Idle;
  assign draining_o = s_stop_pending_q && (s_state_q != Idle);
  assign idle_o = (s_state_q == Idle) && s_master_idle && !s_master_read_busy &&
                  !s_master_write_busy && s_fg_fifo_empty && s_bg_fifo_empty &&
                  s_output_fifo_empty && !s_fg_word_valid_q && !s_bg_word_valid_q &&
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
                      s_pixel_emit_fire;
  assign read_bytes_o = (s_read_rsp_accept && !s_read_rsp_err) ?
                        (s_read_full_q ? 8'd8 : {4'd0, s_read_word_bytes_q}) : 8'd0;
  assign write_bytes_o = (s_write_rsp_accept && !s_write_rsp_err) ? s_write_inflight_bytes_q : 8'd0;
  assign line_done_o = s_write_rsp_accept && !s_write_rsp_err && s_write_ends_row_q;
  assign read_stall_o = s_master_read_stall;
  assign write_stall_o = s_master_write_stall;
  assign pipe_stall_o = ((s_state_q == Process) &&
                         ((s_pixel_valid_q && s_output_fifo_full) ||
                          (s_need_foreground_pixel && !s_fg_word_valid_q && s_fg_fifo_empty) ||
                          (s_need_background_pixel && !s_bg_word_valid_q && s_bg_fifo_empty))) ||
                        ((s_state_q == PlanOutput) &&
                         ((s_output_fifo_count + s_write_plan_beats) > 6'd32));

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_fg_meta_wr_q         <= '0;
      s_fg_meta_rd_q         <= '0;
      s_bg_meta_wr_q         <= '0;
      s_bg_meta_rd_q         <= '0;
      s_output_strobe_wr_q   <= '0;
      s_output_strobe_rd_q   <= '0;
      s_fg_word_valid_q      <= 1'b0;
      s_fg_word_q            <= '0;
      s_fg_word_bytes_left_q <= '0;
      s_fg_word_lane_q       <= '0;
      s_bg_word_valid_q      <= 1'b0;
      s_bg_word_q            <= '0;
      s_bg_word_bytes_left_q <= '0;
      s_bg_word_lane_q       <= '0;
    end else if (clear_i) begin
      s_fg_meta_wr_q         <= '0;
      s_fg_meta_rd_q         <= '0;
      s_bg_meta_wr_q         <= '0;
      s_bg_meta_rd_q         <= '0;
      s_output_strobe_wr_q   <= '0;
      s_output_strobe_rd_q   <= '0;
      s_fg_word_valid_q      <= 1'b0;
      s_fg_word_q            <= '0;
      s_fg_word_bytes_left_q <= '0;
      s_fg_word_lane_q       <= '0;
      s_bg_word_valid_q      <= 1'b0;
      s_bg_word_q            <= '0;
      s_bg_word_bytes_left_q <= '0;
      s_bg_word_lane_q       <= '0;
    end else begin
      if (s_fg_fifo_push) begin
        s_fg_meta_mem[s_fg_meta_wr_q] <= s_read_full_q ? {4'd8, 4'd0} :
                                                         {s_read_word_bytes_q, 1'b0,
                                                          s_read_word_lane_q};
        s_fg_meta_wr_q <= s_fg_meta_wr_q + 1'b1;
      end
      if (s_bg_fifo_push) begin
        s_bg_meta_mem[s_bg_meta_wr_q] <= s_read_full_q ? {4'd8, 4'd0} :
                                                         {s_read_word_bytes_q, 1'b0,
                                                          s_read_word_lane_q};
        s_bg_meta_wr_q <= s_bg_meta_wr_q + 1'b1;
      end
      if (s_output_fifo_push) begin
        s_output_strobe_mem[s_output_strobe_wr_q] <= s_output_push_strobe;
        s_output_strobe_wr_q                      <= s_output_strobe_wr_q + 1'b1;
      end
      if (s_output_fifo_pop) begin
        s_output_strobe_rd_q <= s_output_strobe_rd_q + 1'b1;
      end
      if (s_fg_fifo_pop) begin
        s_fg_meta_rd_q <= s_fg_meta_rd_q + 1'b1;
        if (s_state_q == Process) begin
          s_fg_word_valid_q      <= 1'b1;
          s_fg_word_q            <= s_fg_fifo_data;
          s_fg_word_bytes_left_q <= s_fg_meta_mem[s_fg_meta_rd_q][7:4];
          s_fg_word_lane_q       <= s_fg_meta_mem[s_fg_meta_rd_q][2:0];
        end
      end
      if (s_bg_fifo_pop) begin
        s_bg_meta_rd_q <= s_bg_meta_rd_q + 1'b1;
        if (s_state_q == Process) begin
          s_bg_word_valid_q      <= 1'b1;
          s_bg_word_q            <= s_bg_fifo_data;
          s_bg_word_bytes_left_q <= s_bg_meta_mem[s_bg_meta_rd_q][7:4];
          s_bg_word_lane_q       <= s_bg_meta_mem[s_bg_meta_rd_q][2:0];
        end
      end
      if ((s_state_q == Process) && s_need_foreground_pixel && s_fg_word_valid_q) begin
        if (s_fg_word_bytes_left_q == 4'd1) begin
          s_fg_word_valid_q      <= 1'b0;
          s_fg_word_bytes_left_q <= '0;
        end else begin
          s_fg_word_bytes_left_q <= s_fg_word_bytes_left_q - 1'b1;
          s_fg_word_lane_q       <= s_fg_word_lane_q + 1'b1;
        end
      end
      if ((s_state_q == Process) && !s_need_foreground_pixel &&
          s_need_background_pixel && s_bg_word_valid_q) begin
        if (s_bg_word_bytes_left_q == 4'd1) begin
          s_bg_word_valid_q      <= 1'b0;
          s_bg_word_bytes_left_q <= '0;
        end else begin
          s_bg_word_bytes_left_q <= s_bg_word_bytes_left_q - 1'b1;
          s_bg_word_lane_q       <= s_bg_word_lane_q + 1'b1;
        end
      end
      if (s_state_q == Drain) begin
        s_fg_word_valid_q <= 1'b0;
        s_bg_word_valid_q <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q                      <= Idle;
      s_read_owner_q                 <= ga2d_pkg::ForegroundOwner;
      s_next_read_owner_q            <= ga2d_pkg::ForegroundOwner;
      s_stop_pending_q               <= 1'b0;
      s_operation_q                  <= '0;
      s_width_q                      <= '0;
      s_height_q                     <= '0;
      s_foreground_format_q          <= '0;
      s_background_format_q          <= '0;
      s_destination_format_q         <= '0;
      s_foreground_bpp_q             <= '0;
      s_background_bpp_q             <= '0;
      s_destination_bpp_q            <= '0;
      s_foreground_addr_q            <= '0;
      s_foreground_pitch_q           <= '0;
      s_background_addr_q            <= '0;
      s_background_pitch_q           <= '0;
      s_destination_addr_q           <= '0;
      s_destination_pitch_q          <= '0;
      s_color_q                      <= '0;
      s_global_alpha_q               <= '0;
      s_inplace_background_q         <= 1'b0;
      s_row_bytes_q                  <= '0;
      s_row_index_q                  <= '0;
      s_row_byte_q                   <= '0;
      s_foreground_fetch_addr_q      <= '0;
      s_foreground_fetch_remaining_q <= '0;
      s_background_fetch_addr_q      <= '0;
      s_background_fetch_remaining_q <= '0;
      s_read_beats_q                 <= '0;
      s_read_word_bytes_q            <= '0;
      s_read_word_lane_q             <= '0;
      s_read_full_q                  <= 1'b0;
      s_read_total_bytes_q           <= '0;
      s_read_reserved_q              <= 1'b0;
      s_rd_cmd_owned_q               <= 1'b0;
      s_read_err_seen_q              <= 1'b0;
      s_write_burst_addr_q           <= '0;
      s_write_burst_beats_q          <= '0;
      s_write_burst_bytes_q          <= '0;
      s_write_ends_row_q             <= 1'b0;
      s_output_bytes_staged_q        <= '0;
      s_output_build_data_q          <= '0;
      s_output_build_strobe_q        <= '0;
      s_write_reserved_q             <= 1'b0;
      s_write_reserved_beats_q       <= '0;
      s_write_reserved_bytes_q       <= '0;
      s_write_inflight_bytes_q       <= '0;
      s_wr_cmd_owned_q               <= 1'b0;
      s_foreground_pixel_bytes_q     <= '0;
      s_background_pixel_bytes_q     <= '0;
      s_pixel_valid_q                <= 1'b0;
      s_pixel_output_byte_q          <= '0;
      s_bg_captured_pixels_q         <= '0;
      s_done_q                       <= 1'b0;
      s_aborted_q                    <= 1'b0;
      s_err_seen_q                   <= 1'b0;
      s_err_valid_q                  <= 1'b0;
      s_err_code_q                   <= '0;
      s_err_stage_q                  <= '0;
      s_err_rsp_q                    <= '0;
      s_err_addr_q                   <= '0;
    end else if (clear_i) begin
      s_state_q                  <= Idle;
      s_stop_pending_q           <= 1'b0;
      s_read_reserved_q          <= 1'b0;
      s_rd_cmd_owned_q           <= 1'b0;
      s_write_reserved_q         <= 1'b0;
      s_wr_cmd_owned_q           <= 1'b0;
      s_pixel_valid_q            <= 1'b0;
      s_foreground_pixel_bytes_q <= '0;
      s_background_pixel_bytes_q <= '0;
      s_done_q                   <= 1'b0;
      s_aborted_q                <= 1'b0;
      s_err_seen_q               <= 1'b0;
      s_err_valid_q              <= 1'b0;
    end else begin
      s_done_q      <= 1'b0;
      s_aborted_q   <= 1'b0;
      s_err_valid_q <= 1'b0;
      if (stop_i && (s_state_q != Idle)) begin
        s_stop_pending_q <= 1'b1;
      end

      unique case (s_state_q)
        Idle: begin
          s_stop_pending_q   <= 1'b0;
          s_read_reserved_q  <= 1'b0;
          s_rd_cmd_owned_q   <= 1'b0;
          s_write_reserved_q <= 1'b0;
          s_wr_cmd_owned_q   <= 1'b0;
          s_err_seen_q       <= 1'b0;
          if (start_i && !stop_i) begin
            s_operation_q <= operation_i;
            s_width_q <= width_i;
            s_height_q <= height_i;
            s_foreground_format_q <= foreground_format_i;
            s_background_format_q <= background_format_i;
            s_destination_format_q <= destination_format_i;
            s_foreground_bpp_q <= bytes_per_pixel(foreground_format_i);
            s_background_bpp_q <= bytes_per_pixel(background_format_i);
            s_destination_bpp_q <= bytes_per_pixel(destination_format_i);
            s_foreground_addr_q <= foreground_address_i;
            s_foreground_pitch_q <= foreground_pitch_i;
            s_background_addr_q <= background_address_i;
            s_background_pitch_q <= background_pitch_i;
            s_destination_addr_q <= destination_address_i;
            s_destination_pitch_q <= destination_pitch_i;
            s_color_q <= color_i;
            s_global_alpha_q <= global_alpha_i;
            s_inplace_background_q <= inplace_background_i;
            s_row_bytes_q <= {16'd0, width_i} * {29'd0, bytes_per_pixel(destination_format_i)};
            s_row_index_q <= '0;
            s_row_byte_q <= '0;
            s_foreground_fetch_addr_q <= foreground_address_i;
            s_foreground_fetch_remaining_q <= {16'd0, width_i} * {29'd0, bytes_per_pixel(
                foreground_format_i
            )};
            s_background_fetch_addr_q <= background_address_i;
            s_background_fetch_remaining_q <= {16'd0, width_i} * {29'd0, bytes_per_pixel(
                background_format_i
            )};
            s_foreground_pixel_bytes_q <= '0;
            s_background_pixel_bytes_q <= '0;
            s_pixel_valid_q <= 1'b0;
            s_pixel_output_byte_q <= '0;
            s_bg_captured_pixels_q <= '0;
            s_state_q <= PlanOutput;
          end
        end
        PlanOutput: begin
          if (stop_i) begin
            s_state_q <= Drain;
          end else if ((s_output_fifo_count + s_write_plan_beats) <= 6'd32) begin
            s_write_burst_addr_q    <= s_write_plan_addr;
            s_write_burst_beats_q   <= s_write_plan_beats;
            s_write_burst_bytes_q   <= s_write_plan_bytes;
            s_write_ends_row_q      <= s_write_plan_ends_row;
            s_output_bytes_staged_q <= '0;
            s_output_build_data_q   <= '0;
            s_output_build_strobe_q <= '0;
            s_state_q               <= Process;
          end
        end
        Process: begin
          if (stop_i) begin
            s_state_q <= Drain;
          end else if (!s_pixel_valid_q) begin
            if (s_need_foreground_pixel) begin
              if (s_fg_word_valid_q) begin
                s_foreground_pixel_bytes_q <= s_foreground_pixel_bytes_q + 1'b1;
              end else if (s_fg_fifo_empty) begin
                s_state_q <= ReadPlan;
              end
            end else if (s_need_background_pixel) begin
              if (s_bg_word_valid_q) begin
                s_background_pixel_bytes_q <= s_background_pixel_bytes_q + 1'b1;
              end else if (s_bg_fifo_empty) begin
                s_state_q <= ReadPlan;
              end
            end else begin
              s_pixel_valid_q       <= 1'b1;
              s_pixel_output_byte_q <= '0;
              if (s_operation_q == `APB4_GA2D__OP_BLEND) begin
                s_bg_captured_pixels_q <= s_bg_captured_pixels_q + 1'b1;
              end
            end
          end else if (s_pixel_emit_fire) begin
            s_output_bytes_staged_q <= s_output_bytes_staged_q + 1'b1;
            if (s_pixel_emit_end_word) begin
              s_output_build_data_q   <= '0;
              s_output_build_strobe_q <= '0;
            end else begin
              s_output_build_data_q   <= s_output_build_data_next;
              s_output_build_strobe_q <= s_output_build_strobe_next;
            end
            if (s_pixel_emit_end_pixel) begin
              s_pixel_valid_q            <= 1'b0;
              s_pixel_output_byte_q      <= '0;
              s_foreground_pixel_bytes_q <= '0;
              s_background_pixel_bytes_q <= '0;
            end else begin
              s_pixel_output_byte_q <= s_pixel_output_byte_q + 1'b1;
            end
            if (s_pixel_emit_end_burst) begin
              s_write_reserved_q       <= 1'b1;
              s_write_reserved_beats_q <= s_write_burst_beats_q;
              s_write_reserved_bytes_q <= s_write_burst_bytes_q;
              s_state_q                <= WriteRequest;
            end
          end
        end
        ReadPlan: begin
          if (stop_i) begin
            s_state_q <= Drain;
          end else if (s_read_candidate_valid) begin
            s_read_owner_q       <= s_read_owner_choice;
            s_read_beats_q       <= s_read_plan_beats;
            s_read_word_bytes_q  <= s_read_plan_word_bytes;
            s_read_word_lane_q   <= s_read_plan_lane;
            s_read_full_q        <= s_read_plan_full;
            s_read_total_bytes_q <= s_read_plan_total_bytes;
            s_read_reserved_q    <= 1'b1;
            s_read_err_seen_q    <= 1'b0;
            s_state_q            <= ReadRequest;
          end
        end
        ReadRequest: begin
          if (stop_i) begin
            s_read_reserved_q <= 1'b0;
            s_state_q         <= Drain;
          end else if (s_read_req_accept) begin
            s_rd_cmd_owned_q <= 1'b1;
            s_state_q        <= ReadReceive;
          end
        end
        ReadReceive: begin
          if (s_rd_req_cancel && s_rd_cmd_owned_q && !s_rd_ar_presented) begin
            s_rd_cmd_owned_q <= 1'b0;
            s_state_q        <= Drain;
          end else if (s_read_rsp_accept) begin
            if (s_read_rsp_err && !s_err_seen_q) begin
              s_err_seen_q <= 1'b1;
              s_err_valid_q <= 1'b1;
              s_err_code_q <= s_read_protocol_err ? `APB4_GA2D__ERROR_AXI_PROTOCOL :
                                                     `APB4_GA2D__ERROR_AXI_READ;
              s_err_stage_q <= (s_read_owner_q == ga2d_pkg::ForegroundOwner) ?
                               `APB4_GA2D__ERROR_STAGE_FOREGROUND :
                               `APB4_GA2D__ERROR_STAGE_BACKGROUND;
              s_err_rsp_q <= s_read_protocol_err ? 2'd0 : s_read_rsp;
              s_err_addr_q <= s_read_rsp_addr;
            end
            if (s_read_rsp_err) begin
              s_read_err_seen_q <= 1'b1;
            end
            if (s_read_protocol_err) begin
              // A malformed response retains local-ID ownership until clear_i.
              s_state_q <= Drain;
            end else if (s_read_rsp_terminal) begin
              if (s_read_err_seen_q || s_read_rsp_err || stop_i) begin
                s_read_reserved_q <= 1'b0;
                s_rd_cmd_owned_q  <= 1'b0;
                s_state_q         <= Drain;
              end else begin
                s_read_reserved_q   <= 1'b0;
                s_rd_cmd_owned_q    <= 1'b0;
                s_next_read_owner_q <= ~s_read_owner_q;
                if (s_read_owner_q == ga2d_pkg::ForegroundOwner) begin
                  if (s_read_total_bytes_q == s_foreground_fetch_remaining_q) begin
                    s_foreground_fetch_addr_q <= s_foreground_addr_q +
                                                 ((s_row_index_q + 1'b1) *
                                                  s_foreground_pitch_q);
                    s_foreground_fetch_remaining_q <=
                        {16'd0, s_width_q} * {29'd0, s_foreground_bpp_q};
                  end else begin
                    s_foreground_fetch_addr_q <= s_foreground_fetch_addr_q +
                                                 {24'd0, s_read_total_bytes_q};
                    s_foreground_fetch_remaining_q <= s_foreground_fetch_remaining_q -
                                                      {24'd0, s_read_total_bytes_q};
                  end
                end else begin
                  if (s_read_total_bytes_q == s_background_fetch_remaining_q) begin
                    s_background_fetch_addr_q <= s_background_addr_q +
                                                 ((s_row_index_q + 1'b1) *
                                                  s_background_pitch_q);
                    s_background_fetch_remaining_q <=
                        {16'd0, s_width_q} * {29'd0, s_background_bpp_q};
                  end else begin
                    s_background_fetch_addr_q <= s_background_fetch_addr_q +
                                                 {24'd0, s_read_total_bytes_q};
                    s_background_fetch_remaining_q <= s_background_fetch_remaining_q -
                                                      {24'd0, s_read_total_bytes_q};
                  end
                end
                s_state_q <= Process;
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
              // Do not reclaim the payload after a malformed BID.
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
                  s_state_q     <= PlanOutput;
                end
              end else begin
                s_row_byte_q <= s_row_byte_q + {24'd0, s_write_burst_bytes_q};
                s_state_q    <= PlanOutput;
              end
            end
          end
        end
        Drain: begin
          if (!s_fg_fifo_empty || !s_bg_fifo_empty || !s_output_fifo_empty ||
              s_fg_word_valid_q || s_bg_word_valid_q) begin
            s_state_q <= Drain;
          end else if (s_master_idle) begin
            s_state_q                <= Idle;
            s_aborted_q              <= 1'b1;
            s_read_reserved_q        <= 1'b0;
            s_rd_cmd_owned_q         <= 1'b0;
            s_write_reserved_q       <= 1'b0;
            s_write_reserved_beats_q <= '0;
            s_write_reserved_bytes_q <= '0;
            s_wr_cmd_owned_q         <= 1'b0;
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
