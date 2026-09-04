// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_ring_scheduler (
    // verilog_format: off -- preserve ring, backend, and DMA service columns
    input  logic                   clk_i,
    input  logic                   rst_n_i,
    input  logic                   soft_reset_i,
    input  logic                   counter_clear_i,
    input  logic                   abort_i,
    input  logic                   quiesce_i,
    input  logic                   start_i,
    input  logic [31:0]            ring_base_i,
    input  logic [8:0]             ring_size_i,
    input  logic [7:0]             ring_tail_i,
    input  logic                   ring_enable_i,
    input  logic                   stop_on_error_i,
    input  logic [7:0]             coalesce_count_i,
    input  logic [15:0]            coalesce_timeout_i,
    output logic                   dma_request_valid_o,
    input  logic                   dma_request_ready_i,
    output logic                   dma_request_write_o,
    output logic [31:0]            dma_request_addr_o,
    output logic [31:0]            dma_request_bytes_o,
    axi4_stream_if.sink            dma_read_axis,
    axi4_stream_if.source          dma_write_axis,
    input  logic                   dma_done_i,
    input  logic                   dma_error_i,
    input  logic [5:0]             dma_error_code_i,
    input  logic [3:0]             dma_error_stage_i,
    input  logic [1:0]             dma_error_resp_i,
    input  logic [31:0]            dma_error_addr_i,
    output logic                   backend_job_valid_o,
    input  logic                   backend_job_ready_i,
    output logic [1023:0]          backend_descriptor_o,
    output logic [7:0]             backend_index_o,
    input  logic                   backend_result_valid_i,
    output logic                   backend_result_ready_o,
    input  logic                   backend_result_error_i,
    input  logic [5:0]             backend_result_code_i,
    input  logic [3:0]             backend_result_stage_i,
    input  logic [1:0]             backend_result_resp_i,
    input  logic [31:0]            backend_input_used_i,
    input  logic [31:0]            backend_output_bytes_i,
    input  logic [31:0]            backend_frames_i,
    input  logic [31:0]            backend_source_info_i,
    input  logic [31:0]            backend_cycles_i,
    input  logic [31:0]            backend_detail_i,
    output logic [31:0]            job_status_o,
    output logic [31:0]            ring_status_o,
    output logic [7:0]             ring_head_o,
    output logic [31:0]            ring_completed_o,
    output logic                   ring_event_o,
    output logic                   error_event_o,
    output logic [5:0]             error_code_o,
    output logic [3:0]             error_stage_o,
    output logic [1:0]             error_resp_o,
    output logic [7:0]             error_index_o,
    output logic [31:0]            error_addr_o,
    output logic                   abort_done_o,
    output logic                   aborting_o,
    output logic                   idle_o
    // verilog_format: on
);
  typedef enum logic [3:0] {
    Idle,
    FetchRequest,
    FetchData,
    Evaluate,
    BackendRequest,
    BackendWait,
    ResultWriteRequest,
    ResultWriteData,
    ResultWriteWait,
    OwnerWriteRequest,
    OwnerWriteData,
    OwnerWriteWait,
    Stalled
  } state_e;

  state_e        s_state_q;
  logic   [31:0] s_descriptor_q        [32];
  logic   [ 5:0] s_word_index_q;
  logic   [ 7:0] s_head_q;
  logic   [31:0] s_completed_q;
  logic          s_active_q;
  logic          s_ring_err_q;
  logic          s_wrapped_q;
  logic          s_stopped_q;
  logic   [ 7:0] s_pending_q;
  logic   [15:0] s_coalesce_timer_q;
  logic   [ 7:0] s_last_index_q;
  logic          s_job_err_q;
  logic          s_job_busy_q;
  logic          s_job_done_q;
  logic          s_job_aborted_q;
  logic   [ 5:0] s_job_code_q;
  logic   [ 3:0] s_job_stage_q;
  logic   [ 1:0] s_job_resp_q;
  logic          s_ring_event_q;
  logic          s_err_event_q;
  logic          s_abort_done_q;
  logic   [ 5:0] s_err_code_q;
  logic   [ 3:0] s_err_stage_q;
  logic   [ 1:0] s_err_resp_q;
  logic   [ 7:0] s_err_index_q;
  logic   [31:0] s_err_addr_q;
  logic          s_descriptor_valid;
  logic          s_descriptor_ioc;
  logic   [31:0] s_descriptor_addr;
  logic   [32:0] s_descriptor_addr_ext;
  logic   [32:0] s_ring_last;
  logic          s_ring_config_valid;
  logic          s_writeback_pending;
  logic   [ 7:0] s_next_head;
  logic   [ 8:0] s_incremented_head;
  logic   [ 7:0] s_post_pending;
  logic          s_abort_pending_q;
  logic          s_ring_en_q;
  logic   [63:0] s_timestamp_q;

  function automatic logic [31:0] saturating_increment(input logic [31:0] value_i);
    return (&value_i) ? value_i : value_i + 1'b1;
  endfunction

  function automatic logic is_power_of_two(input logic [8:0] value_i);
    return (value_i != 9'd0) && ((value_i & (value_i - 1'b1)) == 9'd0);
  endfunction

  always_comb begin
    s_descriptor_valid = s_descriptor_q[0][`APB4_APU__DESCRIPTOR_CONTROL_OWN] &&
        (s_descriptor_q[0][29:12] == 18'd0) &&
        (s_descriptor_q[0][3:0] <= 4'd1) && (s_descriptor_q[0][7:4] <= 4'd2) &&
        (s_descriptor_q[0][9:8] <= 2'd1) &&
        (s_descriptor_q[2][1:0] == 2'd0) && (s_descriptor_q[3] != 32'd0) &&
        (((s_descriptor_q[0][9:8] == 2'd0) && (s_descriptor_q[4][1:0] == 2'd0) &&
          (s_descriptor_q[5] != 32'd0)) ||
         ((s_descriptor_q[0][9:8] == 2'd1) && (s_descriptor_q[4] == 32'd0) &&
          (s_descriptor_q[5] == 32'd0))) &&
        (s_descriptor_q[6][31:26] == 6'd0) && (s_descriptor_q[6][19] == 1'b0) &&
        (s_descriptor_q[6][18:17] <= 2'd2) &&
        ((s_descriptor_q[6][25:20] == 6'd0) || (s_descriptor_q[6][25:20] == 6'd16) ||
         (s_descriptor_q[6][25:20] == 6'd24)) &&
        (s_descriptor_q[7][31:21] == 11'd0) && (s_descriptor_q[7][18:17] <= 2'd2) &&
        (s_descriptor_q[7][20:19] <= 2'd1) && (s_descriptor_q[8][31:1] == 31'd0) &&
        (((s_descriptor_q[0][3:0] == 4'd0) && (s_descriptor_q[9] == 32'd0)) ||
         (s_descriptor_q[0][3:0] == 4'd1));
    for (int word_index = 24; word_index < 32; word_index++) begin
      s_descriptor_valid = s_descriptor_valid && (s_descriptor_q[word_index] == 32'd0);
    end
  end

  assign s_descriptor_ioc = s_descriptor_q[0][`APB4_APU__DESCRIPTOR_CONTROL_IOC];
  assign s_descriptor_addr_ext = {1'b0, ring_base_i} + ({25'd0, s_head_q} << 7);
  assign s_descriptor_addr = s_descriptor_addr_ext[31:0];
  assign s_ring_last = {1'b0, ring_base_i} + ({24'd0, ring_size_i} << 7) - 1'b1;
  assign s_ring_config_valid = (ring_base_i[6:0] == 7'd0) &&
      (ring_size_i >= 9'd2) && (ring_size_i <= 9'd256) && is_power_of_two(
      ring_size_i
  ) && (s_ring_last <= 33'h0_ffff_ffff) && (s_descriptor_addr_ext <= 33'h0_ffff_ffff) &&
      ({1'b0, s_head_q} < ring_size_i) && ({1'b0, ring_tail_i} < ring_size_i);
  assign s_incremented_head = {1'b0, s_head_q} + 1'b1;
  assign s_next_head = (s_incremented_head >= ring_size_i) ? 8'd0 : s_incremented_head[7:0];
  assign s_post_pending = (&s_pending_q) ? s_pending_q : s_pending_q + 1'b1;
  assign s_writeback_pending = (s_state_q == ResultWriteRequest) ||
      (s_state_q == ResultWriteData) || (s_state_q == ResultWriteWait) ||
      (s_state_q == OwnerWriteRequest) || (s_state_q == OwnerWriteData) ||
      (s_state_q == OwnerWriteWait);
  assign dma_request_valid_o = (s_state_q == FetchRequest) ||
      (s_state_q == ResultWriteRequest) || (s_state_q == OwnerWriteRequest);
  assign dma_request_write_o = s_state_q != FetchRequest;
  assign dma_request_addr_o = ((s_state_q == OwnerWriteRequest) ||
                               (s_state_q == OwnerWriteData) ||
                               (s_state_q == OwnerWriteWait)) ?
      s_descriptor_addr :
      (((s_state_q == ResultWriteRequest) || (s_state_q == ResultWriteData) ||
        (s_state_q == ResultWriteWait)) ? s_descriptor_addr + 32'd4 : s_descriptor_addr);
  assign dma_request_bytes_o = ((s_state_q == OwnerWriteRequest) ||
                                (s_state_q == OwnerWriteData) ||
                                (s_state_q == OwnerWriteWait)) ? 32'd4 :
      (((s_state_q == ResultWriteRequest) || (s_state_q == ResultWriteData) ||
        (s_state_q == ResultWriteWait)) ? 32'd124 : 32'd128);
  assign dma_read_axis.tready = s_state_q == FetchData;
  assign dma_write_axis.tdata = (s_state_q == OwnerWriteData) ?
      s_descriptor_q[0] : s_descriptor_q[s_word_index_q[4:0]];
  assign dma_write_axis.tkeep = 4'hf;
  assign dma_write_axis.tstrb = 4'hf;
  assign dma_write_axis.tlast = (s_state_q == OwnerWriteData) || (s_word_index_q == 6'd31);
  assign dma_write_axis.tid = '0;
  assign dma_write_axis.tdest = '0;
  assign dma_write_axis.tuser = '0;
  assign dma_write_axis.tvalid = (s_state_q == ResultWriteData) || (s_state_q == OwnerWriteData);
  assign backend_job_valid_o = (s_state_q == BackendRequest) && !abort_i;
  assign backend_descriptor_o = {
    s_descriptor_q[31],
    s_descriptor_q[30],
    s_descriptor_q[29],
    s_descriptor_q[28],
    s_descriptor_q[27],
    s_descriptor_q[26],
    s_descriptor_q[25],
    s_descriptor_q[24],
    s_descriptor_q[23],
    s_descriptor_q[22],
    s_descriptor_q[21],
    s_descriptor_q[20],
    s_descriptor_q[19],
    s_descriptor_q[18],
    s_descriptor_q[17],
    s_descriptor_q[16],
    s_descriptor_q[15],
    s_descriptor_q[14],
    s_descriptor_q[13],
    s_descriptor_q[12],
    s_descriptor_q[11],
    s_descriptor_q[10],
    s_descriptor_q[9],
    s_descriptor_q[8],
    s_descriptor_q[7],
    s_descriptor_q[6],
    s_descriptor_q[5],
    s_descriptor_q[4],
    s_descriptor_q[3],
    s_descriptor_q[2],
    s_descriptor_q[1],
    s_descriptor_q[0]
  };
  assign backend_index_o = s_head_q;
  assign backend_result_ready_o = s_state_q == BackendWait;
  assign ring_head_o = s_head_q;
  assign ring_completed_o = s_completed_q;
  assign ring_event_o = s_ring_event_q;
  assign error_event_o = s_err_event_q;
  assign abort_done_o = s_abort_done_q;
  assign aborting_o = s_abort_pending_q || (s_job_busy_q && s_job_aborted_q);
  assign error_code_o = s_err_code_q;
  assign error_stage_o = s_err_stage_q;
  assign error_resp_o = s_err_resp_q;
  assign error_index_o = s_err_index_q;
  assign error_addr_o = s_err_addr_q;
  assign idle_o = s_state_q == Idle;
  assign job_status_o = {
    12'd0,
    s_job_resp_q,
    s_job_stage_q,
    s_job_code_q,
    s_writeback_pending,
    1'b0,
    (s_state_q == FetchRequest) || (s_state_q == FetchData),
    1'b0,
    s_job_aborted_q,
    s_job_err_q,
    s_job_done_q,
    s_job_busy_q
  };
  assign ring_status_o = {
    8'd0,
    s_last_index_q,
    s_pending_q,
    s_stopped_q,
    s_writeback_pending,
    s_pending_q != 8'd0,
    s_wrapped_q,
    s_ring_err_q,
    (s_head_q == ring_tail_i) && (s_state_q == Idle),
    s_state_q == Stalled,
    s_active_q
  };

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_timestamp_q <= 64'd0;
    end else begin
      s_timestamp_q <= s_timestamp_q + 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q          <= Idle;
      s_word_index_q     <= 6'd0;
      s_head_q           <= 8'd0;
      s_completed_q      <= 32'd0;
      s_active_q         <= 1'b0;
      s_ring_err_q       <= 1'b0;
      s_wrapped_q        <= 1'b0;
      s_stopped_q        <= 1'b0;
      s_pending_q        <= 8'd0;
      s_coalesce_timer_q <= 16'd0;
      s_last_index_q     <= 8'd0;
      s_job_busy_q       <= 1'b0;
      s_job_done_q       <= 1'b0;
      s_job_err_q        <= 1'b0;
      s_job_aborted_q    <= 1'b0;
      s_job_code_q       <= 6'd0;
      s_job_stage_q      <= 4'd0;
      s_job_resp_q       <= 2'd0;
      s_ring_event_q     <= 1'b0;
      s_err_event_q      <= 1'b0;
      s_abort_done_q     <= 1'b0;
      s_err_code_q       <= 6'd0;
      s_err_stage_q      <= 4'd0;
      s_err_resp_q       <= 2'd0;
      s_err_index_q      <= 8'd0;
      s_err_addr_q       <= 32'd0;
      s_abort_pending_q  <= 1'b0;
      s_ring_en_q        <= 1'b0;
    end else if (soft_reset_i) begin
      s_state_q          <= Idle;
      s_word_index_q     <= 6'd0;
      s_head_q           <= 8'd0;
      s_completed_q      <= 32'd0;
      s_active_q         <= 1'b0;
      s_ring_err_q       <= 1'b0;
      s_wrapped_q        <= 1'b0;
      s_stopped_q        <= 1'b0;
      s_pending_q        <= 8'd0;
      s_coalesce_timer_q <= 16'd0;
      s_last_index_q     <= 8'd0;
      s_job_busy_q       <= 1'b0;
      s_job_done_q       <= 1'b0;
      s_job_err_q        <= 1'b0;
      s_job_aborted_q    <= 1'b0;
      s_job_code_q       <= 6'd0;
      s_job_stage_q      <= 4'd0;
      s_job_resp_q       <= 2'd0;
      s_ring_event_q     <= 1'b0;
      s_err_event_q      <= 1'b0;
      s_abort_done_q     <= 1'b0;
      s_err_code_q       <= 6'd0;
      s_err_stage_q      <= 4'd0;
      s_err_resp_q       <= 2'd0;
      s_err_index_q      <= 8'd0;
      s_err_addr_q       <= 32'd0;
      s_abort_pending_q  <= 1'b0;
      s_ring_en_q        <= 1'b0;
    end else begin
      s_ring_event_q <= 1'b0;
      s_err_event_q  <= 1'b0;
      s_abort_done_q <= 1'b0;
      s_ring_en_q    <= ring_enable_i;

      if (counter_clear_i) s_completed_q <= 32'd0;
      if (ring_enable_i && !s_ring_en_q) begin
        s_ring_err_q       <= 1'b0;
        s_wrapped_q        <= 1'b0;
        s_stopped_q        <= 1'b0;
        s_pending_q        <= 8'd0;
        s_coalesce_timer_q <= 16'd0;
        s_last_index_q     <= 8'd0;
      end
      if (!ring_enable_i) begin
        s_active_q         <= 1'b0;
        s_pending_q        <= 8'd0;
        s_coalesce_timer_q <= 16'd0;
        if (s_state_q == Stalled) s_state_q <= Idle;
      end
      if (start_i && ring_enable_i && !quiesce_i && !abort_i && !s_active_q) begin
        s_wrapped_q        <= 1'b0;
        s_stopped_q        <= 1'b0;
        s_pending_q        <= 8'd0;
        s_coalesce_timer_q <= 16'd0;
        s_last_index_q     <= 8'd0;
        s_state_q          <= Idle;
        if (s_ring_config_valid) begin
          s_active_q   <= 1'b1;
          s_ring_err_q <= 1'b0;
        end else begin
          s_active_q    <= 1'b0;
          s_ring_err_q  <= 1'b1;
          s_err_event_q <= 1'b1;
          s_err_code_q  <= 6'd2;
          s_err_stage_q <= 4'd2;
          s_err_resp_q  <= 2'd0;
          s_err_index_q <= 8'd0;
          s_err_addr_q  <= ring_base_i;
          s_job_busy_q  <= 1'b0;
          s_job_done_q  <= 1'b0;
          s_job_err_q   <= 1'b1;
          s_job_code_q  <= 6'd2;
          s_job_stage_q <= 4'd2;
          s_job_resp_q  <= 2'd0;
        end
      end

      if (abort_i && (s_active_q || (s_state_q != Idle))) begin
        s_abort_pending_q  <= 1'b1;
        s_pending_q        <= 8'd0;
        s_coalesce_timer_q <= 16'd0;
        s_active_q         <= 1'b0;
      end

      case (s_state_q)
        Idle: begin
          if (abort_i && s_active_q) begin
            s_job_busy_q      <= 1'b0;
            s_abort_pending_q <= 1'b0;
            s_abort_done_q    <= 1'b1;
          end else if (s_active_q && (s_head_q != ring_tail_i) && !quiesce_i) begin
            s_word_index_q <= 6'd0;
            s_state_q      <= FetchRequest;
          end
        end
        FetchRequest: begin
          if (abort_i) begin
            s_state_q         <= Idle;
            s_job_busy_q      <= 1'b0;
            s_abort_pending_q <= 1'b0;
            s_abort_done_q    <= 1'b1;
          end else if (quiesce_i) begin
            s_state_q    <= Idle;
            s_job_busy_q <= 1'b0;
          end else if (dma_request_ready_i) begin
            s_state_q <= FetchData;
          end
        end
        FetchData: begin
          if (dma_read_axis.tvalid && dma_read_axis.tready) begin
            s_descriptor_q[s_word_index_q[4:0]] <= dma_read_axis.tdata;
            s_word_index_q                      <= s_word_index_q + 1'b1;
          end
          if (dma_done_i) begin
            if (dma_error_i) begin
              s_ring_err_q  <= 1'b1;
              s_err_event_q <= 1'b1;
              s_err_code_q  <= dma_error_code_i;
              s_err_stage_q <= dma_error_stage_i;
              s_err_resp_q  <= dma_error_resp_i;
              s_err_index_q <= s_head_q;
              s_err_addr_q  <= dma_error_addr_i;
              s_active_q    <= 1'b0;
              s_job_busy_q  <= 1'b0;
              s_job_done_q  <= 1'b0;
              s_job_err_q   <= 1'b1;
              s_job_code_q  <= dma_error_code_i;
              s_job_stage_q <= dma_error_stage_i;
              s_job_resp_q  <= dma_error_resp_i;
              if (abort_i || s_abort_pending_q) s_abort_done_q <= 1'b1;
              s_abort_pending_q <= 1'b0;
              s_state_q         <= Idle;
            end else if (abort_i || s_abort_pending_q) begin
              s_active_q        <= 1'b0;
              s_job_busy_q      <= 1'b0;
              s_abort_pending_q <= 1'b0;
              s_abort_done_q    <= 1'b1;
              s_state_q         <= Idle;
            end else begin
              s_state_q <= Evaluate;
            end
          end
        end
        Evaluate: begin
          if (abort_i) begin
            if (s_descriptor_q[0][`APB4_APU__DESCRIPTOR_CONTROL_OWN]) begin
              s_job_busy_q <= 1'b1;
              s_job_done_q <= 1'b0;
              s_job_err_q <= 1'b0;
              s_job_aborted_q <= 1'b1;
              s_job_code_q <= 6'd20;
              s_job_stage_q <= 4'd11;
              s_job_resp_q <= 2'd0;
              s_descriptor_q[0][`APB4_APU__DESCRIPTOR_CONTROL_OWN] <= 1'b0;
              s_descriptor_q[1] <= 32'd1 << `APB4_APU__DESCRIPTOR_STATUS_ABORTED;
              for (int result_word = 10; result_word < 16; result_word++) begin
                s_descriptor_q[result_word] <= 32'd0;
              end
              s_descriptor_q[18] <= s_timestamp_q[31:0];
              s_descriptor_q[19] <= s_timestamp_q[63:32];
              s_descriptor_q[20] <= s_timestamp_q[31:0];
              s_descriptor_q[21] <= s_timestamp_q[63:32];
              s_descriptor_q[22] <= 32'd0;
              s_descriptor_q[23] <= 32'd0;
              s_word_index_q     <= 6'd1;
              s_state_q          <= ResultWriteRequest;
            end else begin
              s_job_busy_q      <= 1'b0;
              s_abort_pending_q <= 1'b0;
              s_abort_done_q    <= 1'b1;
              s_state_q         <= Idle;
            end
          end else if (!s_descriptor_q[0][`APB4_APU__DESCRIPTOR_CONTROL_OWN]) begin
            s_state_q <= Stalled;
          end else if (!s_descriptor_valid) begin
            s_job_busy_q <= 1'b1;
            s_job_done_q <= 1'b0;
            s_job_err_q <= 1'b1;
            s_job_aborted_q <= 1'b0;
            s_job_code_q <= 6'd2;
            s_job_stage_q <= 4'd2;
            s_job_resp_q <= 2'd0;
            s_descriptor_q[0][`APB4_APU__DESCRIPTOR_CONTROL_OWN] <= 1'b0;
            s_descriptor_q[1] <= (32'd1 << `APB4_APU__DESCRIPTOR_STATUS_ERROR) |
                (32'd2 << `APB4_APU__DESCRIPTOR_STATUS_ERROR_CODE) |
                (32'd2 << `APB4_APU__DESCRIPTOR_STATUS_STAGE);
            for (int result_word = 10; result_word < 16; result_word++) begin
              s_descriptor_q[result_word] <= 32'd0;
            end
            s_descriptor_q[18] <= s_timestamp_q[31:0];
            s_descriptor_q[19] <= s_timestamp_q[63:32];
            s_descriptor_q[20] <= s_timestamp_q[31:0];
            s_descriptor_q[21] <= s_timestamp_q[63:32];
            s_descriptor_q[22] <= 32'd0;
            s_descriptor_q[23] <= 32'd0;
            s_word_index_q     <= 6'd1;
            s_state_q          <= ResultWriteRequest;
          end else begin
            s_job_busy_q    <= 1'b1;
            s_job_done_q    <= 1'b0;
            s_job_err_q     <= 1'b0;
            s_job_aborted_q <= 1'b0;
            s_job_code_q    <= 6'd0;
            s_job_stage_q   <= 4'd0;
            s_job_resp_q    <= 2'd0;
            for (int result_word = 10; result_word < 16; result_word++) begin
              s_descriptor_q[result_word] <= 32'd0;
            end
            s_descriptor_q[18] <= s_timestamp_q[31:0];
            s_descriptor_q[19] <= s_timestamp_q[63:32];
            s_descriptor_q[20] <= 32'd0;
            s_descriptor_q[21] <= 32'd0;
            s_descriptor_q[22] <= 32'd0;
            s_descriptor_q[23] <= 32'd0;
            s_state_q          <= BackendRequest;
          end
        end
        BackendRequest: begin
          if (abort_i) begin
            s_job_busy_q <= 1'b1;
            s_job_done_q <= 1'b0;
            s_job_err_q <= 1'b0;
            s_job_aborted_q <= 1'b1;
            s_job_code_q <= 6'd20;
            s_job_stage_q <= 4'd11;
            s_job_resp_q <= 2'd0;
            s_descriptor_q[0][`APB4_APU__DESCRIPTOR_CONTROL_OWN] <= 1'b0;
            s_descriptor_q[1] <= 32'd1 << `APB4_APU__DESCRIPTOR_STATUS_ABORTED;
            s_descriptor_q[20] <= s_timestamp_q[31:0];
            s_descriptor_q[21] <= s_timestamp_q[63:32];
            s_descriptor_q[22] <= 32'd0;
            s_descriptor_q[23] <= 32'd0;
            s_word_index_q <= 6'd1;
            s_state_q <= ResultWriteRequest;
          end else if (backend_job_ready_i) begin
            s_state_q <= BackendWait;
          end
        end
        BackendWait: begin
          if (backend_result_valid_i) begin
            s_job_err_q <= backend_result_error_i;
            s_job_code_q <= backend_result_code_i;
            s_job_stage_q <= backend_result_stage_i;
            s_job_resp_q <= backend_result_resp_i;
            s_job_aborted_q <= abort_i && backend_result_error_i;
            s_descriptor_q[0][`APB4_APU__DESCRIPTOR_CONTROL_OWN] <= 1'b0;
            s_descriptor_q[1] <= (backend_result_error_i ?
                (32'd1 << `APB4_APU__DESCRIPTOR_STATUS_ERROR) :
                (32'd1 << `APB4_APU__DESCRIPTOR_STATUS_DONE)) |
                ((abort_i && backend_result_error_i) ?
                 (32'd1 << `APB4_APU__DESCRIPTOR_STATUS_ABORTED) : 32'd0) |
                (32'(backend_result_code_i) << `APB4_APU__DESCRIPTOR_STATUS_ERROR_CODE) |
                (32'(backend_result_stage_i) << `APB4_APU__DESCRIPTOR_STATUS_STAGE) |
                (32'(backend_result_resp_i) << `APB4_APU__DESCRIPTOR_STATUS_AXI_RESPONSE);
            s_descriptor_q[10] <= backend_input_used_i;
            s_descriptor_q[11] <= backend_output_bytes_i;
            s_descriptor_q[12] <= backend_frames_i;
            s_descriptor_q[13] <= backend_source_info_i;
            s_descriptor_q[14] <= backend_cycles_i;
            s_descriptor_q[15] <= backend_detail_i;
            s_descriptor_q[20] <= s_timestamp_q[31:0];
            s_descriptor_q[21] <= s_timestamp_q[63:32];
            s_word_index_q <= 6'd1;
            s_state_q <= ResultWriteRequest;
          end else if (abort_i) begin
            s_job_busy_q <= 1'b1;
            s_job_done_q <= 1'b0;
            s_job_err_q <= 1'b0;
            s_job_aborted_q <= 1'b1;
            s_job_code_q <= 6'd20;
            s_job_stage_q <= 4'd11;
            s_job_resp_q <= 2'd0;
            s_descriptor_q[0][`APB4_APU__DESCRIPTOR_CONTROL_OWN] <= 1'b0;
            s_descriptor_q[1] <= 32'd1 << `APB4_APU__DESCRIPTOR_STATUS_ABORTED;
            s_descriptor_q[20] <= s_timestamp_q[31:0];
            s_descriptor_q[21] <= s_timestamp_q[63:32];
            s_descriptor_q[22] <= 32'd0;
            s_descriptor_q[23] <= 32'd0;
            s_word_index_q <= 6'd1;
            s_state_q <= ResultWriteRequest;
          end
        end
        ResultWriteRequest: begin
          if (dma_request_ready_i) s_state_q <= ResultWriteData;
        end
        ResultWriteData: begin
          if (dma_done_i) begin
            s_ring_err_q  <= 1'b1;
            s_err_event_q <= 1'b1;
            s_err_code_q  <= dma_error_code_i;
            s_err_stage_q <= dma_error_stage_i;
            s_err_resp_q  <= dma_error_resp_i;
            s_err_index_q <= s_head_q;
            s_err_addr_q  <= dma_error_addr_i;
            s_active_q    <= 1'b0;
            s_job_busy_q  <= 1'b0;
            s_job_done_q  <= 1'b0;
            s_job_err_q   <= 1'b1;
            s_job_code_q  <= dma_error_code_i;
            s_job_stage_q <= dma_error_stage_i;
            s_job_resp_q  <= dma_error_resp_i;
            if (abort_i || s_abort_pending_q) s_abort_done_q <= 1'b1;
            s_abort_pending_q <= 1'b0;
            s_state_q         <= Idle;
          end else if (dma_write_axis.tvalid && dma_write_axis.tready) begin
            s_word_index_q <= s_word_index_q + 1'b1;
            if (s_word_index_q == 6'd31) s_state_q <= ResultWriteWait;
          end
        end
        ResultWriteWait: begin
          if (dma_done_i) begin
            if (dma_error_i) begin
              s_ring_err_q  <= 1'b1;
              s_err_event_q <= 1'b1;
              s_err_code_q  <= dma_error_code_i;
              s_err_stage_q <= dma_error_stage_i;
              s_err_resp_q  <= dma_error_resp_i;
              s_err_index_q <= s_head_q;
              s_err_addr_q  <= dma_error_addr_i;
              s_active_q    <= 1'b0;
              s_job_busy_q  <= 1'b0;
              s_job_done_q  <= 1'b0;
              s_job_err_q   <= 1'b1;
              s_job_code_q  <= dma_error_code_i;
              s_job_stage_q <= dma_error_stage_i;
              s_job_resp_q  <= dma_error_resp_i;
              if (abort_i || s_abort_pending_q) s_abort_done_q <= 1'b1;
              s_abort_pending_q <= 1'b0;
              s_state_q         <= Idle;
            end else begin
              s_state_q <= OwnerWriteRequest;
            end
          end
        end
        OwnerWriteRequest: begin
          if (dma_request_ready_i) s_state_q <= OwnerWriteData;
        end
        OwnerWriteData: begin
          if (dma_done_i) begin
            s_ring_err_q  <= 1'b1;
            s_err_event_q <= 1'b1;
            s_err_code_q  <= dma_error_code_i;
            s_err_stage_q <= dma_error_stage_i;
            s_err_resp_q  <= dma_error_resp_i;
            s_err_index_q <= s_head_q;
            s_err_addr_q  <= dma_error_addr_i;
            s_active_q    <= 1'b0;
            s_job_busy_q  <= 1'b0;
            s_job_done_q  <= 1'b0;
            s_job_err_q   <= 1'b1;
            s_job_code_q  <= dma_error_code_i;
            s_job_stage_q <= dma_error_stage_i;
            s_job_resp_q  <= dma_error_resp_i;
            if (abort_i || s_abort_pending_q) s_abort_done_q <= 1'b1;
            s_abort_pending_q <= 1'b0;
            s_state_q         <= Idle;
          end else if (dma_write_axis.tvalid && dma_write_axis.tready) begin
            s_state_q <= OwnerWriteWait;
          end
        end
        OwnerWriteWait: begin
          if (dma_done_i) begin
            if (dma_error_i) begin
              s_ring_err_q  <= 1'b1;
              s_err_event_q <= 1'b1;
              s_err_code_q  <= dma_error_code_i;
              s_err_stage_q <= dma_error_stage_i;
              s_err_resp_q  <= dma_error_resp_i;
              s_err_index_q <= s_head_q;
              s_err_addr_q  <= dma_error_addr_i;
              s_active_q    <= 1'b0;
              s_job_busy_q  <= 1'b0;
              s_job_done_q  <= 1'b0;
              s_job_err_q   <= 1'b1;
              s_job_code_q  <= dma_error_code_i;
              s_job_stage_q <= dma_error_stage_i;
              s_job_resp_q  <= dma_error_resp_i;
            end else begin
              s_job_busy_q <= 1'b0;
              s_job_done_q <= !s_job_err_q && !s_job_aborted_q;
              if (!counter_clear_i) s_completed_q <= saturating_increment(s_completed_q);
              s_last_index_q <= s_head_q;
              s_head_q       <= s_next_head;
              if (s_next_head == 8'd0) s_wrapped_q <= 1'b1;
              if (abort_i || s_abort_pending_q || s_job_aborted_q) begin
                s_pending_q        <= 8'd0;
                s_coalesce_timer_q <= 16'd0;
              end else if (s_descriptor_ioc || (s_post_pending >= coalesce_count_i)) begin
                s_ring_event_q     <= 1'b1;
                s_pending_q        <= 8'd0;
                s_coalesce_timer_q <= 16'd0;
              end else begin
                s_pending_q <= s_post_pending;
                if (s_pending_q == 8'd0) s_coalesce_timer_q <= coalesce_timeout_i;
              end
              if (s_job_err_q) begin
                s_ring_err_q  <= 1'b1;
                s_err_event_q <= 1'b1;
                s_err_code_q  <= s_job_code_q;
                s_err_stage_q <= s_job_stage_q;
                s_err_resp_q  <= s_job_resp_q;
                s_err_index_q <= s_head_q;
                s_err_addr_q  <= s_descriptor_addr;
                if (stop_on_error_i) begin
                  s_stopped_q        <= 1'b1;
                  s_active_q         <= 1'b0;
                  s_pending_q        <= 8'd0;
                  s_coalesce_timer_q <= 16'd0;
                end
              end
            end
            if (abort_i || s_abort_pending_q || s_job_aborted_q) begin
              s_abort_pending_q <= 1'b0;
              s_abort_done_q    <= 1'b1;
            end
            s_state_q <= Idle;
          end
        end
        Stalled: begin
          if (abort_i) begin
            s_state_q         <= Idle;
            s_job_busy_q      <= 1'b0;
            s_abort_pending_q <= 1'b0;
            s_abort_done_q    <= 1'b1;
          end else if (quiesce_i) begin
            s_state_q    <= Idle;
            s_job_busy_q <= 1'b0;
          end else if ((s_head_q == ring_tail_i) || !s_active_q) begin
            s_state_q <= Idle;
          end else if (start_i && !quiesce_i) begin
            s_word_index_q <= 6'd0;
            s_state_q      <= FetchRequest;
          end
        end
        default: s_state_q <= Idle;
      endcase

      if ((s_pending_q != 8'd0) && (s_coalesce_timer_q != 16'd0) &&
          !((s_state_q == OwnerWriteWait) && dma_done_i) && !abort_i && ring_enable_i) begin
        if (s_coalesce_timer_q == 16'd1) begin
          s_ring_event_q     <= 1'b1;
          s_pending_q        <= 8'd0;
          s_coalesce_timer_q <= 16'd0;
        end else begin
          s_coalesce_timer_q <= s_coalesce_timer_q - 1'b1;
        end
      end
    end
  end
endmodule
