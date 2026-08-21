// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module apb4_timer (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic  clk_i,
    input  logic  rst_n_i,
    input  logic  debug_halted_i,
    apb4_if.slave apb4,
    output logic  irq_o
    // verilog_format: on
);

  logic        s_en;
  logic [ 1:0] s_mode;
  logic        s_direction;
  logic        s_debug_freeze_en;
  logic        s_compare0_en;
  logic        s_compare1_en;
  logic [15:0] s_prescale;
  logic [31:0] s_load;
  logic [31:0] s_compare0;
  logic [31:0] s_compare1;
  logic        s_start;
  logic        s_stop;
  logic        s_load_now;
  logic [31:0] s_value;
  logic        s_debug_frozen;
  logic        s_timeout_event;
  logic        s_compare0_event;
  logic        s_compare1_event;
  logic        s_one_shot_done;

  timer_reg u_timer_reg (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .apb4                 (apb4),
      .value_i              (s_value),
      .debug_frozen_i       (s_debug_frozen),
      .timeout_event_i      (s_timeout_event),
      .compare0_event_i     (s_compare0_event),
      .compare1_event_i     (s_compare1_event),
      .one_shot_done_i      (s_one_shot_done),
      .enable_o             (s_en),
      .mode_o               (s_mode),
      .direction_o          (s_direction),
      .debug_freeze_enable_o(s_debug_freeze_en),
      .compare0_enable_o    (s_compare0_en),
      .compare1_enable_o    (s_compare1_en),
      .prescale_o           (s_prescale),
      .load_o               (s_load),
      .compare0_o           (s_compare0),
      .compare1_o           (s_compare1),
      .start_o              (s_start),
      .stop_o               (s_stop),
      .load_now_o           (s_load_now),
      .irq_o                (irq_o)
  );

  timer_core u_timer_core (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .enable_i             (s_en),
      .mode_i               (s_mode),
      .direction_i          (s_direction),
      .debug_freeze_enable_i(s_debug_freeze_en),
      .debug_halted_i       (debug_halted_i),
      .compare0_enable_i    (s_compare0_en),
      .compare1_enable_i    (s_compare1_en),
      .prescale_i           (s_prescale),
      .load_i               (s_load),
      .compare0_i           (s_compare0),
      .compare1_i           (s_compare1),
      .start_i              (s_start),
      .stop_i               (s_stop),
      .load_now_i           (s_load_now),
      .value_o              (s_value),
      .debug_frozen_o       (s_debug_frozen),
      .timeout_event_o      (s_timeout_event),
      .compare0_event_o     (s_compare0_event),
      .compare1_event_o     (s_compare1_event),
      .one_shot_done_o      (s_one_shot_done)
  );

endmodule
