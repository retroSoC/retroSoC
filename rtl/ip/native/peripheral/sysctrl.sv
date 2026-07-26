// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "user_extensions.svh"
`include "mmap_define.svh"

interface sysctrl_if ();
  logic [`USER_CORESEL_WIDTH-1:0] core_sel_o;
  logic [   `USER_CORE_COUNT-1:0] core_reset_o;
  logic                           user_bus_enable_o;
  logic                           user_bus_idle_i;
  logic                           fault_access_i;
  logic [                    1:0] fault_master_i;
  logic [  `USER_IPSEL_WIDTH-1:0] ip_sel_o;

  modport dut(
      input user_bus_idle_i,
      input fault_access_i,
      input fault_master_i,
      output core_sel_o,
      output core_reset_o,
      output user_bus_enable_o,
      output ip_sel_o
  );
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

  typedef logic [7:0] sysctrl_offset_t;

  localparam sysctrl_offset_t SYSCTRL_CORESEL_OFFSET = 8'h00;
  localparam sysctrl_offset_t SYSCTRL_IPSEL_OFFSET = 8'h04;
  localparam sysctrl_offset_t SYSCTRL_PLL_CFG_OFFSET = sysctrl_offset_t'(`SOC_SYSCTRL_PLL_CFG_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PLL_CMD_OFFSET = sysctrl_offset_t'(`SOC_SYSCTRL_PLL_CMD_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_FAULT_STATUS_OFFSET = sysctrl_offset_t'(`SOC_SYSCTRL_FAULT_STATUS_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_FAULT_ADDR_OFFSET = sysctrl_offset_t'(`SOC_SYSCTRL_FAULT_ADDR_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_FAULT_COUNT_OFFSET = sysctrl_offset_t'(`SOC_SYSCTRL_FAULT_COUNT_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PLL_STATUS_OFFSET = sysctrl_offset_t'(`SOC_SYSCTRL_PLL_STATUS_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_USER_CORE_RESET_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_USER_CORE_RESET_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_USER_CORE_STATUS_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_USER_CORE_STATUS_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_FAULT_MASTER_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_FAULT_MASTER_OFFSET);

  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;

  logic [`USER_CORESEL_WIDTH-1:0] s_sysctrl_coresel_d, s_sysctrl_coresel_q;
  logic s_sysctrl_coresel_en;
  logic s_sysctrl_coresel_write_valid;
  logic [`USER_CORE_COUNT-1:0] s_user_reset_d, s_user_reset_q;
  logic s_user_reset_en;
  logic s_user_running_d, s_user_running_q;
  logic s_user_draining_d, s_user_draining_q;
  logic s_user_config_error_d, s_user_config_error_q;
  logic                        s_user_config_error_clear;
  logic                        s_user_reset_write_legal;
  logic [`USER_CORE_COUNT-1:0] s_user_reset_write_data;
  logic                        s_sysctrl_ipsel_en;
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
  logic [2:0] s_fault_reason_d, s_fault_reason_q;
  logic [31:0] s_fault_addr_d, s_fault_addr_q;
  logic [31:0] s_fault_count_d, s_fault_count_q;
  logic [1:0] s_fault_master_d, s_fault_master_q;

  assign s_nmi_wr_hdshk = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready = s_nmi_ready_q;
  assign nmi.rdata = s_nmi_rdata_q;

  assign sysctrl.ip_sel_o = s_sysctrl_ipsel_q;
  assign sysctrl.core_sel_o = s_sysctrl_coresel_q;
  assign sysctrl.core_reset_o = s_user_reset_q;
  assign sysctrl.user_bus_enable_o = s_user_running_q;
  assign pll_ctrl.req_sel_o = s_pll_cfg_q;
  assign pll_ctrl.req_valid_o = s_pll_req_valid_q;
  assign pll_ctrl.rsp_ready_o = 1'b1;

  assign s_sysctrl_coresel_write_valid = nmi.wdata[`USER_CORESEL_WIDTH-1:0] < `USER_CORE_COUNT;
  assign s_sysctrl_coresel_en = s_nmi_wr_hdshk && nmi.addr[7:0] == SYSCTRL_CORESEL_OFFSET &&
                              nmi.wstrb[0] && s_sysctrl_coresel_write_valid &&
                              (&s_user_reset_q) && sysctrl.user_bus_idle_i && ~s_user_running_q;
  assign s_sysctrl_coresel_d = nmi.wdata[`USER_CORESEL_WIDTH-1:0];
  dffer #(`USER_CORESEL_WIDTH) u_sysctrl_coresel_dffer (
      clk_i,
      rst_n_i,
      s_sysctrl_coresel_en,
      s_sysctrl_coresel_d,
      s_sysctrl_coresel_q
  );

  assign s_user_reset_write_data = nmi.wdata[`USER_CORE_COUNT-1:0];
  assign s_user_reset_write_legal = (&s_user_reset_write_data) ||
      ((s_sysctrl_coresel_q < `USER_CORE_COUNT) &&
       ((~s_user_reset_write_data) ==
        ({{(`USER_CORE_COUNT - 1){1'b0}}, 1'b1} << s_sysctrl_coresel_q)));
  assign s_user_reset_en = s_nmi_wr_hdshk && nmi.addr[7:0] == SYSCTRL_USER_CORE_RESET_OFFSET &&
                           nmi.wstrb[0];
  assign s_user_config_error_clear = s_nmi_wr_hdshk &&
      nmi.addr[7:0] == SYSCTRL_USER_CORE_STATUS_OFFSET && nmi.wstrb[1] && nmi.wdata[11];

  always_comb begin
    s_user_reset_d        = s_user_reset_q;
    s_user_running_d      = s_user_running_q;
    s_user_draining_d     = s_user_draining_q;
    s_user_config_error_d = s_user_config_error_q;
    if (s_user_config_error_clear) begin
      s_user_config_error_d = 1'b0;
    end
    if (s_nmi_wr_hdshk && nmi.addr[7:0] == SYSCTRL_CORESEL_OFFSET && ~s_sysctrl_coresel_en) begin
      s_user_config_error_d = 1'b1;
    end
    if (s_user_reset_en) begin
      if (~s_user_reset_write_legal) begin
        s_user_config_error_d = 1'b1;
      end else if (&s_user_reset_write_data) begin
        s_user_running_d = 1'b0;
        if (sysctrl.user_bus_idle_i) begin
          s_user_reset_d    = s_user_reset_write_data;
          s_user_draining_d = 1'b0;
        end else begin
          s_user_draining_d = 1'b1;
        end
      end else if (sysctrl.user_bus_idle_i && (&s_user_reset_q) && ~s_user_running_q) begin
        s_user_reset_d    = s_user_reset_write_data;
        s_user_running_d  = 1'b1;
        s_user_draining_d = 1'b0;
      end else begin
        s_user_config_error_d = 1'b1;
      end
    end
    if (s_user_draining_q && sysctrl.user_bus_idle_i) begin
      s_user_reset_d    = '1;
      s_user_draining_d = 1'b0;
    end
  end
  dffrc #(`USER_CORE_COUNT, '1) u_user_reset_dffrc (
      clk_i,
      rst_n_i,
      s_user_reset_d,
      s_user_reset_q
  );
  dffr #(1) u_user_running_dffr (
      clk_i,
      rst_n_i,
      s_user_running_d,
      s_user_running_q
  );
  dffr #(1) u_user_draining_dffr (
      clk_i,
      rst_n_i,
      s_user_draining_d,
      s_user_draining_q
  );
  dffr #(1) u_user_config_error_dffr (
      clk_i,
      rst_n_i,
      s_user_config_error_d,
      s_user_config_error_q
  );

  assign s_sysctrl_ipsel_en = s_nmi_wr_hdshk && nmi.addr[7:0] == SYSCTRL_IPSEL_OFFSET;
  assign s_sysctrl_ipsel_d  = nmi.wdata[`USER_IPSEL_WIDTH-1:0];
  dffer #(`USER_IPSEL_WIDTH) u_sysctrl_ipsel_dffer (
      clk_i,
      rst_n_i,
      s_sysctrl_ipsel_en,
      s_sysctrl_ipsel_d,
      s_sysctrl_ipsel_q
  );

  assign s_pll_cfg_en = s_nmi_wr_hdshk && nmi.addr[7:0] == SYSCTRL_PLL_CFG_OFFSET && nmi.wstrb[0];
  assign s_pll_cfg_d  = nmi.wdata[2:0];
  dffer #(3) u_pll_cfg_dffer (
      clk_i,
      rst_n_i,
      s_pll_cfg_en,
      s_pll_cfg_d,
      s_pll_cfg_q
  );

  assign s_pll_apply = s_nmi_wr_hdshk && nmi.addr[7:0] == SYSCTRL_PLL_CMD_OFFSET &&
                       nmi.wstrb[0] && nmi.wdata[0];
  assign s_pll_clear_error = s_nmi_wr_hdshk && nmi.addr[7:0] == SYSCTRL_PLL_CMD_OFFSET &&
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
                                nmi.addr[7:0] == SYSCTRL_FAULT_STATUS_OFFSET &&
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
      s_fault_reason_d  = sysctrl.fault_access_i ? 3'd3 : (fault_reserved_i ? 3'd2 : 3'd1);
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
  dffr #(3) u_fault_reason_dffr (
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
  assign s_fault_master_d = sysctrl.fault_master_i;
  dffer #(2) u_fault_master_dffer (
      clk_i,
      rst_n_i,
      fault_valid_i,
      s_fault_master_d,
      s_fault_master_q
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
      SYSCTRL_CORESEL_OFFSET: s_nmi_rdata_d = {{(32 - `USER_CORESEL_WIDTH) {1'b0}}, s_sysctrl_coresel_q};
      SYSCTRL_IPSEL_OFFSET:   s_nmi_rdata_d = {{(32 - `USER_IPSEL_WIDTH) {1'b0}}, s_sysctrl_ipsel_q};
      SYSCTRL_PLL_CFG_OFFSET: s_nmi_rdata_d = {29'd0, s_pll_cfg_q};
      SYSCTRL_FAULT_STATUS_OFFSET: s_nmi_rdata_d = {27'd0, s_fault_reason_q, s_fault_write_q, s_fault_pending_q};
      SYSCTRL_FAULT_ADDR_OFFSET:   s_nmi_rdata_d = s_fault_addr_q;
      SYSCTRL_FAULT_COUNT_OFFSET:  s_nmi_rdata_d = s_fault_count_q;
      SYSCTRL_PLL_STATUS_OFFSET: s_nmi_rdata_d = {
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
      SYSCTRL_USER_CORE_RESET_OFFSET: s_nmi_rdata_d = {{(32 - `USER_CORE_COUNT) {1'b0}}, s_user_reset_q};
      SYSCTRL_USER_CORE_STATUS_OFFSET: s_nmi_rdata_d = {
          20'd0,
          s_user_config_error_q,
          s_user_draining_q,
          sysctrl.user_bus_idle_i,
          s_user_running_q,
          { (8 - `USER_CORESEL_WIDTH) {1'b0} },
          s_sysctrl_coresel_q
      };
      SYSCTRL_FAULT_MASTER_OFFSET: s_nmi_rdata_d = {30'd0, s_fault_master_q};
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
