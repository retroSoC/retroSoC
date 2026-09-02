`timescale 1ns / 1ps

module retrosoc_top (
    input  clk_i,
    inout  rst_n_i,
    inout  ps2_clk_i,
    inout  ps2_dat_i,
    output ws2812_dat_o,
    inout  i2c_scl_io,
    inout  i2c_sda_io,
    output pwm_2_o,
    output spisd_sck_o,
    output spisd_nss_o,
    output spisd_mosi_o,
    inout  spisd_miso_i,
    output i2s_mclk_o,
    output i2s_sclk_o,
    output i2s_lrck_o,
    output i2s_dacdat_o,
    inout  i2s_adcdat_i,
    output psram_sck_o,
    output psram_nss0_o,
    inout  psram_dat0_io,
    inout  psram_dat1_io,
    inout  psram_dat2_io,
    inout  psram_dat3_io,
    inout  gpio_io30,
    output uart0_tx_o,
    inout  uart0_rx_i,
    output uart1_tx_o,
    inout  uart1_rx_i,
    output xpi_sck_o,
    output xpi_nss0_o,
    inout  xpi_dat0_io,
    inout  xpi_dat1_io,
    inout  xpi_dat2_io,
    inout  xpi_dat3_io,
    output sdram_clk_o,
    output sdram_cke_o,
    output sdram_cs_n_o,
    output sdram_ras_n_o,
    output sdram_cas_n_o,
    output sdram_we_n_o,
    output sdram_ba0_o,
    output sdram_ba1_o,
    output sdram_addr0_o,
    output sdram_addr1_o,
    output sdram_addr2_o,
    output sdram_addr3_o,
    output sdram_addr4_o,
    output sdram_addr5_o,
    output sdram_addr6_o,
    output sdram_addr7_o,
    output sdram_addr8_o,
    output sdram_addr9_o,
    output sdram_addr10_o,
    output sdram_addr11_o,
    output sdram_addr12_o,
    output sdram_dqm0_o,
    output sdram_dqm1_o,
    inout  sdram_dq0_io,
    inout  sdram_dq1_io,
    inout  sdram_dq2_io,
    inout  sdram_dq3_io,
    inout  sdram_dq4_io,
    inout  sdram_dq5_io,
    inout  sdram_dq6_io,
    inout  sdram_dq7_io,
    inout  sdram_dq8_io,
    inout  sdram_dq9_io,
    inout  sdram_dq10_io,
    inout  sdram_dq11_io,
    inout  sdram_dq12_io,
    inout  sdram_dq13_io,
    inout  sdram_dq14_io,
    inout  sdram_dq15_io
);

  wire s_sys_clk;
  wire s_ref24_clk;
  wire s_aud_clk;
  wire s_jtag_tck;
  wire s_jtag_tms;
  wire s_jtag_tdi;
  wire s_jtag_trst_n;
  wire s_usb2_ulpi_clk;
  tri0 s_usb2_ulpi_dir;
  tri0 s_usb2_ulpi_nxt;
  tri0 [7:0] s_usb2_ulpi_data;
  wire s_usb2_ulpi_stp;
  wire s_usb2_ulpi_reset_n;
  clk_wiz_0 u_clk_wiz_0 (
      .clk_in1 (clk_i),
      .clk_out1(s_sys_clk),
      .clk_out2(s_aud_clk)
  );

  assign s_jtag_tck    = 1'b0;
  assign s_jtag_tms    = 1'b0;
  assign s_jtag_tdi    = 1'b0;
  assign s_jtag_trst_n = 1'b0;
  assign s_usb2_ulpi_clk = s_sys_clk;
  assign s_ref24_clk = s_sys_clk;

  retrosoc_asic u_retrosoc (
      `include "retrosoc_asic_fpga_mini_bindings.svh"
  );

endmodule
