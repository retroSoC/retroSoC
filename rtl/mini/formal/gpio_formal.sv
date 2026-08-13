// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module gpio_formal_design (
    // verilog_format: off
    input  logic       clk_i,
    output logic       rst_n_i,
    output logic       f_past_valid,
    output logic       ribp_valid,
    output logic       ribp_ready,
    output logic       ribp_resp_err,
    output logic [31:0] ribp_addr,
    output logic [31:0] ribp_wdata,
    output logic [3:0] ribp_wstrb,
    output logic [3:0] gpio_oe,
    output logic [3:0] gpio_do,
    output logic [3:0] user_oe,
    output logic [3:0] user_do,
    output logic [3:0] user_select,
    output logic [3:0] user_lock,
    output logic [3:0] user_handoff,
    output logic [3:0] user_access,
    output logic [3:0] config_lock,
    output logic [3:0] data_out,
    output logic [3:0] output_enable,
    output logic [3:0] open_drain,
    output logic [3:0] selected_data,
    output logic [3:0] intr_state,
    output logic       irq
    // verilog_format: on
);

  ribp_if ribp ();
  gpio_if #(4) gpio ();
  user_gpio_if #(4) user_gpio ();

  (* anyseq *)logic        f_ribp_valid;
  (* anyseq *)logic [31:0] f_ribp_addr;
  (* anyseq *)logic [31:0] f_ribp_wdata;
  (* anyseq *)logic [ 3:0] f_ribp_wstrb;
  (* anyseq *)logic [ 3:0] f_gpio_di;
  (* anyseq *)logic [ 3:0] f_alt0_do;
  (* anyseq *)logic [ 3:0] f_alt0_oe;
  (* anyseq *)logic [ 3:0] f_alt1_do;
  (* anyseq *)logic [ 3:0] f_alt1_oe;
  (* anyseq *)logic [ 3:0] f_user_do;
  (* anyseq *)logic [ 3:0] f_user_oe;

  assign ribp.valid     = f_ribp_valid;
  assign ribp.addr      = f_ribp_addr;
  assign ribp.wdata     = f_ribp_wdata;
  assign ribp.wstrb     = f_ribp_wstrb;
  assign gpio.di_i      = f_gpio_di;
  assign gpio.alt0_do_i = f_alt0_do;
  assign gpio.alt0_oe_i = f_alt0_oe;
  assign gpio.alt1_do_i = f_alt1_do;
  assign gpio.alt1_oe_i = f_alt1_oe;
  assign user_gpio.do_o = f_user_do;
  assign user_gpio.oe_o = f_user_oe;

  assign ribp_valid     = ribp.valid;
  assign ribp_ready     = ribp.ready;
  assign ribp_resp_err  = ribp.resp_err;
  assign ribp_addr      = ribp.addr;
  assign ribp_wdata     = ribp.wdata;
  assign ribp_wstrb     = ribp.wstrb;
  assign gpio_oe        = gpio.oe_o;
  assign gpio_do        = gpio.do_o;
  assign user_oe        = user_gpio.oe_o;
  assign user_do        = user_gpio.do_o;
  assign user_select    = u_dut.u_gpio_reg.s_user_select_q;
  assign user_lock      = u_dut.u_gpio_reg.s_user_lock_q;
  assign user_handoff   = u_dut.u_gpio_reg.s_user_handoff_q;
  assign user_access    = u_dut.u_gpio_reg.s_user_access_q;
  assign config_lock    = u_dut.u_gpio_reg.s_config_lock_q;
  assign data_out       = u_dut.u_gpio_reg.s_data_out_q;
  assign output_enable  = u_dut.u_gpio_reg.s_output_enable_q;
  assign open_drain     = u_dut.u_gpio_reg.s_open_drain_q;
  assign selected_data  = u_dut.u_gpio_core.s_selected_data;
  assign intr_state     = u_dut.u_gpio_reg.s_intr_state_q;
  assign irq            = gpio.irq_o;

  ribp_gpio #(
      .PinNum       (4),
      .UserBaseAddr (32'h1000_0000),
      .AdminBaseAddr(32'h1001_4000),
      .HasInputCmos (1'b1),
      .HasPullUp    (1'b1),
      .HasPullDown  (1'b1)
  ) u_dut (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .ribp     (ribp),
      .gpio     (gpio),
      .user_gpio(user_gpio)
  );

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
  end

endmodule
