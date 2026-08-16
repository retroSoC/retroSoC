`timescale 1ns / 1ps

`include "mmap_define.svh"

module apb4_topology_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b1;
  logic [31:0] s_decode_addr = 32'd0;

  `include "apb4_periph_declarations.svh"
  `include "apb4_periph_select_routes.svh"

  always #5 clk_i = ~clk_i;

  task automatic expect_select(input logic [31:0] address, input integer slot);
    begin
      s_decode_addr = address;
      #1;
      if (s_psel_comb !== (18'd1 << slot)) begin
        $fatal(1, "unexpected APB4 target slot for %h: got %b", address, s_psel_comb);
      end
    end
  endtask

  task automatic expect_disabled(input logic [31:0] address);
    begin
      s_decode_addr = address;
      #1;
      if (s_psel_comb !== '0) begin
        $fatal(1, "disabled APB4 target accepted %h: got %b", address, s_psel_comb);
      end
    end
  endtask

  initial begin
    expect_select(`SOC_ADDR_APB4_GPIO_BASE, 1);
    expect_select(`SOC_ADDR_APB4_GPIO_ADMIN_BASE, 1);
    expect_select(`SOC_ADDR_APB4_PSRAM_BASE, 4);
    expect_select(`SOC_ADDR_APB4_XPI_BASE, 9);
    expect_select(`SOC_ADDR_APB4_SDRAM_BASE, 13);
    expect_select(`SOC_ADDR_APB4_I2C1_BASE, 17);
    expect_disabled(`SOC_ADDR_APB4_SDIO_BASE);
    expect_disabled(`SOC_ADDR_APB4_OPIPSRAM_BASE);
    $display("SoC topology APB4 routing test passed");
    $finish;
  end
endmodule
