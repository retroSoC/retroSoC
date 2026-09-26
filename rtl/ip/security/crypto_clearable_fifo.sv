// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module crypto_clearable_fifo #(
    parameter int Depth      = 8,
    parameter int CountWidth = $clog2(Depth) + 1
) (
    input  logic                  clk_i,
    input  logic                  rst_n_i,
    input  logic                  clear_i,
    input  logic                  flush_i,
    input  logic                  push_i,
    input  logic [          36:0] data_i,
    input  logic                  pop_i,
    output logic [          36:0] data_o,
    output logic                  empty_o,
    output logic                  full_o,
    output logic [CountWidth-1:0] count_o,
    output logic                  clear_busy_o,
    output logic                  clear_done_o,
    output logic                  clear_error_o
);
  typedef enum logic [2:0] {
    FifoReset,
    FifoFill,
    FifoDrain,
    FifoDone,
    FifoActive
  } clear_state_e;
  clear_state_e s_state_d, s_state_q;
  logic [$bits(clear_state_e)-1:0] s_state_value;
  logic s_err_d, s_err_q;
  logic s_full, s_empty, s_push, s_pop, s_flush;
  logic [           36:0] s_data;
  logic [$clog2(Depth):0] s_count;
  dffr #(
      .DATA_WIDTH($bits(clear_state_e))
  ) u_state (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_value)
  );
  assign s_state_q = clear_state_e'(s_state_value);
  dffr #(
      .DATA_WIDTH(1)
  ) u_error (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
  // Flush establishes pointer zero, filling touches every physical slot, and
  // draining checks every stored payload before resetting the public queue.
  fifo #(
      .DATA_WIDTH  (37),
      .BUFFER_DEPTH(Depth)
  ) u_payload (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_flush),
      .push_i (s_push),
      .full_o (s_full),
      .dat_i  (s_state_q == FifoActive ? data_i : 37'd0),
      .pop_i  (s_pop),
      .empty_o(s_empty),
      .dat_o  (s_data),
      .cnt_o  (s_count)
  );
  assign clear_busy_o  = s_state_q != FifoActive;
  assign clear_done_o  = s_state_q == FifoDone;
  assign clear_error_o = s_err_q;
  assign empty_o       = clear_busy_o || s_empty;
  assign full_o        = clear_busy_o || s_full;
  assign count_o       = clear_busy_o ? '0 : s_count;
  assign data_o        = clear_busy_o ? '0 : s_data;
  always_comb begin
    s_state_d = s_state_q;
    s_err_d   = s_err_q;
    s_push    = 1'b0;
    s_pop     = 1'b0;
    s_flush   = 1'b0;
    unique case (s_state_q)
      FifoReset: begin
        s_flush   = 1'b1;
        s_err_d   = 1'b0;
        s_state_d = FifoFill;
      end
      FifoFill: begin
        s_push = !s_full;
        if (s_full) s_state_d = FifoDrain;
      end
      FifoDrain: begin
        s_pop = !s_empty;
        if (!s_empty && (s_data != 37'd0)) s_err_d = 1'b1;
        if (s_empty) s_state_d = FifoDone;
      end
      FifoDone: begin
        s_flush   = 1'b1;
        s_state_d = FifoActive;
      end
      FifoActive: begin
        s_push  = push_i;
        s_pop   = pop_i;
        s_flush = flush_i;
        if (clear_i) begin
          s_push    = 1'b0;
          s_pop     = 1'b0;
          s_flush   = 1'b1;
          s_state_d = FifoReset;
        end
      end
      default: s_state_d = FifoReset;
    endcase
  end
endmodule
