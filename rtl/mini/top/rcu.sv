// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module rcu #(
    parameter int ExtClkHz        = 72_000_000,
    parameter int ClintTimebaseHz = 1_000_000
) (
    input  logic           ext_clk_i,
    input  logic           aud_clk_i,
    input  logic           ext_rst_n_i,
    input  logic           wdg_reset_req_i,
`ifdef HAVE_PLL
    input  logic           xtal_clk_i,
`endif
           pll_ctrl_if.rcu pll_ctrl,
    output logic           sys_clk_o,
    output logic           sys_rst_n_o,
    output logic           aud_rst_n_o,
    output logic           sys_clkdiv4_o,
    output logic           timebase_tick_o
);
  logic s_ext_clk_buf;
  logic s_aud_clk_buf;
  logic s_sys_clk;
  logic s_ext_rst_n_sync;
  logic s_sys_rst_n_sync;
  logic s_aud_rst_n_sync;
  logic s_sys_reset_source_n;
  logic [3:0] s_div_cnt_d, s_div_cnt_q;
  logic s_sys_clkdiv4_d, s_sys_clkdiv4_q;

  tc_clk_buf u_ext_clk_buf (
      .clk_i(ext_clk_i),
      .clk_o(s_ext_clk_buf)
  );
  tc_clk_buf u_aud_clk_buf (
      .clk_i(aud_clk_i),
      .clk_o(s_aud_clk_buf)
  );

  rst_sync #(
      .STAGE(5)
  ) u_ext_rst_sync (
      .clk_i  (s_ext_clk_buf),
      .rst_n_i(ext_rst_n_i),
      .rst_n_o(s_ext_rst_n_sync)
  );

`ifdef HAVE_PLL
  logic       s_xtal_clk_buf;
  logic       s_pll_clk;
  logic       s_pll_clk_buf;
  logic       s_pll_lock;
  logic       s_pll_capable;
  logic [2:0] s_pll_sel;
  logic       s_pll_apply;
  logic [2:0] s_pll_cfg_sel;
  logic       s_pll_cfg_valid;
  logic       s_pll_cfg_ready;
  logic       s_pll_cfg_req;
  logic s_pll_cfg_sent_d, s_pll_cfg_sent_q;
  logic s_sel_ext_clk;

  tc_clk_buf u_xtal_buf (
      .clk_i(xtal_clk_i),
      .clk_o(s_xtal_clk_buf)
  );
  // ext_clk_i and the PLL reference clock are unrelated. A pulse generated
  // by the controller must cross this boundary through a handshake.
  cdc_2phase #(
      .DATA_WIDTH(3)
  ) u_pll_config_cdc (
      .src_clk_i  (s_ext_clk_buf),
      .src_rst_n_i(s_ext_rst_n_sync),
      .src_data_i (s_pll_sel),
      .src_valid_i(s_pll_cfg_req),
      .src_ready_o(s_pll_cfg_ready),
      .dst_clk_i  (s_xtal_clk_buf),
      .dst_rst_n_i(s_ext_rst_n_sync),
      .dst_data_o (s_pll_cfg_sel),
      .dst_valid_o(s_pll_cfg_valid),
      .dst_ready_i(1'b1)
  );
  assign s_pll_cfg_req = s_pll_apply && ~s_pll_cfg_sent_q;
  always_comb begin
    s_pll_cfg_sent_d = s_pll_cfg_sent_q;
    if (!s_pll_apply) begin
      s_pll_cfg_sent_d = 1'b0;
    end else if (s_pll_cfg_req && s_pll_cfg_ready) begin
      s_pll_cfg_sent_d = 1'b1;
    end
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_pll_cfg_sent_dffr (
      .clk_i  (s_ext_clk_buf),
      .rst_n_i(s_ext_rst_n_sync),
      .dat_i  (s_pll_cfg_sent_d),
      .dat_o  (s_pll_cfg_sent_q)
  );
  tc_pll u_tc_pll (
      .fref_i       (s_xtal_clk_buf),
      .rst_n_i      (s_ext_rst_n_sync),
      .cfg_sel_i    (s_pll_cfg_sel),
      .cfg_apply_i  (s_pll_cfg_valid),
      .pll_capable_o(s_pll_capable),
      .pll_lock_o   (s_pll_lock),
      .pll_clk_o    (s_pll_clk)
  );
  tc_clk_buf u_pll_clk_buf (
      .clk_i(s_pll_clk),
      .clk_o(s_pll_clk_buf)
  );
  tc_clk_switch2 u_sys_clk_switch (
      .clk0_i   (s_pll_clk_buf),
      .clk1_i   (s_ext_clk_buf),
      .clk_sel_i(s_sel_ext_clk),
      .clk_o    (s_sys_clk)
  );

  pll_rcu_controller u_pll_rcu_controller (
      .sys_clk_i       (s_sys_clk),
      .sys_rst_n_i     (s_sys_rst_n_sync),
      .ext_clk_i       (s_ext_clk_buf),
      .ext_rst_n_i     (s_ext_rst_n_sync),
      .pll_lock_i      (s_pll_lock),
      .pll_capable_i   (s_pll_capable),
      .pll_sel_o       (s_pll_sel),
      .pll_apply_o     (s_pll_apply),
      .select_ext_clk_o(s_sel_ext_clk),
      .pll_ctrl        (pll_ctrl)
  );
`else
  logic s_no_pll_rsp_valid_d, s_no_pll_rsp_valid_q;

  assign s_sys_clk                   = s_ext_clk_buf;
  assign pll_ctrl.req_ready_i        = ~s_no_pll_rsp_valid_q;
  assign pll_ctrl.rsp_active_sel_i   = '0;
  assign pll_ctrl.rsp_active_valid_i = 1'b0;
  assign pll_ctrl.rsp_safe_clk_i     = 1'b1;
  assign pll_ctrl.rsp_pll_lock_i     = 1'b0;
  assign pll_ctrl.rsp_error_i        = 2'd1;
  assign pll_ctrl.rsp_valid_i        = s_no_pll_rsp_valid_q;
  assign pll_ctrl.capable_i          = 1'b0;

  always_comb begin
    s_no_pll_rsp_valid_d = s_no_pll_rsp_valid_q;
    if (pll_ctrl.req_valid_o && pll_ctrl.req_ready_i) begin
      s_no_pll_rsp_valid_d = 1'b1;
    end
    if (s_no_pll_rsp_valid_q && pll_ctrl.rsp_ready_o) begin
      s_no_pll_rsp_valid_d = 1'b0;
    end
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_no_pll_rsp_valid_dffr (
      .clk_i  (s_ext_clk_buf),
      .rst_n_i(s_ext_rst_n_sync),
      .dat_i  (s_no_pll_rsp_valid_d),
      .dat_o  (s_no_pll_rsp_valid_q)
  );
