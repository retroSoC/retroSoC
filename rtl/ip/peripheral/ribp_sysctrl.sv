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
`include "rib_defs.svh"

interface sysctrl_if ();
  logic [`USER_CORESEL_WIDTH-1:0] core_sel_o;
  logic [   `USER_CORE_COUNT-1:0] core_reset_o;
  logic                           user_bus_enable_o;
  logic                           user_bus_idle_i;
  logic                           fault_access_i;
  logic [                    1:0] fault_master_i;
  logic [                    2:0] fault_code_i;
  logic                           perf_enable_o;
  logic                           perf_clear_o;
  logic [                   63:0] perf_mgmt_wait_i;
  logic [                   63:0] perf_user_wait_i;
  logic [                   63:0] perf_dma_wait_i;
  logic [                   63:0] perf_ribp_wait_i;
  logic [                   63:0] perf_apb_wait_i;
  logic [                   63:0] perf_sdram_wait_i;
  logic [                   63:0] perf_psram_wait_i;
  logic [                   63:0] perf_flash_wait_i;
  logic                           rtc_wake_i;
  logic                           test_done_o;
  logic                           test_pass_o;
  logic [                    7:0] test_code_o;
  logic [  `USER_IPSEL_WIDTH-1:0] ip_sel_o;

  modport dut(
      input user_bus_idle_i,
      input fault_access_i,
      input fault_master_i,
      input fault_code_i,
      input perf_mgmt_wait_i,
      input perf_user_wait_i,
      input perf_dma_wait_i,
      input perf_ribp_wait_i,
      input perf_apb_wait_i,
      input perf_sdram_wait_i,
      input perf_psram_wait_i,
      input perf_flash_wait_i,
      input rtc_wake_i,
      output core_sel_o,
      output core_reset_o,
      output user_bus_enable_o,
      output ip_sel_o,
      output perf_enable_o,
      output perf_clear_o,
      output test_done_o,
      output test_pass_o,
      output test_code_o
  );
endinterface

