/*
 *  PicoSoC - A simple example SoC using PicoRV32
 *
 *  Copyright (C) 2017  Claire Xenia Wolf <claire@yosyshq.com>
 *  Copyright (C) 2025-2026  Yuchi Miao <miaoyuchi@ict.ac.cn>
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

module retrosoc_top (
    input  wire       ext_clk_i,
    input  wire       rst_n_i,
    input  wire       jtag_tck_i,
    input  wire       jtag_tms_i,
    input  wire       jtag_tdi_i,
    input  wire       jtag_trst_n_i,
    output wire       jtag_tdo_o,
    output wire       test_done_o,
    output wire       test_pass_o,
    output wire [7:0] test_code_o
);

  wire        s_clk;
  wire        s_rst_n;
  wire        s_psram_sck;
  wire        s_psram_nss0;
  wire        s_psram_dat0;
  wire        s_psram_dat1;
  wire        s_psram_dat2;
  wire        s_psram_dat3;
  wire        s_xpi_nss0_o;
  wire        s_xpi_sck_o;
  wire        s_xpi_dat0_io;
  wire        s_xpi_dat1_io;
  wire        s_xpi_dat2_io;
  wire        s_xpi_dat3_io;
  wire        s_sdram_clk;
  wire        s_sdram_cke;
  wire        s_sdram_cs_n;
  wire        s_sdram_ras_n;
  wire        s_sdram_cas_n;
  wire        s_sdram_we_n;
  wire [ 1:0] s_sdram_ba;
  wire [12:0] s_sdram_addr;
  wire [ 1:0] s_sdram_dqm;
  wire [15:0] s_sdram_dq;
  wire        s_jtag_tck;
  wire        s_jtag_tms;
  wire        s_jtag_tdi;
  wire        s_jtag_trst_n;
  wire        s_jtag_tdo;

  assign s_clk         = ext_clk_i;
  assign s_rst_n       = rst_n_i;
  assign s_jtag_tck    = jtag_tck_i;
  assign s_jtag_tms    = jtag_tms_i;
  assign s_jtag_tdi    = jtag_tdi_i;
  assign s_jtag_trst_n = jtag_trst_n_i;
  assign jtag_tdo_o    = s_jtag_tdo;
  assign test_done_o   = u_retrosoc_asic.s_test_done;
  assign test_pass_o   = u_retrosoc_asic.s_test_pass;
  assign test_code_o   = u_retrosoc_asic.s_test_code;
  retrosoc_asic u_retrosoc_asic (
      `include "retrosoc_asic_verilator_bindings.svh"
  );

  QSPIFlash u_QSPIFlash (
      .clk(s_xpi_sck_o),
      .cs (s_xpi_nss0_o),
      .io0(s_xpi_dat0_io),
      .io1(s_xpi_dat1_io),
      .io2(s_xpi_dat2_io),
      .io3(s_xpi_dat3_io)
  );

  ESP_PSRAM64H u_ESP_PSRAM64H (
      .sclk(s_psram_sck),
      .csn (s_psram_nss0),
      .sio ({s_psram_dat3, s_psram_dat2, s_psram_dat1, s_psram_dat0})
  );

  sdram_verilator_model u_sdram_verilator_model (
      .clk_i  (s_sdram_clk),
      .cke_i  (s_sdram_cke),
      .cs_n_i (s_sdram_cs_n),
      .ras_n_i(s_sdram_ras_n),
      .cas_n_i(s_sdram_cas_n),
      .we_n_i (s_sdram_we_n),
      .ba_i   (s_sdram_ba),
      .addr_i (s_sdram_addr),
      .dqm_i  (s_sdram_dqm),
      .dq_io  (s_sdram_dq)
  );

endmodule
