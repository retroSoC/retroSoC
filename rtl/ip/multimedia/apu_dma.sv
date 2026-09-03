// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"
`include "axi4_define.svh"

module apu_dma (
    // verilog_format: off -- preserve command, result, and bus columns
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 abort_i,
    input  logic                 quiesce_i,
    input  logic [7:0]           bridge_epoch_i,
    input  logic                 perf_enable_i,
    input  logic                 counter_clear_i,
    input  logic                 request_valid_i,
    output logic                 request_ready_o,
    input  logic                 request_write_i,
    input  logic [31:0]          request_addr_i,
    input  logic [31:0]          request_bytes_i,
    input  logic [31:0]          read_base_i,
    input  logic [31:0]          read_limit_i,
    input  logic [31:0]          write_base_i,
    input  logic [31:0]          write_limit_i,
    input  logic [31:0]          timeout_i,
    axi4_stream_if.source        read_axis,
    axi4_stream_if.sink          write_axis,
    output logic                 busy_o,
    output logic                 done_o,
    output logic                 error_o,
    output logic                 aborted_o,
    output logic                 aborting_o,
    output logic [5:0]           error_code_o,
    output logic [3:0]           error_stage_o,
    output logic [1:0]           error_resp_o,
    output logic [31:0]          error_addr_o,
    output logic                 input_pending_o,
    output logic                 output_pending_o,
    output logic [63:0]          read_bytes_o,
    output logic [63:0]          write_bytes_o,
    output logic [63:0]          read_stalls_o,
    output logic [63:0]          write_stalls_o,
    axi4_if.master               axi4
    // verilog_format: on
);
  typedef enum logic [2:0] {
    Idle,
    ReadStart,
    ReadData,
    WriteStart,
    WriteData,
    WriteResponse
  } state_e;

  state_e        s_state_q;
  logic   [31:0] s_addr_q;
  logic   [31:0] s_remaining_q;
  logic   [ 4:0] s_burst_beats_q;
  logic   [31:0] s_timeout_q;
  logic          s_drain_q;
  logic          s_err_q;
  logic          s_aborted_q;
  logic   [ 5:0] s_err_code_q;
  logic   [ 3:0] s_err_stage_q;
  logic   [ 1:0] s_err_resp_q;
  logic   [31:0] s_err_addr_q;
  logic          s_done_q;
  logic   [63:0] s_read_bytes_q;
  logic   [63:0] s_write_bytes_q;
  logic   [63:0] s_read_stalls_q;
  logic   [63:0] s_write_stalls_q;
  logic   [ 4:0] s_sel_beats;
  logic   [31:0] s_beat_bytes;
  logic   [ 3:0] s_expected_keep;
  logic          s_read_start_ready;
  logic          s_read_busy;
  logic          s_read_valid;
  logic          s_read_ready;
  logic   [31:0] s_read_data;
  logic   [ 1:0] s_read_resp;
  logic          s_read_last;
  logic          s_read_expected_last;
  logic          s_read_id_error;
  logic          s_read_done;
  logic          s_write_start_ready;
  logic          s_write_busy;
  logic          s_write_ready;
  logic          s_write_done;
  logic   [ 1:0] s_write_resp;
  logic          s_write_id_error;
  logic          s_progress;
  logic          s_timeout_expire;
  logic          s_read_fault;
  logic          s_write_fault;
  logic          s_payload_fault;
  logic          s_timeout_active;
  logic          s_bridge_flush;
  logic          s_read_missing_last;
  logic          s_req_range_valid;
  logic   [32:0] s_req_last;
  logic   [ 7:0] s_bridge_epoch_q;

  function automatic logic [4:0] choose_burst(input logic [11:0] addr_i,
                                              input logic [31:0] bytes_i);
    logic [31:0] s_needed;
    logic [31:0] s_boundary;
    logic [31:0] s_sel;
    begin
      s_needed   = (bytes_i + 32'd3) >> 2;
      s_boundary = (32'd4096 - {20'd0, addr_i}) >> 2;
      s_sel      = s_needed;
      if (s_sel > 32'd16) s_sel = 32'd16;
      if (s_sel > s_boundary) s_sel = s_boundary;
      if (s_sel == 32'd0) s_sel = 32'd1;
      return s_sel[4:0];
    end
  endfunction

  function automatic logic [3:0] byte_mask(input logic [31:0] bytes_i);
    case (bytes_i)
      32'd1:   byte_mask = 4'b0001;
      32'd2:   byte_mask = 4'b0011;
      32'd3:   byte_mask = 4'b0111;
      default: byte_mask = 4'b1111;
    endcase
  endfunction

  function automatic logic [63:0] saturating_add(input logic [63:0] value_i,
                                                 input logic [31:0] increment_i);
    logic [64:0] s_sum;
    begin
      s_sum = {1'b0, value_i} + {33'd0, increment_i};
      return s_sum[64] ? 64'hffff_ffff_ffff_ffff : s_sum[63:0];
    end
  endfunction

  assign s_sel_beats = choose_burst(s_addr_q[11:0], s_remaining_q);
  assign s_beat_bytes = (s_remaining_q < 32'd4) ? s_remaining_q : 32'd4;
  assign s_expected_keep = byte_mask(s_beat_bytes);
  assign s_req_last = {1'b0, request_addr_i} + {1'b0, request_bytes_i} - 1'b1;
  assign s_req_range_valid = (request_bytes_i != 32'd0) && !s_req_last[32] &&
      (request_addr_i[1:0] == 2'd0) &&
      (request_write_i ? ((request_addr_i >= write_base_i) &&
                          (s_req_last[31:0] <= write_limit_i)) :
                         ((request_addr_i >= read_base_i) &&
                          (s_req_last[31:0] <= read_limit_i)));
  assign request_ready_o = (s_state_q == Idle) && !quiesce_i && !abort_i && !s_bridge_flush;
  assign busy_o = s_state_q != Idle;
  assign done_o = s_done_q;
  assign error_o = s_err_q;
  assign aborted_o = s_aborted_q;
  assign aborting_o = busy_o && s_drain_q && s_aborted_q;
  assign error_code_o = s_err_code_q;
  assign error_stage_o = s_err_stage_q;
  assign error_resp_o = s_err_resp_q;
  assign error_addr_o = s_err_addr_q;
  assign input_pending_o = (s_state_q == ReadStart) || (s_state_q == ReadData);
  assign output_pending_o = (s_state_q == WriteStart) || (s_state_q == WriteData) ||
                            (s_state_q == WriteResponse);
  assign read_bytes_o = s_read_bytes_q;
  assign write_bytes_o = s_write_bytes_q;
  assign read_stalls_o = s_read_stalls_q;
  assign write_stalls_o = s_write_stalls_q;

  assign read_axis.tdata = s_read_data;
  assign read_axis.tkeep = s_expected_keep;
  assign read_axis.tstrb = s_expected_keep;
  assign read_axis.tlast = s_remaining_q <= 32'd4;
  assign read_axis.tid = '0;
  assign read_axis.tdest = '0;
  assign read_axis.tuser = '0;
  assign read_axis.tvalid = (s_state_q == ReadData) && s_read_valid && !s_drain_q && !s_read_fault;
  assign s_read_ready = (s_state_q == ReadData) && (s_drain_q || s_read_fault || read_axis.tready);
  assign s_read_fault = s_read_valid &&
      ((s_read_resp != `AXI4_RESP_OKAY) || s_read_id_error ||
       (s_read_last != s_read_expected_last));
  assign s_read_missing_last = (s_state_q == ReadData) && s_read_valid && s_read_ready &&
      s_read_expected_last && !s_read_last;

  assign s_payload_fault = write_axis.tvalid &&
      ((write_axis.tkeep != s_expected_keep) || (write_axis.tstrb != s_expected_keep) ||
       (write_axis.tlast != (s_remaining_q <= 32'd4)));
  assign write_axis.tready = (s_state_q == WriteData) && s_write_ready && !s_drain_q &&
                             !s_payload_fault;
  assign s_write_fault = s_write_done && ((s_write_resp != `AXI4_RESP_OKAY) || s_write_id_error);
  assign s_progress = (axi4.awvalid && axi4.awready) || (axi4.wvalid && axi4.wready) ||
                      (axi4.bvalid && axi4.bready) || (axi4.arvalid && axi4.arready) ||
                      (axi4.rvalid && axi4.rready);
  assign s_timeout_active = s_read_busy || s_write_busy;
  assign s_timeout_expire = s_timeout_active && !s_progress && (s_timeout_q == 32'd1);
  assign s_bridge_flush = bridge_epoch_i != s_bridge_epoch_q;

  dma_axi4_master #(
      .AddrWidth    (32),
      .DataWidth    (32),
      .MaxBurstBeats(16)
  ) u_axi4_master (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .clear_i(s_bridge_flush || s_read_missing_last),
      .read_start_valid_i((s_state_q == ReadStart) && !s_drain_q && !abort_i && !s_timeout_expire),
      .read_start_ready_o(s_read_start_ready),
      .read_addr_i(s_addr_q),
      .read_beats_i(s_sel_beats),
      .read_fixed_i(1'b0),
      .read_busy_o(s_read_busy),
      .read_beat_valid_o(s_read_valid),
      .read_beat_ready_i(s_read_ready),
      .read_data_o(s_read_data),
      .read_resp_o(s_read_resp),
      .read_last_o(s_read_last),
      .read_expected_last_o(s_read_expected_last),
      .read_id_error_o(s_read_id_error),
      .read_done_o(s_read_done),
      .write_start_valid_i((s_state_q == WriteStart) && !s_drain_q && !abort_i &&
                           !s_timeout_expire),
      .write_start_ready_o(s_write_start_ready),
      .write_addr_i(s_addr_q),
      .write_beats_i(s_sel_beats),
      .write_fixed_i(1'b0),
      .write_busy_o(s_write_busy),
      .write_data_valid_i  ((s_state_q == WriteData) &&
                            (s_drain_q || s_payload_fault || write_axis.tvalid)),
      .write_data_ready_o(s_write_ready),
      .write_data_i((s_drain_q || s_payload_fault) ? 32'd0 : write_axis.tdata),
      .write_strb_i((s_drain_q || s_payload_fault) ? 4'd0 : write_axis.tkeep),
      .write_done_o(s_write_done),
      .write_resp_o(s_write_resp),
      .write_id_error_o(s_write_id_error),
      .axi4(axi4)
  );

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q        <= Idle;
      s_addr_q         <= 32'd0;
      s_remaining_q    <= 32'd0;
      s_burst_beats_q  <= 5'd0;
      s_timeout_q      <= 32'd0;
      s_drain_q        <= 1'b0;
      s_err_q          <= 1'b0;
      s_aborted_q      <= 1'b0;
      s_err_code_q     <= 6'd0;
      s_err_stage_q    <= 4'd0;
      s_err_resp_q     <= 2'd0;
      s_err_addr_q     <= 32'd0;
      s_done_q         <= 1'b0;
      s_read_bytes_q   <= 64'd0;
      s_write_bytes_q  <= 64'd0;
      s_read_stalls_q  <= 64'd0;
      s_write_stalls_q <= 64'd0;
      s_bridge_epoch_q <= 8'd0;
    end else begin
      s_done_q         <= 1'b0;
      s_bridge_epoch_q <= bridge_epoch_i;
      if (counter_clear_i) begin
        s_read_bytes_q   <= 64'd0;
        s_write_bytes_q  <= 64'd0;
        s_read_stalls_q  <= 64'd0;
        s_write_stalls_q <= 64'd0;
      end
      if (s_bridge_flush) begin
        s_timeout_q <= 32'd0;
        s_drain_q   <= 1'b0;
        if (s_state_q != Idle) begin
          s_state_q     <= Idle;
          s_done_q      <= 1'b1;
          s_err_q       <= 1'b1;
          s_aborted_q   <= s_aborted_q || abort_i;
          s_err_code_q  <= output_pending_o ? 6'd16 : 6'd15;
          s_err_stage_q <= output_pending_o ? 4'd8 : 4'd3;
          s_err_resp_q  <= `AXI4_RESP_DECODE_ERROR;
          s_err_addr_q  <= s_addr_q;
        end
      end else if (request_valid_i && request_ready_o) begin
        s_drain_q     <= 1'b0;
        s_err_q       <= 1'b0;
        s_aborted_q   <= 1'b0;
        s_err_code_q  <= 6'd0;
        s_err_stage_q <= 4'd0;
        s_err_resp_q  <= 2'd0;
        s_err_addr_q  <= 32'd0;
        s_addr_q      <= request_addr_i;
        s_remaining_q <= request_bytes_i;
        s_timeout_q   <= timeout_i;
        if (!s_req_range_valid) begin
          s_err_q       <= 1'b1;
          s_err_code_q  <= request_write_i ? 6'd16 : 6'd15;
          s_err_stage_q <= request_write_i ? 4'd8 : 4'd3;
          s_err_resp_q  <= `AXI4_RESP_SLAVE_ERROR;
          s_err_addr_q  <= request_addr_i;
          s_done_q      <= 1'b1;
        end else begin
          s_state_q <= request_write_i ? WriteStart : ReadStart;
        end
      end else if (s_state_q != Idle) begin
        if (s_progress) s_timeout_q <= timeout_i;
        else if (s_timeout_active && (s_timeout_q != 32'd0)) s_timeout_q <= s_timeout_q - 1'b1;
        if (perf_enable_i && !counter_clear_i && input_pending_o && !s_progress)
          s_read_stalls_q <= saturating_add(s_read_stalls_q, 1);
        if (perf_enable_i && !counter_clear_i && output_pending_o && !s_progress)
          s_write_stalls_q <= saturating_add(s_write_stalls_q, 1);
        if ((abort_i || s_timeout_expire) && !s_drain_q) begin
          s_drain_q     <= 1'b1;
          s_timeout_q   <= 32'd0;
          s_err_q       <= s_timeout_expire;
          s_aborted_q   <= abort_i;
          s_err_code_q  <= s_timeout_expire ? 6'd17 : 6'd20;
          s_err_stage_q <= output_pending_o ? 4'd8 : 4'd3;
          s_err_addr_q  <= s_addr_q;
        end
        case (s_state_q)
          ReadStart: begin
            if (s_drain_q) begin
              s_state_q   <= Idle;
              s_done_q    <= 1'b1;
              s_drain_q   <= 1'b0;
              s_timeout_q <= 32'd0;
            end else if (s_read_start_ready && !abort_i && !s_timeout_expire) begin
              s_state_q <= ReadData;
            end
          end
          ReadData: begin
            if (s_read_valid && s_read_ready) begin
              if (s_read_fault) begin
                s_err_q       <= 1'b1;
                s_err_code_q  <= 6'd15;
                s_err_stage_q <= 4'd3;
                s_err_resp_q  <= s_read_resp;
                s_err_addr_q  <= s_addr_q;
                s_drain_q     <= 1'b1;
              end else if (perf_enable_i && !s_drain_q && !counter_clear_i) begin
                s_read_bytes_q <= saturating_add(s_read_bytes_q, s_beat_bytes);
              end
              s_addr_q      <= s_addr_q + s_beat_bytes;
              s_remaining_q <= s_remaining_q - s_beat_bytes;
              if (s_read_missing_last) begin
                s_state_q   <= Idle;
                s_done_q    <= 1'b1;
                s_drain_q   <= 1'b0;
                s_timeout_q <= 32'd0;
              end else if (s_read_last) begin
                if (s_drain_q || s_read_fault || (s_remaining_q <= 32'd4)) begin
                  s_state_q   <= Idle;
                  s_done_q    <= 1'b1;
                  s_drain_q   <= 1'b0;
                  s_timeout_q <= 32'd0;
                end else begin
                  s_state_q <= ReadStart;
                end
              end
            end
          end
          WriteStart: begin
            if (s_drain_q) begin
              s_state_q   <= Idle;
              s_done_q    <= 1'b1;
              s_drain_q   <= 1'b0;
              s_timeout_q <= 32'd0;
            end else if (s_write_start_ready && !abort_i && !s_timeout_expire) begin
              s_burst_beats_q <= s_sel_beats;
              s_state_q       <= WriteData;
            end
          end
          WriteData: begin
            if (s_write_ready && (s_drain_q || s_payload_fault || write_axis.tvalid)) begin
              if (s_payload_fault && !s_err_q && !s_drain_q) begin
                s_err_q       <= 1'b1;
                s_err_code_q  <= 6'd16;
                s_err_stage_q <= 4'd8;
                s_err_resp_q  <= `AXI4_RESP_SLAVE_ERROR;
                s_err_addr_q  <= s_addr_q;
                s_drain_q     <= 1'b1;
              end else if (perf_enable_i && !s_drain_q && !counter_clear_i) begin
                s_write_bytes_q <= saturating_add(s_write_bytes_q, s_beat_bytes);
              end
              s_addr_q        <= s_addr_q + s_beat_bytes;
              s_remaining_q   <= s_remaining_q - s_beat_bytes;
              s_burst_beats_q <= s_burst_beats_q - 1'b1;
              if (s_burst_beats_q == 5'd1) s_state_q <= WriteResponse;
            end
          end
          WriteResponse: begin
            if (s_write_done) begin
              if (s_write_fault) begin
                s_err_q       <= 1'b1;
                s_err_code_q  <= 6'd16;
                s_err_stage_q <= 4'd8;
                s_err_resp_q  <= s_write_resp;
                s_err_addr_q  <= s_addr_q;
              end
              if (s_drain_q || s_write_fault || (s_remaining_q == 32'd0)) begin
                s_state_q   <= Idle;
                s_done_q    <= 1'b1;
                s_drain_q   <= 1'b0;
                s_timeout_q <= 32'd0;
              end else begin
                s_state_q <= WriteStart;
              end
            end
          end
          default: s_state_q <= Idle;
        endcase
      end
    end
  end

  logic s_unused_master_status;
  assign s_unused_master_status = s_read_busy ^ s_read_done ^ s_write_busy;
endmodule
