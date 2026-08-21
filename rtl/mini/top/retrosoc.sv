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
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        clk_aud_i,
    input  logic        rst_aud_n_i,
    input  logic        clkdiv4_i,
    input  logic        timebase_tick_i,
    pll_ctrl_if.sysctrl pll_ctrl,
`ifdef HAVE_SRAM_IF
    ram_if.master        ram,
`endif
    gpio_if.soc_pad      gpio,
    input  logic         uart_rx_i,
    output logic         uart_tx_o,
    xpi_if.dut           xpi,
    sdram_if.dut         sdram,
    sdio_if.dut          sdio1,
    input  logic         jtag_tck_i,
    input  logic         jtag_tms_i,
    input  logic         jtag_tdi_i,
    input  logic         jtag_trst_n_i,
    output logic         jtag_tdo_o,
    output logic         wdg_reset_req_o,
    output logic         test_done_o,
    output logic         test_pass_o,
    output logic [7:0]   test_code_o
    // verilog_format: on
);

  // verilog_format: off -- preserve reviewed column alignment
  // Generated fabric links use the common 32-bit AXI4 contract.
  `include "soc_fabric_interfaces.svh"
  apb4_if u_sdram_cfg_if (.pclk(clk_i), .presetn(rst_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_sdram_axi4_if (.aclk(clk_i), .aresetn(rst_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_psram_axi4_if (.aclk(clk_i), .aresetn(rst_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_xpi_axi4_if (.aclk(clk_i), .aresetn(rst_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_spisd_axi4_if (.aclk(clk_i), .aresetn(rst_n_i));
  axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(1), .USER_WIDTH(1))
      u_opipsram_axi4_if (.aclk(clk_i), .aresetn(rst_n_i));
  user_gpio_if u_user_gpio_if ();
  // ip interface
  gpio_if     u_gpio_if     ();
  uart_if     u_uart0_if    ();
  psram_if    u_psram_if    ();
  spi_if      u_spisd_if    ();
  i2c_if      u_i2c0_if     ();
  i2s_if      u_i2s_if      ();
  ws2812_if   u_ws2812_if   ();
  sysctrl_if  u_sysctrl_if  ();
  dvp_if      u_dvp_if      ();
  sdio_if     u_sdio0_if    ();
  opipsram_if u_opipsram_if ();
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
  logic [                          63:0] s_perf_apb4_periph_wait;
  logic [                          63:0] s_perf_apb4_system_wait;
  logic [                          63:0] s_perf_sdram_wait;
  logic [                          63:0] s_perf_psram_wait;
  logic [                          63:0] s_perf_flash_wait;
  logic [                          63:0] s_perf_opipsram_wait;
  logic [     `SOC_IRQ_VECTOR_WIDTH-1:0] s_user_irq;
  logic                                  s_rtc_wake;

  assign u_sysctrl_if.fault_access_i          = s_bus_fault_access;
  assign u_sysctrl_if.fault_master_i          = s_bus_fault_master;
  assign u_sysctrl_if.fault_code_i            = s_bus_fault_code;
  assign s_perf_en                            = u_sysctrl_if.perf_enable_o;
  assign s_perf_clear                         = u_sysctrl_if.perf_clear_o;
  assign test_done_o                          = u_sysctrl_if.test_done_o;
  assign test_pass_o                          = u_sysctrl_if.test_pass_o;
  assign test_code_o                          = u_sysctrl_if.test_code_o;
  assign u_sysctrl_if.perf_mgmt_wait_i        = s_perf_mgmt_wait;
  assign u_sysctrl_if.perf_user_wait_i        = s_perf_user_wait;
  assign u_sysctrl_if.perf_dma_wait_i         = s_perf_dma_wait;
  assign u_sysctrl_if.perf_sdio0_wait_i       = s_perf_sdio0_wait;
  assign u_sysctrl_if.perf_sdio1_wait_i       = s_perf_sdio1_wait;
  assign u_sysctrl_if.perf_apb4_periph_wait_i = s_perf_apb4_periph_wait;
  assign u_sysctrl_if.perf_apb4_system_wait_i = s_perf_apb4_system_wait;
  assign u_sysctrl_if.perf_sdram_wait_i       = s_perf_sdram_wait;
  // The SYSCTRL PSRAM statistic aggregates the legacy and OPI PSRAM windows.
  assign u_sysctrl_if.perf_psram_wait_i       = s_perf_psram_wait + s_perf_opipsram_wait;
  assign u_sysctrl_if.perf_flash_wait_i       = s_perf_flash_wait;
  assign u_sysctrl_if.rtc_wake_i              = s_rtc_wake;
  assign u_uart0_if.rx_i                      = uart_rx_i;
  assign uart_tx_o                            = u_uart0_if.tx_o;

  gpio_pad_bridge u_gpio_pad_bridge (
      .inner(u_gpio_if),
      .outer(gpio)
  );

  // Generated IRQ vector wiring defaults all unallocated core IRQ bits low.
  `include "soc_irq_wiring.svh"

  // Generated GPIO alternate-function wiring is checked against soc_topology.json.
  `include "soc_gpio_alt_bindings.svh"

