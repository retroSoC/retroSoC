`timescale 1ns / 1ps

module clint_tb;
  logic          clk_i = 1'b0;
  logic          ref_clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic          tick_i = 1'b0;
  logic          timebase_tick;
  logic   [31:0] value;
  integer        timebase_tick_count = 0;
  ribp_if ribp ();
  clint_if #(.HART_NUM(2)) clint ();

  always #5 clk_i = ~clk_i;
  always #2 ref_clk_i = ~ref_clk_i;

  always @(posedge clk_i) begin
    if (timebase_tick) timebase_tick_count <= timebase_tick_count + 1;
  end

  clint_timebase #(
      .REF_CLK_HZ (4),
      .TIMEBASE_HZ(1)
  ) u_timebase (
      .ref_clk_i  (ref_clk_i),
      .ref_rst_n_i(rst_n_i),
      .sys_clk_i  (clk_i),
      .sys_rst_n_i(rst_n_i),
      .tick_o     (timebase_tick)
  );

  ribp_clint #(
      .HART_NUM(2)
  ) u_dut (
      .clk_i,
      .rst_n_i,
      .timebase_tick_i(tick_i),
      .ribp,
      .clint
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

  task automatic pulse_tick;
    begin
      @(negedge clk_i);
      tick_i = 1'b1;
      @(negedge clk_i);
      tick_i = 1'b0;
    end
  endtask

  initial begin
    ribp.valid = 1'b0;
    ribp.addr  = '0;
    ribp.wdata = '0;
    ribp.wstrb = '0;

    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;

    ribp_read(32'h0000_0000, value, 1'b0);
    if (value != 32'd0 || clint.software_irq_o != 2'b00) begin
      $fatal(1, "MSIP reset state is invalid");
    end
    ribp_read(32'h0000_4000, value, 1'b0);
    if (value != 32'hFFFF_FFFF) $fatal(1, "MTIMECMP low reset state is invalid");
    ribp_read(32'h0000_4004, value, 1'b0);
    if (value != 32'hFFFF_FFFF || clint.timer_irq_o != 2'b00) begin
      $fatal(1, "MTIMECMP high reset state is invalid");
    end

    ribp_write(32'h0000_0004, 32'h0000_0001, 4'h1, 1'b0);
    if (clint.software_irq_o != 2'b10) $fatal(1, "hart 1 MSIP did not assert");
    ribp_write(32'h0000_0004, 32'h0000_0000, 4'h1, 1'b0);
    if (clint.software_irq_o != 2'b00) $fatal(1, "hart 1 MSIP did not clear");

    ribp_write(32'h0000_BFFC, 32'd0, 4'hF, 1'b0);
    ribp_write(32'h0000_BFF8, 32'd10, 4'hF, 1'b0);
    ribp_read(32'h0000_BFF8, value, 1'b0);
    if (value != 32'd10) $fatal(1, "MTIME write/read failed: %h", value);

    ribp_write(32'h0000_4004, 32'd0, 4'hF, 1'b0);
    ribp_write(32'h0000_4000, 32'd12, 4'hF, 1'b0);
    pulse_tick();
    pulse_tick();
    repeat (2) @(posedge clk_i);
    if (clint.timer_irq_o[0] != 1'b1) $fatal(1, "hart 0 timer IRQ did not assert");
    if (clint.timer_irq_o[1] != 1'b0) $fatal(1, "hart 1 timer IRQ asserted unexpectedly");

    ribp_write(32'h0000_4001, 32'd0, 4'hF, 1'b1);
    ribp_read(32'h0000_0010, value, 1'b1);
    if (value != 32'd0) $fatal(1, "invalid read did not return zero");

    repeat (20) @(posedge clk_i);
    if (timebase_tick_count < 2) begin
      $fatal(1, "reference-clock timebase did not produce synchronized ticks");
    end

    $display("CLINT standard map, multi-hart, IRQ, error, and timebase test passed");
    $finish;
  end
endmodule
