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
    inout  psram_sio0_io_pad,
    inout  psram_sio1_io_pad,
    inout  psram_sio2_io_pad,
    inout  psram_sio3_io_pad,
    // SPISD
    output spisd_sclk_o_pad,
    output spisd_cs_o_pad,
    output spisd_mosi_o_pad,
    input  spisd_miso_i_pad,
    // IRQ
    inout  irq_pin_i_pad,
    // CUST
    output cust_uart_tx_o_pad,
    inout  cust_uart_rx_i_pad,
    output cust_pwm_pwm_0_o_pad,
    output cust_pwm_pwm_1_o_pad,
    output cust_pwm_pwm_2_o_pad,
    output cust_pwm_pwm_3_o_pad,
    inout  cust_ps2_ps2_clk_i_pad,
    inout  cust_ps2_ps2_dat_i_pad,
    inout  cust_i2c_scl_io_pad,
    inout  cust_i2c_sda_io_pad,
    output cust_qspi_spi_clk_o_pad,
    output cust_qspi_spi_csn_0_o_pad,
    output cust_qspi_spi_csn_1_o_pad,
    output cust_qspi_spi_csn_2_o_pad,
    output cust_qspi_spi_csn_3_o_pad,
    inout  cust_qspi_dat_0_io_pad,
    inout  cust_qspi_dat_1_io_pad,
    inout  cust_qspi_dat_2_io_pad,
    inout  cust_qspi_dat_3_io_pad,
    output cust_spfs_clk_o_pad,
    output cust_spfs_cs_o_pad,
    output cust_spfs_mosi_o_pad,
    inout  cust_spfs_miso_i_pad
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
  // io
  logic       s_uart_tx;
  logic       s_uart_rx;
  logic [7:0] s_gpio_out;
  logic [7:0] s_gpio_in;
  logic [7:0] s_gpio_oen;
  logic [7:0] s_gpio_pun;
  logic [7:0] s_gpio_pdn;
  logic       s_psram_sclk;
  logic [1:0] s_psram_ce;
  logic       s_psram_sio0_i;
  logic       s_psram_sio1_i;
  logic       s_psram_sio2_i;
  logic       s_psram_sio3_i;
  logic       s_psram_sio0_o;
  logic       s_psram_sio1_o;
  logic       s_psram_sio2_o;
  logic       s_psram_sio3_o;
  logic       s_psram_sio_oe;
  logic       s_spisd_sclk;
  logic       s_spisd_cs;
  logic       s_spisd_mosi;
  logic       s_spisd_miso;
  logic       s_irq_pin;
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
  // cust
  logic       s_cust_uart_rx;
  logic       s_cust_uart_tx;
  logic [3:0] s_cust_pwm_pwm;
  logic       s_cust_ps2_ps2_clk;
  logic       s_cust_ps2_ps2_dat;
  logic       s_cust_i2c_scl_i;
  logic       s_cust_i2c_scl_o;
  logic       s_cust_i2c_scl_dir;
  logic       s_cust_i2c_sda_i;
  logic       s_cust_i2c_sda_o;
  logic       s_cust_i2c_sda_dir;
  logic       s_cust_qspi_spi_clk;
  logic [3:0] s_cust_qspi_spi_csn;
  logic [3:0] s_cust_qspi_spi_sdo;
  logic [3:0] s_cust_qspi_spi_oe;
  logic [3:0] s_cust_qspi_spi_sdi;
  logic       s_cust_spfs_clk;
  logic       s_cust_spfs_cs;
  logic       s_cust_spfs_mosi;
  logic       s_cust_spfs_miso;


  // verilog_format: off
  tc_io_xtl_pad         u_xtal_io_pad          (.xi_pad(xi_i_pad),               .xo_pad(xo_o_pad),            .en(1'b1),                       .clk(s_xtal_io));
  tc_io_tri_pad         u_extclk_i_pad         (.pad(extclk_i_pad),              .c2p(),                       .c2p_en(1'b0),                   .p2c(s_ext_clk));
  tc_io_tri_pad         u_audclk_i_pad         (.pad(audclk_i_pad),              .c2p(),                       .c2p_en(1'b0),                   .p2c(s_aud_clk));
`ifdef CORE_MDD
  tc_io_tri_pad         u_core_mdd_sel_0_i_pad (.pad(core_mdd_sel_0_i_pad),      .c2p(),                       .c2p_en(1'b0),                   .p2c(s_core_mdd_sel[0]));
  tc_io_tri_pad         u_core_mdd_sel_1_i_pad (.pad(core_mdd_sel_1_i_pad),      .c2p(),                       .c2p_en(1'b0),                   .p2c(s_core_mdd_sel[1]));
  tc_io_tri_pad         u_core_mdd_sel_2_i_pad (.pad(core_mdd_sel_2_i_pad),      .c2p(),                       .c2p_en(1'b0),                   .p2c(s_core_mdd_sel[2]));
  tc_io_tri_pad         u_core_mdd_sel_3_i_pad (.pad(core_mdd_sel_3_i_pad),      .c2p(),                       .c2p_en(1'b0),                   .p2c(s_core_mdd_sel[3]));
  tc_io_tri_pad         u_core_mdd_sel_4_i_pad (.pad(core_mdd_sel_4_i_pad),      .c2p(),                       .c2p_en(1'b0),                   .p2c(s_core_mdd_sel[4]));
`endif
`ifdef IP_MDD
  tc_io_tri_pad         u_ip_mdd_gpio_0_io_pad (.pad(ip_mdd_gpio_0_io_pad),      .c2p(s_ip_mdd_gpio_out[0]),   .c2p_en(~s_ip_mdd_gpio_oen[0]),  .p2c(s_ip_mdd_gpio_in[0]));
  tc_io_tri_pad         u_ip_mdd_gpio_1_io_pad (.pad(ip_mdd_gpio_1_io_pad),      .c2p(s_ip_mdd_gpio_out[1]),   .c2p_en(~s_ip_mdd_gpio_oen[1]),  .p2c(s_ip_mdd_gpio_in[1]));
  tc_io_tri_pad         u_ip_mdd_gpio_2_io_pad (.pad(ip_mdd_gpio_2_io_pad),      .c2p(s_ip_mdd_gpio_out[2]),   .c2p_en(~s_ip_mdd_gpio_oen[2]),  .p2c(s_ip_mdd_gpio_in[2]));
  tc_io_tri_pad         u_ip_mdd_gpio_3_io_pad (.pad(ip_mdd_gpio_3_io_pad),      .c2p(s_ip_mdd_gpio_out[3]),   .c2p_en(~s_ip_mdd_gpio_oen[3]),  .p2c(s_ip_mdd_gpio_in[3]));
  tc_io_tri_pad         u_ip_mdd_gpio_4_io_pad (.pad(ip_mdd_gpio_4_io_pad),      .c2p(s_ip_mdd_gpio_out[4]),   .c2p_en(~s_ip_mdd_gpio_oen[4]),  .p2c(s_ip_mdd_gpio_in[4]));
  tc_io_tri_pad         u_ip_mdd_gpio_5_io_pad (.pad(ip_mdd_gpio_5_io_pad),      .c2p(s_ip_mdd_gpio_out[5]),   .c2p_en(~s_ip_mdd_gpio_oen[5]),  .p2c(s_ip_mdd_gpio_in[5]));
  tc_io_tri_pad         u_ip_mdd_gpio_6_io_pad (.pad(ip_mdd_gpio_6_io_pad),      .c2p(s_ip_mdd_gpio_out[6]),   .c2p_en(~s_ip_mdd_gpio_oen[6]),  .p2c(s_ip_mdd_gpio_in[6]));
  tc_io_tri_pad         u_ip_mdd_gpio_7_io_pad (.pad(ip_mdd_gpio_7_io_pad),      .c2p(s_ip_mdd_gpio_out[7]),   .c2p_en(~s_ip_mdd_gpio_oen[7]),  .p2c(s_ip_mdd_gpio_in[7]));
  tc_io_tri_pad         u_ip_mdd_gpio_8_io_pad (.pad(ip_mdd_gpio_8_io_pad),      .c2p(s_ip_mdd_gpio_out[8]),   .c2p_en(~s_ip_mdd_gpio_oen[8]),  .p2c(s_ip_mdd_gpio_in[8]));
  tc_io_tri_pad         u_ip_mdd_gpio_9_io_pad (.pad(ip_mdd_gpio_9_io_pad),      .c2p(s_ip_mdd_gpio_out[9]),   .c2p_en(~s_ip_mdd_gpio_oen[9]),  .p2c(s_ip_mdd_gpio_in[9]));
  tc_io_tri_pad         u_ip_mdd_gpio_10_io_pad(.pad(ip_mdd_gpio_10_io_pad),     .c2p(s_ip_mdd_gpio_out[10]),  .c2p_en(~s_ip_mdd_gpio_oen[10]), .p2c(s_ip_mdd_gpio_in[10]));
  tc_io_tri_pad         u_ip_mdd_gpio_11_io_pad(.pad(ip_mdd_gpio_11_io_pad),     .c2p(s_ip_mdd_gpio_out[11]),  .c2p_en(~s_ip_mdd_gpio_oen[11]), .p2c(s_ip_mdd_gpio_in[11]));
  tc_io_tri_pad         u_ip_mdd_gpio_12_io_pad(.pad(ip_mdd_gpio_12_io_pad),     .c2p(s_ip_mdd_gpio_out[12]),  .c2p_en(~s_ip_mdd_gpio_oen[12]), .p2c(s_ip_mdd_gpio_in[12]));
  tc_io_tri_pad         u_ip_mdd_gpio_13_io_pad(.pad(ip_mdd_gpio_13_io_pad),     .c2p(s_ip_mdd_gpio_out[13]),  .c2p_en(~s_ip_mdd_gpio_oen[13]), .p2c(s_ip_mdd_gpio_in[13]));
  tc_io_tri_pad         u_ip_mdd_gpio_14_io_pad(.pad(ip_mdd_gpio_14_io_pad),     .c2p(s_ip_mdd_gpio_out[14]),  .c2p_en(~s_ip_mdd_gpio_oen[14]), .p2c(s_ip_mdd_gpio_in[14]));
  tc_io_tri_pad         u_ip_mdd_gpio_15_io_pad(.pad(ip_mdd_gpio_15_io_pad),     .c2p(s_ip_mdd_gpio_out[15]),  .c2p_en(~s_ip_mdd_gpio_oen[15]), .p2c(s_ip_mdd_gpio_in[15]));
`endif
`ifdef HAVE_PLL
  tc_io_tri_pad         u_pll_cfg_0_i_pad      (.pad(pll_cfg_0_i_pad),           .c2p(),                       .c2p_en(1'b0),                   .p2c(s_pll_cfg[0]));
  tc_io_tri_pad         u_pll_cfg_1_i_pad      (.pad(pll_cfg_1_i_pad),           .c2p(),                       .c2p_en(1'b0),                   .p2c(s_pll_cfg[1]));
  tc_io_tri_pad         u_pll_cfg_2_i_pad      (.pad(pll_cfg_2_i_pad),           .c2p(),                       .c2p_en(1'b0),                   .p2c(s_pll_cfg[2]));
`endif
  tc_io_tri_pad         u_clk_bypass_i_pad     (.pad(clk_bypass_i_pad),          .c2p(),                       .c2p_en(1'b0),                   .p2c(s_clk_bypass));
  tc_io_tri_schmitt_pad u_ext_rst_n_i_pad      (.pad(ext_rst_n_i_pad),           .c2p(),                       .c2p_en(1'b0),                   .p2c(s_ext_rst_n));
  tc_io_tri_pad         u_sys_clkdiv4_o_pad    (.pad(sys_clkdiv4_o_pad),         .c2p(s_sys_clkdiv4),          .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad         u_uart_tx_o_pad        (.pad(uart_tx_o_pad),             .c2p(s_uart_tx),              .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad         u_uart_rx_i_pad        (.pad(uart_rx_i_pad),             .c2p(),                       .c2p_en(1'b0),                   .p2c(s_uart_rx));
  tc_io_tri_pad         u_gpio_0_io_pad        (.pad(gpio_0_io_pad),             .c2p(s_gpio_out[0]),          .c2p_en(~s_gpio_oen[0]),         .p2c(s_gpio_in[0]));
  tc_io_tri_pad         u_gpio_1_io_pad        (.pad(gpio_1_io_pad),             .c2p(s_gpio_out[1]),          .c2p_en(~s_gpio_oen[1]),         .p2c(s_gpio_in[1]));
  tc_io_tri_pad         u_gpio_2_io_pad        (.pad(gpio_2_io_pad),             .c2p(s_gpio_out[2]),          .c2p_en(~s_gpio_oen[2]),         .p2c(s_gpio_in[2]));
  tc_io_tri_pad         u_gpio_3_io_pad        (.pad(gpio_3_io_pad),             .c2p(s_gpio_out[3]),          .c2p_en(~s_gpio_oen[3]),         .p2c(s_gpio_in[3]));
  tc_io_tri_schmitt_pad u_gpio_4_io_pad        (.pad(gpio_4_io_pad),             .c2p(s_gpio_out[4]),          .c2p_en(~s_gpio_oen[4]),         .p2c(s_gpio_in[4]));
  tc_io_tri_schmitt_pad u_gpio_5_io_pad        (.pad(gpio_5_io_pad),             .c2p(s_gpio_out[5]),          .c2p_en(~s_gpio_oen[5]),         .p2c(s_gpio_in[5]));
  tc_io_tri_schmitt_pad u_gpio_6_io_pad        (.pad(gpio_6_io_pad),             .c2p(s_gpio_out[6]),          .c2p_en(~s_gpio_oen[6]),         .p2c(s_gpio_in[6]));
  tc_io_tri_schmitt_pad u_gpio_7_io_pad        (.pad(gpio_7_io_pad),             .c2p(s_gpio_out[7]),          .c2p_en(~s_gpio_oen[7]),         .p2c(s_gpio_in[7]));
  tc_io_tri_pad         u_psram_sclk_o_pad     (.pad(psram_sclk_o_pad),          .c2p(s_psram_sclk),           .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad         u_psram_ce0_o_pad      (.pad(psram_ce0_o_pad),           .c2p(s_psram_ce[0]),          .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad         u_psram_ce1_o_pad      (.pad(psram_ce1_o_pad),           .c2p(s_psram_ce[1]),          .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad         u_psram_sio0_io_pad    (.pad(psram_sio0_io_pad),         .c2p(s_psram_sio0_o),         .c2p_en(~s_psram_sio_oe),        .p2c(s_psram_sio0_i));
  tc_io_tri_pad         u_psram_sio1_io_pad    (.pad(psram_sio1_io_pad),         .c2p(s_psram_sio1_o),         .c2p_en(~s_psram_sio_oe),        .p2c(s_psram_sio1_i));
  tc_io_tri_pad         u_psram_sio2_io_pad    (.pad(psram_sio2_io_pad),         .c2p(s_psram_sio2_o),         .c2p_en(~s_psram_sio_oe),        .p2c(s_psram_sio2_i));
  tc_io_tri_pad         u_psram_sio3_io_pad    (.pad(psram_sio3_io_pad),         .c2p(s_psram_sio3_o),         .c2p_en(~s_psram_sio_oe),        .p2c(s_psram_sio3_i));
  tc_io_tri_pad         u_spisd_sclk_o_pad     (.pad(spisd_sclk_o_pad),          .c2p(s_spisd_sclk),           .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad         u_spisd_cs_o_pad       (.pad(spisd_cs_o_pad),            .c2p(s_spisd_cs),             .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad         u_spisd_mosi_o_pad     (.pad(spisd_mosi_o_pad),          .c2p(s_spisd_mosi),           .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad         u_spisd_miso_i_pad     (.pad(spisd_miso_i_pad),          .c2p(),                       .c2p_en(1'b0),                   .p2c(s_spisd_miso));
  tc_io_tri_schmitt_pad u_irq_pin_i_pad        (.pad(irq_pin_i_pad),             .c2p(),                       .c2p_en(1'b0),                   .p2c(s_irq_pin));
  // cust
  tc_io_tri_pad u_cust_uart_tx_o_pad           (.pad(cust_uart_tx_o_pad),        .c2p(s_cust_uart_tx),         .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad u_cust_uart_rx_i_pad           (.pad(cust_uart_rx_i_pad),        .c2p(),                       .c2p_en(1'b0),                   .p2c(s_cust_uart_rx));
  tc_io_tri_pad u_cust_pwm_pwm_0_o_pad         (.pad(cust_pwm_pwm_0_o_pad),      .c2p(s_cust_pwm_pwm[0]),      .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad u_cust_pwm_pwm_1_o_pad         (.pad(cust_pwm_pwm_1_o_pad),      .c2p(s_cust_pwm_pwm[1]),      .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad u_cust_pwm_pwm_2_o_pad         (.pad(cust_pwm_pwm_2_o_pad),      .c2p(s_cust_pwm_pwm[2]),      .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad u_cust_pwm_pwm_3_o_pad         (.pad(cust_pwm_pwm_3_o_pad),      .c2p(s_cust_pwm_pwm[3]),      .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad u_cust_ps2_ps2_clk_i_pad       (.pad(cust_ps2_ps2_clk_i_pad),    .c2p(),                       .c2p_en(1'b0),                   .p2c(s_cust_ps2_ps2_clk));
  tc_io_tri_pad u_cust_ps2_ps2_dat_i_pad       (.pad(cust_ps2_ps2_dat_i_pad),    .c2p(),                       .c2p_en(1'b0),                   .p2c(s_cust_ps2_ps2_dat));
  tc_io_tri_pad u_cust_i2c_scl_io_pad          (.pad(cust_i2c_scl_io_pad),       .c2p(s_cust_i2c_scl_o),       .c2p_en(~s_cust_i2c_scl_dir),    .p2c(s_cust_i2c_scl_i));
  tc_io_tri_pad u_cust_i2c_sda_io_pad          (.pad(cust_i2c_sda_io_pad),       .c2p(s_cust_i2c_sda_o),       .c2p_en(~s_cust_i2c_sda_dir),    .p2c(s_cust_i2c_sda_i));
  tc_io_tri_pad u_cust_qspi_spi_clk_o_pad      (.pad(cust_qspi_spi_clk_o_pad),   .c2p(s_cust_qspi_spi_clk),    .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad u_cust_qspi_spi_csn_0_o_pad    (.pad(cust_qspi_spi_csn_0_o_pad), .c2p(s_cust_qspi_spi_csn[0]), .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad u_cust_qspi_spi_csn_1_o_pad    (.pad(cust_qspi_spi_csn_1_o_pad), .c2p(s_cust_qspi_spi_csn[1]), .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad u_cust_qspi_spi_csn_2_o_pad    (.pad(cust_qspi_spi_csn_2_o_pad), .c2p(s_cust_qspi_spi_csn[2]), .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad u_cust_qspi_spi_csn_3_o_pad    (.pad(cust_qspi_spi_csn_3_o_pad), .c2p(s_cust_qspi_spi_csn[3]), .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad u_cust_qspi_dat_0_io_pad       (.pad(cust_qspi_dat_0_io_pad),    .c2p(s_cust_qspi_spi_sdo[0]), .c2p_en(s_cust_qspi_spi_oe[0]),  .p2c(s_cust_qspi_spi_sdi[0]));
  tc_io_tri_pad u_cust_qspi_dat_1_io_pad       (.pad(cust_qspi_dat_1_io_pad),    .c2p(s_cust_qspi_spi_sdo[1]), .c2p_en(s_cust_qspi_spi_oe[1]),  .p2c(s_cust_qspi_spi_sdi[1]));
  tc_io_tri_pad u_cust_qspi_dat_2_io_pad       (.pad(cust_qspi_dat_2_io_pad),    .c2p(s_cust_qspi_spi_sdo[2]), .c2p_en(s_cust_qspi_spi_oe[2]),  .p2c(s_cust_qspi_spi_sdi[2]));
  tc_io_tri_pad u_cust_qspi_dat_3_io_pad       (.pad(cust_qspi_dat_3_io_pad),    .c2p(s_cust_qspi_spi_sdo[3]), .c2p_en(s_cust_qspi_spi_oe[3]),  .p2c(s_cust_qspi_spi_sdi[3]));
  tc_io_tri_pad u_cust_spfs_clk_o_pad          (.pad(cust_spfs_clk_o_pad),       .c2p(s_cust_spfs_clk),        .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad u_cust_spfs_cs_o_pad           (.pad(cust_spfs_cs_o_pad),        .c2p(s_cust_spfs_cs),         .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad u_cust_spfs_mosi_o_pad         (.pad(cust_spfs_mosi_o_pad),      .c2p(s_cust_spfs_mosi),       .c2p_en(1'b1),                   .p2c());
  tc_io_tri_pad u_cust_spfs_miso_i_pad         (.pad(cust_spfs_miso_i_pad),      .c2p(),                       .c2p_en(1'b0),                   .p2c(s_cust_spfs_miso));

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
      .clk_i              (s_sys_clk),
      .rst_n_i            (s_sys_rst_n),
      .clk_aud_i          (s_aud_clk),
      .rst_aud_n_i        (s_aud_rst_n),
`ifdef CORE_MDD
      .core_mdd_sel_i     (s_core_mdd_sel),
`endif
`ifdef IP_MDD
      .ip_mdd_gpio_out_o  (s_ip_mdd_gpio_out),
      .ip_mdd_gpio_in_i   (s_ip_mdd_gpio_in),
      .ip_mdd_gpio_oen_o  (s_ip_mdd_gpio_oen),
`endif
`ifdef HAVE_SRAM_IF
      .ram_addr_o         (s_ram_addr),
      .ram_wdata_o        (s_ram_wdata),
      .ram_wstrb_o        (s_ram_wstrb),
      .ram_rdata_i        (s_ram_rdata),
`endif
      .gpio_out_o         (s_gpio_out),
      .gpio_in_i          (s_gpio_in),
      .gpio_pun_o         (s_gpio_pun),
      .gpio_pdn_o         (s_gpio_pdn),
      .gpio_oen_o         (s_gpio_oen),
      .uart_tx_o          (s_uart_tx),
      .uart_rx_i          (s_uart_rx),
      .psram_sclk_o       (s_psram_sclk),
      .psram_ce_o         (s_psram_ce),
      .psram_sio0_i       (s_psram_sio0_i),
      .psram_sio1_i       (s_psram_sio1_i),
      .psram_sio2_i       (s_psram_sio2_i),
      .psram_sio3_i       (s_psram_sio3_i),
      .psram_sio0_o       (s_psram_sio0_o),
      .psram_sio1_o       (s_psram_sio1_o),
      .psram_sio2_o       (s_psram_sio2_o),
      .psram_sio3_o       (s_psram_sio3_o),
      .psram_sio_oe_o     (s_psram_sio_oe),
      .spisd_sclk_o       (s_spisd_sclk),
      .spisd_cs_o         (s_spisd_cs),
      .spisd_mosi_o       (s_spisd_mosi),
      .spisd_miso_i       (s_spisd_miso),
      .irq_pin_i          (s_irq_pin),
      .cust_uart_rx_i     (s_cust_uart_rx),
      .cust_uart_tx_o     (s_cust_uart_tx),
      .cust_pwm_pwm_o     (s_cust_pwm_pwm),
      .cust_ps2_ps2_clk_i (s_cust_ps2_ps2_clk),
      .cust_ps2_ps2_dat_i (s_cust_ps2_ps2_dat),
      .cust_i2c_scl_i     (s_cust_i2c_scl_i),
      .cust_i2c_scl_o     (s_cust_i2c_scl_o),
      .cust_i2c_scl_dir_o (s_cust_i2c_scl_dir),
      .cust_i2c_sda_i     (s_cust_i2c_sda_i),
      .cust_i2c_sda_o     (s_cust_i2c_sda_o),
      .cust_i2c_sda_dir_o (s_cust_i2c_sda_dir),
      .cust_qspi_spi_clk_o(s_cust_qspi_spi_clk),
      .cust_qspi_spi_csn_o(s_cust_qspi_spi_csn),
      .cust_qspi_spi_sdo_o(s_cust_qspi_spi_sdo),
      .cust_qspi_spi_oe_o (s_cust_qspi_spi_oe),
      .cust_qspi_spi_sdi_i(s_cust_qspi_spi_sdi),
`ifdef HAVE_PLL
      .cust_spfs_div4_i   (s_pll_cfg[2]),
`else
      .cust_spfs_div4_i   ('0),
`endif
      .cust_spfs_clk_o    (s_cust_spfs_clk),
      .cust_spfs_cs_o     (s_cust_spfs_cs),
      .cust_spfs_mosi_o   (s_cust_spfs_mosi),
      .cust_spfs_miso_i   (s_cust_spfs_miso)
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
