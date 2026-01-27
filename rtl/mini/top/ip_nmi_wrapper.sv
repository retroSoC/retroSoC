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

module ip_nmi_wrapper (
    // verilog_format: off
    input logic        clk_i,
    input logic        rst_n_i,
    input logic        clk_aud_i,
    input logic        rst_aud_n_i,
    // natv if
    nmi_if.slave       nmi,
    nmi_gpio_if.dut    gpio,
    uart_if.dut        uart,
    psram_if.dut       psram,
    spi_if.dut         spisd,
    i2c_if.dut         i2c,
    nv_i2s_if.dut      i2s,
    onewire_if.dut     onewire,
    qspi_if.dut        qspi,
    nmi_if.master      dma_nmi,
    sysctrl_if.dut     sysctrl,
    sdram_if.dut       sdram,
    dvp_if.dut         dvp,
    // irq
    output logic [9:0] irq_o
    // verilog_format: on
);

  // bus interface
  nmi_if u_uart_nmi_if ();
  nmi_if u_gpio_nmi_if ();
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
  nmi_if u_clint_nmi_if ();
  nmi_if u_sdram_nmi_if ();
  nmi_if u_dvp_nmi_if ();
  // ip interface
  simp_clint_if u_clint_if ();
  dma_hw_trg_if u_dma_hw_trg_if ();

  logic s_psram_cfg_sel, s_psram_mem_sel;
  logic s_spisd_cfg_sel;
  logic s_sdram_cfg_sel, s_sdram_mem_sel;
  logic s_qspi_cfg_sel, s_qspi_mem_sel;
  logic s_dma_i2s_tx_stall, s_dma_i2s_rx_stall;
  logic s_dma_qspi_tx_stall, s_dma_qspi_rx_stall;
  logic s_dma_xfer_done;
  // irq
  logic s_tim0_irq, s_tim1_irq;


  // dma channel
  assign u_dma_hw_trg_if.i2s_tx_proc = ~s_dma_i2s_tx_stall;
  assign u_dma_hw_trg_if.i2s_rx_proc = ~s_dma_i2s_rx_stall;
  assign u_dma_hw_trg_if.qspi_tx_proc = ~s_dma_qspi_tx_stall;
  assign u_dma_hw_trg_if.qspi_rx_proc = ~s_dma_qspi_rx_stall;
  // gpio
  assign u_gpio_nmi_if.valid    = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_GPIO_START);
  assign u_gpio_nmi_if.addr     = nmi.addr;
  assign u_gpio_nmi_if.wdata    = nmi.wdata;
  assign u_gpio_nmi_if.wstrb    = nmi.wstrb;
  // uart
  assign u_uart_nmi_if.valid    = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_UART_START);
  assign u_uart_nmi_if.addr     = nmi.addr;
  assign u_uart_nmi_if.wdata    = nmi.wdata;
  assign u_uart_nmi_if.wstrb    = nmi.wstrb;
  // tim0
  assign u_tim0_nmi_if.valid    = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_TIM0_START);
  assign u_tim0_nmi_if.addr     = nmi.addr;
  assign u_tim0_nmi_if.wdata    = nmi.wdata;
  assign u_tim0_nmi_if.wstrb    = nmi.wstrb;
  // tim1
  assign u_tim1_nmi_if.valid    = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_TIM1_START);
  assign u_tim1_nmi_if.addr     = nmi.addr;
  assign u_tim1_nmi_if.wdata    = nmi.wdata;
  assign u_tim1_nmi_if.wstrb    = nmi.wstrb;
  // psram
  assign s_psram_cfg_sel        = nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_PSRAM_START;
  assign s_psram_mem_sel        = nmi.addr[31:28] == `PSRAM_START;
  assign u_psram_nmi_if.valid   = nmi.valid && (s_psram_mem_sel || s_psram_cfg_sel);
  assign u_psram_nmi_if.addr    = nmi.addr;
  assign u_psram_nmi_if.wdata   = nmi.wdata;
  assign u_psram_nmi_if.wstrb   = nmi.wstrb;
  // spisd
  assign s_spisd_cfg_sel        = nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_SPISD_START;
  assign u_spisd_nmi_if.valid   = nmi.valid && (nmi.addr[31:28] == `SPISD_START0 ||
                                                nmi.addr[31:28] == `SPISD_START1 ||
                                                nmi.addr[31:28] == `SPISD_START2 ||
                                                nmi.addr[31:28] == `SPISD_START3 || s_spisd_cfg_sel);
  assign u_spisd_nmi_if.addr    = nmi.addr;
  assign u_spisd_nmi_if.wdata   = nmi.wdata;
  assign u_spisd_nmi_if.wstrb   = nmi.wstrb;
  // i2c
  assign u_i2c_nmi_if.valid     = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_I2C_START);
  assign u_i2c_nmi_if.addr      = nmi.addr;
  assign u_i2c_nmi_if.wdata     = nmi.wdata;
  assign u_i2c_nmi_if.wstrb     = nmi.wstrb;
  // i2s
  assign u_i2s_nmi_if.valid     = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_I2S_START);
  assign u_i2s_nmi_if.addr      = nmi.addr;
  assign u_i2s_nmi_if.wdata     = nmi.wdata;
  assign u_i2s_nmi_if.wstrb     = nmi.wstrb;
  // onewire
  assign u_onewire_nmi_if.valid = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_ONEWIRE_START);
  assign u_onewire_nmi_if.addr  = nmi.addr;
  assign u_onewire_nmi_if.wdata = nmi.wdata;
  assign u_onewire_nmi_if.wstrb = nmi.wstrb;
  // qspi
  assign s_qspi_cfg_sel         = nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_QSPI_START;
  assign s_qspi_mem_sel         = nmi.addr[31:28] == `FLASH_START || nmi.addr[31:28] == `QSPI_MEM_START;
  assign u_qspi_nmi_if.valid    = nmi.valid && (s_qspi_cfg_sel || s_qspi_mem_sel);
  assign u_qspi_nmi_if.addr     = nmi.addr;
  assign u_qspi_nmi_if.wdata    = nmi.wdata;
  assign u_qspi_nmi_if.wstrb    = nmi.wstrb;
  // dma
  assign u_dma_nmi_if.valid     = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_DMA_START);
  assign u_dma_nmi_if.addr      = nmi.addr;
  assign u_dma_nmi_if.wdata     = nmi.wdata;
  assign u_dma_nmi_if.wstrb     = nmi.wstrb;
  // sysctrl
  assign u_sysctrl_nmi_if.valid = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_SYSCTRL_START);
  assign u_sysctrl_nmi_if.addr  = nmi.addr;
  assign u_sysctrl_nmi_if.wdata = nmi.wdata;
  assign u_sysctrl_nmi_if.wstrb = nmi.wstrb;
  // clint
  assign u_clint_nmi_if.valid   = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_CLINT_START);
  assign u_clint_nmi_if.addr    = nmi.addr;
  assign u_clint_nmi_if.wdata   = nmi.wdata;
  assign u_clint_nmi_if.wstrb   = nmi.wstrb;
  // sdram
  assign s_sdram_cfg_sel        = nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_SDRAM_START;
  assign s_sdram_mem_sel        = nmi.addr[31:24] >= `SDRAM_START && nmi.addr[31:24] <= `SDRAM_END;
  assign u_sdram_nmi_if.valid   = nmi.valid && (s_sdram_cfg_sel || s_sdram_mem_sel);
  assign u_sdram_nmi_if.addr    = nmi.addr;
  assign u_sdram_nmi_if.wdata   = nmi.wdata;
  assign u_sdram_nmi_if.wstrb   = nmi.wstrb;
  // dvp
  assign u_dvp_nmi_if.valid   = nmi.valid && (nmi.addr[31:28] == `NATV_IP_START && nmi.addr[15:8] == `NMI_DVP_START);
  assign u_dvp_nmi_if.addr    = nmi.addr;
  assign u_dvp_nmi_if.wdata   = nmi.wdata;
  assign u_dvp_nmi_if.wstrb   = nmi.wstrb;

  // verilog_format: off
  assign nmi.ready              = (u_uart_nmi_if.valid    & u_uart_nmi_if.ready)    |
                                  (u_gpio_nmi_if.valid    & u_gpio_nmi_if.ready)    |
                                  (u_tim0_nmi_if.valid    & u_tim0_nmi_if.ready)    |
                                  (u_tim1_nmi_if.valid    & u_tim1_nmi_if.ready)    |
                                  (u_psram_nmi_if.valid   & u_psram_nmi_if.ready)   |
                                  (u_spisd_nmi_if.valid   & u_spisd_nmi_if.ready)   |
                                  (u_i2c_nmi_if.valid     & u_i2c_nmi_if.ready)     |
                                  (u_i2s_nmi_if.valid     & u_i2s_nmi_if.ready)     |
                                  (u_onewire_nmi_if.valid & u_onewire_nmi_if.ready) |
                                  (u_qspi_nmi_if.valid    & u_qspi_nmi_if.ready)    |
                                  (u_dma_nmi_if.valid     & u_dma_nmi_if.ready)     |
                                  (u_sysctrl_nmi_if.valid & u_sysctrl_nmi_if.ready) |
                                  (u_clint_nmi_if.valid   & u_clint_nmi_if.ready)   |
                                  (u_sdram_nmi_if.valid   & u_sdram_nmi_if.ready)   |
                                  (u_dvp_nmi_if.valid     & u_dvp_nmi_if.ready);

  assign nmi.rdata              = ({32{(u_uart_nmi_if.valid    & u_uart_nmi_if.ready)}}    & u_uart_nmi_if.rdata)    |
                                  ({32{(u_gpio_nmi_if.valid    & u_gpio_nmi_if.ready)}}    & u_gpio_nmi_if.rdata)    |
                                  ({32{(u_tim0_nmi_if.valid    & u_tim0_nmi_if.ready)}}    & u_tim0_nmi_if.rdata)    |
                                  ({32{(u_tim1_nmi_if.valid    & u_tim1_nmi_if.ready)}}    & u_tim1_nmi_if.rdata)    |
                                  ({32{(u_psram_nmi_if.valid   & u_psram_nmi_if.ready)}}   & u_psram_nmi_if.rdata)   |
                                  ({32{(u_spisd_nmi_if.valid   & u_spisd_nmi_if.ready)}}   & u_spisd_nmi_if.rdata)   |
                                  ({32{(u_i2c_nmi_if.valid     & u_i2c_nmi_if.ready)}}     & u_i2c_nmi_if.rdata)     |
                                  ({32{(u_i2s_nmi_if.valid     & u_i2s_nmi_if.ready)}}     & u_i2s_nmi_if.rdata)     |
                                  ({32{(u_onewire_nmi_if.valid & u_onewire_nmi_if.ready)}} & u_onewire_nmi_if.rdata) |
                                  ({32{(u_qspi_nmi_if.valid    & u_qspi_nmi_if.ready)}}    & u_qspi_nmi_if.rdata)    |
                                  ({32{(u_dma_nmi_if.valid     & u_dma_nmi_if.ready)}}     & u_dma_nmi_if.rdata)     |
                                  ({32{(u_sysctrl_nmi_if.valid & u_sysctrl_nmi_if.ready)}} & u_sysctrl_nmi_if.rdata) |
                                  ({32{(u_clint_nmi_if.valid   & u_clint_nmi_if.ready)}}   & u_clint_nmi_if.rdata)   |
                                  ({32{(u_sdram_nmi_if.valid   & u_sdram_nmi_if.ready)}}   & u_sdram_nmi_if.rdata)   |
                                  ({32{(u_dvp_nmi_if.valid     & u_dvp_nmi_if.ready)}}     & u_dvp_nmi_if.rdata);
  // verilog_format: on

  // irq
  assign irq_o[0] = u_clint_if.sfr_irq_o;
  assign irq_o[1] = u_clint_if.tmr_irq_o;
  assign irq_o[2] = uart.irq_o;
  assign irq_o[3] = s_tim0_irq;
  assign irq_o[4] = s_tim1_irq;
  assign irq_o[5] = psram.irq_o;
  assign irq_o[6] = spisd.irq_o;
  assign irq_o[7] = i2c.irq_o;
  assign irq_o[8] = i2s.irq_o;
  assign irq_o[9] = qspi.irq_o;


  nmi_gpio u_nmi_gpio (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_gpio_nmi_if),
      .gpio   (gpio)
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

endmodule
