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

module retrosoc_tb_tiny;
  localparam real EXT_CPU_FREQ = 64.0;

  reg  r_ext_clk;
  reg  r_rst_n;
  wire s_uart_rx;

  wire s_cust_psram_sclk;
  wire s_cust_psram_ce;
  wire s_cust_psram_sio0;
  wire s_cust_psram_sio1;
  wire s_cust_psram_sio2;
  wire s_cust_psram_sio3;
  wire s_cust_spfs_clk_o;
  wire s_cust_spfs_cs_o;
  wire s_cust_spfs_mosi_o;
  wire s_cust_spfs_miso_i;

  always #(1000 / EXT_CPU_FREQ / 2) r_ext_clk = (r_ext_clk === 1'b0);

  retrosoc_asic_tiny u_retrosoc_asic_tiny (
      .extclk_i_pad             (r_ext_clk),
      .ext_rst_n_i_pad          (r_rst_n),
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
      .cust_psram_ce_o_pad      (s_cust_psram_ce),
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

  rs232 u_rs232_0 (
      .rs232_rx_i(s_uart_tx),
      .rs232_tx_o(s_uart_rx)
  );

  psram_model u_psram_model (
      .sck (s_cust_psram_sclk),
      .dio ({s_cust_psram_sio3, s_cust_psram_sio2, s_cust_psram_sio1, s_cust_psram_sio0}),
      .ce_n(s_cust_psram_ce)
  );

  initial begin
    r_rst_n = 1;
    #43;
    r_rst_n = 0;
    #170701;
    r_rst_n = 1;
  end

  initial begin
    if ($test$plusargs("behv_wave")) begin
      $display("gen behv sim wave");
      if ($test$plusargs("sim_iver")) begin
        $dumpfile("retrosoc_tb_tiny.fst");
        $dumpvars(0, retrosoc_tb_tiny);
      end else begin
        // $fsdbDumpfile("retrosoc_tb.fsdb");
        // $fsdbDumpvars(0);
      end
      repeat (200) begin
        repeat (5000) @(posedge r_ext_clk);
      end
      $finish;
    end else if ($test$plusargs("syn_wave")) begin
      $display("gen syn sim wave");
      if ($test$plusargs("sim_iver")) begin
        $display("gen retrosoc_syn_tb_tiny.fst");
        $dumpfile("retrosoc_syn_tb_tiny.fst");
        $dumpvars(0, retrosoc_tb_tiny);
      end else begin
        // $fsdbDumpfile("retrosoc_syn_tb.fsdb");
        // $fsdbDumpvars(0);
      end
      repeat (10) begin
        $display("hello");
        repeat (100) @(posedge r_ext_clk);
      end
      $finish;
    end

    // repeat (1500) begin
    // repeat (5000) @(posedge r_ext_clk);
    // $display("+5000 cycles");
    // end
    // $finish;
  end
endmodule
