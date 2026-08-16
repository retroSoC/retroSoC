// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module apb4_gpio #(
    parameter int          PinNum        = 32,
    parameter logic [31:0] UserBaseAddr  = 32'h1000_0000,
    parameter logic [31:0] AdminBaseAddr = 32'h1001_4000,
    parameter bit          HasInputCmos  = 1'b0,
    parameter bit          HasPullUp     = 1'b0,
    parameter bit          HasPullDown   = 1'b0
) (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic         clk_i,
    input  logic         rst_n_i,
    apb4_if.slave        apb4,
    gpio_if.dut          gpio,
    user_gpio_if.padctrl user_gpio
    // verilog_format: on
);

  logic [PinNum-1:0] s_data_in;
  logic [PinNum-1:0] s_data_out;
  logic [PinNum-1:0] s_output_en;
  logic [PinNum-1:0] s_open_drain;
  logic [PinNum-1:0] s_input_cmos;
  logic [PinNum-1:0] s_pull_up;
  logic [PinNum-1:0] s_pull_down;
  logic [PinNum-1:0] s_alt_en;
  logic [PinNum-1:0] s_alt_sel;
  logic [PinNum-1:0] s_user_sel;
  logic [PinNum-1:0] s_user_handoff;
  logic [PinNum-1:0] s_filter_en;
  logic [      15:0] s_filter_div;
  logic [       3:0] s_filter_count;
  logic [PinNum-1:0] s_intr_rise_en;
  logic [PinNum-1:0] s_intr_fall_en;
  logic [PinNum-1:0] s_intr_high_en;
  logic [PinNum-1:0] s_intr_low_en;
  logic [PinNum-1:0] s_intr_event;
  logic              s_irq;

  gpio_reg #(
      .PinNum       (PinNum),
      .UserBaseAddr (UserBaseAddr),
      .AdminBaseAddr(AdminBaseAddr),
      .HasInputCmos (HasInputCmos),
      .HasPullUp    (HasPullUp),
      .HasPullDown  (HasPullDown)
  ) u_gpio_reg (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .apb4              (apb4),
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
      .PinNum(PinNum)
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
