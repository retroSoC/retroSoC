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

`ifdef PICOSOC_V
// `error "retrosoc.v must be read before picosoc.v!"
`endif

`define PICOSOC_MEM spram_model

module retrosoc #(
    // We limit the amount of memory in simulation
    // in order to avoid reduce simulation time
    // required for intialization of RAM
    parameter integer MEM_WORDS = 256
) (
    input  clk_i,
    input  rst_n_i,
    output uart_tx_o,
    input  uart_rx_i,
    output led1_o,
    output led2_o,
    output led3_o,
    output led4_o,
    output led5_o,
    output led6_o,
    output led7_o,
    output flash_csb_o,
    output flash_clk_o,
    inout  flash_io0_io,
    inout  flash_io1_io,
    inout  flash_io2_io,
    inout  flash_io3_io
);

  wire s_flash_io0_oe, s_flash_io0_do, s_flash_io0_di;
  wire s_flash_io1_oe, s_flash_io1_do, s_flash_io1_di;
  wire s_flash_io2_oe, s_flash_io2_do, s_flash_io2_di;
  wire s_flash_io3_oe, s_flash_io3_do, s_flash_io3_di;
  wire        s_iomem_valid;
  reg         r_iomem_ready;
  wire [ 3:0] s_iomem_wstrb;
  wire [31:0] s_iomem_addr;
  wire [31:0] s_iomem_wdata;
  reg  [31:0] r_iomem_rdata;
  wire [ 7:0] s_leds;
  reg  [31:0] r_gpio;

  assign flash_io0_io   = s_flash_io0_oe ? s_flash_io0_do : 1'bz;
  assign s_flash_io0_di = flash_io0_io;
  assign flash_io1_io   = s_flash_io1_oe ? s_flash_io1_do : 1'bz;
  assign s_flash_io1_di = flash_io1_io;
  assign flash_io2_io   = s_flash_io2_oe ? s_flash_io2_do : 1'bz;
  assign s_flash_io2_di = flash_io2_io;
  assign flash_io3_io   = s_flash_io3_oe ? s_flash_io3_do : 1'bz;
  assign s_flash_io3_di = flash_io3_io;

  assign led1_o         = s_leds[1];
  assign led2_o         = s_leds[2];
  assign led3_o         = s_leds[3];
  assign led4_o         = s_leds[4];
  assign led5_o         = s_leds[5];
  assign led6_o         = s_leds[6];
  assign led7_o         = s_leds[7];
  assign s_leds         = r_gpio;

  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      r_gpio <= 0;
    end else begin
      r_iomem_ready <= 0;
      if (s_iomem_valid && !r_iomem_ready && s_iomem_addr[31:24] == 8'h03) begin
        r_iomem_ready <= 1;
        r_iomem_rdata <= r_gpio;
        if (s_iomem_wstrb[0]) r_gpio[7:0] <= s_iomem_wdata[7:0];
        if (s_iomem_wstrb[1]) r_gpio[15:8] <= s_iomem_wdata[15:8];
        if (s_iomem_wstrb[2]) r_gpio[23:16] <= s_iomem_wdata[23:16];
        if (s_iomem_wstrb[3]) r_gpio[31:24] <= s_iomem_wdata[31:24];
      end
    end
  end

  picosoc #(
      .MEM_WORDS      (MEM_WORDS),
      .BARREL_SHIFTER (1),
      .COMPRESSED_ISA (1),
      .ENABLE_FAST_MUL(1),
      .ENABLE_DIV     (1)
  ) u_picosoc (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .uart_tx_o     (uart_tx_o),
      .uart_rx_i     (uart_rx_i),
      .flash_csb_o   (flash_csb_o),
      .flash_clk_o   (flash_clk_o),
      .flash_io0_oe_o(s_flash_io0_oe),
      .flash_io1_oe_o(s_flash_io1_oe),
      .flash_io2_oe_o(s_flash_io2_oe),
      .flash_io3_oe_o(s_flash_io3_oe),
      .flash_io0_do_o(s_flash_io0_do),
      .flash_io1_do_o(s_flash_io1_do),
      .flash_io2_do_o(s_flash_io2_do),
      .flash_io3_do_o(s_flash_io3_do),
      .flash_io0_di_i(s_flash_io0_di),
      .flash_io1_di_i(s_flash_io1_di),
      .flash_io2_di_i(s_flash_io2_di),
      .flash_io3_di_i(s_flash_io3_di),
      .iomem_valid_o (s_iomem_valid),
      .iomem_ready_i (r_iomem_ready),
      .iomem_wstrb_o (s_iomem_wstrb),
      .iomem_addr_o  (s_iomem_addr),
      .iomem_wdata_o (s_iomem_wdata),
      .iomem_rdata_i (r_iomem_rdata)
  );
endmodule
