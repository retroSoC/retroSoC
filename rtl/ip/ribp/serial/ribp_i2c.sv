// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module ribp_i2c #(
    parameter int CMD_FIFO_DEPTH = 16,
    parameter int RX_FIFO_DEPTH  = 16
) (
    // verilog_format: off
    input  logic  clk_i,
    input  logic  rst_n_i,
    output logic  dma_tx_stall_o,
    output logic  dma_rx_stall_o,
    ribp_if.slave ribp,
    i2c_if.dut    i2c
    // verilog_format: on
);

  logic        s_enable;
  logic [15:0] s_scl_low_cycles;
  logic [15:0] s_scl_high_cycles;
  logic [15:0] s_start_hold_cycles;
  logic [15:0] s_start_setup_cycles;
  logic [15:0] s_data_hold_cycles;
  logic [15:0] s_data_setup_cycles;
  logic [15:0] s_stop_setup_cycles;
  logic [15:0] s_bus_free_cycles;
  logic [ 3:0] s_scl_filter_cycles;
  logic [ 3:0] s_sda_filter_cycles;
  logic [23:0] s_stretch_timeout;
  logic [23:0] s_bus_idle_timeout;
  logic [23:0] s_command_timeout;
  logic [ 9:0] s_target_addr;
  logic        s_ten_bit;
  logic        s_abort;
  logic        s_recover;
  logic        s_cmd_valid;
  logic [11:0] s_cmd_data;
  logic        s_cmd_pop;
  logic        s_rx_push;
  logic [ 7:0] s_rx_data;
  logic        s_rx_full;
  logic        s_busy;
  logic        s_recovery_active;
  logic        s_scl_filtered;
  logic        s_sda_filtered;
  logic        s_scl_pull_low;
  logic        s_sda_pull_low;
  logic        s_done_event;
  logic        s_addr_nack_event;
  logic        s_data_nack_event;
  logic        s_arb_lost_event;
  logic        s_stretch_timeout_event;
  logic        s_bus_timeout_event;
  logic        s_command_timeout_event;
  logic        s_command_error_event;
  logic        s_rx_overflow_event;
  logic        s_aborted_event;
  logic        s_recovery_done_event;
  logic        s_recovery_failed_event;
  logic        s_core_cmd_flush;

  assign i2c.scl_o    = 1'b0;
  assign i2c.sda_o    = 1'b0;
  assign i2c.scl_oe_o = s_scl_pull_low;
  assign i2c.sda_oe_o = s_sda_pull_low;

  i2c_filter u_i2c_filter (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .scl_filter_cycles_i(s_scl_filter_cycles),
      .sda_filter_cycles_i(s_sda_filter_cycles),
      .scl_async_i        (i2c.scl_i),
      .sda_async_i        (i2c.sda_i),
      .scl_o              (s_scl_filtered),
      .sda_o              (s_sda_filtered)
  );

  i2c_reg #(
      .CMD_FIFO_DEPTH(CMD_FIFO_DEPTH),
      .RX_FIFO_DEPTH (RX_FIFO_DEPTH)
  ) u_i2c_reg (
      .clk_i                  (clk_i),
      .rst_n_i                (rst_n_i),
      .ribp                   (ribp),
      .enable_o               (s_enable),
      .scl_low_cycles_o       (s_scl_low_cycles),
      .scl_high_cycles_o      (s_scl_high_cycles),
      .start_hold_cycles_o    (s_start_hold_cycles),
      .start_setup_cycles_o   (s_start_setup_cycles),
      .data_hold_cycles_o     (s_data_hold_cycles),
      .data_setup_cycles_o    (s_data_setup_cycles),
      .stop_setup_cycles_o    (s_stop_setup_cycles),
      .bus_free_cycles_o      (s_bus_free_cycles),
      .scl_filter_cycles_o    (s_scl_filter_cycles),
      .sda_filter_cycles_o    (s_sda_filter_cycles),
      .stretch_timeout_o      (s_stretch_timeout),
      .bus_idle_timeout_o     (s_bus_idle_timeout),
      .command_timeout_o      (s_command_timeout),
      .target_addr_o          (s_target_addr),
      .ten_bit_o              (s_ten_bit),
      .abort_o                (s_abort),
      .recover_o              (s_recover),
      .cmd_valid_o            (s_cmd_valid),
      .cmd_data_o             (s_cmd_data),
      .cmd_pop_i              (s_cmd_pop),
      .core_cmd_flush_i       (s_core_cmd_flush),
      .rx_push_i              (s_rx_push),
      .rx_data_i              (s_rx_data),
      .rx_full_o              (s_rx_full),
      .busy_i                 (s_busy),
      .recovery_active_i      (s_recovery_active),
      .scl_i                  (s_scl_filtered),
      .sda_i                  (s_sda_filtered),
      .done_event_i           (s_done_event),
      .addr_nack_event_i      (s_addr_nack_event),
      .data_nack_event_i      (s_data_nack_event),
      .arb_lost_event_i       (s_arb_lost_event),
      .stretch_timeout_event_i(s_stretch_timeout_event),
      .bus_timeout_event_i    (s_bus_timeout_event),
      .command_timeout_event_i(s_command_timeout_event),
      .command_error_event_i  (s_command_error_event),
      .rx_overflow_event_i    (s_rx_overflow_event),
      .aborted_event_i        (s_aborted_event),
      .recovery_done_event_i  (s_recovery_done_event),
      .recovery_failed_event_i(s_recovery_failed_event),
      .dma_tx_stall_o         (dma_tx_stall_o),
      .dma_rx_stall_o         (dma_rx_stall_o),
      .irq_o                  (i2c.irq_o)
  );

  i2c_core u_i2c_core (
      .clk_i                  (clk_i),
      .rst_n_i                (rst_n_i),
      .enable_i               (s_enable),
      .scl_low_cycles_i       (s_scl_low_cycles),
      .scl_high_cycles_i      (s_scl_high_cycles),
      .start_hold_cycles_i    (s_start_hold_cycles),
      .start_setup_cycles_i   (s_start_setup_cycles),
      .data_hold_cycles_i     (s_data_hold_cycles),
      .data_setup_cycles_i    (s_data_setup_cycles),
      .stop_setup_cycles_i    (s_stop_setup_cycles),
      .bus_free_cycles_i      (s_bus_free_cycles),
      .stretch_timeout_i      (s_stretch_timeout),
      .bus_idle_timeout_i     (s_bus_idle_timeout),
      .command_timeout_i      (s_command_timeout),
      .target_addr_i          (s_target_addr),
      .ten_bit_i              (s_ten_bit),
      .abort_i                (s_abort),
      .recover_i              (s_recover),
      .cmd_valid_i            (s_cmd_valid),
      .cmd_data_i             (s_cmd_data),
      .cmd_pop_o              (s_cmd_pop),
      .cmd_flush_o            (s_core_cmd_flush),
      .rx_full_i              (s_rx_full),
      .rx_push_o              (s_rx_push),
      .rx_data_o              (s_rx_data),
      .scl_i                  (s_scl_filtered),
      .sda_i                  (s_sda_filtered),
      .scl_pull_low_o         (s_scl_pull_low),
      .sda_pull_low_o         (s_sda_pull_low),
      .busy_o                 (s_busy),
      .recovery_active_o      (s_recovery_active),
      .done_event_o           (s_done_event),
      .addr_nack_event_o      (s_addr_nack_event),
      .data_nack_event_o      (s_data_nack_event),
      .arb_lost_event_o       (s_arb_lost_event),
      .stretch_timeout_event_o(s_stretch_timeout_event),
      .bus_timeout_event_o    (s_bus_timeout_event),
      .command_timeout_event_o(s_command_timeout_event),
      .command_error_event_o  (s_command_error_event),
      .rx_overflow_event_o    (s_rx_overflow_event),
      .aborted_event_o        (s_aborted_event),
      .recovery_done_event_o  (s_recovery_done_event),
      .recovery_failed_event_o(s_recovery_failed_event)
  );

endmodule
