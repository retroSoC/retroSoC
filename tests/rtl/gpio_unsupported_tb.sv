`timescale 1ns / 1ps

`include "gpio_define.svh"

module gpio_unsupported_tb;
  localparam int PinNum = 4;
  localparam logic [31:0] UserBase = 32'h1000_0000;
  localparam logic [31:0] AdminBase = 32'h1001_4000;

  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  gpio_if #(PinNum) gpio ();
  user_gpio_if #(PinNum) user_gpio ();
  logic [31:0] read_data;

  always #5 clk_i = ~clk_i;

  apb4_gpio #(
      .PinNum       (PinNum),
      .UserBaseAddr (UserBase),
      .AdminBaseAddr(AdminBase),
      .HasInputCmos (1'b0),
      .HasPullUp    (1'b0),
      .HasPullDown  (1'b0)
  ) dut (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .apb4     (apb4),
      .gpio     (gpio),
      .user_gpio(user_gpio)
  );

  task automatic write_register(input logic [31:0] address, input logic [31:0] data,
                                input logic expected_error);
    begin
      @(negedge clk_i);
      apb4.paddr   = address;
      apb4.pwdata  = data;
      apb4.pstrb   = 4'hF;
      apb4.pwrite  = 1'b1;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr !== expected_error) begin
        $fatal(1, "write %h error=%b expected=%b", address, apb4.pslverr, expected_error);
      end
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
    end
  endtask

  task automatic read_register(input logic [31:0] address, output logic [31:0] data);
    begin
      @(negedge clk_i);
      apb4.paddr   = address;
      apb4.pwdata  = '0;
      apb4.pstrb   = '0;
      apb4.pwrite  = 1'b0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr !== 1'b0) $fatal(1, "read %h unexpectedly failed", address);
      data         = apb4.prdata;
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  initial begin
    apb4.psel      = 1'b0;
    apb4.penable   = 1'b0;
    apb4.pwrite    = 1'b0;
    apb4.paddr     = '0;
    apb4.pwdata    = '0;
    apb4.pstrb     = '0;
    apb4.pprot     = '0;
    gpio.di_i      = '0;
    gpio.alt0_do_i = '0;
    gpio.alt0_oe_i = '0;
    gpio.alt1_do_i = '0;
    gpio.alt1_oe_i = '0;
    user_gpio.do_o = '0;
    user_gpio.oe_o = '0;

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (3) @(posedge clk_i);

    read_register(AdminBase + `APB4_GPIO_PAD_CAPABILITY, read_data);
    if (read_data !== 32'h0000_0000) $fatal(1, "unsupported pad capability mismatch");
    write_register(AdminBase + `APB4_GPIO_ADMIN_PULL_UP, 32'h1, 1'b1);
    write_register(AdminBase + `APB4_GPIO_ADMIN_PULL_DOWN, 32'h1, 1'b1);
    write_register(AdminBase + `APB4_GPIO_ADMIN_PULL_UP, 32'h0, 1'b0);
    if ((gpio.pu_o !== '0) || (gpio.pd_o !== '0)) begin
      $fatal(1, "unsupported pull controls reached the GPIO pad interface");
    end

    $display("GPIO unsupported capability test passed");
    $finish;
  end
endmodule
