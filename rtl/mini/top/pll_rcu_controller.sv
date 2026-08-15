// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module pll_rcu_controller #(
    parameter int LockTimeout = 1024
) (
    // verilog_format: off -- preserve aligned port declarations 
    input  logic                 sys_clk_i,
    input  logic                 sys_rst_n_i,
    input  logic                 ext_clk_i,
    input  logic                 ext_rst_n_i,
    input  logic                 pll_lock_i,
    input  logic                 pll_capable_i,
    output logic           [2:0] pll_sel_o,
    output logic                 pll_apply_o,
    output logic                 select_ext_clk_o,
    pll_ctrl_if.rcu              pll_ctrl
    // verilog_format: on
);
  localparam logic [2:0] PLL_IDLE = 3'd0;
  localparam logic [2:0] PLL_SAFE = 3'd1;
  localparam logic [2:0] PLL_APPLY = 3'd2;
  localparam logic [2:0] PLL_WAIT_LOCK = 3'd3;
  localparam logic [2:0] PLL_SWITCH = 3'd4;
  localparam logic [2:0] PLL_RESPOND = 3'd5;

  logic [2:0] s_req_sel;
  logic s_req_valid, s_req_ready;
  logic [7:0] s_rsp_data;
  logic s_rsp_valid, s_rsp_ready;
  logic [7:0] s_rsp_sys_data;
  logic       s_rsp_sys_valid;
  logic [2:0] s_state_d, s_state_q;
  logic [2:0] s_pll_sel_d, s_pll_sel_q;
  logic s_pll_apply_d, s_pll_apply_q;
  logic s_sel_ext_clk_d, s_sel_ext_clk_q;
  logic [15:0] s_lock_count_d, s_lock_count_q;
  logic [2:0] s_active_sel_d, s_active_sel_q;
  logic s_active_valid_d, s_active_valid_q;
  logic s_safe_clk_d, s_safe_clk_q;
  logic s_lock_d, s_lock_q;
  logic s_lock_seen_low_d, s_lock_seen_low_q;
  logic [1:0] s_err_d, s_err_q;
  logic s_rsp_valid_d, s_rsp_valid_q;

  cdc_2phase #(
      .DATA_WIDTH(3)
  ) u_pll_request_cdc (
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
  ) u_pll_response_cdc (
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
  assign s_req_ready = s_state_q == PLL_IDLE;
  assign s_rsp_data = {s_err_q, s_lock_q, s_safe_clk_q, s_active_valid_q, s_active_sel_q};
  assign pll_sel_o = s_pll_sel_q;
  assign pll_apply_o = s_pll_apply_q;
  assign select_ext_clk_o = s_sel_ext_clk_q;

  always_comb begin
    s_state_d         = s_state_q;
    s_pll_sel_d       = s_pll_sel_q;
    s_pll_apply_d     = (s_state_q == PLL_APPLY) || (s_state_q == PLL_WAIT_LOCK);
    s_sel_ext_clk_d   = s_sel_ext_clk_q;
    s_lock_count_d    = s_lock_count_q;
    s_active_sel_d    = s_active_sel_q;
    s_active_valid_d  = s_active_valid_q;
    s_safe_clk_d      = s_safe_clk_q;
    s_lock_d          = s_lock_q;
    s_lock_seen_low_d = s_lock_seen_low_q;
    s_err_d           = s_err_q;
    s_rsp_valid_d     = s_rsp_valid_q;

    unique case (s_state_q)
      PLL_IDLE: begin
        s_lock_seen_low_d = 1'b0;
        if (s_req_valid) begin
          s_pll_sel_d     = s_req_sel;
          s_sel_ext_clk_d = 1'b1;
          s_err_d         = 2'd0;
          s_state_d       = PLL_SAFE;
        end
      end
      PLL_SAFE: begin
        s_lock_seen_low_d = 1'b0;
        s_sel_ext_clk_d   = 1'b1;
        s_safe_clk_d      = 1'b1;
        s_lock_d          = 1'b0;
        if (pll_capable_i) begin
          s_state_d = PLL_APPLY;
        end else begin
          s_active_valid_d = 1'b0;
          s_err_d          = 2'd1;
          s_state_d        = PLL_RESPOND;
        end
      end
      PLL_APPLY: begin
        s_lock_count_d    = '0;
        s_lock_seen_low_d = 1'b0;
        s_state_d         = PLL_WAIT_LOCK;
      end
      PLL_WAIT_LOCK: begin
        if (!pll_lock_i) begin
          s_lock_seen_low_d = 1'b1;
        end
        if (s_lock_seen_low_q && pll_lock_i) begin
          s_active_sel_d   = s_pll_sel_q;
          s_active_valid_d = 1'b1;
          s_safe_clk_d     = 1'b0;
          s_lock_d         = 1'b1;
          s_err_d          = 2'd0;
          s_state_d        = PLL_SWITCH;
        end else if (s_lock_count_q == LockTimeout - 1) begin
          s_active_valid_d = 1'b0;
          s_safe_clk_d     = 1'b1;
          s_lock_d         = 1'b0;
          s_err_d          = 2'd2;
          s_state_d        = PLL_RESPOND;
        end else begin
          s_lock_count_d = s_lock_count_q + 1'b1;
        end
      end
      PLL_SWITCH: begin
        s_sel_ext_clk_d = 1'b0;
        s_state_d       = PLL_RESPOND;
      end
      PLL_RESPOND: begin
        s_rsp_valid_d = 1'b1;
        if (s_rsp_valid_q && s_rsp_ready) begin
          s_rsp_valid_d = 1'b0;
          s_state_d     = PLL_IDLE;
        end
      end
      default: begin
        s_state_d = PLL_IDLE;
      end
    endcase
  end

  dffrc #(
      .DATA_WIDTH(3),
      .RESET_VAL (PLL_IDLE)
  ) u_state_dffrc (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_q)
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
  ) u_select_ext_clk_dffrc (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_sel_ext_clk_d),
      .dat_o  (s_sel_ext_clk_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_lock_count_dffr (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_lock_count_d),
      .dat_o  (s_lock_count_q)
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
      .DATA_WIDTH(1)
  ) u_lock_seen_low_dffr (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_lock_seen_low_d),
      .dat_o  (s_lock_seen_low_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_error_dffr (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rsp_valid_dffr (
      .clk_i  (ext_clk_i),
      .rst_n_i(ext_rst_n_i),
      .dat_i  (s_rsp_valid_d),
      .dat_o  (s_rsp_valid_q)
  );
endmodule
