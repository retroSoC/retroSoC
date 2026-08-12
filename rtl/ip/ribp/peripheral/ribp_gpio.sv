// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module ribp_gpio #(
    parameter int          PIN_NUM         = 32,
    parameter logic [31:0] USER_BASE_ADDR  = 32'h1000_0000,
    parameter logic [31:0] ADMIN_BASE_ADDR = 32'h1001_4000,
    parameter bit          HAS_INPUT_CMOS  = 1'b0,
    parameter bit          HAS_PULL_UP     = 1'b0,
    parameter bit          HAS_PULL_DOWN   = 1'b0
) (
    // verilog_format: off
    input  logic             clk_i,
    input  logic             rst_n_i,
    ribp_if.slave            ribp,
    gpio_if.dut              gpio,
    user_gpio_if.padctrl     user_gpio
    // verilog_format: on
);

  logic [PIN_NUM-1:0] s_data_in;
  logic [PIN_NUM-1:0] s_data_out;
  logic [PIN_NUM-1:0] s_output_en;
  logic [PIN_NUM-1:0] s_open_drain;
  logic [PIN_NUM-1:0] s_input_cmos;
  logic [PIN_NUM-1:0] s_pull_up;
  logic [PIN_NUM-1:0] s_pull_down;
  logic [PIN_NUM-1:0] s_alt_en;
  logic [PIN_NUM-1:0] s_alt_sel;
  logic [PIN_NUM-1:0] s_user_sel;
  logic [PIN_NUM-1:0] s_user_handoff;
  logic [PIN_NUM-1:0] s_filter_en;
  logic [       15:0] s_filter_div;
  logic [        3:0] s_filter_count;
  logic [PIN_NUM-1:0] s_intr_rise_en;
  logic [PIN_NUM-1:0] s_intr_fall_en;
  logic [PIN_NUM-1:0] s_intr_high_en;
  logic [PIN_NUM-1:0] s_intr_low_en;
  logic [PIN_NUM-1:0] s_intr_event;
  logic               s_irq;

  gpio_reg #(
      .PIN_NUM        (PIN_NUM),
      .USER_BASE_ADDR (USER_BASE_ADDR),
      .ADMIN_BASE_ADDR(ADMIN_BASE_ADDR),
      .HAS_INPUT_CMOS (HAS_INPUT_CMOS),
      .HAS_PULL_UP    (HAS_PULL_UP),
      .HAS_PULL_DOWN  (HAS_PULL_DOWN)
  ) u_gpio_reg (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .ribp              (ribp),
      .data_in_i         (s_data_in),
      .intr_event_i      (s_intr_event),
      .data_out_o        (s_data_out),
      .output_enable_o   (s_output_en),
      .open_drain_o      (s_open_drain),
      .input_cmos_o      (s_input_cmos),
      .pull_up_o         (s_pull_up),
      .pull_down_o       (s_pull_down),
      .alt_enable_o      (s_alt_en),
      .alt_select_o      (s_alt_sel),
      .user_select_o     (s_user_sel),
      .user_handoff_o    (s_user_handoff),
      .filter_enable_o   (s_filter_en),
      .filter_div_o      (s_filter_div),
      .filter_count_o    (s_filter_count),
      .intr_rise_enable_o(s_intr_rise_en),
      .intr_fall_enable_o(s_intr_fall_en),
      .intr_high_enable_o(s_intr_high_en),
      .intr_low_enable_o (s_intr_low_en),
      .irq_o             (s_irq)
  );

  gpio_core #(
      .PIN_NUM(PIN_NUM)
  ) u_gpio_core (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .data_out_i        (s_data_out),
      .output_enable_i   (s_output_en),
      .open_drain_i      (s_open_drain),
      .input_cmos_i      (s_input_cmos),
      .pull_up_i         (s_pull_up),
      .pull_down_i       (s_pull_down),
      .alt_enable_i      (s_alt_en),
      .alt_select_i      (s_alt_sel),
      .user_select_i     (s_user_sel),
      .user_handoff_i    (s_user_handoff),
      .filter_enable_i   (s_filter_en),
      .filter_div_i      (s_filter_div),
      .filter_count_i    (s_filter_count),
      .intr_rise_enable_i(s_intr_rise_en),
      .intr_fall_enable_i(s_intr_fall_en),
      .intr_high_enable_i(s_intr_high_en),
      .intr_low_enable_i (s_intr_low_en),
      .irq_i             (s_irq),
      .data_in_o         (s_data_in),
      .intr_event_o      (s_intr_event),
      .gpio              (gpio),
      .user_gpio         (user_gpio)
  );

endmodule
