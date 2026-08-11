// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "gpio_define.svh"
`include "soc_clock_config.svh"
`include "user_extensions.svh"

// GPIO mux reference. The executable source of truth is
// rtl/mini/integration/soc_topology.json. ALT_ENABLE selects the alternate
// path, ALT_SELECT chooses ALT0/ALT1, and USER_SELECT gives the pin to User IP.
//
// GPIO    ALT0                         DIR     ALT1                    DIR
// ------  ---------------------------  ------  ----------------------  ------
// GPIO00  UART0_CTS_N                  IN      PS2_CLK                 BIDI
// GPIO01  UART0_RTS_N                  OUT     PS2_DATA                BIDI
// GPIO02  PWM_SYNC                     IN      WS2812_DATA             OUT
// GPIO03  PWM0                         OUT     I2C1_SCL                BIDI
// GPIO04  PWM1                         OUT     I2C1_SDA                BIDI
// GPIO05  PWM2                         OUT     CLKDIV4                 OUT
// GPIO06  PWM3                         OUT     SPISD_SCK               OUT
// GPIO07  I2C0_SCL                     BIDI    SPISD_NSS               OUT
// GPIO08  I2C0_SDA                     BIDI    SPISD_MOSI              OUT
// GPIO09  PWM_FAULT                    IN      SPISD_MISO              IN
// GPIO10  I2S_MCLK                     OUT     DVP_PCLK                IN
// GPIO11  I2S_SCLK                     OUT     DVP_HREF                IN
// GPIO12  I2S_LRCK                     OUT     DVP_VSYNC               IN
// GPIO13  I2S_DAC_DATA                 OUT     DVP_DATA0               IN
// GPIO14  I2S_ADC_DATA                 IN      DVP_DATA1               IN
// GPIO15  SDIO_SCK                     OUT     DVP_DATA2               IN
// GPIO16  SDIO_CMD                     BIDI    DVP_DATA3               IN
// GPIO17  SDIO_DATA0                   BIDI    DVP_DATA4               IN
// GPIO18  SDIO_DATA1                   BIDI    DVP_DATA5               IN
// GPIO19  SDIO_DATA2                   BIDI    DVP_DATA6               IN
// GPIO20  SDIO_DATA3                   BIDI    DVP_DATA7               IN
// GPIO21  OPI_PSRAM_SCK                OUT     QSPI_PSRAM_SCK          OUT
// GPIO22  OPI_PSRAM_CE                 OUT     QSPI_PSRAM_NSS0         OUT
// GPIO23  OPI_PSRAM_IO0                BIDI    QSPI_PSRAM_IO0          BIDI
// GPIO24  OPI_PSRAM_IO1                BIDI    QSPI_PSRAM_IO1          BIDI
// GPIO25  OPI_PSRAM_IO2                BIDI    QSPI_PSRAM_IO2          BIDI
// GPIO26  OPI_PSRAM_IO3                BIDI    QSPI_PSRAM_IO3          BIDI
// GPIO27  OPI_PSRAM_IO4                BIDI    QSPI_PSRAM_NSS1         OUT
// GPIO28  OPI_PSRAM_IO5                BIDI    QSPI_PSRAM_NSS2         OUT
// GPIO29  OPI_PSRAM_IO6                BIDI    QSPI_PSRAM_NSS3         OUT
// GPIO30  OPI_PSRAM_IO7                BIDI    PWM_CAPTURE0            IN
// GPIO31  OPI_PSRAM_DQS                BIDI    PWM_CAPTURE1            IN

module retrosoc_asic (
    `include "retrosoc_asic_ports.svh"
);
  logic s_ext_clk;
  logic s_aud_clk;
  logic s_sys_clkdiv4;
  logic s_timebase_tick;
`ifdef HAVE_PLL
  logic s_xtal_io;
`endif
  logic       s_sys_clk;
  logic       s_ext_rst_n;
  logic       s_sys_rst_n;
  logic       s_aud_rst_n;
  logic       s_wdg_reset_req;
  logic       s_jtag_tck;
  logic       s_jtag_tms;
  logic       s_jtag_tdi;
  logic       s_jtag_trst_n;
  logic       s_jtag_tdo;
  logic       s_uart0_rx;
  logic       s_uart0_tx;
  (* keep = "true" *)logic       s_test_done;
  (* keep = "true" *)logic       s_test_pass;
  (* keep = "true" *)logic [7:0] s_test_code;

`ifdef HAVE_SRAM_IF
  ram_if u_ram_if ();
`endif

  gpio_if u_gpio_if ();
  xpi_if u_xpi_if ();
  sdram_if u_sdram_if ();
  pll_ctrl_if u_pll_ctrl_if ();

  `include "retrosoc_asic_pad_bindings.svh"

rcu #(
      .EXT_CLK_HZ       (`SOC_EXT_CLK_HZ),
      .CLINT_TIMEBASE_HZ(`SOC_CLINT_TIMEBASE_HZ)
  ) u_rcu (
      .ext_clk_i      (s_ext_clk),
      .aud_clk_i      (s_aud_clk),
      .ext_rst_n_i    (s_ext_rst_n),
      .wdg_reset_req_i(s_wdg_reset_req),
`ifdef HAVE_PLL
      .xtal_clk_i     (s_xtal_io),
`endif
      .pll_ctrl       (u_pll_ctrl_if),
      .sys_clk_o      (s_sys_clk),
      .sys_rst_n_o    (s_sys_rst_n),
      .aud_rst_n_o    (s_aud_rst_n),
      .sys_clkdiv4_o  (s_sys_clkdiv4),
      .timebase_tick_o(s_timebase_tick)
  );

`ifdef HAVE_SRAM_IF
  onchip_ram u_onchip_ram (
      .clk_i(s_sys_clk),
      .ram  (u_ram_if)
  );
`endif

  retrosoc u_retrosoc (
      .clk_i          (s_sys_clk),
      .rst_n_i        (s_sys_rst_n),
      .clk_aud_i      (s_aud_clk),
      .rst_aud_n_i    (s_aud_rst_n),
      .clkdiv4_i      (s_sys_clkdiv4),
      .timebase_tick_i(s_timebase_tick),
      .pll_ctrl       (u_pll_ctrl_if),
`ifdef HAVE_SRAM_IF
      .ram            (u_ram_if),
`endif
      .gpio           (u_gpio_if),
      .uart_rx_i      (s_uart0_rx),
      .uart_tx_o      (s_uart0_tx),
      .xpi            (u_xpi_if),
      .sdram          (u_sdram_if),
      .jtag_tck_i     (s_jtag_tck),
      .jtag_tms_i     (s_jtag_tms),
      .jtag_tdi_i     (s_jtag_tdi),
      .jtag_trst_n_i  (s_jtag_trst_n),
      .jtag_tdo_o     (s_jtag_tdo),
      .wdg_reset_req_o(s_wdg_reset_req),
      .test_done_o    (s_test_done),
      .test_pass_o    (s_test_pass),
      .test_code_o    (s_test_code)
  );

endmodule
