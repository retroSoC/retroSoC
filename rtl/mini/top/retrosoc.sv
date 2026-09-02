// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"
`include "user_extensions.svh"
`include "soc_irq_config.svh"

module retrosoc (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic        clk_aon_i,
    input  logic        rst_aon_n_i,
    input  logic        clk_lp_i,
    input  logic        rst_lp_n_i,
    input  logic        clk_hp_i,
    input  logic        clk_hp_core_i,
    input  logic        rst_hp_n_i,
    input  logic        clk_pclk_i,
    input  logic        rst_pclk_n_i,
    input  logic        clk_mem_i,
    input  logic        rst_mem_n_i,
    input  logic [1:0]  mem_pad_mode_i,
    input  logic        mem_pad_lock_i,
    input  logic        hp_block_i,
    input  logic        clk_aud_i,
    input  logic        rst_aud_n_i,
    input  logic        clk_ulpi_i,
    input  logic        clkdiv4_i,
    input  logic        timebase_tick_i,
    pll_ctrl_if.sysctrl pll_ctrl,
    clock_ctrl_if.sysctrl clock_ctrl,
    gpio_if.soc_pad      gpio,
    input  logic         uart_rx_i,
    output logic         uart_tx_o,
    input  logic         uart1_rx_i,
    output logic         uart1_tx_o,
    xpi_if.dut           xpi,
    sdram_if.dut         sdram,
    sdio_if.dut          sdio1,
    usb2_ulpi_if.dut     usb2,
    input  logic         jtag_tck_i,
    input  logic         jtag_tms_i,
    input  logic         jtag_tdi_i,
    input  logic         jtag_trst_n_i,
    output logic         jtag_tdo_o,
    output logic         wdg_reset_req_o,
    output logic         test_done_o,
    output logic         test_pass_o,
    output logic [7:0]   test_code_o,
    output logic         hp_idle_o,
    output logic         pclk_idle_o
    // verilog_format: on
);

  // verilog_format: off -- preserve reviewed column alignment
  // Generated fabric links use the common 32-bit AXI4 contract.
  `include "soc_fabric_interfaces.svh"
  apb4_if u_sdram_cfg_if (.pclk(clk_mem_i), .presetn(rst_mem_n_i));
  apb4_if u_sram_cfg_if (.pclk(clk_hp_i), .presetn(rst_hp_n_i));
  apb4_if u_sdram_cfg_pclk_if (.pclk(clk_pclk_i), .presetn(rst_pclk_n_i));
  apb4_if u_sram_cfg_pclk_if (.pclk(clk_pclk_i), .presetn(rst_pclk_n_i));
  apb4_if u_fabric_monitor_pclk_if (.pclk(clk_pclk_i), .presetn(rst_pclk_n_i));
  apb4_if u_fabric_monitor_hp_if (.pclk(clk_hp_i), .presetn(rst_hp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_cfg_pclk_axi4_if (.aclk(clk_pclk_i), .aresetn(rst_pclk_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_system_pclk_axi4_if (.aclk(clk_pclk_i), .aresetn(rst_pclk_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_sram_axi4_if (.aclk(clk_lp_i), .aresetn(rst_lp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_sdram_axi4_if (.aclk(clk_lp_i), .aresetn(rst_lp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_psram_axi4_if (.aclk(clk_lp_i), .aresetn(rst_lp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_xpi_axi4_if (.aclk(clk_lp_i), .aresetn(rst_lp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_spisd_axi4_if (.aclk(clk_pclk_i), .aresetn(rst_pclk_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_opipsram_axi4_if (.aclk(clk_lp_i), .aresetn(rst_lp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(3), .USER_WIDTH(1))
      u_ext_h_wide_axi4_if (.aclk(clk_pclk_i), .aresetn(rst_pclk_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(3), .USER_WIDTH(1))
      u_jpeg_wide_axi4_if (.aclk(clk_pclk_i), .aresetn(rst_pclk_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(3), .USER_WIDTH(1))
      u_hp_icache_axi4_if (.aclk(clk_hp_i), .aresetn(rst_hp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(3), .USER_WIDTH(1))
      u_hp_dcache_axi4_if (.aclk(clk_hp_i), .aresetn(rst_hp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(3), .USER_WIDTH(1))
      u_hp_mmio_wide_axi4_if (.aclk(clk_hp_i), .aresetn(rst_hp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_hp_mmio_hp_axi4_if (.aclk(clk_hp_i), .aresetn(rst_hp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_hp_mmio_gated_axi4_if (.aclk(clk_hp_i), .aresetn(rst_hp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_hp_mmio_lp_axi4_if (.aclk(clk_lp_i), .aresetn(rst_lp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(6), .USER_WIDTH(1))
      u_data_sram_axi4_if (.aclk(clk_hp_i), .aresetn(rst_hp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_retired_data_sram_axi4_if (.aclk(clk_lp_i), .aresetn(rst_lp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_data_sdram_axi4_if (.aclk(clk_mem_i), .aresetn(rst_mem_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_retired_data_sdram_axi4_if (.aclk(clk_lp_i), .aresetn(rst_lp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_data_qpi_axi4_if (.aclk(clk_mem_i), .aresetn(rst_mem_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_data_opi_axi4_if (.aclk(clk_mem_i), .aresetn(rst_mem_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_data_xpi_axi4_if (.aclk(clk_mem_i), .aresetn(rst_mem_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_retired_data_qpi_axi4_if (.aclk(clk_lp_i), .aresetn(rst_lp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_retired_data_opi_axi4_if (.aclk(clk_lp_i), .aresetn(rst_lp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_retired_data_xpi_axi4_if (.aclk(clk_lp_i), .aresetn(rst_lp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_idle_axi4_if (.aclk(clk_lp_i), .aresetn(rst_lp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_mgmt_control_axi4_if (.aclk(clk_lp_i), .aresetn(rst_lp_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_mgmt_data_axi4_if (.aclk(clk_lp_i), .aresetn(rst_lp_n_i));
  user_gpio_if u_user_gpio_if ();
  // ip interface
  gpio_if     u_gpio_if     ();
  uart_if     u_uart0_if    ();
  uart_if     u_uart1_if    ();
  psram_if    u_psram_if    ();
  psram_if    u_psram_raw_if ();
  spi_if      u_spisd_if    ();
  i2c_if      u_i2c0_if     ();
  i2s_if      u_i2s_if      ();
  ws2812_if   u_ws2812_if   ();
  sysctrl_if  u_sysctrl_if  ();
  dvp_if      u_dvp_if      ();
  sdio_if     u_sdio0_if    ();
  opipsram_if u_opipsram_if ();
  opipsram_if u_opipsram_raw_if ();
  i2c_if      u_i2c1_if     ();
  pwm_if      u_pwm_if      ();
  ps2_if      u_ps2_if      ();
  // verilog_format: on

  logic                                  s_mgmt_debug_halted;
  logic [     `SOC_IRQ_VECTOR_WIDTH-1:0] s_irq;
  logic [`SOC_IRQ_APB4_PERIPH_WIDTH-1:0] s_apb4_periph_irq;
  logic [`SOC_IRQ_APB4_SYSTEM_WIDTH-1:0] s_apb4_system_irq;
  logic                                  s_bus_fault_valid;
  logic [                          31:0] s_bus_fault_addr;
  logic [                           3:0] s_bus_fault_wstrb;
  logic                                  s_bus_fault_reserved;
  logic                                  s_bus_fault_access;
  logic [                           2:0] s_bus_fault_master;
  logic [                           2:0] s_bus_fault_code;
  logic                                  s_perf_en;
  logic                                  s_perf_clear;
  logic [                          63:0] s_perf_mgmt_wait;
  logic [                          63:0] s_perf_user_wait;
  logic [                          63:0] s_perf_dma_wait;
  logic [                          63:0] s_perf_sdio0_wait;
  logic [                          63:0] s_perf_sdio1_wait;
  logic [                          63:0] s_perf_usb2_wait;
  logic [                          63:0] s_perf_apb4_periph_wait;
  logic [                          63:0] s_perf_apb4_system_wait;
  logic [                          63:0] s_perf_sdram_wait;
  logic [                          63:0] s_perf_psram_wait;
  logic [                          63:0] s_perf_flash_wait;
  logic [                          63:0] s_perf_opipsram_wait;
