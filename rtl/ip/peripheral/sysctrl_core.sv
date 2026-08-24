// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "user_extensions.svh"
`include "rib_defs.svh"
`include "sysctrl_define.svh"

module sysctrl_core (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic         clk_i,
    input  logic         rst_n_i,
    input  logic         write_valid_i,
    input  logic [7:0]   write_offset_i,
    input  logic [31:0]  write_data_i,
    input  logic [3:0]   write_strobe_i,
    input  logic [7:0]   read_offset_i,
    input  logic         fault_valid_i,
    input  logic [31:0]  fault_addr_i,
    input  logic [3:0]   fault_wstrb_i,
    input  logic         fault_reserved_i,
    sysctrl_if.dut       sysctrl,
    pll_ctrl_if.sysctrl  pll_ctrl,
    output logic         read_data_valid_o,
    output logic [31:0]  read_data_o
    // verilog_format: on
);

  typedef logic [7:0] sysctrl_offset_t;

  localparam sysctrl_offset_t CoreSel = sysctrl_offset_t'(`APB4_SYSCTRL__CORESEL);
  localparam sysctrl_offset_t IpSel = sysctrl_offset_t'(`APB4_SYSCTRL__IPSEL);
  localparam sysctrl_offset_t PllCfg = sysctrl_offset_t'(`APB4_SYSCTRL__PLL_CFG);
  localparam sysctrl_offset_t PllCmd = sysctrl_offset_t'(`APB4_SYSCTRL__PLL_CMD);
  localparam sysctrl_offset_t FaultStatus = sysctrl_offset_t'(`APB4_SYSCTRL__FAULT_STATUS);
  localparam sysctrl_offset_t FaultAddr = sysctrl_offset_t'(`APB4_SYSCTRL__FAULT_ADDR);
  localparam sysctrl_offset_t FaultCount = sysctrl_offset_t'(`APB4_SYSCTRL__FAULT_COUNT);
  localparam sysctrl_offset_t PllStatus = sysctrl_offset_t'(`APB4_SYSCTRL__PLL_STATUS);
  localparam sysctrl_offset_t UserCoreReset = sysctrl_offset_t'(`APB4_SYSCTRL__USER_CORE_RESET);
  localparam sysctrl_offset_t UserCoreStatus = sysctrl_offset_t'(`APB4_SYSCTRL__USER_CORE_STATUS);
  localparam sysctrl_offset_t FaultMaster = sysctrl_offset_t'(`APB4_SYSCTRL__FAULT_MASTER);
  localparam sysctrl_offset_t FaultDetail = sysctrl_offset_t'(`APB4_SYSCTRL__FAULT_DETAIL);
  localparam sysctrl_offset_t PerfCtrl = sysctrl_offset_t'(`APB4_SYSCTRL__PERF_CTRL);
  localparam sysctrl_offset_t PerfMgmtWaitLo = sysctrl_offset_t'(`APB4_SYSCTRL__PERF_MGMT_WAIT_LO);
  localparam sysctrl_offset_t PerfMgmtWaitHi = sysctrl_offset_t'(`APB4_SYSCTRL__PERF_MGMT_WAIT_HI);
  localparam sysctrl_offset_t PerfUserWaitLo = sysctrl_offset_t'(`APB4_SYSCTRL__PERF_USER_WAIT_LO);
  localparam sysctrl_offset_t PerfUserWaitHi = sysctrl_offset_t'(`APB4_SYSCTRL__PERF_USER_WAIT_HI);
  localparam sysctrl_offset_t PerfDmaWaitLo = sysctrl_offset_t'(`APB4_SYSCTRL__PERF_DMA_WAIT_LO);
  localparam sysctrl_offset_t PerfDmaWaitHi = sysctrl_offset_t'(`APB4_SYSCTRL__PERF_DMA_WAIT_HI);
  localparam sysctrl_offset_t PerfSdio0WaitLo =
      sysctrl_offset_t'(`APB4_SYSCTRL__PERF_SDIO0_WAIT_LO);
  localparam sysctrl_offset_t PerfSdio0WaitHi =
      sysctrl_offset_t'(`APB4_SYSCTRL__PERF_SDIO0_WAIT_HI);
  localparam sysctrl_offset_t PerfSdio1WaitLo =
      sysctrl_offset_t'(`APB4_SYSCTRL__PERF_SDIO1_WAIT_LO);
  localparam sysctrl_offset_t PerfSdio1WaitHi =
      sysctrl_offset_t'(`APB4_SYSCTRL__PERF_SDIO1_WAIT_HI);
  localparam sysctrl_offset_t PerfUsb2WaitLo = sysctrl_offset_t'(`APB4_SYSCTRL__PERF_USB2_WAIT_LO);
  localparam sysctrl_offset_t PerfUsb2WaitHi = sysctrl_offset_t'(`APB4_SYSCTRL__PERF_USB2_WAIT_HI);
  localparam sysctrl_offset_t PerfApb4PeriphWaitLo =
      sysctrl_offset_t'(`APB4_SYSCTRL__PERF_APB4_PERIPH_WAIT_LO);
  localparam sysctrl_offset_t PerfApb4PeriphWaitHi =
      sysctrl_offset_t'(`APB4_SYSCTRL__PERF_APB4_PERIPH_WAIT_HI);
  localparam sysctrl_offset_t PerfApb4SystemWaitLo =
      sysctrl_offset_t'(`APB4_SYSCTRL__PERF_APB4_SYSTEM_WAIT_LO);
  localparam sysctrl_offset_t PerfApb4SystemWaitHi =
      sysctrl_offset_t'(`APB4_SYSCTRL__PERF_APB4_SYSTEM_WAIT_HI);
  localparam sysctrl_offset_t PerfSdramWaitLo =
      sysctrl_offset_t'(`APB4_SYSCTRL__PERF_SDRAM_WAIT_LO);
  localparam sysctrl_offset_t PerfSdramWaitHi =
      sysctrl_offset_t'(`APB4_SYSCTRL__PERF_SDRAM_WAIT_HI);
  localparam sysctrl_offset_t PerfPsramWaitLo =
      sysctrl_offset_t'(`APB4_SYSCTRL__PERF_PSRAM_WAIT_LO);
  localparam sysctrl_offset_t PerfPsramWaitHi =
      sysctrl_offset_t'(`APB4_SYSCTRL__PERF_PSRAM_WAIT_HI);
  localparam sysctrl_offset_t PerfFlashWaitLo =
      sysctrl_offset_t'(`APB4_SYSCTRL__PERF_FLASH_WAIT_LO);
  localparam sysctrl_offset_t PerfFlashWaitHi =
      sysctrl_offset_t'(`APB4_SYSCTRL__PERF_FLASH_WAIT_HI);
  localparam sysctrl_offset_t TestStatus = sysctrl_offset_t'(`APB4_SYSCTRL__TEST_STATUS);
  localparam sysctrl_offset_t RtcWakeStatus = sysctrl_offset_t'(`APB4_SYSCTRL__RTC_WAKE_STATUS);

  logic [`USER_CORESEL_WIDTH-1:0] s_sysctrl_coresel_d, s_sysctrl_coresel_q;
  logic [`USER_CORE_COUNT-1:0] s_user_reset_d, s_user_reset_q;
  logic s_user_running_d, s_user_running_q;
  logic s_user_draining_d, s_user_draining_q;
  logic s_user_config_err_d, s_user_config_err_q;
  logic [`USER_IPSEL_WIDTH-1:0] s_sysctrl_ipsel_d, s_sysctrl_ipsel_q;
  logic [2:0] s_pll_cfg_d, s_pll_cfg_q;
  logic s_pll_req_valid_d, s_pll_req_valid_q;
  logic s_pll_busy_d, s_pll_busy_q;
  logic s_pll_err_d, s_pll_err_q;
  logic [1:0] s_pll_err_reason_d, s_pll_err_reason_q;
  logic [2:0] s_pll_active_sel_d, s_pll_active_sel_q;
  logic s_pll_active_valid_d, s_pll_active_valid_q;
  logic s_pll_safe_clk_d, s_pll_safe_clk_q;
  logic s_pll_lock_d, s_pll_lock_q;
  logic s_fault_pending_d, s_fault_pending_q;
  logic s_fault_write_d, s_fault_write_q;
  logic [2:0] s_fault_reason_d, s_fault_reason_q;
  logic [2:0] s_fault_detail_d, s_fault_detail_q;
  logic [31:0] s_fault_addr_d, s_fault_addr_q;
  logic [31:0] s_fault_count_d, s_fault_count_q;
  logic [2:0] s_fault_master_d, s_fault_master_q;
  logic s_perf_en_d, s_perf_en_q;
  logic [63:0] s_perf_mgmt_wait_d, s_perf_mgmt_wait_q;
  logic [63:0] s_perf_user_wait_d, s_perf_user_wait_q;
  logic [63:0] s_perf_dma_wait_d, s_perf_dma_wait_q;
  logic [63:0] s_perf_sdio0_wait_d, s_perf_sdio0_wait_q;
  logic [63:0] s_perf_sdio1_wait_d, s_perf_sdio1_wait_q;
  logic [63:0] s_perf_usb2_wait_d, s_perf_usb2_wait_q;
  logic [63:0] s_perf_apb4_periph_wait_d, s_perf_apb4_periph_wait_q;
  logic [63:0] s_perf_apb4_system_wait_d, s_perf_apb4_system_wait_q;
  logic [63:0] s_perf_sdram_wait_d, s_perf_sdram_wait_q;
  logic [63:0] s_perf_psram_wait_d, s_perf_psram_wait_q;
  logic [63:0] s_perf_flash_wait_d, s_perf_flash_wait_q;
  logic s_test_done_d, s_test_done_q;
  logic s_test_pass_d, s_test_pass_q;
  logic [7:0] s_test_code_d, s_test_code_q;
  logic s_rtc_wake_seen_d, s_rtc_wake_seen_q;
  logic        s_rtc_wake_sync;
  logic        s_core_sel_write_valid;
  logic        s_core_sel_write_en;
  logic        s_user_reset_write_en;
  logic        s_user_reset_write_legal;
  logic        s_user_config_err_clear;
  logic        s_pll_cfg_write_en;
  logic        s_pll_apply;
  logic        s_pll_clear_err;
  logic        s_pll_rsp_accept;
  logic        s_fault_stat_clear;
  logic        s_perf_write_en;
  logic        s_perf_clear;
  logic        s_perf_snapshot;
  logic        s_test_stat_write;
  logic        s_rtc_wake_clear;
  logic [14:0] unused_write_data;

  // TEST_STATUS[30:16] and the same bits on every other register are reserved.
  assign unused_write_data         = write_data_i[30:16];

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

  assign s_core_sel_write_valid = write_data_i[`USER_CORESEL_WIDTH-1:0] < `USER_CORE_COUNT;
  assign s_core_sel_write_en = write_valid_i && (write_offset_i == CoreSel) &&
                               write_strobe_i[0] && s_core_sel_write_valid &&
                               (&s_user_reset_q) && sysctrl.user_bus_idle_i && !s_user_running_q;
  assign s_user_reset_write_en = write_valid_i && (write_offset_i == UserCoreReset) &&
                                 write_strobe_i[0];
  assign s_user_reset_write_legal = (&write_data_i[`USER_CORE_COUNT-1:0]) ||
      ((s_sysctrl_coresel_q < `USER_CORE_COUNT) &&
       ((~write_data_i[`USER_CORE_COUNT-1:0]) ==
        ({{(`USER_CORE_COUNT - 1){1'b0}}, 1'b1} << s_sysctrl_coresel_q)));
  assign s_user_config_err_clear = write_valid_i && (write_offset_i == UserCoreStatus) &&
                                   write_strobe_i[1] && write_data_i[11];

  always_comb begin
    s_sysctrl_coresel_d = s_sysctrl_coresel_q;
    s_user_reset_d      = s_user_reset_q;
    s_user_running_d    = s_user_running_q;
    s_user_draining_d   = s_user_draining_q;
    s_user_config_err_d = s_user_config_err_q;
    if (s_core_sel_write_en) begin
      s_sysctrl_coresel_d = write_data_i[`USER_CORESEL_WIDTH-1:0];
    end
    if (s_user_config_err_clear) begin
      s_user_config_err_d = 1'b0;
    end
    if (write_valid_i && (write_offset_i == CoreSel) && !s_core_sel_write_en) begin
      s_user_config_err_d = 1'b1;
    end
    if (s_user_reset_write_en) begin
      if (!s_user_reset_write_legal) begin
        s_user_config_err_d = 1'b1;
      end else if (&write_data_i[`USER_CORE_COUNT-1:0]) begin
        s_user_running_d = 1'b0;
        if (sysctrl.user_bus_idle_i) begin
          s_user_reset_d    = write_data_i[`USER_CORE_COUNT-1:0];
          s_user_draining_d = 1'b0;
        end else begin
          s_user_draining_d = 1'b1;
        end
      end else if (sysctrl.user_bus_idle_i && (&s_user_reset_q) && !s_user_running_q) begin
        s_user_reset_d    = write_data_i[`USER_CORE_COUNT-1:0];
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

  assign s_pll_cfg_write_en = write_valid_i && (write_offset_i == PllCfg) && write_strobe_i[0];
  assign s_pll_apply = write_valid_i && (write_offset_i == PllCmd) && write_strobe_i[0] &&
                       write_data_i[`APB4_SYSCTRL__PLL_CMD_APPLY];
  assign s_pll_clear_err = write_valid_i && (write_offset_i == PllCmd) && write_strobe_i[0] &&
                           write_data_i[`APB4_SYSCTRL__PLL_CMD_CLEAR_ERROR];
  assign s_pll_rsp_accept = pll_ctrl.rsp_valid_i;

  always_comb begin
    s_sysctrl_ipsel_d    = s_sysctrl_ipsel_q;
    s_pll_cfg_d          = s_pll_cfg_q;
    s_pll_req_valid_d    = s_pll_req_valid_q;
    s_pll_busy_d         = s_pll_busy_q;
    s_pll_err_d          = s_pll_err_q;
    s_pll_err_reason_d   = s_pll_err_reason_q;
    s_pll_active_sel_d   = s_pll_active_sel_q;
    s_pll_active_valid_d = s_pll_active_valid_q;
    s_pll_safe_clk_d     = s_pll_safe_clk_q;
    s_pll_lock_d         = s_pll_lock_q;
    if (write_valid_i && (write_offset_i == IpSel)) begin
      s_sysctrl_ipsel_d = write_data_i[`USER_IPSEL_WIDTH-1:0];
    end
    if (s_pll_cfg_write_en) begin
      s_pll_cfg_d = write_data_i[2:0];
    end
    if (s_pll_req_valid_q && pll_ctrl.req_ready_i) begin
      s_pll_req_valid_d = 1'b0;
    end
    if (s_pll_apply && !s_pll_busy_q && !s_pll_req_valid_q) begin
      s_pll_req_valid_d = 1'b1;
      s_pll_busy_d      = 1'b1;
    end
    if (s_pll_rsp_accept) begin
      s_pll_busy_d         = 1'b0;
      s_pll_active_sel_d   = pll_ctrl.rsp_active_sel_i;
      s_pll_active_valid_d = pll_ctrl.rsp_active_valid_i;
      s_pll_safe_clk_d     = pll_ctrl.rsp_safe_clk_i;
      s_pll_lock_d         = pll_ctrl.rsp_pll_lock_i;
    end
    if (s_pll_clear_err) begin
      s_pll_err_d        = 1'b0;
      s_pll_err_reason_d = 2'd0;
    end
    if (s_pll_apply && (s_pll_busy_q || s_pll_req_valid_q)) begin
      s_pll_err_d        = 1'b1;
      s_pll_err_reason_d = 2'd3;
    end
    if (s_pll_rsp_accept && (|pll_ctrl.rsp_error_i)) begin
      s_pll_err_d        = 1'b1;
      s_pll_err_reason_d = pll_ctrl.rsp_error_i;
    end
  end

  assign s_fault_stat_clear = write_valid_i && (write_offset_i == FaultStatus) &&
                              write_strobe_i[0] &&
                              write_data_i[`APB4_SYSCTRL__FAULT_STATUS_PENDING];
  always_comb begin
    s_fault_pending_d = s_fault_pending_q;
    s_fault_write_d   = s_fault_write_q;
    s_fault_reason_d  = s_fault_reason_q;
    s_fault_detail_d  = s_fault_detail_q;
    s_fault_addr_d    = s_fault_addr_q;
    s_fault_count_d   = s_fault_count_q;
    s_fault_master_d  = s_fault_master_q;
    if (s_fault_stat_clear) begin
      s_fault_pending_d = 1'b0;
    end
    if (fault_valid_i) begin
      s_fault_pending_d = 1'b1;
      if (!s_fault_pending_q || s_fault_stat_clear) begin
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
        s_fault_addr_d   = fault_addr_i;
        s_fault_master_d = sysctrl.fault_master_i;
      end
      if (!(&s_fault_count_q)) begin
        s_fault_count_d = s_fault_count_q + 32'd1;
      end
    end
  end

  assign s_perf_write_en = write_valid_i && (write_offset_i == PerfCtrl) && write_strobe_i[0];
  assign s_perf_clear    = s_perf_write_en && write_data_i[`APB4_SYSCTRL__PERF_CTRL_CLEAR];
  assign s_perf_snapshot = s_perf_write_en && write_data_i[`APB4_SYSCTRL__PERF_CTRL_SNAPSHOT];
  always_comb begin
    s_perf_en_d               = s_perf_en_q;
    s_perf_mgmt_wait_d        = s_perf_mgmt_wait_q;
    s_perf_user_wait_d        = s_perf_user_wait_q;
    s_perf_dma_wait_d         = s_perf_dma_wait_q;
    s_perf_sdio0_wait_d       = s_perf_sdio0_wait_q;
    s_perf_sdio1_wait_d       = s_perf_sdio1_wait_q;
    s_perf_usb2_wait_d        = s_perf_usb2_wait_q;
    s_perf_apb4_periph_wait_d = s_perf_apb4_periph_wait_q;
    s_perf_apb4_system_wait_d = s_perf_apb4_system_wait_q;
    s_perf_sdram_wait_d       = s_perf_sdram_wait_q;
    s_perf_psram_wait_d       = s_perf_psram_wait_q;
    s_perf_flash_wait_d       = s_perf_flash_wait_q;
    if (s_perf_write_en) begin
      s_perf_en_d = write_data_i[`APB4_SYSCTRL__PERF_CTRL_ENABLE];
    end
    if (s_perf_snapshot) begin
      s_perf_mgmt_wait_d        = sysctrl.perf_mgmt_wait_i;
      s_perf_user_wait_d        = sysctrl.perf_user_wait_i;
      s_perf_dma_wait_d         = sysctrl.perf_dma_wait_i;
      s_perf_sdio0_wait_d       = sysctrl.perf_sdio0_wait_i;
      s_perf_sdio1_wait_d       = sysctrl.perf_sdio1_wait_i;
      s_perf_usb2_wait_d        = sysctrl.perf_usb2_wait_i;
      s_perf_apb4_periph_wait_d = sysctrl.perf_apb4_periph_wait_i;
      s_perf_apb4_system_wait_d = sysctrl.perf_apb4_system_wait_i;
      s_perf_sdram_wait_d       = sysctrl.perf_sdram_wait_i;
      s_perf_psram_wait_d       = sysctrl.perf_psram_wait_i;
      s_perf_flash_wait_d       = sysctrl.perf_flash_wait_i;
    end
  end

  assign s_test_stat_write = write_valid_i && (write_offset_i == TestStatus) &&
                             (write_strobe_i == 4'hF) &&
                             write_data_i[`APB4_SYSCTRL__TEST_STATUS_VALID] && !s_test_done_q;
  assign s_rtc_wake_clear = write_valid_i && (write_offset_i == RtcWakeStatus) &&
                            write_strobe_i[0] &&
                            write_data_i[`APB4_SYSCTRL__RTC_WAKE_STATUS_SEEN];
  always_comb begin
    s_test_done_d     = s_test_done_q;
    s_test_pass_d     = s_test_pass_q;
    s_test_code_d     = s_test_code_q;
    s_rtc_wake_seen_d = s_rtc_wake_seen_q;
    if (s_test_stat_write) begin
      s_test_done_d = 1'b1;
      s_test_pass_d = write_data_i[`APB4_SYSCTRL__TEST_STATUS_PASS];
      s_test_code_d = write_data_i[`APB4_SYSCTRL__TEST_STATUS_CODE+:8];
    end
    if (s_rtc_wake_clear) begin
      s_rtc_wake_seen_d = 1'b0;
    end
    if (s_rtc_wake_sync) begin
      s_rtc_wake_seen_d = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_sysctrl_coresel_q       <= '0;
      s_user_reset_q            <= '1;
      s_user_running_q          <= 1'b0;
      s_user_draining_q         <= 1'b0;
      s_user_config_err_q       <= 1'b0;
      s_sysctrl_ipsel_q         <= '0;
      s_pll_cfg_q               <= '0;
      s_pll_req_valid_q         <= 1'b0;
      s_pll_busy_q              <= 1'b0;
      s_pll_err_q               <= 1'b0;
      s_pll_err_reason_q        <= '0;
      s_pll_active_sel_q        <= '0;
      s_pll_active_valid_q      <= 1'b0;
      s_pll_safe_clk_q          <= 1'b1;
      s_pll_lock_q              <= 1'b0;
      s_fault_pending_q         <= 1'b0;
      s_fault_write_q           <= 1'b0;
      s_fault_reason_q          <= '0;
      s_fault_detail_q          <= '0;
      s_fault_addr_q            <= '0;
      s_fault_count_q           <= '0;
      s_fault_master_q          <= '0;
      s_perf_en_q               <= 1'b0;
      s_perf_mgmt_wait_q        <= '0;
      s_perf_user_wait_q        <= '0;
      s_perf_dma_wait_q         <= '0;
      s_perf_sdio0_wait_q       <= '0;
      s_perf_sdio1_wait_q       <= '0;
      s_perf_usb2_wait_q        <= '0;
      s_perf_apb4_periph_wait_q <= '0;
      s_perf_apb4_system_wait_q <= '0;
      s_perf_sdram_wait_q       <= '0;
      s_perf_psram_wait_q       <= '0;
      s_perf_flash_wait_q       <= '0;
      s_test_done_q             <= 1'b0;
      s_test_pass_q             <= 1'b0;
      s_test_code_q             <= '0;
      s_rtc_wake_seen_q         <= 1'b0;
    end else begin
      s_sysctrl_coresel_q       <= s_sysctrl_coresel_d;
      s_user_reset_q            <= s_user_reset_d;
      s_user_running_q          <= s_user_running_d;
      s_user_draining_q         <= s_user_draining_d;
      s_user_config_err_q       <= s_user_config_err_d;
      s_sysctrl_ipsel_q         <= s_sysctrl_ipsel_d;
      s_pll_cfg_q               <= s_pll_cfg_d;
      s_pll_req_valid_q         <= s_pll_req_valid_d;
      s_pll_busy_q              <= s_pll_busy_d;
      s_pll_err_q               <= s_pll_err_d;
      s_pll_err_reason_q        <= s_pll_err_reason_d;
      s_pll_active_sel_q        <= s_pll_active_sel_d;
      s_pll_active_valid_q      <= s_pll_active_valid_d;
      s_pll_safe_clk_q          <= s_pll_safe_clk_d;
      s_pll_lock_q              <= s_pll_lock_d;
      s_fault_pending_q         <= s_fault_pending_d;
      s_fault_write_q           <= s_fault_write_d;
      s_fault_reason_q          <= s_fault_reason_d;
      s_fault_detail_q          <= s_fault_detail_d;
      s_fault_addr_q            <= s_fault_addr_d;
      s_fault_count_q           <= s_fault_count_d;
      s_fault_master_q          <= s_fault_master_d;
      s_perf_en_q               <= s_perf_en_d;
      s_perf_mgmt_wait_q        <= s_perf_mgmt_wait_d;
      s_perf_user_wait_q        <= s_perf_user_wait_d;
      s_perf_dma_wait_q         <= s_perf_dma_wait_d;
      s_perf_sdio0_wait_q       <= s_perf_sdio0_wait_d;
      s_perf_sdio1_wait_q       <= s_perf_sdio1_wait_d;
      s_perf_usb2_wait_q        <= s_perf_usb2_wait_d;
      s_perf_apb4_periph_wait_q <= s_perf_apb4_periph_wait_d;
      s_perf_apb4_system_wait_q <= s_perf_apb4_system_wait_d;
      s_perf_sdram_wait_q       <= s_perf_sdram_wait_d;
      s_perf_psram_wait_q       <= s_perf_psram_wait_d;
      s_perf_flash_wait_q       <= s_perf_flash_wait_d;
      s_test_done_q             <= s_test_done_d;
      s_test_pass_q             <= s_test_pass_d;
      s_test_code_q             <= s_test_code_d;
      s_rtc_wake_seen_q         <= s_rtc_wake_seen_d;
    end
  end

  always_comb begin
    read_data_valid_o = 1'b1;
    read_data_o       = '0;
    unique case (read_offset_i)
      CoreSel: read_data_o = {{(32 - `USER_CORESEL_WIDTH) {1'b0}}, s_sysctrl_coresel_q};
      IpSel: read_data_o = {{(32 - `USER_IPSEL_WIDTH) {1'b0}}, s_sysctrl_ipsel_q};
      PllCfg: read_data_o = {29'd0, s_pll_cfg_q};
      FaultStatus: read_data_o = {27'd0, s_fault_reason_q, s_fault_write_q, s_fault_pending_q};
      FaultAddr: read_data_o = s_fault_addr_q;
      FaultCount: read_data_o = s_fault_count_q;
      PllStatus:
      read_data_o = {
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
      UserCoreReset: read_data_o = {{(32 - `USER_CORE_COUNT) {1'b0}}, s_user_reset_q};
      UserCoreStatus:
      read_data_o = {
        20'd0,
        s_user_config_err_q,
        s_user_draining_q,
        sysctrl.user_bus_idle_i,
        s_user_running_q,
        {(8 - `USER_CORESEL_WIDTH) {1'b0}},
        s_sysctrl_coresel_q
      };
      FaultMaster: read_data_o = {29'd0, s_fault_master_q};
      FaultDetail: read_data_o = {29'd0, s_fault_detail_q};
      PerfCtrl: read_data_o = {31'd0, s_perf_en_q};
      PerfMgmtWaitLo: read_data_o = s_perf_mgmt_wait_q[31:0];
      PerfMgmtWaitHi: read_data_o = s_perf_mgmt_wait_q[63:32];
      PerfUserWaitLo: read_data_o = s_perf_user_wait_q[31:0];
      PerfUserWaitHi: read_data_o = s_perf_user_wait_q[63:32];
      PerfDmaWaitLo: read_data_o = s_perf_dma_wait_q[31:0];
      PerfDmaWaitHi: read_data_o = s_perf_dma_wait_q[63:32];
      PerfSdio0WaitLo: read_data_o = s_perf_sdio0_wait_q[31:0];
      PerfSdio0WaitHi: read_data_o = s_perf_sdio0_wait_q[63:32];
      PerfSdio1WaitLo: read_data_o = s_perf_sdio1_wait_q[31:0];
      PerfSdio1WaitHi: read_data_o = s_perf_sdio1_wait_q[63:32];
      PerfUsb2WaitLo: read_data_o = s_perf_usb2_wait_q[31:0];
      PerfUsb2WaitHi: read_data_o = s_perf_usb2_wait_q[63:32];
      PerfApb4PeriphWaitLo: read_data_o = s_perf_apb4_periph_wait_q[31:0];
      PerfApb4PeriphWaitHi: read_data_o = s_perf_apb4_periph_wait_q[63:32];
      PerfApb4SystemWaitLo: read_data_o = s_perf_apb4_system_wait_q[31:0];
      PerfApb4SystemWaitHi: read_data_o = s_perf_apb4_system_wait_q[63:32];
      PerfSdramWaitLo: read_data_o = s_perf_sdram_wait_q[31:0];
      PerfSdramWaitHi: read_data_o = s_perf_sdram_wait_q[63:32];
      PerfPsramWaitLo: read_data_o = s_perf_psram_wait_q[31:0];
      PerfPsramWaitHi: read_data_o = s_perf_psram_wait_q[63:32];
      PerfFlashWaitLo: read_data_o = s_perf_flash_wait_q[31:0];
      PerfFlashWaitHi: read_data_o = s_perf_flash_wait_q[63:32];
      TestStatus: read_data_o = {s_test_done_q, 15'd0, s_test_code_q, 7'd0, s_test_pass_q};
      RtcWakeStatus: read_data_o = {30'd0, s_rtc_wake_seen_q, s_rtc_wake_sync};
      default: begin
        read_data_valid_o = 1'b0;
      end
    endcase
  end

endmodule
