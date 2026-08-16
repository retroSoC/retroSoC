`timescale 1ns / 1ps

`include "gpio_define.svh"

module gpio_tb;
  localparam int PinNum = 4;
  localparam logic [31:0] USER_BASE = 32'h1000_0000;
  localparam logic [31:0] ADMIN_BASE = 32'h1001_4000;

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
      .UserBaseAddr (USER_BASE),
      .AdminBaseAddr(ADMIN_BASE),
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

  task automatic read_register(input logic [31:0] address, output logic [31:0] data,
                               input logic expected_error);
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
      if (apb4.pslverr !== expected_error) begin
        $fatal(1, "read %h error=%b expected=%b", address, apb4.pslverr, expected_error);
      end
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

    read_register(ADMIN_BASE + `APB4_GPIO_CAPABILITY, read_data, 1'b0);
    if (read_data !== 32'h007F_4204) $fatal(1, "capability register mismatch");
    read_register(ADMIN_BASE + `APB4_GPIO_PAD_CAPABILITY, read_data, 1'b0);
    if (read_data !== 32'h0000_0007) $fatal(1, "pad capability register mismatch");
    read_register(ADMIN_BASE + `APB4_GPIO_ADMIN_OUTPUT_ENABLE, read_data, 1'b0);
    if (read_data !== 32'd0) $fatal(1, "output enable reset value mismatch");

    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_OUT_SET, 32'h1, 1'b0);
    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_OE_SET, 32'h1, 1'b0);
    if ({gpio.oe_o[0], gpio.do_o[0]} !== 2'b11) $fatal(1, "software output failed");
    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_OUT_TOGGLE, 32'h1, 1'b0);
    if (gpio.do_o[0] !== 1'b0) $fatal(1, "atomic output toggle failed");
    read_register(ADMIN_BASE + 32'h2, read_data, 1'b1);

    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_USER_ACCESS_MASK, 32'h2, 1'b0);
    write_register(USER_BASE + `APB4_GPIO_USER_OUT_SET, 32'h6, 1'b0);
    read_register(USER_BASE + `APB4_GPIO_USER_DATA_OUT, read_data, 1'b0);
    if (read_data !== 32'h2) $fatal(1, "user access mask did not isolate output data");

    user_gpio.do_o[2] = 1'b1;
    user_gpio.oe_o[2] = 1'b1;
    @(negedge clk_i);
    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_USER_SELECT, 32'h4, 1'b0);
    @(posedge clk_i);
    #1;
    if ({gpio.oe_o[2], gpio.do_o[2]} !== 2'b11) $fatal(1, "user output was not selected");

    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_OE_SET, 32'h2, 1'b0);
    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_OPEN_DRAIN, 32'h2, 1'b0);
    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_OUT_SET, 32'h2, 1'b0);
    if ({gpio.oe_o[1], gpio.do_o[1]} !== 2'b00) $fatal(1, "open-drain release failed");
    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_OUT_CLEAR, 32'h2, 1'b0);
    if ({gpio.oe_o[1], gpio.do_o[1]} !== 2'b10) $fatal(1, "open-drain low drive failed");

    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_PULL_UP, 32'h8, 1'b0);
    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_PULL_DOWN, 32'h8, 1'b1);

    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_INTR_RISE_ENABLE, 32'h1, 1'b0);
    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_INTR_ENABLE, 32'h1, 1'b0);
    gpio.di_i[0] = 1'b1;
    repeat (5) @(posedge clk_i);
    read_register(ADMIN_BASE + `APB4_GPIO_ADMIN_INTR_STATE, read_data, 1'b0);
    if ((read_data & 32'h1) == 0) $fatal(1, "rising edge interrupt was not latched");
    if (!gpio.irq_o) $fatal(1, "combined GPIO interrupt was not asserted");
    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_INTR_STATE, 32'h1, 1'b0);
    if (gpio.irq_o) $fatal(1, "W1C did not clear the interrupt");
    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_INTR_TEST, 32'h1, 1'b0);
    if (!gpio.irq_o) $fatal(1, "software interrupt test failed");
    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_INTR_STATE, 32'h1, 1'b0);

    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_INTR_RISE_ENABLE, 32'h9, 1'b0);
    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_INTR_HIGH_ENABLE, 32'h8, 1'b1);

    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_FILTER_DIV, 32'h0, 1'b0);
    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_FILTER_COUNT, 32'h4, 1'b0);
    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_FILTER_ENABLE, 32'h8, 1'b0);
    gpio.di_i[3] = 1'b1;
    @(posedge clk_i);
    gpio.di_i[3] = 1'b0;
    repeat (5) @(posedge clk_i);
    read_register(ADMIN_BASE + `APB4_GPIO_ADMIN_DATA_IN, read_data, 1'b0);
    if ((read_data & 32'h8) != 0) $fatal(1, "input filter accepted a short pulse");
    gpio.di_i[3] = 1'b1;
    repeat (8) @(posedge clk_i);
    read_register(ADMIN_BASE + `APB4_GPIO_ADMIN_DATA_IN, read_data, 1'b0);
    if ((read_data & 32'h8) == 0) $fatal(1, "input filter rejected a stable input");

    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_CONFIG_LOCK, 32'h1, 1'b0);
    write_register(ADMIN_BASE + `APB4_GPIO_ADMIN_OE_CLEAR, 32'h1, 1'b1);
    if (gpio.oe_o[0] !== 1'b1) $fatal(1, "configuration lock did not protect OE");

    $display("GPIO directed test passed");
    $finish;
  end
endmodule
