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

`ifndef PICORV32_REGS
`ifdef PICORV32_V
// `error "picosoc.v must be read before picorv32.v!"
`endif

`define PICORV32_REGS picosoc_regs
`endif

`ifndef PICOSOC_MEM
`define PICOSOC_MEM picosoc_mem
`endif

// this macro can be used to check if the verilog files in your
// design are read in the correct order.
`define PICOSOC_V

module retrosoc #(
    parameter integer        MEM_WORDS        = 256,
    parameter         [ 0:0] BARREL_SHIFTER   = 1,
    parameter         [ 0:0] COMPRESSED_ISA   = 1,
    parameter         [ 0:0] ENABLE_MUL       = 0,
    parameter         [ 0:0] ENABLE_FAST_MUL  = 1,
    parameter         [ 0:0] ENABLE_DIV       = 1,
    parameter         [ 0:0] ENABLE_IRQ       = 0,
    parameter         [ 0:0] ENABLE_IRQ_QREGS = 1,
    parameter         [31:0] STACKADDR        = (4 * MEM_WORDS),  // end of memory
    parameter         [31:0] PROGADDR_RESET   = 32'h0010_0000,    // 1 MB into flash
    parameter         [31:0] PROGADDR_IRQ     = 32'h0000_0000
) (
    input         clk_i,
    input         rst_n_i,
    output        iomem_valid_o,
    input         iomem_ready_i,
    output [ 3:0] iomem_wstrb_o,
    output [31:0] iomem_addr_o,
    output [31:0] iomem_wdata_o,
    input  [31:0] iomem_rdata_i,
    output        uart_tx_o,
    input         uart_rx_i,
    output        flash_csb_o,
    output        flash_clk_o,
    output        flash_io0_oe_o,
    output        flash_io1_oe_o,
    output        flash_io2_oe_o,
    output        flash_io3_oe_o,
    output        flash_io0_do_o,
    output        flash_io1_do_o,
    output        flash_io2_do_o,
    output        flash_io3_do_o,
    input         flash_io0_di_i,
    input         flash_io1_di_i,
    input         flash_io2_di_i,
    input         flash_io3_di_i
);

  wire        s_mem_valid;
  wire        s_mem_instr;
  wire        s_mem_ready;
  wire [31:0] s_mem_addr;
  wire [31:0] s_mem_wdata;
  wire [ 3:0] s_mem_wstrb;
  wire [31:0] s_mem_rdata;
  wire        s_spimem_ready;
  wire [31:0] s_spimem_rdata;
  reg         s_ram_ready;
  wire [31:0] s_ram_rdata;

  assign iomem_valid_o = s_mem_valid && (s_mem_addr[31:24] > 8'h01);
  assign iomem_wstrb_o = s_mem_wstrb;
  assign iomem_addr_o  = s_mem_addr;
  assign iomem_wdata_o = s_mem_wdata;

  wire        s_spimemio_cfgreg_sel = s_mem_valid && (s_mem_addr == 32'h0200_0000);
  wire [31:0] s_spimemio_cfgreg_do;
  wire        s_simpleuart_reg_div_sel = s_mem_valid && (s_mem_addr == 32'h0200_0004);
  wire [31:0] s_simpleuart_reg_div_do;
  wire        s_simpleuart_reg_dat_sel = s_mem_valid && (s_mem_addr == 32'h0200_0008);
  wire [31:0] s_simpleuart_reg_dat_do;
  wire        s_simpleuart_reg_dat_wait;

  assign s_mem_ready = (iomem_valid_o && iomem_ready_i) || s_spimem_ready || s_ram_ready || s_spimemio_cfgreg_sel ||
            s_simpleuart_reg_div_sel || (s_simpleuart_reg_dat_sel && !s_simpleuart_reg_dat_wait);

  assign s_mem_rdata = (iomem_valid_o && iomem_ready_i) ? iomem_rdata_i : s_spimem_ready ? s_spimem_rdata : s_ram_ready ? s_ram_rdata :
            s_spimemio_cfgreg_sel ? s_spimemio_cfgreg_do : s_simpleuart_reg_div_sel ? s_simpleuart_reg_div_do :
            s_simpleuart_reg_dat_sel ? s_simpleuart_reg_dat_do : 32'h 0000_0000;

  picorv32 #(
      .BARREL_SHIFTER  (BARREL_SHIFTER),
      .COMPRESSED_ISA  (COMPRESSED_ISA),
      .ENABLE_MUL      (ENABLE_MUL),
      .ENABLE_FAST_MUL (ENABLE_FAST_MUL),
      .ENABLE_DIV      (ENABLE_DIV),
      .ENABLE_IRQ      (1),
      .ENABLE_IRQ_QREGS(ENABLE_IRQ_QREGS),
      .STACKADDR       (STACKADDR),
      .PROGADDR_RESET  (PROGADDR_RESET),
      .PROGADDR_IRQ    (PROGADDR_IRQ)
  ) u_picorv32 (
      .clk      (clk_i),
      .resetn   (rst_n_i),
      .mem_valid(s_mem_valid),
      .mem_instr(s_mem_instr),
      .mem_ready(s_mem_ready),
      .mem_addr (s_mem_addr),
      .mem_wdata(s_mem_wdata),
      .mem_wstrb(s_mem_wstrb),
      .mem_rdata(s_mem_rdata),
      .irq      (32'd0)
  );

  spimemio u_spimemio (
      .clk         (clk_i),
      .resetn      (rst_n_i),
      .valid       (s_mem_valid && s_mem_addr >= 4 * MEM_WORDS && s_mem_addr < 32'h0200_0000),
      .ready       (s_spimem_ready),
      .addr        (s_mem_addr[23:0]),
      .rdata       (s_spimem_rdata),
      .flash_csb   (flash_csb_o),
      .flash_clk   (flash_clk_o),
      .flash_io0_oe(flash_io0_oe_o),
      .flash_io1_oe(flash_io1_oe_o),
      .flash_io2_oe(flash_io2_oe_o),
      .flash_io3_oe(flash_io3_oe_o),
      .flash_io0_do(flash_io0_do_o),
      .flash_io1_do(flash_io1_do_o),
      .flash_io2_do(flash_io2_do_o),
      .flash_io3_do(flash_io3_do_o),
      .flash_io0_di(flash_io0_di_i),
      .flash_io1_di(flash_io1_di_i),
      .flash_io2_di(flash_io2_di_i),
      .flash_io3_di(flash_io3_di_i),
      .cfgreg_we   (s_spimemio_cfgreg_sel ? s_mem_wstrb : 4'b0000),
      .cfgreg_di   (s_mem_wdata),
      .cfgreg_do   (s_spimemio_cfgreg_do)
  );

  simpleuart u_simpleuart (
      .clk         (clk_i),
      .resetn      (rst_n_i),
      .ser_tx      (uart_tx_o),
      .ser_rx      (uart_rx_i),
      .reg_div_we  (s_simpleuart_reg_div_sel ? s_mem_wstrb : 4'b0000),
      .reg_div_di  (s_mem_wdata),
      .reg_div_do  (s_simpleuart_reg_div_do),
      .reg_dat_we  (s_simpleuart_reg_dat_sel ? s_mem_wstrb[0] : 1'b0),
      .reg_dat_re  (s_simpleuart_reg_dat_sel && !s_mem_wstrb),
      .reg_dat_di  (s_mem_wdata),
      .reg_dat_do  (s_simpleuart_reg_dat_do),
      .reg_dat_wait(s_simpleuart_reg_dat_wait)
  );

  always @(posedge clk_i) s_ram_ready <= s_mem_valid && !s_mem_ready && s_mem_addr < 4 * MEM_WORDS;

  `PICOSOC_MEM u_picosoc_mem (
      .clk  (clk_i),
      .wen  ((s_mem_valid && !s_mem_ready && s_mem_addr < 4 * MEM_WORDS) ? s_mem_wstrb : 4'b0),
      .addr (s_mem_addr[23:2]),
      .wdata(s_mem_wdata),
      .rdata(s_ram_rdata)
  );
endmodule

// Implementation note:
// Replace the following two modules with wrappers for your SRAM cells.

module picosoc_regs (
    input         clk,
    input         wen,
    input  [ 5:0] waddr,
    input  [ 5:0] raddr1,
    input  [ 5:0] raddr2,
    input  [31:0] wdata,
    output [31:0] rdata1,
    output [31:0] rdata2
);
  reg [31:0] regs[0:31];

  always @(posedge clk) if (wen) regs[waddr[4:0]] <= wdata;

  assign rdata1 = regs[raddr1[4:0]];
  assign rdata2 = regs[raddr2[4:0]];
endmodule

module picosoc_mem (
    input             clk,
    input      [ 3:0] wen,
    input      [21:0] addr,
    input      [31:0] wdata,
    output reg [31:0] rdata
);
  //   reg [31:0] mem[0:256-1];
  //   always @(posedge clk) begin
  //     rdata <= mem[addr];
  //     if (wen[0]) mem[addr][7:0] <= wdata[7:0];
  //     if (wen[1]) mem[addr][15:8] <= wdata[15:8];
  //     if (wen[2]) mem[addr][23:16] <= wdata[23:16];
  //     if (wen[3]) mem[addr][31:24] <= wdata[31:24];
  //   end
  spram_model u_spram_model (
      .clk  (clk),
      .wen  (wen),
      .addr (addr),
      .wdata(wdata),
      .rdata(rdata)
  );
endmodule

