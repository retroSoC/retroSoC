// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING, BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`timescale 1ns / 1ps

`include "axi4_define.svh"

module sdio_dma #(
    parameter int AddrWidth = 32,
    parameter int DataWidth = 32,
    parameter int DescCount = 16
) (
    input  logic                          clk_i,
    input  logic                          rst_n_i,
    input  logic                          start_i,
    input  logic                          abort_i,
    input  logic                          direction_i,
    input  logic          [AddrWidth-1:0] desc_base_i,
    input  logic          [         15:0] desc_count_i,
    input  logic          [         31:0] total_bytes_i,
    input  logic                          data_in_valid_i,
    output logic                          data_in_ready_o,
    input  logic          [         31:0] data_in_i,
    input  logic          [          3:0] data_in_strb_i,
    input  logic                          data_in_last_i,
    output logic                          data_out_valid_o,
    input  logic                          data_out_ready_i,
    output logic          [         31:0] data_out_o,
    output logic          [          3:0] data_out_strb_o,
    output logic                          data_out_last_o,
    output logic                          busy_o,
    output logic                          done_o,
    output logic                          error_o,
    output logic          [          7:0] error_code_o,
    output logic          [AddrWidth-1:0] current_desc_o,
    output logic          [         31:0] bytes_done_o,
    output logic          [AddrWidth-1:0] error_addr_o,
    output logic                          descriptor_irq_o,
    output logic                          abort_done_o,
           axi4_if.master                 dma_axi4
);
  localparam logic [15:0] DescCountLimit = 16'(DescCount);

  typedef enum logic [3:0] {
    Idle,
    FetchStart,
    FetchWait,
    Validate,
    PayloadReadStart,
    PayloadReadWait,
    PayloadWriteStart,
    PayloadWriteWait,
    WritebackStart,
    WritebackWait,
    Terminal
  } dma_state_e;

  dma_state_e s_state_d, s_state_q;
  logic [AddrWidth-1:0] s_desc_addr_d, s_desc_addr_q;
  logic [15:0] s_desc_limit_d, s_desc_limit_q;
  logic [15:0] s_desc_index_d, s_desc_index_q;
  logic s_direction_d, s_direction_q;
  logic [31:0] s_total_bytes_d, s_total_bytes_q;
  logic [31:0] s_total_seen_d, s_total_seen_q;
  logic [31:0] s_total_done_d, s_total_done_q;
  logic [31:0] s_desc_progress_d, s_desc_progress_q;
  logic [4:0] s_burst_beats_d, s_burst_beats_q;
  logic [4:0] s_burst_index_d, s_burst_index_q;
  logic [31:0] s_desc_buffer_d, s_desc_buffer_q;
  logic [31:0] s_desc_count_d, s_desc_count_q;
  logic [31:0] s_desc_next_d, s_desc_next_q;
  logic [31:0] s_desc_control_d, s_desc_control_q;
  logic [31:0] s_writeback_control_d, s_writeback_control_q;
  logic [31:0] s_fetch_word_d[0:3];
  logic [31:0] s_fetch_word_q[0:3];
  logic s_desc_end_d, s_desc_end_q;
  logic s_desc_irq_d, s_desc_irq_q;
  logic s_fault_d, s_fault_q;
  logic [7:0] s_err_code_d, s_err_code_q;
  logic [AddrWidth-1:0] s_err_addr_d, s_err_addr_q;
  logic s_done_d, s_done_q;
  logic s_err_sticky_d, s_err_sticky_q;
  logic s_abort_pending_d, s_abort_pending_q;
  logic s_write_final_sent_d, s_write_final_sent_q;
  logic [4:0] s_write_beat_count_d, s_write_beat_count_q;
  logic s_descriptor_irq_d, s_descriptor_irq_q;
  logic s_abort_done_d, s_abort_done_q;

  logic                 s_read_start_valid;
  logic                 s_read_start_ready;
  logic [AddrWidth-1:0] s_read_addr;
  logic [          4:0] s_read_beats;
  logic                 s_read_beat_valid;
  logic                 s_read_beat_ready;
  logic [DataWidth-1:0] s_read_data;
  logic [          1:0] s_read_resp;
  logic                 s_read_last;
  logic                 s_read_expected_last;
  logic                 s_read_id_error;
  logic                 s_read_done;
  logic                 s_write_start_valid;
  logic                 s_write_start_ready;
  logic [AddrWidth-1:0] s_write_addr;
  logic [          4:0] s_write_beats;
  logic                 s_write_data_valid;
  logic                 s_write_data_ready;
  logic [DataWidth-1:0] s_write_data;
  logic [          3:0] s_write_strb;
  logic                 s_write_done;
  logic [          1:0] s_write_resp;
  logic                 s_write_id_error;
  logic                 s_read_busy;
  logic                 s_write_busy;

  logic [         31:0] s_payload_addr;
  logic [         31:0] s_payload_left;
  logic [          4:0] s_payload_beats;
  logic [         31:0] s_burst_offset;
  logic [         31:0] s_beat_left;
  logic [          2:0] s_beat_bytes;
  logic [         31:0] s_progress_after_beat;
  logic [          2:0] s_input_bytes;
  logic                 s_axi_read_fault;
  logic                 s_axi_write_fault;

  function automatic logic [4:0] choose_burst(input logic [11:0] addr_low_i,
                                              input logic [31:0] bytes_i);
    logic [31:0] needed;
    logic [31:0] boundary;
    logic [31:0] selected;
    begin
      needed   = (bytes_i + 32'd3) >> 2;
      boundary = (32'd4096 - {20'd0, addr_low_i}) >> 2;
      selected = needed;
      if (selected > 32'd16) selected = 32'd16;
      if (selected > boundary) selected = boundary;
      if (selected == 32'd0) selected = 32'd1;
      return selected[4:0];
    end
  endfunction

  function automatic logic [2:0] beat_bytes(input logic [31:0] bytes_i);
    return (bytes_i >= 32'd4) ? 3'd4 : bytes_i[2:0];
  endfunction

  function automatic logic strobe_valid(input logic [3:0] strb_i);
    return (strb_i != 4'd0) && ((strb_i & (strb_i + 4'd1)) == 4'd0);
  endfunction

  assign s_payload_addr = s_desc_buffer_q + s_desc_progress_q;
  assign s_payload_left = s_desc_count_q - s_desc_progress_q;
  assign s_payload_beats = choose_burst(s_payload_addr[11:0], s_payload_left);
  assign s_burst_offset = {27'd0, s_burst_index_q} << 2;
  assign s_beat_left = s_payload_left;
  assign s_beat_bytes = beat_bytes(s_beat_left);
  assign s_progress_after_beat = s_desc_progress_q + {29'd0, s_beat_bytes};
  assign s_input_bytes = count_strobe(data_in_strb_i);
  assign s_axi_read_fault = (s_read_resp != `AXI4_RESP_OKAY) || s_read_id_error ||
                            (s_read_last != s_read_expected_last);
  assign s_axi_write_fault = (s_write_resp != `AXI4_RESP_OKAY) || s_write_id_error;

  function automatic logic [2:0] count_strobe(input logic [3:0] strb_i);
    logic [2:0] count;
    begin
      count = 3'd0;
      for (int index = 0; index < 4; index++) begin
        if (strb_i[index]) count = count + 1'b1;
      end
      return count;
    end
  endfunction

  assign s_read_start_valid = !abort_i &&
                              ((s_state_q == FetchStart) || (s_state_q == PayloadReadStart));
  assign s_read_addr = (s_state_q == FetchStart) ? s_desc_addr_q : s_payload_addr;
  assign s_read_beats = (s_state_q == FetchStart) ? 5'd4 : s_payload_beats;
  assign s_read_beat_ready = (s_state_q == FetchWait) ||
                             ((s_state_q == PayloadReadWait) &&
                              (abort_i || s_abort_pending_q || data_out_ready_i));

  assign s_write_start_valid = (s_state_q == PayloadWriteStart) || (s_state_q == WritebackStart);
  assign s_write_addr = (s_state_q == PayloadWriteStart) ? s_payload_addr : s_desc_addr_q + 32'd12;
  assign s_write_beats = (s_state_q == PayloadWriteStart) ? s_payload_beats : 5'd1;
  assign s_write_data_valid = (s_state_q == PayloadWriteWait)
                                ? (s_abort_pending_q || data_in_valid_i)
                                : (s_state_q == WritebackWait);
  assign s_write_data = (s_state_q == PayloadWriteWait && s_abort_pending_q)
                          ? '0
                          : (s_state_q == WritebackWait ? s_writeback_control_q : data_in_i);
  assign s_write_strb = (s_state_q == PayloadWriteWait && s_abort_pending_q)
                          ? 4'b0000
                          : (s_state_q == WritebackWait ? 4'b1111 : data_in_strb_i);

  assign data_in_ready_o = (s_state_q == PayloadWriteWait) && !s_abort_pending_q &&
                           s_write_data_ready;
  assign data_out_valid_o = (s_state_q == PayloadReadWait) && s_read_beat_valid &&
                            !s_abort_pending_q && !s_axi_read_fault;
  assign data_out_o = s_read_data;
  assign data_out_strb_o = (4'b0001 << s_beat_bytes) - 1'b1;
  assign data_out_last_o = s_desc_end_q && (s_progress_after_beat >= s_desc_count_q);
  assign busy_o = ((s_state_q != Idle) && (s_state_q != Terminal)) || s_read_busy || s_write_busy;
  assign done_o = s_done_q;
  assign error_o = s_err_sticky_q;
  assign error_code_o = s_err_code_q;
  assign current_desc_o = s_desc_addr_q;
  assign bytes_done_o = s_total_done_q;
  assign error_addr_o = s_err_addr_q;
  assign descriptor_irq_o = s_descriptor_irq_q;
  assign abort_done_o = s_abort_done_q;

  dma_axi4_master #(
      .AddrWidth    (AddrWidth),
      .DataWidth    (DataWidth),
      .MaxBurstBeats(16)
  ) u_dma_axi4_master (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .read_start_valid_i  (s_read_start_valid),
      .read_start_ready_o  (s_read_start_ready),
      .read_addr_i         (s_read_addr),
      .read_beats_i        (s_read_beats),
      .read_fixed_i        (1'b0),
      .read_busy_o         (s_read_busy),
      .read_beat_valid_o   (s_read_beat_valid),
      .read_beat_ready_i   (s_read_beat_ready),
      .read_data_o         (s_read_data),
      .read_resp_o         (s_read_resp),
      .read_last_o         (s_read_last),
      .read_expected_last_o(s_read_expected_last),
      .read_id_error_o     (s_read_id_error),
      .read_done_o         (s_read_done),
      .write_start_valid_i (s_write_start_valid),
      .write_start_ready_o (s_write_start_ready),
      .write_addr_i        (s_write_addr),
      .write_beats_i       (s_write_beats),
      .write_fixed_i       (1'b0),
      .write_busy_o        (s_write_busy),
      .write_data_valid_i  (s_write_data_valid),
      .write_data_ready_o  (s_write_data_ready),
      .write_data_i        (s_write_data),
      .write_strb_i        (s_write_strb),
      .write_done_o        (s_write_done),
      .write_resp_o        (s_write_resp),
      .write_id_error_o    (s_write_id_error),
      .axi4                (dma_axi4)
  );

  always_comb begin
    s_state_d             = s_state_q;
    s_desc_addr_d         = s_desc_addr_q;
    s_desc_limit_d        = s_desc_limit_q;
    s_desc_index_d        = s_desc_index_q;
    s_direction_d         = s_direction_q;
    s_total_bytes_d       = s_total_bytes_q;
    s_total_seen_d        = s_total_seen_q;
    s_total_done_d        = s_total_done_q;
    s_desc_progress_d     = s_desc_progress_q;
    s_burst_beats_d       = s_burst_beats_q;
    s_burst_index_d       = s_burst_index_q;
    s_desc_buffer_d       = s_desc_buffer_q;
    s_desc_count_d        = s_desc_count_q;
    s_desc_next_d         = s_desc_next_q;
    s_desc_control_d      = s_desc_control_q;
    s_writeback_control_d = s_writeback_control_q;
    s_desc_end_d          = s_desc_end_q;
    s_desc_irq_d          = s_desc_irq_q;
    s_fault_d             = s_fault_q;
    s_err_code_d          = s_err_code_q;
    s_err_addr_d          = s_err_addr_q;
    s_done_d              = 1'b0;
    s_err_sticky_d        = s_err_sticky_q;
    s_abort_pending_d     = s_abort_pending_q;
    s_write_final_sent_d  = s_write_final_sent_q;
    s_write_beat_count_d  = s_write_beat_count_q;
    s_descriptor_irq_d    = 1'b0;
    s_abort_done_d        = 1'b0;
    for (int index = 0; index < 4; index++) begin
      s_fetch_word_d[index] = s_fetch_word_q[index];
    end

    if (s_state_q == Idle) begin
      if (start_i) begin
        s_desc_addr_d     = desc_base_i;
        s_desc_limit_d    = desc_count_i;
        s_desc_index_d    = '0;
        s_direction_d     = direction_i;
        s_total_bytes_d   = total_bytes_i;
        s_total_seen_d    = '0;
        s_total_done_d    = '0;
        s_desc_progress_d = '0;
        s_fault_d         = 1'b0;
        s_err_code_d      = '0;
        s_err_addr_d      = '0;
        s_err_sticky_d    = 1'b0;
        s_abort_pending_d = 1'b0;
        if ((desc_base_i[3:0] != 4'b0000) || (desc_base_i[11:0] >= 12'hFF0) ||
            (desc_count_i == 16'd0) || (desc_count_i > DescCountLimit)) begin
          s_state_d      = Terminal;
          s_done_d       = 1'b1;
          s_fault_d      = 1'b1;
          s_err_sticky_d = 1'b1;
          s_err_code_d   = 8'h02;
          s_err_addr_d   = desc_base_i;
        end else begin
          s_state_d = FetchStart;
        end
      end
    end else if (s_state_q == FetchStart) begin
      if (abort_i) begin
        s_fault_d      = 1'b1;
        s_err_sticky_d = 1'b1;
        s_err_code_d   = 8'h08;
        s_err_addr_d   = s_desc_addr_q;
        s_state_d      = Terminal;
        s_done_d       = 1'b1;
        s_abort_done_d = 1'b1;
      end else if (s_desc_addr_q[3:0] != 4'b0000 || s_desc_addr_q[11:0] >= 12'hFF0) begin
        s_fault_d      = 1'b1;
        s_err_sticky_d = 1'b1;
        s_err_code_d   = 8'h02;
        s_err_addr_d   = s_desc_addr_q;
        s_state_d      = Terminal;
        s_done_d       = 1'b1;
      end else if (s_read_start_ready) begin
        s_burst_index_d = '0;
        s_state_d       = FetchWait;
      end
    end else begin
      unique case (s_state_q)
        FetchWait: begin
          if (abort_i) begin
            s_abort_pending_d = 1'b1;
            s_fault_d         = 1'b1;
            s_err_sticky_d    = 1'b1;
            s_err_code_d      = 8'h08;
            s_err_addr_d      = s_desc_addr_q;
          end
          if (s_read_beat_valid && s_read_beat_ready) begin
            s_fetch_word_d[s_burst_index_q[1:0]] = s_read_data;
            if (s_axi_read_fault) begin
              s_fault_d      = 1'b1;
              s_err_sticky_d = 1'b1;
              s_err_code_d   = 8'h04;
              s_err_addr_d   = s_desc_addr_q;
            end
            if (s_read_done) begin
              s_abort_pending_d = 1'b0;
              s_state_d         = Validate;
            end else begin
              s_burst_index_d = s_burst_index_q + 1'b1;
            end
          end
        end
        Validate: begin
          s_desc_buffer_d   = s_fetch_word_q[0];
          s_desc_count_d    = s_fetch_word_q[1];
          s_desc_next_d     = s_fetch_word_q[2];
          s_desc_control_d  = s_fetch_word_q[3];
          s_desc_end_d      = s_fetch_word_q[3][sdio_pkg::SDIO_DESC_END];
          s_desc_irq_d      = s_fetch_word_q[3][sdio_pkg::SDIO_DESC_IRQ];
          s_desc_progress_d = '0;
          s_total_seen_d    = s_total_seen_q + s_fetch_word_q[1];
          if (!s_fetch_word_q[3][sdio_pkg::SDIO_DESC_OWN] ||
              (s_fetch_word_q[0][1:0] != 2'b00) ||
              (s_fetch_word_q[1] == 32'd0) ||
              (s_fetch_word_q[3][31:18] != 14'd0) ||
              (s_fetch_word_q[3][sdio_pkg::SDIO_DESC_END] &&
               ((s_fetch_word_q[2] != 32'd0) ||
                s_fetch_word_q[3][sdio_pkg::SDIO_DESC_CHAIN])) ||
              (!s_fetch_word_q[3][sdio_pkg::SDIO_DESC_END] &&
               (!s_fetch_word_q[3][sdio_pkg::SDIO_DESC_CHAIN] ||
                (s_fetch_word_q[2][3:0] != 4'b0000) ||
                (s_fetch_word_q[2][11:0] >= 12'hFF0) ||
                (s_fetch_word_q[2] == 32'd0) ||
                (s_desc_index_q + 1'b1 >= s_desc_limit_q))) ||
              ((s_total_bytes_q != 32'd0) &&
               ((s_total_seen_q + s_fetch_word_q[1] > s_total_bytes_q) ||
                (s_fetch_word_q[3][sdio_pkg::SDIO_DESC_END] &&
                 (s_total_seen_q + s_fetch_word_q[1] != s_total_bytes_q)))) ||
              s_fault_q) begin
            s_fault_d      = 1'b1;
            s_err_sticky_d = 1'b1;
            if (s_err_code_q == 8'd0) s_err_code_d = 8'h02;
          end
          s_writeback_control_d = (s_fetch_word_q[3] &
                                   ~(32'd1 << sdio_pkg::SDIO_DESC_OWN)) |
                                  (s_fault_d ? (32'd1 << sdio_pkg::SDIO_DESC_ERROR) :
                                               (32'd1 << sdio_pkg::SDIO_DESC_DONE));
          if (!s_fetch_word_q[3][sdio_pkg::SDIO_DESC_OWN]) begin
            s_state_d = Terminal;
            s_done_d  = 1'b1;
          end else if (s_fault_d || s_abort_pending_q) begin
            s_state_d = WritebackStart;
          end else if (s_direction_q == sdio_pkg::SdioDataFromCard) begin
            // Card-to-host consumes the stream and AXI-writes memory.
            s_state_d = PayloadWriteStart;
          end else begin
            // Host-to-card AXI-reads memory and produces the stream.
            s_state_d = PayloadReadStart;
          end
        end
        PayloadReadStart: begin
          if (abort_i) begin
            s_abort_pending_d = 1'b1;
            s_fault_d         = 1'b1;
            s_err_sticky_d    = 1'b1;
            s_err_code_d      = 8'h08;
            s_err_addr_d      = s_payload_addr;
            s_state_d         = WritebackStart;
          end else if (s_read_start_ready) begin
            s_burst_beats_d   = s_payload_beats;
            s_burst_index_d   = '0;
            s_abort_pending_d = 1'b0;
            s_state_d         = PayloadReadWait;
          end
        end
        PayloadReadWait: begin
          if (abort_i) begin
            s_abort_pending_d = 1'b1;
            s_fault_d         = 1'b1;
            s_err_sticky_d    = 1'b1;
            s_err_code_d      = 8'h08;
            s_err_addr_d      = s_payload_addr;
          end
          if (s_read_beat_valid && s_read_beat_ready) begin
            if (s_axi_read_fault) begin
              s_fault_d      = 1'b1;
              s_err_sticky_d = 1'b1;
              s_err_code_d   = 8'h04;
              s_err_addr_d   = s_payload_addr + s_burst_offset;
            end
            if (!s_abort_pending_q && !abort_i && !s_axi_read_fault) begin
              s_desc_progress_d = s_progress_after_beat;
              s_total_done_d    = s_total_done_q + {29'd0, s_beat_bytes};
            end
            if (s_read_done) begin
              s_abort_pending_d = 1'b0;
              if (s_fault_d || abort_i || s_abort_pending_q) begin
                s_writeback_control_d = (s_desc_control_q &
                                         ~(32'd1 << sdio_pkg::SDIO_DESC_OWN)) |
                                        (32'd1 << sdio_pkg::SDIO_DESC_ERROR);
                s_state_d = WritebackStart;
              end else if (s_progress_after_beat >= s_desc_count_q) begin
                s_writeback_control_d = (s_desc_control_q &
                                         ~(32'd1 << sdio_pkg::SDIO_DESC_OWN)) |
                                        (32'd1 << sdio_pkg::SDIO_DESC_DONE);
                s_state_d = WritebackStart;
              end else begin
                s_state_d = PayloadReadStart;
              end
            end else begin
              s_burst_index_d = s_burst_index_q + 1'b1;
            end
          end
        end
        PayloadWriteStart: begin
          if (abort_i) begin
            s_abort_pending_d = 1'b1;
            s_fault_d = 1'b1;
            s_err_sticky_d = 1'b1;
            s_err_code_d = 8'h08;
            s_err_addr_d = s_payload_addr;
            s_writeback_control_d = (s_desc_control_q &
                                     ~(32'd1 << sdio_pkg::SDIO_DESC_OWN)) |
                                    (32'd1 << sdio_pkg::SDIO_DESC_ERROR);
            s_state_d = WritebackStart;
          end else if (s_write_start_ready) begin
            s_burst_beats_d      = s_payload_beats;
            s_burst_index_d      = '0;
            s_write_beat_count_d = '0;
            s_write_final_sent_d = 1'b0;
            s_state_d            = PayloadWriteWait;
          end
        end
        PayloadWriteWait: begin
          if (abort_i) begin
            s_abort_pending_d = 1'b1;
            s_fault_d         = 1'b1;
            s_err_sticky_d    = 1'b1;
            s_err_code_d      = 8'h08;
            s_err_addr_d      = s_payload_addr + s_burst_offset;
          end
          if (s_write_data_valid && s_write_data_ready) begin
            if (!s_abort_pending_q && !abort_i) begin
              if (!strobe_valid(
                      data_in_strb_i
                  ) || (s_input_bytes != s_beat_bytes) ||
                      (data_in_last_i !=
                       (s_desc_end_q && (s_progress_after_beat >= s_desc_count_q)))) begin
                s_fault_d      = 1'b1;
                s_err_sticky_d = 1'b1;
                s_err_code_d   = 8'h10;
              end
              s_desc_progress_d = s_progress_after_beat;
              s_total_done_d    = s_total_done_q + {29'd0, s_beat_bytes};
            end
            s_write_beat_count_d = s_write_beat_count_q + 1'b1;
            s_burst_index_d      = s_burst_index_q + 1'b1;
            if (s_write_beat_count_q + 1'b1 >= s_burst_beats_q) begin
              s_write_final_sent_d = 1'b1;
            end
          end
          if (s_write_done) begin
            if (s_axi_write_fault) begin
              s_fault_d      = 1'b1;
              s_err_sticky_d = 1'b1;
              s_err_code_d   = 8'h04;
              s_err_addr_d   = s_payload_addr + s_burst_offset;
            end
            if (s_write_final_sent_q) begin
              s_writeback_control_d = (s_desc_control_q &
                                       ~(32'd1 << sdio_pkg::SDIO_DESC_OWN)) |
                                      (s_fault_d ? (32'd1 << sdio_pkg::SDIO_DESC_ERROR) :
                                                   (32'd1 << sdio_pkg::SDIO_DESC_DONE));
              s_state_d = WritebackStart;
            end
          end
        end
        WritebackStart: begin
          if (s_write_start_ready) begin
            s_state_d = WritebackWait;
          end
        end
        WritebackWait: begin
          if (s_write_done) begin
            if (s_axi_write_fault) begin
              s_fault_d      = 1'b1;
              s_err_sticky_d = 1'b1;
              s_err_code_d   = 8'h04;
              s_err_addr_d   = s_desc_addr_q + 32'd12;
            end
            if (s_fault_q || s_fault_d || s_axi_write_fault ||
                s_writeback_control_q[sdio_pkg::SDIO_DESC_ERROR]) begin
              s_abort_done_d = s_abort_pending_q ||
                               (s_writeback_control_q[sdio_pkg::SDIO_DESC_ERROR] &&
                                (s_err_code_q == 8'h08));
              s_state_d = Terminal;
              s_done_d = 1'b1;
            end else if (s_desc_end_q) begin
              s_descriptor_irq_d = s_desc_irq_q;
              s_state_d          = Terminal;
              s_done_d           = 1'b1;
            end else begin
              s_descriptor_irq_d = s_desc_irq_q;
              s_desc_index_d     = s_desc_index_q + 1'b1;
              s_desc_addr_d      = s_desc_next_q;
              s_state_d          = FetchStart;
            end
          end
        end
        Terminal: begin
          s_state_d = Idle;
        end
        default: begin
          s_state_d      = Idle;
          s_fault_d      = 1'b1;
          s_err_sticky_d = 1'b1;
          s_err_code_d   = 8'h80;
        end
      endcase
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q             <= Idle;
      s_desc_addr_q         <= '0;
      s_desc_limit_q        <= '0;
      s_desc_index_q        <= '0;
      s_direction_q         <= sdio_pkg::SdioDataFromCard;
      s_total_bytes_q       <= '0;
      s_total_seen_q        <= '0;
      s_total_done_q        <= '0;
      s_desc_progress_q     <= '0;
      s_burst_beats_q       <= '0;
      s_burst_index_q       <= '0;
      s_desc_buffer_q       <= '0;
      s_desc_count_q        <= '0;
      s_desc_next_q         <= '0;
      s_desc_control_q      <= '0;
      s_writeback_control_q <= '0;
      s_desc_end_q          <= 1'b0;
      s_desc_irq_q          <= 1'b0;
      s_fault_q             <= 1'b0;
      s_err_code_q          <= '0;
      s_err_addr_q          <= '0;
      s_done_q              <= 1'b0;
      s_err_sticky_q        <= 1'b0;
      s_abort_pending_q     <= 1'b0;
      s_write_final_sent_q  <= 1'b0;
      s_write_beat_count_q  <= '0;
      s_descriptor_irq_q    <= 1'b0;
      s_abort_done_q        <= 1'b0;
      for (int index = 0; index < 4; index++) begin
        s_fetch_word_q[index] <= '0;
      end
    end else begin
      s_state_q             <= s_state_d;
      s_desc_addr_q         <= s_desc_addr_d;
      s_desc_limit_q        <= s_desc_limit_d;
      s_desc_index_q        <= s_desc_index_d;
      s_direction_q         <= s_direction_d;
      s_total_bytes_q       <= s_total_bytes_d;
      s_total_seen_q        <= s_total_seen_d;
      s_total_done_q        <= s_total_done_d;
      s_desc_progress_q     <= s_desc_progress_d;
      s_burst_beats_q       <= s_burst_beats_d;
      s_burst_index_q       <= s_burst_index_d;
      s_desc_buffer_q       <= s_desc_buffer_d;
      s_desc_count_q        <= s_desc_count_d;
      s_desc_next_q         <= s_desc_next_d;
      s_desc_control_q      <= s_desc_control_d;
      s_writeback_control_q <= s_writeback_control_d;
      s_desc_end_q          <= s_desc_end_d;
      s_desc_irq_q          <= s_desc_irq_d;
      s_fault_q             <= s_fault_d;
      s_err_code_q          <= s_err_code_d;
      s_err_addr_q          <= s_err_addr_d;
      s_done_q              <= s_done_d;
      s_err_sticky_q        <= s_err_sticky_d;
      s_abort_pending_q     <= s_abort_pending_d;
      s_write_final_sent_q  <= s_write_final_sent_d;
      s_write_beat_count_q  <= s_write_beat_count_d;
      s_descriptor_irq_q    <= s_descriptor_irq_d;
      s_abort_done_q        <= s_abort_done_d;
      for (int index = 0; index < 4; index++) begin
        s_fetch_word_q[index] <= s_fetch_word_d[index];
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    if ((AddrWidth < 4) || (DataWidth != 32) || (DescCount < 1) || (DescCount > 65535)) begin
      $fatal(1, "sdio_dma: unsupported geometry");
    end
  end
`endif
endmodule
