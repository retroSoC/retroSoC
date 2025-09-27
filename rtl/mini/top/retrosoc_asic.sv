// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// NOTE: need to focus on the port dir

`include "mdd_config.svh"

module retrosoc_asic (
    input  xi_i_pad,
    output xo_o_pad,
    inout  extclk_i_pad,
    inout  audclk_i_pad,
    // IRQ
    inout  extn_irq_i_pad,
`ifdef CORE_MDD
    inout  core_sel_0_i_pad,
    inout  core_sel_1_i_pad,
    inout  core_sel_2_i_pad,
    inout  core_sel_3_i_pad,
    inout  core_sel_4_i_pad,
`endif
`ifdef IP_MDD
    inout  user_gpio_0_io_pad,
    inout  user_gpio_1_io_pad,
    inout  user_gpio_2_io_pad,
    inout  user_gpio_3_io_pad,
    inout  user_gpio_4_io_pad,
    inout  user_gpio_5_io_pad,
    inout  user_gpio_6_io_pad,
    inout  user_gpio_7_io_pad,
    inout  user_gpio_8_io_pad,
    inout  user_gpio_9_io_pad,
    inout  user_gpio_10_io_pad,
    inout  user_gpio_11_io_pad,
    inout  user_gpio_12_io_pad,
    inout  user_gpio_13_io_pad,
    inout  user_gpio_14_io_pad,
    inout  user_gpio_15_io_pad,
`endif
`ifdef HAVE_PLL
    inout  pll_cfg_0_i_pad,
    inout  pll_cfg_1_i_pad,
    inout  pll_cfg_2_i_pad,
