`timescale 1ns / 1ps

`include "mmap_define.svh"

module soc_topology_nmi_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  nmi_if nmi ();

  `include "soc_nmi_interfaces.svh"
  `include "soc_nmi_routes.svh"

  always #5 clk_i = ~clk_i;

  task automatic expect_route(input logic [31:0] address, input integer slot,
                              input logic [31:0] expected_rdata);
    begin
      @(negedge clk_i);
      nmi.addr  = address;
      nmi.valid = 1'b1;
      #1;
      if (s_slv_sel_d !== (18'd1 << slot)) begin
        $fatal(1, "unexpected target slot for %h", address);
      end
      @(posedge clk_i);
      #1;
      if (!nmi.ready || nmi.rdata !== expected_rdata) begin
        $fatal(1, "unexpected response for %h", address);
      end
      @(negedge clk_i);
      nmi.valid = 1'b0;
      @(posedge clk_i);
    end
  endtask

  task automatic expect_disabled(input logic [31:0] address);
    begin
      @(negedge clk_i);
      nmi.addr  = address;
      nmi.valid = 1'b1;
      #1;
      if (s_slv_sel_d !== '0) begin
        $fatal(1, "disabled target accepted %h", address);
      end
      @(posedge clk_i);
      #1;
      if (nmi.ready || nmi.rdata !== '0) begin
        $fatal(1, "disabled target responded to %h", address);
      end
      @(negedge clk_i);
      nmi.valid = 1'b0;
      @(posedge clk_i);
    end
  endtask

  initial begin
    nmi.valid               = 1'b0;
    nmi.addr                = '0;
    nmi.wdata               = '0;
    nmi.wstrb               = '0;

    u_uart_nmi_if.ready     = 1'b1;
    u_gpio_nmi_if.ready     = 1'b1;
    u_tim0_nmi_if.ready     = 1'b1;
    u_tim1_nmi_if.ready     = 1'b1;
    u_psram_nmi_if.ready    = 1'b1;
    u_spisd_nmi_if.ready    = 1'b1;
    u_i2c0_nmi_if.ready     = 1'b1;
    u_i2s_nmi_if.ready      = 1'b1;
    u_onewire_nmi_if.ready  = 1'b1;
    u_xpi_nmi_if.ready      = 1'b1;
    u_dma_nmi_if.ready      = 1'b1;
    u_sysctrl_nmi_if.ready  = 1'b1;
    u_clint_nmi_if.ready    = 1'b1;
    u_sdram_nmi_if.ready    = 1'b1;
    u_dvp_nmi_if.ready      = 1'b1;
    u_sdio_nmi_if.ready     = 1'b1;
    u_opipsram_nmi_if.ready = 1'b1;
    u_i2c1_nmi_if.ready     = 1'b1;

    u_uart_nmi_if.rdata     = 32'h0000_0000;
    u_gpio_nmi_if.rdata     = 32'h1111_1111;
    u_tim0_nmi_if.rdata     = 32'h2222_2222;
    u_tim1_nmi_if.rdata     = 32'h3333_3333;
    u_psram_nmi_if.rdata    = 32'h4444_4444;
    u_spisd_nmi_if.rdata    = 32'h5555_5555;
    u_i2c0_nmi_if.rdata     = 32'h6666_6666;
    u_i2s_nmi_if.rdata      = 32'h7777_7777;
    u_onewire_nmi_if.rdata  = 32'h8888_8888;
    u_xpi_nmi_if.rdata      = 32'h9999_9999;
    u_dma_nmi_if.rdata      = 32'hAAAA_AAAA;
    u_sysctrl_nmi_if.rdata  = 32'hBBBB_BBBB;
    u_clint_nmi_if.rdata    = 32'hCCCC_CCCC;
    u_sdram_nmi_if.rdata    = 32'hDDDD_DDDD;
    u_dvp_nmi_if.rdata      = 32'hEEEE_EEEE;
    u_sdio_nmi_if.rdata     = 32'hF0F0_F0F0;
    u_opipsram_nmi_if.rdata = 32'h0F0F_0F0F;
    u_i2c1_nmi_if.rdata     = 32'h1234_5678;

    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;

    expect_route(`SOC_ADDR_NMI_GPIO_BASE, 1, 32'h1111_1111);
    expect_route(`SOC_ADDR_PSRAM_BASE, 4, 32'h4444_4444);
    expect_route(`SOC_ADDR_FLASH_BASE, 9, 32'h9999_9999);
    expect_route(`SOC_ADDR_NMI_I2C1_BASE, 17, 32'h1234_5678);
    expect_disabled(`SOC_ADDR_NMI_SDIO_BASE);

    $display("SoC topology NMI routing test passed");
    $finish;
  end
endmodule
