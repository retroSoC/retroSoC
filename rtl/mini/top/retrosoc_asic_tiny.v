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

`timescale 1 ns / 1 ps

// NOTE: need to focus on the port dir
module retrosoc_asic_tiny (
    input  extclk_i_pad,
    input  ext_rst_n_i_pad,
    // UART
    output uart_tx_o_pad,
    input  uart_rx_i_pad,
    // GPIO
    output gpio_0_io_pad,
    output gpio_1_io_pad,
    output gpio_2_io_pad,
    output gpio_3_io_pad,
    output gpio_4_io_pad,
    output gpio_5_io_pad,
    output gpio_6_io_pad,
    output gpio_7_io_pad,
    output gpio_8_io_pad,
    output gpio_9_io_pad,
    output gpio_10_io_pad,
    output gpio_11_io_pad,
    output gpio_12_io_pad,
    output gpio_13_io_pad,
    output gpio_14_io_pad,
    output gpio_15_io_pad,
    // CUST
    output cust_qspi_spi_clk_o_pad,
    output cust_qspi_spi_csn_0_o_pad,
    output cust_qspi_spi_csn_1_o_pad,
    output cust_qspi_spi_csn_2_o_pad,
    output cust_qspi_spi_csn_3_o_pad,
    inout  cust_qspi_dat_0_io_pad,
    inout  cust_qspi_dat_1_io_pad,
    inout  cust_qspi_dat_2_io_pad,
    inout  cust_qspi_dat_3_io_pad,
    output cust_psram_sclk_o_pad,
    output cust_psram_ce_o_pad,
    inout  cust_psram_sio0_io_pad,
    inout  cust_psram_sio1_io_pad,
    inout  cust_psram_sio2_io_pad,
    inout  cust_psram_sio3_io_pad,
    output cust_spfs_clk_o_pad,
    output cust_spfs_cs_o_pad,
    output cust_spfs_mosi_o_pad,
    inout  cust_spfs_miso_i_pad
);
  // ip
  wire        s_ext_clk_i;
  wire        s_ext_rst_n_i;
  wire        s_uart_tx_o;
  wire        s_uart_rx_i;
  wire [15:0] s_gpio_out_o;
  wire [15:0] s_gpio_in_i;
  wire [15:0] s_gpio_outenb_o;
  wire [15:0] s_gpio_pullupb_o;
  wire [15:0] s_gpio_pulldownb_o;
  wire        s_cust_qspi_spi_clk_o;
  wire [ 3:0] s_cust_qspi_spi_csn_o;
  wire [ 3:0] s_cust_qspi_spi_sdo_o;
  wire [ 3:0] s_cust_qspi_spi_oe_o;
  wire [ 3:0] s_cust_qspi_spi_sdi_i;
  wire        s_cust_psram_sclk_o;
  wire        s_cust_psram_ce_o;
  wire        s_cust_psram_sio0_i;
  wire        s_cust_psram_sio1_i;
  wire        s_cust_psram_sio2_i;
  wire        s_cust_psram_sio3_i;
  wire        s_cust_psram_sio0_o;
  wire        s_cust_psram_sio1_o;
  wire        s_cust_psram_sio2_o;
  wire        s_cust_psram_sio3_o;
  wire        s_cust_psram_sio_oe_o;
  wire        s_cust_spfs_clk_o;
  wire        s_cust_spfs_cs_o;
  wire        s_cust_spfs_mosi_o;
  wire        s_cust_spfs_miso_i;

  // verilog_format: off
  tc_io_tri_pad         u_extclk_i_pad      (.pad(extclk_i_pad),       .c2p(),                 .c2p_en(1'b0),                 .p2c(s_ext_clk_i));
  tc_io_tri_schmitt_pad u_ext_rst_n_i_pad   (.pad(ext_rst_n_i_pad),    .c2p(),                 .c2p_en(1'b0),                 .p2c(s_ext_rst_n_i));
  tc_io_tri_pad         u_uart_tx_o_pad     (.pad(uart_tx_o_pad),      .c2p(s_uart_tx_o),      .c2p_en(1'b1),                 .p2c());
  tc_io_tri_pad         u_uart_rx_i_pad     (.pad(uart_rx_i_pad),      .c2p(),                 .c2p_en(1'b0),                 .p2c(s_uart_rx_i));
  tc_io_tri_pad         u_gpio_0_io_pad     (.pad(gpio_0_io_pad),      .c2p(s_gpio_out_o[0]),  .c2p_en(~s_gpio_outenb_o[0]),  .p2c(s_gpio_in_i[0]));
  tc_io_tri_pad         u_gpio_1_io_pad     (.pad(gpio_1_io_pad),      .c2p(s_gpio_out_o[1]),  .c2p_en(~s_gpio_outenb_o[1]),  .p2c(s_gpio_in_i[1]));
  tc_io_tri_pad         u_gpio_2_io_pad     (.pad(gpio_2_io_pad),      .c2p(s_gpio_out_o[2]),  .c2p_en(~s_gpio_outenb_o[2]),  .p2c(s_gpio_in_i[2]));
  tc_io_tri_pad         u_gpio_3_io_pad     (.pad(gpio_3_io_pad),      .c2p(s_gpio_out_o[3]),  .c2p_en(~s_gpio_outenb_o[3]),  .p2c(s_gpio_in_i[3]));
  tc_io_tri_pad         u_gpio_4_io_pad     (.pad(gpio_4_io_pad),      .c2p(s_gpio_out_o[4]),  .c2p_en(~s_gpio_outenb_o[4]),  .p2c(s_gpio_in_i[4]));
  tc_io_tri_pad         u_gpio_5_io_pad     (.pad(gpio_5_io_pad),      .c2p(s_gpio_out_o[5]),  .c2p_en(~s_gpio_outenb_o[5]),  .p2c(s_gpio_in_i[5]));
  tc_io_tri_pad         u_gpio_6_io_pad     (.pad(gpio_6_io_pad),      .c2p(s_gpio_out_o[6]),  .c2p_en(~s_gpio_outenb_o[6]),  .p2c(s_gpio_in_i[6]));
  tc_io_tri_pad         u_gpio_7_io_pad     (.pad(gpio_7_io_pad),      .c2p(s_gpio_out_o[7]),  .c2p_en(~s_gpio_outenb_o[7]),  .p2c(s_gpio_in_i[7]));
  tc_io_tri_schmitt_pad u_gpio_8_io_pad     (.pad(gpio_8_io_pad),      .c2p(s_gpio_out_o[8]),  .c2p_en(~s_gpio_outenb_o[8]),  .p2c(s_gpio_in_i[8]));
  tc_io_tri_schmitt_pad u_gpio_9_io_pad     (.pad(gpio_9_io_pad),      .c2p(s_gpio_out_o[9]),  .c2p_en(~s_gpio_outenb_o[9]),  .p2c(s_gpio_in_i[9]));
  tc_io_tri_schmitt_pad u_gpio_10_io_pad    (.pad(gpio_10_io_pad),     .c2p(s_gpio_out_o[10]), .c2p_en(~s_gpio_outenb_o[10]), .p2c(s_gpio_in_i[10]));
  tc_io_tri_schmitt_pad u_gpio_11_io_pad    (.pad(gpio_11_io_pad),     .c2p(s_gpio_out_o[11]), .c2p_en(~s_gpio_outenb_o[11]), .p2c(s_gpio_in_i[11]));
  tc_io_tri_schmitt_pad u_gpio_12_io_pad    (.pad(gpio_12_io_pad),     .c2p(s_gpio_out_o[12]), .c2p_en(~s_gpio_outenb_o[12]), .p2c(s_gpio_in_i[12]));
  tc_io_tri_schmitt_pad u_gpio_13_io_pad    (.pad(gpio_13_io_pad),     .c2p(s_gpio_out_o[13]), .c2p_en(~s_gpio_outenb_o[13]), .p2c(s_gpio_in_i[13]));
  tc_io_tri_schmitt_pad u_gpio_14_io_pad    (.pad(gpio_14_io_pad),     .c2p(s_gpio_out_o[14]), .c2p_en(~s_gpio_outenb_o[14]), .p2c(s_gpio_in_i[14]));
  tc_io_tri_schmitt_pad u_gpio_15_io_pad    (.pad(gpio_15_io_pad),     .c2p(s_gpio_out_o[15]), .c2p_en(~s_gpio_outenb_o[15]), .p2c(s_gpio_in_i[15]));
  // cust
  tc_io_tri_pad u_cust_qspi_spi_clk_o_pad  (.pad(cust_qspi_spi_clk_o_pad),   .c2p(s_cust_qspi_spi_clk_o),    .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad u_cust_qspi_spi_csn_0_o_pad(.pad(cust_qspi_spi_csn_0_o_pad), .c2p(s_cust_qspi_spi_csn_o[0]), .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad u_cust_qspi_spi_csn_1_o_pad(.pad(cust_qspi_spi_csn_1_o_pad), .c2p(s_cust_qspi_spi_csn_o[1]), .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad u_cust_qspi_spi_csn_2_o_pad(.pad(cust_qspi_spi_csn_2_o_pad), .c2p(s_cust_qspi_spi_csn_o[2]), .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad u_cust_qspi_spi_csn_3_o_pad(.pad(cust_qspi_spi_csn_3_o_pad), .c2p(s_cust_qspi_spi_csn_o[3]), .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad u_cust_qspi_dat_0_io_pad   (.pad(cust_qspi_dat_0_io_pad),    .c2p(s_cust_qspi_spi_sdo_o[0]), .c2p_en(s_cust_qspi_spi_oe_o[0]),  .p2c(s_cust_qspi_spi_sdi_i[0]));
  tc_io_tri_pad u_cust_qspi_dat_1_io_pad   (.pad(cust_qspi_dat_1_io_pad),    .c2p(s_cust_qspi_spi_sdo_o[1]), .c2p_en(s_cust_qspi_spi_oe_o[1]),  .p2c(s_cust_qspi_spi_sdi_i[1]));
  tc_io_tri_pad u_cust_qspi_dat_2_io_pad   (.pad(cust_qspi_dat_2_io_pad),    .c2p(s_cust_qspi_spi_sdo_o[2]), .c2p_en(s_cust_qspi_spi_oe_o[2]),  .p2c(s_cust_qspi_spi_sdi_i[2]));
  tc_io_tri_pad u_cust_qspi_dat_3_io_pad   (.pad(cust_qspi_dat_3_io_pad),    .c2p(s_cust_qspi_spi_sdo_o[3]), .c2p_en(s_cust_qspi_spi_oe_o[3]),  .p2c(s_cust_qspi_spi_sdi_i[3]));
  tc_io_tri_pad u_cust_psram_sclk_o_pad    (.pad(cust_psram_sclk_o_pad),     .c2p(s_cust_psram_sclk_o),      .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad u_cust_psram_ce_o_pad      (.pad(cust_psram_ce_o_pad),       .c2p(s_cust_psram_ce_o),        .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad u_cust_psram_sio0_io_pad   (.pad(cust_psram_sio0_io_pad),    .c2p(s_cust_psram_sio0_o),      .c2p_en(~s_cust_psram_sio_oe_o),   .p2c(s_cust_psram_sio0_i));
  tc_io_tri_pad u_cust_psram_sio1_io_pad   (.pad(cust_psram_sio1_io_pad),    .c2p(s_cust_psram_sio1_o),      .c2p_en(~s_cust_psram_sio_oe_o),   .p2c(s_cust_psram_sio1_i));
  tc_io_tri_pad u_cust_psram_sio2_io_pad   (.pad(cust_psram_sio2_io_pad),    .c2p(s_cust_psram_sio2_o),      .c2p_en(~s_cust_psram_sio_oe_o),   .p2c(s_cust_psram_sio2_i));
  tc_io_tri_pad u_cust_psram_sio3_io_pad   (.pad(cust_psram_sio3_io_pad),    .c2p(s_cust_psram_sio3_o),      .c2p_en(~s_cust_psram_sio_oe_o),   .p2c(s_cust_psram_sio3_i));
  tc_io_tri_pad u_cust_spfs_clk_o_pad      (.pad(cust_spfs_clk_o_pad),       .c2p(s_cust_spfs_clk_o),        .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad u_cust_spfs_cs_o_pad       (.pad(cust_spfs_cs_o_pad),        .c2p(s_cust_spfs_cs_o),         .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad u_cust_spfs_mosi_o_pad     (.pad(cust_spfs_mosi_o_pad),      .c2p(s_cust_spfs_mosi_o),       .c2p_en(1'b1),                     .p2c());
  tc_io_tri_pad u_cust_spfs_miso_i_pad     (.pad(cust_spfs_miso_i_pad),      .c2p(),                         .c2p_en(1'b0),                     .p2c(s_cust_spfs_miso_i));
  // verilog_format: on

  retrosoc_tiny u_retrosoc_tiny (
      .clk_i                    (s_ext_clk_i),
      .rst_n_i                  (s_ext_rst_n_i),
      .clk_ext_sel_i            (1'b1),
      .gpio_out_o               (s_gpio_out_o),
      .gpio_in_i                (s_gpio_in_i),
      .gpio_pullupb_o           (s_gpio_pullupb_o),
      .gpio_pulldownb_o         (s_gpio_pulldownb_o),
      .gpio_outenb_o            (s_gpio_outenb_o),
      .spi_slv_ro_config_i      (8'd0),
      .spi_slv_ro_xtal_ena_i    (1'b0),
      .spi_slv_ro_reg_ena_i     (1'b0),
      .spi_slv_ro_pll_cp_ena_i  (1'b0),
      .spi_slv_ro_pll_vco_ena_i (1'b0),
      .spi_slv_ro_pll_bias_ena_i(1'b0),
      .spi_slv_ro_pll_trim_i    (4'd0),
      .spi_slv_ro_mfgr_id_i     (12'd0),
      .spi_slv_ro_prod_id_i     (8'd0),
      .spi_slv_ro_mask_rev_i    (4'd0),
      .uart_tx_o                (s_uart_tx_o),
      .uart_rx_i                (s_uart_rx_i),
      .cust_qspi_spi_clk_o      (s_cust_qspi_spi_clk_o),
      .cust_qspi_spi_csn_o      (s_cust_qspi_spi_csn_o),
      .cust_qspi_spi_sdo_o      (s_cust_qspi_spi_sdo_o),
      .cust_qspi_spi_oe_o       (s_cust_qspi_spi_oe_o),
      .cust_qspi_spi_sdi_i      (s_cust_qspi_spi_sdi_i),
      .cust_psram_sclk_o        (s_cust_psram_sclk_o),
      .cust_psram_ce_o          (s_cust_psram_ce_o),
      .cust_psram_sio0_i        (s_cust_psram_sio0_i),
      .cust_psram_sio1_i        (s_cust_psram_sio1_i),
      .cust_psram_sio2_i        (s_cust_psram_sio2_i),
      .cust_psram_sio3_i        (s_cust_psram_sio3_i),
      .cust_psram_sio0_o        (s_cust_psram_sio0_o),
      .cust_psram_sio1_o        (s_cust_psram_sio1_o),
      .cust_psram_sio2_o        (s_cust_psram_sio2_o),
      .cust_psram_sio3_o        (s_cust_psram_sio3_o),
      .cust_psram_sio_oe_o      (s_cust_psram_sio_oe_o),
      .cust_spfs_div4_i         (1'b0),
      .cust_spfs_clk_o          (s_cust_spfs_clk_o),
      .cust_spfs_cs_o           (s_cust_spfs_cs_o),
      .cust_spfs_mosi_o         (s_cust_spfs_mosi_o),
      .cust_spfs_miso_i         (s_cust_spfs_miso_i)
  );
endmodule
