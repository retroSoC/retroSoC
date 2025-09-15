/*
 *  retrosoc_asic - A full example SoC using PicoRV32 in ASIC
 *
 *  Copyright (C) 2017  Clifford Wolf <clifford@clifford.at>
 *  Copyright (C) 2018,2019  Tim Edwards <tim@efabless.com>
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

// NOTE: need to focus on the port dir
module retrosoc_asic (
    input  xi_i_pad,
    output xo_o_pad,
    inout  extclk_i_pad,
    inout  audclk_i_pad,
    // IRQ
    inout  irq_pin_i_pad,
`ifdef CORE_MDD
    inout  core_mdd_sel_0_i_pad,
    inout  core_mdd_sel_1_i_pad,
    inout  core_mdd_sel_2_i_pad,
    inout  core_mdd_sel_3_i_pad,
    inout  core_mdd_sel_4_i_pad,
`endif
`ifdef IP_MDD
    inout  ip_mdd_gpio_0_io_pad,
    inout  ip_mdd_gpio_1_io_pad,
    inout  ip_mdd_gpio_2_io_pad,
    inout  ip_mdd_gpio_3_io_pad,
    inout  ip_mdd_gpio_4_io_pad,
    inout  ip_mdd_gpio_5_io_pad,
    inout  ip_mdd_gpio_6_io_pad,
    inout  ip_mdd_gpio_7_io_pad,
    inout  ip_mdd_gpio_8_io_pad,
    inout  ip_mdd_gpio_9_io_pad,
    inout  ip_mdd_gpio_10_io_pad,
    inout  ip_mdd_gpio_11_io_pad,
    inout  ip_mdd_gpio_12_io_pad,
    inout  ip_mdd_gpio_13_io_pad,
    inout  ip_mdd_gpio_14_io_pad,
    inout  ip_mdd_gpio_15_io_pad,
`endif
`ifdef HAVE_PLL
    inout  pll_cfg_0_i_pad,
    inout  pll_cfg_1_i_pad,
    inout  pll_cfg_2_i_pad,
`endif
    inout  clk_bypass_i_pad,
    inout  ext_rst_n_i_pad,
    output sys_clkdiv4_o_pad,
    // UART
    output uart_tx_o_pad,
    inout  uart_rx_i_pad,
    // GPIO
    inout  gpio_0_io_pad,
    inout  gpio_1_io_pad,
    inout  gpio_2_io_pad,
    inout  gpio_3_io_pad,
    inout  gpio_4_io_pad,
    inout  gpio_5_io_pad,
    inout  gpio_6_io_pad,
    inout  gpio_7_io_pad,
    // PSRAM
    output psram_sclk_o_pad,
    output psram_ce0_o_pad,
    output psram_ce1_o_pad,
    output psram_ce2_o_pad,
    output psram_ce3_o_pad,
    inout  psram_sio0_io_pad,
    inout  psram_sio1_io_pad,
    inout  psram_sio2_io_pad,
    inout  psram_sio3_io_pad,
    // SPISD
    output spisd_sclk_o_pad,
    output spisd_cs_o_pad,
    output spisd_mosi_o_pad,
    input  spisd_miso_i_pad,
    // apb
    output uart1_tx_o_pad,
    inout  uart1_rx_i_pad,
    output pwm_pwm_0_o_pad,
    output pwm_pwm_1_o_pad,
    output pwm_pwm_2_o_pad,
    output pwm_pwm_3_o_pad,
    inout  ps2_ps2_clk_i_pad,
    inout  ps2_ps2_dat_i_pad,
    inout  i2c_scl_io_pad,
    inout  i2c_sda_io_pad,
    output qspi_spi_clk_o_pad,
    output qspi_spi_csn_0_o_pad,
    output qspi_spi_csn_1_o_pad,
    output qspi_spi_csn_2_o_pad,
    output qspi_spi_csn_3_o_pad,
    inout  qspi_dat_0_io_pad,
    inout  qspi_dat_1_io_pad,
    inout  qspi_dat_2_io_pad,
    inout  qspi_dat_3_io_pad,
    output spfs_clk_o_pad,
    output spfs_cs_o_pad,
    output spfs_mosi_o_pad,
    inout  spfs_miso_i_pad
);
  // clk&rst
  logic s_xtal_io;
  logic s_ext_clk;
  logic s_aud_clk;
`ifdef HAVE_PLL
  logic [2:0] s_pll_cfg;
`endif
  logic       s_clk_bypass;
  logic       s_sys_clk;
  logic       s_ext_rst_n;
  logic       s_sys_rst_n;
  logic       s_aud_rst_n;
  logic       s_sys_clkdiv4;
  logic       s_irq_pin;
  // io
  logic       s_uart_tx;
  logic       s_uart_rx;
  logic [7:0] s_gpio_out;
  logic [7:0] s_gpio_in;
  logic [7:0] s_gpio_oen;
  logic [7:0] s_gpio_pun;
  logic [7:0] s_gpio_pdn;

`ifdef CORE_MDD
  logic [4:0] s_core_mdd_sel;
`endif
`ifdef IP_MDD
  logic [15:0] s_ip_mdd_gpio_out;
  logic [15:0] s_ip_mdd_gpio_in;
  logic [15:0] s_ip_mdd_gpio_oen;
`endif
`ifdef HAVE_SRAM_IF
  // ram
  logic [14:0] s_ram_addr;
  logic [31:0] s_ram_wdata;
  logic [ 3:0] s_ram_wstrb;
  logic [31:0] s_ram_rdata;
`endif

  qspi_if u_psram_if ();
  spi_if u_spisd_if ();
  uart_if u_uart1_if ();
  pwm_if u_pwm_if ();
  ps2_if u_ps2_if ();
  i2c_if u_i2c_if ();
  qspi_if u_qspi_if ();
  spi_if u_spfs_if ();
  // verilog_format: off
  tc_io_xtl_pad         u_xtal_io_pad          (.xi_pad(xi_i_pad),               .xo_pad(xo_o_pad),            .en(1'b1),                       .clk(s_xtal_io));
  tc_io_tri_pad         u_extclk_i_pad         (.pad(extclk_i_pad),              .c2p(),                       .c2p_en(1'b0),                   .p2c(s_ext_clk));
  tc_io_tri_pad         u_audclk_i_pad         (.pad(audclk_i_pad),              .c2p(),                       .c2p_en(1'b0),                   .p2c(s_aud_clk));
  tc_io_tri_schmitt_pad u_irq_pin_i_pad        (.pad(irq_pin_i_pad),             .c2p(),                       .c2p_en(1'b0),                   .p2c(s_irq_pin));
`ifdef CORE_MDD
  tc_io_tri_pad         u_core_mdd_sel_0_i_pad (.pad(core_mdd_sel_0_i_pad),      .c2p(),                       .c2p_en(1'b0),                   .p2c(s_core_mdd_sel[0]));
  tc_io_tri_pad         u_core_mdd_sel_1_i_pad (.pad(core_mdd_sel_1_i_pad),      .c2p(),                       .c2p_en(1'b0),                   .p2c(s_core_mdd_sel[1]));
  tc_io_tri_pad         u_core_mdd_sel_2_i_pad (.pad(core_mdd_sel_2_i_pad),      .c2p(),                       .c2p_en(1'b0),                   .p2c(s_core_mdd_sel[2]));
  tc_io_tri_pad         u_core_mdd_sel_3_i_pad (.pad(core_mdd_sel_3_i_pad),      .c2p(),                       .c2p_en(1'b0),                   .p2c(s_core_mdd_sel[3]));
  tc_io_tri_pad         u_core_mdd_sel_4_i_pad (.pad(core_mdd_sel_4_i_pad),      .c2p(),                       .c2p_en(1'b0),                   .p2c(s_core_mdd_sel[4]));
`endif
`ifdef IP_MDD
  tc_io_tri_pad         u_ip_mdd_gpio_0_io_pad (.pad(ip_mdd_gpio_0_io_pad),      .c2p(s_ip_mdd_gpio_out[0]),   .c2p_en(s_ip_mdd_gpio_oen[0]),   .p2c(s_ip_mdd_gpio_in[0]));
  tc_io_tri_pad         u_ip_mdd_gpio_1_io_pad (.pad(ip_mdd_gpio_1_io_pad),      .c2p(s_ip_mdd_gpio_out[1]),   .c2p_en(s_ip_mdd_gpio_oen[1]),   .p2c(s_ip_mdd_gpio_in[1]));
  tc_io_tri_pad         u_ip_mdd_gpio_2_io_pad (.pad(ip_mdd_gpio_2_io_pad),      .c2p(s_ip_mdd_gpio_out[2]),   .c2p_en(s_ip_mdd_gpio_oen[2]),   .p2c(s_ip_mdd_gpio_in[2]));
  tc_io_tri_pad         u_ip_mdd_gpio_3_io_pad (.pad(ip_mdd_gpio_3_io_pad),      .c2p(s_ip_mdd_gpio_out[3]),   .c2p_en(s_ip_mdd_gpio_oen[3]),   .p2c(s_ip_mdd_gpio_in[3]));
  tc_io_tri_pad         u_ip_mdd_gpio_4_io_pad (.pad(ip_mdd_gpio_4_io_pad),      .c2p(s_ip_mdd_gpio_out[4]),   .c2p_en(s_ip_mdd_gpio_oen[4]),   .p2c(s_ip_mdd_gpio_in[4]));
  tc_io_tri_pad         u_ip_mdd_gpio_5_io_pad (.pad(ip_mdd_gpio_5_io_pad),      .c2p(s_ip_mdd_gpio_out[5]),   .c2p_en(s_ip_mdd_gpio_oen[5]),   .p2c(s_ip_mdd_gpio_in[5]));
  tc_io_tri_pad         u_ip_mdd_gpio_6_io_pad (.pad(ip_mdd_gpio_6_io_pad),      .c2p(s_ip_mdd_gpio_out[6]),   .c2p_en(s_ip_mdd_gpio_oen[6]),   .p2c(s_ip_mdd_gpio_in[6]));
  tc_io_tri_pad         u_ip_mdd_gpio_7_io_pad (.pad(ip_mdd_gpio_7_io_pad),      .c2p(s_ip_mdd_gpio_out[7]),   .c2p_en(s_ip_mdd_gpio_oen[7]),   .p2c(s_ip_mdd_gpio_in[7]));
  tc_io_tri_pad         u_ip_mdd_gpio_8_io_pad (.pad(ip_mdd_gpio_8_io_pad),      .c2p(s_ip_mdd_gpio_out[8]),   .c2p_en(s_ip_mdd_gpio_oen[8]),   .p2c(s_ip_mdd_gpio_in[8]));
  tc_io_tri_pad         u_ip_mdd_gpio_9_io_pad (.pad(ip_mdd_gpio_9_io_pad),      .c2p(s_ip_mdd_gpio_out[9]),   .c2p_en(s_ip_mdd_gpio_oen[9]),   .p2c(s_ip_mdd_gpio_in[9]));
  tc_io_tri_pad         u_ip_mdd_gpio_10_io_pad(.pad(ip_mdd_gpio_10_io_pad),     .c2p(s_ip_mdd_gpio_out[10]),  .c2p_en(s_ip_mdd_gpio_oen[10]),  .p2c(s_ip_mdd_gpio_in[10]));
  tc_io_tri_pad         u_ip_mdd_gpio_11_io_pad(.pad(ip_mdd_gpio_11_io_pad),     .c2p(s_ip_mdd_gpio_out[11]),  .c2p_en(s_ip_mdd_gpio_oen[11]),  .p2c(s_ip_mdd_gpio_in[11]));
  tc_io_tri_pad         u_ip_mdd_gpio_12_io_pad(.pad(ip_mdd_gpio_12_io_pad),     .c2p(s_ip_mdd_gpio_out[12]),  .c2p_en(s_ip_mdd_gpio_oen[12]),  .p2c(s_ip_mdd_gpio_in[12]));
  tc_io_tri_pad         u_ip_mdd_gpio_13_io_pad(.pad(ip_mdd_gpio_13_io_pad),     .c2p(s_ip_mdd_gpio_out[13]),  .c2p_en(s_ip_mdd_gpio_oen[13]),  .p2c(s_ip_mdd_gpio_in[13]));
  tc_io_tri_pad         u_ip_mdd_gpio_14_io_pad(.pad(ip_mdd_gpio_14_io_pad),     .c2p(s_ip_mdd_gpio_out[14]),  .c2p_en(s_ip_mdd_gpio_oen[14]),  .p2c(s_ip_mdd_gpio_in[14]));
  tc_io_tri_pad         u_ip_mdd_gpio_15_io_pad(.pad(ip_mdd_gpio_15_io_pad),     .c2p(s_ip_mdd_gpio_out[15]),  .c2p_en(s_ip_mdd_gpio_oen[15]),  .p2c(s_ip_mdd_gpio_in[15]));
`endif
`ifdef HAVE_PLL
  tc_io_tri_pad         u_pll_cfg_0_i_pad      (.pad(pll_cfg_0_i_pad),           .c2p(),                           .c2p_en(1'b0),                   .p2c(s_pll_cfg[0]));
  tc_io_tri_pad         u_pll_cfg_1_i_pad      (.pad(pll_cfg_1_i_pad),           .c2p(),                           .c2p_en(1'b0),                   .p2c(s_pll_cfg[1]));
  tc_io_tri_pad         u_pll_cfg_2_i_pad      (.pad(pll_cfg_2_i_pad),           .c2p(),                           .c2p_en(1'b0),                   .p2c(s_pll_cfg[2]));
`endif
  tc_io_tri_pad         u_clk_bypass_i_pad     (.pad(clk_bypass_i_pad),          .c2p(),                           .c2p_en(1'b0),                      .p2c(s_clk_bypass));
  tc_io_tri_schmitt_pad u_ext_rst_n_i_pad      (.pad(ext_rst_n_i_pad),           .c2p(),                           .c2p_en(1'b0),                      .p2c(s_ext_rst_n));
  tc_io_tri_pad         u_sys_clkdiv4_o_pad    (.pad(sys_clkdiv4_o_pad),         .c2p(s_sys_clkdiv4),              .c2p_en(1'b1),                      .p2c());
  // natv
  tc_io_tri_pad         u_uart_tx_o_pad        (.pad(uart_tx_o_pad),             .c2p(s_uart_tx),                  .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_uart_rx_i_pad        (.pad(uart_rx_i_pad),             .c2p(),                           .c2p_en(1'b0),                      .p2c(s_uart_rx));
  tc_io_tri_pad         u_gpio_0_io_pad        (.pad(gpio_0_io_pad),             .c2p(s_gpio_out[0]),              .c2p_en(~s_gpio_oen[0]),            .p2c(s_gpio_in[0]));
  tc_io_tri_pad         u_gpio_1_io_pad        (.pad(gpio_1_io_pad),             .c2p(s_gpio_out[1]),              .c2p_en(~s_gpio_oen[1]),            .p2c(s_gpio_in[1]));
  tc_io_tri_pad         u_gpio_2_io_pad        (.pad(gpio_2_io_pad),             .c2p(s_gpio_out[2]),              .c2p_en(~s_gpio_oen[2]),            .p2c(s_gpio_in[2]));
  tc_io_tri_pad         u_gpio_3_io_pad        (.pad(gpio_3_io_pad),             .c2p(s_gpio_out[3]),              .c2p_en(~s_gpio_oen[3]),            .p2c(s_gpio_in[3]));
  tc_io_tri_schmitt_pad u_gpio_4_io_pad        (.pad(gpio_4_io_pad),             .c2p(s_gpio_out[4]),              .c2p_en(~s_gpio_oen[4]),            .p2c(s_gpio_in[4]));
  tc_io_tri_schmitt_pad u_gpio_5_io_pad        (.pad(gpio_5_io_pad),             .c2p(s_gpio_out[5]),              .c2p_en(~s_gpio_oen[5]),            .p2c(s_gpio_in[5]));
  tc_io_tri_schmitt_pad u_gpio_6_io_pad        (.pad(gpio_6_io_pad),             .c2p(s_gpio_out[6]),              .c2p_en(~s_gpio_oen[6]),            .p2c(s_gpio_in[6]));
  tc_io_tri_schmitt_pad u_gpio_7_io_pad        (.pad(gpio_7_io_pad),             .c2p(s_gpio_out[7]),              .c2p_en(~s_gpio_oen[7]),            .p2c(s_gpio_in[7]));
  tc_io_tri_pad         u_psram_sclk_o_pad     (.pad(psram_sclk_o_pad),          .c2p(u_psram_if.spi_sck_o),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_psram_ce0_o_pad      (.pad(psram_ce0_o_pad),           .c2p(u_psram_if.spi_nss_o[0]),    .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_psram_ce1_o_pad      (.pad(psram_ce1_o_pad),           .c2p(u_psram_if.spi_nss_o[1]),    .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_psram_ce2_o_pad      (.pad(psram_ce2_o_pad),           .c2p(u_psram_if.spi_nss_o[2]),    .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_psram_ce3_o_pad      (.pad(psram_ce3_o_pad),           .c2p(u_psram_if.spi_nss_o[3]),    .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_psram_sio0_io_pad    (.pad(psram_sio0_io_pad),         .c2p(u_psram_if.spi_io_out_o[0]), .c2p_en(u_psram_if.spi_io_en_o[0]), .p2c(u_psram_if.spi_io_in_i[0]));
  tc_io_tri_pad         u_psram_sio1_io_pad    (.pad(psram_sio1_io_pad),         .c2p(u_psram_if.spi_io_out_o[1]), .c2p_en(u_psram_if.spi_io_en_o[1]), .p2c(u_psram_if.spi_io_in_i[1]));
  tc_io_tri_pad         u_psram_sio2_io_pad    (.pad(psram_sio2_io_pad),         .c2p(u_psram_if.spi_io_out_o[2]), .c2p_en(u_psram_if.spi_io_en_o[2]), .p2c(u_psram_if.spi_io_in_i[2]));
  tc_io_tri_pad         u_psram_sio3_io_pad    (.pad(psram_sio3_io_pad),         .c2p(u_psram_if.spi_io_out_o[3]), .c2p_en(u_psram_if.spi_io_en_o[3]), .p2c(u_psram_if.spi_io_in_i[3]));
  tc_io_tri_pad         u_spisd_sclk_o_pad     (.pad(spisd_sclk_o_pad),          .c2p(u_spisd_if.spi_sck_o),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_spisd_cs_o_pad       (.pad(spisd_cs_o_pad),            .c2p(u_spisd_if.spi_nss_o),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_spisd_mosi_o_pad     (.pad(spisd_mosi_o_pad),          .c2p(u_spisd_if.spi_mosi_o),      .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_spisd_miso_i_pad     (.pad(spisd_miso_i_pad),          .c2p(),                           .c2p_en(1'b0),                      .p2c(u_spisd_if.spi_miso_i));
  // apb
  tc_io_tri_pad         u_uart1_tx_o_pad       (.pad(uart1_tx_o_pad),            .c2p(u_uart1_if.uart_tx_o),      .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad         u_uart1_rx_i_pad       (.pad(uart1_rx_i_pad),            .c2p(),                          .c2p_en(1'b0),                     .p2c(u_uart1_if.uart_rx_i));
  tc_io_tri_pad         u_pwm_pwm_0_o_pad      (.pad(pwm_pwm_0_o_pad),           .c2p(u_pwm_if.pwm_o[0]),         .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad         u_pwm_pwm_1_o_pad      (.pad(pwm_pwm_1_o_pad),           .c2p(u_pwm_if.pwm_o[1]),         .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad         u_pwm_pwm_2_o_pad      (.pad(pwm_pwm_2_o_pad),           .c2p(u_pwm_if.pwm_o[2]),         .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad         u_pwm_pwm_3_o_pad      (.pad(pwm_pwm_3_o_pad),           .c2p(u_pwm_if.pwm_o[3]),         .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad         u_ps2_ps2_clk_i_pad    (.pad(ps2_ps2_clk_i_pad),         .c2p(),                          .c2p_en(1'b0),                     .p2c(u_ps2_if.ps2_clk_i));
  tc_io_tri_pad         u_ps2_ps2_dat_i_pad    (.pad(ps2_ps2_dat_i_pad),         .c2p(),                          .c2p_en(1'b0),                     .p2c(u_ps2_if.ps2_dat_i));
  tc_io_tri_pad         u_i2c_scl_io_pad       (.pad(i2c_scl_io_pad),            .c2p(u_i2c_if.scl_o),            .c2p_en(u_i2c_if.scl_dir_o),       .p2c(u_i2c_if.scl_i));
  tc_io_tri_pad         u_i2c_sda_io_pad       (.pad(i2c_sda_io_pad),            .c2p(u_i2c_if.sda_o),            .c2p_en(u_i2c_if.sda_dir_o),       .p2c(u_i2c_if.sda_i));
  tc_io_tri_pad         u_qspi_spi_clk_o_pad   (.pad(qspi_spi_clk_o_pad),        .c2p(u_qspi_if.spi_sck_o),       .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad         u_qspi_spi_csn_0_o_pad (.pad(qspi_spi_csn_0_o_pad),      .c2p(u_qspi_if.spi_nss_o[0]),    .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad         u_qspi_spi_csn_1_o_pad (.pad(qspi_spi_csn_1_o_pad),      .c2p(u_qspi_if.spi_nss_o[1]),    .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad         u_qspi_spi_csn_2_o_pad (.pad(qspi_spi_csn_2_o_pad),      .c2p(u_qspi_if.spi_nss_o[2]),    .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad         u_qspi_spi_csn_3_o_pad (.pad(qspi_spi_csn_3_o_pad),      .c2p(u_qspi_if.spi_nss_o[3]),    .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad         u_qspi_dat_0_io_pad    (.pad(qspi_dat_0_io_pad),         .c2p(u_qspi_if.spi_io_out_o[0]), .c2p_en(u_qspi_if.spi_io_en_o[0]), .p2c(u_qspi_if.spi_io_in_i[0]));
  tc_io_tri_pad         u_qspi_dat_1_io_pad    (.pad(qspi_dat_1_io_pad),         .c2p(u_qspi_if.spi_io_out_o[1]), .c2p_en(u_qspi_if.spi_io_en_o[1]), .p2c(u_qspi_if.spi_io_in_i[1]));
  tc_io_tri_pad         u_qspi_dat_2_io_pad    (.pad(qspi_dat_2_io_pad),         .c2p(u_qspi_if.spi_io_out_o[2]), .c2p_en(u_qspi_if.spi_io_en_o[2]), .p2c(u_qspi_if.spi_io_in_i[2]));
  tc_io_tri_pad         u_qspi_dat_3_io_pad    (.pad(qspi_dat_3_io_pad),         .c2p(u_qspi_if.spi_io_out_o[3]), .c2p_en(u_qspi_if.spi_io_en_o[3]), .p2c(u_qspi_if.spi_io_in_i[3]));
  tc_io_tri_pad         u_spfs_clk_o_pad       (.pad(spfs_clk_o_pad),            .c2p(u_spfs_if.spi_sck_o),       .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad         u_spfs_cs_o_pad        (.pad(spfs_cs_o_pad),             .c2p(u_spfs_if.spi_nss_o),       .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad         u_spfs_mosi_o_pad      (.pad(spfs_mosi_o_pad),           .c2p(u_spfs_if.spi_mosi_o),      .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad         u_spfs_miso_i_pad      (.pad(spfs_miso_i_pad),           .c2p(),                          .c2p_en(1'b0),                     .p2c(u_spfs_if.spi_miso_i));

  // verilog_format: on
  // clk buffer & mux
  rcu u_rcu (
      .xtal_clk_i   (s_xtal_io),
      .ext_clk_i    (s_ext_clk),
      .aud_clk_i    (s_aud_clk),
      .clk_bypass_i (s_clk_bypass),
      .ext_rst_n_i  (s_ext_rst_n),
`ifdef HAVE_PLL
      .pll_cfg_i    (s_pll_cfg),
`endif
      .sys_clk_o    (s_sys_clk),
      .sys_rst_n_o  (s_sys_rst_n),
      .aud_rst_n_o  (s_aud_rst_n),
      .sys_clkdiv4_o(s_sys_clkdiv4)
  );

  retrosoc u_retrosoc (
      .clk_i            (s_sys_clk),
      .rst_n_i          (s_sys_rst_n),
      .clk_aud_i        (s_aud_clk),
      .rst_aud_n_i      (s_aud_rst_n),
`ifdef HAVE_PLL
      .spfs_div4_i      (s_pll_cfg[2]),
`else
      .spfs_div4_i      ('0),
`endif
      .irq_pin_i        (s_irq_pin),
`ifdef CORE_MDD
      .core_mdd_sel_i   (s_core_mdd_sel),
`endif
`ifdef IP_MDD
      .ip_mdd_gpio_out_o(s_ip_mdd_gpio_out),
      .ip_mdd_gpio_in_i (s_ip_mdd_gpio_in),
      .ip_mdd_gpio_oen_o(s_ip_mdd_gpio_oen),
`endif
`ifdef HAVE_SRAM_IF
      .ram_addr_o       (s_ram_addr),
      .ram_wdata_o      (s_ram_wdata),
      .ram_wstrb_o      (s_ram_wstrb),
      .ram_rdata_i      (s_ram_rdata),
`endif
      .gpio_out_o       (s_gpio_out),
      .gpio_in_i        (s_gpio_in),
      .gpio_pun_o       (s_gpio_pun),
      .gpio_pdn_o       (s_gpio_pdn),
      .gpio_oen_o       (s_gpio_oen),
      .uart_tx_o        (s_uart_tx),
      .uart_rx_i        (s_uart_rx),
      .psram            (u_psram_if),
      .spisd            (u_spisd_if),
      .uart             (u_uart1_if),
      .pwm              (u_pwm_if),
      .ps2              (u_ps2_if),
      .i2c              (u_i2c_if),
      .qspi             (u_qspi_if),
      .spfs             (u_spfs_if)
  );

`ifdef HAVE_SRAM_IF
  onchip_ram u_onchip_ram (
      .clk_i  (s_sys_clk),
      .addr_i (s_ram_addr),
      .wdata_i(s_ram_wdata),
      .wstrb_i(s_ram_wstrb),
      .rdata_o(s_ram_rdata)
  );
`endif

endmodule