`ifndef MINI_PRODUCT
  logic [`SOC_IRQ_VECTOR_WIDTH-1:0] s_user_irq;
`else
  logic s_unused_product_legacy;
`endif
  logic             s_rtc_wake;
  logic             s_hp_jtag_tdo;
  logic             s_hp_debug_reset_req;
  logic             s_lp_jtag_tdo;
  logic             s_debug_hp_sel_jtag;
  logic [63:0]      s_hp_time;
  logic             s_hp_timer_irq;
  logic             s_hp_software_irq;
  logic             s_hp_machine_external_irq;
  logic             s_hp_supervisor_external_irq;
  logic             s_data_plane_idle;
  logic             s_data_plane_flush_busy;
  logic             s_mgmt_router_idle;
  logic [ 7:0]      s_data_plane_outstanding_read;
  logic [ 7:0]      s_data_plane_outstanding_write;
  logic             s_data_plane_fault_valid;
  logic [ 2:0]      s_data_plane_fault_master;
  logic [ 2:0]      s_data_plane_fault_target;
  logic [31:0]      s_data_plane_fault_addr;
  logic             s_data_plane_fault_write;
  logic [ 3:0]      s_data_plane_fault_reason;
  logic             s_hp_mmio_idle;
  logic [ 3:0]      s_pclk_pending_d;
  logic [ 3:0]      s_pclk_pending_q;
  logic [ 1:0]      s_mem_pad_mode_lp;
  logic             s_mem_pad_lock_lp;
  logic             s_hp_release_req_aon;
  logic             s_hp_debug_reset_req_aon;
  logic             s_hp_idle_aon;
  logic             s_hp_flush_busy_aon;
  logic             s_hp_lifecycle_release_aon;
  logic             s_hp_lifecycle_release_hp;
  logic             s_hp_lifecycle_block;
  logic             s_hp_lifecycle_flush;
  logic             s_hp_cache_req_aon;
  logic             s_hp_cache_req_pclk;
  logic             s_hp_cache_clean_pclk;
  logic             s_hp_cache_clean_aon;
  logic             s_hp_lifecycle_draining;
  logic             s_hp_lifecycle_fault;
  logic             s_hp_block_combined;
  logic             s_hp_block_hp;
  logic             s_hp_recovery_hp;
  logic             s_hp_flush_hp;
  logic             s_hp_mmio_clear_busy;
  logic [ 7:0]      s_hp_mmio_epoch;
  logic [ 2:0]      s_hp_lifecycle_stat_pclk;
  logic             s_ext_h_data_idle;
  logic             s_ext_h_block;
  logic [31:0]      s_ext_h_read_base;
  logic [31:0]      s_ext_h_read_limit;
  logic [31:0]      s_ext_h_write_base;
  logic [31:0]      s_ext_h_write_limit;
  logic [31:0]      s_ext_h_timeout;
  logic             s_ext_h_irq_raw;
  logic [ 1:0]      s_ext_h_owner;
  logic [ 7:0][1:0] s_resource_owner;
  logic [ 7:0]      s_resource_owner_lock;
  logic [ 7:0]      s_resource_quiesce;
  logic [ 7:0]      s_resource_reset;
  logic [ 6:0]      s_resource_idle_hp;
  logic [ 6:0]      s_resource_idle_pclk;
  logic [ 6:0]      s_resource_block_ack_hp;
  logic [ 6:0]      s_resource_block_ack_pclk;
  logic [ 6:0]      s_resource_irq_raw;
  logic [ 6:0]      s_resource_irq_lp;
  logic [ 6:0]      s_resource_irq_hp;
  logic             s_apu_idle;
  logic             s_jpeg_idle;
  logic [ 7:0]      s_resource_idle_combined;
  logic [ 7:0]      s_resource_block_ack_combined;
  logic [31:0]      s_fault_addr_mux;
  logic [ 3:0]      s_fault_wstrb_mux;
  logic             s_fault_reserved_mux;
  logic [ 2:0]      unused_cdc_clear_busy;
  logic [ 2:0][7:0] unused_cdc_epoch;

