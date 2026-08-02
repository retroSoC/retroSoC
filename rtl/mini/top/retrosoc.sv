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
    // verilog_format: off
    input  logic                           clk_i,
    input  logic                           rst_n_i,
    input  logic                           clk_aud_i,
    input  logic                           rst_aud_n_i,
    input  logic                           clkdiv4_i,
    pll_ctrl_if.sysctrl                    pll_ctrl,
`ifdef HAVE_SRAM_IF
    ram_if.master                          ram,
`endif
    gpio_if.soc_pad                        gpio,
    uart_if.dut                            uart0,
    xpi_if.dut                             xpi,
    sdram_if.dut                           sdram
    // verilog_format: on
);

  // verilog_format: off
  // Generated fabric links reuse the common nmi_if contract.
  `include "soc_fabric_interfaces.svh"
  user_gpio_if u_user_gpio_if ();
  // ip interface
  gpio_if     u_gpio_if     ();
  psram_if    u_psram_if    ();
  spi_if      u_spisd_if    ();
  i2c_if      u_i2c0_if     ();
  i2s_if      u_i2s_if      ();
  onewire_if  u_onewire_if  ();
  sysctrl_if  u_sysctrl_if  ();
  dvp_if      u_dvp_if      ();
  sdio_if     u_sdio_if     ();
  opipsram_if u_opipsram_if ();
  i2c_if      u_i2c1_if     ();
  uart_if     u_uart1_if    ();
  pwm_if      u_pwm_if      ();
  ps2_if      u_ps2_if      ();
  // verilog_format: on

  logic                             s_tmr_capch;
  logic [`SOC_IRQ_VECTOR_WIDTH-1:0] s_irq;
  logic [   `SOC_IRQ_NMI_WIDTH-1:0] s_nmi_irq;
  logic [   `SOC_IRQ_APB_WIDTH-1:0] s_apb_irq;
  logic                             s_bus_fault_valid;
  logic [                     31:0] s_bus_fault_addr;
  logic [                      3:0] s_bus_fault_wstrb;
  logic                             s_bus_fault_reserved;
  logic                             s_bus_fault_access;
  logic [                      1:0] s_bus_fault_master;
  logic [                      2:0] s_bus_fault_code;
  logic                             s_apb_resp_err;
  logic                             s_perf_enable;
  logic                             s_perf_clear;
  logic [                     63:0] s_perf_mgmt_wait;
  logic [                     63:0] s_perf_user_wait;
  logic [                     63:0] s_perf_dma_wait;
  logic [                     63:0] s_perf_natv_wait;
  logic [                     63:0] s_perf_apb_wait;
  logic [                     63:0] s_perf_sdram_wait;
  logic [                     63:0] s_perf_psram_wait;
  logic [                     63:0] s_perf_flash_wait;
  logic [`SOC_IRQ_VECTOR_WIDTH-1:0] s_user_irq;

  assign u_sysctrl_if.fault_access_i    = s_bus_fault_access;
  assign u_sysctrl_if.fault_master_i    = s_bus_fault_master;
  assign u_sysctrl_if.fault_code_i      = s_bus_fault_code;
  assign s_perf_enable                  = u_sysctrl_if.perf_enable_o;
  assign s_perf_clear                   = u_sysctrl_if.perf_clear_o;
  assign u_sysctrl_if.perf_mgmt_wait_i  = s_perf_mgmt_wait;
  assign u_sysctrl_if.perf_user_wait_i  = s_perf_user_wait;
  assign u_sysctrl_if.perf_dma_wait_i   = s_perf_dma_wait;
  assign u_sysctrl_if.perf_natv_wait_i  = s_perf_natv_wait;
  assign u_sysctrl_if.perf_apb_wait_i   = s_perf_apb_wait;
  assign u_sysctrl_if.perf_sdram_wait_i = s_perf_sdram_wait;
  assign u_sysctrl_if.perf_psram_wait_i = s_perf_psram_wait;
  assign u_sysctrl_if.perf_flash_wait_i = s_perf_flash_wait;

  gpio_pad_bridge u_gpio_pad_bridge (
      .inner(u_gpio_if),
      .outer(gpio)
  );

  // Generated IRQ vector wiring defaults all unallocated core IRQ bits low.
  `include "soc_irq_wiring.svh"

  // Generated GPIO alternate-function wiring is checked against soc_topology.json.
  `include "soc_gpio_alt_bindings.svh"

core_wrapper u_core_wrapper (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      `include "soc_mgmt_core_wrapper_fabric.svh"
      .irq_i  (s_irq)
  );

  assign s_user_irq = u_sysctrl_if.user_bus_enable_o ? s_irq : '0;
  user_core_top u_user_core_top (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .irq_i       (s_user_irq),
      .sel_i       (u_sysctrl_if.core_sel_o),
      `include "soc_user_core_fabric.svh"
      .core_reset_i(u_sysctrl_if.core_reset_o)
  );

  bus u_bus (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
`ifdef HAVE_SRAM_IF
      .ram              (ram),
`endif
      .user_bus_enable_i(u_sysctrl_if.user_bus_enable_o),
      .user_bus_idle_o  (u_sysctrl_if.user_bus_idle_i),
      `include "soc_bus_fabric.svh"
      .apb_resp_err_i   (s_apb_resp_err),
      .perf_enable_i    (s_perf_enable),
      .perf_clear_i     (s_perf_clear),
      .fault_valid_o    (s_bus_fault_valid),
      .fault_addr_o     (s_bus_fault_addr),
      .fault_wstrb_o    (s_bus_fault_wstrb),
      .fault_reserved_o (s_bus_fault_reserved),
      .fault_access_o   (s_bus_fault_access),
      .fault_master_o   (s_bus_fault_master),
      .fault_code_o     (s_bus_fault_code),
      .perf_mgmt_wait_o (s_perf_mgmt_wait),
      .perf_user_wait_o (s_perf_user_wait),
      .perf_dma_wait_o  (s_perf_dma_wait),
      .perf_natv_wait_o (s_perf_natv_wait),
      .perf_apb_wait_o  (s_perf_apb_wait),
      .perf_sdram_wait_o(s_perf_sdram_wait),
      .perf_psram_wait_o(s_perf_psram_wait),
      .perf_flash_wait_o(s_perf_flash_wait)
  );

  ip_nmi_wrapper u_ip_nmi_wrapper (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .clk_aud_i       (clk_aud_i),
      .rst_aud_n_i     (rst_aud_n_i),
      `include "soc_ip_nmi_wrapper_fabric.svh"
      .gpio            (u_gpio_if),
      .user_gpio       (u_user_gpio_if),
      .uart            (uart0),
      .psram           (u_psram_if),
      .spisd           (u_spisd_if),
      .i2c0            (u_i2c0_if),
      .i2s             (u_i2s_if),
      .onewire         (u_onewire_if),
      .xpi             (xpi),
      .sysctrl         (u_sysctrl_if),
      .pll_ctrl        (pll_ctrl),
      .sdram           (sdram),
      .dvp             (u_dvp_if),
      .sdio            (u_sdio_if),
      .opipsram        (u_opipsram_if),
      .i2c1            (u_i2c1_if),
      .fault_valid_i   (s_bus_fault_valid),
      .fault_addr_i    (s_bus_fault_addr),
      .fault_wstrb_i   (s_bus_fault_wstrb),
      .fault_reserved_i(s_bus_fault_reserved),
      .irq_o           (s_nmi_irq)
  );

  ip_apb_wrapper u_ip_apb_wrapper (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .clk_aud_i     (clk_aud_i),
      .rst_aud_n_i   (rst_aud_n_i),
      .tmr_capch_i   (s_tmr_capch),
      `include "soc_ip_apb_wrapper_fabric.svh"
      .uart          (u_uart1_if),
      .pwm           (u_pwm_if),
      .ps2           (u_ps2_if),
      .ip_sel_i      (u_sysctrl_if.ip_sel_o),
      .user_gpio     (u_user_gpio_if),
      .nmi_resp_err_o(s_apb_resp_err),
      .irq_o         (s_apb_irq)
  );

endmodule
