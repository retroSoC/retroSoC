// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module uart_core (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [23:0] baud_int_i,
    input  logic [ 7:0] baud_frac_i,
    input  logic [ 1:0] data_bits_i,
    input  logic        stop2_i,
    input  logic [ 1:0] parity_i,
    input  logic        tx_enable_i,
    input  logic        rx_enable_i,
    input  logic        loopback_i,
    input  logic        tx_start_allowed_i,
    input  logic        break_i,
    input  logic        tx_data_valid_i,
    input  logic [ 7:0] tx_data_i,
    output logic        tx_data_pop_o,
    output logic        tx_busy_o,
    output logic        tx_done_o,
    output logic        rx_active_o,
    output logic        rx_data_valid_o,
    output logic [11:0] rx_data_o,
    output logic        bit_tick_o,
    input  logic        rx_i,
    output logic        tx_o
    // verilog_format: on
);

  logic s_sample_tick;
  logic s_tx;
  logic s_rx;

  assign s_rx = loopback_i ? s_tx : rx_i;
  assign tx_o = s_tx;

  uart_baudgen u_uart_baudgen (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .enable_i     (tx_enable_i || rx_enable_i || tx_busy_o),
      .baud_int_i   (baud_int_i),
      .baud_frac_i  (baud_frac_i),
      .sample_tick_o(s_sample_tick),
      .bit_tick_o   (bit_tick_o)
  );

  ribp_uart_tx u_ribp_uart_tx (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .sample_tick_i  (s_sample_tick),
      .enable_i       (tx_enable_i),
      .start_allowed_i(tx_start_allowed_i),
      .break_i        (break_i),
      .data_bits_i    (data_bits_i),
      .stop2_i        (stop2_i),
      .parity_i       (parity_i),
      .data_valid_i   (tx_data_valid_i),
      .data_i         (tx_data_i),
      .data_pop_o     (tx_data_pop_o),
      .busy_o         (tx_busy_o),
      .done_o         (tx_done_o),
      .tx_o           (s_tx)
  );

  ribp_uart_rx u_ribp_uart_rx (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .sample_tick_i(s_sample_tick),
      .enable_i     (rx_enable_i),
      .data_bits_i  (data_bits_i),
      .stop2_i      (stop2_i),
      .parity_i     (parity_i),
      .rx_i         (s_rx),
      .active_o     (rx_active_o),
      .data_valid_o (rx_data_valid_o),
      .data_o       (rx_data_o)
  );

endmodule
