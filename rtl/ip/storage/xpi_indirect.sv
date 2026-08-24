// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module xpi_indirect (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic                    clk_i,
    input  logic                    rst_n_i,
    input  logic                    indirect_start_i,
    input  logic                    poll_start_i,
    input  logic                    abort_i,
    input  logic [              1:0] indirect_slot_i,
    input  logic [              3:0] indirect_seq_i,
    input  logic [             31:0] indirect_addr_i,
    input  logic [             15:0] indirect_count_i,
    input  logic [              1:0] poll_slot_i,
    input  logic [              3:0] poll_seq_i,
    input  logic [             31:0] poll_mask_i,
    input  logic [             31:0] poll_match_i,
    input  logic [             31:0] poll_interval_i,
    input  logic [             31:0] poll_timeout_i,
    output logic                    tx_fifo_pop_o,
    input  logic                    tx_fifo_empty_i,
    input  logic [             31:0] tx_fifo_data_i,
    output logic                    rx_fifo_push_o,
    input  logic                    rx_fifo_full_i,
    output logic [             31:0] rx_fifo_data_o,
    output logic                    busy_o,
    output logic                    core_req_valid_o,
    input  logic                    core_req_ready_i,
    output logic [              1:0] core_req_slot_o,
    output logic [              3:0] core_req_seq_o,
    output logic [             31:0] core_req_addr_o,
    output logic [             15:0] core_req_len_o,
    output logic                    core_tx_valid_o,
    input  logic                    core_tx_ready_i,
    output logic [              7:0] core_tx_data_o,
    input  logic                    core_rx_valid_i,
    output logic                    core_rx_ready_o,
    input  logic [              7:0] core_rx_data_i,
    input  logic                    core_done_i,
    input  logic                    core_error_i,
    input  xpi_pkg::xpi_error_e     core_error_code_i,
    input  logic [              2:0] core_error_pc_i,
    output logic                    indirect_done_event_o,
    output logic                    poll_match_event_o,
    output logic                    timeout_event_o,
    output logic                    error_event_o,
    output logic                    abort_done_event_o,
    output xpi_pkg::xpi_error_e     error_code_o,
    output logic [             31:0] error_addr_o,
    output logic [              1:0] error_slot_o,
    output logic [              2:0] error_pc_o,
    output logic                    perf_read_byte_event_o,
    output logic                    perf_write_byte_event_o,
    output logic                    perf_command_event_o
    // verilog_format: on
);

  import xpi_pkg::*;

  typedef enum logic [2:0] {
    Idle,
    IndirectRequest,
    IndirectTransfer,
    PollRequest,
    PollTransfer,
    PollInterval
  } xpi_indirect_state_e;

  logic [2:0] s_state_bits_q;
  xpi_indirect_state_e s_state_d, s_state_q;
  logic [31:0] s_tx_word_d, s_tx_word_q;
  logic s_tx_word_valid_d, s_tx_word_valid_q;
  logic [1:0] s_tx_byte_idx_d, s_tx_byte_idx_q;
  logic [15:0] s_tx_byte_count_d, s_tx_byte_count_q;
  logic [31:0] s_rx_word_d, s_rx_word_q;
  logic [1:0] s_rx_byte_idx_d, s_rx_byte_idx_q;
  logic [15:0] s_rx_byte_count_d, s_rx_byte_count_q;
  logic s_rx_word_pending_d, s_rx_word_pending_q;
  logic s_core_finished_d, s_core_finished_q;
  logic [31:0] s_poll_value_d, s_poll_value_q;
  logic [31:0] s_poll_elapsed_d, s_poll_elapsed_q;
  logic [31:0] s_poll_interval_cnt_d, s_poll_interval_cnt_q;
  logic [3:0] s_err_code_bits_q;
  xpi_error_e s_err_code_d, s_err_code_q;
  logic [31:0] s_err_addr_d, s_err_addr_q;
  logic [1:0] s_err_slot_d, s_err_slot_q;
  logic [2:0] s_err_pc_d, s_err_pc_q;
  logic        s_polling;
  logic        s_rx_last_byte;
  logic [31:0] s_rx_word_with_byte;

  assign s_state_q = xpi_indirect_state_e'(s_state_bits_q);
  assign s_err_code_q = xpi_error_e'(s_err_code_bits_q);
  assign s_polling = (s_state_q == PollRequest) || (s_state_q == PollTransfer) ||
                     (s_state_q == PollInterval);
  assign busy_o = s_state_q != Idle;
  assign core_req_valid_o = (s_state_q == IndirectRequest) || (s_state_q == PollRequest);
  assign core_req_slot_o = s_polling ? poll_slot_i : indirect_slot_i;
  assign core_req_seq_o = s_polling ? poll_seq_i : indirect_seq_i;
  assign core_req_addr_o = s_polling ? 32'd0 : indirect_addr_i;
  assign core_req_len_o = s_polling ? 16'd4 : indirect_count_i;
  assign core_tx_valid_o = (s_state_q == IndirectTransfer) && s_tx_word_valid_q &&
                           (s_tx_byte_count_q < indirect_count_i);
  assign core_tx_data_o = s_tx_word_q[(s_tx_byte_idx_q*8)+:8];
  assign core_rx_ready_o = ((s_state_q == IndirectTransfer) && !s_rx_word_pending_q) ||
                           (s_state_q == PollTransfer);
  assign rx_fifo_push_o = s_rx_word_pending_q && !rx_fifo_full_i;
  assign rx_fifo_data_o = s_rx_word_q;
  assign tx_fifo_pop_o = (s_state_q == IndirectTransfer) && !s_tx_word_valid_q &&
                         !tx_fifo_empty_i && (s_tx_byte_count_q < indirect_count_i);
  assign s_rx_last_byte = (s_rx_byte_count_q + 1'b1) >= indirect_count_i;

  always_comb begin
    s_rx_word_with_byte                         = s_rx_word_q;
    s_rx_word_with_byte[(s_rx_byte_idx_q*8)+:8] = core_rx_data_i;
  end

  assign error_code_o = s_err_code_q;
  assign error_addr_o = s_err_addr_q;
  assign error_slot_o = s_err_slot_q;
  assign error_pc_o   = s_err_pc_q;

  always_comb begin
    s_state_d               = s_state_q;
    s_tx_word_d             = s_tx_word_q;
    s_tx_word_valid_d       = s_tx_word_valid_q;
    s_tx_byte_idx_d         = s_tx_byte_idx_q;
    s_tx_byte_count_d       = s_tx_byte_count_q;
    s_rx_word_d             = s_rx_word_q;
    s_rx_byte_idx_d         = s_rx_byte_idx_q;
    s_rx_byte_count_d       = s_rx_byte_count_q;
    s_rx_word_pending_d     = s_rx_word_pending_q;
    s_core_finished_d       = s_core_finished_q;
    s_poll_value_d          = s_poll_value_q;
    s_poll_elapsed_d        = s_poll_elapsed_q;
    s_poll_interval_cnt_d   = s_poll_interval_cnt_q;
    s_err_code_d            = s_err_code_q;
    s_err_addr_d            = s_err_addr_q;
    s_err_slot_d            = s_err_slot_q;
    s_err_pc_d              = s_err_pc_q;
    indirect_done_event_o   = 1'b0;
    poll_match_event_o      = 1'b0;
    timeout_event_o         = 1'b0;
    error_event_o           = 1'b0;
    abort_done_event_o      = 1'b0;
    perf_read_byte_event_o  = 1'b0;
    perf_write_byte_event_o = 1'b0;
    perf_command_event_o    = 1'b0;

    if (tx_fifo_pop_o) begin
      s_tx_word_d       = tx_fifo_data_i;
      s_tx_word_valid_d = 1'b1;
      s_tx_byte_idx_d   = '0;
    end
    if (rx_fifo_push_o) begin
      s_rx_word_pending_d = 1'b0;
      s_rx_word_d         = '0;
      s_rx_byte_idx_d     = '0;
    end

    unique case (s_state_q)
      Idle: begin
        s_tx_word_valid_d   = 1'b0;
        s_tx_byte_idx_d     = '0;
        s_tx_byte_count_d   = '0;
        s_rx_word_d         = '0;
        s_rx_byte_idx_d     = '0;
        s_rx_byte_count_d   = '0;
        s_rx_word_pending_d = 1'b0;
        s_core_finished_d   = 1'b0;
        s_poll_value_d      = '0;
        s_poll_elapsed_d    = '0;
        s_err_code_d        = XpiErrorNone;
        if (indirect_start_i) begin
          s_state_d = IndirectRequest;
        end else if (poll_start_i) begin
          s_state_d = PollRequest;
        end
      end

      IndirectRequest: begin
        if (abort_i) begin
          abort_done_event_o = 1'b1;
          s_err_code_d       = XpiErrorAborted;
          s_err_addr_d       = indirect_addr_i;
          s_err_slot_d       = indirect_slot_i;
          s_state_d          = Idle;
        end else if (core_req_valid_o && core_req_ready_i) begin
          perf_command_event_o = 1'b1;
          s_state_d            = IndirectTransfer;
        end
      end

      IndirectTransfer: begin
        if (core_tx_valid_o && core_tx_ready_i) begin
          perf_write_byte_event_o = 1'b1;
          s_tx_byte_count_d       = s_tx_byte_count_q + 1'b1;
          if ((s_tx_byte_idx_q == 2'd3) || ((s_tx_byte_count_q + 1'b1) >= indirect_count_i)) begin
            s_tx_word_valid_d = 1'b0;
            s_tx_byte_idx_d   = '0;
          end else begin
            s_tx_byte_idx_d = s_tx_byte_idx_q + 1'b1;
          end
        end
        if (core_rx_valid_i && core_rx_ready_o) begin
          perf_read_byte_event_o = 1'b1;
          s_rx_word_d            = s_rx_word_with_byte;
          s_rx_byte_count_d      = s_rx_byte_count_q + 1'b1;
          if ((s_rx_byte_idx_q == 2'd3) || s_rx_last_byte) begin
            s_rx_word_pending_d = 1'b1;
            s_rx_byte_idx_d     = '0;
          end else begin
            s_rx_byte_idx_d = s_rx_byte_idx_q + 1'b1;
          end
        end
        if (core_done_i) begin
          s_core_finished_d = 1'b1;
          if (core_error_i) begin
            s_err_code_d  = core_error_code_i;
            s_err_addr_d  = indirect_addr_i;
            s_err_slot_d  = indirect_slot_i;
            s_err_pc_d    = core_error_pc_i;
            error_event_o = 1'b1;
            s_state_d     = Idle;
          end else if (!s_rx_word_pending_q || rx_fifo_push_o) begin
            indirect_done_event_o = 1'b1;
            s_state_d             = Idle;
          end
        end else if (s_core_finished_q && (!s_rx_word_pending_q || rx_fifo_push_o)) begin
          indirect_done_event_o = 1'b1;
          s_state_d             = Idle;
        end
      end

      PollRequest: begin
        if (abort_i) begin
          abort_done_event_o = 1'b1;
          s_err_code_d       = XpiErrorAborted;
          s_err_slot_d       = poll_slot_i;
          s_state_d          = Idle;
        end else if (core_req_valid_o && core_req_ready_i) begin
          perf_command_event_o = 1'b1;
          s_poll_value_d       = '0;
          s_rx_byte_idx_d      = '0;
          s_state_d            = PollTransfer;
        end
      end

      PollTransfer: begin
        s_poll_elapsed_d = s_poll_elapsed_q + 1'b1;
        if (core_rx_valid_i && core_rx_ready_o) begin
          s_poll_value_d[(s_rx_byte_idx_q*8)+:8] = core_rx_data_i;
          s_rx_byte_idx_d                        = s_rx_byte_idx_q + 1'b1;
          perf_read_byte_event_o                 = 1'b1;
        end
        if (core_done_i) begin
          if (core_error_i) begin
            s_err_code_d  = core_error_code_i;
            s_err_slot_d  = poll_slot_i;
            s_err_pc_d    = core_error_pc_i;
            error_event_o = 1'b1;
            s_state_d     = Idle;
          end else if ((s_poll_value_q & poll_mask_i) == (poll_match_i & poll_mask_i)) begin
            poll_match_event_o = 1'b1;
            s_state_d          = Idle;
          end else if ((poll_timeout_i != 32'd0) &&
                       (s_poll_elapsed_q >= poll_timeout_i - 1'b1)) begin
            s_err_code_d    = XpiErrorTimeout;
            s_err_slot_d    = poll_slot_i;
            timeout_event_o = 1'b1;
            s_state_d       = Idle;
          end else begin
            s_poll_interval_cnt_d = poll_interval_i;
            s_state_d             = PollInterval;
          end
        end
      end

      PollInterval: begin
        s_poll_elapsed_d = s_poll_elapsed_q + 1'b1;
        if (abort_i) begin
          abort_done_event_o = 1'b1;
          s_err_code_d       = XpiErrorAborted;
          s_err_slot_d       = poll_slot_i;
          s_state_d          = Idle;
        end else if ((poll_timeout_i != 32'd0) && (s_poll_elapsed_q >= poll_timeout_i - 1'b1)) begin
          s_err_code_d    = XpiErrorTimeout;
          s_err_slot_d    = poll_slot_i;
          timeout_event_o = 1'b1;
          s_state_d       = Idle;
        end else if (s_poll_interval_cnt_q == 32'd0) begin
          s_state_d = PollRequest;
        end else begin
          s_poll_interval_cnt_d = s_poll_interval_cnt_q - 1'b1;
        end
      end

      default: s_state_d = Idle;
    endcase
  end

  dffrc #(
      .DATA_WIDTH(3),
      .RESET_VAL (Idle)
  ) u_state_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_tx_word_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_word_d),
      .dat_o  (s_tx_word_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_tx_word_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_word_valid_d),
      .dat_o  (s_tx_word_valid_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_tx_byte_idx_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_byte_idx_d),
      .dat_o  (s_tx_byte_idx_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_tx_byte_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_byte_count_d),
      .dat_o  (s_tx_byte_count_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_rx_word_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_word_d),
      .dat_o  (s_rx_word_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_rx_byte_idx_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_byte_idx_d),
      .dat_o  (s_rx_byte_idx_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_rx_byte_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_byte_count_d),
      .dat_o  (s_rx_byte_count_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rx_word_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_word_pending_d),
      .dat_o  (s_rx_word_pending_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_core_finished_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_core_finished_d),
      .dat_o  (s_core_finished_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_poll_value_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_poll_value_d),
      .dat_o  (s_poll_value_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_poll_elapsed_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_poll_elapsed_d),
      .dat_o  (s_poll_elapsed_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_poll_interval_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_poll_interval_cnt_d),
      .dat_o  (s_poll_interval_cnt_q)
  );
  dffrc #(
      .DATA_WIDTH(4),
      .RESET_VAL (XpiErrorNone)
  ) u_error_code_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_code_d),
      .dat_o  (s_err_code_bits_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_error_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_addr_d),
      .dat_o  (s_err_addr_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_error_slot_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_slot_d),
      .dat_o  (s_err_slot_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_error_pc_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_pc_d),
      .dat_o  (s_err_pc_q)
  );

endmodule
