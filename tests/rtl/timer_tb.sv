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
  ribp_if ribp ();

  always #5 clk_i = ~clk_i;

  ribp_timer u_dut (
      .clk_i,
      .rst_n_i,
      .debug_halted_i,
      .ribp,
      .irq_o
  );

  task automatic ribp_write(input logic [31:0] address, input logic [31:0] data,
                            input logic [3:0] strobe, input logic expected_error);
    begin
      @(negedge clk_i);
      ribp.valid = 1'b1;
      ribp.addr  = address;
      ribp.wdata = data;
      ribp.wstrb = strobe;
      do @(negedge clk_i); while (!ribp.ready);
      if (ribp.resp_err !== expected_error) begin
        $fatal(1, "write %h error=%b expected=%b", address, ribp.resp_err, expected_error);
      end
      ribp.valid = 1'b0;
      ribp.wstrb = '0;
    end
  endtask

  task automatic ribp_read(input logic [31:0] address, output logic [31:0] data,
                           input logic expected_error);
    begin
      @(negedge clk_i);
      ribp.valid = 1'b1;
      ribp.addr  = address;
      ribp.wdata = '0;
      ribp.wstrb = '0;
      do @(negedge clk_i); while (!ribp.ready);
      data = ribp.rdata;
      if (ribp.resp_err !== expected_error) begin
        $fatal(1, "read %h error=%b expected=%b", address, ribp.resp_err, expected_error);
      end
      ribp.valid = 1'b0;
    end
  endtask

  task automatic wait_inactive;
    logic [31:0] status;
    int          cycles;
    begin
      status = '1;
      cycles = 0;
      while ((status[0] != 1'b0) && (cycles < 64)) begin
        ribp_read(32'h0000_001C, status, 1'b0);
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
    ribp.valid = 1'b0;
    ribp.addr  = '0;
    ribp.wdata = '0;
    ribp.wstrb = '0;

    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;

    ribp_read(32'h0000_00F8, value, 1'b0);
    if (value != 32'h0002_0000) $fatal(1, "unexpected timer version %h", value);
    ribp_read(32'h0000_00FC, value, 1'b0);
    if (value != 32'h00F2_1020) $fatal(1, "unexpected timer capability %h", value);
    ribp_read(32'h0000_0100, value, 1'b1);
    if (value != 32'd0) $fatal(1, "invalid read did not return zero");
    ribp_read(32'h0000_0002, value, 1'b1);
    ribp_write(32'h0000_0008, 32'h1234_5678, 4'hF, 1'b1);
    ribp_read(32'h0000_002C, value, 1'b1);
    ribp_write(32'h0000_0000, 32'h0000_0006, 4'hF, 1'b1);

    // Free-running mode wraps naturally and stops without changing its value.
    ribp_write(32'h0000_0000, CTRL_ENABLE, 4'hF, 1'b0);
    repeat (6) @(posedge clk_i);
    ribp_read(32'h0000_0008, value, 1'b0);
    if (value == 32'd0) $fatal(1, "free-running timer did not advance");
    ribp_write(32'h0000_0000, 32'd0, 4'hF, 1'b0);

    // Up-counting periodic mode with both compare channels.
    ribp_write(32'h0000_0010, 32'd1, 4'hF, 1'b0);
    ribp_write(32'h0000_0014, 32'd1, 4'hF, 1'b0);
    ribp_write(32'h0000_0018, 32'd2, 4'hF, 1'b0);
    ribp_write(32'h0000_0004, 32'd3, 4'hF, 1'b0);
    ribp_write(32'h0000_0024, 32'h0000_0007, 4'hF, 1'b0);
    ribp_write(32'h0000_0000, CTRL_ENABLE | CTRL_PERIODIC | CTRL_COMPARE_ENABLE, 4'hF, 1'b0);
    ribp_write(32'h0000_0010, 32'd0, 4'hF, 1'b1);
    repeat (12) @(posedge clk_i);
    ribp_read(32'h0000_0020, intr_state, 1'b0);
    if (intr_state[2:0] != 3'b111 || !irq_o) begin
      $fatal(1, "periodic compare/timeout state invalid: %h irq=%b", intr_state, irq_o);
    end
    ribp_write(32'h0000_0020, 32'h0000_0007, 4'h1, 1'b0);
    ribp_write(32'h0000_0000, CTRL_PERIODIC | CTRL_COMPARE_ENABLE, 4'hF, 1'b0);

    // Down-counting one-shot stops at zero and leaves a sticky timeout.
    ribp_write(32'h0000_0004, 32'd2, 4'hF, 1'b0);
    ribp_write(32'h0000_0020, 32'h0000_0007, 4'h1, 1'b0);
    ribp_write(32'h0000_0000, CTRL_ENABLE | CTRL_ONE_SHOT | CTRL_DIRECTION_DOWN, 4'hF, 1'b0);
    wait_inactive();
    ribp_read(32'h0000_0008, value, 1'b0);
    ribp_read(32'h0000_0020, intr_state, 1'b0);
    if (value != 32'd0 || !intr_state[0]) begin
      $fatal(1, "one-shot completion invalid value=%h state=%h", value, intr_state);
    end

    // Background load updates the next down-counting period without an immediate reload.
    ribp_write(32'h0000_0020, 32'h0000_0007, 4'h1, 1'b0);
    ribp_write(32'h0000_0004, 32'd5, 4'hF, 1'b0);
    ribp_write(32'h0000_0010, 32'd3, 4'hF, 1'b0);
    ribp_write(32'h0000_0000, CTRL_ENABLE | CTRL_PERIODIC | CTRL_DIRECTION_DOWN, 4'hF, 1'b0);
    ribp_read(32'h0000_0008, value, 1'b0);
    ribp_write(32'h0000_000C, 32'd1, 4'hF, 1'b0);
    ribp_read(32'h0000_0008, frozen_value, 1'b0);
    if (frozen_value == 32'd1) $fatal(1, "BGLOAD changed the live counter immediately");
    repeat (32) @(posedge clk_i);
    ribp_read(32'h0000_0008, value, 1'b0);
    if (value > 32'd1) $fatal(1, "BGLOAD was not used by the next period: %h", value);
    ribp_write(32'h0000_0000, CTRL_PERIODIC | CTRL_DIRECTION_DOWN, 4'hF, 1'b0);

    // Debug freeze stops both prescaler and counter while keeping RIBP readable.
    ribp_write(32'h0000_0004, 32'd20, 4'hF, 1'b0);
    ribp_write(32'h0000_0010, 32'd0, 4'hF, 1'b0);
    ribp_write(32'h0000_0000, CTRL_ENABLE | CTRL_PERIODIC | CTRL_DEBUG_FREEZE, 4'hF, 1'b0);
    debug_halted_i = 1'b1;
    repeat (2) @(posedge clk_i);
    ribp_read(32'h0000_0008, frozen_value, 1'b0);
    repeat (8) @(posedge clk_i);
    ribp_read(32'h0000_0008, value, 1'b0);
    ribp_read(32'h0000_001C, status, 1'b0);
    if (value != frozen_value || status[1:0] != 2'b11) begin
      $fatal(1, "debug freeze invalid before=%h after=%h status=%h", frozen_value, value, status);
    end
    debug_halted_i = 1'b0;
    repeat (4) @(posedge clk_i);
    ribp_read(32'h0000_0008, value, 1'b0);
    if (value == frozen_value) $fatal(1, "timer did not resume after debug halt");

    // Software interrupt test and W1C clear.
    ribp_write(32'h0000_002C, 32'h0000_0006, 4'h1, 1'b0);
    ribp_read(32'h0000_0020, intr_state, 1'b0);
    if ((intr_state[2:1] != 2'b11) || !irq_o) $fatal(1, "interrupt test failed");
    ribp_write(32'h0000_0020, 32'h0000_0007, 4'h1, 1'b0);

    $display("RIBP Timer register, mode, interrupt, and error test passed");
    $finish;
  end
endmodule
