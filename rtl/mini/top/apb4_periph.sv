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

module apb4_periph (
    // verilog_format: off -- preserve reviewed column alignment
    input logic                                   clk_i,
    input logic                                   rst_n_i,
    input logic                                   clk_aud_i,
    input logic                                   rst_aud_n_i,
    input logic                                   debug_halted_i,
    input logic                                   timebase_tick_i,
    axi4_if.slave                                 cfg_axi4,
    axi4_if.slave                                 psram_axi4,
    axi4_if.slave                                 xpi_axi4,
    axi4_if.master                                spisd_axi4,
    axi4_if.slave                                 opipsram_axi4,
    gpio_if.dut                                   gpio,
    user_gpio_if.padctrl                          user_gpio,
    uart_if.dut                                   uart,
    psram_if.dut                                  psram,
    spi_if.dut                                    spisd,
    i2c_if.dut                                    i2c0,
    i2s_if.dut                                    i2s,
    ws2812_if.dut                                 ws2812,
    xpi_if.dut                                    xpi,
    axi4_if.master                                dma_axi4,
    axi4_if.master                                sdio0_axi4,
    axi4_if.master                                sdio1_axi4,
    sysctrl_if.dut                                sysctrl,
    pll_ctrl_if.sysctrl                           pll_ctrl,
    apb4_if.master                                sdram_cfg,
    dvp_if.dut                                    dvp,
    sdio_if.dut                                   sdio0,
    sdio_if.dut                                   sdio1,
    opipsram_if.dut                               opipsram,
    i2c_if.dut                                    i2c1,
    input logic                                   fault_valid_i,
    input logic [31:0]                            fault_addr_i,
    input logic [3:0]                             fault_wstrb_i,
    input logic                                   fault_reserved_i,
    output logic [`SOC_IRQ_APB4_PERIPH_WIDTH-1:0] irq_o
    // verilog_format: on
);

  // Generated timed and pure scalar APB interfaces preserve FPGA compatibility.
  `include "apb4_periph_interfaces.svh"
  `include "apb4_periph_bridges.svh"

axi4_stream_if #(
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .DEST_WIDTH(1),
      .USER_WIDTH(1)
  ) u_i2s_tx_axis_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .DEST_WIDTH(1),
      .USER_WIDTH(1)
  ) u_i2s_rx_axis_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .DEST_WIDTH(1),
      .USER_WIDTH(1)
  ) u_dvp_rx_axis_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .DEST_WIDTH(1),
      .USER_WIDTH(1)
  ) u_crypto_in_axis_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .DEST_WIDTH(1),
      .USER_WIDTH(1)
  ) u_crypto_out_axis_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  clint_if u_clint_if ();
  dma_req_if u_dma_req_if ();

  logic s_dma_i2s_tx_stall, s_dma_i2s_rx_stall;
  logic s_dma_xpi_tx_stall, s_dma_xpi_rx_stall;
  logic s_dma_uart_tx_stall, s_dma_uart_rx_stall;
  logic s_dma_i2c0_tx_stall, s_dma_i2c0_rx_stall;
  logic s_dma_i2c1_tx_stall, s_dma_i2c1_rx_stall;
  logic s_dma_xfer_done;
  logic s_dma_irq;
  logic s_dma_crypto_in_proc;
  logic s_dma_crypto_out_proc;
  logic s_crypto_irq;
  logic s_tim0_irq, s_tim1_irq;
  logic s_dvp_irq;
  logic s_xpi_irq;

`ifdef PDK_GF180
  localparam bit GPIO_HAS_INPUT_CMOS = 1'b1;
  localparam bit GPIO_HAS_PULL_UP = 1'b1;
  localparam bit GPIO_HAS_PULL_DOWN = 1'b1;
`elsif PDK_ICS55
  localparam bit GPIO_HAS_INPUT_CMOS = 1'b1;
  localparam bit GPIO_HAS_PULL_UP = 1'b1;
  localparam bit GPIO_HAS_PULL_DOWN = 1'b1;
`elsif PDK_SKY130
  localparam bit GPIO_HAS_INPUT_CMOS = 1'b1;
  localparam bit GPIO_HAS_PULL_UP = 1'b0;
  localparam bit GPIO_HAS_PULL_DOWN = 1'b0;
`else
  localparam bit GPIO_HAS_INPUT_CMOS = 1'b0;
  localparam bit GPIO_HAS_PULL_UP = 1'b0;
  localparam bit GPIO_HAS_PULL_DOWN = 1'b0;
`endif

  axi42apb4_periph u_axi42apb4_periph (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (cfg_axi4),
      `include "apb4_periph_connections.svh"
  );

  assign u_dma_req_if.i2s_tx_proc     = ~s_dma_i2s_tx_stall;
  assign u_dma_req_if.i2s_rx_proc     = ~s_dma_i2s_rx_stall;
  assign u_dma_req_if.qspi_tx_proc    = ~s_dma_xpi_tx_stall;
  assign u_dma_req_if.qspi_rx_proc    = ~s_dma_xpi_rx_stall;
  assign u_dma_req_if.uart_tx_proc    = ~s_dma_uart_tx_stall;
  assign u_dma_req_if.uart_rx_proc    = ~s_dma_uart_rx_stall;
  assign u_dma_req_if.i2c0_tx_proc    = ~s_dma_i2c0_tx_stall;
  assign u_dma_req_if.i2c0_rx_proc    = ~s_dma_i2c0_rx_stall;
  assign u_dma_req_if.i2c1_tx_proc    = ~s_dma_i2c1_tx_stall;
  assign u_dma_req_if.i2c1_rx_proc    = ~s_dma_i2c1_rx_stall;
  assign u_dma_req_if.crypto_in_proc  = s_dma_crypto_in_proc;
  assign u_dma_req_if.crypto_out_proc = s_dma_crypto_out_proc;

  `include "apb4_periph_irq_bindings.svh"

  // verilog_format: off -- preserve reviewed column alignment
  apb4_gpio #(
      .UserBaseAddr (`SOC_ADDR_APB4_GPIO_BASE),
      .AdminBaseAddr(`SOC_ADDR_APB4_GPIO_ADMIN_BASE),
      .HasInputCmos (GPIO_HAS_INPUT_CMOS),
      .HasPullUp    (GPIO_HAS_PULL_UP),
      .HasPullDown  (GPIO_HAS_PULL_DOWN)
  ) u_apb4_gpio (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .apb4      (u_gpio_apb4_if),
      .gpio      (gpio),
      .user_gpio (user_gpio)
  );
  // verilog_format: on

  apb4_uart u_apb4_uart (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .dma_tx_stall_o(s_dma_uart_tx_stall),
      .dma_rx_stall_o(s_dma_uart_rx_stall),
      .apb4          (u_uart_apb4_if),
      .uart          (uart)
  );

  apb4_timer u_apb4_timer0 (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .debug_halted_i(debug_halted_i),
      .apb4          (u_tim0_apb4_if),
      .irq_o         (s_tim0_irq)
  );

  apb4_timer u_apb4_timer1 (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .debug_halted_i(debug_halted_i),
      .apb4          (u_tim1_apb4_if),
      .irq_o         (s_tim1_irq)
  );

  apb4_psram u_apb4_psram (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .cfg_apb4(u_psram_apb4_if),
      .mem_axi4(psram_axi4),
      .psram   (psram)
  );

  apb4_spisd u_apb4_spisd (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .apb4    (u_spisd_apb4_if),
      .dma_axi4(spisd_axi4),
      .spi     (spisd)
  );

  apb4_i2c u_apb4_i2c0 (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .dma_tx_stall_o(s_dma_i2c0_tx_stall),
      .dma_rx_stall_o(s_dma_i2c0_rx_stall),
      .apb4          (u_i2c0_apb4_if),
      .i2c           (i2c0)
  );

  apb4_i2s u_apb4_i2s (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .clk_aud_i     (clk_aud_i),
      .rst_aud_n_i   (rst_aud_n_i),
      .dma_tx_stall_o(s_dma_i2s_tx_stall),
      .dma_rx_stall_o(s_dma_i2s_rx_stall),
      .apb4          (u_i2s_apb4_if),
      .tx_axis       (u_i2s_tx_axis_if),
      .rx_axis       (u_i2s_rx_axis_if),
      .i2s           (i2s)
  );

  apb4_ws2812 u_apb4_ws2812 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .apb4   (u_ws2812_apb4_if),
      .ws2812 (ws2812)
  );

  apb4_xpi u_apb4_xpi (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .dma_xfer_done_i(s_dma_xfer_done),
      .dma_tx_stall_o (s_dma_xpi_tx_stall),
      .dma_rx_stall_o (s_dma_xpi_rx_stall),
      .irq_o          (s_xpi_irq),
      .apb4           (u_xpi_apb4_if),
      .mem_axi4       (xpi_axi4),
      .xpi            (xpi)
  );

  apb4_dma #(
      .NumChannels(6)
  ) u_apb4_dma (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .dma_xfer_done_o(s_dma_xfer_done),
      .irq_o          (s_dma_irq),
      .hw_trg         (u_dma_req_if),
      .apb4           (u_dma_apb4_if),
      .axi4           (dma_axi4),
      .i2s_tx_axis    (u_i2s_tx_axis_if),
      .i2s_rx_axis    (u_i2s_rx_axis_if),
      .dvp_rx_axis    (u_dvp_rx_axis_if),
      .crypto_in_axis (u_crypto_in_axis_if),
      .crypto_out_axis(u_crypto_out_axis_if)
  );

  apb4_crypto u_apb4_crypto (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .dma_input_proc_o (s_dma_crypto_in_proc),
      .dma_output_proc_o(s_dma_crypto_out_proc),
      .irq_o            (s_crypto_irq),
      .apb4             (u_crypto_apb4_if),
      .crypto_in_axis   (u_crypto_in_axis_if),
      .crypto_out_axis  (u_crypto_out_axis_if)
  );

  apb4_sysctrl u_apb4_sysctrl (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .fault_valid_i   (fault_valid_i),
      .fault_addr_i    (fault_addr_i),
      .fault_wstrb_i   (fault_wstrb_i),
      .fault_reserved_i(fault_reserved_i),
      .apb4            (u_sysctrl_apb4_if),
      .sysctrl         (sysctrl),
      .pll_ctrl        (pll_ctrl)
  );

  apb4_clint u_apb4_clint (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .timebase_tick_i(timebase_tick_i),
      .apb4           (u_clint_apb4_if),
      .clint          (u_clint_if)
  );

  axi4s_dvp u_axi4_dvp (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .apb4   (u_dvp_apb4_if),
      .rx_axis(u_dvp_rx_axis_if),
      .dvp    (dvp),
      .irq_o  (s_dvp_irq)
  );

  apb4_sdio u_apb4_sdio0 (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .apb4    (u_sdio0_apb4_if),
      .dma_axi4(sdio0_axi4),
      .sdio    (sdio0)
  );

  apb4_sdio u_apb4_sdio1 (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .apb4    (u_sdio1_apb4_if),
      .dma_axi4(sdio1_axi4),
      .sdio    (sdio1)
  );

  apb4_opipsram u_apb4_opipsram (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .clk_phy_i  (clk_i),
      .rst_phy_n_i(rst_n_i),
      .cfg_apb4   (u_opipsram_apb4_if),
      .mem_axi4   (opipsram_axi4),
      .psram      (opipsram)
  );

  apb4_i2c u_apb4_i2c1 (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .dma_tx_stall_o(s_dma_i2c1_tx_stall),
      .dma_rx_stall_o(s_dma_i2c1_rx_stall),
      .apb4          (u_i2c1_apb4_if),
      .i2c           (i2c1)
  );

endmodule
