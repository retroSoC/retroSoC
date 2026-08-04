`timescale 1ns / 1ps

module gpio_user_mux_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  ribp_if rib ();
  gpio_if gpio ();
  user_gpio_if user_gpio ();
  logic [31:0] read_data;

  always #5 clk_i = ~clk_i;

  ribp_gpio dut (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .ribp     (rib),
      .gpio     (gpio),
      .user_gpio(user_gpio)
  );

  task automatic write_register(input logic [7:0] address, input logic [31:0] data);
    begin
      @(negedge clk_i);
      rib.addr  = {24'd0, address};
      rib.wdata = data;
      rib.wstrb = 4'hF;
      rib.valid = 1'b1;
      @(posedge clk_i);
      #1;
      @(negedge clk_i);
      rib.valid = 1'b0;
      @(posedge clk_i);
      #1;
    end
  endtask

  task automatic read_register(input logic [7:0] address, output logic [31:0] data);
    begin
      @(negedge clk_i);
      rib.addr  = {24'd0, address};
      rib.wdata = '0;
      rib.wstrb = '0;
      rib.valid = 1'b1;
      @(posedge clk_i);
      #1;
      data = rib.rdata;
      @(negedge clk_i);
      rib.valid = 1'b0;
      @(posedge clk_i);
      #1;
    end
  endtask

  task automatic select_user_gpio(input logic [31:0] selection);
    begin
      @(negedge clk_i);
      rib.addr  = 32'h0000_0030;
      rib.wdata = selection;
      rib.wstrb = 4'hF;
      rib.valid = 1'b1;
      @(posedge clk_i);
      #1;
      if (gpio.oe_o[0] !== 1'b0) $fatal(1, "GPIO handoff did not drive high impedance");
      @(negedge clk_i);
      rib.valid = 1'b0;
      @(posedge clk_i);
      #1;
    end
  endtask

  initial begin
    rib.valid      = 1'b0;
    rib.addr       = '0;
    rib.wdata      = '0;
    rib.wstrb      = '0;
    gpio.di_i      = '0;
    gpio.alt0_do_i = '0;
    gpio.alt0_oe_i = '0;
    gpio.alt1_do_i = '0;
    gpio.alt1_oe_i = '0;
    user_gpio.do_o = '0;
    user_gpio.oe_o = '0;

    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (2) @(posedge clk_i);

    write_register(8'h00, 32'h0000_0001);
    write_register(8'h10, 32'h0000_0001);
    if ({gpio.oe_o[0], gpio.do_o[0]} !== 2'b11) $fatal(1, "rib software GPIO is not active");

    user_gpio.do_o[0] = 1'b0;
    user_gpio.oe_o[0] = 1'b1;
    select_user_gpio(32'h0000_0001);
    if ({gpio.oe_o[0], gpio.do_o[0]} !== 2'b10) $fatal(1, "user GPIO was not selected");
    read_register(8'h30, read_data);
    if (read_data !== 32'h0000_0001) $fatal(1, "USER_SEL readback is incorrect");
    read_register(8'h38, read_data);
    if (read_data !== 32'h0000_0001) $fatal(1, "USER_STATUS is not active after handoff");

    gpio.di_i[0] = 1'b1;
    #1;
    if (user_gpio.di_i[0] !== 1'b1) $fatal(1, "user GPIO input path is disconnected");

    write_register(8'h34, 32'h0000_0001);
    read_register(8'h34, read_data);
    if (read_data !== 32'h0000_0001) $fatal(1, "USER_LOCK is not write-one-set");
    write_register(8'h30, '0);
    if ({gpio.oe_o[0], gpio.do_o[0]} !== 2'b10) $fatal(1, "USER_LOCK did not preserve ownership");
    read_register(8'h30, read_data);
    if (read_data !== 32'h0000_0001) $fatal(1, "locked USER_SEL changed");

    gpio.alt0_do_i[1] = 1'b1;
    gpio.alt0_oe_i[1] = 1'b1;
    write_register(8'h28, 32'h0000_0002);
    if ({gpio.oe_o[1], gpio.do_o[1]} !== 2'b11) $fatal(1, "alternate GPIO mode regressed");

    write_register(8'h04, 32'h0000_0001);
    write_register(8'h08, 32'h0000_0001);
    write_register(8'h0C, 32'h0000_0001);
    if ({gpio.cs_o[0], gpio.pu_o[0], gpio.pd_o[0]} !== 3'b111)
      $fatal(1, "rib GPIO electrical controls changed under user ownership");

    $display("GPIO user ownership test passed");
    $finish;
  end
endmodule
