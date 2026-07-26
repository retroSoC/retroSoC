// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module gpio_user_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        nmi_valid,
    output logic [31:0] nmi_addr,
    output logic [31:0] nmi_wdata,
    output logic [ 3:0] nmi_wstrb,
    output logic        nmi_ready,
    output logic [31:0] gpio_di,
    output logic [31:0] gpio_oe,
    output logic [31:0] gpio_do,
    output logic [31:0] user_di,
    output logic [31:0] user_oe,
    output logic [31:0] user_do,
    output logic [31:0] user_sel,
    output logic [31:0] user_lock,
    output logic [31:0] user_handoff,
    output logic [31:0] user_status,
    output logic [31:0] native_oe,
    output logic [31:0] native_do
);

  nmi_if nmi ();
  gpio_if gpio ();
  user_gpio_if user_gpio ();

  (* anyseq *)logic        f_nmi_valid;
  (* anyseq *)logic [31:0] f_nmi_addr;
  (* anyseq *)logic [31:0] f_nmi_wdata;
  (* anyseq *)logic [ 3:0] f_nmi_wstrb;
  (* anyseq *)logic [31:0] f_gpio_di;
  (* anyseq *)logic [31:0] f_alt0_do;
  (* anyseq *)logic [31:0] f_alt0_oe;
  (* anyseq *)logic [31:0] f_alt1_do;
  (* anyseq *)logic [31:0] f_alt1_oe;
  (* anyseq *)logic [31:0] f_user_do;
  (* anyseq *)logic [31:0] f_user_oe;

  assign nmi.valid      = f_nmi_valid;
  assign nmi.addr       = f_nmi_addr;
  assign nmi.wdata      = f_nmi_wdata;
  assign nmi.wstrb      = f_nmi_wstrb;
  assign gpio.di_i      = f_gpio_di;
  assign gpio.alt0_do_i = f_alt0_do;
  assign gpio.alt0_oe_i = f_alt0_oe;
  assign gpio.alt1_do_i = f_alt1_do;
  assign gpio.alt1_oe_i = f_alt1_oe;
  assign user_gpio.do_o = f_user_do;
  assign user_gpio.oe_o = f_user_oe;

  assign nmi_valid      = nmi.valid;
  assign nmi_addr       = nmi.addr;
  assign nmi_wdata      = nmi.wdata;
  assign nmi_wstrb      = nmi.wstrb;
  assign nmi_ready      = nmi.ready;
  assign gpio_di        = gpio.di_i;
  assign gpio_oe        = gpio.oe_o;
  assign gpio_do        = gpio.do_o;
  assign user_di        = user_gpio.di_i;
  assign user_oe        = user_gpio.oe_o;
  assign user_do        = user_gpio.do_o;
  assign user_sel       = u_dut.s_gpio_user_sel_q;
  assign user_lock      = u_dut.s_gpio_user_lock_q;
  assign user_handoff   = u_dut.s_gpio_user_handoff_q;
  assign user_status    = u_dut.s_gpio_user_status;
  assign native_oe      = u_dut.s_gpio_native_oe;
  assign native_do      = u_dut.s_gpio_native_out;

  nmi_gpio u_dut (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .nmi      (nmi),
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
