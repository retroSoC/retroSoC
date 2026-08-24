// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

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

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  gpio_if #(4) gpio ();
  user_gpio_if #(4) user_gpio ();

  (* anyseq *)logic        f_apb_sel;
  (* anyseq *)logic [31:0] f_apb_addr;
  (* anyseq *)logic [31:0] f_apb_wdata;
  (* anyseq *)logic [ 3:0] f_apb_pstrb;
  (* anyseq *)logic [ 3:0] f_gpio_di;
  (* anyseq *)logic [ 3:0] f_alt0_do;
  (* anyseq *)logic [ 3:0] f_alt0_oe;
  (* anyseq *)logic [ 3:0] f_alt1_do;
  (* anyseq *)logic [ 3:0] f_alt1_oe;
  (* anyseq *)logic [ 3:0] f_user_do;
  (* anyseq *)logic [ 3:0] f_user_oe;

  assign apb4.psel      = f_apb_sel;
  assign apb4.penable   = f_apb_sel;
  assign apb4.pwrite    = |f_apb_pstrb;
  assign apb4.paddr     = f_apb_addr;
  assign apb4.pwdata    = f_apb_wdata;
  assign apb4.pstrb     = f_apb_pstrb;
  assign apb4.pprot     = 3'b000;
  assign gpio.di_i      = f_gpio_di;
  assign gpio.alt0_do_i = f_alt0_do;
  assign gpio.alt0_oe_i = f_alt0_oe;
  assign gpio.alt1_do_i = f_alt1_do;
  assign gpio.alt1_oe_i = f_alt1_oe;
  assign user_gpio.do_o = f_user_do;
  assign user_gpio.oe_o = f_user_oe;

  assign ribp_valid     = apb4.psel;
  assign ribp_ready     = apb4.pready;
  assign ribp_resp_err  = apb4.pslverr;
  assign ribp_addr      = apb4.paddr;
  assign ribp_wdata     = apb4.pwdata;
  assign ribp_wstrb     = apb4.pstrb;
  assign gpio_oe        = gpio.oe_o;
  assign gpio_do        = gpio.do_o;
  assign user_oe        = user_gpio.oe_o;
  assign user_do        = user_gpio.do_o;
  assign user_select    = u_dut.u_gpio_reg.s_user_sel_q;
  assign user_lock      = u_dut.u_gpio_reg.s_user_lock_q;
  assign user_handoff   = u_dut.u_gpio_reg.s_user_handoff_q;
  assign user_access    = u_dut.u_gpio_reg.s_user_access_q;
  assign config_lock    = u_dut.u_gpio_reg.s_config_lock_q;
  assign data_out       = u_dut.u_gpio_reg.s_data_out_q;
  assign output_enable  = u_dut.u_gpio_reg.s_output_en_q;
  assign open_drain     = u_dut.u_gpio_reg.s_open_drain_q;
  assign selected_data  = u_dut.u_gpio_core.s_selected_data;
  assign intr_state     = u_dut.u_gpio_reg.s_intr_state_q;
  assign irq            = gpio.irq_o;

  apb4_gpio #(
      .PinNum       (4),
      .UserBaseAddr (32'h1000_0000),
      .AdminBaseAddr(32'h1001_4000),
      .HasInputCmos (1'b1),
      .HasPullUp    (1'b1),
      .HasPullDown  (1'b1)
  ) u_dut (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .apb4     (apb4),
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
