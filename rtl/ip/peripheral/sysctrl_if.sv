// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "user_extensions.svh"

interface sysctrl_if ();
  logic [`USER_CORESEL_WIDTH-1:0] core_sel_o;
  logic [   `USER_CORE_COUNT-1:0] core_reset_o;
  logic                           user_bus_enable_o;
  logic                           user_bus_idle_i;
  logic                           fault_access_i;
  logic [                    2:0] fault_master_i;
  logic [                    2:0] fault_code_i;
  logic                           perf_enable_o;
  logic                           perf_clear_o;
  logic [                   63:0] perf_mgmt_wait_i;
  logic [                   63:0] perf_user_wait_i;
  logic [                   63:0] perf_dma_wait_i;
  logic [                   63:0] perf_sdio0_wait_i;
  logic [                   63:0] perf_sdio1_wait_i;
  logic [                   63:0] perf_apb4_periph_wait_i;
  logic [                   63:0] perf_apb4_system_wait_i;
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
      input perf_sdio0_wait_i,
      input perf_sdio1_wait_i,
      input perf_apb4_periph_wait_i,
      input perf_apb4_system_wait_i,
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
