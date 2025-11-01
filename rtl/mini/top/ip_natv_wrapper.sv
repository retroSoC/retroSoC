// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// addr range: [31:28]: 4'h1(reg), 4'h4(psram), 4'h5(spisd)
`include "mmap_define.svh"

module ip_natv_wrapper (
    // verilog_format: off
    input logic        clk_i,
    input logic        rst_n_i,
    input logic        clk_aud_i,
    input logic        rst_aud_n_i,
    // natv if
    nmi_if.slave       nmi,
    simp_gpio_if.dut   gpio,
    uart_if.dut        uart,
    qspi_if.dut        psram,
    spi_if.dut         spisd,
    i2c_if.dut         i2c,
    nv_i2s_if.dut      i2s,
    onewire_if.dut     onewire,
    qspi_if.dut        qspi,
    nmi_if.master      dma_nmi,
    sysctrl_if.dut     sysctrl,
    // irq
    output logic [2:0] irq_o
    // verilog_format: on
);

  nmi_if u_gpio_nmi_if ();
  nmi_if u_uart_nmi_if ();
  nmi_if u_tim0_nmi_if ();
  nmi_if u_tim1_nmi_if ();
  nmi_if u_psram_nmi_if ();
  nmi_if u_spisd_nmi_if ();
  nmi_if u_i2c_nmi_if ();
  nmi_if u_i2s_nmi_if ();
  nmi_if u_onewire_nmi_if ();
  nmi_if u_qspi_nmi_if ();
  nmi_if u_dma_nmi_if ();
  nmi_if u_sysctrl_nmi_if ();

  dma_hw_trg_if u_dma_hw_trg_if ();

  logic s_psram_cfg_sel, s_psram_mem_sel;
  logic s_spisd_cfg_sel;
  logic s_dma_i2s_tx_stall, s_dma_i2s_rx_stall;
  logic s_dma_qspi_tx_stall, s_dma_qspi_rx_stall;

  // dma channel
  assign u_dma_hw_trg_if.i2s_tx_proc = ~s_dma_i2s_tx_stall;
  assign u_dma_hw_trg_if.i2s_rx_proc = ~s_dma_i2s_rx_stall;
  assign u_dma_hw_trg_if.qspi_tx_proc = ~s_dma_qspi_tx_stall;
  assign u_dma_hw_trg_if.qspi_rx_proc = ~s_dma_qspi_rx_stall;
  // addr
  assign u_gpio_nmi_if.valid    = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_GPIO_START);
  assign u_gpio_nmi_if.addr     = nmi.addr;
  assign u_gpio_nmi_if.wdata    = nmi.wdata;
  assign u_gpio_nmi_if.wstrb    = nmi.wstrb;

  assign u_uart_nmi_if.valid    = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_UART_START);
  assign u_uart_nmi_if.addr     = nmi.addr;
  assign u_uart_nmi_if.wdata    = nmi.wdata;
  assign u_uart_nmi_if.wstrb    = nmi.wstrb;

  assign u_tim0_nmi_if.valid    = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_TIM0_START);
  assign u_tim0_nmi_if.addr     = nmi.addr;
  assign u_tim0_nmi_if.wdata    = nmi.wdata;
  assign u_tim0_nmi_if.wstrb    = nmi.wstrb;

  assign u_tim1_nmi_if.valid    = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_TIM1_START);
  assign u_tim1_nmi_if.addr     = nmi.addr;
  assign u_tim1_nmi_if.wdata    = nmi.wdata;
  assign u_tim1_nmi_if.wstrb    = nmi.wstrb;

  assign s_psram_cfg_sel        = nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_PSRAM_START;
  assign s_psram_mem_sel        = nmi.addr[31:28] == `PSRAM_START;
  assign u_psram_nmi_if.valid   = nmi.valid && (s_psram_mem_sel || s_psram_cfg_sel);
  assign u_psram_nmi_if.addr    = nmi.addr;
  assign u_psram_nmi_if.wdata   = nmi.wdata;
  assign u_psram_nmi_if.wstrb   = nmi.wstrb;

  assign s_spisd_cfg_sel        = nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_SPISD_START;
  assign u_spisd_nmi_if.valid   = nmi.valid && (nmi.addr[31:28] == `SPISD_START0 ||
                                                nmi.addr[31:28] == `SPISD_START1 ||
                                                nmi.addr[31:28] == `SPISD_START2 ||
                                                nmi.addr[31:28] == `SPISD_START3 || s_spisd_cfg_sel);
  assign u_spisd_nmi_if.addr    = nmi.addr;
  assign u_spisd_nmi_if.wdata   = nmi.wdata;
  assign u_spisd_nmi_if.wstrb   = nmi.wstrb;

  assign u_i2c_nmi_if.valid     = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_I2C_START);
  assign u_i2c_nmi_if.addr      = nmi.addr;
  assign u_i2c_nmi_if.wdata     = nmi.wdata;
  assign u_i2c_nmi_if.wstrb     = nmi.wstrb;

  assign u_i2s_nmi_if.valid     = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_I2S_START);
  assign u_i2s_nmi_if.addr      = nmi.addr;
  assign u_i2s_nmi_if.wdata     = nmi.wdata;
  assign u_i2s_nmi_if.wstrb     = nmi.wstrb;

  assign u_onewire_nmi_if.valid   = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_ONEWIRE_START);
  assign u_onewire_nmi_if.addr    = nmi.addr;
  assign u_onewire_nmi_if.wdata   = nmi.wdata;
  assign u_onewire_nmi_if.wstrb   = nmi.wstrb;

  assign u_qspi_nmi_if.valid      = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_QSPI_START);
  assign u_qspi_nmi_if.addr       = nmi.addr;
  assign u_qspi_nmi_if.wdata      = nmi.wdata;
  assign u_qspi_nmi_if.wstrb      = nmi.wstrb;

  assign u_dma_nmi_if.valid       = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_DMA_START);
  assign u_dma_nmi_if.addr        = nmi.addr;
  assign u_dma_nmi_if.wdata       = nmi.wdata;
  assign u_dma_nmi_if.wstrb       = nmi.wstrb;

  assign u_sysctrl_nmi_if.valid   = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_SYSCTRL_START);
  assign u_sysctrl_nmi_if.addr    = nmi.addr;
  assign u_sysctrl_nmi_if.wdata   = nmi.wdata;
  assign u_sysctrl_nmi_if.wstrb   = nmi.wstrb;

  // verilog_format: off
  assign nmi.ready              = (u_gpio_nmi_if.valid    & u_gpio_nmi_if.ready)  |
                                  (u_uart_nmi_if.valid    & u_uart_nmi_if.ready)  |
                                  (u_tim0_nmi_if.valid    & u_tim0_nmi_if.ready)  |
                                  (u_tim1_nmi_if.valid    & u_tim1_nmi_if.ready)  |
                                  (u_psram_nmi_if.valid   & u_psram_nmi_if.ready) |
                                  (u_spisd_nmi_if.valid   & u_spisd_nmi_if.ready) |
                                  (u_i2c_nmi_if.valid     & u_i2c_nmi_if.ready) |
                                  (u_i2s_nmi_if.valid     & u_i2s_nmi_if.ready) |
                                  (u_onewire_nmi_if.valid & u_onewire_nmi_if.ready) |
                                  (u_qspi_nmi_if.valid    & u_qspi_nmi_if.ready) |
                                  (u_dma_nmi_if.valid     & u_dma_nmi_if.ready) |
                                  (u_sysctrl_nmi_if.valid & u_sysctrl_nmi_if.ready);

  assign nmi.rdata              = ({32{(u_gpio_nmi_if.valid    & u_gpio_nmi_if.ready)}}    & u_gpio_nmi_if.rdata)  |
                                  ({32{(u_uart_nmi_if.valid    & u_uart_nmi_if.ready)}}    & u_uart_nmi_if.rdata)  |
                                  ({32{(u_tim0_nmi_if.valid    & u_tim0_nmi_if.ready)}}    & u_tim0_nmi_if.rdata)  |
                                  ({32{(u_tim1_nmi_if.valid    & u_tim1_nmi_if.ready)}}    & u_tim1_nmi_if.rdata)  |
                                  ({32{(u_psram_nmi_if.valid   & u_psram_nmi_if.ready)}}   & u_psram_nmi_if.rdata) |
                                  ({32{(u_spisd_nmi_if.valid   & u_spisd_nmi_if.ready)}}   & u_spisd_nmi_if.rdata) |
                                  ({32{(u_i2c_nmi_if.valid     & u_i2c_nmi_if.ready)}}     & u_i2c_nmi_if.rdata) |
                                  ({32{(u_i2s_nmi_if.valid     & u_i2s_nmi_if.ready)}}     & u_i2s_nmi_if.rdata) |
                                  ({32{(u_onewire_nmi_if.valid & u_onewire_nmi_if.ready)}} & u_onewire_nmi_if.rdata) |
                                  ({32{(u_qspi_nmi_if.valid    & u_qspi_nmi_if.ready)}}    & u_qspi_nmi_if.rdata) |
                                  ({32{(u_dma_nmi_if.valid     & u_dma_nmi_if.ready)}}     & u_dma_nmi_if.rdata) |
                                  ({32{(u_sysctrl_nmi_if.valid & u_sysctrl_nmi_if.ready)}} & u_sysctrl_nmi_if.rdata);
 // verilog_format: on

  assign irq_o[0]               = uart.irq_o;
  simple_gpio u_simple_gpio (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_gpio_nmi_if),
      .gpio   (gpio)
  );

  simple_uart u_simple_uart (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_uart_nmi_if),
      .uart   (uart)
  );

  simple_timer u_simple_timer0 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_tim0_nmi_if),
      .irq_o  (irq_o[1])
  );

  simple_timer u_simple_timer1 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_tim1_nmi_if),
      .irq_o  (irq_o[2])
  );

  nmi_psram u_nmi_psram (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_psram_nmi_if),
      .qspi   (psram)
  );

  nmi_spisd u_nmi_spisd (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_spisd_nmi_if),
      .spi    (spisd)
  );

  nmi_i2c u_nmi_i2c (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_i2c_nmi_if),
      .i2c    (i2c)
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

  nmi_qspi u_nmi_qspi (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .dma_xfer_done_i(s_dma_xfer_done),
      .dma_tx_stall_o (s_dma_qspi_tx_stall),
      .dma_rx_stall_o (s_dma_qspi_rx_stall),
      .nmi            (u_qspi_nmi_if),
      .qspi           (qspi)
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
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_sysctrl_nmi_if),
      .sysctrl(sysctrl)
  );
endmodule
