// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module pll_rcu_formal_design (
    input  logic       clk_i,
    output logic       rst_n_i,
    output logic       f_past_valid,
    output logic       req_valid,
    output logic [2:0] req_sel,
    output logic       req_ready,
    output logic       rsp_valid,
    output logic       rsp_ready,
    output logic       pll_lock,
    output logic       pll_capable,
    output logic [2:0] state,
    output logic       pll_apply,
    output logic       select_ext_clk,
    output logic       active_valid,
    output logic       safe_clk,
    output logic       active_lock,
    output logic [1:0] error
);

  pll_ctrl_if pll_ctrl ();

  (* anyseq *)logic       f_req_valid;
  (* anyseq *)logic [2:0] f_req_sel;
  (* anyseq *)logic       f_rsp_ready;
  (* anyseq *)logic       f_pll_lock;
  (* anyseq *)logic       f_pll_capable;

  assign pll_ctrl.req_valid_o = f_req_valid;
  assign pll_ctrl.req_sel_o   = f_req_sel;
  assign pll_ctrl.rsp_ready_o = f_rsp_ready;
  assign req_valid            = pll_ctrl.req_valid_o;
  assign req_sel              = pll_ctrl.req_sel_o;
  assign req_ready            = pll_ctrl.req_ready_i;
  assign rsp_valid            = pll_ctrl.rsp_valid_i;
  assign rsp_ready            = pll_ctrl.rsp_ready_o;
  assign pll_lock             = f_pll_lock;
  assign pll_capable          = f_pll_capable;
  assign state                = u_dut.s_state_q;
  assign pll_apply            = u_dut.s_pll_apply_q;
  assign select_ext_clk       = u_dut.s_select_ext_clk_q;
  assign active_valid         = u_dut.s_active_valid_q;
  assign safe_clk             = u_dut.s_safe_clk_q;
  assign active_lock          = u_dut.s_lock_q;
  assign error                = u_dut.s_error_q;

  // Both controller domains share the formal clock. This proves the control
  // FSM and the production cdc_2phase composition, not asynchronous CDC timing.
  pll_rcu_controller #(
      .LOCK_TIMEOUT(4)
  ) u_dut (
      .sys_clk_i       (clk_i),
      .sys_rst_n_i     (rst_n_i),
      .ext_clk_i       (clk_i),
      .ext_rst_n_i     (rst_n_i),
      .pll_lock_i      (f_pll_lock),
      .pll_capable_i   (f_pll_capable),
      .pll_sel_o       (),
      .pll_apply_o     (),
      .select_ext_clk_o(),
      .pll_ctrl        (pll_ctrl)
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
