// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef SYSCTEL_DEF_SV
`define SYSCTEL_DEF_SV

// verilog_format: off
`define NATV_SYSCTRL_CORESEL 8'h00 // RO
`define NATV_SYSCTRL_IPSEL   8'h04 // WR/RD
`define NATV_SYSCTRL_PLL_CFG `SOC_SYSCTRL_PLL_CFG_OFFSET // WR/RD
`define NATV_SYSCTRL_PLL_CMD `SOC_SYSCTRL_PLL_CMD_OFFSET // WO
`define NATV_SYSCTRL_FAULT_STATUS `SOC_SYSCTRL_FAULT_STATUS_OFFSET // W1C/RD
`define NATV_SYSCTRL_FAULT_ADDR   `SOC_SYSCTRL_FAULT_ADDR_OFFSET   // RD
`define NATV_SYSCTRL_FAULT_COUNT  `SOC_SYSCTRL_FAULT_COUNT_OFFSET  // RD
`define NATV_SYSCTRL_PLL_STATUS   `SOC_SYSCTRL_PLL_STATUS_OFFSET   // RD
// verilog_format: on

`endif

`include "mdd_config.svh"
`include "mmap_define.svh"

interface sysctrl_if ();
  logic [`USER_CORESEL_WIDTH-1:0] core_sel_i;
  logic [  `USER_IPSEL_WIDTH-1:0] ip_sel_o;

  modport dut(input core_sel_i, output ip_sel_o);
endinterface