`ifdef HAVE_SRAM_IF
  localparam bit SramPresent = 1'b1;
`else
  localparam bit SramPresent = 1'b0;
`endif

  assign u_sysctrl_if.fault_access_i = s_data_plane_fault_valid ?
      s_data_plane_fault_write : s_bus_fault_access;
  assign u_sysctrl_if.fault_master_i = s_data_plane_fault_valid ?
      s_data_plane_fault_master : s_bus_fault_master;
  assign u_sysctrl_if.fault_code_i = s_data_plane_fault_valid ?
      s_data_plane_fault_reason[2:0] : s_bus_fault_code;
  assign s_perf_en = u_sysctrl_if.perf_enable_o;
  assign s_perf_clear = u_sysctrl_if.perf_clear_o;
  assign test_done_o = u_sysctrl_if.test_done_o;
  assign test_pass_o = u_sysctrl_if.test_pass_o;
  assign test_code_o = u_sysctrl_if.test_code_o;
  assign u_sysctrl_if.perf_mgmt_wait_i = s_perf_mgmt_wait;
  assign u_sysctrl_if.perf_user_wait_i = s_perf_user_wait;
  assign u_sysctrl_if.perf_dma_wait_i = s_perf_dma_wait;
  assign u_sysctrl_if.perf_sdio0_wait_i = s_perf_sdio0_wait;
  assign u_sysctrl_if.perf_sdio1_wait_i = s_perf_sdio1_wait;
  assign u_sysctrl_if.perf_usb2_wait_i = s_perf_usb2_wait;
  assign u_sysctrl_if.perf_apb4_periph_wait_i = s_perf_apb4_periph_wait;
  assign u_sysctrl_if.perf_apb4_system_wait_i = s_perf_apb4_system_wait;
  assign u_sysctrl_if.perf_sdram_wait_i = s_perf_sdram_wait;
  // The SYSCTRL PSRAM statistic aggregates the legacy and OPI PSRAM windows.
  assign u_sysctrl_if.perf_psram_wait_i = s_perf_psram_wait + s_perf_opipsram_wait;
  assign u_sysctrl_if.perf_flash_wait_i = s_perf_flash_wait;
  assign u_sysctrl_if.rtc_wake_i = s_rtc_wake;
`ifdef HAVE_HP
  assign u_sysctrl_if.hp_present_i = 1'b1;
