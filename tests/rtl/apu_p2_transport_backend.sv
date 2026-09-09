// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// Verification-only direct/ring client for the production APU DMA.
module apu_p2_transport_backend (
    // verilog_format: off -- preserve job, request, stream, and result columns
    input  logic                   clk_i,
    input  logic                   rst_n_i,
    input  logic                   abort_i,
    input  logic                   direct_start_i,
    input  logic [31:0]            direct_source_i,
    input  logic [31:0]            direct_destination_i,
    input  logic [31:0]            direct_bytes_i,
    input  logic                   job_valid_i,
    output logic                   job_ready_o,
    input  logic [1023:0]          descriptor_i,
    input  logic [7:0]             index_i,
    input  logic                   hold_result_i,
    input  logic                   inject_result_error_i,
    input  logic [5:0]             inject_result_code_i,
    input  logic [3:0]             inject_result_stage_i,
    input  logic [1:0]             inject_result_resp_i,
    output logic                   result_valid_o,
    input  logic                   result_ready_i,
    output logic                   result_error_o,
    output logic [5:0]             result_code_o,
    output logic [3:0]             result_stage_o,
    output logic [1:0]             result_resp_o,
    output logic [31:0]            input_used_o,
    output logic [31:0]            output_bytes_o,
    output logic [31:0]            frames_o,
    output logic [31:0]            source_info_o,
    output logic [31:0]            cycles_o,
    output logic [31:0]            detail_o,
    output logic [31:0]            accepted_jobs_o,
    output logic                   request_valid_o,
    input  logic                   request_ready_i,
    output logic                   request_write_o,
    output logic [31:0]            request_addr_o,
    output logic [31:0]            request_bytes_o,
    axi4_stream_if.sink            read_axis,
    axi4_stream_if.source          write_axis,
    input  logic                   dma_done_i,
    input  logic                   dma_error_i,
    input  logic                   dma_aborted_i,
    input  logic [5:0]             dma_error_code_i,
    input  logic [3:0]             dma_error_stage_i,
    input  logic [1:0]             dma_error_resp_i,
    output logic                   busy_o,
    output logic                   direct_done_o,
    output logic                   direct_error_o
    // verilog_format: on
);
  typedef enum logic [3:0] {
    Idle,
    ReadRequest,
    ReadData,
    ReadWait,
    WriteRequest,
    WriteData,
    WriteWait,
    Result
  } state_e;

  state_e        s_state_q;
  logic          s_ring_q;
  logic   [ 7:0] s_index_q;
  logic   [31:0] s_source_addr_q;
  logic   [31:0] s_destination_addr_q;
  logic   [31:0] s_bytes_q;
  logic   [ 5:0] s_read_index_q;
  logic   [ 5:0] s_write_index_q;
  logic   [31:0] s_buffer_q           [32];
  logic   [ 3:0] s_keep_q             [32];
  logic          s_result_error_q;
  logic   [ 5:0] s_result_code_q;
  logic   [ 3:0] s_result_stage_q;
  logic   [ 1:0] s_result_resp_q;
  logic   [31:0] s_accepted_jobs_q;
  logic          s_direct_done_q;
  logic          s_direct_error_q;
  logic          s_abort_pending_q;

  function automatic logic [31:0] bounded_bytes(input logic [31:0] length_i,
                                                input logic [31:0] capacity_i);
    return (length_i < capacity_i) ? length_i : capacity_i;
  endfunction

  assign job_ready_o = (s_state_q == Idle) && !direct_start_i && !abort_i;
  assign result_valid_o = (s_state_q == Result) && !hold_result_i;
  assign result_error_o = s_result_error_q;
  assign result_code_o = s_result_code_q;
  assign result_stage_o = s_result_stage_q;
  assign result_resp_o = s_result_resp_q;
  assign input_used_o = s_bytes_q;
  assign output_bytes_o = s_bytes_q;
  assign frames_o = s_bytes_q >> 2;
  assign source_info_o = 32'h0004_0000 | {24'd0, s_index_q};
  assign cycles_o = 32'd64 + {24'd0, s_index_q};
  assign detail_o = 32'h5032_0000 | {24'd0, s_index_q};
  assign accepted_jobs_o = s_accepted_jobs_q;
  assign request_valid_o = !abort_i && ((s_state_q == ReadRequest) || (s_state_q == WriteRequest));
  assign request_write_o = s_state_q == WriteRequest;
  assign request_addr_o = request_write_o ? s_destination_addr_q : s_source_addr_q;
  assign request_bytes_o = s_bytes_q;
  assign read_axis.tready = s_state_q == ReadData;
  assign write_axis.tdata = s_buffer_q[s_write_index_q[4:0]];
  assign write_axis.tkeep = s_keep_q[s_write_index_q[4:0]];
  assign write_axis.tstrb = s_keep_q[s_write_index_q[4:0]];
  assign write_axis.tlast = s_write_index_q == s_read_index_q;
  assign write_axis.tid = '0;
  assign write_axis.tdest = '0;
  assign write_axis.tuser = '0;
  assign write_axis.tvalid = s_state_q == WriteData;
  assign busy_o = s_state_q != Idle;
  assign direct_done_o = s_direct_done_q;
  assign direct_error_o = s_direct_error_q;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q            <= Idle;
      s_ring_q             <= 1'b0;
      s_index_q            <= 8'd0;
      s_source_addr_q      <= 32'd0;
      s_destination_addr_q <= 32'd0;
      s_bytes_q            <= 32'd0;
      s_read_index_q       <= 6'd0;
      s_write_index_q      <= 6'd0;
      s_result_error_q     <= 1'b0;
      s_result_code_q      <= 6'd0;
      s_result_stage_q     <= 4'd0;
      s_result_resp_q      <= 2'd0;
      s_accepted_jobs_q    <= 32'd0;
      s_direct_done_q      <= 1'b0;
      s_direct_error_q     <= 1'b0;
      s_abort_pending_q    <= 1'b0;
    end else begin
      s_direct_done_q <= 1'b0;
      if (abort_i && (s_state_q != Idle)) s_abort_pending_q <= 1'b1;
      unique case (s_state_q)
        Idle: begin
          if (job_valid_i && job_ready_o) begin
            s_ring_q <= 1'b1;
            s_index_q <= index_i;
            s_source_addr_q <= descriptor_i[(2*32)+:32];
            s_destination_addr_q <= descriptor_i[(4*32)+:32];
            s_bytes_q <= bounded_bytes(descriptor_i[(3*32)+:32], descriptor_i[(5*32)+:32]);
            s_read_index_q <= 6'd0;
            s_write_index_q <= 6'd0;
            s_result_error_q <= 1'b0;
            s_result_code_q <= 6'd0;
            s_result_stage_q <= 4'd0;
            s_result_resp_q <= 2'd0;
            s_accepted_jobs_q <= s_accepted_jobs_q + 1'b1;
            s_abort_pending_q <= 1'b0;
            s_state_q <= ReadRequest;
          end else if (direct_start_i && !abort_i) begin
            s_ring_q             <= 1'b0;
            s_index_q            <= 8'd0;
            s_source_addr_q      <= direct_source_i;
            s_destination_addr_q <= direct_destination_i;
            s_bytes_q            <= direct_bytes_i;
            s_read_index_q       <= 6'd0;
            s_write_index_q      <= 6'd0;
            s_direct_error_q     <= 1'b0;
            s_abort_pending_q    <= 1'b0;
            s_state_q            <= ReadRequest;
          end
        end
        ReadRequest: begin
          if (abort_i) begin
            s_state_q         <= Idle;
            s_abort_pending_q <= 1'b0;
            if (!s_ring_q) begin
              s_direct_done_q  <= 1'b1;
              s_direct_error_q <= 1'b1;
            end
          end else if (request_ready_i) begin
            s_state_q <= ReadData;
          end
        end
        ReadData: begin
          if (read_axis.tvalid && read_axis.tready) begin
            s_buffer_q[s_read_index_q[4:0]] <= read_axis.tdata;
            s_keep_q[s_read_index_q[4:0]]   <= read_axis.tkeep;
            if (read_axis.tlast) s_state_q <= ReadWait;
            else s_read_index_q <= s_read_index_q + 1'b1;
          end
          if (dma_done_i && (s_abort_pending_q || dma_aborted_i)) begin
            s_state_q         <= Idle;
            s_abort_pending_q <= 1'b0;
            if (!s_ring_q) begin
              s_direct_done_q  <= 1'b1;
              s_direct_error_q <= 1'b1;
            end
          end else if (dma_done_i && dma_error_i) begin
            s_result_error_q <= 1'b1;
            s_result_code_q  <= dma_error_code_i;
            s_result_stage_q <= dma_error_stage_i;
            s_result_resp_q  <= dma_error_resp_i;
            s_state_q        <= s_ring_q ? Result : Idle;
            if (!s_ring_q) begin
              s_direct_done_q  <= 1'b1;
              s_direct_error_q <= 1'b1;
            end
          end
        end
        ReadWait: begin
          if (dma_done_i) begin
            if (s_abort_pending_q || dma_aborted_i) begin
              s_state_q         <= Idle;
              s_abort_pending_q <= 1'b0;
              if (!s_ring_q) begin
                s_direct_done_q  <= 1'b1;
                s_direct_error_q <= 1'b1;
              end
            end else if (dma_error_i) begin
              s_result_error_q <= 1'b1;
              s_result_code_q  <= dma_error_code_i;
              s_result_stage_q <= dma_error_stage_i;
              s_result_resp_q  <= dma_error_resp_i;
              s_state_q        <= s_ring_q ? Result : Idle;
              if (!s_ring_q) begin
                s_direct_done_q  <= 1'b1;
                s_direct_error_q <= 1'b1;
              end
            end else begin
              s_write_index_q <= 6'd0;
              s_state_q       <= WriteRequest;
            end
          end
        end
        WriteRequest: begin
          if (abort_i) begin
            s_state_q         <= Idle;
            s_abort_pending_q <= 1'b0;
            if (!s_ring_q) begin
              s_direct_done_q  <= 1'b1;
              s_direct_error_q <= 1'b1;
            end
          end else if (request_ready_i) begin
            s_state_q <= WriteData;
          end
        end
        WriteData: begin
          if (dma_done_i && (s_abort_pending_q || dma_aborted_i)) begin
            s_state_q         <= Idle;
            s_abort_pending_q <= 1'b0;
            if (!s_ring_q) begin
              s_direct_done_q  <= 1'b1;
              s_direct_error_q <= 1'b1;
            end
          end else if (dma_done_i && dma_error_i) begin
            s_result_error_q <= 1'b1;
            s_result_code_q  <= dma_error_code_i;
            s_result_stage_q <= dma_error_stage_i;
            s_result_resp_q  <= dma_error_resp_i;
            s_state_q        <= s_ring_q ? Result : Idle;
            if (!s_ring_q) begin
              s_direct_done_q  <= 1'b1;
              s_direct_error_q <= 1'b1;
            end
          end else if (write_axis.tvalid && write_axis.tready) begin
            if (write_axis.tlast) s_state_q <= WriteWait;
            else s_write_index_q <= s_write_index_q + 1'b1;
          end
        end
        WriteWait: begin
          if (dma_done_i) begin
            s_result_error_q <= dma_error_i || inject_result_error_i;
            s_result_code_q  <= dma_error_i ? dma_error_code_i : inject_result_code_i;
            s_result_stage_q <= dma_error_i ? dma_error_stage_i : inject_result_stage_i;
            s_result_resp_q  <= dma_error_i ? dma_error_resp_i : inject_result_resp_i;
            if (s_abort_pending_q || dma_aborted_i) begin
              s_state_q         <= Idle;
              s_abort_pending_q <= 1'b0;
            end else begin
              s_state_q <= s_ring_q ? Result : Idle;
            end
            if (!s_ring_q) begin
              s_direct_done_q  <= 1'b1;
              s_direct_error_q <= dma_error_i || dma_aborted_i || s_abort_pending_q;
            end
          end
        end
        Result: begin
          if (result_valid_o && result_ready_i) begin
            s_state_q         <= Idle;
            s_abort_pending_q <= 1'b0;
          end
        end
        default: s_state_q <= Idle;
      endcase
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_n_i && job_valid_i && job_ready_o && ((bounded_bytes(
            descriptor_i[(3*32)+:32], descriptor_i[(5*32)+:32]
        ) == 32'd0) || (bounded_bytes(
            descriptor_i[(3*32)+:32], descriptor_i[(5*32)+:32]
        ) > 32'd128))) begin
      $fatal(1, "apu_p2_transport_backend: ring transfer bytes must be in [1, 128]");
    end
    if (rst_n_i && direct_start_i &&
        ((direct_bytes_i == 32'd0) || (direct_bytes_i > 32'd128))) begin
      $fatal(1, "apu_p2_transport_backend: direct transfer bytes must be in [1, 128]");
    end
  end
`endif
endmodule
