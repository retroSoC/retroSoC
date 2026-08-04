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
`include "rib_defs.svh"

module ip_ribp_wrapper (
    // verilog_format: off
    input logic              clk_i,
    input logic              rst_n_i,
    input logic              clk_aud_i,
    input logic              rst_aud_n_i,
    rib_if.slave   rib,
    gpio_if.dut              gpio,
    user_gpio_if.padctrl     user_gpio,
    uart_if.dut              uart,
    psram_if.dut             psram,
    spi_if.dut               spisd,
    i2c_if.dut               i2c0,
    i2s_if.dut               i2s,
    onewire_if.dut           onewire,
    xpi_if.dut               xpi,
    rib_if.master  dma_rib,
    sysctrl_if.dut           sysctrl,
    pll_ctrl_if.sysctrl      pll_ctrl,
    sdram_if.dut             sdram,
    dvp_if.dut               dvp,
    sdio_if.dut              sdio,
    opipsram_if.dut          opipsram,
    i2c_if.dut               i2c1,
    input logic              fault_valid_i,
    input logic [31:0]       fault_addr_i,
    input logic [3:0]        fault_wstrb_i,
    input logic              fault_reserved_i,
    output logic [`SOC_IRQ_RIBP_WIDTH-1:0] irq_o
    // verilog_format: on
);

  // verilog_format: off
  // Generated RIBP target declarations preserve scalar-interface compatibility.
  `include "ribp_interfaces.svh"

  ribp_if ribp ();
  // verilog_format: on

  simp_clint_if u_clint_if ();
  dma_hw_trg_if u_dma_hw_trg_if ();

  logic s_dma_i2s_tx_stall, s_dma_i2s_rx_stall;
  logic s_dma_xpi_tx_stall, s_dma_xpi_rx_stall;
  logic s_dma_xfer_done;
  logic s_tim0_irq, s_tim1_irq;

  rib2ribp u_rib2ribp (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .rib    (rib),
      .ribp   (ribp)
  );

  // Generated target routing operates on the RIBP boundary behind the RIB
  // adapter. Register targets therefore remain INCR1-only.

  assign u_dma_hw_trg_if.i2s_tx_proc  = ~s_dma_i2s_tx_stall;
  assign u_dma_hw_trg_if.i2s_rx_proc  = ~s_dma_i2s_rx_stall;
  assign u_dma_hw_trg_if.qspi_tx_proc = ~s_dma_xpi_tx_stall;
  assign u_dma_hw_trg_if.qspi_rx_proc = ~s_dma_xpi_rx_stall;

  // Uses ClusterIP common ribp_if and register.sv dffr through generated bindings.
  `include "ribp_routes.svh"

  // verilog_format: off
  // Generated IRQ ownership and core-vector bit assignments are topology checked.
  `include "ribp_irq_bindings.svh"

  ribp_gpio u_rib_gpio (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .ribp(u_gpio_ribp_if),
      .gpio     (gpio),
      .user_gpio(user_gpio)
  );
  // verilog_format: on

  ribp_uart u_rib_uart (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_uart_ribp_if),
      .uart   (uart)
  );

  ribp_timer u_rib_timer0 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_tim0_ribp_if),
      .irq_o  (s_tim0_irq)
  );

  ribp_timer u_rib_timer1 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_tim1_ribp_if),
      .irq_o  (s_tim1_irq)
  );

  ribp_psram u_rib_psram (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_psram_ribp_if),
      .psram  (psram)
  );

  ribp_spisd u_rib_spisd (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_spisd_ribp_if),
      .spi    (spisd)
  );

  ribp_i2c u_rib_i2c0 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_i2c0_ribp_if),
      .i2c    (i2c0)
  );

  ribp_i2s u_rib_i2s (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .clk_aud_i     (clk_aud_i),
      .rst_aud_n_i   (rst_aud_n_i),
      .dma_tx_stall_o(s_dma_i2s_tx_stall),
      .dma_rx_stall_o(s_dma_i2s_rx_stall),
      .ribp          (u_i2s_ribp_if),
      .i2s           (i2s)
  );

  ribp_onewire u_rib_onewire (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_onewire_ribp_if),
      .onewire(onewire)
  );

  ribp_xpi u_rib_xpi (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .dma_xfer_done_i(s_dma_xfer_done),
      .dma_tx_stall_o (s_dma_xpi_tx_stall),
      .dma_rx_stall_o (s_dma_xpi_rx_stall),
      .ribp           (u_xpi_ribp_if),
      .xpi            (xpi)
  );

  ribp_dma u_rib_dma (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .dma_xfer_done_o(s_dma_xfer_done),
      .hw_trg         (u_dma_hw_trg_if),
      .ribp           (u_dma_ribp_if),
      .rib            (dma_rib)
  );

  ribp_sysctrl u_rib_sysctrl (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .fault_valid_i   (fault_valid_i),
      .fault_addr_i    (fault_addr_i),
      .fault_wstrb_i   (fault_wstrb_i),
      .fault_reserved_i(fault_reserved_i),
      .ribp            (u_sysctrl_ribp_if),
      .sysctrl         (sysctrl),
      .pll_ctrl        (pll_ctrl)
  );

  ribp_clint u_rib_clint (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_clint_ribp_if),
      .clint  (u_clint_if)
  );

  ribp_sdram u_rib_sdram (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_sdram_ribp_if),
      .sdram  (sdram)
  );

  ribp_dvp u_rib_dvp (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_dvp_ribp_if),
      .dvp    (dvp)
  );

  ribp_sdio u_rib_sdio (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_sdio_ribp_if),
      .sdio   (sdio)
  );

  ribp_opipsram u_rib_opipsram (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_opipsram_ribp_if),
      .psram  (opipsram)
  );

  ribp_i2c u_rib_i2c1 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_i2c1_ribp_if),
      .i2c    (i2c1)
  );

endmodule
