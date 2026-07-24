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
`include "soc_irq_config.svh"

module ip_nmi_wrapper (
    // verilog_format: off
    input logic        clk_i,
    input logic        rst_n_i,
    input logic        clk_aud_i,
    input logic        rst_aud_n_i,
    nmi_if.slave       nmi,
    gpio_if.dut        gpio,
    user_gpio_if.padctrl user_gpio,
    uart_if.dut        uart,
    psram_if.dut       psram,
    spi_if.dut         spisd,
    i2c_if.dut         i2c0,
    i2s_if.dut         i2s,
    onewire_if.dut     onewire,
    xpi_if.dut         xpi,
    nmi_if.master      dma_nmi,
    sysctrl_if.dut     sysctrl,
    pll_ctrl_if.sysctrl pll_ctrl,
    sdram_if.dut       sdram,
    dvp_if.dut         dvp,
    sdio_if.dut        sdio,
    opipsram_if.dut    opipsram,
    i2c_if.dut         i2c1,
    input logic        fault_valid_i,
    input logic [31:0] fault_addr_i,
    input logic [3:0]  fault_wstrb_i,
    input logic        fault_reserved_i,
    output logic [`SOC_IRQ_NMI_WIDTH-1:0] irq_o
    // verilog_format: on
);

  // Generated NMI target declarations preserve scalar-interface compatibility.
  `include "soc_nmi_interfaces.svh"

simp_clint_if u_clint_if ();
  dma_hw_trg_if u_dma_hw_trg_if ();

  logic s_dma_i2s_tx_stall, s_dma_i2s_rx_stall;
  logic s_dma_xpi_tx_stall, s_dma_xpi_rx_stall;
  logic s_dma_xfer_done;
  logic s_tim0_irq, s_tim1_irq;

  assign u_dma_hw_trg_if.i2s_tx_proc  = ~s_dma_i2s_tx_stall;
  assign u_dma_hw_trg_if.i2s_rx_proc  = ~s_dma_i2s_rx_stall;
  assign u_dma_hw_trg_if.qspi_tx_proc = ~s_dma_xpi_tx_stall;
  assign u_dma_hw_trg_if.qspi_rx_proc = ~s_dma_xpi_rx_stall;

  // Uses ClusterIP common nmi_if and register.sv dffr through generated bindings.
  `include "soc_nmi_routes.svh"

  // Generated IRQ ownership and core-vector bit assignments are topology checked.
  `include "soc_nmi_irq_bindings.svh"

nmi_gpio u_nmi_gpio (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .nmi      (u_gpio_nmi_if),
      .gpio     (gpio),
      .user_gpio(user_gpio)
  );

  nmi_uart u_nmi_uart (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_uart_nmi_if),
      .uart   (uart)
  );

  nmi_timer u_nmi_timer0 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_tim0_nmi_if),
      .irq_o  (s_tim0_irq)
  );

  nmi_timer u_nmi_timer1 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_tim1_nmi_if),
      .irq_o  (s_tim1_irq)
  );

  nmi_psram u_nmi_psram (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_psram_nmi_if),
      .psram  (psram)
  );

  nmi_spisd u_nmi_spisd (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_spisd_nmi_if),
      .spi    (spisd)
  );

  nmi_i2c u_nmi_i2c0 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_i2c0_nmi_if),
      .i2c    (i2c0)
  );

  nmi_i2s u_nmi_i2s (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .clk_aud_i     (clk_aud_i),
      .rst_aud_n_i   (rst_aud_n_i),
      .dma_tx_stall_o(s_dma_i2s_tx_stall),
      .dma_rx_stall_o(s_dma_i2s_rx_stall),
      .nmi           (u_i2s_nmi_if),
      .i2s           (i2s)
  );

  nmi_onewire u_nmi_onewire (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_onewire_nmi_if),
      .onewire(onewire)
  );

  nmi_xpi u_nmi_xpi (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .dma_xfer_done_i(s_dma_xfer_done),
      .dma_tx_stall_o (s_dma_xpi_tx_stall),
      .dma_rx_stall_o (s_dma_xpi_rx_stall),
      .nmi            (u_xpi_nmi_if),
      .xpi            (xpi)
  );

  nmi_dma u_nmi_dma (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .dma_xfer_done_o(s_dma_xfer_done),
      .hw_trg         (u_dma_hw_trg_if),
      .nmi            (u_dma_nmi_if),
      .nmi_dma        (dma_nmi)
  );

  nmi_sysctrl u_nmi_sysctrl (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .fault_valid_i   (fault_valid_i),
      .fault_addr_i    (fault_addr_i),
      .fault_wstrb_i   (fault_wstrb_i),
      .fault_reserved_i(fault_reserved_i),
      .nmi             (u_sysctrl_nmi_if),
      .sysctrl         (sysctrl),
      .pll_ctrl        (pll_ctrl)
  );

  nmi_clint u_nmi_clint (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_clint_nmi_if),
      .clint  (u_clint_if)
  );

  nmi_sdram u_nmi_sdram (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_sdram_nmi_if),
      .sdram  (sdram)
  );

  nmi_dvp u_nmi_dvp (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_dvp_nmi_if),
      .dvp    (dvp)
  );

  nmi_sdio u_nmi_sdio (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_sdio_nmi_if),
      .sdio   (sdio)
  );

  nmi_opipsram u_nmi_opipsram (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_opipsram_nmi_if),
      .psram  (opipsram)
  );

  nmi_i2c u_nmi_i2c1 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_i2c1_nmi_if),
      .i2c    (i2c1)
  );

endmodule
