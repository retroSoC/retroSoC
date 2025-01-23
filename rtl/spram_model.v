
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

module spram_model (
    input         clk,
    input  [ 3:0] wen,
    input  [21:0] addr,
    input  [31:0] wdata,
    output [31:0] rdata
);

  wire cs_00, cs_01, cs_10, cs_11;
  wire [31:0] rdata_00, rdata_01;
  wire [31:0] rdata_10, rdata_11;

  assign cs_00 = ~addr[11] && ~addr[10];
  assign cs_01 = ~addr[11] && addr[10];
  assign cs_10 = addr[11] && ~addr[10];
  assign cs_11 = addr[11] && addr[10];

  assign rdata = ({32{cs_00}} & rdata_00) | ({32{cs_01}} & rdata_01) |
                 ({32{cs_10}} & rdata_10) | ({32{cs_11}} & rdata_11);

  // 4x4KB=16KB
  // SPRAM1024X32 u_ram00 (
  tc_sram_1024x32 u_ram00 (
      .clk_i (clk),
      .cs_i  (cs_00),
      .addr_i(addr[9:0]),
      .data_i(wdata),
      .mask_i(wen),
      .wren_i(|wen),
      .data_o(rdata_00)
  );

  // SPRAM1024X32 u_ram01 (
  tc_sram_1024x32 u_ram01 (
      .clk_i (clk),
      .cs_i  (cs_01),
      .addr_i(addr[9:0]),
      .data_i(wdata),
      .mask_i(wen),
      .wren_i(|wen),
      .data_o(rdata_01)
  );

  // SPRAM1024X32 u_ram10 (
  tc_sram_1024x32 u_ram10 (
      .clk_i (clk),
      .cs_i  (cs_10),
      .addr_i(addr[9:0]),
      .data_i(wdata),
      .mask_i(wen),
      .wren_i(|wen),
      .data_o(rdata_10)
  );

  // SPRAM1024X32 u_ram11 (
  tc_sram_1024x32 u_ram11 (
      .clk_i (clk),
      .cs_i  (cs_11),
      .addr_i(addr[9:0]),
      .data_i(wdata),
      .mask_i(wen),
      .wren_i(|wen),
      .data_o(rdata_11)
  );
endmodule


// 4KB
module SPRAM1024X32 (
    input             clk_i,
    input             cs_i,
    input      [ 9:0] addr_i,
    input      [31:0] data_i,
    input      [ 3:0] mask_i,
    input             wren_i,
    output reg [31:0] data_o
);
  reg [31:0] mem[0:1023];
  always @(posedge clk_i) begin
    if (cs_i) begin
      if (!wren_i) begin
        data_o <= mem[addr_i];
      end else begin
        if (mask_i[0]) mem[addr_i][7:0] <= data_i[7:0];
        if (mask_i[1]) mem[addr_i][15:8] <= data_i[15:8];
        if (mask_i[2]) mem[addr_i][23:16] <= data_i[23:16];
        if (mask_i[3]) mem[addr_i][31:24] <= data_i[31:24];
        data_o <= 32'bx;
      end
    end
  end
endmodule
