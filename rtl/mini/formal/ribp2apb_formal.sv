// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module formal_apb_slave (
    apb4_pure_if.slave apb
);

  (* anyseq *)logic        f_ready;
  (* anyseq *)logic [31:0] f_rdata;
  (* anyseq *)logic        f_slverr;

  assign apb.pready  = f_ready;
  assign apb.prdata  = f_rdata;
  assign apb.pslverr = f_slverr;

endmodule

module ribp2apb_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        rib_valid,
    output logic [31:0] rib_addr,
    output logic [31:0] rib_wdata,
    output logic [ 3:0] rib_wstrb,
    output logic        rib_ready,
    output logic [ 9:0] psel_comb,
    output logic [ 9:0] psel_q,
    output logic        xfer_ready,
    output logic [ 1:0] fsm_q
);

  ribp_if rib ();
  apb4_pure_if archinfo ();
  apb4_pure_if rng ();
  apb4_pure_if uart ();
  apb4_pure_if pwm ();
  apb4_pure_if ps2 ();
  apb4_pure_if rtc ();
  apb4_pure_if wdg ();
  apb4_pure_if crc ();
  apb4_pure_if tmr ();
  apb4_pure_if user_ip ();

  (* anyseq *)logic        f_rib_valid;
  (* anyseq *)logic [31:0] f_rib_addr;
  (* anyseq *)logic [31:0] f_rib_wdata;
  (* anyseq *)logic [ 3:0] f_rib_wstrb;

  assign rib.valid = f_rib_valid;
  assign rib.addr  = f_rib_addr;
  assign rib.wdata = f_rib_wdata;
  assign rib.wstrb = f_rib_wstrb;
  assign rib_valid = rib.valid;
  assign rib_addr  = rib.addr;
  assign rib_wdata = rib.wdata;
  assign rib_wstrb = rib.wstrb;
  assign rib_ready = rib.ready;

  formal_apb_slave u_archinfo_slave (.apb(archinfo));
  formal_apb_slave u_rng_slave (.apb(rng));
  formal_apb_slave u_uart_slave (.apb(uart));
  formal_apb_slave u_pwm_slave (.apb(pwm));
  formal_apb_slave u_ps2_slave (.apb(ps2));
  formal_apb_slave u_rtc_slave (.apb(rtc));
  formal_apb_slave u_wdg_slave (.apb(wdg));
  formal_apb_slave u_crc_slave (.apb(crc));
  formal_apb_slave u_tmr_slave (.apb(tmr));
  formal_apb_slave u_user_ip_slave (.apb(user_ip));

  ribp2apb u_dut (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .ribp    (rib),
      .archinfo(archinfo),
      .rng     (rng),
      .uart    (uart),
      .pwm     (pwm),
      .ps2     (ps2),
      .rtc     (rtc),
      .wdg     (wdg),
      .crc     (crc),
      .tmr     (tmr),
      .user_ip (user_ip)
  );

  assign psel_comb  = u_dut.s_psel_comb;
  assign psel_q     = u_dut.s_psel_q;
  assign xfer_ready = u_dut.s_xfer_ready;
  assign fsm_q      = u_dut.s_fsm_q;

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
  end

endmodule
