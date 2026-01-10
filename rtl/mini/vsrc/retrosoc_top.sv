/*
 *  PicoSoC - A simple example SoC using PicoRV32
 *
 *  Copyright (C) 2017  Claire Xenia Wolf <claire@yosyshq.com>
 *  Copyright (C) 2025  Yuchi Miao <miaoyuchi@ict.ac.cn>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

`timescale 1 ns / 1 ps

module retrosoc_top (
    input wire       ext_clk_i,
    input wire       rst_n_i,
    input wire [4:0] core_sel_i
);

  wire       s_clk;
  wire       s_rst_n;
  wire [4:0] s_core_sel;
  wire       s_clk_bypass;
  wire       s_psram_sck;
  wire       s_psram_nss0;
  wire       s_psram_dat0;
  wire       s_psram_dat1;
  wire       s_psram_dat2;
  wire       s_psram_dat3;
  wire       s_spfs_sck;
  wire       s_spfs_nss;
  wire       s_spfs_mosi;
  wire       s_spfs_miso;

  assign s_clk        = ext_clk_i;
  assign s_rst_n      = rst_n_i;
  assign s_core_sel   = core_sel_i;
  assign s_clk_bypass = 1'b1;
  retrosoc_asic u_retrosoc_asic (
      .extclk_i_pad       (s_clk),
      .audclk_i_pad       (),
      .ext_rst_n_i_pad    (s_rst_n),
      .sys_clkdiv4_o_pad  (),
`ifdef HAVE_PLL
      .xi_i_pad           (),
      .xo_o_pad           (),
      .clk_bypass_i_pad   (s_clk_bypass),
      .pll_cfg_0_i_pad    (),
      .pll_cfg_1_i_pad    (),
      .pll_cfg_2_i_pad    (),
`endif
`ifdef CORE_MDD
      .core_sel_0_i_pad   (s_core_sel[0]),
      .core_sel_1_i_pad   (s_core_sel[1]),
      .core_sel_2_i_pad   (s_core_sel[2]),
      .core_sel_3_i_pad   (s_core_sel[3]),
      .core_sel_4_i_pad   (s_core_sel[4]),
`endif
`ifdef IP_MDD
      .user_gpio_0_io_pad (),
      .user_gpio_1_io_pad (),
      .user_gpio_2_io_pad (),
      .user_gpio_3_io_pad (),
      .user_gpio_4_io_pad (),
      .user_gpio_5_io_pad (),
      .user_gpio_6_io_pad (),
      .user_gpio_7_io_pad (),
      .user_gpio_8_io_pad (),
      .user_gpio_9_io_pad (),
      .user_gpio_10_io_pad(),
      .user_gpio_11_io_pad(),
      .user_gpio_12_io_pad(),
      .user_gpio_13_io_pad(),
      .user_gpio_14_io_pad(),
      .user_gpio_15_io_pad(),
`endif
      .tmr_capch_i_pad    (),
      .extn_irq_i_pad     (),
      .uart0_tx_o_pad     (),
      .uart0_rx_i_pad     (),
      .gpio_0_io_pad      (),
      .gpio_1_io_pad      (),
      .gpio_2_io_pad      (),
      .gpio_3_io_pad      (),
      .gpio_4_io_pad      (),
      .gpio_5_io_pad      (),
      .gpio_6_io_pad      (),
      .gpio_7_io_pad      (),
      .psram_sck_o_pad    (s_psram_sck),
      .psram_nss0_o_pad   (s_psram_nss0),
      .psram_nss1_o_pad   (),
      .psram_nss2_o_pad   (),
      .psram_nss3_o_pad   (),
      .psram_dat0_io_pad  (s_psram_dat0),
      .psram_dat1_io_pad  (s_psram_dat1),
      .psram_dat2_io_pad  (s_psram_dat2),
      .psram_dat3_io_pad  (s_psram_dat3),
      .spisd_sck_o_pad    (),
      .spisd_nss_o_pad    (),
      .spisd_mosi_o_pad   (),
      .spisd_miso_i_pad   (),
      .i2s_mclk_o_pad     (),
      .i2s_sclk_o_pad     (),
      .i2s_lrck_o_pad     (),
      .i2s_dacdat_o_pad   (),
      .i2s_adcdat_i_pad   (),
      .onewire_dat_o_pad  (),
      .uart1_tx_o_pad     (),
      .uart1_rx_i_pad     (),
      .pwm_0_o_pad        (),
      .pwm_1_o_pad        (),
      .pwm_2_o_pad        (),
      .pwm_3_o_pad        (),
      .ps2_clk_i_pad      (),
      .ps2_dat_i_pad      (),
      .i2c_scl_io_pad     (),
      .i2c_sda_io_pad     (),
      .qspi_sck_o_pad     (),
      .qspi_nss0_o_pad    (),
      .qspi_nss1_o_pad    (),
      .qspi_nss2_o_pad    (),
      .qspi_nss3_o_pad    (),
      .qspi_dat0_io_pad   (),
      .qspi_dat1_io_pad   (),
      .qspi_dat2_io_pad   (),
      .qspi_dat3_io_pad   (),
      .spfs_sck_o_pad     (s_spfs_sck),
      .spfs_nss_o_pad     (s_spfs_nss),
      .spfs_mosi_o_pad    (s_spfs_mosi),
      .spfs_miso_i_pad    (s_spfs_miso)
  );

  spiFlash u_spiFlash (
      .clk (s_spfs_sck),
      .cs  (s_spfs_nss),
      .mosi(s_spfs_mosi),
      .miso(s_spfs_miso)
  );

  ESP_PSRAM64H u_ESP_PSRAM64H (
      .sclk(s_psram_sck),
      .csn (s_psram_nss0),
      .sio ({s_psram_dat3, s_psram_dat2, s_psram_dat1, s_psram_dat0})
  );


endmodule