`endif

  tc_clk_buf u_sys_clk_buf (
      .clk_i(s_sys_clk),
      .clk_o(sys_clk_o)
  );

  rst_sync #(
      .STAGE(5)
  ) u_sys_rst_sync (
      .clk_i  (sys_clk_o),
      .rst_n_i(s_sys_reset_source_n),
      .rst_n_o(s_sys_rst_n_sync)
  );
  rst_sync #(
      .STAGE(5)
  ) u_aud_rst_sync (
      .clk_i  (s_aud_clk_buf),
      .rst_n_i(ext_rst_n_i),
      .rst_n_o(s_aud_rst_n_sync)
  );

  assign sys_rst_n_o          = s_sys_rst_n_sync;
  assign aud_rst_n_o          = s_aud_rst_n_sync;
  assign sys_clkdiv4_o        = s_sys_clkdiv4_q;
  assign s_sys_reset_source_n = ext_rst_n_i && !wdg_reset_req_i;

  clint_timebase #(
      .RefClkHz  (ExtClkHz),
      .TimebaseHz(ClintTimebaseHz)
  ) u_clint_timebase (
      .ref_clk_i  (s_ext_clk_buf),
      .ref_rst_n_i(s_ext_rst_n_sync),
      .sys_clk_i  (sys_clk_o),
      .sys_rst_n_i(sys_rst_n_o),
      .tick_o     (timebase_tick_o)
  );

  assign s_div_cnt_d = (s_div_cnt_q == 4'd1) ? '0 : s_div_cnt_q + 1'b1;
  dffr #(
      .DATA_WIDTH(4)
  ) u_div_cnt_dffr (
      .clk_i  (sys_clk_o),
      .rst_n_i(sys_rst_n_o),
      .dat_i  (s_div_cnt_d),
      .dat_o  (s_div_cnt_q)
  );
  assign s_sys_clkdiv4_d = (s_div_cnt_q == 4'd1) ? ~s_sys_clkdiv4_q : s_sys_clkdiv4_q;
  dffr #(
      .DATA_WIDTH(1)
  ) u_sys_clkdiv4_dffr (
      .clk_i  (sys_clk_o),
      .rst_n_i(sys_rst_n_o),
      .dat_i  (s_sys_clkdiv4_d),
      .dat_o  (s_sys_clkdiv4_q)
  );
endmodule
