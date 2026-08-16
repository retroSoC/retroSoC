// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module apb4_uart #(
    parameter int TxFifoDepth = 64,
    parameter int RxFifoDepth = 64
) (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic  clk_i,
    input  logic  rst_n_i,
    output logic  dma_tx_stall_o,
    output logic  dma_rx_stall_o,
    apb4_if.slave apb4,
    uart_if.dut   uart
    // verilog_format: on
);

  logic [23:0] s_baud_int;
  logic [ 7:0] s_baud_frac;
  logic [ 1:0] s_data_bits;
  logic        s_stop2;
  logic [ 1:0] s_parity;
  logic        s_tx_en;
  logic        s_rx_en;
  logic        s_loopback;
  logic        s_break;
  logic        s_auto_cts_en;
  logic        s_auto_rts_en;
  logic [ 6:0] s_rts_assert_level;
  logic [ 6:0] s_rts_deassert_level;
  logic        s_tx_data_valid;
  logic [ 7:0] s_tx_data;
  logic [ 6:0] s_rx_level;
  logic        s_tx_data_pop;
  logic        s_tx_busy;
  logic        s_tx_done;
  logic        s_rx_active;
  logic        s_rx_data_valid;
  logic [11:0] s_rx_data;
  logic        s_bit_tick;
  logic        s_irq;
  logic        s_tx;
  logic        s_cts_asserted;
  logic        s_rts_asserted;
  logic        s_tx_start_allowed;
  logic        s_tx_flow_blocked;
  logic        s_cts_change;

  assign uart.tx_o  = s_tx;
  assign uart.irq_o = s_irq;

  uart_reg #(
      .TxFifoDepth(TxFifoDepth),
      .RxFifoDepth(RxFifoDepth)
  ) u_uart_reg (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .apb4                (apb4),
      .baud_int_o          (s_baud_int),
      .baud_frac_o         (s_baud_frac),
      .data_bits_o         (s_data_bits),
      .stop2_o             (s_stop2),
      .parity_o            (s_parity),
      .tx_enable_o         (s_tx_en),
      .rx_enable_o         (s_rx_en),
      .loopback_o          (s_loopback),
      .break_o             (s_break),
      .auto_cts_enable_o   (s_auto_cts_en),
      .auto_rts_enable_o   (s_auto_rts_en),
      .rts_assert_level_o  (s_rts_assert_level),
      .rts_deassert_level_o(s_rts_deassert_level),
      .tx_data_valid_o     (s_tx_data_valid),
      .tx_data_o           (s_tx_data),
      .rx_level_o          (s_rx_level),
      .tx_data_pop_i       (s_tx_data_pop),
      .tx_busy_i           (s_tx_busy),
      .tx_done_i           (s_tx_done),
      .rx_active_i         (s_rx_active),
      .rx_data_valid_i     (s_rx_data_valid),
      .rx_data_i           (s_rx_data),
      .bit_tick_i          (s_bit_tick),
      .cts_asserted_i      (s_cts_asserted),
      .rts_asserted_i      (s_rts_asserted),
      .tx_flow_blocked_i   (s_tx_flow_blocked),
      .cts_change_i        (s_cts_change),
      .dma_tx_stall_o      (dma_tx_stall_o),
      .dma_rx_stall_o      (dma_rx_stall_o),
      .irq_o               (s_irq)
  );

  uart_core u_uart_core (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .baud_int_i        (s_baud_int),
      .baud_frac_i       (s_baud_frac),
      .data_bits_i       (s_data_bits),
      .stop2_i           (s_stop2),
      .parity_i          (s_parity),
      .tx_enable_i       (s_tx_en),
      .rx_enable_i       (s_rx_en),
      .loopback_i        (s_loopback),
      .tx_start_allowed_i(s_tx_start_allowed),
      .break_i           (s_break),
      .tx_data_valid_i   (s_tx_data_valid),
      .tx_data_i         (s_tx_data),
      .tx_data_pop_o     (s_tx_data_pop),
      .tx_busy_o         (s_tx_busy),
      .tx_done_o         (s_tx_done),
      .rx_active_o       (s_rx_active),
      .rx_data_valid_o   (s_rx_data_valid),
      .rx_data_o         (s_rx_data),
      .bit_tick_o        (s_bit_tick),
      .rx_i              (uart.rx_i),
      .tx_o              (s_tx)
  );

  uart_flow_ctrl u_uart_flow_ctrl (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .cts_n_async_i       (uart.cts_n_i),
      .auto_cts_enable_i   (s_auto_cts_en),
      .auto_rts_enable_i   (s_auto_rts_en),
      .tx_enable_i         (s_tx_en),
      .rx_enable_i         (s_rx_en),
      .loopback_i          (s_loopback),
      .tx_data_valid_i     (s_tx_data_valid),
      .tx_busy_i           (s_tx_busy),
      .rx_level_i          (s_rx_level),
      .rts_assert_level_i  (s_rts_assert_level),
      .rts_deassert_level_i(s_rts_deassert_level),
      .cts_asserted_o      (s_cts_asserted),
      .rts_asserted_o      (s_rts_asserted),
      .tx_start_allowed_o  (s_tx_start_allowed),
      .tx_flow_blocked_o   (s_tx_flow_blocked),
      .cts_change_o        (s_cts_change),
      .rts_n_o             (uart.rts_n_o)
  );

endmodule
