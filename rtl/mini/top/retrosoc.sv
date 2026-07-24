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
`include "mdd_config.svh"

module retrosoc (
    // verilog_format: off
    input  logic                           clk_i,
    input  logic                           rst_n_i,
    input  logic                           clk_aud_i,
    input  logic                           rst_aud_n_i,
    input  logic                           clkdiv4_i,
    pll_ctrl_if.sysctrl                    pll_ctrl,
`ifdef CORE_MDD
    input  logic [`USER_CORESEL_WIDTH-1:0] core_sel_i,
`endif
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

  logic        s_tmr_capch;
  logic [31:0] s_irq;
  logic [ 9:0] s_nmi_irq;
  logic [ 6:0] s_apb_irq;
  logic        s_bus_fault_valid;
  logic [31:0] s_bus_fault_addr;
  logic [ 3:0] s_bus_fault_wstrb;
  logic        s_bus_fault_reserved;

  gpio_pad_bridge u_gpio_pad_bridge (
      .inner(u_gpio_if),
      .outer(gpio)
  );

`ifndef IP_MDD
  assign u_user_gpio_if.do_o = '0;
  assign u_user_gpio_if.oe_o = '0;
`endif

`ifdef CORE_MDD
  assign u_sysctrl_if.core_sel_i = core_sel_i;
`else
  assign u_sysctrl_if.core_sel_i = '0;
`endif

  assign s_irq[9:0]   = s_nmi_irq;
  assign s_irq[16:10] = s_apb_irq;
  assign s_irq[31:17] = 15'd0;

  // Generated GPIO alternate-function wiring is checked against soc_topology.json.
  `include "soc_gpio_alt_bindings.svh"

core_wrapper u_core_wrapper (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
`ifdef CORE_MDD
      .core_sel_i(core_sel_i),
`endif
      `include "soc_core_wrapper_fabric.svh"
      .irq_i     (s_irq)
  );

  bus u_bus (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
`ifdef HAVE_SRAM_IF
      .ram             (ram),
`endif
      `include "soc_bus_fabric.svh"
      .fault_valid_o   (s_bus_fault_valid),
      .fault_addr_o    (s_bus_fault_addr),
      .fault_wstrb_o   (s_bus_fault_wstrb),
      .fault_reserved_o(s_bus_fault_reserved)
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
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .clk_aud_i  (clk_aud_i),
      .rst_aud_n_i(rst_aud_n_i),
      .tmr_capch_i(s_tmr_capch),
      `include "soc_ip_apb_wrapper_fabric.svh"
      .uart       (u_uart1_if),
      .pwm        (u_pwm_if),
      .ps2        (u_ps2_if),
`ifdef IP_MDD
      .ip_sel_i   (u_sysctrl_if.ip_sel_o),
      .user_gpio  (u_user_gpio_if),
`endif
      .irq_o      (s_apb_irq)
  );

endmodule
