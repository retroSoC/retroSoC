// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module clock_config_controller (
    // verilog_format: off -- preserve the PCLK-to-AON transaction boundary columns
    input  logic             ctrl_clk_i,
    input  logic             ctrl_rst_n_i,
    input  logic             aon_clk_i,
    input  logic             aon_rst_n_i,
    input  logic       [2:0] hp_pstate_i,
    input  logic             hp_pll_sel_i,
    input  logic             pll_fault_i,
    input  logic             pclk_idle_i,
    clock_ctrl_if.rcu        clock_ctrl,
    output logic       [1:0] lp_mode_o,
    output logic       [1:0] lp_div_o,
    output logic       [2:0] pclk_div_o,
    output logic       [7:0] gate_mask_o,
    output logic      [15:0] timeout_o,
    output logic             pclk_update_o,
    output logic             force_safe_o,
    output logic             clear_fault_o,
    output logic       [1:0] mem_pad_mode_o,
    output logic             mem_pad_lock_o
    // verilog_format: on
);
  localparam logic [3:0] CommandLp = 4'd1;
  localparam logic [3:0] CommandPclk = 4'd2;
  localparam logic [3:0] CommandForceSafe = 4'd3;
  localparam logic [3:0] CommandGate = 4'd4;
  localparam logic [3:0] CommandClearFault = 4'd5;
  localparam logic [3:0] CommandTimeout = 4'd6;
  localparam logic [3:0] CommandMemPad = 4'd7;
  localparam logic [3:0] CommandMemFaultClear = 4'd8;

  logic [31:0] s_req_data;
  logic        s_req_valid;
  logic        s_req_ready;
  logic [31:0] s_rsp_data;
  logic        s_rsp_valid;
  logic        s_rsp_ready;
  logic [31:0] s_rsp_ctrl_data;
  logic        s_rsp_ctrl_valid;
  logic [ 1:0] s_lp_mode_d;
  logic [ 1:0] s_lp_mode_q;
  logic [ 1:0] s_lp_div_d;
  logic [ 1:0] s_lp_div_q;
  logic [ 2:0] s_pclk_div_d;
  logic [ 2:0] s_pclk_div_q;
  logic [ 7:0] s_gate_mask_d;
  logic [ 7:0] s_gate_mask_q;
  logic [15:0] s_timeout_d;
  logic [15:0] s_timeout_q;
  logic        s_pclk_update_d;
  logic        s_pclk_update_q;
  logic        s_force_safe_d;
  logic        s_force_safe_q;
  logic        s_clear_fault_d;
  logic        s_clear_fault_q;
  logic        s_rsp_pending_d;
  logic        s_rsp_pending_q;
  logic [ 3:0] s_rsp_code_d;
  logic [ 3:0] s_rsp_code_q;
  logic        s_req_legal;
  logic [ 1:0] s_mem_pad_mode_d;
  logic [ 1:0] s_mem_pad_mode_q;
  logic        s_mem_pad_lock_d;
  logic        s_mem_pad_lock_q;
  logic        s_mem_pad_fault_d;
  logic        s_mem_pad_fault_q;
  logic        s_unused_req_data;

  cdc_2phase #(
      .DATA_WIDTH(32)
  ) u_clock_req_cdc (
      .src_clk_i  (ctrl_clk_i),
      .src_rst_n_i(ctrl_rst_n_i),
      .src_data_i (clock_ctrl.req_data_o),
      .src_valid_i(clock_ctrl.req_valid_o),
      .src_ready_o(clock_ctrl.req_ready_i),
      .dst_clk_i  (aon_clk_i),
      .dst_rst_n_i(aon_rst_n_i),
      .dst_data_o (s_req_data),
      .dst_valid_o(s_req_valid),
      .dst_ready_i(s_req_ready)
  );

  cdc_2phase #(
      .DATA_WIDTH(32)
  ) u_clock_rsp_cdc (
      .src_clk_i  (aon_clk_i),
      .src_rst_n_i(aon_rst_n_i),
      .src_data_i (s_rsp_data),
      .src_valid_i(s_rsp_valid),
      .src_ready_o(s_rsp_ready),
      .dst_clk_i  (ctrl_clk_i),
      .dst_rst_n_i(ctrl_rst_n_i),
      .dst_data_o (s_rsp_ctrl_data),
      .dst_valid_o(s_rsp_ctrl_valid),
      .dst_ready_i(clock_ctrl.rsp_ready_o)
  );

  assign clock_ctrl.rsp_data_i = s_rsp_ctrl_data;
  assign clock_ctrl.rsp_valid_i = s_rsp_ctrl_valid;
  assign clock_ctrl.current_i = {
    13'd0, s_gate_mask_q, s_pclk_div_q, s_lp_div_q, s_lp_mode_q, hp_pll_sel_i, hp_pstate_i
  };
  assign clock_ctrl.fault_i = {30'd0, s_rsp_code_q != 4'd0, pll_fault_i};
  assign clock_ctrl.memory_i = {27'd0, s_mem_pad_fault_q, 1'b1, s_mem_pad_lock_q, s_mem_pad_mode_q};
  assign s_req_ready = !s_rsp_pending_q;
  assign s_rsp_valid = s_rsp_pending_q;
  assign s_rsp_data = {28'd0, s_rsp_code_q};
  assign lp_mode_o = s_lp_mode_q;
  assign lp_div_o = s_lp_div_q;
  assign pclk_div_o = s_pclk_div_q;
  assign gate_mask_o = s_gate_mask_q;
  assign timeout_o = s_timeout_q;
  assign pclk_update_o = s_pclk_update_q;
  assign force_safe_o = s_force_safe_q;
  assign clear_fault_o = s_clear_fault_q;
  assign mem_pad_mode_o = s_mem_pad_mode_q;
  assign mem_pad_lock_o = s_mem_pad_lock_q;
  assign s_unused_req_data = ^s_req_data[27:16];

  always_comb begin
    s_lp_mode_d       = s_lp_mode_q;
    s_lp_div_d        = s_lp_div_q;
    s_pclk_div_d      = s_pclk_div_q;
    s_gate_mask_d     = s_gate_mask_q;
    s_timeout_d       = s_timeout_q;
    s_pclk_update_d   = 1'b0;
    s_force_safe_d    = 1'b0;
    s_clear_fault_d   = 1'b0;
    s_rsp_pending_d   = s_rsp_pending_q;
    s_rsp_code_d      = s_rsp_code_q;
    s_req_legal       = 1'b0;
    s_mem_pad_mode_d  = s_mem_pad_mode_q;
    s_mem_pad_lock_d  = s_mem_pad_lock_q;
    s_mem_pad_fault_d = s_mem_pad_fault_q;
    if (s_rsp_pending_q && s_rsp_ready) begin
      s_rsp_pending_d = 1'b0;
    end
    if (s_req_valid && s_req_ready) begin
      unique case (s_req_data[31:28])
        CommandLp: begin
          s_req_legal = (s_req_data[1:0] <= 2'd2) && (s_req_data[3:2] <= 2'd2);
          if (s_req_legal) begin
            s_lp_mode_d = s_req_data[1:0];
            s_lp_div_d  = s_req_data[3:2];
          end
        end
        CommandPclk: begin
          s_req_legal = (s_req_data[2:0] <= 3'd4) && pclk_idle_i;
          if (s_req_legal) begin
            s_pclk_div_d    = s_req_data[2:0];
            s_pclk_update_d = 1'b1;
          end
        end
        CommandForceSafe: begin
          s_req_legal    = s_req_data[0];
          s_force_safe_d = s_req_legal;
          if (s_req_legal) begin
            s_lp_mode_d     = 2'd0;
            s_pclk_div_d    = 3'd0;
            s_pclk_update_d = 1'b1;
          end
        end
        CommandGate: begin
          s_req_legal   = 1'b1;
          s_gate_mask_d = s_req_data[7:0];
        end
        CommandClearFault: begin
          s_req_legal     = s_req_data[0];
          s_clear_fault_d = s_req_legal;
        end
        CommandTimeout: begin
          s_req_legal = s_req_data[15:0] != 16'd0;
          if (s_req_legal) s_timeout_d = s_req_data[15:0];
        end
        CommandMemPad: begin
          s_req_legal = !s_mem_pad_lock_q && (s_req_data[1:0] <= 2'd2);
          if (s_req_legal) begin
            s_mem_pad_mode_d = s_req_data[1:0];
            s_mem_pad_lock_d = s_req_data[8];
          end else begin
            s_mem_pad_fault_d = 1'b1;
          end
        end
        CommandMemFaultClear: begin
          s_req_legal = s_req_data[0];
          if (s_req_legal) s_mem_pad_fault_d = 1'b0;
        end
        default: s_req_legal = 1'b0;
      endcase
      s_rsp_code_d    = s_req_legal ? 4'd0 : 4'd1;
      s_rsp_pending_d = 1'b1;
    end
  end

  dffrc #(
      .DATA_WIDTH(2),
      .RESET_VAL (2'd0)
  ) u_lp_mode_dffrc (
      .clk_i  (aon_clk_i),
      .rst_n_i(aon_rst_n_i),
      .dat_i  (s_lp_mode_d),
      .dat_o  (s_lp_mode_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_lp_div_dffr (
      .clk_i  (aon_clk_i),
      .rst_n_i(aon_rst_n_i),
      .dat_i  (s_lp_div_d),
      .dat_o  (s_lp_div_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_pclk_div_dffr (
      .clk_i  (aon_clk_i),
      .rst_n_i(aon_rst_n_i),
      .dat_i  (s_pclk_div_d),
      .dat_o  (s_pclk_div_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_gate_mask_dffr (
      .clk_i  (aon_clk_i),
      .rst_n_i(aon_rst_n_i),
      .dat_i  (s_gate_mask_d),
      .dat_o  (s_gate_mask_q)
  );
  dffrc #(
      .DATA_WIDTH(16),
      .RESET_VAL (16'd1024)
  ) u_timeout_dffrc (
      .clk_i  (aon_clk_i),
      .rst_n_i(aon_rst_n_i),
      .dat_i  (s_timeout_d),
      .dat_o  (s_timeout_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_pclk_update_dffr (
      .clk_i  (aon_clk_i),
      .rst_n_i(aon_rst_n_i),
      .dat_i  (s_pclk_update_d),
      .dat_o  (s_pclk_update_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_force_safe_dffr (
      .clk_i  (aon_clk_i),
      .rst_n_i(aon_rst_n_i),
      .dat_i  (s_force_safe_d),
      .dat_o  (s_force_safe_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_clear_fault_dffr (
      .clk_i  (aon_clk_i),
      .rst_n_i(aon_rst_n_i),
      .dat_i  (s_clear_fault_d),
      .dat_o  (s_clear_fault_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rsp_pending_dffr (
      .clk_i  (aon_clk_i),
      .rst_n_i(aon_rst_n_i),
      .dat_i  (s_rsp_pending_d),
      .dat_o  (s_rsp_pending_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_rsp_code_dffr (
      .clk_i  (aon_clk_i),
      .rst_n_i(aon_rst_n_i),
      .dat_i  (s_rsp_code_d),
      .dat_o  (s_rsp_code_q)
  );
  dffrc #(
      .DATA_WIDTH(2),
      .RESET_VAL (2'd1)
  ) u_mem_pad_mode_dffrc (
      .clk_i  (aon_clk_i),
      .rst_n_i(aon_rst_n_i),
      .dat_i  (s_mem_pad_mode_d),
      .dat_o  (s_mem_pad_mode_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_mem_pad_lock_dffr (
      .clk_i  (aon_clk_i),
      .rst_n_i(aon_rst_n_i),
      .dat_i  (s_mem_pad_lock_d),
      .dat_o  (s_mem_pad_lock_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_mem_pad_fault_dffr (
      .clk_i  (aon_clk_i),
      .rst_n_i(aon_rst_n_i),
      .dat_i  (s_mem_pad_fault_d),
      .dat_o  (s_mem_pad_fault_q)
  );
endmodule
