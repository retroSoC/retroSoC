// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module ribp_ws2812 #(
    parameter int TxFifoDepth = 16
) (
    // verilog_format: off
    input logic    clk_i,
    input logic    rst_n_i,
    ribp_if.slave  ribp,
    ws2812_if.dut ws2812
    // verilog_format: on
);

  logic [15:0] s_bit_cycles;
  logic [15:0] s_t0h_cycles;
  logic [15:0] s_t1h_cycles;
  logic [31:0] s_reset_cycles;
  logic [31:0] s_frame_words;
  logic s_start, s_abort;
  logic s_data_valid, s_data_pop;
  logic [23:0] s_data;
  logic        s_fifo_flush;
  logic s_busy, s_reset_active;
  logic [31:0] s_remaining_words;
  logic s_done, s_underflow, s_aborted;
  logic s_irq, s_dat;

  assign ws2812.dat_o = s_dat;
  assign ws2812.irq_o = s_irq;

  ws2812_reg #(
      .TxFifoDepth(TxFifoDepth)
  ) u_ws2812_reg (
      .clk_i                 (clk_i),
      .rst_n_i               (rst_n_i),
      .ribp                  (ribp),
      .bit_cycles_o          (s_bit_cycles),
      .t0h_cycles_o          (s_t0h_cycles),
      .t1h_cycles_o          (s_t1h_cycles),
      .reset_cycles_o        (s_reset_cycles),
      .frame_words_o         (s_frame_words),
      .start_o               (s_start),
      .abort_o               (s_abort),
      .data_valid_o          (s_data_valid),
      .data_o                (s_data),
      .data_pop_i            (s_data_pop),
      .core_fifo_flush_i     (s_fifo_flush),
      .core_busy_i           (s_busy),
      .core_reset_active_i   (s_reset_active),
      .core_remaining_words_i(s_remaining_words),
      .core_done_i           (s_done),
      .core_underflow_i      (s_underflow),
      .core_aborted_i        (s_aborted),
      .irq_o                 (s_irq)
  );

  ws2812_core u_ws2812_core (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .bit_cycles_i     (s_bit_cycles),
      .t0h_cycles_i     (s_t0h_cycles),
      .t1h_cycles_i     (s_t1h_cycles),
      .reset_cycles_i   (s_reset_cycles),
      .frame_words_i    (s_frame_words),
      .start_i          (s_start),
      .abort_i          (s_abort),
      .data_valid_i     (s_data_valid),
      .data_i           (s_data),
      .data_pop_o       (s_data_pop),
      .fifo_flush_o     (s_fifo_flush),
      .busy_o           (s_busy),
      .reset_active_o   (s_reset_active),
      .remaining_words_o(s_remaining_words),
      .done_o           (s_done),
      .underflow_o      (s_underflow),
      .aborted_o        (s_aborted),
      .dat_o            (s_dat)
  );

endmodule
