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
  event       ser_sample;

  reg         r_clk;
  reg   [5:0] r_rst_cnt = 0;
  wire  [6:0] s_leds;
  wire s_led1, s_led2, s_led3, s_led4, s_led5, s_led6, s_led7;
  wire s_uart_rx, s_uart_tx;
  wire s_flash_csb;
  wire s_flash_clk;
  wire s_flash_io0;
  wire s_flash_io1;
  wire s_flash_io2;
  wire s_flash_io3;

  // always #5 r_clk = (r_clk === 1'b0);  // 100M
  always #10 r_clk = (r_clk === 1'b0);  // 50M
  wire s_rst_n = &r_rst_cnt;

  always @(posedge r_clk) begin
    r_rst_cnt <= r_rst_cnt + !s_rst_n;
  end

  assign s_leds = {s_led7, s_led6, s_led5, s_led4, s_led3, s_led2, s_led1};
  always @(s_leds) begin
    #1 $display("s_leds: %b", s_leds);
  end

  retrosoc_asic u_retrosoc (
      .clk_i           (r_clk),
      .rst_n_i         (s_rst_n),
      .uart_tx_o_pad   (s_uart_tx),
      .uart_rx_i_pad   (s_uart_rx),
      .flash_csb_o_pad (s_flash_csb),
      .flash_clk_o_pad (s_flash_clk),
      .flash_io0_io_pad(s_flash_io0),
      .flash_io1_io_pad(s_flash_io1),
      .flash_io2_io_pad(s_flash_io2),
      .flash_io3_io_pad(s_flash_io3),
      .led1_o_pad      (s_led1),
      .led2_o_pad      (s_led2),
      .led3_o_pad      (s_led3),
      .led4_o_pad      (s_led4),
      .led5_o_pad      (s_led5),
      .led6_o_pad      (s_led6),
      .led7_o_pad      (s_led7)
  );

  spiflash u_spiflash (
      .csb(s_flash_csb),
      .clk(s_flash_clk),
      .io0(s_flash_io0),
      .io1(s_flash_io1),
      .io2(s_flash_io2),
      .io3(s_flash_io3)
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
    if ($test$plusargs("behv_wave")) begin
      $dumpfile("retrosoc_tb.vcd");
      $dumpvars(0, retrosoc_tb);
    end else if ($test$plusargs("syn_wave")) begin
      $dumpfile("retrosoc_syn_tb.vcd");
      $dumpvars(0, retrosoc_tb);
    end

    repeat (100) begin
      repeat (5000) @(posedge r_clk);
      // $display("+5000 cycles");
    end
    // $finish;
  end
endmodule