module nmi_sysctrl (
    // verilog_format: off
    input logic    clk_i,
    input logic    rst_n_i,
    input logic    fault_valid_i,
    input logic [31:0] fault_addr_i,
    input logic [3:0]  fault_wstrb_i,
    input logic        fault_reserved_i,
    nmi_if.slave   nmi,
    sysctrl_if.dut sysctrl,
    pll_ctrl_if.sysctrl pll_ctrl
    // verilog_format: on
);

  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;

  logic [`USER_CORESEL_WIDTH-1:0] s_sysctrl_coresel_d, s_sysctrl_coresel_q;
  logic s_sysctrl_ipsel_en;
  logic [`USER_IPSEL_WIDTH-1:0] s_sysctrl_ipsel_d, s_sysctrl_ipsel_q;
  logic [2:0] s_pll_cfg_d, s_pll_cfg_q;
  logic s_pll_cfg_en;
  logic s_pll_apply, s_pll_clear_error;
  logic s_pll_req_valid_d, s_pll_req_valid_q;
  logic s_pll_busy_d, s_pll_busy_q;
  logic s_pll_rsp_accept;
  logic s_pll_error_d, s_pll_error_q;
  logic [1:0] s_pll_error_reason_d, s_pll_error_reason_q;
  logic [2:0] s_pll_active_sel_d, s_pll_active_sel_q;
  logic s_pll_active_valid_d, s_pll_active_valid_q;
  logic s_pll_safe_clk_d, s_pll_safe_clk_q;
  logic s_pll_lock_d, s_pll_lock_q;
  logic s_fault_status_clear;
  logic s_fault_pending_d, s_fault_pending_q;
  logic s_fault_write_d, s_fault_write_q;
  logic [1:0] s_fault_reason_d, s_fault_reason_q;
  logic [31:0] s_fault_addr_d, s_fault_addr_q;
  logic [31:0] s_fault_count_d, s_fault_count_q;

  assign s_nmi_wr_hdshk       = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk       = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready            = s_nmi_ready_q;
  assign nmi.rdata            = s_nmi_rdata_q;

  assign sysctrl.ip_sel_o     = s_sysctrl_ipsel_q;
  assign pll_ctrl.req_sel_o   = s_pll_cfg_q;
  assign pll_ctrl.req_valid_o = s_pll_req_valid_q;
  assign pll_ctrl.rsp_ready_o = 1'b1;

  assign s_sysctrl_coresel_d  = sysctrl.core_sel_i;
  dffr #(`USER_CORESEL_WIDTH) u_sysctrl_coresel_dffr (
      clk_i,
      rst_n_i,
      s_sysctrl_coresel_d,
      s_sysctrl_coresel_q
  );

  assign s_sysctrl_ipsel_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_SYSCTRL_IPSEL;
  assign s_sysctrl_ipsel_d  = nmi.wdata[`USER_IPSEL_WIDTH-1:0];
  dffer #(`USER_IPSEL_WIDTH) u_sysctrl_ipsel_dffer (
      clk_i,
      rst_n_i,
      s_sysctrl_ipsel_en,
      s_sysctrl_ipsel_d,
      s_sysctrl_ipsel_q
  );

  assign s_pll_cfg_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_SYSCTRL_PLL_CFG && nmi.wstrb[0];
  assign s_pll_cfg_d  = nmi.wdata[2:0];
  dffer #(3) u_pll_cfg_dffer (
      clk_i,
      rst_n_i,
      s_pll_cfg_en,
      s_pll_cfg_d,
      s_pll_cfg_q
  );

  assign s_pll_apply = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_SYSCTRL_PLL_CMD &&
                       nmi.wstrb[0] && nmi.wdata[0];
  assign s_pll_clear_error = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_SYSCTRL_PLL_CMD &&
                             nmi.wstrb[0] && nmi.wdata[1];
  assign s_pll_rsp_accept = pll_ctrl.rsp_valid_i && pll_ctrl.rsp_ready_o;

  always_comb begin
    s_pll_req_valid_d = s_pll_req_valid_q;
    s_pll_busy_d      = s_pll_busy_q;
    if (s_pll_req_valid_q && pll_ctrl.req_ready_i) begin
      s_pll_req_valid_d = 1'b0;
    end
    if (s_pll_apply && ~s_pll_busy_q && ~s_pll_req_valid_q) begin
      s_pll_req_valid_d = 1'b1;
      s_pll_busy_d      = 1'b1;
    end
    if (s_pll_rsp_accept) begin
      s_pll_busy_d = 1'b0;
    end
  end
  dffr #(1) u_pll_req_valid_dffr (
      clk_i,
      rst_n_i,
      s_pll_req_valid_d,
      s_pll_req_valid_q
  );
  dffr #(1) u_pll_busy_dffr (
      clk_i,
      rst_n_i,
      s_pll_busy_d,
      s_pll_busy_q
  );

  always_comb begin
    s_pll_error_d        = s_pll_error_q;
    s_pll_error_reason_d = s_pll_error_reason_q;
    if (s_pll_clear_error) begin
      s_pll_error_d        = 1'b0;
      s_pll_error_reason_d = 2'd0;
    end
    if (s_pll_apply && (s_pll_busy_q || s_pll_req_valid_q)) begin
      s_pll_error_d        = 1'b1;
      s_pll_error_reason_d = 2'd3;
    end
    if (s_pll_rsp_accept && |pll_ctrl.rsp_error_i) begin
      s_pll_error_d        = 1'b1;
      s_pll_error_reason_d = pll_ctrl.rsp_error_i;
    end
  end
  dffr #(1) u_pll_error_dffr (
      clk_i,
      rst_n_i,
      s_pll_error_d,
      s_pll_error_q
  );
  dffr #(2) u_pll_error_reason_dffr (
      clk_i,
      rst_n_i,
      s_pll_error_reason_d,
      s_pll_error_reason_q
  );

  assign s_pll_active_sel_d = pll_ctrl.rsp_active_sel_i;
  dffer #(3) u_pll_active_sel_dffer (
      clk_i,
      rst_n_i,
      s_pll_rsp_accept,
      s_pll_active_sel_d,
      s_pll_active_sel_q
  );
  assign s_pll_active_valid_d = pll_ctrl.rsp_active_valid_i;
  dffer #(1) u_pll_active_valid_dffer (
      clk_i,
      rst_n_i,
      s_pll_rsp_accept,
      s_pll_active_valid_d,
      s_pll_active_valid_q
  );
  assign s_pll_safe_clk_d = pll_ctrl.rsp_safe_clk_i;
  dfferc #(1, 1'b1) u_pll_safe_clk_dfferc (
      clk_i,
      rst_n_i,
      s_pll_rsp_accept,
      s_pll_safe_clk_d,
      s_pll_safe_clk_q
  );
  assign s_pll_lock_d = pll_ctrl.rsp_pll_lock_i;
  dffer #(1) u_pll_lock_dffer (
      clk_i,
      rst_n_i,
      s_pll_rsp_accept,
      s_pll_lock_d,
      s_pll_lock_q
  );

  assign s_fault_status_clear = s_nmi_wr_hdshk &&
                                nmi.addr[7:0] == `NATV_SYSCTRL_FAULT_STATUS &&
                                nmi.wstrb[0] && nmi.wdata[0];
  always_comb begin
    s_fault_pending_d = s_fault_pending_q;
    s_fault_write_d   = s_fault_write_q;
    s_fault_reason_d  = s_fault_reason_q;
    s_fault_addr_d    = s_fault_addr_q;
    s_fault_count_d   = s_fault_count_q;
    if (s_fault_status_clear) begin
      s_fault_pending_d = 1'b0;
    end
    if (fault_valid_i) begin
      s_fault_pending_d = 1'b1;
      s_fault_write_d   = |fault_wstrb_i;
      s_fault_reason_d  = fault_reserved_i ? 2'd2 : 2'd1;
      s_fault_addr_d    = fault_addr_i;
      if (~(&s_fault_count_q)) begin
        s_fault_count_d = s_fault_count_q + 32'd1;
      end
    end
  end
  dffr #(1) u_fault_pending_dffr (
      clk_i,
      rst_n_i,
      s_fault_pending_d,
      s_fault_pending_q
  );
  dffr #(1) u_fault_write_dffr (
      clk_i,
      rst_n_i,
      s_fault_write_d,
      s_fault_write_q
  );
  dffr #(2) u_fault_reason_dffr (
      clk_i,
      rst_n_i,
      s_fault_reason_d,
      s_fault_reason_q
  );
  dffr #(32) u_fault_addr_dffr (
      clk_i,
      rst_n_i,
      s_fault_addr_d,
      s_fault_addr_q
  );
  dffr #(32) u_fault_count_dffr (
      clk_i,
      rst_n_i,
      s_fault_count_d,
      s_fault_count_q
  );

  assign s_nmi_ready_d = nmi.valid && (~s_nmi_ready_q);
  dffr #(1) u_nmi_ready_dffr (
      clk_i,
      rst_n_i,
      s_nmi_ready_d,
      s_nmi_ready_q
  );

  assign s_nmi_rdata_en = s_nmi_rd_hdshk;
  always_comb begin
    s_nmi_rdata_d = s_nmi_rdata_q;
    unique case (nmi.addr[7:0])
      // verilog_format: off
      `NATV_SYSCTRL_CORESEL: s_nmi_rdata_d = {{(32 - `USER_CORESEL_WIDTH) {1'b0}}, s_sysctrl_coresel_q};
      `NATV_SYSCTRL_IPSEL:   s_nmi_rdata_d = {{(32 - `USER_IPSEL_WIDTH) {1'b0}}, s_sysctrl_ipsel_q};
      `NATV_SYSCTRL_PLL_CFG: s_nmi_rdata_d = {29'd0, s_pll_cfg_q};
      `NATV_SYSCTRL_FAULT_STATUS: s_nmi_rdata_d = {28'd0, s_fault_reason_q, s_fault_write_q, s_fault_pending_q};
      `NATV_SYSCTRL_FAULT_ADDR:   s_nmi_rdata_d = s_fault_addr_q;
      `NATV_SYSCTRL_FAULT_COUNT:  s_nmi_rdata_d = s_fault_count_q;
      `NATV_SYSCTRL_PLL_STATUS: s_nmi_rdata_d = {
          21'd0,
          pll_ctrl.capable_i,
          s_pll_lock_q,
          s_pll_safe_clk_q,
          s_pll_error_reason_q,
          s_pll_error_q,
          s_pll_busy_q,
          s_pll_active_valid_q,
          s_pll_active_sel_q
      };
      default: s_nmi_rdata_d = s_nmi_rdata_q;
    endcase
      // verilog_format: on
  end
  dffer #(32) u_nmi_rdata_dffer (
      clk_i,
      rst_n_i,
      s_nmi_rdata_en,
      s_nmi_rdata_d,
      s_nmi_rdata_q
  );

endmodule
