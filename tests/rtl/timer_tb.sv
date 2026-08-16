`timescale 1ns / 1ps

module timer_tb;
  localparam logic [31:0] CTRL_ENABLE = 32'h0000_0001;
  localparam logic [31:0] CTRL_PERIODIC = 32'h0000_0002;
  localparam logic [31:0] CTRL_ONE_SHOT = 32'h0000_0004;
  localparam logic [31:0] CTRL_DIRECTION_DOWN = 32'h0000_0008;
  localparam logic [31:0] CTRL_DEBUG_FREEZE = 32'h0000_0010;
  localparam logic [31:0] CTRL_COMPARE_ENABLE = 32'h0000_0060;

  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  logic debug_halted_i = 1'b0;
  logic irq_o;
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  apb4_timer u_dut (
      .clk_i,
      .rst_n_i,
      .debug_halted_i,
      .apb4,
      .irq_o
  );

  task automatic apb4_write(input logic [31:0] address, input logic [31:0] data,
                            input logic [3:0] strobe, input logic expected_error);
    begin
      @(negedge clk_i);
      apb4.paddr   = address;
      apb4.pwdata  = data;
      apb4.pstrb   = strobe;
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

  task automatic apb4_read(input logic [31:0] address, output logic [31:0] data,
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

  task automatic wait_inactive;
    logic [31:0] status;
    int          cycles;
    begin
      status = '1;
      cycles = 0;
      while ((status[0] != 1'b0) && (cycles < 64)) begin
        apb4_read(32'h0000_001C, status, 1'b0);
        cycles++;
      end
      if (status[0] != 1'b0) $fatal(1, "timer did not enter inactive state");
    end
  endtask

  logic [31:0] value;
  logic [31:0] frozen_value;
  logic [31:0] status;
  logic [31:0] intr_state;

  initial begin
    apb4.psel    = 1'b0;
    apb4.penable = 1'b0;
    apb4.pwrite  = 1'b0;
    apb4.paddr   = '0;
    apb4.pwdata  = '0;
    apb4.pstrb   = '0;
    apb4.pprot   = '0;

    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;

    apb4_read(32'h0000_00F8, value, 1'b0);
    if (value != 32'h0002_0000) $fatal(1, "unexpected timer version %h", value);
    apb4_read(32'h0000_00FC, value, 1'b0);
    if (value != 32'h00F2_1020) $fatal(1, "unexpected timer capability %h", value);
    apb4_read(32'h0000_0100, value, 1'b1);
    if (value != 32'd0) $fatal(1, "invalid read did not return zero");
    apb4_read(32'h0000_0002, value, 1'b1);
    apb4_write(32'h0000_0008, 32'h1234_5678, 4'hF, 1'b1);
    apb4_read(32'h0000_002C, value, 1'b1);
    apb4_write(32'h0000_0000, 32'h0000_0006, 4'hF, 1'b1);

    // Free-running mode wraps naturally and stops without changing its value.
    apb4_write(32'h0000_0000, CTRL_ENABLE, 4'hF, 1'b0);
    repeat (6) @(posedge clk_i);
    apb4_read(32'h0000_0008, value, 1'b0);
    if (value == 32'd0) $fatal(1, "free-running timer did not advance");
    apb4_write(32'h0000_0000, 32'd0, 4'hF, 1'b0);

    // Up-counting periodic mode with both compare channels.
    apb4_write(32'h0000_0010, 32'd1, 4'hF, 1'b0);
    apb4_write(32'h0000_0014, 32'd1, 4'hF, 1'b0);
    apb4_write(32'h0000_0018, 32'd2, 4'hF, 1'b0);
    apb4_write(32'h0000_0004, 32'd3, 4'hF, 1'b0);
    apb4_write(32'h0000_0024, 32'h0000_0007, 4'hF, 1'b0);
    apb4_write(32'h0000_0000, CTRL_ENABLE | CTRL_PERIODIC | CTRL_COMPARE_ENABLE, 4'hF, 1'b0);
    apb4_write(32'h0000_0010, 32'd0, 4'hF, 1'b1);
    repeat (12) @(posedge clk_i);
    apb4_read(32'h0000_0020, intr_state, 1'b0);
    if (intr_state[2:0] != 3'b111 || !irq_o) begin
      $fatal(1, "periodic compare/timeout state invalid: %h irq=%b", intr_state, irq_o);
    end
    apb4_write(32'h0000_0020, 32'h0000_0007, 4'h1, 1'b0);
    apb4_write(32'h0000_0000, CTRL_PERIODIC | CTRL_COMPARE_ENABLE, 4'hF, 1'b0);

    // Down-counting one-shot stops at zero and leaves a sticky timeout.
    apb4_write(32'h0000_0004, 32'd2, 4'hF, 1'b0);
    apb4_write(32'h0000_0020, 32'h0000_0007, 4'h1, 1'b0);
    apb4_write(32'h0000_0000, CTRL_ENABLE | CTRL_ONE_SHOT | CTRL_DIRECTION_DOWN, 4'hF, 1'b0);
    wait_inactive();
    apb4_read(32'h0000_0008, value, 1'b0);
    apb4_read(32'h0000_0020, intr_state, 1'b0);
    if (value != 32'd0 || !intr_state[0]) begin
      $fatal(1, "one-shot completion invalid value=%h state=%h", value, intr_state);
    end

    // Background load updates the next down-counting period without an immediate reload.
    apb4_write(32'h0000_0020, 32'h0000_0007, 4'h1, 1'b0);
    apb4_write(32'h0000_0004, 32'd5, 4'hF, 1'b0);
    apb4_write(32'h0000_0010, 32'd3, 4'hF, 1'b0);
    apb4_write(32'h0000_0000, CTRL_ENABLE | CTRL_PERIODIC | CTRL_DIRECTION_DOWN, 4'hF, 1'b0);
    apb4_read(32'h0000_0008, value, 1'b0);
    apb4_write(32'h0000_000C, 32'd1, 4'hF, 1'b0);
    apb4_read(32'h0000_0008, frozen_value, 1'b0);
    if (frozen_value == 32'd1) $fatal(1, "BGLOAD changed the live counter immediately");
    repeat (32) @(posedge clk_i);
    apb4_read(32'h0000_0008, value, 1'b0);
    if (value > 32'd1) $fatal(1, "BGLOAD was not used by the next period: %h", value);
    apb4_write(32'h0000_0000, CTRL_PERIODIC | CTRL_DIRECTION_DOWN, 4'hF, 1'b0);

    // Debug freeze stops both prescaler and counter while keeping APB4 readable.
    apb4_write(32'h0000_0004, 32'd20, 4'hF, 1'b0);
    apb4_write(32'h0000_0010, 32'd0, 4'hF, 1'b0);
    apb4_write(32'h0000_0000, CTRL_ENABLE | CTRL_PERIODIC | CTRL_DEBUG_FREEZE, 4'hF, 1'b0);
    debug_halted_i = 1'b1;
    repeat (2) @(posedge clk_i);
    apb4_read(32'h0000_0008, frozen_value, 1'b0);
    repeat (8) @(posedge clk_i);
    apb4_read(32'h0000_0008, value, 1'b0);
    apb4_read(32'h0000_001C, status, 1'b0);
    if (value != frozen_value || status[1:0] != 2'b11) begin
      $fatal(1, "debug freeze invalid before=%h after=%h status=%h", frozen_value, value, status);
    end
    debug_halted_i = 1'b0;
    repeat (4) @(posedge clk_i);
    apb4_read(32'h0000_0008, value, 1'b0);
    if (value == frozen_value) $fatal(1, "timer did not resume after debug halt");

    // Software interrupt test and W1C clear.
    apb4_write(32'h0000_002C, 32'h0000_0006, 4'h1, 1'b0);
    apb4_read(32'h0000_0020, intr_state, 1'b0);
    if ((intr_state[2:1] != 2'b11) || !irq_o) $fatal(1, "interrupt test failed");
    apb4_write(32'h0000_0020, 32'h0000_0007, 4'h1, 1'b0);

    $display("APB4 Timer register, mode, interrupt, and error test passed");
    $finish;
  end
endmodule
