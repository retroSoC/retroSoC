// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module ws2812_core (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [15:0] bit_cycles_i,
    input  logic [15:0] t0h_cycles_i,
    input  logic [15:0] t1h_cycles_i,
    input  logic [31:0] reset_cycles_i,
    input  logic [31:0] frame_words_i,
    input  logic        start_i,
    input  logic        abort_i,
    input  logic        data_valid_i,
    input  logic [23:0] data_i,
    output logic        data_pop_o,
    output logic        fifo_flush_o,
    output logic        busy_o,
    output logic        reset_active_o,
    output logic [31:0] remaining_words_o,
    output logic        done_o,
    output logic        underflow_o,
    output logic        aborted_o,
    output logic        dat_o
    // verilog_format: on
);

  typedef enum logic [1:0] {
    WS_IDLE,
    WS_XFER,
    WS_RESET
  } ws_state_t;

  ws_state_t s_state_d, s_state_q;
  logic [15:0] s_bit_cycles_d, s_bit_cycles_q;
  logic [15:0] s_t0h_cycles_d, s_t0h_cycles_q;
  logic [15:0] s_t1h_cycles_d, s_t1h_cycles_q;
  logic [31:0] s_reset_cycles_d, s_reset_cycles_q;
  logic [15:0] s_bit_cycle_d, s_bit_cycle_q;
  logic [4:0] s_bit_index_d, s_bit_index_q;
  logic [31:0] s_reset_cycle_d, s_reset_cycle_q;
  logic [31:0] s_remaining_words_d, s_remaining_words_q;
  logic [23:0] s_xfer_data_d, s_xfer_data_q;
  logic s_success_pending_d, s_success_pending_q;
  logic s_abort_pending_d, s_abort_pending_q;
  logic s_done_d, s_done_q;
  logic s_underflow_d, s_underflow_q;
  logic s_aborted_d, s_aborted_q;
  logic [15:0] s_high_cycles;

  assign busy_o            = s_state_q != WS_IDLE;
  assign reset_active_o    = s_state_q == WS_RESET;
  assign remaining_words_o = s_remaining_words_q;
  assign done_o            = s_done_q;
  assign underflow_o       = s_underflow_q;
  assign aborted_o         = s_aborted_q;
  assign s_high_cycles     = s_xfer_data_q[23] ? s_t1h_cycles_q : s_t0h_cycles_q;

  always_comb begin
    s_state_d           = s_state_q;
    s_bit_cycles_d      = s_bit_cycles_q;
    s_t0h_cycles_d      = s_t0h_cycles_q;
    s_t1h_cycles_d      = s_t1h_cycles_q;
    s_reset_cycles_d    = s_reset_cycles_q;
    s_bit_cycle_d       = s_bit_cycle_q;
    s_bit_index_d       = s_bit_index_q;
    s_reset_cycle_d     = s_reset_cycle_q;
    s_remaining_words_d = s_remaining_words_q;
    s_xfer_data_d       = s_xfer_data_q;
    s_success_pending_d = s_success_pending_q;
    s_abort_pending_d   = s_abort_pending_q;
    s_done_d            = 1'b0;
    s_underflow_d       = 1'b0;
    s_aborted_d         = 1'b0;
    data_pop_o          = 1'b0;
    fifo_flush_o        = 1'b0;
    dat_o               = 1'b0;

    unique case (s_state_q)
      WS_IDLE: begin
        s_bit_cycle_d       = '0;
        s_bit_index_d       = '0;
        s_reset_cycle_d     = '0;
        s_remaining_words_d = '0;
        s_success_pending_d = 1'b0;
        s_abort_pending_d   = 1'b0;
        if (start_i) begin
          s_bit_cycles_d      = bit_cycles_i;
          s_t0h_cycles_d      = t0h_cycles_i;
          s_t1h_cycles_d      = t1h_cycles_i;
          s_reset_cycles_d    = reset_cycles_i;
          s_remaining_words_d = frame_words_i;
          s_xfer_data_d       = data_i;
          data_pop_o          = 1'b1;
          s_state_d           = WS_XFER;
        end
      end

      WS_XFER: begin
        dat_o = s_bit_cycle_q < s_high_cycles;
        if (abort_i) begin
          s_bit_cycle_d       = '0;
          s_bit_index_d       = '0;
          s_reset_cycle_d     = '0;
          s_remaining_words_d = '0;
          s_success_pending_d = 1'b0;
          s_abort_pending_d   = 1'b1;
          fifo_flush_o        = 1'b1;
          s_state_d           = WS_RESET;
        end else if (s_bit_cycle_q == (s_bit_cycles_q - 1'b1)) begin
          s_bit_cycle_d = '0;
          if (s_bit_index_q == 5'd23) begin
            s_bit_index_d = '0;
            if (s_remaining_words_q == 32'd1) begin
              s_remaining_words_d = '0;
              s_reset_cycle_d     = '0;
              s_success_pending_d = 1'b1;
              s_state_d           = WS_RESET;
            end else if (data_valid_i) begin
              s_remaining_words_d = s_remaining_words_q - 1'b1;
              s_xfer_data_d       = data_i;
              data_pop_o          = 1'b1;
            end else begin
              s_remaining_words_d = '0;
              s_reset_cycle_d     = '0;
              s_success_pending_d = 1'b0;
              s_abort_pending_d   = 1'b0;
              s_underflow_d       = 1'b1;
              fifo_flush_o        = 1'b1;
              s_state_d           = WS_RESET;
            end
          end else begin
            s_bit_index_d = s_bit_index_q + 1'b1;
            s_xfer_data_d = {s_xfer_data_q[22:0], 1'b0};
          end
        end else begin
          s_bit_cycle_d = s_bit_cycle_q + 1'b1;
        end
      end

      WS_RESET: begin
        if (abort_i) begin
          s_reset_cycle_d     = '0;
          s_success_pending_d = 1'b0;
          s_abort_pending_d   = 1'b1;
          fifo_flush_o        = 1'b1;
        end else if (s_reset_cycle_q == (s_reset_cycles_q - 1'b1)) begin
          s_reset_cycle_d = '0;
          s_state_d       = WS_IDLE;
          if (s_abort_pending_q) begin
            s_aborted_d = 1'b1;
          end else if (s_success_pending_q) begin
            s_done_d = 1'b1;
          end
          s_success_pending_d = 1'b0;
          s_abort_pending_d   = 1'b0;
        end else begin
          s_reset_cycle_d = s_reset_cycle_q + 1'b1;
        end
      end

      default: begin
        s_state_d           = WS_IDLE;
        s_bit_cycle_d       = '0;
        s_bit_index_d       = '0;
        s_reset_cycle_d     = '0;
        s_remaining_words_d = '0;
        s_success_pending_d = 1'b0;
        s_abort_pending_d   = 1'b0;
        fifo_flush_o        = 1'b1;
      end
    endcase
  end

  dffercn #(
      .REG_TYPE (ws_state_t),
      .RESET_VAL(WS_IDLE)
  ) u_state_dffercn (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (1'b1),
      .dat_i  (s_state_d),
      .dat_o  (s_state_q)
  );

  dffr #(16) u_bit_cycles_dffr (
      clk_i,
      rst_n_i,
      s_bit_cycles_d,
      s_bit_cycles_q
  );
  dffr #(16) u_t0h_cycles_dffr (
      clk_i,
      rst_n_i,
      s_t0h_cycles_d,
      s_t0h_cycles_q
  );
  dffr #(16) u_t1h_cycles_dffr (
      clk_i,
      rst_n_i,
      s_t1h_cycles_d,
      s_t1h_cycles_q
  );
  dffr #(32) u_reset_cycles_dffr (
      clk_i,
      rst_n_i,
      s_reset_cycles_d,
      s_reset_cycles_q
  );
  dffr #(16) u_bit_cycle_dffr (
      clk_i,
      rst_n_i,
      s_bit_cycle_d,
      s_bit_cycle_q
  );
  dffr #(5) u_bit_index_dffr (
      clk_i,
      rst_n_i,
      s_bit_index_d,
      s_bit_index_q
  );
  dffr #(32) u_reset_cycle_dffr (
      clk_i,
      rst_n_i,
      s_reset_cycle_d,
      s_reset_cycle_q
  );
  dffr #(32) u_remaining_words_dffr (
      clk_i,
      rst_n_i,
      s_remaining_words_d,
      s_remaining_words_q
  );
  dffr #(24) u_xfer_data_dffr (
      clk_i,
      rst_n_i,
      s_xfer_data_d,
      s_xfer_data_q
  );
  dffr #(1) u_success_pending_dffr (
      clk_i,
      rst_n_i,
      s_success_pending_d,
      s_success_pending_q
  );
  dffr #(1) u_abort_pending_dffr (
      clk_i,
      rst_n_i,
      s_abort_pending_d,
      s_abort_pending_q
  );
  dffr #(1) u_done_dffr (
      clk_i,
      rst_n_i,
      s_done_d,
      s_done_q
  );
  dffr #(1) u_underflow_dffr (
      clk_i,
      rst_n_i,
      s_underflow_d,
      s_underflow_q
  );
  dffr #(1) u_aborted_dffr (
      clk_i,
      rst_n_i,
      s_aborted_d,
      s_aborted_q
  );

endmodule