core_wrapper u_core_wrapper (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      `include "soc_mgmt_core_wrapper_fabric.svh"
      .irq_i         (s_irq),
      .jtag_tck_i    (jtag_tck_i),
      .jtag_tms_i    (jtag_tms_i),
      .jtag_tdi_i    (jtag_tdi_i),
      .jtag_trst_n_i (jtag_trst_n_i),
      .jtag_tdo_o    (jtag_tdo_o),
      .debug_halted_o(s_mgmt_debug_halted)
  );

  assign s_user_irq = u_sysctrl_if.user_bus_enable_o ? (s_irq & `SOC_USER_IRQ_MASK) : '0;
  user_core_top u_user_core_top (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .irq_i       (s_user_irq),
      .sel_i       (u_sysctrl_if.core_sel_o),
      `include "soc_user_core_fabric.svh"
      .core_reset_i(u_sysctrl_if.core_reset_o)
  );

  axi4_bus u_bus (
      .clk_i                  (clk_i),
      .rst_n_i                (rst_n_i),
`ifdef HAVE_SRAM_IF
      .ram                    (ram),
`endif
      .user_bus_enable_i      (u_sysctrl_if.user_bus_enable_o),
      .user_bus_idle_o        (u_sysctrl_if.user_bus_idle_i),
      `include "soc_bus_fabric.svh"
      .sdram_axi4             (u_sdram_axi4_if),
      .psram_axi4             (u_psram_axi4_if),
      .xpi_axi4               (u_xpi_axi4_if),
      .spisd_axi4             (u_spisd_axi4_if),
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
      .perf_apb4_periph_wait_o(s_perf_apb4_periph_wait),
      .perf_apb4_system_wait_o(s_perf_apb4_system_wait),
      .perf_sdram_wait_o      (s_perf_sdram_wait),
      .perf_psram_wait_o      (s_perf_psram_wait),
      .perf_flash_wait_o      (s_perf_flash_wait),
      .perf_opipsram_wait_o   (s_perf_opipsram_wait)
  );

  apb4_periph u_apb4_periph (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .clk_aud_i       (clk_aud_i),
      .rst_aud_n_i     (rst_aud_n_i),
      .debug_halted_i  (s_mgmt_debug_halted),
      .timebase_tick_i (timebase_tick_i),
      `include "apb4_periph_fabric.svh"
      .psram_axi4      (u_psram_axi4_if),
      .xpi_axi4        (u_xpi_axi4_if),
      .spisd_axi4      (u_spisd_axi4_if),
      .opipsram_axi4   (u_opipsram_axi4_if),
      .gpio            (u_gpio_if),
      .user_gpio       (u_user_gpio_if),
      .uart            (u_uart0_if),
      .psram           (u_psram_if),
      .spisd           (u_spisd_if),
      .i2c0            (u_i2c0_if),
      .i2s             (u_i2s_if),
      .ws2812          (u_ws2812_if),
      .xpi             (xpi),
      .sysctrl         (u_sysctrl_if),
      .pll_ctrl        (pll_ctrl),
      .sdram_cfg       (u_sdram_cfg_if),
      .dvp             (u_dvp_if),
      .sdio0           (u_sdio0_if),
      .sdio1           (sdio1),
      .opipsram        (u_opipsram_if),
      .i2c1            (u_i2c1_if),
      .fault_valid_i   (s_bus_fault_valid),
      .fault_addr_i    (s_bus_fault_addr),
      .fault_wstrb_i   (s_bus_fault_wstrb),
      .fault_reserved_i(s_bus_fault_reserved),
      .irq_o           (s_apb4_periph_irq)
  );

  axi4_sdram u_axi4_sdram (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .axi4    (u_sdram_axi4_if),
      .cfg_apb4(u_sdram_cfg_if),
      .sdram   (sdram)
  );

  apb4_system u_apb4_system (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .clk_aud_i      (clk_aud_i),
      .rst_aud_n_i    (rst_aud_n_i),
      .debug_halted_i (s_mgmt_debug_halted),
      `include "apb4_system_fabric.svh"
      .pwm            (u_pwm_if),
      .ps2            (u_ps2_if),
      .ip_sel_i       (u_sysctrl_if.ip_sel_o),
      .user_gpio      (u_user_gpio_if),
      .rtc_wake_o     (s_rtc_wake),
      .wdg_reset_req_o(wdg_reset_req_o),
      .irq_o          (s_apb4_system_irq)
  );

endmodule
