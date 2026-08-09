// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module ribp_uart #(
    parameter int TX_FIFO_DEPTH = 64,
    parameter int RX_FIFO_DEPTH = 64
) (
    // verilog_format: off
    input  logic  clk_i,
    input  logic  rst_n_i,
    output logic  dma_tx_stall_o,
    output logic  dma_rx_stall_o,
    ribp_if.slave ribp,
    uart_if.dut   uart
    // verilog_format: on
);

  logic [23:0] s_baud_int;
  logic [ 7:0] s_baud_frac;
  logic [ 1:0] s_data_bits;
  logic        s_stop2;
  logic [ 1:0] s_parity;
  logic        s_tx_enable;
  logic        s_rx_enable;
  logic        s_loopback;
  logic        s_break;
  logic        s_tx_data_valid;
  logic [ 7:0] s_tx_data;
  logic        s_tx_data_pop;
  logic        s_tx_busy;
  logic        s_tx_done;
  logic        s_rx_active;
  logic        s_rx_data_valid;
  logic [11:0] s_rx_data;
  logic        s_bit_tick;
  logic        s_irq;
  logic        s_tx;

  assign uart.tx_o  = s_tx;
  assign uart.irq_o = s_irq;

  uart_reg #(
      .TX_FIFO_DEPTH(TX_FIFO_DEPTH),
      .RX_FIFO_DEPTH(RX_FIFO_DEPTH)
  ) u_uart_reg (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .ribp           (ribp),
      .baud_int_o     (s_baud_int),
      .baud_frac_o    (s_baud_frac),
      .data_bits_o    (s_data_bits),
      .stop2_o        (s_stop2),
      .parity_o       (s_parity),
      .tx_enable_o    (s_tx_enable),
      .rx_enable_o    (s_rx_enable),
      .loopback_o     (s_loopback),
      .break_o        (s_break),
      .tx_data_valid_o(s_tx_data_valid),
      .tx_data_o      (s_tx_data),
      .tx_data_pop_i  (s_tx_data_pop),
      .tx_busy_i      (s_tx_busy),
      .tx_done_i      (s_tx_done),
      .rx_active_i    (s_rx_active),
      .rx_data_valid_i(s_rx_data_valid),
      .rx_data_i      (s_rx_data),
      .bit_tick_i     (s_bit_tick),
      .dma_tx_stall_o (dma_tx_stall_o),
      .dma_rx_stall_o (dma_rx_stall_o),
      .irq_o          (s_irq)
  );

  uart_core u_uart_core (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .baud_int_i     (s_baud_int),
      .baud_frac_i    (s_baud_frac),
      .data_bits_i    (s_data_bits),
      .stop2_i        (s_stop2),
      .parity_i       (s_parity),
      .tx_enable_i    (s_tx_enable),
      .rx_enable_i    (s_rx_enable),
      .loopback_i     (s_loopback),
      .break_i        (s_break),
      .tx_data_valid_i(s_tx_data_valid),
      .tx_data_i      (s_tx_data),
      .tx_data_pop_o  (s_tx_data_pop),
      .tx_busy_o      (s_tx_busy),
      .tx_done_o      (s_tx_done),
      .rx_active_o    (s_rx_active),
      .rx_data_valid_o(s_rx_data_valid),
      .rx_data_o      (s_rx_data),
      .bit_tick_o     (s_bit_tick),
      .rx_i           (uart.rx_i),
      .tx_o           (s_tx)
  );

endmodule
