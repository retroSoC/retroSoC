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

`define PICOSOC_MEM ice40up5k_spram

module retrosoc #(
    parameter integer MEM_WORDS = 32768
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
    inout  flash_io0,
    inout  flash_io1,
    inout  flash_io2,
    inout  flash_io3
);

  wire flash_io0_oe, flash_io0_do, flash_io0_di;
  wire flash_io1_oe, flash_io1_do, flash_io1_di;
  wire flash_io2_oe, flash_io2_do, flash_io2_di;
  wire flash_io3_oe, flash_io3_do, flash_io3_di;
  wire        iomem_valid;
  reg         iomem_ready;
  wire [ 3:0] iomem_wstrb;
  wire [31:0] iomem_addr;
  wire [31:0] iomem_wdata;
  reg  [31:0] iomem_rdata;
  wire [ 7:0] leds;
  reg  [31:0] gpio;

  assign flash_io0    = flash_io0_oe ? flash_io0_do : 1'bz;
  assign flash_io0_di = flash_io0;
  assign flash_io1    = flash_io1_oe ? flash_io1_do : 1'bz;
  assign flash_io1_di = flash_io1;
  assign flash_io2    = flash_io2_oe ? flash_io2_do : 1'bz;
  assign flash_io2_di = flash_io2;
  assign flash_io3    = flash_io3_oe ? flash_io3_do : 1'bz;
  assign flash_io3_di = flash_io3;

  assign led1_o       = leds[1];
  assign led2_o       = leds[2];
  assign led3_o       = leds[3];
  assign led4_o       = leds[4];
  assign led5_o       = leds[5];
  assign led6_o       = leds[6];
  assign led7_o       = leds[7];
  assign leds         = gpio;

  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      gpio <= 0;
    end else begin
      iomem_ready <= 0;
      if (iomem_valid && !iomem_ready && iomem_addr[31:24] == 8'h03) begin
        iomem_ready <= 1;
        iomem_rdata <= gpio;
        if (iomem_wstrb[0]) gpio[7:0] <= iomem_wdata[7:0];
        if (iomem_wstrb[1]) gpio[15:8] <= iomem_wdata[15:8];
        if (iomem_wstrb[2]) gpio[23:16] <= iomem_wdata[23:16];
        if (iomem_wstrb[3]) gpio[31:24] <= iomem_wdata[31:24];
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
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .uart_tx_o    (uart_tx_o),
      .uart_rx_i    (uart_rx_i),
      .flash_csb_o  (flash_csb_o),
      .flash_clk_o  (flash_clk_o),
      .flash_io0_oe (flash_io0_oe),
      .flash_io1_oe (flash_io1_oe),
      .flash_io2_oe (flash_io2_oe),
      .flash_io3_oe (flash_io3_oe),
      .flash_io0_do (flash_io0_do),
      .flash_io1_do (flash_io1_do),
      .flash_io2_do (flash_io2_do),
      .flash_io3_do (flash_io3_do),
      .flash_io0_di (flash_io0_di),
      .flash_io1_di (flash_io1_di),
      .flash_io2_di (flash_io2_di),
      .flash_io3_di (flash_io3_di),
      .iomem_valid_o(iomem_valid),
      .iomem_ready_i(iomem_ready),
      .iomem_wstrb_o(iomem_wstrb),
      .iomem_addr_o (iomem_addr),
      .iomem_wdata_o(iomem_wdata),
      .iomem_rdata_i(iomem_rdata)
  );
endmodule