`endif
    inout  clk_bypass_i_pad,
    inout  ext_rst_n_i_pad,
    output sys_clkdiv4_o_pad,
    // uart
    output uart0_tx_o_pad,
    inout  uart0_rx_i_pad,
    // gpio
    inout  gpio_0_io_pad,
    inout  gpio_1_io_pad,
    inout  gpio_2_io_pad,
    inout  gpio_3_io_pad,
    inout  gpio_4_io_pad,
    inout  gpio_5_io_pad,
    inout  gpio_6_io_pad,
    inout  gpio_7_io_pad,
    // psram
    output psram_sck_o_pad,
    output psram_nss0_o_pad,
    output psram_nss1_o_pad,
    output psram_nss2_o_pad,
    output psram_nss3_o_pad,
    inout  psram_dat0_io_pad,
    inout  psram_dat1_io_pad,
    inout  psram_dat2_io_pad,
    inout  psram_dat3_io_pad,
    // spisd
    output spisd_sck_o_pad,
    output spisd_nss_o_pad,
    output spisd_mosi_o_pad,
    input  spisd_miso_i_pad,
    // i2s
    output i2s_mclk_o_pad,
    output i2s_sclk_o_pad,
    output i2s_lrck_o_pad,
    output i2s_dacdat_o_pad,
    input  i2s_adcdat_i_pad,
    // onewire
    output onewire_dat_o_pad,
    // apb ip
    output uart1_tx_o_pad,
    inout  uart1_rx_i_pad,
    output pwm_0_o_pad,
    output pwm_1_o_pad,
    output pwm_2_o_pad,
    output pwm_3_o_pad,
    inout  ps2_clk_i_pad,
    inout  ps2_dat_i_pad,
    inout  i2c_scl_io_pad,
    inout  i2c_sda_io_pad,
    output qspi_sck_o_pad,
    output qspi_nss0_o_pad,
    output qspi_nss1_o_pad,
    output qspi_nss2_o_pad,
    output qspi_nss3_o_pad,
    inout  qspi_dat0_io_pad,
    inout  qspi_dat1_io_pad,
    inout  qspi_dat2_io_pad,
    inout  qspi_dat3_io_pad,
    output spfs_sck_o_pad,
    output spfs_nss_o_pad,
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
  logic s_clk_bypass;
  logic s_sys_clk;
  logic s_ext_rst_n;
  logic s_sys_rst_n;
  logic s_aud_rst_n;
  logic s_sys_clkdiv4;
  logic s_extn_irq;
`ifdef CORE_MDD
  logic [`USER_CORESEL_WIDTH-1:0] s_core_sel;
`endif
`ifdef IP_MDD
  user_gpio_if u_user_gpio_if ();
`endif
`ifdef HAVE_SRAM_IF
  ram_if u_ram_if ();
`endif

  simp_gpio_if u_gpio_if ();
  uart_if u_uart0_if ();
  qspi_if u_psram_if ();
  spi_if u_spisd_if ();
  nv_i2s_if u_i2s_if ();
  onewire_if u_onewire_if ();
  uart_if u_uart1_if ();
  pwm_if u_pwm_if ();
  ps2_if u_ps2_if ();
  i2c_if u_i2c_if ();
  qspi_if u_qspi_if ();
  spi_if u_spfs_if ();
  // verilog_format: off
  tc_io_xtl_pad         u_xtal_io_pad           (.xi_pad(xi_i_pad),           .xo_pad(xo_o_pad),                .en(1'b1),                          .clk(s_xtal_io));
  tc_io_tri_pad         u_extclk_i_pad          (.pad(extclk_i_pad),          .c2p(),                           .c2p_en(1'b0),                      .p2c(s_ext_clk));
  tc_io_tri_pad         u_audclk_i_pad          (.pad(audclk_i_pad),          .c2p(),                           .c2p_en(1'b0),                      .p2c(s_aud_clk));
  tc_io_tri_schmitt_pad u_extn_irq_i_pad        (.pad(extn_irq_i_pad),        .c2p(),                           .c2p_en(1'b0),                      .p2c(s_extn_irq));
`ifdef CORE_MDD
  tc_io_tri_pad         u_core_sel_0_i_pad      (.pad(core_sel_0_i_pad),      .c2p(),                           .c2p_en(1'b0),                      .p2c(s_core_sel[0]));
  tc_io_tri_pad         u_core_sel_1_i_pad      (.pad(core_sel_1_i_pad),      .c2p(),                           .c2p_en(1'b0),                      .p2c(s_core_sel[1]));
  tc_io_tri_pad         u_core_sel_2_i_pad      (.pad(core_sel_2_i_pad),      .c2p(),                           .c2p_en(1'b0),                      .p2c(s_core_sel[2]));
  tc_io_tri_pad         u_core_sel_3_i_pad      (.pad(core_sel_3_i_pad),      .c2p(),                           .c2p_en(1'b0),                      .p2c(s_core_sel[3]));
  tc_io_tri_pad         u_core_sel_4_i_pad      (.pad(core_sel_4_i_pad),      .c2p(),                           .c2p_en(1'b0),                      .p2c(s_core_sel[4]));
`endif
`ifdef IP_MDD
  tc_io_tri_pad         u_user_gpio_0_io_pad    (.pad(user_gpio_0_io_pad),    .c2p(u_user_gpio_if.gpio_out[0]),  .c2p_en(~u_user_gpio_if.gpio_oen[0]),  .p2c(u_user_gpio_if.gpio_in[0]));
  tc_io_tri_pad         u_user_gpio_1_io_pad    (.pad(user_gpio_1_io_pad),    .c2p(u_user_gpio_if.gpio_out[1]),  .c2p_en(~u_user_gpio_if.gpio_oen[1]),  .p2c(u_user_gpio_if.gpio_in[1]));
  tc_io_tri_pad         u_user_gpio_2_io_pad    (.pad(user_gpio_2_io_pad),    .c2p(u_user_gpio_if.gpio_out[2]),  .c2p_en(~u_user_gpio_if.gpio_oen[2]),  .p2c(u_user_gpio_if.gpio_in[2]));
  tc_io_tri_pad         u_user_gpio_3_io_pad    (.pad(user_gpio_3_io_pad),    .c2p(u_user_gpio_if.gpio_out[3]),  .c2p_en(~u_user_gpio_if.gpio_oen[3]),  .p2c(u_user_gpio_if.gpio_in[3]));
  tc_io_tri_pad         u_user_gpio_4_io_pad    (.pad(user_gpio_4_io_pad),    .c2p(u_user_gpio_if.gpio_out[4]),  .c2p_en(~u_user_gpio_if.gpio_oen[4]),  .p2c(u_user_gpio_if.gpio_in[4]));
  tc_io_tri_pad         u_user_gpio_5_io_pad    (.pad(user_gpio_5_io_pad),    .c2p(u_user_gpio_if.gpio_out[5]),  .c2p_en(~u_user_gpio_if.gpio_oen[5]),  .p2c(u_user_gpio_if.gpio_in[5]));
  tc_io_tri_pad         u_user_gpio_6_io_pad    (.pad(user_gpio_6_io_pad),    .c2p(u_user_gpio_if.gpio_out[6]),  .c2p_en(~u_user_gpio_if.gpio_oen[6]),  .p2c(u_user_gpio_if.gpio_in[6]));
  tc_io_tri_pad         u_user_gpio_7_io_pad    (.pad(user_gpio_7_io_pad),    .c2p(u_user_gpio_if.gpio_out[7]),  .c2p_en(~u_user_gpio_if.gpio_oen[7]),  .p2c(u_user_gpio_if.gpio_in[7]));
  tc_io_tri_pad         u_user_gpio_8_io_pad    (.pad(user_gpio_8_io_pad),    .c2p(u_user_gpio_if.gpio_out[8]),  .c2p_en(~u_user_gpio_if.gpio_oen[8]),  .p2c(u_user_gpio_if.gpio_in[8]));
  tc_io_tri_pad         u_user_gpio_9_io_pad    (.pad(user_gpio_9_io_pad),    .c2p(u_user_gpio_if.gpio_out[9]),  .c2p_en(~u_user_gpio_if.gpio_oen[9]),  .p2c(u_user_gpio_if.gpio_in[9]));
  tc_io_tri_pad         u_user_gpio_10_io_pad   (.pad(user_gpio_10_io_pad),   .c2p(u_user_gpio_if.gpio_out[10]), .c2p_en(~u_user_gpio_if.gpio_oen[10]), .p2c(u_user_gpio_if.gpio_in[10]));
  tc_io_tri_pad         u_user_gpio_11_io_pad   (.pad(user_gpio_11_io_pad),   .c2p(u_user_gpio_if.gpio_out[11]), .c2p_en(~u_user_gpio_if.gpio_oen[11]), .p2c(u_user_gpio_if.gpio_in[11]));
  tc_io_tri_pad         u_user_gpio_12_io_pad   (.pad(user_gpio_12_io_pad),   .c2p(u_user_gpio_if.gpio_out[12]), .c2p_en(~u_user_gpio_if.gpio_oen[12]), .p2c(u_user_gpio_if.gpio_in[12]));
  tc_io_tri_pad         u_user_gpio_13_io_pad   (.pad(user_gpio_13_io_pad),   .c2p(u_user_gpio_if.gpio_out[13]), .c2p_en(~u_user_gpio_if.gpio_oen[13]), .p2c(u_user_gpio_if.gpio_in[13]));
  tc_io_tri_pad         u_user_gpio_14_io_pad   (.pad(user_gpio_14_io_pad),   .c2p(u_user_gpio_if.gpio_out[14]), .c2p_en(~u_user_gpio_if.gpio_oen[14]), .p2c(u_user_gpio_if.gpio_in[14]));
  tc_io_tri_pad         u_user_gpio_15_io_pad   (.pad(user_gpio_15_io_pad),   .c2p(u_user_gpio_if.gpio_out[15]), .c2p_en(~u_user_gpio_if.gpio_oen[15]), .p2c(u_user_gpio_if.gpio_in[15]));
`endif
`ifdef HAVE_PLL
  tc_io_tri_pad         u_pll_cfg_0_i_pad       (.pad(pll_cfg_0_i_pad),       .c2p(),                           .c2p_en(1'b0),                      .p2c(s_pll_cfg[0]));
  tc_io_tri_pad         u_pll_cfg_1_i_pad       (.pad(pll_cfg_1_i_pad),       .c2p(),                           .c2p_en(1'b0),                      .p2c(s_pll_cfg[1]));
  tc_io_tri_pad         u_pll_cfg_2_i_pad       (.pad(pll_cfg_2_i_pad),       .c2p(),                           .c2p_en(1'b0),                      .p2c(s_pll_cfg[2]));
`endif
  tc_io_tri_pad         u_clk_bypass_i_pad      (.pad(clk_bypass_i_pad),      .c2p(),                           .c2p_en(1'b0),                      .p2c(s_clk_bypass));
  tc_io_tri_schmitt_pad u_ext_rst_n_i_pad       (.pad(ext_rst_n_i_pad),       .c2p(),                           .c2p_en(1'b0),                      .p2c(s_ext_rst_n));
  tc_io_tri_pad         u_sys_clkdiv4_o_pad     (.pad(sys_clkdiv4_o_pad),     .c2p(s_sys_clkdiv4),              .c2p_en(1'b1),                      .p2c());
  // natv
  tc_io_tri_pad         u_uart0_tx_o_pad        (.pad(uart0_tx_o_pad),        .c2p(u_uart0_if.uart_tx_o),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_uart0_rx_i_pad        (.pad(uart0_rx_i_pad),        .c2p(),                           .c2p_en(1'b0),                      .p2c(u_uart0_if.uart_rx_i));
  tc_io_tri_pad         u_gpio_0_io_pad         (.pad(gpio_0_io_pad),         .c2p(u_gpio_if.gpio_out[0]),      .c2p_en(~u_gpio_if.gpio_oen[0]),    .p2c(u_gpio_if.gpio_in[0]));
  tc_io_tri_pad         u_gpio_1_io_pad         (.pad(gpio_1_io_pad),         .c2p(u_gpio_if.gpio_out[1]),      .c2p_en(~u_gpio_if.gpio_oen[1]),    .p2c(u_gpio_if.gpio_in[1]));
  tc_io_tri_pad         u_gpio_2_io_pad         (.pad(gpio_2_io_pad),         .c2p(u_gpio_if.gpio_out[2]),      .c2p_en(~u_gpio_if.gpio_oen[2]),    .p2c(u_gpio_if.gpio_in[2]));
  tc_io_tri_pad         u_gpio_3_io_pad         (.pad(gpio_3_io_pad),         .c2p(u_gpio_if.gpio_out[3]),      .c2p_en(~u_gpio_if.gpio_oen[3]),    .p2c(u_gpio_if.gpio_in[3]));
  tc_io_tri_schmitt_pad u_gpio_4_io_pad         (.pad(gpio_4_io_pad),         .c2p(u_gpio_if.gpio_out[4]),      .c2p_en(~u_gpio_if.gpio_oen[4]),    .p2c(u_gpio_if.gpio_in[4]));
  tc_io_tri_schmitt_pad u_gpio_5_io_pad         (.pad(gpio_5_io_pad),         .c2p(u_gpio_if.gpio_out[5]),      .c2p_en(~u_gpio_if.gpio_oen[5]),    .p2c(u_gpio_if.gpio_in[5]));
  tc_io_tri_schmitt_pad u_gpio_6_io_pad         (.pad(gpio_6_io_pad),         .c2p(u_gpio_if.gpio_out[6]),      .c2p_en(~u_gpio_if.gpio_oen[6]),    .p2c(u_gpio_if.gpio_in[6]));
  tc_io_tri_schmitt_pad u_gpio_7_io_pad         (.pad(gpio_7_io_pad),         .c2p(u_gpio_if.gpio_out[7]),      .c2p_en(~u_gpio_if.gpio_oen[7]),    .p2c(u_gpio_if.gpio_in[7]));
  tc_io_tri_pad         u_psram_sck_o_pad       (.pad(psram_sck_o_pad),       .c2p(u_psram_if.spi_sck_o),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_psram_nss0_o_pad      (.pad(psram_nss0_o_pad),      .c2p(u_psram_if.spi_nss_o[0]),    .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_psram_nss1_o_pad      (.pad(psram_nss1_o_pad),      .c2p(u_psram_if.spi_nss_o[1]),    .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_psram_nss2_o_pad      (.pad(psram_nss2_o_pad),      .c2p(u_psram_if.spi_nss_o[2]),    .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_psram_nss3_o_pad      (.pad(psram_nss3_o_pad),      .c2p(u_psram_if.spi_nss_o[3]),    .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_psram_dat0_io_pad     (.pad(psram_dat0_io_pad),     .c2p(u_psram_if.spi_io_out_o[0]), .c2p_en(u_psram_if.spi_io_en_o[0]), .p2c(u_psram_if.spi_io_in_i[0]));
  tc_io_tri_pad         u_psram_dat1_io_pad     (.pad(psram_dat1_io_pad),     .c2p(u_psram_if.spi_io_out_o[1]), .c2p_en(u_psram_if.spi_io_en_o[1]), .p2c(u_psram_if.spi_io_in_i[1]));
  tc_io_tri_pad         u_psram_dat2_io_pad     (.pad(psram_dat2_io_pad),     .c2p(u_psram_if.spi_io_out_o[2]), .c2p_en(u_psram_if.spi_io_en_o[2]), .p2c(u_psram_if.spi_io_in_i[2]));
  tc_io_tri_pad         u_psram_dat3_io_pad     (.pad(psram_dat3_io_pad),     .c2p(u_psram_if.spi_io_out_o[3]), .c2p_en(u_psram_if.spi_io_en_o[3]), .p2c(u_psram_if.spi_io_in_i[3]));
  tc_io_tri_pad         u_spisd_sck_o_pad       (.pad(spisd_sck_o_pad),       .c2p(u_spisd_if.spi_sck_o),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_spisd_nss_o_pad       (.pad(spisd_nss_o_pad),       .c2p(u_spisd_if.spi_nss_o),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_spisd_mosi_o_pad      (.pad(spisd_mosi_o_pad),      .c2p(u_spisd_if.spi_mosi_o),      .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_spisd_miso_i_pad      (.pad(spisd_miso_i_pad),      .c2p(),                           .c2p_en(1'b0),                      .p2c(u_spisd_if.spi_miso_i));
  tc_io_tri_pad         u_i2s_mclk_o_pad        (.pad(i2s_mclk_o_pad),        .c2p(u_i2s_if.mclk_o),            .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_i2s_sclk_o_pad        (.pad(i2s_sclk_o_pad),        .c2p(u_i2s_if.sclk_o),            .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_i2s_lrck_o_pad        (.pad(i2s_lrck_o_pad),        .c2p(u_i2s_if.lrck_o),            .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_i2s_dacdat_o_pad      (.pad(i2s_dacdat_o_pad),      .c2p(u_i2s_if.dacdat_o),          .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_i2s_adcdat_i_pad      (.pad(i2s_adcdat_i_pad),      .c2p(),                           .c2p_en(1'b0),                      .p2c(u_i2s_if.adcdat_i));
  tc_io_tri_pad         u_onewire_dat_o_pad     (.pad(onewire_dat_o_pad),     .c2p(u_onewire_if.dat_o),         .c2p_en(1'b1),                      .p2c());
  // apb
  tc_io_tri_pad         u_uart1_tx_o_pad       (.pad(uart1_tx_o_pad),         .c2p(u_uart1_if.uart_tx_o),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_uart1_rx_i_pad       (.pad(uart1_rx_i_pad),         .c2p(),                           .c2p_en(1'b0),                      .p2c(u_uart1_if.uart_rx_i));
  tc_io_tri_pad         u_pwm_0_o_pad          (.pad(pwm_0_o_pad),            .c2p(u_pwm_if.pwm_o[0]),          .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_pwm_1_o_pad          (.pad(pwm_1_o_pad),            .c2p(u_pwm_if.pwm_o[1]),          .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_pwm_2_o_pad          (.pad(pwm_2_o_pad),            .c2p(u_pwm_if.pwm_o[2]),          .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_pwm_3_o_pad          (.pad(pwm_3_o_pad),            .c2p(u_pwm_if.pwm_o[3]),          .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_ps2_clk_i_pad        (.pad(ps2_clk_i_pad),          .c2p(),                           .c2p_en(1'b0),                      .p2c(u_ps2_if.ps2_clk_i));
  tc_io_tri_pad         u_ps2_dat_i_pad        (.pad(ps2_dat_i_pad),          .c2p(),                           .c2p_en(1'b0),                      .p2c(u_ps2_if.ps2_dat_i));
  tc_io_tri_pad         u_i2c_scl_io_pad       (.pad(i2c_scl_io_pad),         .c2p(u_i2c_if.scl_o),             .c2p_en(u_i2c_if.scl_dir_o),        .p2c(u_i2c_if.scl_i));
  tc_io_tri_pad         u_i2c_sda_io_pad       (.pad(i2c_sda_io_pad),         .c2p(u_i2c_if.sda_o),             .c2p_en(u_i2c_if.sda_dir_o),        .p2c(u_i2c_if.sda_i));
  tc_io_tri_pad         u_qspi_sck_o_pad       (.pad(qspi_sck_o_pad),         .c2p(u_qspi_if.spi_sck_o),        .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_qspi_nss0_o_pad      (.pad(qspi_nss0_o_pad),        .c2p(u_qspi_if.spi_nss_o[0]),     .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_qspi_nss1_o_pad      (.pad(qspi_nss1_o_pad),        .c2p(u_qspi_if.spi_nss_o[1]),     .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_qspi_nss2_o_pad      (.pad(qspi_nss2_o_pad),        .c2p(u_qspi_if.spi_nss_o[2]),     .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_qspi_nss3_o_pad      (.pad(qspi_nss3_o_pad),        .c2p(u_qspi_if.spi_nss_o[3]),     .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_qspi_dat0_io_pad     (.pad(qspi_dat0_io_pad),       .c2p(u_qspi_if.spi_io_out_o[0]),  .c2p_en(u_qspi_if.spi_io_en_o[0]),  .p2c(u_qspi_if.spi_io_in_i[0]));
  tc_io_tri_pad         u_qspi_dat1_io_pad     (.pad(qspi_dat1_io_pad),       .c2p(u_qspi_if.spi_io_out_o[1]),  .c2p_en(u_qspi_if.spi_io_en_o[1]),  .p2c(u_qspi_if.spi_io_in_i[1]));
  tc_io_tri_pad         u_qspi_dat2_io_pad     (.pad(qspi_dat2_io_pad),       .c2p(u_qspi_if.spi_io_out_o[2]),  .c2p_en(u_qspi_if.spi_io_en_o[2]),  .p2c(u_qspi_if.spi_io_in_i[2]));
  tc_io_tri_pad         u_qspi_dat3_io_pad     (.pad(qspi_dat3_io_pad),       .c2p(u_qspi_if.spi_io_out_o[3]),  .c2p_en(u_qspi_if.spi_io_en_o[3]),  .p2c(u_qspi_if.spi_io_in_i[3]));
  tc_io_tri_pad         u_spfs_sck_o_pad       (.pad(spfs_sck_o_pad),         .c2p(u_spfs_if.spi_sck_o),        .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_spfs_nss_o_pad       (.pad(spfs_nss_o_pad),         .c2p(u_spfs_if.spi_nss_o),        .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_spfs_mosi_o_pad      (.pad(spfs_mosi_o_pad),        .c2p(u_spfs_if.spi_mosi_o),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_spfs_miso_i_pad      (.pad(spfs_miso_i_pad),        .c2p(),                           .c2p_en(1'b0),                      .p2c(u_spfs_if.spi_miso_i));

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
      .clk_i      (s_sys_clk),
      .rst_n_i    (s_sys_rst_n),
      .clk_aud_i  (s_aud_clk),
      .rst_aud_n_i(s_aud_rst_n),
`ifdef HAVE_PLL
      .spfs_div4_i(s_pll_cfg[2]),
`else
      .spfs_div4_i('0),
`endif
      .extn_irq_i (s_extn_irq),
`ifdef CORE_MDD
      .core_sel_i (s_core_sel),
`endif
`ifdef IP_MDD
      .gpio       (u_user_gpio_if),
`endif
`ifdef HAVE_SRAM_IF
      .ram        (u_ram_if),
`endif
      .gpio       (u_gpio_if),
      .uart0      (u_uart0_if),
      .psram      (u_psram_if),
      .spisd      (u_spisd_if),
      .i2s        (u_i2s_if),
      .onewire    (u_onewire_if),
      .uart1      (u_uart1_if),
      .pwm        (u_pwm_if),
      .ps2        (u_ps2_if),
      .i2c        (u_i2c_if),
      .qspi       (u_qspi_if),
      .spfs       (u_spfs_if)
  );

`ifdef HAVE_SRAM_IF
  onchip_ram u_onchip_ram (
      .clk_i(s_sys_clk),
      .ram  (u_ram_if)
  );
`endif

endmodule
