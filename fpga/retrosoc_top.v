`timescale 1ns / 1ps

module retrosoc_top (
    input  clk_i,
    input  rst_n_i,
    input  uart_rx_i,
    output uart_tx_o,
    output flash_csb_o,
    output flash_clk_o,
    inout  flash_io0_io,
    inout  flash_io1_io
);

  wire clk_core;
  clk_wiz_0 u_clk_wiz_0 (
      .clk_in1 (clk_i),
      .clk_out1(clk_core)
  );

  retrosoc_asic #(
      .MEM_WORDS(256)
  ) u_retrosoc (
      .clk_i       (clk_core),
      .rst_n_i     (rst_n_i),
      .uart_rx_i   (uart_rx_i),
      .uart_tx_o   (uart_tx_o),
      .flash_csb_o (flash_csb_o),
      .flash_clk_o (flash_clk_o),
      .flash_io0_io(flash_io0_io),
      .flash_io1_io(flash_io1_io)
  );
endmodule
