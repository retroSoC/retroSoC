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
    input wire ext_clk_i,
    input wire rst_n_i
);

  wire s_uart_tx;
  wire s_flash_csb;
  wire s_flash_clk;
  wire s_flash_io0;
  wire s_flash_io1;
  wire s_flash_io2;
  wire s_flash_io3;
  wire s_cust_psram_sclk;
  wire s_cust_psram_ce;
  wire s_cust_psram_sio0;
  wire s_cust_psram_sio1;
  wire s_cust_psram_sio2;
  wire s_cust_psram_sio3;
  wire s_cust_spfs_clk_o;
  wire s_cust_spfs_cs_o;
  wire s_cust_spfs_mosi_o;
  wire s_cust_spfs_miso_i;

  retrosoc_asic u_retrosoc_asic (
      .xi_i_pad                 ('0),
      .xo_o_pad                 (),
      .extclk_i_pad             (ext_clk_i),
`ifdef CORE_MDD
      .core_mdd_sel_0_i_pad     ('0),
      .core_mdd_sel_1_i_pad     ('0),
      .core_mdd_sel_2_i_pad     ('0),
      .core_mdd_sel_3_i_pad     ('0),
      .core_mdd_sel_4_i_pad     ('0),
`endif
`ifdef IP_MDD
      .ip_mdd_sel_0_i_pad       ('0),
      .ip_mdd_sel_1_i_pad       ('0),
      .ip_mdd_sel_2_i_pad       ('0),
      .ip_mdd_sel_3_i_pad       ('0),
      .ip_mdd_sel_4_i_pad       ('0),
      .ip_mdd_gpio_0_io_pad     (),
      .ip_mdd_gpio_1_io_pad     (),
      .ip_mdd_gpio_2_io_pad     (),
      .ip_mdd_gpio_3_io_pad     (),
      .ip_mdd_gpio_4_io_pad     (),
      .ip_mdd_gpio_5_io_pad     (),
      .ip_mdd_gpio_6_io_pad     (),
      .ip_mdd_gpio_7_io_pad     (),
      .ip_mdd_gpio_8_io_pad     (),
      .ip_mdd_gpio_9_io_pad     (),
      .ip_mdd_gpio_10_io_pad    (),
      .ip_mdd_gpio_11_io_pad    (),
      .ip_mdd_gpio_12_io_pad    (),
      .ip_mdd_gpio_13_io_pad    (),
      .ip_mdd_gpio_14_io_pad    (),
      .ip_mdd_gpio_15_io_pad    (),
`endif
`ifdef HAVE_PLL
      .pll_cfg_0_i_pad          ('0),
      .pll_cfg_1_i_pad          ('0),
      .pll_cfg_2_i_pad          ('0),
`endif
      .clk_bypass_i_pad         ('1),
      .ext_rst_n_i_pad          (rst_n_i),
      .sys_clkdiv4_o_pad        (),
      .uart_tx_o_pad            (s_uart_tx),
      .uart_rx_i_pad            (),
      .gpio_0_io_pad            (),
      .gpio_1_io_pad            (),
      .gpio_2_io_pad            (),
      .gpio_3_io_pad            (),
      .gpio_4_io_pad            (),
      .gpio_5_io_pad            (),
      .gpio_6_io_pad            (),
      .gpio_7_io_pad            (),
      .gpio_8_io_pad            (),
      .gpio_9_io_pad            (),
      .gpio_10_io_pad           (),
      .gpio_11_io_pad           (),
      .gpio_12_io_pad           (),
      .gpio_13_io_pad           (),
      .gpio_14_io_pad           (),
      .gpio_15_io_pad           (),
      .irq_pin_i_pad            (),
      .cust_uart_tx_o_pad       (),
      .cust_uart_rx_i_pad       (),
      .cust_pwm_pwm_0_o_pad     (),
      .cust_pwm_pwm_1_o_pad     (),
      .cust_pwm_pwm_2_o_pad     (),
      .cust_pwm_pwm_3_o_pad     (),
      .cust_ps2_ps2_clk_i_pad   (),
      .cust_ps2_ps2_dat_i_pad   (),
      .cust_i2c_scl_io_pad      (),
      .cust_i2c_sda_io_pad      (),
      .cust_qspi_spi_clk_o_pad  (),
      .cust_qspi_spi_csn_0_o_pad(),
      .cust_qspi_spi_csn_1_o_pad(),
      .cust_qspi_spi_csn_2_o_pad(),
      .cust_qspi_spi_csn_3_o_pad(),
      .cust_qspi_dat_0_io_pad   (),
      .cust_qspi_dat_1_io_pad   (),
      .cust_qspi_dat_2_io_pad   (),
      .cust_qspi_dat_3_io_pad   (),
      .cust_psram_sclk_o_pad    (s_cust_psram_sclk),
      .cust_psram_ce_o_pad      (s_cust_psram_ce),
      .cust_psram_sio0_io_pad   (s_cust_psram_sio0),
      .cust_psram_sio1_io_pad   (s_cust_psram_sio1),
      .cust_psram_sio2_io_pad   (s_cust_psram_sio2),
      .cust_psram_sio3_io_pad   (s_cust_psram_sio3),
      .cust_spfs_clk_o_pad      (s_cust_spfs_clk_o),
      .cust_spfs_cs_o_pad       (s_cust_spfs_cs_o),
      .cust_spfs_mosi_o_pad     (s_cust_spfs_mosi_o),
      .cust_spfs_miso_i_pad     (s_cust_spfs_miso_i)
  );

  N25Qxxx u_N25Qxxx (
      .C_       (s_cust_spfs_clk_o),
      .S        (s_cust_spfs_cs_o),
      .DQ0      (s_cust_spfs_mosi_o),
      .DQ1      (s_cust_spfs_miso_i),
      .HOLD_DQ3 (),
      .Vpp_W_DQ2(),
      .Vcc      ('d3000)
  );

  rs232 u_rs232_0 (
      .rs232_rx_i(s_uart_tx),
      .rs232_tx_o()
  );

  ESP_PSRAM64H u_ESP_PSRAM64H (
      .sclk(s_cust_psram_sclk),
      .csn (s_cust_psram_ce),
      .sio ({s_cust_psram_sio3, s_cust_psram_sio2, s_cust_psram_sio1, s_cust_psram_sio0})
  );


endmodule
