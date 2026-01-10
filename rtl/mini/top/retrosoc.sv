// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"
`include "mdd_config.svh"

module retrosoc (
    // verilog_format: off
    input  logic                           clk_i,
    input  logic                           rst_n_i,
    input  logic                           clk_aud_i,
    input  logic                           rst_aud_n_i,
    input  logic                           tmr_capch_i,
    input  logic                           spfs_div4_i,
    input  logic                           extn_irq_i,
`ifdef CORE_MDD
    input  logic [`USER_CORESEL_WIDTH-1:0] core_sel_i,
`endif
`ifdef IP_MDD
    user_gpio_if.dut                       user_gpio,
`endif
`ifdef HAVE_SRAM_IF
    ram_if.master                          ram,
`endif
    uart_if.dut                            uart0,
    simp_gpio_if.dut                       gpio,
    qspi_if.dut                            psram,
    spi_if.dut                             spisd,
    i2c_if.dut                             i2c,
    qspi_if.dut                            qspi,
    nv_i2s_if.dut                          i2s,
    onewire_if.dut                         onewire,
    uart_if.dut                            uart1,
    pwm_if.dut                             pwm,
    ps2_if.dut                             ps2,
    spi_if.dut                             spfs
    // verilog_format: on
);

  // verilog_format: off
  // bus interface
  nmi_if u_core_nmi_if ();
  nmi_if u_dma_nmi_if ();
  nmi_if u_natv_nmi_if();
  nmi_if u_apb_nmi_if();
  // ip interface
  sysctrl_if u_sysctrl_if();
  // verilog_format: on
  // irq
  logic [31:0] s_irq;
  logic [ 9:0] s_natv_irq;
  logic [ 6:0] s_apb_irq;

`ifdef CORE_MDD
  assign u_sysctrl_if.core_sel_i = core_sel_i;
`else
  assign u_sysctrl_if.core_sel_i = '0;
`endif

  // irq
  assign s_irq[9:0]   = s_natv_irq;
  assign s_irq[16:10] = s_apb_irq;
  assign s_irq[17]    = extn_irq_i;
  assign s_irq[31:18] = 14'd0;


  core_wrapper u_core_wrapper (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
`ifdef CORE_MDD
      .core_sel_i(core_sel_i),
`endif
      .nmi       (u_core_nmi_if),
      .irq_i     (s_irq)
  );


  bus u_bus (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
`ifdef HAVE_SRAM_IF
      .ram     (ram),
`endif
      // master
      .core_nmi(u_core_nmi_if),
      .dma_nmi (u_dma_nmi_if),
      // slave
      .natv_nmi(u_natv_nmi_if),
      .apb_nmi (u_apb_nmi_if)
  );


  ip_natv_wrapper u_ip_natv_wrapper (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .clk_aud_i  (clk_aud_i),
      .rst_aud_n_i(rst_aud_n_i),
      .nmi        (u_natv_nmi_if),
      .uart       (uart0),
      .gpio       (gpio),
      .psram      (psram),
      .spisd      (spisd),
      .i2c        (i2c),
      .i2s        (i2s),
      .onewire    (onewire),
      .qspi       (qspi),
      .dma_nmi    (u_dma_nmi_if),
      .sysctrl    (u_sysctrl_if),
      .irq_o      (s_natv_irq)
  );


  ip_apb_wrapper u_ip_apb_wrapper (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .clk_aud_i  (clk_aud_i),
      .rst_aud_n_i(rst_aud_n_i),
      .tmr_capch_i(tmr_capch_i),
      .spfs_div4_i(spfs_div4_i),
      .nmi        (u_apb_nmi_if),
      .uart       (uart1),
      .pwm        (pwm),
      .ps2        (ps2),
      .spfs       (spfs),
`ifdef IP_MDD
      .ip_sel_i   (u_sysctrl_if.ip_sel_o),
      .gpio       (user_gpio),
`endif
      .irq_o      (s_apb_irq)
  );

endmodule
