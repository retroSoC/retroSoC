// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "axi4_define.svh"

module usb2_dma #(
    parameter int AddrWidth      = 32,
    parameter int DataWidth      = 32,
    parameter int MaxDescriptors = 256
) (
    // verilog_format: off -- preserve command, packet stream, and completion groups
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 start_i,
    input  logic                 abort_i,
    input  logic                 memory_to_packet_i,
    input  logic                 allow_short_i,
    input  logic [AddrWidth-1:0] desc_base_i,
    input  logic [15:0]          desc_limit_i,
    input  logic [31:0]          transfer_bytes_i,
    input  logic                 packet_in_valid_i,
    output logic                 packet_in_ready_o,
    input  logic [DataWidth-1:0] packet_in_data_i,
    input  logic [DataWidth/8-1:0] packet_in_strb_i,
    input  logic                 packet_in_last_i,
    output logic                 packet_out_valid_o,
    input  logic                 packet_out_ready_i,
    output logic [DataWidth-1:0] packet_out_data_o,
    output logic [DataWidth/8-1:0] packet_out_strb_o,
    output logic                 packet_out_last_o,
    output logic                 busy_o,
    output logic                 done_o,
    output logic                 error_o,
    output logic [7:0]           error_code_o,
    output logic [AddrWidth-1:0] current_desc_o,
    output logic [AddrWidth-1:0] next_desc_o,
    output logic [31:0]          bytes_done_o,
    output logic [31:0]          frame_o,
    output logic                 descriptor_irq_o,
    output logic                 abort_done_o,
    axi4_if.master               dma_axi4
    // verilog_format: on
);
  localparam int BeatBytes = DataWidth / 8;
  localparam int DescIndexWidth = $clog2(MaxDescriptors);
  localparam logic [7:0] ErrorDescriptor = 8'd1;
  localparam logic [7:0] ErrorLength = 8'd2;
  localparam logic [7:0] ErrorAxiRead = 8'd3;
  localparam logic [7:0] ErrorAxiWrite = 8'd4;
  localparam logic [7:0] ErrorPacket = 8'd5;
  localparam logic [7:0] ErrorAbort = 8'd6;
  localparam logic [7:0] ErrorWriteback = 8'd7;

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
    OwnershipStart,
    OwnershipWait,
    Complete,
    Terminal
  } dma_state_e;

  dma_state_e s_state_d, s_state_q;
  logic [3:0] s_state_bits_q;
  logic [AddrWidth-1:0] s_desc_addr_d, s_desc_addr_q;
  logic [DescIndexWidth-1:0] s_desc_index_d, s_desc_index_q;
  logic [15:0] s_desc_limit_d, s_desc_limit_q;
  logic s_memory_to_packet_d, s_memory_to_packet_q;
  logic s_allow_short_d, s_allow_short_q;
  logic s_unlimited_d, s_unlimited_q;
  logic [31:0] s_remaining_d, s_remaining_q;
  logic [31:0] s_total_done_d, s_total_done_q;
  logic [7:0][31:0] s_desc_words_d, s_desc_words_q;
  logic [3:0] s_fetch_index_d, s_fetch_index_q;
  logic [31:0] s_selected_bytes_d, s_selected_bytes_q;
  logic [31:0] s_desc_progress_d, s_desc_progress_q;
  logic [4:0] s_burst_beats_d, s_burst_beats_q;
  logic [4:0] s_burst_index_d, s_burst_index_q;
  logic [2:0] s_writeback_index_d, s_writeback_index_q;
  logic s_fault_d, s_fault_q;
  logic [7:0] s_err_code_d, s_err_code_q;
  logic s_abort_pending_d, s_abort_pending_q;
  logic s_done_d, s_done_q;
  logic s_err_d, s_err_q;
  logic s_descriptor_irq_d, s_descriptor_irq_q;
  logic s_abort_done_d, s_abort_done_q;

  logic                                         s_desc_own;
  logic                                         s_desc_chain;
  logic                                         s_desc_end;
  logic                                         s_desc_irq;
  logic                                         s_desc_short_ok;
  logic                                         s_desc_zero_packet;
  logic                                         s_desc_valid;
  usb2_pkg::usb2_desc_error_e                   s_desc_err;
  logic                       [           31:0] s_desc_buffer;
  logic                       [           31:0] s_desc_len;
  logic                       [           31:0] s_desc_next;
  logic                       [           31:0] s_desc_control;
  logic                       [           31:0] s_desc_frame;
  logic                       [           31:0] s_payload_addr;
  logic                       [           31:0] s_payload_left;
  logic                       [            4:0] s_payload_beats;
  logic                       [            2:0] s_payload_beat_bytes;
  logic                       [            3:0] s_payload_expected_strb;
  logic                       [           31:0] s_progress_after_beat;
  logic                       [           31:0] s_remaining_after_desc;
  logic                                         s_transfer_last;
  logic                                         s_descriptor_short;
  logic                       [           31:0] s_completion_stat;
  logic                       [           31:0] s_control_released;
  logic                                         s_packet_input_valid;
  logic                                         s_packet_input_fault;

  logic                                         s_read_start_valid;
  logic                                         s_read_start_ready;
  logic                       [  AddrWidth-1:0] s_read_addr;
  logic                       [            4:0] s_read_beats;
  logic                                         s_read_beat_valid;
  logic                                         s_read_beat_ready;
  logic                       [  DataWidth-1:0] s_read_data;
  logic                       [            1:0] s_read_resp;
  logic                                         s_read_last;
  logic                                         s_read_expected_last;
  logic                                         s_read_id_err;
  logic                                         s_read_done;
  logic                                         s_read_busy;
  logic                                         s_write_start_valid;
  logic                                         s_write_start_ready;
  logic                       [  AddrWidth-1:0] s_write_addr;
  logic                       [            4:0] s_write_beats;
  logic                                         s_write_data_valid;
  logic                                         s_write_data_ready;
  logic                       [  DataWidth-1:0] s_write_data;
  logic                       [DataWidth/8-1:0] s_write_strb;
  logic                                         s_write_done;
  logic                       [            1:0] s_write_resp;
  logic                                         s_write_id_err;
  logic                                         s_write_busy;
  logic                                         s_axi_read_fault;
  logic                                         s_axi_write_fault;

  function automatic logic [4:0] choose_burst(input logic [11:0] addr_low_i,
                                              input logic [31:0] bytes_i);
    logic [31:0] beats_needed;
    logic [31:0] boundary_beats;
    logic [31:0] selected;
    begin
      beats_needed   = (bytes_i + (BeatBytes - 1)) / BeatBytes;
      boundary_beats = (32'd4096 - {20'd0, addr_low_i}) / BeatBytes;
      selected       = beats_needed;
      if (selected > 32'd16) selected = 32'd16;
      if (selected > boundary_beats) selected = boundary_beats;
      if (selected == 32'd0) selected = 32'd1;
      return selected[4:0];
    end
  endfunction

  function automatic logic [2:0] beat_bytes(input logic [31:0] bytes_i);
    return (bytes_i >= BeatBytes) ? 3'(BeatBytes) : bytes_i[2:0];
  endfunction

  function automatic logic [3:0] byte_strobe(input logic [2:0] bytes_i);
    unique case (bytes_i)
      3'd0:    return 4'b0000;
      3'd1:    return 4'b0001;
      3'd2:    return 4'b0011;
      3'd3:    return 4'b0111;
      default: return 4'b1111;
    endcase
  endfunction

  assign s_state_q = dma_state_e'(s_state_bits_q);
  assign s_desc_buffer = s_desc_words_q[usb2_pkg::USB2_DESC_BUFFER_WORD];
  assign s_desc_len = s_desc_words_q[usb2_pkg::USB2_DESC_LENGTH_WORD];
  assign s_desc_next = s_desc_words_q[usb2_pkg::USB2_DESC_NEXT_WORD];
  assign s_desc_control = s_desc_words_q[usb2_pkg::USB2_DESC_CONTROL_WORD];
  assign s_desc_frame = s_desc_words_q[usb2_pkg::USB2_DESC_FRAME_WORD];
  assign s_payload_addr = s_desc_buffer + s_desc_progress_q;
  assign s_payload_left = s_selected_bytes_q - s_desc_progress_q;
  assign s_payload_beats = choose_burst(s_payload_addr[11:0], s_payload_left);
  assign s_payload_beat_bytes = beat_bytes(s_payload_left);
  assign s_payload_expected_strb = byte_strobe(s_payload_beat_bytes);
  assign s_progress_after_beat = s_desc_progress_q + {29'd0, s_payload_beat_bytes};
  assign s_remaining_after_desc = s_remaining_q - s_selected_bytes_q;
  assign s_transfer_last = s_unlimited_q ? s_desc_end : (s_remaining_q <= s_selected_bytes_q);
  assign s_descriptor_short = s_selected_bytes_q < s_desc_len;
  assign s_control_released = s_desc_control & 32'hFFFF_FFFE;

  always_comb begin
    s_completion_stat                            = 32'd0;
    s_completion_stat[usb2_pkg::USB2_DESC_DONE]  = 1'b1;
    s_completion_stat[usb2_pkg::USB2_DESC_SHORT] = s_descriptor_short;
    if (s_fault_q) begin
      unique case (s_err_code_q)
        ErrorAxiRead, ErrorAxiWrite, ErrorWriteback:
        s_completion_stat[usb2_pkg::USB2_DESC_AXI_ERROR] = 1'b1;
        ErrorAbort: s_completion_stat[usb2_pkg::USB2_DESC_ABORTED] = 1'b1;
        default: s_completion_stat[usb2_pkg::USB2_DESC_PROTOCOL_ERROR] = 1'b1;
      endcase
    end
  end

  usb2_dma_descriptor #(
      .MaxDescriptors(MaxDescriptors)
  ) u_descriptor (
      .buffer_addr_i  (s_desc_buffer),
      .byte_length_i  (s_desc_len),
      .next_addr_i    (s_desc_next),
      .control_i      (s_desc_control),
      .actual_length_i(s_desc_words_q[usb2_pkg::USB2_DESC_ACTUAL_WORD]),
      .status_i       (s_desc_words_q[usb2_pkg::USB2_DESC_STATUS_WORD]),
      .frame_i        (s_desc_frame),
      .reserved_i     (s_desc_words_q[usb2_pkg::USB2_DESC_RESERVED_WORD]),
      .desc_index_i   (s_desc_index_q),
      .own_o          (s_desc_own),
      .chain_o        (s_desc_chain),
      .end_o          (s_desc_end),
      .irq_o          (s_desc_irq),
      .short_ok_o     (s_desc_short_ok),
      .zero_packet_o  (s_desc_zero_packet),
      .valid_o        (s_desc_valid),
      .error_o        (s_desc_err)
  );

  assign s_read_start_valid = !abort_i &&
                              ((s_state_q == FetchStart) || (s_state_q == PayloadReadStart));
  assign s_read_addr = (s_state_q == FetchStart) ? s_desc_addr_q : s_payload_addr;
  assign s_read_beats = (s_state_q == FetchStart) ? 5'd8 : s_payload_beats;
  assign s_axi_read_fault = (s_read_resp != `AXI4_RESP_OKAY) || s_read_id_err ||
                            (s_read_last != s_read_expected_last);
  assign s_read_beat_ready = (s_state_q == FetchWait) ||
                             ((s_state_q == PayloadReadWait) &&
                              (s_fault_q || s_abort_pending_q || packet_out_ready_i));
  assign packet_out_valid_o = (s_state_q == PayloadReadWait) && s_read_beat_valid &&
                              !s_fault_q && !s_abort_pending_q && !s_axi_read_fault;
  assign packet_out_data_o = s_read_data;
  assign packet_out_strb_o = s_payload_expected_strb;
  assign packet_out_last_o = (s_progress_after_beat >= s_selected_bytes_q) && s_transfer_last;

  assign s_write_start_valid = (s_state_q == PayloadWriteStart) ||
                               (s_state_q == WritebackStart) ||
                               (s_state_q == OwnershipStart);
  assign s_write_addr = (s_state_q == PayloadWriteStart) ? s_payload_addr :
                        ((s_state_q == WritebackStart) ? (s_desc_addr_q + 32'd16) :
                                                        (s_desc_addr_q + 32'd12));
  assign s_write_beats = (s_state_q == WritebackStart) ? 5'd2 :
                         ((s_state_q == OwnershipStart) ? 5'd1 : s_payload_beats);
  assign s_packet_input_valid = (s_state_q == PayloadWriteWait) && packet_in_valid_i;
  assign s_packet_input_fault = s_packet_input_valid &&
                                ((packet_in_strb_i != s_payload_expected_strb) ||
                                 (packet_in_last_i !=
                                  ((s_progress_after_beat >= s_selected_bytes_q) &&
                                   s_transfer_last)));
  assign packet_in_ready_o = (s_state_q == PayloadWriteWait) && !s_fault_q &&
                             !s_abort_pending_q && s_write_data_ready;
  assign s_write_data_valid = (s_state_q == PayloadWriteWait) ?
                                  (packet_in_valid_i || s_fault_q || s_abort_pending_q) :
                              ((s_state_q == WritebackWait) || (s_state_q == OwnershipWait));
  assign s_write_data = (s_state_q == PayloadWriteWait) ?
                            ((s_fault_q || s_abort_pending_q) ? '0 : packet_in_data_i) :
                        ((s_state_q == WritebackWait) ?
                             ((s_writeback_index_q == 3'd0) ? s_desc_progress_q :
                                                              s_completion_stat) :
                             s_control_released);
  assign s_write_strb = ((s_state_q == PayloadWriteWait) &&
                         (s_fault_q || s_abort_pending_q)) ? '0 :
                        ((s_state_q == PayloadWriteWait) ? packet_in_strb_i : '1);
  assign s_axi_write_fault = (s_write_resp != `AXI4_RESP_OKAY) || s_write_id_err;

  assign busy_o = ((s_state_q != Idle) && (s_state_q != Terminal)) || s_read_busy || s_write_busy;
  assign done_o = s_done_q;
  assign error_o = s_err_q;
  assign error_code_o = s_err_code_q;
  assign current_desc_o = s_desc_addr_q;
  assign next_desc_o = s_desc_next;
  assign bytes_done_o = s_total_done_q;
  assign frame_o = s_desc_frame;
  assign descriptor_irq_o = s_descriptor_irq_q;
  assign abort_done_o = s_abort_done_q;

  dma_axi4_master #(
      .AddrWidth    (AddrWidth),
      .DataWidth    (DataWidth),
      .MaxBurstBeats(16)
  ) u_axi4_master (
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
      .read_id_error_o     (s_read_id_err),
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
      .write_id_error_o    (s_write_id_err),
      .axi4                (dma_axi4)
  );

  always_comb begin
    s_state_d            = s_state_q;
    s_desc_addr_d        = s_desc_addr_q;
    s_desc_index_d       = s_desc_index_q;
    s_desc_limit_d       = s_desc_limit_q;
    s_memory_to_packet_d = s_memory_to_packet_q;
    s_allow_short_d      = s_allow_short_q;
    s_unlimited_d        = s_unlimited_q;
    s_remaining_d        = s_remaining_q;
    s_total_done_d       = s_total_done_q;
    s_desc_words_d       = s_desc_words_q;
    s_fetch_index_d      = s_fetch_index_q;
    s_selected_bytes_d   = s_selected_bytes_q;
    s_desc_progress_d    = s_desc_progress_q;
    s_burst_beats_d      = s_burst_beats_q;
    s_burst_index_d      = s_burst_index_q;
    s_writeback_index_d  = s_writeback_index_q;
    s_fault_d            = s_fault_q;
    s_err_code_d         = s_err_code_q;
    s_abort_pending_d    = s_abort_pending_q || abort_i;
    s_done_d             = 1'b0;
    s_err_d              = s_err_q;
    s_descriptor_irq_d   = 1'b0;
    s_abort_done_d       = 1'b0;

    unique case (s_state_q)
      Idle: begin
        s_abort_pending_d = 1'b0;
        if (start_i) begin
          s_desc_addr_d        = desc_base_i;
          s_desc_index_d       = '0;
          s_desc_limit_d       = desc_limit_i;
          s_memory_to_packet_d = memory_to_packet_i;
          s_allow_short_d      = allow_short_i;
          s_unlimited_d        = transfer_bytes_i == 32'd0;
          s_remaining_d        = transfer_bytes_i;
          s_total_done_d       = 32'd0;
          s_desc_words_d       = '0;
          s_fetch_index_d      = '0;
          s_desc_progress_d    = 32'd0;
          s_fault_d            = 1'b0;
          s_err_code_d         = 8'd0;
          s_err_d              = 1'b0;
          if ((desc_base_i[4:0] != 5'd0) || (desc_base_i[11:0] > 12'hFE0) ||
              (desc_limit_i == 16'd0) || (desc_limit_i > 16'(MaxDescriptors))) begin
            s_fault_d    = 1'b1;
            s_err_code_d = ErrorDescriptor;
            s_state_d    = Terminal;
          end else begin
            s_state_d = FetchStart;
          end
        end
      end
      FetchStart: begin
        if (abort_i) begin
          s_fault_d    = 1'b1;
          s_err_code_d = ErrorAbort;
          s_state_d    = Terminal;
        end else if (s_read_start_ready) begin
          s_fetch_index_d = '0;
          s_state_d       = FetchWait;
        end
      end
      FetchWait: begin
        if (s_read_beat_valid && s_read_beat_ready) begin
          if (s_axi_read_fault) begin
            s_fault_d    = 1'b1;
            s_err_code_d = ErrorAxiRead;
          end else begin
            s_desc_words_d[s_fetch_index_q] = s_read_data;
          end
          s_fetch_index_d = s_fetch_index_q + 1'b1;
          if (s_read_done) begin
            if (s_fault_q || s_axi_read_fault || abort_i) begin
              s_fault_d    = 1'b1;
              s_err_code_d = abort_i ? ErrorAbort : ErrorAxiRead;
              s_state_d    = Terminal;
            end else begin
              s_state_d = Validate;
            end
          end
        end
      end
      Validate: begin
        s_desc_progress_d = 32'd0;
        if (!s_desc_valid || (s_desc_err != usb2_pkg::Usb2DescOk) || !s_desc_own ||
            (s_desc_zero_packet && !s_memory_to_packet_q)) begin
          s_fault_d    = 1'b1;
          s_err_code_d = ErrorDescriptor;
          s_state_d    = Terminal;
        end else if (!s_unlimited_q && (s_remaining_q > s_desc_len) && s_desc_end) begin
          s_fault_d    = 1'b1;
          s_err_code_d = ErrorLength;
          s_state_d    = WritebackStart;
        end else begin
          if (!s_unlimited_q && (s_remaining_q < s_desc_len)) begin
            s_selected_bytes_d = s_remaining_q;
          end else begin
            s_selected_bytes_d = s_desc_len;
          end
          if (!s_unlimited_q && (s_remaining_q < s_desc_len) &&
              !(s_allow_short_q || s_desc_short_ok)) begin
            s_fault_d    = 1'b1;
            s_err_code_d = ErrorLength;
            s_state_d    = WritebackStart;
          end else if (s_memory_to_packet_q) begin
            s_state_d = PayloadReadStart;
          end else begin
            s_state_d = PayloadWriteStart;
          end
        end
      end
      PayloadReadStart: begin
        if (s_read_start_ready) begin
          s_burst_beats_d = s_payload_beats;
          s_burst_index_d = '0;
          s_state_d       = PayloadReadWait;
        end
      end
      PayloadReadWait: begin
        if (s_read_beat_valid && s_read_beat_ready) begin
          s_burst_index_d = s_burst_index_q + 1'b1;
          if (s_axi_read_fault) begin
            s_fault_d    = 1'b1;
            s_err_code_d = ErrorAxiRead;
          end else if (!s_fault_q && !s_abort_pending_q) begin
            s_desc_progress_d = s_progress_after_beat;
            s_total_done_d    = s_total_done_q + {29'd0, s_payload_beat_bytes};
          end
          if (s_read_done) begin
            if (s_fault_q || s_axi_read_fault || s_abort_pending_q || abort_i) begin
              s_fault_d    = 1'b1;
              s_err_code_d = (s_abort_pending_q || abort_i) ? ErrorAbort : ErrorAxiRead;
              s_state_d    = WritebackStart;
            end else if (s_progress_after_beat >= s_selected_bytes_q) begin
              s_state_d = WritebackStart;
            end else begin
              s_state_d = PayloadReadStart;
            end
          end
        end
      end
      PayloadWriteStart: begin
        if (s_write_start_ready) begin
          s_burst_beats_d = s_payload_beats;
          s_burst_index_d = '0;
          s_state_d       = PayloadWriteWait;
        end
      end
      PayloadWriteWait: begin
        if (s_write_data_valid && s_write_data_ready) begin
          s_burst_index_d = s_burst_index_q + 1'b1;
          if (s_packet_input_fault && !s_fault_q) begin
            s_fault_d    = 1'b1;
            s_err_code_d = ErrorPacket;
          end else if (!s_fault_q && !s_abort_pending_q) begin
            s_desc_progress_d = s_progress_after_beat;
            s_total_done_d    = s_total_done_q + {29'd0, s_payload_beat_bytes};
          end
        end
        if (s_write_done) begin
          if (s_axi_write_fault || s_fault_q || s_packet_input_fault ||
              s_abort_pending_q || abort_i) begin
            s_fault_d = 1'b1;
            if (s_abort_pending_q || abort_i) begin
              s_err_code_d = ErrorAbort;
            end else if (s_axi_write_fault) begin
              s_err_code_d = ErrorAxiWrite;
            end else begin
              s_err_code_d = ErrorPacket;
            end
            s_state_d = WritebackStart;
          end else if (s_desc_progress_q >= s_selected_bytes_q) begin
            s_state_d = WritebackStart;
          end else begin
            s_state_d = PayloadWriteStart;
          end
        end
      end
      WritebackStart: begin
        if (s_write_start_ready) begin
          s_writeback_index_d = 3'd0;
          s_state_d           = WritebackWait;
        end
      end
      WritebackWait: begin
        if (s_write_data_valid && s_write_data_ready) begin
          s_writeback_index_d = s_writeback_index_q + 1'b1;
        end
        if (s_write_done) begin
          if (s_axi_write_fault) begin
            s_fault_d    = 1'b1;
            s_err_code_d = ErrorWriteback;
            s_state_d    = Terminal;
          end else begin
            s_state_d = OwnershipStart;
          end
        end
      end
      OwnershipStart: begin
        if (s_write_start_ready) begin
          s_state_d = OwnershipWait;
        end
      end
      OwnershipWait: begin
        if (s_write_done) begin
          if (s_axi_write_fault) begin
            s_fault_d    = 1'b1;
            s_err_code_d = ErrorWriteback;
            s_state_d    = Terminal;
          end else begin
            s_descriptor_irq_d = s_desc_irq;
            s_state_d          = Complete;
          end
        end
      end
      Complete: begin
        if (s_fault_q) begin
          s_state_d = Terminal;
        end else if ((!s_unlimited_q && (s_remaining_q <= s_selected_bytes_q)) ||
                     (s_unlimited_q && s_desc_end)) begin
          s_state_d = Terminal;
        end else if (!s_desc_chain || s_desc_end ||
                     (({8'd0, s_desc_index_q} + 1'b1) >= s_desc_limit_q)) begin
          s_fault_d    = 1'b1;
          s_err_code_d = ErrorLength;
          s_state_d    = Terminal;
        end else begin
          s_desc_addr_d     = s_desc_next;
          s_desc_index_d    = s_desc_index_q + 1'b1;
          s_desc_words_d    = '0;
          s_desc_progress_d = 32'd0;
          if (!s_unlimited_q) begin
            s_remaining_d = s_remaining_after_desc;
          end
          s_state_d = FetchStart;
        end
      end
      Terminal: begin
        s_done_d       = !s_fault_q;
        s_err_d        = s_fault_q;
        s_abort_done_d = s_err_code_q == ErrorAbort;
        s_state_d      = Idle;
      end
      default: begin
        s_fault_d    = 1'b1;
        s_err_code_d = ErrorPacket;
        s_state_d    = Terminal;
      end
    endcase
  end

  dffr #(
      .DATA_WIDTH(4)
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(AddrWidth)
  ) u_desc_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_desc_addr_d),
      .dat_o  (s_desc_addr_q)
  );
  dffr #(
      .DATA_WIDTH(DescIndexWidth)
  ) u_desc_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_desc_index_d),
      .dat_o  (s_desc_index_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_desc_limit_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_desc_limit_d),
      .dat_o  (s_desc_limit_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_memory_to_packet_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_memory_to_packet_d),
      .dat_o  (s_memory_to_packet_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_allow_short_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_allow_short_d),
      .dat_o  (s_allow_short_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_unlimited_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_unlimited_d),
      .dat_o  (s_unlimited_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_remaining_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_remaining_d),
      .dat_o  (s_remaining_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_total_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_total_done_d),
      .dat_o  (s_total_done_q)
  );
  dffr #(
      .DATA_WIDTH(256)
  ) u_desc_words_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_desc_words_d),
      .dat_o  (s_desc_words_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_fetch_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fetch_index_d),
      .dat_o  (s_fetch_index_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_selected_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_selected_bytes_d),
      .dat_o  (s_selected_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_desc_progress_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_desc_progress_d),
      .dat_o  (s_desc_progress_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_burst_beats_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_burst_beats_d),
      .dat_o  (s_burst_beats_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_burst_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_burst_index_d),
      .dat_o  (s_burst_index_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_writeback_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_writeback_index_d),
      .dat_o  (s_writeback_index_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_fault_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_d),
      .dat_o  (s_fault_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_error_code_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_code_d),
      .dat_o  (s_err_code_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_abort_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_abort_pending_d),
      .dat_o  (s_abort_pending_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_done_d),
      .dat_o  (s_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_descriptor_irq_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_descriptor_irq_d),
      .dat_o  (s_descriptor_irq_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_abort_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_abort_done_d),
      .dat_o  (s_abort_done_q)
  );

`ifndef SYNTHESIS
  initial begin
    if ((AddrWidth != 32) || (DataWidth != 32) || (MaxDescriptors < 2) ||
        (MaxDescriptors > 256)) begin
      $fatal(1, "usb2_dma: delivered configuration requires 32-bit AXI and 2..256 descriptors");
    end
  end
`endif
endmodule
