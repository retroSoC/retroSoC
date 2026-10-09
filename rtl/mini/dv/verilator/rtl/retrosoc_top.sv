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
    input  wire        ext_clk_i,
    input  wire        ref24_clk_i,
    input  wire        rst_n_i,
    input  wire        jtag_tck_i,
    input  wire        jtag_tms_i,
    input  wire        jtag_tdi_i,
    input  wire        jtag_trst_n_i,
    output wire        jtag_tdo_o,
    output wire        test_done_o,
    output wire        test_pass_o,
    output wire [ 7:0] test_code_o,
    output wire        diag_aon_rst_n_o,
    output wire        diag_lp_rst_n_o,
    output wire        diag_pclk_rst_n_o,
    output wire        diag_hp_rst_n_o,
    output wire [31:0] diag_mgmt_araddr_o,
    output wire        diag_mgmt_arvalid_o,
    output wire        diag_mgmt_arready_o,
    output wire        diag_xpi_arvalid_o,
    output wire        diag_xpi_arready_o,
    output wire        diag_xpi_rvalid_o,
    output wire        diag_xpi_rready_o,
    output wire        sdio1_clk_o,
    inout  wire        sdio1_cmd_io,
    inout  wire        sdio1_dat0_io,
    inout  wire        sdio1_dat1_io,
    inout  wire        sdio1_dat2_io,
    inout  wire        sdio1_dat3_io
);

  wire        s_clk;
  wire        s_ref24_clk;
  wire        s_rst_n;
  wire        s_psram_sck;
  wire        s_psram_nss0;
  wire        s_psram_nss1;
  wire        s_psram_nss2;
  wire        s_psram_nss3;
  tri1        s_psram_dat0;
  tri1        s_psram_dat1;
  tri1        s_psram_dat2;
  tri1        s_psram_dat3;
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
  wire        s_uart1_tx;
  wire        s_uart1_rx;
  wire        s_usb2_ulpi_clk;
  tri0        s_usb2_ulpi_dir;
  tri0        s_usb2_ulpi_nxt;
  // This wrapper intentionally has no external ULPI PHY model.
  // verilator lint_off UNUSEDSIGNAL
  tri0 [ 7:0] s_usb2_ulpi_data;
  wire        s_usb2_ulpi_stp;
  wire        s_usb2_ulpi_reset_n;
  // verilator lint_on UNUSEDSIGNAL

  assign s_clk               = ext_clk_i;
  assign s_ref24_clk         = ref24_clk_i;
  assign s_rst_n             = rst_n_i;
  assign s_jtag_tck          = jtag_tck_i;
  assign s_jtag_tms          = jtag_tms_i;
  assign s_jtag_tdi          = jtag_tdi_i;
  assign s_jtag_trst_n       = jtag_trst_n_i;
  assign s_uart1_rx          = s_uart1_tx;
  assign jtag_tdo_o          = s_jtag_tdo;
  assign test_done_o         = u_retrosoc_asic.s_test_done;
  assign test_pass_o         = u_retrosoc_asic.s_test_pass;
  assign test_code_o         = u_retrosoc_asic.s_test_code;
  assign diag_aon_rst_n_o    = u_retrosoc_asic.s_aon_rst_n;
  assign diag_lp_rst_n_o     = u_retrosoc_asic.s_sys_rst_n;
  assign diag_pclk_rst_n_o   = u_retrosoc_asic.s_pclk_rst_n;
  assign diag_hp_rst_n_o     = u_retrosoc_asic.s_hp_rst_n;
  assign diag_mgmt_araddr_o  = u_retrosoc_asic.u_retrosoc.u_mgmt_axi4_if.araddr;
  assign diag_mgmt_arvalid_o = u_retrosoc_asic.u_retrosoc.u_mgmt_axi4_if.arvalid;
  assign diag_mgmt_arready_o = u_retrosoc_asic.u_retrosoc.u_mgmt_axi4_if.arready;
  assign diag_xpi_arvalid_o  = u_retrosoc_asic.u_retrosoc.u_xpi_axi4_if.arvalid;
  assign diag_xpi_arready_o  = u_retrosoc_asic.u_retrosoc.u_xpi_axi4_if.arready;
  assign diag_xpi_rvalid_o   = u_retrosoc_asic.u_retrosoc.u_xpi_axi4_if.rvalid;
  assign diag_xpi_rready_o   = u_retrosoc_asic.u_retrosoc.u_xpi_axi4_if.rready;
  assign s_usb2_ulpi_clk     = s_clk;
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

  ESP_PSRAM64H #(
      .ID            (0),
      .POWER_UP_CHECK(0),
      .TIMING_CHECK  (0)
  ) u_ESP_PSRAM64H_0 (
      .sclk(s_psram_sck),
      .csn (s_psram_nss0),
      .sio ({s_psram_dat3, s_psram_dat2, s_psram_dat1, s_psram_dat0})
  );

  ESP_PSRAM64H #(
      .ID            (1),
      .POWER_UP_CHECK(0),
      .TIMING_CHECK  (0)
  ) u_ESP_PSRAM64H_1 (
      .sclk(s_psram_sck),
      .csn (s_psram_nss1),
      .sio ({s_psram_dat3, s_psram_dat2, s_psram_dat1, s_psram_dat0})
  );

  ESP_PSRAM64H #(
      .ID            (2),
      .POWER_UP_CHECK(0),
      .TIMING_CHECK  (0)
  ) u_ESP_PSRAM64H_2 (
      .sclk(s_psram_sck),
      .csn (s_psram_nss2),
      .sio ({s_psram_dat3, s_psram_dat2, s_psram_dat1, s_psram_dat0})
  );

  ESP_PSRAM64H #(
      .ID            (3),
      .POWER_UP_CHECK(0),
      .TIMING_CHECK  (0)
  ) u_ESP_PSRAM64H_3 (
      .sclk(s_psram_sck),
      .csn (s_psram_nss3),
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

`ifdef RETROSOC_WS2812_P3_OBSERVE
  // Approved option A: actual Mini PIO frames and recovery, never DMA latency.
  `define _P3_PERIPH u_retrosoc_asic.u_retrosoc.u_apb4_periph
  `define _P3_WS `_P3_PERIPH.u_apb4_ws2812
  int unsigned        s_p3_frames = 0;
  int unsigned        s_p3_done = 0;
  int unsigned        s_p3_underflows = 0;
  int unsigned        s_p3_aborts = 0;
  int unsigned        s_p3_dma_starts = 0;
  int unsigned        s_p3_word = 0;
  int unsigned        s_p3_bit = 0;
  int unsigned        s_p3_bit_cycle = 0;
  int unsigned        s_p3_reset_cycles = 0;
  int unsigned        s_p3_expected_words;
  logic        [23:0] s_p3_pixel;
  logic               s_p3_busy_previous = 1'b0;
  logic               s_p3_expected_high;
  // Sample settled outputs halfway between active edges. The model has no
  // timing delays and the production waveform is never driven by this observer.
  always @(negedge u_retrosoc_asic.u_retrosoc.clk_pclk_i) begin
    if (`_P3_WS.s_busy && !s_p3_busy_previous) begin
      s_p3_frames       = s_p3_frames + 1;
      s_p3_word         = 0;
      s_p3_bit          = 0;
      s_p3_bit_cycle    = 0;
      s_p3_reset_cycles = 0;
    end
    if (`_P3_WS.s_underflow) s_p3_underflows = s_p3_underflows + 1;
    if (`_P3_WS.s_aborted) s_p3_aborts = s_p3_aborts + 1;
    if (`_P3_PERIPH.u_apb4_dma.s_start != '0) s_p3_dma_starts = s_p3_dma_starts + 1;
    if (`_P3_WS.s_busy && !`_P3_WS.s_reset_active && s_p3_frames <= 4) begin
      s_p3_pixel         = 24'(s_p3_word * 32'h010203);
      s_p3_expected_high = s_p3_bit_cycle < (s_p3_pixel[23-s_p3_bit] ? 17 : 8);
      if (`_P3_WS.s_dat !== s_p3_expected_high)
        $fatal(
            1,
            "SIM_TEST_FAIL Mini PIO waveform frame=%0d word=%0d bit=%0d cycle=%0d",
            s_p3_frames,
            s_p3_word,
            s_p3_bit,
            s_p3_bit_cycle
        );
      s_p3_bit_cycle = s_p3_bit_cycle + 1;
      if (s_p3_bit_cycle == 30) begin
        s_p3_bit_cycle = 0;
        s_p3_bit       = s_p3_bit + 1;
        if (s_p3_bit == 24) begin
          s_p3_bit  = 0;
          s_p3_word = s_p3_word + 1;
        end
      end
    end
    if (`_P3_WS.s_reset_active) begin
      if (`_P3_WS.s_dat !== 1'b0) $fatal(1, "SIM_TEST_FAIL Mini PIO reset-low");
      s_p3_reset_cycles = s_p3_reset_cycles + 1;
    end
    if (!`_P3_WS.s_busy && s_p3_busy_previous) begin
      if (s_p3_reset_cycles < 7200) $fatal(1, "SIM_TEST_FAIL Mini PIO short reset interval");
      if (s_p3_frames <= 4) begin
        case (s_p3_frames)
          1:       s_p3_expected_words = 4;
          2:       s_p3_expected_words = 16;
          3:       s_p3_expected_words = 33;
          default: s_p3_expected_words = 65;
        endcase
        if (s_p3_word != s_p3_expected_words || s_p3_bit != 0 || s_p3_bit_cycle != 0)
          $fatal(1, "SIM_TEST_FAIL Mini PIO frame length");
        s_p3_done = s_p3_done + 1;
      end
    end
    s_p3_busy_previous = `_P3_WS.s_busy;
  end
  // The C++ harness calls final() immediately on TEST_STATUS.
  final begin
    if (test_done_o && test_pass_o) begin
      if (s_p3_frames != 6 || s_p3_done != 4 || s_p3_underflows != 1 ||
          s_p3_aborts < 1 || s_p3_dma_starts != 0)
        $fatal(1, "SIM_TEST_FAIL incomplete Mini PIO observations");
      $display(
          "WS2812_P3_MINI_PIO_OBSERVER frames=%0d completed=%0d underflows=%0d aborts=%0d dma_starts=%0d",
          s_p3_frames, s_p3_done, s_p3_underflows, s_p3_aborts, s_p3_dma_starts);
    end
  end
  `undef _P3_WS
  `undef _P3_PERIPH
`endif
endmodule
