`timescale 1ns / 1ps

`include "mmap_define.svh"

module ribp_topology_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  ribp_if ribp ();

  `include "ribp_interfaces.svh"
  `include "ribp_routes.svh"

  always #5 clk_i = ~clk_i;

  task automatic expect_route(input logic [31:0] address, input integer slot,
                              input logic [31:0] expected_rdata);
    begin
      @(negedge clk_i);
      ribp.addr  = address;
      ribp.valid = 1'b1;
      #1;
      if (s_slv_sel_d !== (18'd1 << slot)) begin
        $fatal(1, "unexpected target slot for %h", address);
      end
      @(posedge clk_i);
      #1;
      if (!ribp.ready || ribp.rdata !== expected_rdata) begin
        $fatal(1, "unexpected response for %h", address);
      end
      @(negedge clk_i);
      ribp.valid = 1'b0;
      @(posedge clk_i);
    end
  endtask

  task automatic expect_disabled(input logic [31:0] address);
    begin
      @(negedge clk_i);
      ribp.addr  = address;
      ribp.valid = 1'b1;
      #1;
      if (s_slv_sel_d !== '0) begin
        $fatal(1, "disabled target accepted %h", address);
      end
      @(posedge clk_i);
      #1;
      if (ribp.ready || ribp.rdata !== 32'd0) begin
        $fatal(1, "disabled target responded to %h", address);
      end
      @(negedge clk_i);
      ribp.valid = 1'b0;
      @(posedge clk_i);
    end
  endtask

  task automatic expect_error_route(input logic [31:0] address, input integer slot);
    begin
      @(negedge clk_i);
      ribp.addr  = address;
      ribp.valid = 1'b1;
      #1;
      if (s_slv_sel_d !== (18'd1 << slot)) begin
        $fatal(1, "unexpected error target slot for %h", address);
      end
      @(posedge clk_i);
      #1;
      if (!ribp.ready || !ribp.resp_err) begin
        $fatal(1, "error response was not propagated for %h", address);
      end
      @(negedge clk_i);
      ribp.valid = 1'b0;
      @(posedge clk_i);
    end
  endtask

  initial begin
    ribp.valid                  = 1'b0;
    ribp.addr                   = '0;
    ribp.wdata                  = '0;
    ribp.wstrb                  = '0;

    u_uart_ribp_if.ready        = 1'b1;
    u_gpio_ribp_if.ready        = 1'b1;
    u_tim0_ribp_if.ready        = 1'b1;
    u_tim1_ribp_if.ready        = 1'b1;
    u_psram_ribp_if.ready       = 1'b1;
    u_spisd_ribp_if.ready       = 1'b1;
    u_i2c0_ribp_if.ready        = 1'b1;
    u_i2s_ribp_if.ready         = 1'b1;
    u_onewire_ribp_if.ready     = 1'b1;
    u_xpi_ribp_if.ready         = 1'b1;
    u_dma_ribp_if.ready         = 1'b1;
    u_sysctrl_ribp_if.ready     = 1'b1;
    u_clint_ribp_if.ready       = 1'b1;
    u_sdram_ribp_if.ready       = 1'b1;
    u_dvp_ribp_if.ready         = 1'b1;
    u_sdio_ribp_if.ready        = 1'b1;
    u_opipsram_ribp_if.ready    = 1'b1;
    u_i2c1_ribp_if.ready        = 1'b1;

    u_uart_ribp_if.rdata        = 32'h0000_0000;
    u_gpio_ribp_if.rdata        = 32'h1111_1111;
    u_tim0_ribp_if.rdata        = 32'h2222_2222;
    u_tim1_ribp_if.rdata        = 32'h3333_3333;
    u_psram_ribp_if.rdata       = 32'h4444_4444;
    u_spisd_ribp_if.rdata       = 32'h5555_5555;
    u_i2c0_ribp_if.rdata        = 32'h6666_6666;
    u_i2s_ribp_if.rdata         = 32'h7777_7777;
    u_onewire_ribp_if.rdata     = 32'h8888_8888;
    u_xpi_ribp_if.rdata         = 32'h9999_9999;
    u_dma_ribp_if.rdata         = 32'hAAAA_AAAA;
    u_sysctrl_ribp_if.rdata     = 32'hBBBB_BBBB;
    u_clint_ribp_if.rdata       = 32'hCCCC_CCCC;
    u_sdram_ribp_if.rdata       = 32'hDDDD_DDDD;
    u_dvp_ribp_if.rdata         = 32'hEEEE_EEEE;
    u_sdio_ribp_if.rdata        = 32'hF0F0_F0F0;
    u_opipsram_ribp_if.rdata    = 32'h0F0F_0F0F;
    u_i2c1_ribp_if.rdata        = 32'h1234_5678;

    u_uart_ribp_if.resp_err     = 1'b0;
    u_gpio_ribp_if.resp_err     = 1'b0;
    u_tim0_ribp_if.resp_err     = 1'b0;
    u_tim1_ribp_if.resp_err     = 1'b0;
    u_psram_ribp_if.resp_err    = 1'b0;
    u_spisd_ribp_if.resp_err    = 1'b0;
    u_i2c0_ribp_if.resp_err     = 1'b0;
    u_i2s_ribp_if.resp_err      = 1'b0;
    u_onewire_ribp_if.resp_err  = 1'b0;
    u_xpi_ribp_if.resp_err      = 1'b0;
    u_dma_ribp_if.resp_err      = 1'b0;
    u_sysctrl_ribp_if.resp_err  = 1'b0;
    u_clint_ribp_if.resp_err    = 1'b0;
    u_sdram_ribp_if.resp_err    = 1'b0;
    u_dvp_ribp_if.resp_err      = 1'b0;
    u_sdio_ribp_if.resp_err     = 1'b0;
    u_opipsram_ribp_if.resp_err = 1'b0;
    u_i2c1_ribp_if.resp_err     = 1'b0;

    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;

    expect_route(`SOC_ADDR_RIBP_GPIO_BASE, 1, 32'h1111_1111);
    expect_route(`SOC_ADDR_PSRAM_BASE, 4, 32'h4444_4444);
    expect_route(`SOC_ADDR_FLASH_BASE, 9, 32'h9999_9999);
    expect_route(`SOC_ADDR_RIBP_I2C1_BASE, 17, 32'h1234_5678);
    expect_disabled(`SOC_ADDR_RIBP_SDIO_BASE);
    u_gpio_ribp_if.resp_err = 1'b1;
    expect_error_route(`SOC_ADDR_RIBP_GPIO_BASE, 1);
    u_gpio_ribp_if.resp_err = 1'b0;

    $display("SoC topology RIBP routing test passed");
    $finish;
  end
endmodule
