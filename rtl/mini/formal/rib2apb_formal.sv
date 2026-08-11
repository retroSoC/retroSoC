// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
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


module rib2apb_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        rib_cmd_valid,
    output logic [31:0] rib_cmd_addr,
    output logic        rib_cmd_write,
    output logic [ 1:0] rib_cmd_len,
    output logic        rib_cmd_ready,
    output logic        rib_w_valid,
    output logic [31:0] rib_wdata,
    output logic [ 3:0] rib_wstrb,
    output logic        rib_wlast,
    output logic        rib_w_ready,
    output logic        rib_rsp_valid,
    output logic [31:0] rib_rdata,
    output logic        rib_resp_err,
    output logic [ 2:0] rib_resp_code,
    output logic [ 1:0] rib_rsp_beat,
    output logic        rib_rsp_last,
    output logic        rib_rsp_ready,
    output logic [ 7:0] psel_comb,
    output logic [ 7:0] psel_q,
    output logic        xfer_ready,
    output logic        xfer_error,
    output logic        rsp_input_valid,
    output logic        rsp_input_ready,
    output logic [38:0] rsp_input_data,
    output logic [ 2:0] fsm_q
);

  rib_if rib ();
  apb4_pure_if archinfo ();
  apb4_pure_if rng ();
  apb4_pure_if pwm ();
  apb4_pure_if ps2 ();
  apb4_pure_if rtc ();
  apb4_pure_if wdg ();
  apb4_pure_if crc ();
  apb4_pure_if user_ip ();

  (* anyseq *)logic        f_rib_cmd_valid;
  (* anyseq *)logic [31:0] f_rib_cmd_addr;
  (* anyseq *)logic        f_rib_cmd_write;
  (* anyseq *)logic [ 1:0] f_rib_cmd_len;
  (* anyseq *)logic        f_rib_w_valid;
  (* anyseq *)logic [31:0] f_rib_wdata;
  (* anyseq *)logic [ 3:0] f_rib_wstrb;
  (* anyseq *)logic        f_rib_wlast;
  (* anyseq *)logic        f_rib_rsp_ready;

  assign rib.cmd_valid = f_rib_cmd_valid;
  assign rib.cmd_addr  = f_rib_cmd_addr;
  assign rib.cmd_write = f_rib_cmd_write;
  assign rib.cmd_len   = f_rib_cmd_len;
  assign rib.w_valid   = f_rib_w_valid;
  assign rib.wdata     = f_rib_wdata;
  assign rib.wstrb     = f_rib_wstrb;
  assign rib.wlast     = f_rib_wlast;
  assign rib.rsp_ready = f_rib_rsp_ready;

  assign rib_cmd_valid = rib.cmd_valid;
  assign rib_cmd_addr  = rib.cmd_addr;
  assign rib_cmd_write = rib.cmd_write;
  assign rib_cmd_len   = rib.cmd_len;
  assign rib_cmd_ready = rib.cmd_ready;
  assign rib_w_valid   = rib.w_valid;
  assign rib_wdata     = rib.wdata;
  assign rib_wstrb     = rib.wstrb;
  assign rib_wlast     = rib.wlast;
  assign rib_w_ready   = rib.w_ready;
  assign rib_rsp_valid = rib.rsp_valid;
  assign rib_rdata     = rib.rdata;
  assign rib_resp_err  = rib.resp_err;
  assign rib_resp_code = rib.resp_code;
  assign rib_rsp_beat  = rib.rsp_beat;
  assign rib_rsp_last  = rib.rsp_last;
  assign rib_rsp_ready = rib.rsp_ready;

  formal_apb_slave u_archinfo_slave (.apb(archinfo));
  formal_apb_slave u_rng_slave (.apb(rng));
  formal_apb_slave u_pwm_slave (.apb(pwm));
  formal_apb_slave u_ps2_slave (.apb(ps2));
  formal_apb_slave u_rtc_slave (.apb(rtc));
  formal_apb_slave u_wdg_slave (.apb(wdg));
  formal_apb_slave u_crc_slave (.apb(crc));
  formal_apb_slave u_user_ip_slave (.apb(user_ip));

  rib2apb u_dut (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .rib     (rib),
      .archinfo(archinfo),
      .rng     (rng),
      .pwm     (pwm),
      .ps2     (ps2),
      .rtc     (rtc),
      .wdg     (wdg),
      .crc     (crc),
      .user_ip (user_ip)
  );

  assign psel_comb       = u_dut.s_psel_comb;
  assign psel_q          = u_dut.s_psel_q;
  assign xfer_ready      = u_dut.s_xfer_ready;
  assign xfer_error      = u_dut.s_xfer_error;
  assign rsp_input_valid = u_dut.s_rsp_input_valid;
  assign rsp_input_ready = u_dut.s_rsp_input_ready;
  assign rsp_input_data  = u_dut.s_rsp_input_data;
  assign fsm_q           = u_dut.s_fsm_q;

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
  end

endmodule
