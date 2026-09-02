// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module pll_rcu_controller #(
    parameter int unsigned LockTimeout    = 1024,
    parameter int unsigned QuiesceTimeout = 1024,
    parameter int unsigned LockQualCycles = 4
) (
    // verilog_format: off -- preserve the clock-domain control boundary columns
    input  logic                 sys_clk_i,
    input  logic                 sys_rst_n_i,
    input  logic                 ext_clk_i,
    input  logic                 ext_rst_n_i,
    input  logic                 pll_lock_i,
    input  logic                 pll_capable_i,
    input  logic                 hp_idle_i,
    input  logic                 pclk_idle_i,
    input  logic          [15:0] timeout_i,
    input  logic                 force_safe_i,
    input  logic                 clear_fault_i,
    output logic           [2:0] pll_sel_o,
    output logic                 pll_apply_o,
    output logic                 sel_ext_clk_o,
    output logic                 hp_block_o,
    output logic                 lp_force_ref_o,
    output logic                 pll_fault_o,
    pll_ctrl_if.rcu              pll_ctrl
    // verilog_format: on
);
  typedef enum logic [3:0] {
    Idle,
    Validate,
    Quiesce,
    ParkLp,
    ApplyPll,
    WaitLockLow,
    QualifyLock,
    SwitchPll,
    RestoreLp,
    Respond,
    FailSafe
  } state_e;

  logic   [ 2:0] s_req_sel;
  logic          s_req_valid;
  logic          s_req_ready;
  logic   [ 7:0] s_rsp_data;
  logic          s_rsp_ready;
  logic   [ 7:0] s_rsp_sys_data;
  logic          s_rsp_sys_valid;

  state_e        s_state_d;
  state_e        s_state_q;
  logic   [ 3:0] s_state_bits_q;
  logic   [ 2:0] s_pll_sel_d;
  logic   [ 2:0] s_pll_sel_q;
  logic          s_pll_apply_d;
  logic          s_pll_apply_q;
  logic          s_sel_ext_d;
  logic          s_sel_ext_q;
  logic          s_hp_block_d;
  logic          s_hp_block_q;
  logic          s_lp_force_ref_d;
  logic          s_lp_force_ref_q;
  logic   [15:0] s_timeout_cnt_d;
  logic   [15:0] s_timeout_cnt_q;
  logic   [ 7:0] s_lock_qual_cnt_d;
  logic   [ 7:0] s_lock_qual_cnt_q;
  logic   [ 2:0] s_active_sel_d;
  logic   [ 2:0] s_active_sel_q;
  logic          s_active_valid_d;
  logic          s_active_valid_q;
  logic          s_safe_clk_d;
  logic          s_safe_clk_q;
  logic          s_lock_d;
  logic          s_lock_q;
  logic   [ 1:0] s_err_d;
  logic   [ 1:0] s_err_q;
  logic          s_fault_sticky_d;
  logic          s_fault_sticky_q;
  logic          s_rsp_valid_d;
  logic          s_rsp_valid_q;
  logic   [15:0] s_timeout_limit;

  assign s_state_q = state_e'(s_state_bits_q);

  cdc_2phase #(
      .DATA_WIDTH(3)
  ) u_pll_req_cdc (
      .src_clk_i  (sys_clk_i),
      .src_rst_n_i(sys_rst_n_i),
      .src_data_i (pll_ctrl.req_sel_o),
      .src_valid_i(pll_ctrl.req_valid_o),
      .src_ready_o(pll_ctrl.req_ready_i),
      .dst_clk_i  (ext_clk_i),
      .dst_rst_n_i(ext_rst_n_i),
      .dst_data_o (s_req_sel),
      .dst_valid_o(s_req_valid),
      .dst_ready_i(s_req_ready)
  );

  cdc_2phase #(
      .DATA_WIDTH(8)
  ) u_pll_rsp_cdc (
      .src_clk_i  (ext_clk_i),
      .src_rst_n_i(ext_rst_n_i),
      .src_data_i (s_rsp_data),
      .src_valid_i(s_rsp_valid_q),
      .src_ready_o(s_rsp_ready),
      .dst_clk_i  (sys_clk_i),
      .dst_rst_n_i(sys_rst_n_i),
      .dst_data_o (s_rsp_sys_data),
      .dst_valid_o(s_rsp_sys_valid),
      .dst_ready_i(pll_ctrl.rsp_ready_o)
  );

  assign pll_ctrl.rsp_active_sel_i = s_rsp_sys_data[2:0];
  assign pll_ctrl.rsp_active_valid_i = s_rsp_sys_data[3];
  assign pll_ctrl.rsp_safe_clk_i = s_rsp_sys_data[4];
  assign pll_ctrl.rsp_pll_lock_i = s_rsp_sys_data[5];
  assign pll_ctrl.rsp_error_i = s_rsp_sys_data[7:6];
  assign pll_ctrl.rsp_valid_i = s_rsp_sys_valid;
  assign pll_ctrl.capable_i = pll_capable_i;
  assign s_req_ready = s_state_q == Idle;
  assign s_rsp_data = {s_err_q, s_lock_q, s_safe_clk_q, s_active_valid_q, s_active_sel_q};
  assign pll_sel_o = s_pll_sel_q;
  assign pll_apply_o = s_pll_apply_q;
  assign sel_ext_clk_o = s_sel_ext_q;
  assign hp_block_o = s_hp_block_q;
  assign lp_force_ref_o = s_lp_force_ref_q;
  assign pll_fault_o = s_fault_sticky_q;
  assign s_timeout_limit = (timeout_i < 16'd2) ? 16'd2 : timeout_i;

  always_comb begin
    s_state_d         = s_state_q;
    s_pll_sel_d       = s_pll_sel_q;
    s_pll_apply_d     = 1'b0;
    s_sel_ext_d       = s_sel_ext_q;
    s_hp_block_d      = s_hp_block_q;
    s_lp_force_ref_d  = s_lp_force_ref_q;
    s_timeout_cnt_d   = s_timeout_cnt_q;
    s_lock_qual_cnt_d = s_lock_qual_cnt_q;
    s_active_sel_d    = s_active_sel_q;
    s_active_valid_d  = s_active_valid_q;
    s_safe_clk_d      = s_safe_clk_q;
    s_lock_d          = s_lock_q;
    s_err_d           = s_err_q;
    s_fault_sticky_d  = s_fault_sticky_q;
    s_rsp_valid_d     = s_rsp_valid_q;

    if (clear_fault_i) begin
      s_fault_sticky_d = 1'b0;
    end

    unique case (s_state_q)
      Idle: begin
        s_hp_block_d    = 1'b0;
        s_rsp_valid_d   = 1'b0;
        s_timeout_cnt_d = '0;
        if (force_safe_i) begin
          s_err_d   = 2'd0;
          s_state_d = FailSafe;
        end else if (s_active_valid_q && !pll_lock_i) begin
          s_err_d          = 2'd3;
          s_fault_sticky_d = 1'b1;
          s_state_d        = FailSafe;
        end else if (s_req_valid) begin
          s_pll_sel_d = s_req_sel;
          s_err_d     = 2'd0;
          s_state_d   = Validate;
        end
      end
      Validate: begin
        if (!pll_capable_i) begin
          s_err_d          = 2'd1;
          s_fault_sticky_d = 1'b1;
          s_state_d        = FailSafe;
        end else begin
          s_hp_block_d    = 1'b1;
          s_timeout_cnt_d = '0;
          s_state_d       = Quiesce;
        end
      end
      Quiesce: begin
        if (hp_idle_i && pclk_idle_i) begin
          s_timeout_cnt_d = '0;
          s_state_d       = ParkLp;
        end else if (s_timeout_cnt_q == s_timeout_limit - 1'b1) begin
          s_err_d          = 2'd2;
          s_fault_sticky_d = 1'b1;
          s_state_d        = FailSafe;
        end else begin
          s_timeout_cnt_d = s_timeout_cnt_q + 1'b1;
        end
      end
      ParkLp: begin
        s_lp_force_ref_d = 1'b1;
        s_sel_ext_d      = 1'b1;
        s_safe_clk_d     = 1'b1;
        s_active_valid_d = 1'b0;
        s_lock_d         = 1'b0;
        s_state_d        = ApplyPll;
      end
      ApplyPll: begin
        s_pll_apply_d     = 1'b1;
        s_timeout_cnt_d   = '0;
        s_lock_qual_cnt_d = '0;
        s_state_d         = WaitLockLow;
      end
      WaitLockLow: begin
        if (!pll_lock_i) begin
          s_timeout_cnt_d = '0;
          s_state_d       = QualifyLock;
        end else if (s_timeout_cnt_q == s_timeout_limit - 1'b1) begin
          s_err_d          = 2'd2;
          s_fault_sticky_d = 1'b1;
          s_state_d        = FailSafe;
        end else begin
          s_timeout_cnt_d = s_timeout_cnt_q + 1'b1;
        end
      end
      QualifyLock: begin
        if (!pll_lock_i) begin
          s_lock_qual_cnt_d = '0;
        end else if (s_lock_qual_cnt_q == 8'(LockQualCycles - 1)) begin
          s_lock_d         = 1'b1;
          s_active_sel_d   = s_pll_sel_q;
          s_active_valid_d = 1'b1;
          s_state_d        = SwitchPll;
        end else begin
          s_lock_qual_cnt_d = s_lock_qual_cnt_q + 1'b1;
        end
        if (s_timeout_cnt_q == s_timeout_limit - 1'b1) begin
          s_err_d          = 2'd2;
          s_fault_sticky_d = 1'b1;
          s_state_d        = FailSafe;
        end else begin
          s_timeout_cnt_d = s_timeout_cnt_q + 1'b1;
        end
      end
      SwitchPll: begin
        s_sel_ext_d  = 1'b0;
        s_safe_clk_d = 1'b0;
        s_state_d    = RestoreLp;
      end
      RestoreLp: begin
        s_lp_force_ref_d = 1'b0;
        s_err_d          = 2'd0;
        s_state_d        = Respond;
      end
      Respond: begin
        s_rsp_valid_d = 1'b1;
        if (s_rsp_valid_q && s_rsp_ready) begin
          s_rsp_valid_d = 1'b0;
          s_state_d     = Idle;
        end
      end
      FailSafe: begin
        s_sel_ext_d      = 1'b1;
        s_lp_force_ref_d = 1'b1;
        s_safe_clk_d     = 1'b1;
        s_lock_d         = 1'b0;
        s_active_valid_d = 1'b0;
        s_state_d        = Respond;
      end
      default: begin
        s_sel_ext_d      = 1'b1;
        s_lp_force_ref_d = 1'b1;
        s_safe_clk_d     = 1'b1;
        s_state_d        = FailSafe;
      end
    endcase
  end

  dffrc #(
      .DATA_WIDTH(4),
      .RESET_VAL (Idle)
  ) u_state_dffrc (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_pll_sel_dffr (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_pll_sel_d),
      .dat_o  (s_pll_sel_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_pll_apply_dffr (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_pll_apply_d),
      .dat_o  (s_pll_apply_q)
  );
  dffrc #(
      .DATA_WIDTH(1),
      .RESET_VAL (1'b1)
  ) u_sel_ext_dffrc (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_sel_ext_d),
      .dat_o  (s_sel_ext_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_hp_block_dffr (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_hp_block_d),
      .dat_o  (s_hp_block_q)
  );
  dffrc #(
      .DATA_WIDTH(1),
      .RESET_VAL (1'b1)
  ) u_lp_force_ref_dffrc (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_lp_force_ref_d),
      .dat_o  (s_lp_force_ref_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_timeout_cnt_dffr (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_timeout_cnt_d),
      .dat_o  (s_timeout_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_lock_qual_cnt_dffr (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_lock_qual_cnt_d),
      .dat_o  (s_lock_qual_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_active_sel_dffr (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_active_sel_d),
      .dat_o  (s_active_sel_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_active_valid_dffr (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_active_valid_d),
      .dat_o  (s_active_valid_q)
  );
  dffrc #(
      .DATA_WIDTH(1),
      .RESET_VAL (1'b1)
  ) u_safe_clk_dffrc (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_safe_clk_d),
      .dat_o  (s_safe_clk_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_lock_dffr (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_lock_d),
      .dat_o  (s_lock_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_err_dffr (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_fault_sticky_dffr (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_fault_sticky_d),
      .dat_o  (s_fault_sticky_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rsp_valid_dffr (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_rsp_valid_d),
      .dat_o  (s_rsp_valid_q)
  );

`ifndef SYNTHESIS
  initial begin
    if ((LockTimeout < 2) || (QuiesceTimeout < 2) || (LockQualCycles < 2) ||
        (LockQualCycles > 255)) begin
      $fatal(1, "pll_rcu_controller: invalid timeout or qualification parameter");
    end
  end
`endif
endmodule
