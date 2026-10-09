`timescale 1ns / 1ps

`include "gpio_define.svh"

module gpio_pad_integration_tb;
  localparam int PinNum = 1;
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
  tri pad;

  always #5 clk_i = ~clk_i;

  apb4_gpio #(
      .PinNum       (PinNum),
      .UserBaseAddr (UserBase),
      .AdminBaseAddr(AdminBase),
      .HasInputCmos (1'b1),
      .HasPullUp    (1'b1),
      .HasPullDown  (1'b1)
  ) dut (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .apb4     (apb4),
      .gpio     (gpio),
      .user_gpio(user_gpio)
  );

  tc_io_tri_full_pad u_pad (
      .pad   (pad),
      .c2p   (gpio.do_o[0]),
      .c2p_en(gpio.oe_o[0]),
      .p2c   (gpio.di_i[0]),
      .cs    (gpio.cs_o[0]),
      .pu    (gpio.pu_o[0]),
      .pd    (gpio.pd_o[0])
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

  initial begin
    apb4.psel      = 1'b0;
    apb4.penable   = 1'b0;
    apb4.pwrite    = 1'b0;
    apb4.paddr     = '0;
    apb4.pwdata    = '0;
    apb4.pstrb     = '0;
    apb4.pprot     = '0;
    gpio.alt0_do_i = '0;
    gpio.alt0_oe_i = '0;
    gpio.alt1_do_i = '0;
    gpio.alt1_oe_i = '0;
    user_gpio.do_o = '0;
    user_gpio.oe_o = '0;

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (3) @(posedge clk_i);

    write_register(AdminBase + `APB4_GPIO_ADMIN_PULL_UP, 32'h1, 1'b0);
    #1;
    if ((pad !== 1'b1) || (gpio.di_i[0] !== 1'b1)) $fatal(1, "pull-up did not reach pad");
    write_register(AdminBase + `APB4_GPIO_ADMIN_PULL_DOWN, 32'h1, 1'b1);
    if ({gpio.pu_o[0], gpio.pd_o[0]} !== 2'b10) $fatal(1, "pull conflict changed state");

    write_register(AdminBase + `APB4_GPIO_ADMIN_PULL_UP, 32'h0, 1'b0);
    write_register(AdminBase + `APB4_GPIO_ADMIN_PULL_DOWN, 32'h1, 1'b0);
    #1;
    if ((pad !== 1'b0) || (gpio.di_i[0] !== 1'b0)) $fatal(1, "pull-down did not reach pad");

    write_register(AdminBase + `APB4_GPIO_ADMIN_CONFIG_LOCK, 32'h1, 1'b0);
    write_register(AdminBase + `APB4_GPIO_ADMIN_PULL_DOWN, 32'h0, 1'b1);
    #1;
    if ((pad !== 1'b0) || (gpio.pd_o[0] !== 1'b1)) $fatal(1, "lock did not preserve pull-down");

    $display("GPIO controller-to-pad integration test passed");
    $finish;
  end
endmodule
