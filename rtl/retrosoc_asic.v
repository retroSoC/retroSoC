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
module retrosoc_asic (
    input  xi_i_pad,
    output xo_o_pad,
    input  xclk_i_pad,
    input  rst_n_i_pad,
    // HOUSEKEEPING SPI
    input  hk_sdi_i_pad,
    output hk_sdo_o_pad,
    input  hk_csb_i_pad,
    input  hk_sck_i_pad,
    // SPI MST
    input  spi_mst_sdi_i_pad,
    output spi_mst_csb_o_pad,
    output spi_mst_sck_o_pad,
    output spi_mst_sdo_o_pad,
    // SPI FLASH
    output flash_csb_o_pad,
    output flash_clk_o_pad,
    inout  flash_io0_io_pad,
    inout  flash_io1_io_pad,
    inout  flash_io2_io_pad,
    inout  flash_io3_io_pad,
    // UART
    output uart_tx_o_pad,
    input  uart_rx_i_pad,
    // I2C
    inout  i2c_sda_io_pad,
    inout  i2c_scl_io_pad,
    // GPIO
    output gpio_0_o_pad,
    output gpio_1_o_pad,
    output gpio_2_o_pad,
    output gpio_3_o_pad,
    output gpio_4_o_pad,
    output gpio_5_o_pad,
    output gpio_6_o_pad,
    output gpio_7_o_pad,
    output gpio_8_o_pad,
    output gpio_9_o_pad,
    output gpio_10_o_pad,
    output gpio_11_o_pad,
    output gpio_12_o_pad,
    output gpio_13_o_pad,
    output gpio_14_o_pad,
    output gpio_15_o_pad,
    // IRQ
    input  irq_pin_i_pad,
    // CUST
    output cust_uart_tx_o_pad,
    inout  cust_uart_rx_i_pad,
    output cust_pwm_pwm_0_o_pad,
    output cust_pwm_pwm_1_o_pad,
    output cust_pwm_pwm_2_o_pad,
    output cust_pwm_pwm_3_o_pad,
    inout  cust_ps2_ps2_clk_i_pad,
    inout  cust_ps2_ps2_dat_i_pad
);
  // clk&rst
  wire        s_xtal_io;
  wire        s_xtal_io_buf;
  wire        s_xclk_i;
  wire        s_xclk_i_buf;
  wire        s_pll_clk;
  wire        s_pll_clk_buf;
  wire        s_clk;
  wire        s_clk_buf;  // NOTE: UNUSED
  wire        s_rst_n_i;
  wire        s_rst_n;
  // io
  wire        s_hk_sdi_i;
  wire        s_hk_sdo_o;
  wire        s_hk_csb_i;
  wire        s_hk_sck_i;
  wire        s_spi_mst_sdi_i;
  wire        s_spi_mst_csb_o;
  wire        s_spi_mst_sck_o;
  wire        s_spi_mst_sdo_o;
  wire        s_spi_mst_oenb_o;
  wire        s_flash_csb_o;
  wire        s_flash_clk_o;
  wire        s_flash_clk_oeb_o;
  wire        s_flash_csb_oeb_o;
  wire        s_flash_io0_oeb_o;
  wire        s_flash_io1_oeb_o;
  wire        s_flash_io2_oeb_o;
  wire        s_flash_io3_oeb_o;
  wire        s_flash_io0_do_o;
  wire        s_flash_io1_do_o;
  wire        s_flash_io2_do_o;
  wire        s_flash_io3_do_o;
  wire        s_flash_io0_di_i;
  wire        s_flash_io1_di_i;
  wire        s_flash_io2_di_i;
  wire        s_flash_io3_di_i;
  wire        s_uart_tx_o;
  wire        s_uart_rx_i;
  wire        s_i2c_scl_i;
  wire        s_i2c_scl_o;
  wire        s_i2c_scl_oeb_o;
  wire        s_i2c_sda_i;
  wire        s_i2c_sda_o;
  wire        s_i2c_sda_oeb_o;
  wire [15:0] s_gpio_out_o;
  wire [15:0] s_gpio_in_i;
  wire [15:0] s_gpio_outenb_o;
  wire [15:0] s_gpio_pullupb_o;
  wire [15:0] s_gpio_pulldownb_o;
  wire        s_irq_pin_i;
  // ram
  wire [ 3:0] s_ram_wenb;
  wire [13:0] s_ram_addr;
  wire [31:0] s_ram_wdata;
  wire [31:0] s_ram_rdata;
  // housekeeping
  wire        s_hk_sdo_enb;
  wire        s_hk_xtal_ena;
  wire        s_hk_pll_vco_ena;
  wire        s_hk_pll_vco_in;
  wire        s_hk_pll_cp_ena;
  wire        s_hk_pll_bias_ena;
  wire [ 3:0] s_hk_pll_trim;
  wire        s_hk_pll_bypass;
  wire        s_hk_irq;
  wire        s_hk_rst;
  wire        s_hk_trap;
  wire        s_hk_pt_rst;
  wire        s_hk_pt_csb;
  wire        s_hk_pt_sck;
  wire        s_hk_pt_sdi;
  wire        s_hk_pt_sdo;
  wire [11:0] s_hk_mfgr_id;
  wire [ 7:0] s_hk_prod_id;
  wire [ 3:0] s_hk_mask_rev;
  // cust
  wire        s_cust_uart_rx_i;
  wire        s_cust_uart_tx_o;
  wire [ 3:0] s_cust_pwm_pwm_o;
  wire        s_cust_ps2_ps2_clk_i;
  wire        s_cust_ps2_ps2_dat_i;

  // verilog_format: off
  ihp_io_xtl_pad u_xtal_pad          (.xi_pad(xi_i_pad),        .xo_pad(xo_o_pad),      .en(s_hk_xtal_ena),            .clk(s_xtal_io));
  ihp_io_tri_pad u_xclk_i_pad        (.pad(xclk_i_pad),         .c2p(),                 .c2p_en(1'b0),                 .p2c(s_xclk_i));
  ihp_io_tri_pad u_rst_n_i_pad       (.pad(rst_n_i_pad),        .c2p(),                 .c2p_en(1'b0),                 .p2c(s_rst_n_i));
  ihp_io_tri_pad u_hk_sdi_i_pad      (.pad(hk_sdi_i_pad),       .c2p(),                 .c2p_en(1'b0),                 .p2c(s_hk_sdi_i));
  ihp_io_tri_pad u_hk_sdo_o_pad      (.pad(hk_sdo_o_pad),       .c2p(s_hk_sdo_o),       .c2p_en(~s_hk_sdo_enb),        .p2c());
  ihp_io_tri_pad u_hk_csb_i_pad      (.pad(hk_csb_i_pad),       .c2p(),                 .c2p_en(1'b0),                 .p2c(s_hk_csb_i));
  ihp_io_tri_pad u_hk_sck_i_pad      (.pad(hk_sck_i_pad),       .c2p(),                 .c2p_en(1'b0),                 .p2c(s_hk_sck_i));
  ihp_io_tri_pad u_spi_mst_sdi_i_pad (.pad(spi_mst_sdi_i_pad),  .c2p(),                 .c2p_en(1'b0),                 .p2c(s_spi_mst_sdi_i));
  ihp_io_tri_pad u_spi_mst_csb_o_pad (.pad(spi_mst_csb_o_pad),  .c2p(s_spi_mst_csb_o),  .c2p_en(1'b1),                 .p2c());
  ihp_io_tri_pad u_spi_mst_sck_o_pad (.pad(spi_mst_sck_o_pad),  .c2p(s_spi_mst_sck_o),  .c2p_en(1'b1),                 .p2c());
  ihp_io_tri_pad u_spi_mst_sdo_o_pad (.pad(spi_mst_sdo_o_pad),  .c2p(s_spi_mst_sdo_o),  .c2p_en(~s_spi_mst_oenb_o),    .p2c());
  ihp_io_tri_pad u_flash_csb_o_pad   (.pad(flash_csb_o_pad),    .c2p(s_flash_csb_o),    .c2p_en(~s_flash_csb_oeb_o),   .p2c());
  ihp_io_tri_pad u_flash_clk_o_pad   (.pad(flash_clk_o_pad),    .c2p(s_flash_clk_o),    .c2p_en(~s_flash_clk_oeb_o),   .p2c());
  ihp_io_tri_pad u_flash_io0_io_pad  (.pad(flash_io0_io_pad),   .c2p(s_flash_io0_do_o), .c2p_en(~s_flash_io0_oeb_o),   .p2c(s_flash_io0_di_i));
  ihp_io_tri_pad u_flash_io1_io_pad  (.pad(flash_io1_io_pad),   .c2p(s_flash_io1_do_o), .c2p_en(~s_flash_io1_oeb_o),   .p2c(s_flash_io1_di_i));
  ihp_io_tri_pad u_flash_io2_io_pad  (.pad(flash_io2_io_pad),   .c2p(s_flash_io2_do_o), .c2p_en(~s_flash_io2_oeb_o),   .p2c(s_flash_io2_di_i));
  ihp_io_tri_pad u_flash_io3_io_pad  (.pad(flash_io3_io_pad),   .c2p(s_flash_io3_do_o), .c2p_en(~s_flash_io3_oeb_o),   .p2c(s_flash_io3_di_i));
  ihp_io_tri_pad u_uart_tx_o_pad     (.pad(uart_tx_o_pad),      .c2p(s_uart_tx_o),      .c2p_en(1'b1),                 .p2c());
  ihp_io_tri_pad u_uart_rx_i_pad     (.pad(uart_rx_i_pad),      .c2p(),                 .c2p_en(1'b0),                 .p2c(s_uart_rx_i));
  ihp_io_tri_pad u_i2c_sda_io_pad    (.pad(i2c_sda_io_pad),     .c2p(s_i2c_sda_o),      .c2p_en(~s_i2c_sda_oeb_o),     .p2c(s_i2c_sda_i));
  ihp_io_tri_pad u_i2c_scl_io_pad    (.pad(i2c_scl_io_pad),     .c2p(s_i2c_scl_o),      .c2p_en(~s_i2c_scl_oeb_o),     .p2c(s_i2c_scl_i));
  ihp_io_tri_pad u_gpio_0_o_pad      (.pad(gpio_0_o_pad),       .c2p(s_gpio_out_o[0]),  .c2p_en(~s_gpio_outenb_o[0]),  .p2c(s_gpio_in_i[0]));
  ihp_io_tri_pad u_gpio_1_o_pad      (.pad(gpio_1_o_pad),       .c2p(s_gpio_out_o[1]),  .c2p_en(~s_gpio_outenb_o[1]),  .p2c(s_gpio_in_i[1]));
  ihp_io_tri_pad u_gpio_2_o_pad      (.pad(gpio_2_o_pad),       .c2p(s_gpio_out_o[2]),  .c2p_en(~s_gpio_outenb_o[2]),  .p2c(s_gpio_in_i[2]));
  ihp_io_tri_pad u_gpio_3_o_pad      (.pad(gpio_3_o_pad),       .c2p(s_gpio_out_o[3]),  .c2p_en(~s_gpio_outenb_o[3]),  .p2c(s_gpio_in_i[3]));
  ihp_io_tri_pad u_gpio_4_o_pad      (.pad(gpio_4_o_pad),       .c2p(s_gpio_out_o[4]),  .c2p_en(~s_gpio_outenb_o[4]),  .p2c(s_gpio_in_i[4]));
  ihp_io_tri_pad u_gpio_5_o_pad      (.pad(gpio_5_o_pad),       .c2p(s_gpio_out_o[5]),  .c2p_en(~s_gpio_outenb_o[5]),  .p2c(s_gpio_in_i[5]));
  ihp_io_tri_pad u_gpio_6_o_pad      (.pad(gpio_6_o_pad),       .c2p(s_gpio_out_o[6]),  .c2p_en(~s_gpio_outenb_o[6]),  .p2c(s_gpio_in_i[6]));
  ihp_io_tri_pad u_gpio_7_o_pad      (.pad(gpio_7_o_pad),       .c2p(s_gpio_out_o[7]),  .c2p_en(~s_gpio_outenb_o[7]),  .p2c(s_gpio_in_i[7]));
  ihp_io_tri_pad u_gpio_8_o_pad      (.pad(gpio_8_o_pad),       .c2p(s_gpio_out_o[8]),  .c2p_en(~s_gpio_outenb_o[8]),  .p2c(s_gpio_in_i[8]));
  ihp_io_tri_pad u_gpio_9_o_pad      (.pad(gpio_9_o_pad),       .c2p(s_gpio_out_o[9]),  .c2p_en(~s_gpio_outenb_o[9]),  .p2c(s_gpio_in_i[9]));
  ihp_io_tri_pad u_gpio_10_o_pad     (.pad(gpio_10_o_pad),      .c2p(s_gpio_out_o[10]), .c2p_en(~s_gpio_outenb_o[10]), .p2c(s_gpio_in_i[10]));
  ihp_io_tri_pad u_gpio_11_o_pad     (.pad(gpio_11_o_pad),      .c2p(s_gpio_out_o[11]), .c2p_en(~s_gpio_outenb_o[11]), .p2c(s_gpio_in_i[11]));
  ihp_io_tri_pad u_gpio_12_o_pad     (.pad(gpio_12_o_pad),      .c2p(s_gpio_out_o[12]), .c2p_en(~s_gpio_outenb_o[12]), .p2c(s_gpio_in_i[12]));
  ihp_io_tri_pad u_gpio_13_o_pad     (.pad(gpio_13_o_pad),      .c2p(s_gpio_out_o[13]), .c2p_en(~s_gpio_outenb_o[13]), .p2c(s_gpio_in_i[13]));
  ihp_io_tri_pad u_gpio_14_o_pad     (.pad(gpio_14_o_pad),      .c2p(s_gpio_out_o[14]), .c2p_en(~s_gpio_outenb_o[14]), .p2c(s_gpio_in_i[14]));
  ihp_io_tri_pad u_gpio_15_o_pad     (.pad(gpio_15_o_pad),      .c2p(s_gpio_out_o[15]), .c2p_en(~s_gpio_outenb_o[15]), .p2c(s_gpio_in_i[15]));
  ihp_io_tri_pad u_irq_pin_i_pad     (.pad(irq_pin_i_pad),      .c2p(),                 .c2p_en(1'b0),                 .p2c(s_irq_pin_i));
  // cust
  ihp_io_tri_pad u_cust_uart_tx_o_pad    (.pad(cust_uart_tx_o_pad),     .c2p(s_cust_uart_tx_o),    .c2p_en(1'b1),                 .p2c());
  ihp_io_tri_pad u_cust_uart_rx_i_pad    (.pad(cust_uart_rx_i_pad),     .c2p(),                    .c2p_en(1'b0),                 .p2c(s_cust_uart_rx_i));
  ihp_io_tri_pad u_cust_pwm_pwm_0_o_pad  (.pad(cust_pwm_pwm_0_o_pad),   .c2p(s_cust_pwm_pwm_o[0]), .c2p_en(1'b1),                 .p2c());
  ihp_io_tri_pad u_cust_pwm_pwm_1_o_pad  (.pad(cust_pwm_pwm_1_o_pad),   .c2p(s_cust_pwm_pwm_o[1]), .c2p_en(1'b1),                 .p2c());
  ihp_io_tri_pad u_cust_pwm_pwm_2_o_pad  (.pad(cust_pwm_pwm_2_o_pad),   .c2p(s_cust_pwm_pwm_o[2]), .c2p_en(1'b1),                 .p2c());
  ihp_io_tri_pad u_cust_pwm_pwm_3_o_pad  (.pad(cust_pwm_pwm_3_o_pad),   .c2p(s_cust_pwm_pwm_o[3]), .c2p_en(1'b1),                 .p2c());
  ihp_io_tri_pad u_cust_ps2_ps2_clk_i_pad(.pad(cust_ps2_ps2_clk_i_pad), .c2p(),                    .c2p_en(1'b0),                 .p2c(s_cust_ps2_ps2_clk_i));
  ihp_io_tri_pad u_cust_ps2_ps2_dat_i_pad(.pad(cust_ps2_ps2_dat_i_pad), .c2p(),                    .c2p_en(1'b0),                 .p2c(s_cust_ps2_ps2_dat_i));
  // clk buf
  ihp_clk_buffer u_xtal_buf (.clk_i(s_xtal_io), .clk_o(s_xtal_io_buf));
  ihp_clk_buffer u_xclk_buf (.clk_i(s_xclk_i), .clk_o(s_xclk_i_buf));
  // verilog_format: on

  // reset assignment. "s_rst_n_i" comes from button, while "s_hk_rst"
  // comes from standalone SPI (and is normally zero unless activated from the SPI).
  assign s_clk   = s_hk_pll_bypass ? s_xclk_i_buf : s_pll_clk_buf;
  //   assign s_rst_n = s_rst_n_i & ~s_hk_rst;
  assign s_rst_n = s_rst_n_i;
  retrosoc u_retrosoc (
      .clk_i                    (s_clk),
      .rst_n_i                  (s_rst_n),
      .xtal_in_i                (s_xtal_io_buf),
      .clk_pll_i                (s_pll_clk_buf),
      .clk_ext_sel_i            (s_hk_pll_bypass),
      .hk_pt_i                  (s_hk_pt_rst),
      .hk_pt_csb_i              (s_hk_pt_csb),
      .hk_pt_sck_i              (s_hk_pt_sck),
      .hk_pt_sdi_i              (s_hk_pt_sdi),
      .hk_pt_sdo_o              (s_hk_pt_sdo),
      .ram_wenb_o               (s_ram_wenb),
      .ram_addr_o               (s_ram_addr),
      .ram_wdata_o              (s_ram_wdata),
      .ram_rdata_o              (s_ram_rdata),
      .gpio_out_o               (s_gpio_out_o),
      .gpio_in_i                (s_gpio_in_i),
      .gpio_pullupb_o           (s_gpio_pullupb_o),
      .gpio_pulldownb_o         (s_gpio_pulldownb_o),
      .gpio_outenb_o            (s_gpio_outenb_o),
      .spi_slv_ro_config_i      (8'd0),
      .spi_slv_ro_xtal_ena_i    (s_hk_xtal_ena),
      .spi_slv_ro_reg_ena_i     (1'b0),
      .spi_slv_ro_pll_cp_ena_i  (s_hk_pll_cp_ena),
      .spi_slv_ro_pll_vco_ena_i (s_hk_pll_vco_ena),
      .spi_slv_ro_pll_bias_ena_i(s_hk_pll_bias_ena),
      .spi_slv_ro_pll_trim_i    (s_hk_pll_trim),
      .spi_slv_ro_mfgr_id_i     (s_hk_mfgr_id),
      .spi_slv_ro_prod_id_i     (s_hk_prod_id),
      .spi_slv_ro_mask_rev_i    (s_hk_mask_rev),
      .uart_tx_o                (s_uart_tx_o),
      .uart_rx_i                (s_uart_rx_i),
      .i2c_scl_i                (s_i2c_scl_i),
      .i2c_scl_o                (s_i2c_scl_o),
      .i2c_scl_oeb_o            (s_i2c_scl_oeb_o),
      .i2c_sda_i                (s_i2c_sda_i),
      .i2c_sda_o                (s_i2c_sda_o),
      .i2c_sda_oeb_o            (s_i2c_sda_oeb_o),
      .spi_mst_sdo_o            (s_spi_mst_sdo_o),
      .spi_mst_csb_o            (s_spi_mst_csb_o),
      .spi_mst_sck_o            (s_spi_mst_sck_o),
      .spi_mst_sdi_i            (s_spi_mst_sdi_i),
      .spi_mst_oenb_o           (s_spi_mst_oenb_o),
      .irq_pin_i                (s_irq_pin_i),
      .irq_spi_i                (s_hk_irq),
      .trap_o                   (s_hk_trap),
      .flash_csb_o              (s_flash_csb_o),
      .flash_clk_o              (s_flash_clk_o),
      .flash_clk_oeb_o          (s_flash_clk_oeb_o),
      .flash_csb_oeb_o          (s_flash_csb_oeb_o),
      .flash_io0_oeb_o          (s_flash_io0_oeb_o),
      .flash_io1_oeb_o          (s_flash_io1_oeb_o),
      .flash_io2_oeb_o          (s_flash_io2_oeb_o),
      .flash_io3_oeb_o          (s_flash_io3_oeb_o),
      .flash_io0_do_o           (s_flash_io0_do_o),
      .flash_io1_do_o           (s_flash_io1_do_o),
      .flash_io2_do_o           (s_flash_io2_do_o),
      .flash_io3_do_o           (s_flash_io3_do_o),
      .flash_io0_di_i           (s_flash_io0_di_i),
      .flash_io1_di_i           (s_flash_io1_di_i),
      .flash_io2_di_i           (s_flash_io2_di_i),
      .flash_io3_di_i           (s_flash_io3_di_i),
      .cust_uart_rx_i           (s_cust_uart_rx_i),
      .cust_uart_tx_o           (s_cust_uart_tx_o),
      .cust_pwm_pwm_o           (s_cust_pwm_pwm_o),
      .cust_ps2_ps2_clk_i       (s_cust_ps2_ps2_clk_i),
      .cust_ps2_ps2_dat_i       (s_cust_ps2_ps2_dat_i)
  );

  /* it can control the xtal oscillator, PLL which CANNOT be changed from the CPU */
  /* without potentially killing it.       */
  // 'reg_ena': regulator enable
  ravenna_spi u_ravenna_spi (
      .RST            (~s_rst_n),
      .SCK            (s_hk_sck_i),
      .SDI            (s_hk_sdi_i),
      .CSB            (s_hk_csb_i),
      .SDO            (s_hk_sdo_o),
      .sdo_enb        (s_hk_sdo_enb),
      .xtal_ena       (s_hk_xtal_ena),
      .reg_ena        (),
      .pll_vco_ena    (s_hk_pll_vco_ena),
      .pll_vco_in     (s_hk_pll_vco_in),
      .pll_cp_ena     (s_hk_pll_cp_ena),
      .pll_bias_ena   (s_hk_pll_bias_ena),
      .pll_trim       (s_hk_pll_trim),
      .pll_bypass     (s_hk_pll_bypass),
      .tm_nvcp        (),
      .irq            (s_hk_irq),
      .reset          (s_hk_rst),
      .trap           (s_hk_trap),
      .pass_thru_reset(s_hk_pt_rst),
      .pass_thru_sck  (s_hk_pt_sck),
      .pass_thru_csb  (s_hk_pt_csb),
      .pass_thru_sdi  (s_hk_pt_sdi),
      .pass_thru_sdo  (s_hk_pt_sdo),
      .mask_rev_in    (4'd0),
      .mfgr_id        (s_hk_mfgr_id),
      .prod_id        (s_hk_prod_id),
      .mask_rev       (s_hk_mask_rev)
  );

  spram_model u_spram_model (
      .clk  (s_clk),
      .wen  (~s_ram_wenb),
      .addr (s_ram_addr),
      .wdata(s_ram_wdata),
      .rdata(s_ram_rdata)
  );

  assign s_pll_clk     = s_xclk_i_buf;
  assign s_pll_clk_buf = s_pll_clk;
endmodule