module ribp_sysctrl (
    // verilog_format: off -- preserve reviewed column alignment
    input logic         clk_i,
    input logic         rst_n_i,
    input logic         fault_valid_i,
    input logic [31:0]  fault_addr_i,
    input logic [3:0]   fault_wstrb_i,
    input logic         fault_reserved_i,
    ribp_if.slave       ribp,
    sysctrl_if.dut      sysctrl,
    pll_ctrl_if.sysctrl pll_ctrl
    // verilog_format: on
);

  typedef logic [7:0] sysctrl_offset_t;

  localparam sysctrl_offset_t SYSCTRL_CORESEL_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_CORESEL_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_IPSEL_OFFSET = sysctrl_offset_t'(`SOC_SYSCTRL_IPSEL_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PLL_CFG_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PLL_CFG_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PLL_CMD_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PLL_CMD_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_FAULT_STATUS_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_FAULT_STATUS_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_FAULT_ADDR_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_FAULT_ADDR_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_FAULT_COUNT_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_FAULT_COUNT_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PLL_STATUS_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PLL_STATUS_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_USER_CORE_RESET_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_USER_CORE_RESET_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_USER_CORE_STATUS_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_USER_CORE_STATUS_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_FAULT_MASTER_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_FAULT_MASTER_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_FAULT_DETAIL_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_FAULT_DETAIL_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_CTRL_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_CTRL_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_MGMT_WAIT_LO_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_MGMT_WAIT_LO_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_MGMT_WAIT_HI_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_MGMT_WAIT_HI_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_USER_WAIT_LO_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_USER_WAIT_LO_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_USER_WAIT_HI_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_USER_WAIT_HI_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_DMA_WAIT_LO_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_DMA_WAIT_LO_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_DMA_WAIT_HI_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_DMA_WAIT_HI_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_RIBP_WAIT_LO_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_RIBP_WAIT_LO_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_RIBP_WAIT_HI_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_RIBP_WAIT_HI_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_APB_WAIT_LO_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_APB_WAIT_LO_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_APB_WAIT_HI_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_APB_WAIT_HI_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_SDRAM_WAIT_LO_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_SDRAM_WAIT_LO_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_SDRAM_WAIT_HI_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_SDRAM_WAIT_HI_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_PSRAM_WAIT_LO_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_PSRAM_WAIT_LO_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_PSRAM_WAIT_HI_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_PSRAM_WAIT_HI_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_FLASH_WAIT_LO_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_FLASH_WAIT_LO_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_PERF_FLASH_WAIT_HI_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_PERF_FLASH_WAIT_HI_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_TEST_STATUS_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_TEST_STATUS_OFFSET);
  localparam sysctrl_offset_t SYSCTRL_RTC_WAKE_STATUS_OFFSET =
      sysctrl_offset_t'(`SOC_SYSCTRL_RTC_WAKE_STATUS_OFFSET);

  logic s_ribp_wr_hdshk, s_ribp_rd_hdshk;
  logic s_ribp_ready_d, s_ribp_ready_q;
  logic s_ribp_rdata_en;
  logic [31:0] s_ribp_rdata_d, s_ribp_rdata_q;

  logic [`USER_CORESEL_WIDTH-1:0] s_sysctrl_coresel_d, s_sysctrl_coresel_q;
  logic s_sysctrl_coresel_en;
  logic s_sysctrl_coresel_write_valid;
  logic [`USER_CORE_COUNT-1:0] s_user_reset_d, s_user_reset_q;
  logic s_user_reset_en;
  logic s_user_running_d, s_user_running_q;
  logic s_user_draining_d, s_user_draining_q;
  logic s_user_config_err_d, s_user_config_err_q;
  logic                        s_user_config_err_clear;
  logic                        s_user_reset_write_legal;
  logic [`USER_CORE_COUNT-1:0] s_user_reset_write_data;
  logic                        s_sysctrl_ipsel_en;
  logic [`USER_IPSEL_WIDTH-1:0] s_sysctrl_ipsel_d, s_sysctrl_ipsel_q;
  logic [2:0] s_pll_cfg_d, s_pll_cfg_q;
  logic s_pll_cfg_en;
  logic s_pll_apply, s_pll_clear_err;
  logic s_pll_req_valid_d, s_pll_req_valid_q;
  logic s_pll_busy_d, s_pll_busy_q;
  logic s_pll_rsp_accept;
  logic s_pll_err_d, s_pll_err_q;
  logic [1:0] s_pll_err_reason_d, s_pll_err_reason_q;
  logic [2:0] s_pll_active_sel_d, s_pll_active_sel_q;
  logic s_pll_active_valid_d, s_pll_active_valid_q;
  logic s_pll_safe_clk_d, s_pll_safe_clk_q;
  logic s_pll_lock_d, s_pll_lock_q;
  logic s_fault_stat_clear;
  logic s_fault_pending_d, s_fault_pending_q;
  logic s_fault_write_d, s_fault_write_q;
  logic [2:0] s_fault_reason_d, s_fault_reason_q;
  logic [2:0] s_fault_detail_d, s_fault_detail_q;
  logic [31:0] s_fault_addr_d, s_fault_addr_q;
  logic [31:0] s_fault_count_d, s_fault_count_q;
  logic [1:0] s_fault_master_d, s_fault_master_q;
  logic s_perf_en_d, s_perf_en_q;
  logic s_perf_en_en, s_perf_clear, s_perf_snapshot;
  logic [63:0] s_perf_mgmt_wait_q;
  logic [63:0] s_perf_user_wait_q;
  logic [63:0] s_perf_dma_wait_q;
  logic [63:0] s_perf_ribp_wait_q;
  logic [63:0] s_perf_apb_wait_q;
  logic [63:0] s_perf_sdram_wait_q;
  logic [63:0] s_perf_psram_wait_q;
  logic [63:0] s_perf_flash_wait_q;
  logic s_test_done_d, s_test_done_q;
  logic s_test_pass_d, s_test_pass_q;
  logic [7:0] s_test_code_d, s_test_code_q;
  logic s_test_stat_write;
  logic s_rtc_wake_sync;
  logic s_rtc_wake_clear;
  logic s_rtc_wake_seen_d, s_rtc_wake_seen_q;

  assign s_ribp_wr_hdshk           = ribp.valid && (~s_ribp_ready_q) && (|ribp.wstrb);
  assign s_ribp_rd_hdshk           = ribp.valid && (~s_ribp_ready_q) && (~(|ribp.wstrb));
  assign ribp.ready                = s_ribp_ready_q;
  assign ribp.resp_err             = 1'b0;
  assign ribp.rdata                = s_ribp_rdata_q;

  assign sysctrl.ip_sel_o          = s_sysctrl_ipsel_q;
  assign sysctrl.core_sel_o        = s_sysctrl_coresel_q;
  assign sysctrl.core_reset_o      = s_user_reset_q;
  assign sysctrl.user_bus_enable_o = s_user_running_q;
  assign sysctrl.perf_enable_o     = s_perf_en_q;
  assign sysctrl.perf_clear_o      = s_perf_clear;
  assign sysctrl.test_done_o       = s_test_done_q;
  assign sysctrl.test_pass_o       = s_test_pass_q;
  assign sysctrl.test_code_o       = s_test_code_q;
  assign pll_ctrl.req_sel_o        = s_pll_cfg_q;
  assign pll_ctrl.req_valid_o      = s_pll_req_valid_q;
  assign pll_ctrl.rsp_ready_o      = 1'b1;

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_rtc_wake_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (sysctrl.rtc_wake_i),
      .dat_o  (s_rtc_wake_sync)
  );

  assign s_rtc_wake_clear = s_ribp_wr_hdshk &&
      (ribp.addr[7:0] == SYSCTRL_RTC_WAKE_STATUS_OFFSET) && ribp.wstrb[0] && ribp.wdata[1];
  always_comb begin
    s_rtc_wake_seen_d = s_rtc_wake_seen_q;
    if (s_rtc_wake_clear) begin
      s_rtc_wake_seen_d = 1'b0;
    end
    if (s_rtc_wake_sync) begin
      s_rtc_wake_seen_d = 1'b1;
    end
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_rtc_wake_seen_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rtc_wake_seen_d),
      .dat_o  (s_rtc_wake_seen_q)
  );

  assign s_sysctrl_coresel_write_valid = ribp.wdata[`USER_CORESEL_WIDTH-1:0] < `USER_CORE_COUNT;
  assign s_sysctrl_coresel_en = s_ribp_wr_hdshk && ribp.addr[7:0] == SYSCTRL_CORESEL_OFFSET &&
                              ribp.wstrb[0] && s_sysctrl_coresel_write_valid &&
                              (&s_user_reset_q) && sysctrl.user_bus_idle_i && ~s_user_running_q;
  assign s_sysctrl_coresel_d = ribp.wdata[`USER_CORESEL_WIDTH-1:0];
  dffer #(
      .DATA_WIDTH(`USER_CORESEL_WIDTH)
  ) u_sysctrl_coresel_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_sysctrl_coresel_en),
      .dat_i  (s_sysctrl_coresel_d),
      .dat_o  (s_sysctrl_coresel_q)
  );

  assign s_user_reset_write_data = ribp.wdata[`USER_CORE_COUNT-1:0];
  assign s_user_reset_write_legal = (&s_user_reset_write_data) ||
      ((s_sysctrl_coresel_q < `USER_CORE_COUNT) &&
       ((~s_user_reset_write_data) ==
        ({{(`USER_CORE_COUNT - 1){1'b0}}, 1'b1} << s_sysctrl_coresel_q)));
  assign s_user_reset_en = s_ribp_wr_hdshk && ribp.addr[7:0] == SYSCTRL_USER_CORE_RESET_OFFSET &&
                           ribp.wstrb[0];
  assign s_user_config_err_clear = s_ribp_wr_hdshk &&
      ribp.addr[7:0] == SYSCTRL_USER_CORE_STATUS_OFFSET && ribp.wstrb[1] && ribp.wdata[11];

  always_comb begin
    s_user_reset_d      = s_user_reset_q;
    s_user_running_d    = s_user_running_q;
    s_user_draining_d   = s_user_draining_q;
    s_user_config_err_d = s_user_config_err_q;
    if (s_user_config_err_clear) begin
      s_user_config_err_d = 1'b0;
    end
    if (s_ribp_wr_hdshk && ribp.addr[7:0] == SYSCTRL_CORESEL_OFFSET && ~s_sysctrl_coresel_en) begin
      s_user_config_err_d = 1'b1;
    end
    if (s_user_reset_en) begin
      if (~s_user_reset_write_legal) begin
        s_user_config_err_d = 1'b1;
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
        s_user_config_err_d = 1'b1;
      end
    end
    if (s_user_draining_q && sysctrl.user_bus_idle_i) begin
      s_user_reset_d    = '1;
      s_user_draining_d = 1'b0;
    end
  end
  dffrc #(
      .DATA_WIDTH(`USER_CORE_COUNT),
      .RESET_VAL ('1)
  ) u_user_reset_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_user_reset_d),
      .dat_o  (s_user_reset_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_user_running_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_user_running_d),
      .dat_o  (s_user_running_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_user_draining_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_user_draining_d),
      .dat_o  (s_user_draining_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_user_config_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_user_config_err_d),
      .dat_o  (s_user_config_err_q)
  );

  assign s_sysctrl_ipsel_en = s_ribp_wr_hdshk && ribp.addr[7:0] == SYSCTRL_IPSEL_OFFSET;
  assign s_sysctrl_ipsel_d  = ribp.wdata[`USER_IPSEL_WIDTH-1:0];
  dffer #(
      .DATA_WIDTH(`USER_IPSEL_WIDTH)
  ) u_sysctrl_ipsel_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_sysctrl_ipsel_en),
      .dat_i  (s_sysctrl_ipsel_d),
      .dat_o  (s_sysctrl_ipsel_q)
  );

  assign s_pll_cfg_en = s_ribp_wr_hdshk &&
                        (ribp.addr[7:0] == SYSCTRL_PLL_CFG_OFFSET) && ribp.wstrb[0];
  assign s_pll_cfg_d = ribp.wdata[2:0];
  dffer #(
      .DATA_WIDTH(3)
  ) u_pll_cfg_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_pll_cfg_en),
      .dat_i  (s_pll_cfg_d),
      .dat_o  (s_pll_cfg_q)
  );

  assign s_pll_apply = s_ribp_wr_hdshk && ribp.addr[7:0] == SYSCTRL_PLL_CMD_OFFSET &&
                       ribp.wstrb[0] && ribp.wdata[0];
  assign s_pll_clear_err = s_ribp_wr_hdshk && ribp.addr[7:0] == SYSCTRL_PLL_CMD_OFFSET &&
                             ribp.wstrb[0] && ribp.wdata[1];
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
  dffr #(
      .DATA_WIDTH(1)
  ) u_pll_req_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pll_req_valid_d),
      .dat_o  (s_pll_req_valid_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_pll_busy_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pll_busy_d),
      .dat_o  (s_pll_busy_q)
  );

  always_comb begin
    s_pll_err_d        = s_pll_err_q;
    s_pll_err_reason_d = s_pll_err_reason_q;
    if (s_pll_clear_err) begin
      s_pll_err_d        = 1'b0;
      s_pll_err_reason_d = 2'd0;
    end
    if (s_pll_apply && (s_pll_busy_q || s_pll_req_valid_q)) begin
      s_pll_err_d        = 1'b1;
      s_pll_err_reason_d = 2'd3;
    end
    if (s_pll_rsp_accept && |pll_ctrl.rsp_error_i) begin
      s_pll_err_d        = 1'b1;
      s_pll_err_reason_d = pll_ctrl.rsp_error_i;
    end
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_pll_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pll_err_d),
      .dat_o  (s_pll_err_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_pll_error_reason_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pll_err_reason_d),
      .dat_o  (s_pll_err_reason_q)
  );

  assign s_pll_active_sel_d = pll_ctrl.rsp_active_sel_i;
  dffer #(
      .DATA_WIDTH(3)
  ) u_pll_active_sel_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_pll_rsp_accept),
      .dat_i  (s_pll_active_sel_d),
      .dat_o  (s_pll_active_sel_q)
  );
  assign s_pll_active_valid_d = pll_ctrl.rsp_active_valid_i;
  dffer #(
      .DATA_WIDTH(1)
  ) u_pll_active_valid_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_pll_rsp_accept),
      .dat_i  (s_pll_active_valid_d),
      .dat_o  (s_pll_active_valid_q)
  );
  assign s_pll_safe_clk_d = pll_ctrl.rsp_safe_clk_i;
  dfferc #(
      .DATA_WIDTH(1),
      .RESET_VAL (1'b1)
  ) u_pll_safe_clk_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_pll_rsp_accept),
      .dat_i  (s_pll_safe_clk_d),
      .dat_o  (s_pll_safe_clk_q)
  );
  assign s_pll_lock_d = pll_ctrl.rsp_pll_lock_i;
  dffer #(
      .DATA_WIDTH(1)
  ) u_pll_lock_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_pll_rsp_accept),
      .dat_i  (s_pll_lock_d),
      .dat_o  (s_pll_lock_q)
  );

  assign s_perf_en_en = s_ribp_wr_hdshk && ribp.addr[7:0] == SYSCTRL_PERF_CTRL_OFFSET &&
                            ribp.wstrb[0];
  assign s_perf_en_d = ribp.wdata[0];
  assign s_perf_clear = s_perf_en_en && ribp.wdata[1];
  assign s_perf_snapshot = s_perf_en_en && ribp.wdata[2];
  dffer #(
      .DATA_WIDTH(1)
  ) u_perf_enable_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_perf_en_en),
      .dat_i  (s_perf_en_d),
      .dat_o  (s_perf_en_q)
  );
  dffer #(
      .DATA_WIDTH(64)
  ) u_perf_mgmt_wait_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_perf_snapshot),
      .dat_i  (sysctrl.perf_mgmt_wait_i),
      .dat_o  (s_perf_mgmt_wait_q)
  );
  dffer #(
      .DATA_WIDTH(64)
  ) u_perf_user_wait_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_perf_snapshot),
      .dat_i  (sysctrl.perf_user_wait_i),
      .dat_o  (s_perf_user_wait_q)
  );
  dffer #(
      .DATA_WIDTH(64)
  ) u_perf_dma_wait_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_perf_snapshot),
      .dat_i  (sysctrl.perf_dma_wait_i),
      .dat_o  (s_perf_dma_wait_q)
  );
  dffer #(
      .DATA_WIDTH(64)
  ) u_perf_ribp_wait_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_perf_snapshot),
      .dat_i  (sysctrl.perf_ribp_wait_i),
      .dat_o  (s_perf_ribp_wait_q)
  );
  dffer #(
      .DATA_WIDTH(64)
  ) u_perf_apb_wait_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_perf_snapshot),
      .dat_i  (sysctrl.perf_apb_wait_i),
      .dat_o  (s_perf_apb_wait_q)
  );
  dffer #(
      .DATA_WIDTH(64)
  ) u_perf_sdram_wait_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_perf_snapshot),
      .dat_i  (sysctrl.perf_sdram_wait_i),
      .dat_o  (s_perf_sdram_wait_q)
  );
  dffer #(
      .DATA_WIDTH(64)
  ) u_perf_psram_wait_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_perf_snapshot),
      .dat_i  (sysctrl.perf_psram_wait_i),
      .dat_o  (s_perf_psram_wait_q)
  );
  dffer #(
      .DATA_WIDTH(64)
  ) u_perf_flash_wait_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_perf_snapshot),
      .dat_i  (sysctrl.perf_flash_wait_i),
      .dat_o  (s_perf_flash_wait_q)
  );

  assign s_test_stat_write = s_ribp_wr_hdshk && ribp.addr[7:0] == SYSCTRL_TEST_STATUS_OFFSET &&
                               ribp.wstrb == 4'hF && ribp.wdata[31] && ~s_test_done_q;
  assign s_test_done_d = 1'b1;
  dffer #(
      .DATA_WIDTH(1)
  ) u_test_done_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_test_stat_write),
      .dat_i  (s_test_done_d),
      .dat_o  (s_test_done_q)
  );
  assign s_test_pass_d = ribp.wdata[0];
  dffer #(
      .DATA_WIDTH(1)
  ) u_test_pass_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_test_stat_write),
      .dat_i  (s_test_pass_d),
      .dat_o  (s_test_pass_q)
  );
  assign s_test_code_d = ribp.wdata[15:8];
  dffer #(
      .DATA_WIDTH(8)
  ) u_test_code_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_test_stat_write),
      .dat_i  (s_test_code_d),
      .dat_o  (s_test_code_q)
  );

  assign s_fault_stat_clear = s_ribp_wr_hdshk &&
                                ribp.addr[7:0] == SYSCTRL_FAULT_STATUS_OFFSET &&
                                ribp.wstrb[0] && ribp.wdata[0];
  always_comb begin
    s_fault_pending_d = s_fault_pending_q;
    s_fault_write_d   = s_fault_write_q;
    s_fault_reason_d  = s_fault_reason_q;
    s_fault_detail_d  = s_fault_detail_q;
    s_fault_addr_d    = s_fault_addr_q;
    s_fault_count_d   = s_fault_count_q;
    if (s_fault_stat_clear) begin
      s_fault_pending_d = 1'b0;
    end
    if (fault_valid_i) begin
      s_fault_pending_d = 1'b1;
      if (~s_fault_pending_q || s_fault_stat_clear) begin
        s_fault_write_d = |fault_wstrb_i;
        s_fault_detail_d = |sysctrl.fault_code_i ? sysctrl.fault_code_i :
                           sysctrl.fault_access_i ? `RIB_RESP_PROTERR :
                           fault_reserved_i ? `RIB_RESP_RESERVED : `RIB_RESP_DECERR;
        unique case (s_fault_detail_d)
          `RIB_RESP_RESERVED: s_fault_reason_d = 3'd2;
          `RIB_RESP_PROTERR:  s_fault_reason_d = 3'd3;
          `RIB_RESP_SLVERR:   s_fault_reason_d = 3'd4;
          `RIB_RESP_TIMEOUT:  s_fault_reason_d = 3'd5;
          default:            s_fault_reason_d = 3'd1;
        endcase
        s_fault_addr_d = fault_addr_i;
      end
      if (~(&s_fault_count_q)) begin
        s_fault_count_d = s_fault_count_q + 32'd1;
      end
    end
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_fault_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_pending_d),
      .dat_o  (s_fault_pending_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_fault_write_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_write_d),
      .dat_o  (s_fault_write_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_fault_reason_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_reason_d),
      .dat_o  (s_fault_reason_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_fault_detail_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_detail_d),
      .dat_o  (s_fault_detail_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_fault_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_addr_d),
      .dat_o  (s_fault_addr_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_fault_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_count_d),
      .dat_o  (s_fault_count_q)
  );
  always_comb begin
    s_fault_master_d = s_fault_master_q;
    if (fault_valid_i && (~s_fault_pending_q || s_fault_stat_clear)) begin
      s_fault_master_d = sysctrl.fault_master_i;
    end
  end
  dffr #(
      .DATA_WIDTH(2)
  ) u_fault_master_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_master_d),
      .dat_o  (s_fault_master_q)
  );

  assign s_ribp_ready_d = ribp.valid && (~s_ribp_ready_q);
  dffr #(
      .DATA_WIDTH(1)
  ) u_ribp_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ribp_ready_d),
      .dat_o  (s_ribp_ready_q)
  );

  assign s_ribp_rdata_en = s_ribp_rd_hdshk;
  always_comb begin
    s_ribp_rdata_d = s_ribp_rdata_q;
    unique case (ribp.addr[7:0])
      // verilog_format: off -- preserve reviewed column alignment
      SYSCTRL_CORESEL_OFFSET:
          s_ribp_rdata_d = {{(32 - `USER_CORESEL_WIDTH) {1'b0}}, s_sysctrl_coresel_q};
      SYSCTRL_IPSEL_OFFSET:
          s_ribp_rdata_d = {{(32 - `USER_IPSEL_WIDTH) {1'b0}}, s_sysctrl_ipsel_q};
      SYSCTRL_PLL_CFG_OFFSET:            s_ribp_rdata_d = {29'd0, s_pll_cfg_q};
      SYSCTRL_FAULT_STATUS_OFFSET:
          s_ribp_rdata_d = {27'd0, s_fault_reason_q, s_fault_write_q, s_fault_pending_q};
      SYSCTRL_FAULT_ADDR_OFFSET:         s_ribp_rdata_d = s_fault_addr_q;
      SYSCTRL_FAULT_COUNT_OFFSET:        s_ribp_rdata_d = s_fault_count_q;
      SYSCTRL_PLL_STATUS_OFFSET:         s_ribp_rdata_d = {
          21'd0,
          pll_ctrl.capable_i,
          s_pll_lock_q,
          s_pll_safe_clk_q,
          s_pll_err_reason_q,
          s_pll_err_q,
          s_pll_busy_q,
          s_pll_active_valid_q,
          s_pll_active_sel_q
      };
      SYSCTRL_USER_CORE_RESET_OFFSET:
          s_ribp_rdata_d = {{(32 - `USER_CORE_COUNT) {1'b0}}, s_user_reset_q};
      SYSCTRL_USER_CORE_STATUS_OFFSET:   s_ribp_rdata_d = {
          20'd0,
          s_user_config_err_q,
          s_user_draining_q,
          sysctrl.user_bus_idle_i,
          s_user_running_q,
          { (8 - `USER_CORESEL_WIDTH) {1'b0} },
          s_sysctrl_coresel_q
      };
      SYSCTRL_FAULT_MASTER_OFFSET:       s_ribp_rdata_d = {30'd0, s_fault_master_q};
      SYSCTRL_FAULT_DETAIL_OFFSET:       s_ribp_rdata_d = {29'd0, s_fault_detail_q};
      SYSCTRL_PERF_CTRL_OFFSET:          s_ribp_rdata_d = {31'd0, s_perf_en_q};
      SYSCTRL_PERF_MGMT_WAIT_LO_OFFSET:  s_ribp_rdata_d = s_perf_mgmt_wait_q[31:0];
      SYSCTRL_PERF_MGMT_WAIT_HI_OFFSET:  s_ribp_rdata_d = s_perf_mgmt_wait_q[63:32];
      SYSCTRL_PERF_USER_WAIT_LO_OFFSET:  s_ribp_rdata_d = s_perf_user_wait_q[31:0];
      SYSCTRL_PERF_USER_WAIT_HI_OFFSET:  s_ribp_rdata_d = s_perf_user_wait_q[63:32];
      SYSCTRL_PERF_DMA_WAIT_LO_OFFSET:   s_ribp_rdata_d = s_perf_dma_wait_q[31:0];
      SYSCTRL_PERF_DMA_WAIT_HI_OFFSET:   s_ribp_rdata_d = s_perf_dma_wait_q[63:32];
      SYSCTRL_PERF_RIBP_WAIT_LO_OFFSET:   s_ribp_rdata_d = s_perf_ribp_wait_q[31:0];
      SYSCTRL_PERF_RIBP_WAIT_HI_OFFSET:   s_ribp_rdata_d = s_perf_ribp_wait_q[63:32];
      SYSCTRL_PERF_APB_WAIT_LO_OFFSET:   s_ribp_rdata_d = s_perf_apb_wait_q[31:0];
      SYSCTRL_PERF_APB_WAIT_HI_OFFSET:   s_ribp_rdata_d = s_perf_apb_wait_q[63:32];
      SYSCTRL_PERF_SDRAM_WAIT_LO_OFFSET: s_ribp_rdata_d = s_perf_sdram_wait_q[31:0];
      SYSCTRL_PERF_SDRAM_WAIT_HI_OFFSET: s_ribp_rdata_d = s_perf_sdram_wait_q[63:32];
      SYSCTRL_PERF_PSRAM_WAIT_LO_OFFSET: s_ribp_rdata_d = s_perf_psram_wait_q[31:0];
      SYSCTRL_PERF_PSRAM_WAIT_HI_OFFSET: s_ribp_rdata_d = s_perf_psram_wait_q[63:32];
      SYSCTRL_PERF_FLASH_WAIT_LO_OFFSET: s_ribp_rdata_d = s_perf_flash_wait_q[31:0];
      SYSCTRL_PERF_FLASH_WAIT_HI_OFFSET: s_ribp_rdata_d = s_perf_flash_wait_q[63:32];
      SYSCTRL_TEST_STATUS_OFFSET:         s_ribp_rdata_d = {
          s_test_done_q, 15'd0, s_test_code_q, 7'd0, s_test_pass_q
      };
      SYSCTRL_RTC_WAKE_STATUS_OFFSET:     s_ribp_rdata_d = {
          30'd0, s_rtc_wake_seen_q, s_rtc_wake_sync
      };
      default:                            s_ribp_rdata_d = s_ribp_rdata_q;
    endcase
      // verilog_format: on
  end
  dffer #(
      .DATA_WIDTH(32)
  ) u_ribp_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_ribp_rdata_en),
      .dat_i  (s_ribp_rdata_d),
      .dat_o  (s_ribp_rdata_q)
  );

endmodule
