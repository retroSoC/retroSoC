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
  // localparam ser_half_period = 53;
  localparam ser_half_period = 26;
  event ser_sample;

  reg   r_clk;
  reg   r_rst_n;
  wire  s_uart_rx;
  wire  s_flash_csb;
  wire  s_flash_clk;
  wire  s_flash_io0;
  wire  s_flash_io1;
  wire  s_flash_io2;
  wire  s_flash_io3;
  wire  s_i2c_sda_io;
  wire  s_i2c_scl_io;
  wire  s_cust_uart_tx;
  wire  s_cust_uart_rx;
  wire  s_cust_ps2_ps2_clk;
  wire  s_cust_ps2_ps2_dat;

  // always #5 r_clk = (r_clk === 1'b0);  // 100M
  always #10 r_clk = (r_clk === 1'b0);  // 50M

  retrosoc_asic u_retrosoc_asic (
      .xi_i_pad                 (r_clk),
      .xo_o_pad                 (),
      .xclk_i_pad               (r_clk),
      .rst_n_i_pad              (r_rst_n),
      .hk_sdi_i_pad             (1'b1),
      .hk_sdo_o_pad             (),
      .hk_csb_i_pad             (1'b1),
      .hk_sck_i_pad             (1'b0),
      .spi_mst_sdi_i_pad        (1'b0),
      .spi_mst_csb_o_pad        (),
      .spi_mst_sck_o_pad        (),
      .spi_mst_sdo_o_pad        (),
      .flash_csb_o_pad          (s_flash_csb),
      .flash_clk_o_pad          (s_flash_clk),
      .flash_io0_io_pad         (s_flash_io0),
      .flash_io1_io_pad         (s_flash_io1),
      .flash_io2_io_pad         (s_flash_io2),
      .flash_io3_io_pad         (s_flash_io3),
      .uart_tx_o_pad            (s_uart_tx),
      .uart_rx_i_pad            (1'b0),
      .i2c_sda_io_pad           (s_i2c_sda_io),
      .i2c_scl_io_pad           (s_i2c_scl_io),
      .gpio_0_o_pad             (),
      .gpio_1_o_pad             (),
      .gpio_2_o_pad             (),
      .gpio_3_o_pad             (),
      .gpio_4_o_pad             (),
      .gpio_5_o_pad             (),
      .gpio_6_o_pad             (),
      .gpio_7_o_pad             (),
      .gpio_8_o_pad             (),
      .gpio_9_o_pad             (),
      .gpio_10_o_pad            (),
      .gpio_11_o_pad            (),
      .gpio_12_o_pad            (),
      .gpio_13_o_pad            (),
      .gpio_14_o_pad            (),
      .gpio_15_o_pad            (),
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
      .cust_qspi_dat_3_io_pad   ()
  );

  spiflash u_spiflash (
      .csb(s_flash_csb),
      .clk(s_flash_clk),
      .io0(s_flash_io0),
      .io1(s_flash_io1),
      .io2(s_flash_io2),
      .io3(s_flash_io3)
  );

  // Testbench pullups on SDA, SCL lines
  pullup i2c_scl_up (s_i2c_scl_io);
  pullup i2c_sda_up (s_i2c_sda_io);
  i2c_slave u_i2c_slave (
      .scl(s_i2c_scl_io),
      .sda(s_i2c_sda_io)
  );

  rs232 u_rs232 (
      .rs232_rx_i(s_cust_uart_tx),
      .rs232_tx_o(s_cust_uart_rx)
  );

  kdb_model u_kdb_model (
      .ps2_clk_o(s_cust_ps2_ps2_clk),
      .ps2_dat_o(s_cust_ps2_ps2_dat)
  );

  reg [7:0] buffer;
  always begin
    @(negedge s_uart_tx);

    repeat (ser_half_period) @(posedge r_clk);
    ->ser_sample;  // start bit

    repeat (8) begin
      repeat (ser_half_period) @(posedge r_clk);
      repeat (ser_half_period) @(posedge r_clk);
      buffer = {s_uart_tx, buffer[7:1]};
      ->ser_sample;  // data bit
    end

    repeat (ser_half_period) @(posedge r_clk);
    repeat (ser_half_period) @(posedge r_clk);
    ->ser_sample;  // stop bit

    if (buffer < 32 || buffer >= 127)
      // $display("Serial data: %d", buffer);
      $write(
          "%c", buffer
      );
    else
      // $display("Serial data: '%c'", buffer);
      $write(
          "%c", buffer
      );
  end



  initial begin
    r_rst_n = 1;
    #60;
    r_rst_n = 0;
    #100;
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

  initial begin
    if ($test$plusargs("behv_wave")) begin
      $dumpfile("retrosoc_tb.fst");
      $dumpvars(0, retrosoc_tb);
    end else if ($test$plusargs("syn_wave")) begin
      $dumpfile("retrosoc_syn_tb.fst");
      $dumpvars(0, retrosoc_tb);
    end

    repeat (1500) begin
      repeat (5000) @(posedge r_clk);
      // $display("+5000 cycles");
    end
    $finish;
  end
endmodule
