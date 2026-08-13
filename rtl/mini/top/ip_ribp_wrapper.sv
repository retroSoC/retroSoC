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
    input logic              debug_halted_i,
    input logic              timebase_tick_i,
    axi4_if.slave            cfg_axi4,
    axi4_if.slave            sdram_axi4,
    axi4_if.slave            psram_axi4,
    axi4_if.slave            xpi_axi4,
    axi4_if.slave            spisd_axi4,
    gpio_if.dut              gpio,
    user_gpio_if.padctrl     user_gpio,
    uart_if.dut              uart,
    psram_if.dut             psram,
    spi_if.dut               spisd,
    i2c_if.dut               i2c0,
    i2s_if.dut               i2s,
    ws2812_if.dut            ws2812,
    xpi_if.dut               xpi,
    axi4_if.master           dma_axi4,
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
  ribp_if u_sdram_data_ribp_if ();
  ribp_if u_sdram_target_ribp_if ();
  ribp_if u_psram_data_ribp_if ();
  ribp_if u_psram_target_ribp_if ();
  ribp_if u_xpi_data_ribp_if ();
  ribp_if u_xpi_target_ribp_if ();
  ribp_if u_spisd_data_ribp_if ();
  ribp_if u_spisd_target_ribp_if ();
  rib_if  u_dma_rib_if ();
  axi4_stream_if #(.DATA_WIDTH(32), .ID_WIDTH(1), .DEST_WIDTH(1), .USER_WIDTH(1))
      u_i2s_tx_axis_if (.aclk(clk_i), .aresetn(rst_n_i));
  axi4_stream_if #(.DATA_WIDTH(32), .ID_WIDTH(1), .DEST_WIDTH(1), .USER_WIDTH(1))
      u_i2s_rx_axis_if (.aclk(clk_i), .aresetn(rst_n_i));
  axi4_stream_if #(.DATA_WIDTH(32), .ID_WIDTH(1), .DEST_WIDTH(1), .USER_WIDTH(1))
      u_dvp_rx_axis_if (.aclk(clk_i), .aresetn(rst_n_i));
  // verilog_format: on

  clint_if u_clint_if ();
  dma_hw_trg_if u_dma_hw_trg_if ();

  logic s_dma_i2s_tx_stall, s_dma_i2s_rx_stall;
  logic s_dma_xpi_tx_stall, s_dma_xpi_rx_stall;
  logic s_dma_uart_tx_stall, s_dma_uart_rx_stall;
  logic s_dma_i2c0_tx_stall, s_dma_i2c0_rx_stall;
  logic s_dma_i2c1_tx_stall, s_dma_i2c1_rx_stall;
  logic s_dma_xfer_done;
  logic s_tim0_irq, s_tim1_irq;
  logic s_dvp_irq;

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

  axi42ribp u_axi42ribp (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (cfg_axi4),
      .ribp   (ribp)
  );

  axi42ribp_burst u_sdram_axi42ribp (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (sdram_axi4),
      .ribp   (u_sdram_data_ribp_if)
  );

  axi42ribp_burst u_psram_axi42ribp (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (psram_axi4),
      .ribp   (u_psram_data_ribp_if)
  );

  axi42ribp_burst u_xpi_axi42ribp (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (xpi_axi4),
      .ribp   (u_xpi_data_ribp_if)
  );

  axi42ribp_burst u_spisd_axi42ribp (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (spisd_axi4),
      .ribp   (u_spisd_data_ribp_if)
  );

  ribp_arbiter2 u_sdram_ribp_arbiter (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .cfg    (u_sdram_ribp_if),
      .data   (u_sdram_data_ribp_if),
      .target (u_sdram_target_ribp_if)
  );

  ribp_arbiter2 u_psram_ribp_arbiter (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .cfg    (u_psram_ribp_if),
      .data   (u_psram_data_ribp_if),
      .target (u_psram_target_ribp_if)
  );

  ribp_arbiter2 u_xpi_ribp_arbiter (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .cfg    (u_xpi_ribp_if),
      .data   (u_xpi_data_ribp_if),
      .target (u_xpi_target_ribp_if)
  );

  ribp_arbiter2 u_spisd_ribp_arbiter (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .cfg    (u_spisd_ribp_if),
      .data   (u_spisd_data_ribp_if),
      .target (u_spisd_target_ribp_if)
  );

  rib2axi4 u_dma_rib2axi4 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .rib    (u_dma_rib_if),
      .axi4   (dma_axi4)
  );

  // Generated target routing operates on the RIBP configuration boundary
  // behind the AXI4 adapter. Register targets therefore remain INCR1-only.

  assign u_dma_hw_trg_if.i2s_tx_proc  = ~s_dma_i2s_tx_stall;
  assign u_dma_hw_trg_if.i2s_rx_proc  = ~s_dma_i2s_rx_stall;
  assign u_dma_hw_trg_if.qspi_tx_proc = ~s_dma_xpi_tx_stall;
  assign u_dma_hw_trg_if.qspi_rx_proc = ~s_dma_xpi_rx_stall;
  assign u_dma_hw_trg_if.uart_tx_proc = ~s_dma_uart_tx_stall;
  assign u_dma_hw_trg_if.uart_rx_proc = ~s_dma_uart_rx_stall;
  assign u_dma_hw_trg_if.i2c0_tx_proc = ~s_dma_i2c0_tx_stall;
  assign u_dma_hw_trg_if.i2c0_rx_proc = ~s_dma_i2c0_rx_stall;
  assign u_dma_hw_trg_if.i2c1_tx_proc = ~s_dma_i2c1_tx_stall;
  assign u_dma_hw_trg_if.i2c1_rx_proc = ~s_dma_i2c1_rx_stall;

  // Uses ClusterIP common ribp_if and register.sv dffr through generated bindings.
  `include "ribp_routes.svh"

  // verilog_format: off
  // Generated IRQ ownership and core-vector bit assignments are topology checked.
  `include "ribp_irq_bindings.svh"

  ribp_gpio #(
      .USER_BASE_ADDR (`SOC_ADDR_RIBP_GPIO_BASE),
      .ADMIN_BASE_ADDR(`SOC_ADDR_RIBP_GPIO_ADMIN_BASE),
      .HAS_INPUT_CMOS (GPIO_HAS_INPUT_CMOS),
      .HAS_PULL_UP    (GPIO_HAS_PULL_UP),
      .HAS_PULL_DOWN  (GPIO_HAS_PULL_DOWN)
  ) u_rib_gpio (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .ribp      (u_gpio_ribp_if),
      .gpio      (gpio),
      .user_gpio (user_gpio)
  );
  // verilog_format: on

  ribp_uart u_rib_uart (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .dma_tx_stall_o(s_dma_uart_tx_stall),
      .dma_rx_stall_o(s_dma_uart_rx_stall),
      .ribp          (u_uart_ribp_if),
      .uart          (uart)
  );

  ribp_timer u_rib_timer0 (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .debug_halted_i(debug_halted_i),
      .ribp          (u_tim0_ribp_if),
      .irq_o         (s_tim0_irq)
  );

  ribp_timer u_rib_timer1 (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .debug_halted_i(debug_halted_i),
      .ribp          (u_tim1_ribp_if),
      .irq_o         (s_tim1_irq)
  );

  ribp_psram u_rib_psram (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_psram_target_ribp_if),
      .psram  (psram)
  );

  ribp_spisd u_rib_spisd (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_spisd_target_ribp_if),
      .spi    (spisd)
  );

  ribp_i2c u_rib_i2c0 (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .dma_tx_stall_o(s_dma_i2c0_tx_stall),
      .dma_rx_stall_o(s_dma_i2c0_rx_stall),
      .ribp          (u_i2c0_ribp_if),
      .i2c           (i2c0)
  );

  ribp_i2s u_rib_i2s (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .clk_aud_i     (clk_aud_i),
      .rst_aud_n_i   (rst_aud_n_i),
      .dma_tx_stall_o(s_dma_i2s_tx_stall),
      .dma_rx_stall_o(s_dma_i2s_rx_stall),
      .ribp          (u_i2s_ribp_if),
      .tx_axis       (u_i2s_tx_axis_if),
      .rx_axis       (u_i2s_rx_axis_if),
      .i2s           (i2s)
  );

  ribp_ws2812 u_rib_ws2812 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_ws2812_ribp_if),
      .ws2812 (ws2812)
  );

  ribp_xpi u_rib_xpi (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .dma_xfer_done_i(s_dma_xfer_done),
      .dma_tx_stall_o (s_dma_xpi_tx_stall),
      .dma_rx_stall_o (s_dma_xpi_rx_stall),
      .ribp           (u_xpi_target_ribp_if),
      .xpi            (xpi)
  );

  ribp_dma u_rib_dma (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .dma_xfer_done_o(s_dma_xfer_done),
      .hw_trg         (u_dma_hw_trg_if),
      .ribp           (u_dma_ribp_if),
      .rib            (u_dma_rib_if),
      .i2s_tx_axis    (u_i2s_tx_axis_if),
      .i2s_rx_axis    (u_i2s_rx_axis_if),
      .dvp_rx_axis    (u_dvp_rx_axis_if)
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
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .timebase_tick_i(timebase_tick_i),
      .ribp           (u_clint_ribp_if),
      .clint          (u_clint_if)
  );

  ribp_sdram u_rib_sdram (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_sdram_target_ribp_if),
      .sdram  (sdram)
  );

  ribp_dvp u_rib_dvp (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (u_dvp_ribp_if),
      .rx_axis(u_dvp_rx_axis_if),
      .dvp    (dvp),
      .irq_o  (s_dvp_irq)
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
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .dma_tx_stall_o(s_dma_i2c1_tx_stall),
      .dma_rx_stall_o(s_dma_i2c1_rx_stall),
      .ribp          (u_i2c1_ribp_if),
      .i2c           (i2c1)
  );

endmodule