`else
  assign u_sysctrl_if.hp_present_i = 1'b0;
`endif
  assign u_sysctrl_if.hp_actual_released_i = s_hp_lifecycle_stat_pclk[2];
  assign u_sysctrl_if.hp_draining_i = s_hp_lifecycle_stat_pclk[1];
  assign u_sysctrl_if.hp_forced_fault_i = s_hp_lifecycle_stat_pclk[0];
  assign s_fault_addr_mux = s_data_plane_fault_valid ? s_data_plane_fault_addr : s_bus_fault_addr;
  assign s_fault_wstrb_mux = s_data_plane_fault_valid && s_data_plane_fault_write ?
      4'hF : s_bus_fault_wstrb;
  assign s_fault_reserved_mux = s_data_plane_fault_valid ? 1'b0 : s_bus_fault_reserved;
  assign u_uart0_if.rx_i = uart_rx_i;
  assign uart_tx_o = u_uart0_if.tx_o;
  assign u_uart1_if.rx_i = uart1_rx_i;
  assign uart1_tx_o = u_uart1_if.tx_o;

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(2)
  ) u_mem_pad_mode_sync (
      .clk_i  (clk_lp_i),
      .rst_n_i(rst_lp_n_i),
      .dat_i  (mem_pad_mode_i),
      .dat_o  (s_mem_pad_mode_lp)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_mem_pad_lock_sync (
      .clk_i  (clk_lp_i),
      .rst_n_i(rst_lp_n_i),
      .dat_i  (mem_pad_lock_i),
      .dat_o  (s_mem_pad_lock_lp)
  );

  memory_pad_mux u_memory_pad_mux (
      .mode_i        (s_mem_pad_mode_lp),
      .controller_qpi(u_psram_raw_if),
      .pads_qpi      (u_psram_if),
      .controller_opi(u_opipsram_raw_if),
      .pads_opi      (u_opipsram_if)
  );

  gpio_pad_bridge u_gpio_pad_bridge (
      .inner(u_gpio_if),
      .outer(gpio)
  );

  // Generated IRQ vector wiring defaults all unallocated core IRQ bits low.
  `include "soc_irq_wiring.svh"

  // Generated GPIO alternate-function wiring is checked against soc_topology.json.
  `include "soc_gpio_alt_bindings.svh"

core_wrapper u_core_wrapper (
      .clk_i         (clk_lp_i),
      .rst_n_i       (rst_lp_n_i),
      `include "soc_mgmt_core_wrapper_fabric.svh"
      .irq_i         (s_irq),
      .jtag_tck_i    (jtag_tck_i),
      .jtag_tms_i    (s_debug_hp_sel_jtag ? 1'b1 : jtag_tms_i),
      .jtag_tdi_i    (s_debug_hp_sel_jtag ? 1'b0 : jtag_tdi_i),
      .jtag_trst_n_i (jtag_trst_n_i),
      .jtag_tdo_o    (s_lp_jtag_tdo),
      .debug_halted_o(s_mgmt_debug_halted)
  );

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_debug_select_sync (
      .clk_i  (jtag_tck_i),
      .rst_n_i(jtag_trst_n_i),
      .dat_i  (u_sysctrl_if.debug_hp_select_o),
      .dat_o  (s_debug_hp_sel_jtag)
  );

  assign jtag_tdo_o = s_debug_hp_sel_jtag ? s_hp_jtag_tdo : s_lp_jtag_tdo;

`ifdef MINI_PRODUCT
  assign s_unused_product_legacy = ^{
    u_sysctrl_if.core_sel_o, u_sysctrl_if.core_reset_o, u_sysctrl_if.user_bus_enable_o
  };

  axi4_master_idle u_retired_user_master (.axi4(u_user_axi4_if));
  axi4_error_slave u_retired_user_slave (
      .clk_i  (clk_lp_i),
      .rst_n_i(rst_lp_n_i),
      .axi4   (u_user_axi4_if)
  );
`else
  assign s_user_irq = u_sysctrl_if.user_bus_enable_o ? (s_irq & `SOC_USER_IRQ_MASK) : '0;

  user_core_top u_user_core_top (
      .clk_i       (clk_lp_i),
      .rst_n_i     (rst_lp_n_i),
      .irq_i       (s_user_irq),
      .sel_i       (u_sysctrl_if.core_sel_o),
      `include "soc_user_core_fabric.svh"
      .core_reset_i(u_sysctrl_if.core_reset_o)
  );

  assign u_ext_h_wide_axi4_if.awready = 1'b0;
  assign u_ext_h_wide_axi4_if.wready  = 1'b0;
  assign u_ext_h_wide_axi4_if.bid     = '0;
  assign u_ext_h_wide_axi4_if.bresp   = '0;
  assign u_ext_h_wide_axi4_if.buser   = '0;
  assign u_ext_h_wide_axi4_if.bvalid  = 1'b0;
  assign u_ext_h_wide_axi4_if.arready = 1'b0;
  assign u_ext_h_wide_axi4_if.rid     = '0;
  assign u_ext_h_wide_axi4_if.rdata   = '0;
  assign u_ext_h_wide_axi4_if.rresp   = '0;
  assign u_ext_h_wide_axi4_if.rlast   = 1'b0;
  assign u_ext_h_wide_axi4_if.ruser   = '0;
  assign u_ext_h_wide_axi4_if.rvalid  = 1'b0;
`endif

`ifdef HAVE_HP
  hp_subsystem u_hp_subsystem (
      .clk_i                    (clk_hp_core_i),
      .rst_n_i                  (rst_hp_n_i),
      .core_reset_i             (!s_hp_lifecycle_release_hp),
      .time_i                   (s_hp_time),
      .timer_irq_i              (s_hp_timer_irq),
      .software_irq_i           (s_hp_software_irq),
      .machine_external_irq_i   (s_hp_machine_external_irq),
      .supervisor_external_irq_i(s_hp_supervisor_external_irq),
      .jtag_tck_i               (jtag_tck_i),
      .jtag_tms_i               (s_debug_hp_sel_jtag ? jtag_tms_i : 1'b1),
      .jtag_tdi_i               (s_debug_hp_sel_jtag ? jtag_tdi_i : 1'b0),
      .jtag_trst_n_i            (jtag_trst_n_i),
      .jtag_tdo_o               (s_hp_jtag_tdo),
      .debug_reset_req_o        (s_hp_debug_reset_req),
      .icache_axi4              (u_hp_icache_axi4_if),
      .dcache_axi4              (u_hp_dcache_axi4_if),
      .mmio_axi4                (u_hp_mmio_wide_axi4_if)
  );
`else
  axi4_master_idle u_hp_icache_idle (.axi4(u_hp_icache_axi4_if));
  axi4_master_idle u_hp_dcache_idle (.axi4(u_hp_dcache_axi4_if));
  axi4_master_idle u_hp_mmio_idle (.axi4(u_hp_mmio_wide_axi4_if));
  assign s_hp_jtag_tdo        = 1'b0;
  assign s_hp_debug_reset_req = 1'b0;
`endif

  axi4_downsizer_64to32 u_hp_mmio_downsizer (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .clear_i(s_hp_flush_hp),
      .wide   (u_hp_mmio_wide_axi4_if),
      .narrow (u_hp_mmio_hp_axi4_if)
  );

  axi4_async_bridge #(
      .DataWidth(32),
      .IdWidth  (1)
  ) u_hp_mmio_cdc (
      .src_clk_i   (clk_hp_i),
      .src_rst_n_i (rst_hp_n_i),
      .dst_clk_i   (clk_lp_i),
      .dst_rst_n_i (rst_lp_n_i),
      .clear_i     (s_hp_flush_hp),
      .clear_busy_o(s_hp_mmio_clear_busy),
      .epoch_o     (s_hp_mmio_epoch),
      .src_axi4    (u_hp_mmio_gated_axi4_if),
      .dst_axi4    (u_hp_mmio_lp_axi4_if)
  );

  axi4_address_gate u_hp_mmio_gate (
      .clk_i      (clk_hp_i),
      .rst_n_i    (rst_hp_n_i),
      .block_new_i(s_hp_block_hp),
      .source     (u_hp_mmio_hp_axi4_if),
      .sink       (u_hp_mmio_gated_axi4_if),
      .idle_o     (s_hp_mmio_idle)
  );

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(4)
  ) u_hp_lifecycle_input_sync (
      .clk_i(clk_aon_i),
      .rst_n_i(rst_aon_n_i),
      .dat_i({
        u_sysctrl_if.hp_release_o,
        s_hp_debug_reset_req,
        s_data_plane_idle && s_hp_mmio_idle,
        s_data_plane_flush_busy || s_hp_mmio_clear_busy
      }),
      .dat_o({s_hp_release_req_aon, s_hp_debug_reset_req_aon, s_hp_idle_aon, s_hp_flush_busy_aon})
  );
  hp_lifecycle_controller u_hp_lifecycle_controller (
      .clk_i          (clk_aon_i),
      .rst_n_i        (rst_aon_n_i),
      .release_req_i  (s_hp_release_req_aon && !s_hp_debug_reset_req_aon),
      .hp_idle_i      (s_hp_idle_aon),
      .flush_busy_i   (s_hp_flush_busy_aon),
      .cache_clean_i  (s_hp_cache_clean_aon),
      .timeout_i      (16'd1024),
      .hp_release_o   (s_hp_lifecycle_release_aon),
      .block_new_o    (s_hp_lifecycle_block),
      .flush_o        (s_hp_lifecycle_flush),
      .cache_request_o(s_hp_cache_req_aon),
      .draining_o     (s_hp_lifecycle_draining),
      .forced_fault_o (s_hp_lifecycle_fault)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_hp_cache_req_sync (
      .clk_i  (clk_pclk_i),
      .rst_n_i(rst_pclk_n_i),
      .dat_i  (s_hp_cache_req_aon),
      .dat_o  (s_hp_cache_req_pclk)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_hp_cache_clean_sync (
      .clk_i  (clk_aon_i),
      .rst_n_i(rst_aon_n_i),
      .dat_i  (s_hp_cache_clean_pclk),
      .dat_o  (s_hp_cache_clean_aon)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_hp_release_sync (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  (s_hp_lifecycle_release_aon),
      .dat_o  (s_hp_lifecycle_release_hp)
  );
  assign s_hp_block_combined = hp_block_i || s_hp_lifecycle_block;
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(3)
  ) u_hp_lifecycle_control_sync (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  ({s_hp_block_combined, s_hp_lifecycle_block, s_hp_lifecycle_flush}),
      .dat_o  ({s_hp_block_hp, s_hp_recovery_hp, s_hp_flush_hp})
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(3)
  ) u_hp_lifecycle_status_sync (
      .clk_i  (clk_pclk_i),
      .rst_n_i(rst_pclk_n_i),
      .dat_i  ({s_hp_lifecycle_release_aon, s_hp_lifecycle_draining, s_hp_lifecycle_fault}),
      .dat_o  (s_hp_lifecycle_stat_pclk)
  );

  axi4_mgmt_router u_mgmt_router (
      .clk_i  (clk_lp_i),
      .rst_n_i(rst_lp_n_i),
      .source (u_mgmt_axi4_if),
      .control(u_mgmt_control_axi4_if),
      .data   (u_mgmt_data_axi4_if),
      .idle_o (s_mgmt_router_idle)
  );

  soc_data_plane u_data_plane (
      .clk_lp_i            (clk_lp_i),
      .rst_lp_n_i          (rst_lp_n_i),
      .clk_io_i            (clk_pclk_i),
      .rst_io_n_i          (rst_pclk_n_i),
      .clk_hp_i            (clk_hp_i),
      .rst_hp_n_i          (rst_hp_n_i),
      .clk_mem_i           (clk_mem_i),
      .rst_mem_n_i         (rst_mem_n_i),
      .block_new_i         (s_hp_block_hp),
      .recovery_i          (s_hp_recovery_hp),
      .flush_i             (s_hp_flush_hp),
      .resource_block_i    (s_resource_quiesce[6:0] | s_resource_reset[6:0]),
      .mem_pad_mode_i      (s_mem_pad_mode_lp),
      .ext_h_block_i       (s_ext_h_block),
      .ext_h_read_base_i   (s_ext_h_read_base),
      .ext_h_read_limit_i  (s_ext_h_read_limit),
      .ext_h_write_base_i  (s_ext_h_write_base),
      .ext_h_write_limit_i (s_ext_h_write_limit),
      .hp_icache_axi4      (u_hp_icache_axi4_if),
      .hp_dcache_axi4      (u_hp_dcache_axi4_if),
      .dma_axi4            (u_dma_axi4_if),
      .sdio0_axi4          (u_sdio0_axi4_if),
      .sdio1_axi4          (u_sdio1_axi4_if),
      .spisd_axi4          (u_spisd_axi4_if),
      .usb2_axi4           (u_usb2_axi4_if),
      .jpeg_axi4           (u_jpeg_wide_axi4_if),
      .lp_data_axi4        (u_mgmt_data_axi4_if),
      .ext_h_axi4          (u_ext_h_wide_axi4_if),
      .sram_gateway_axi4   (u_data_sram_axi4_if),
      .sdram_gateway_axi4  (u_data_sdram_axi4_if),
      .qpi_gateway_axi4    (u_data_qpi_axi4_if),
      .opi_gateway_axi4    (u_data_opi_axi4_if),
      .xpi_gateway_axi4    (u_data_xpi_axi4_if),
      .fabric_monitor_apb4 (u_fabric_monitor_hp_if),
      .idle_o              (s_data_plane_idle),
      .flush_busy_o        (s_data_plane_flush_busy),
      .ext_h_idle_o        (s_ext_h_data_idle),
      .resource_idle_o     (s_resource_idle_hp),
      .resource_block_ack_o(s_resource_block_ack_hp),
      .outstanding_read_o  (s_data_plane_outstanding_read),
      .outstanding_write_o (s_data_plane_outstanding_write),
      .fault_valid_o       (s_data_plane_fault_valid),
      .fault_master_o      (s_data_plane_fault_master),
      .fault_target_o      (s_data_plane_fault_target),
      .fault_addr_o        (s_data_plane_fault_addr),
      .fault_write_o       (s_data_plane_fault_write),
      .fault_reason_o      (s_data_plane_fault_reason)
  );

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(7)
  ) u_resource_idle_sync (
      .clk_i  (clk_pclk_i),
      .rst_n_i(rst_pclk_n_i),
      .dat_i  (s_resource_idle_hp),
      .dat_o  (s_resource_idle_pclk)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(7)
  ) u_resource_block_ack_sync (
      .clk_i  (clk_pclk_i),
      .rst_n_i(rst_pclk_n_i),
      .dat_i  (s_resource_block_ack_hp),
      .dat_o  (s_resource_block_ack_pclk)
  );

  axi4_master_idle u_idle_master (.axi4(u_idle_axi4_if));
  axi4_master_idle u_retired_sram_master (.axi4(u_retired_data_sram_axi4_if));
  axi4_master_idle u_retired_sdram_master (.axi4(u_retired_data_sdram_axi4_if));
  axi4_master_idle u_retired_qpi_master (.axi4(u_retired_data_qpi_axi4_if));
  axi4_master_idle u_retired_opi_master (.axi4(u_retired_data_opi_axi4_if));
  axi4_master_idle u_retired_xpi_master (.axi4(u_retired_data_xpi_axi4_if));

  axi4_async_bridge #(
      .DataWidth(32),
      .IdWidth  (1)
  ) u_cfg_pclk_cdc (
      .src_clk_i   (clk_lp_i),
      .src_rst_n_i (rst_lp_n_i),
      .dst_clk_i   (clk_pclk_i),
      .dst_rst_n_i (rst_pclk_n_i),
      .clear_i     (1'b0),
      .clear_busy_o(unused_cdc_clear_busy[1]),
      .epoch_o     (unused_cdc_epoch[1]),
      .src_axi4    (u_cfg_axi4_if),
      .dst_axi4    (u_cfg_pclk_axi4_if)
  );
  axi4_async_bridge #(
      .DataWidth(32),
      .IdWidth  (1)
  ) u_system_pclk_cdc (
      .src_clk_i   (clk_lp_i),
      .src_rst_n_i (rst_lp_n_i),
      .dst_clk_i   (clk_pclk_i),
      .dst_rst_n_i (rst_pclk_n_i),
      .clear_i     (1'b0),
      .clear_busy_o(unused_cdc_clear_busy[2]),
      .epoch_o     (unused_cdc_epoch[2]),
      .src_axi4    (u_system_axi4_if),
      .dst_axi4    (u_system_pclk_axi4_if)
  );
  apb4_async_bridge u_sdram_cfg_cdc (
      .src_clk_i  (clk_pclk_i),
      .src_rst_n_i(rst_pclk_n_i),
      .dst_clk_i  (clk_mem_i),
      .dst_rst_n_i(rst_mem_n_i),
      .src_apb4   (u_sdram_cfg_pclk_if),
      .dst_apb4   (u_sdram_cfg_if)
  );
  apb4_async_bridge u_sram_cfg_cdc (
      .src_clk_i  (clk_pclk_i),
      .src_rst_n_i(rst_pclk_n_i),
      .dst_clk_i  (clk_hp_i),
      .dst_rst_n_i(rst_hp_n_i),
      .src_apb4   (u_sram_cfg_pclk_if),
      .dst_apb4   (u_sram_cfg_if)
  );
  apb4_async_bridge u_fabric_monitor_cdc (
      .src_clk_i  (clk_pclk_i),
      .src_rst_n_i(rst_pclk_n_i),
      .dst_clk_i  (clk_hp_i),
      .dst_rst_n_i(rst_hp_n_i),
      .src_apb4   (u_fabric_monitor_pclk_if),
      .dst_apb4   (u_fabric_monitor_hp_if)
  );

  always_comb begin
    s_pclk_pending_d = s_pclk_pending_q;
    if (u_cfg_axi4_if.bvalid && u_cfg_axi4_if.bready) s_pclk_pending_d[0] = 1'b0;
    if (u_cfg_axi4_if.awvalid && u_cfg_axi4_if.awready) s_pclk_pending_d[0] = 1'b1;
    if (u_cfg_axi4_if.rvalid && u_cfg_axi4_if.rready && u_cfg_axi4_if.rlast)
      s_pclk_pending_d[1] = 1'b0;
    if (u_cfg_axi4_if.arvalid && u_cfg_axi4_if.arready) s_pclk_pending_d[1] = 1'b1;
    if (u_system_axi4_if.bvalid && u_system_axi4_if.bready) s_pclk_pending_d[2] = 1'b0;
    if (u_system_axi4_if.awvalid && u_system_axi4_if.awready) s_pclk_pending_d[2] = 1'b1;
    if (u_system_axi4_if.rvalid && u_system_axi4_if.rready && u_system_axi4_if.rlast)
      s_pclk_pending_d[3] = 1'b0;
    if (u_system_axi4_if.arvalid && u_system_axi4_if.arready) s_pclk_pending_d[3] = 1'b1;
  end

  dffr #(
      .DATA_WIDTH(4)
  ) u_pclk_pending_dffr (
      .clk_i  (clk_lp_i),
      .rst_n_i(rst_lp_n_i),
      .dat_i  (s_pclk_pending_d),
      .dat_o  (s_pclk_pending_q)
  );

  assign hp_idle_o = s_data_plane_idle && s_hp_mmio_idle;
  assign pclk_idle_o = !(|s_pclk_pending_q) && !u_cfg_axi4_if.awvalid &&
                       !u_cfg_axi4_if.arvalid && !u_system_axi4_if.awvalid &&
                       !u_system_axi4_if.arvalid;

  onchip_ram #(
      .Present    (SramPresent),
      .CapacityKiB(`SOC_ADDR_SRAM_SIZE >> 10),
      .DataWidth  (64),
      .IdWidth    (6)
  ) u_onchip_ram (
      .clk_i        (clk_hp_i),
      .rst_n_i      (rst_hp_n_i),
      .perf_enable_i(s_perf_en),
      .perf_clear_i (s_perf_clear),
      .mem_axi4     (u_data_sram_axi4_if),
      .cfg_apb4     (u_sram_cfg_if)
  );

  axi4_error_slave u_retired_sram_target (
      .clk_i  (clk_lp_i),
      .rst_n_i(rst_lp_n_i),
      .axi4   (u_sram_axi4_if)
  );
  axi4_error_slave u_retired_sdram_target (
      .clk_i  (clk_lp_i),
      .rst_n_i(rst_lp_n_i),
      .axi4   (u_sdram_axi4_if)
  );
  axi4_error_slave u_retired_qpi_target (
      .clk_i  (clk_lp_i),
      .rst_n_i(rst_lp_n_i),
      .axi4   (u_psram_axi4_if)
  );
  axi4_error_slave u_retired_xpi_target (
      .clk_i  (clk_lp_i),
      .rst_n_i(rst_lp_n_i),
      .axi4   (u_xpi_axi4_if)
  );
  axi4_error_slave u_retired_opi_target (
      .clk_i  (clk_lp_i),
      .rst_n_i(rst_lp_n_i),
      .axi4   (u_opipsram_axi4_if)
  );

  axi4_bus u_bus (
      .clk_i                  (clk_lp_i),
      .rst_n_i                (rst_lp_n_i),
      .mgmt_axi4              (u_mgmt_control_axi4_if),
      .user_axi4              (u_retired_data_sram_axi4_if),
      .dma_axi4               (u_retired_data_sdram_axi4_if),
      .sdio0_axi4             (u_retired_data_qpi_axi4_if),
      .sdio1_axi4             (u_retired_data_xpi_axi4_if),
      .usb2_axi4              (u_hp_mmio_lp_axi4_if),
      .spisd_axi4             (u_retired_data_opi_axi4_if),
      .hp_axi4                (u_idle_axi4_if),
      .cfg_axi4               (u_cfg_axi4_if),
      .system_axi4            (u_system_axi4_if),
      .sram_axi4              (u_sram_axi4_if),
      .user_bus_enable_i      (1'b1),
      .user_bus_idle_o        (u_sysctrl_if.user_bus_idle_i),
      .mem_pad_mode_i         (s_mem_pad_mode_lp),
      .sdram_axi4             (u_sdram_axi4_if),
      .psram_axi4             (u_psram_axi4_if),
      .xpi_axi4               (u_xpi_axi4_if),
      .opipsram_axi4          (u_opipsram_axi4_if),
      .perf_enable_i          (s_perf_en),
      .perf_clear_i           (s_perf_clear),
      .fault_valid_o          (s_bus_fault_valid),
      .fault_addr_o           (s_bus_fault_addr),
      .fault_wstrb_o          (s_bus_fault_wstrb),
      .fault_reserved_o       (s_bus_fault_reserved),
      .fault_access_o         (s_bus_fault_access),
      .fault_master_o         (s_bus_fault_master),
      .fault_code_o           (s_bus_fault_code),
      .perf_mgmt_wait_o       (s_perf_mgmt_wait),
      .perf_user_wait_o       (s_perf_user_wait),
      .perf_dma_wait_o        (s_perf_dma_wait),
      .perf_sdio0_wait_o      (s_perf_sdio0_wait),
      .perf_sdio1_wait_o      (s_perf_sdio1_wait),
      .perf_usb2_wait_o       (s_perf_usb2_wait),
      .perf_apb4_periph_wait_o(s_perf_apb4_periph_wait),
      .perf_apb4_system_wait_o(s_perf_apb4_system_wait),
      .perf_sdram_wait_o      (s_perf_sdram_wait),
      .perf_psram_wait_o      (s_perf_psram_wait),
      .perf_flash_wait_o      (s_perf_flash_wait),
      .perf_opipsram_wait_o   (s_perf_opipsram_wait)
  );

  apb4_periph u_apb4_periph (
      .clk_i                       (clk_pclk_i),
      .rst_n_i                     (rst_pclk_n_i),
      .clk_aud_i                   (clk_aud_i),
      .rst_aud_n_i                 (rst_aud_n_i),
      .clk_ulpi_i                  (clk_ulpi_i),
      .clk_mem_i                   (clk_mem_i),
      .rst_mem_n_i                 (rst_mem_n_i),
      .debug_halted_i              (s_mgmt_debug_halted),
      .timebase_tick_i             (timebase_tick_i),
      .ext_h_hp_irq_i              ((s_ext_h_owner == 2'd1) ? s_ext_h_irq_raw : 1'b0),
      .resource_irq_lp_i           (s_resource_irq_lp),
      .resource_irq_hp_i           (s_resource_irq_hp),
      .apu_owner_i                 (s_resource_owner[7]),
      .apu_owner_lock_i            (s_resource_owner_lock[7]),
      .apu_quiesce_i               (s_resource_quiesce[7]),
      .apu_reset_i                 (s_resource_reset[7]),
      .jpeg_quiesce_i              (s_resource_quiesce[6]),
      .jpeg_reset_i                (s_resource_reset[6]),
      .cfg_axi4                    (u_cfg_pclk_axi4_if),
      .dma_axi4                    (u_dma_axi4_if),
      .sdio0_axi4                  (u_sdio0_axi4_if),
      .sdio1_axi4                  (u_sdio1_axi4_if),
      .usb2_axi4                   (u_usb2_axi4_if),
      .jpeg_axi4                   (u_jpeg_wide_axi4_if),
      .psram_axi4                  (u_data_qpi_axi4_if),
      .xpi_axi4                    (u_data_xpi_axi4_if),
      .spisd_axi4                  (u_spisd_axi4_if),
      .opipsram_axi4               (u_data_opi_axi4_if),
      .gpio                        (u_gpio_if),
      .user_gpio                   (u_user_gpio_if),
      .uart                        (u_uart0_if),
      .uart1                       (u_uart1_if),
      .psram                       (u_psram_raw_if),
      .spisd                       (u_spisd_if),
      .i2c0                        (u_i2c0_if),
      .i2s                         (u_i2s_if),
      .ws2812                      (u_ws2812_if),
      .xpi                         (xpi),
      .sysctrl                     (u_sysctrl_if),
      .pll_ctrl                    (pll_ctrl),
      .clock_ctrl                  (clock_ctrl),
      .sdram_cfg                   (u_sdram_cfg_pclk_if),
      .sram_cfg                    (u_sram_cfg_pclk_if),
      .dvp                         (u_dvp_if),
      .sdio0                       (u_sdio0_if),
      .sdio1                       (sdio1),
      .usb2                        (usb2),
      .opipsram                    (u_opipsram_raw_if),
      .i2c1                        (u_i2c1_if),
      .fault_valid_i               (s_data_plane_fault_valid || s_bus_fault_valid),
      .fault_addr_i                (s_fault_addr_mux),
      .fault_wstrb_i               (s_fault_wstrb_mux),
      .fault_reserved_i            (s_fault_reserved_mux),
      .hp_time_o                   (s_hp_time),
      .hp_timer_irq_o              (s_hp_timer_irq),
      .hp_software_irq_o           (s_hp_software_irq),
      .hp_machine_external_irq_o   (s_hp_machine_external_irq),
      .hp_supervisor_external_irq_o(s_hp_supervisor_external_irq),
      .resource_irq_raw_o          (s_resource_irq_raw),
      .apu_idle_o                  (s_apu_idle),
      .jpeg_idle_o                 (s_jpeg_idle),
      .irq_o                       (s_apb4_periph_irq)
  );

  axi4_sdram u_axi4_sdram (
      .clk_i   (clk_mem_i),
      .rst_n_i (rst_mem_n_i),
      .axi4    (u_data_sdram_axi4_if),
      .cfg_apb4(u_sdram_cfg_if),
      .sdram   (sdram)
  );

  apb4_system u_apb4_system (
      .clk_i                (clk_pclk_i),
      .rst_n_i              (rst_pclk_n_i),
      .clk_aud_i            (clk_aud_i),
      .rst_aud_n_i          (rst_aud_n_i),
      .debug_halted_i       (s_mgmt_debug_halted),
      .ext_h_data_idle_i    (s_ext_h_data_idle),
      .resource_idle_i      (s_resource_idle_combined),
      .resource_block_ack_i (s_resource_block_ack_combined),
      .resource_irq_i       (s_resource_irq_raw),
      .cache_request_i      (s_hp_cache_req_pclk),
      .ext_h_axi4           (u_ext_h_wide_axi4_if),
      .fabric_monitor       (u_fabric_monitor_pclk_if),
      .axi4                 (u_system_pclk_axi4_if),
      .pwm                  (u_pwm_if),
      .ps2                  (u_ps2_if),
      .ip_sel_i             (u_sysctrl_if.ip_sel_o),
      .user_gpio            (u_user_gpio_if),
      .rtc_wake_o           (s_rtc_wake),
      .wdg_reset_req_o      (wdg_reset_req_o),
      .ext_h_block_o        (s_ext_h_block),
      .ext_h_read_base_o    (s_ext_h_read_base),
      .ext_h_read_limit_o   (s_ext_h_read_limit),
      .ext_h_write_base_o   (s_ext_h_write_base),
      .ext_h_write_limit_o  (s_ext_h_write_limit),
      .ext_h_timeout_o      (s_ext_h_timeout),
      .ext_h_irq_raw_o      (s_ext_h_irq_raw),
      .ext_h_owner_o        (s_ext_h_owner),
      .cache_clean_o        (s_hp_cache_clean_pclk),
      .resource_owner_o     (s_resource_owner),
      .resource_owner_lock_o(s_resource_owner_lock),
      .resource_quiesce_o   (s_resource_quiesce),
      .resource_reset_o     (s_resource_reset),
      .resource_irq_lp_o    (s_resource_irq_lp),
      .resource_irq_hp_o    (s_resource_irq_hp),
      .irq_o                (s_apb4_system_irq)
  );

  assign s_resource_idle_combined = {
    s_apu_idle,
    s_jpeg_idle && s_resource_idle_pclk[6],
    s_ext_h_data_idle && s_resource_idle_pclk[5],
    s_resource_idle_pclk[4:0]
  };
  assign s_resource_block_ack_combined = {
    s_apu_idle && (s_resource_quiesce[7] || s_resource_reset[7]), s_resource_block_ack_pclk
  };

  logic [36:0] s_unused_domain_inputs;
  assign s_unused_domain_inputs = {
    clk_pclk_i,
    rst_pclk_n_i,
    clk_mem_i,
    rst_mem_n_i ^ s_mem_pad_lock_lp,
    s_data_plane_outstanding_read,
    s_data_plane_outstanding_write,
    s_data_plane_fault_target,
    s_data_plane_fault_addr[1:0],
    s_data_plane_fault_reason[3],
    s_mgmt_router_idle,
    s_hp_lifecycle_draining,
    s_hp_lifecycle_fault,
    ^s_resource_owner,
    ^s_resource_owner_lock,
    ^s_resource_quiesce,
    ^s_resource_reset,
    ^unused_cdc_clear_busy,
    ^unused_cdc_epoch,
    ^{s_hp_mmio_epoch, s_hp_mmio_clear_busy},
    ^s_ext_h_timeout
  };

endmodule
