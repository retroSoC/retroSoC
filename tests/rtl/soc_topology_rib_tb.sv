`timescale 1ns / 1ps

`include "mmap_define.svh"

module soc_topology_rib_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  rib_if rib ();

  `include "soc_rib_interfaces.svh"
  `include "soc_rib_routes.svh"

  always #5 clk_i = ~clk_i;

  task automatic expect_route(input logic [31:0] address, input integer slot,
                              input logic [31:0] expected_rdata);
    begin
      @(negedge clk_i);
      rib.addr  = address;
      rib.valid = 1'b1;
      #1;
      if (s_slv_sel_d !== (18'd1 << slot)) begin
        $fatal(1, "unexpected target slot for %h", address);
      end
      @(posedge clk_i);
      #1;
      if (!rib.ready || rib.rdata !== expected_rdata) begin
        $fatal(1, "unexpected response for %h", address);
      end
      @(negedge clk_i);
      rib.valid = 1'b0;
      @(posedge clk_i);
    end
  endtask

  task automatic expect_disabled(input logic [31:0] address);
    begin
      @(negedge clk_i);
      rib.addr  = address;
      rib.valid = 1'b1;
      #1;
      if (s_slv_sel_d !== '0) begin
        $fatal(1, "disabled target accepted %h", address);
      end
      @(posedge clk_i);
      #1;
      if (rib.ready || rib.rdata !== '0) begin
        $fatal(1, "disabled target responded to %h", address);
      end
      @(negedge clk_i);
      rib.valid = 1'b0;
      @(posedge clk_i);
    end
  endtask

  initial begin
    rib.valid               = 1'b0;
    rib.addr                = '0;
    rib.wdata               = '0;
    rib.wstrb               = '0;

    u_uart_rib_if.ready     = 1'b1;
    u_gpio_rib_if.ready     = 1'b1;
    u_tim0_rib_if.ready     = 1'b1;
    u_tim1_rib_if.ready     = 1'b1;
    u_psram_rib_if.ready    = 1'b1;
    u_spisd_rib_if.ready    = 1'b1;
    u_i2c0_rib_if.ready     = 1'b1;
    u_i2s_rib_if.ready      = 1'b1;
    u_onewire_rib_if.ready  = 1'b1;
    u_xpi_rib_if.ready      = 1'b1;
    u_dma_rib_if.ready      = 1'b1;
    u_sysctrl_rib_if.ready  = 1'b1;
    u_clint_rib_if.ready    = 1'b1;
    u_sdram_rib_if.ready    = 1'b1;
    u_dvp_rib_if.ready      = 1'b1;
    u_sdio_rib_if.ready     = 1'b1;
    u_opipsram_rib_if.ready = 1'b1;
    u_i2c1_rib_if.ready     = 1'b1;

    u_uart_rib_if.rdata     = 32'h0000_0000;
    u_gpio_rib_if.rdata     = 32'h1111_1111;
    u_tim0_rib_if.rdata     = 32'h2222_2222;
    u_tim1_rib_if.rdata     = 32'h3333_3333;
    u_psram_rib_if.rdata    = 32'h4444_4444;
    u_spisd_rib_if.rdata    = 32'h5555_5555;
    u_i2c0_rib_if.rdata     = 32'h6666_6666;
    u_i2s_rib_if.rdata      = 32'h7777_7777;
    u_onewire_rib_if.rdata  = 32'h8888_8888;
    u_xpi_rib_if.rdata      = 32'h9999_9999;
    u_dma_rib_if.rdata      = 32'hAAAA_AAAA;
    u_sysctrl_rib_if.rdata  = 32'hBBBB_BBBB;
    u_clint_rib_if.rdata    = 32'hCCCC_CCCC;
    u_sdram_rib_if.rdata    = 32'hDDDD_DDDD;
    u_dvp_rib_if.rdata      = 32'hEEEE_EEEE;
    u_sdio_rib_if.rdata     = 32'hF0F0_F0F0;
    u_opipsram_rib_if.rdata = 32'h0F0F_0F0F;
    u_i2c1_rib_if.rdata     = 32'h1234_5678;

    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;

    expect_route(`SOC_ADDR_RIB_GPIO_BASE, 1, 32'h1111_1111);
    expect_route(`SOC_ADDR_PSRAM_BASE, 4, 32'h4444_4444);
    expect_route(`SOC_ADDR_FLASH_BASE, 9, 32'h9999_9999);
    expect_route(`SOC_ADDR_RIB_I2C1_BASE, 17, 32'h1234_5678);
    expect_disabled(`SOC_ADDR_RIB_SDIO_BASE);

    $display("SoC topology RIB routing test passed");
    $finish;
  end
endmodule
