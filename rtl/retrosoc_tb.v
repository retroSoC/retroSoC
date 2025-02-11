/*
 *  PicoSoC - A simple example SoC using PicoRV32
 *
 *  Copyright (C) 2017  Claire Xenia Wolf <claire@yosyshq.com>
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

module retrosoc_tb;
  localparam CPU_FREQ = 50;  // MHz

  reg  r_clk;
  reg  r_rst_n;
  wire s_uart_rx;
  wire s_flash_csb;
  wire s_flash_clk;
  wire s_flash_io0;
  wire s_flash_io1;
  wire s_flash_io2;
  wire s_flash_io3;
  // wire s_i2c_sda_io;
  // wire s_i2c_scl_io;
  wire s_cust_uart_tx;
  wire s_cust_uart_rx;
  wire s_cust_ps2_ps2_clk;
  wire s_cust_ps2_ps2_dat;
  wire s_cust_psram_sclk;
  wire s_cust_psram_ce_0;
  wire s_cust_psram_ce_1;
  wire s_cust_psram_ce_2;
  wire s_cust_psram_ce_3;
  wire s_cust_psram_sio0;
  wire s_cust_psram_sio1;
  wire s_cust_psram_sio2;
  wire s_cust_psram_sio3;
  wire s_cust_spfs_clk_o;
  wire s_cust_spfs_cs_o;
  wire s_cust_spfs_mosi_o;
  wire s_cust_spfs_miso_i;

  always #(1000 / CPU_FREQ / 2) r_clk = (r_clk === 1'b0);

  retrosoc_asic u_retrosoc_asic (
      .xi_i_pad                 (r_clk),
      .xo_o_pad                 (),
      .extclk_i_pad             (r_clk),
      .clkbypass_i_pad          (1'b1),
      .rst_n_i_pad              (r_rst_n),
      .hk_sdi_i_pad             (1'b1),
      .hk_sdo_o_pad             (),
      .hk_csb_i_pad             (1'b1),
      .hk_sck_i_pad             (1'b0),
      .flash_csb_o_pad          (s_flash_csb),
      .flash_clk_o_pad          (s_flash_clk),
      .flash_io0_io_pad         (s_flash_io0),
      .flash_io1_io_pad         (s_flash_io1),
      .flash_io2_io_pad         (s_flash_io2),
      .flash_io3_io_pad         (s_flash_io3),
      .uart_tx_o_pad            (s_uart_tx),
      .uart_rx_i_pad            (1'b0),
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
      .irq_pin_i_pad            (1'b0),
      .cust_uart_tx_o_pad       (s_cust_uart_tx),
      .cust_uart_rx_i_pad       (s_cust_uart_rx),
      .cust_ps2_ps2_clk_i_pad   (s_cust_ps2_ps2_clk),
      .cust_ps2_ps2_dat_i_pad   (s_cust_ps2_ps2_dat),
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
      .cust_psram_ce_0_o_pad    (s_cust_psram_ce_0),
      .cust_psram_ce_1_o_pad    (s_cust_psram_ce_1),
      .cust_psram_ce_2_o_pad    (s_cust_psram_ce_2),
      .cust_psram_ce_3_o_pad    (s_cust_psram_ce_3),
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

  // Testbench pullups on SDA, SCL lines
  // pullup i2c_scl_up (s_i2c_scl_io);
  // pullup i2c_sda_up (s_i2c_sda_io);
  // i2c_slave u_i2c_slave (
  //     .scl(s_i2c_scl_io),
  //     .sda(s_i2c_sda_io)
  // );

  rs232 u_rs232_0 (
      .rs232_rx_i(s_uart_tx),
      .rs232_tx_o(s_uart_rx)
  );

  rs232 u_rs232_1 (
      .rs232_rx_i(s_cust_uart_tx),
      .rs232_tx_o(s_cust_uart_rx)
  );

  kdb_model u_kdb_model (
      .ps2_clk_o(s_cust_ps2_ps2_clk),
      .ps2_dat_o(s_cust_ps2_ps2_dat)
  );

  psram_model u_psram_model0 (
      .sck (s_cust_psram_sclk),
      .dio ({s_cust_psram_sio3, s_cust_psram_sio2, s_cust_psram_sio1, s_cust_psram_sio0}),
      .ce_n(s_cust_psram_ce_0)
  );
  psram_model u_psram_model1 (
      .sck (s_cust_psram_sclk),
      .dio ({s_cust_psram_sio3, s_cust_psram_sio2, s_cust_psram_sio1, s_cust_psram_sio0}),
      .ce_n(s_cust_psram_ce_1)
  );
  psram_model u_psram_model2 (
      .sck (s_cust_psram_sclk),
      .dio ({s_cust_psram_sio3, s_cust_psram_sio2, s_cust_psram_sio1, s_cust_psram_sio0}),
      .ce_n(s_cust_psram_ce_2)
  );
  psram_model u_psram_model3 (
      .sck (s_cust_psram_sclk),
      .dio ({s_cust_psram_sio3, s_cust_psram_sio2, s_cust_psram_sio1, s_cust_psram_sio0}),
      .ce_n(s_cust_psram_ce_3)
  );

  initial begin
    r_rst_n = 1;
    #43;
    r_rst_n = 0;
    #170701;
    r_rst_n = 1;
  end

  initial begin : KDB_MODEL_BLOCK
    integer i;
    #1000;
    while (1) begin
      #1000;
      for (i = 0; i < 26; i = i + 1) begin
        u_kdb_model.send_code(i + 8'd65);
        #500;
      end
    end
  end

  initial begin : UART_RX_BLOCK
    integer i;
    #1000;
    while (1) begin
      #1000;
      for (i = 0; i < 26; i = i + 1) begin
        u_rs232_1.send(i + 8'd66);
        #500;
      end
    end
  end


  initial begin
    if ($test$plusargs("behv_wave")) begin
      $dumpfile("retrosoc_tb.fst");
      $dumpvars(0, retrosoc_tb);
      repeat (200) begin
        repeat (5000) @(posedge r_clk);
      end
      $finish;
    end else if ($test$plusargs("syn_wave")) begin
      $dumpfile("retrosoc_syn_tb.fst");
      $dumpvars(0, retrosoc_tb);
      repeat (1500) begin
        repeat (5000) @(posedge r_clk);
      end
      $finish;
    end

    // repeat (1500) begin
    // repeat (5000) @(posedge r_clk);
    // $display("+5000 cycles");
    // end
    // $finish;
  end
endmodule
