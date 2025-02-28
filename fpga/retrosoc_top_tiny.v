`timescale 1ns / 1ps

module retrosoc_top_tiny (
    input  clk_i,
    input  rst_n_i,
    input  uart_rx_i,
    output uart_tx_o,
    inout  gpio_io2,
    output cust_qspi_spi_clk_o,
    output cust_qspi_spi_csn_0_o,
    inout  cust_qspi_dat_0_io,
    output cust_psram_sclk_o,
    output cust_psram_ce_0_o,
    inout  cust_psram_sio0_io,
    inout  cust_psram_sio1_io,
    inout  cust_psram_sio2_io,
    inout  cust_psram_sio3_io,
    output cust_spfs_clk_o,
    output cust_spfs_cs_o,
    output cust_spfs_mosi_o,
    input  cust_spfs_miso_i
);

  wire s_sys_clk;
  clk_wiz_0 u_clk_wiz_0 (
      .clk_in1 (clk_i),
      .clk_out1(s_sys_clk)
  );

  retrosoc_asic_tiny u_retrosoc_tiny (
      .extclk_i_pad             (s_sys_clk),
      .ext_rst_n_i_pad          (rst_n_i),
      // UART
      .uart_tx_o_pad            (uart_tx_o),
      .uart_rx_i_pad            (uart_rx_i),
      // GPIO
      .gpio_0_io_pad            (),
      .gpio_1_io_pad            (),
      .gpio_2_io_pad            (gpio_io2),
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
      // CUST
      .cust_qspi_spi_clk_o_pad  (cust_qspi_spi_clk_o),
      .cust_qspi_spi_csn_0_o_pad(cust_qspi_spi_csn_0_o),
      .cust_qspi_spi_csn_1_o_pad(),
      .cust_qspi_spi_csn_2_o_pad(),
      .cust_qspi_spi_csn_3_o_pad(),
      .cust_qspi_dat_0_io_pad   (cust_qspi_dat_0_io),
      .cust_qspi_dat_1_io_pad   (),
      .cust_qspi_dat_2_io_pad   (),
      .cust_qspi_dat_3_io_pad   (),
      .cust_psram_sclk_o_pad    (cust_psram_sclk_o),
      .cust_psram_ce_o_pad      (cust_psram_ce_0_o),
      .cust_psram_sio0_io_pad   (cust_psram_sio0_io),
      .cust_psram_sio1_io_pad   (cust_psram_sio1_io),
      .cust_psram_sio2_io_pad   (cust_psram_sio2_io),
      .cust_psram_sio3_io_pad   (cust_psram_sio3_io),
      .cust_spfs_clk_o_pad      (cust_spfs_clk_o),
      .cust_spfs_cs_o_pad       (cust_spfs_cs_o),
      .cust_spfs_mosi_o_pad     (cust_spfs_mosi_o),
      .cust_spfs_miso_i_pad     (cust_spfs_miso_i)
  );
endmodule
