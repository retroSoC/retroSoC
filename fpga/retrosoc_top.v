`timescale 1ns / 1ps

module retrosoc_top (
    input  clk_i,
    input  rst_n_i,
    input  uart_rx_i,
    output uart_tx_o,
    inout  gpio_io0,
    inout  gpio_io1,
    inout  gpio_io2,
    inout  i2c_scl_io,
    inout  i2c_sda_io,
    output cust_uart_tx_o,
    input  cust_uart_rx_i,
    output cust_pwm_pwm_o,
    input  cust_ps2_ps2_clk_i,
    input  cust_ps2_ps2_dat_i,
    output cust_qspi_spi_clk_o,
    output cust_qspi_spi_csn_0_o,
    inout  cust_qspi_dat_0_io,
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

  retrosoc_asic u_retrosoc (
      .xi_i_pad                 (s_sys_clk),
      .xo_o_pad                 (),
      .extclk_i_pad             (s_sys_clk),
      .clkbypass_i_pad          (1'b1),
      .rst_n_i_pad              (rst_n_i),
      // HOUSEKEEPING SPI
      .hk_sdi_i_pad             (1'b0),
      .hk_sdo_o_pad             (),
      .hk_csb_i_pad             (1'b0),
      .hk_sck_i_pad             (1'b0),
      // SPI MST
      .spi_mst_sdi_i_pad        (1'b0),
      .spi_mst_csb_o_pad        (),
      .spi_mst_sck_o_pad        (),
      .spi_mst_sdo_o_pad        (),
      // SPI FLASH
      .flash_csb_o_pad          (),
      .flash_clk_o_pad          (),
      .flash_io0_io_pad         (),
      .flash_io1_io_pad         (),
      .flash_io2_io_pad         (),
      .flash_io3_io_pad         (),
      // UART
      .uart_tx_o_pad            (uart_tx_o),
      .uart_rx_i_pad            (uart_rx_i),
      // I2C
      .i2c_sda_io_pad           (i2c_scl_io),
      .i2c_scl_io_pad           (i2c_sda_io),
      // GPIO
      .gpio_0_io_pad            (gpio_io0),
      .gpio_1_io_pad            (gpio_io1),
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
      // IRQ
      .irq_pin_i_pad            (1'b0),
      // CUST
      .cust_uart_tx_o_pad       (cust_uart_tx_o),
      .cust_uart_rx_i_pad       (cust_uart_rx_i),
      .cust_pwm_pwm_0_o_pad     (cust_pwm_pwm_o),
      .cust_pwm_pwm_1_o_pad     (),
      .cust_pwm_pwm_2_o_pad     (),
      .cust_pwm_pwm_3_o_pad     (),
      .cust_ps2_ps2_clk_i_pad   (cust_ps2_ps2_clk_i),
      .cust_ps2_ps2_dat_i_pad   (cust_ps2_ps2_dat_i),
      .cust_qspi_spi_clk_o_pad  (cust_qspi_spi_clk_o),
      .cust_qspi_spi_csn_0_o_pad(cust_qspi_spi_csn_0_o),
      .cust_qspi_spi_csn_1_o_pad(),
      .cust_qspi_spi_csn_2_o_pad(),
      .cust_qspi_spi_csn_3_o_pad(),
      .cust_qspi_dat_0_io_pad   (cust_qspi_dat_0_io),
      .cust_qspi_dat_1_io_pad   (),
      .cust_qspi_dat_2_io_pad   (),
      .cust_qspi_dat_3_io_pad   (),
      .cust_psram_sclk_o_pad    (),
      .cust_psram_ce_0_o_pad    (),
      .cust_psram_ce_1_o_pad    (),
      .cust_psram_ce_2_o_pad    (),
      .cust_psram_ce_3_o_pad    (),
      .cust_psram_sio0_io_pad   (),
      .cust_psram_sio1_io_pad   (),
      .cust_psram_sio2_io_pad   (),
      .cust_psram_sio3_io_pad   (),
      .cust_spfs_clk_o_pad      (cust_spfs_clk_o),
      .cust_spfs_cs_o_pad       (cust_spfs_cs_o),
      .cust_spfs_mosi_o_pad     (cust_spfs_mosi_o),
      .cust_spfs_miso_i_pad     (cust_spfs_miso_i)
  );
endmodule
