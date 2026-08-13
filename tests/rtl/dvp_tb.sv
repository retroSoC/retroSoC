`timescale 1ns / 1ps

module dvp_tb;
  logic        clk_i = 1'b0;
  logic        pclk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        href_i = 1'b0;
  logic        vsync_i = 1'b0;
  logic [ 7:0] dat_i = 8'd0;
  logic [31:0] ribp_rdata;
  logic        irq_o;
  ribp_if ribp ();
  axi4_stream_if #(
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .DEST_WIDTH(1),
      .USER_WIDTH(1)
  ) axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  dvp_if dvp ();

  assign dvp.pclk_i  = pclk_i;
  assign dvp.href_i  = href_i;
  assign dvp.vsync_i = vsync_i;
  assign dvp.dat_i   = dat_i;
  assign axis.tready = 1'b1;
  always #5 clk_i = ~clk_i;
  always #10 pclk_i = ~pclk_i;

  ribp_dvp u_dut (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (ribp),
      .rx_axis(axis),
      .dvp    (dvp),
      .irq_o  (irq_o)
  );

  task automatic write(input logic [31:0] address, input logic [31:0] data);
    begin
      @(negedge clk_i);
      ribp.valid = 1'b1;
      ribp.addr  = address;
      ribp.wdata = data;
      ribp.wstrb = 4'hf;
      do @(negedge clk_i); while (!ribp.ready);
      if (ribp.resp_err) $fatal(1, "unexpected write error at %h", address);
      ribp.valid = 1'b0;
      ribp.wstrb = '0;
    end
  endtask

  task automatic read(input logic [31:0] address, output logic [31:0] data);
    begin
      @(negedge clk_i);
      ribp.valid = 1'b1;
      ribp.addr  = address;
      ribp.wdata = '0;
      ribp.wstrb = '0;
      do @(negedge clk_i); while (!ribp.ready);
      data       = ribp.rdata;
      ribp.valid = 1'b0;
    end
  endtask

  task automatic frame(input int lines, input int pixels);
    begin
      vsync_i = 1'b1;
      repeat (3) @(posedge pclk_i);
      vsync_i = 1'b0;
      repeat (2) @(posedge pclk_i);
      for (int line = 0; line < lines; line++) begin
        href_i = 1'b1;
        for (int index = 0; index < pixels * 2; index++) begin
          dat_i = index + line * 8;
          @(posedge pclk_i);
        end
        href_i = 1'b0;
        repeat (2) @(posedge pclk_i);
      end
      vsync_i = 1'b1;
      repeat (3) @(posedge pclk_i);
      vsync_i = 1'b0;
    end
  endtask

  task automatic check_frame(input int lines, input int pixels, input int expected_beats);
    begin
      beats = 0;
      frame(lines, pixels);
      repeat (80) @(posedge clk_i);
      if (beats != expected_beats)
        $fatal(1, "unexpected AXI beat count=%0d expected=%0d", beats, expected_beats);
    end
  endtask

  logic [31:0] value;
  int          beats;
  always @(posedge clk_i) begin
    if (axis.tvalid && axis.tready) begin
      beats = beats + 1;
      if (beats == 1 && !axis.tuser[0]) $fatal(1, "SOF missing");
      if ((beats == 2 || beats == 4) && !axis.tlast) $fatal(1, "EOL missing");
    end
  end
  initial begin
    ribp.valid = 1'b0;
    ribp.addr  = '0;
    ribp.wdata = '0;
    ribp.wstrb = '0;
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    read(32'h0000_00f8, value);
    if (value != 32'h0002_0000) $fatal(1, "bad DVP version %h", value);
    read(32'h0000_0100, value);
    if (!ribp.resp_err) $fatal(1, "invalid DVP access was accepted");
    write(32'h0000_0018, {16'd2, 16'd4});
    write(32'h0000_000c, 32'd1);
    write(32'h0000_0000, 32'd3);
    repeat (50) @(posedge pclk_i);
    check_frame(2, 4, 4);
    read(32'h0000_0024, value);
    if (value == 0)
      $fatal(1, "frame count/beats invalid count=%h beats=%0d", value, beats);
    write(32'h0000_0018, {16'd2, 16'd3});
    check_frame(1, 3, 2);
    write(32'h0000_0048, 32'h0000_0004);
    read(32'h0000_003c, value);
    if (ribp.resp_err) $fatal(1, "DVP interrupt read failed");
    $display("RIBP DVP V2 capture test passed");
    $finish;
  end
endmodule
