`timescale 1ns / 1ps

module soc_rib_burst_ram_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic   [31:0] memory         [0:31];
  logic   [31:0] expected       [ 0:3];
  integer        index;
  soc_rib_burst_if burst ();
  ram_if ram ();

  always #5 clk_i = ~clk_i;

  always_ff @(posedge clk_i) begin
    ram.rdata <= memory[ram.addr];
    if (ram.wstrb[0]) memory[ram.addr][7:0] <= ram.wdata[7:0];
    if (ram.wstrb[1]) memory[ram.addr][15:8] <= ram.wdata[15:8];
    if (ram.wstrb[2]) memory[ram.addr][23:16] <= ram.wdata[23:16];
    if (ram.wstrb[3]) memory[ram.addr][31:24] <= ram.wdata[31:24];
  end

  soc_rib_burst_ram u_dut (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .burst  (burst),
      .ram    (ram)
  );

  task automatic issue_command(input logic write);
    begin
      @(negedge clk_i);
      burst.cmd_addr  = 32'h3000_0000;
      burst.cmd_write = write;
      burst.cmd_len   = `SOC_RIB_BURST_INCR4;
      burst.cmd_valid = 1'b1;
      while (!burst.cmd_ready) @(posedge clk_i);
      @(negedge clk_i);
      burst.cmd_valid = 1'b0;
    end
  endtask

  initial begin
    for (index = 0; index < 32; index = index + 1) memory[index] = '0;
    for (index = 0; index < 4; index = index + 1) begin
      expected[index] = 32'hA500_1000 + index;
    end
    burst.cmd_valid = 1'b0;
    burst.cmd_addr  = '0;
    burst.cmd_write = 1'b0;
    burst.cmd_len   = '0;
    burst.w_valid   = 1'b0;
    burst.wdata     = '0;
    burst.wstrb     = '0;
    burst.wlast     = 1'b0;
    burst.rsp_ready = 1'b1;

    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_n_i = 1'b1;

    issue_command(1'b1);
    for (index = 0; index < 4; index = index + 1) begin
      burst.w_valid = 1'b1;
      burst.wdata   = expected[index];
      burst.wstrb   = 4'hF;
      burst.wlast   = index == 3;
      while (!burst.w_ready) @(posedge clk_i);
      @(negedge clk_i);
    end
    burst.w_valid = 1'b0;
    burst.wlast   = 1'b0;
    while (!burst.rsp_valid) @(posedge clk_i);
    if (burst.resp_err || !burst.rsp_last || burst.rsp_beat != 2'd3) begin
      $fatal(1, "invalid SRAM write response");
    end
    @(negedge clk_i);

    burst.rsp_ready = 1'b0;
    issue_command(1'b0);
    while (!burst.rsp_valid) @(negedge clk_i);
    burst.rsp_ready = 1'b1;
    for (index = 0; index < 4; index = index + 1) begin
      if (burst.rdata !== expected[index] || burst.rsp_beat !== index[1:0] ||
          burst.rsp_last !== (index == 3) || burst.resp_err) begin
        $fatal(1, "invalid SRAM read response beat=%0d data=%h expected=%h rsp_beat=%0d last=%0b",
               index, burst.rdata, expected[index], burst.rsp_beat, burst.rsp_last);
      end
      @(posedge clk_i);
      @(negedge clk_i);
      if ((index != 3) && !burst.rsp_valid) begin
        $fatal(1, "SRAM inserted a response bubble at beat %0d", index + 1);
      end
    end

    burst.rsp_ready = 1'b0;
    issue_command(1'b0);
    while (!burst.rsp_valid) @(negedge clk_i);
    repeat (4) begin
      @(posedge clk_i);
      if (!burst.rsp_valid || burst.rdata !== expected[0] || burst.rsp_beat != 2'd0) begin
        $fatal(1, "SRAM response changed while stalled");
      end
    end
    @(negedge clk_i);
    burst.rsp_ready = 1'b1;
    for (index = 0; index < 4; index = index + 1) begin
      if (burst.rdata !== expected[index] || burst.rsp_beat !== index[1:0]) begin
        $fatal(1, "SRAM lost data after backpressure beat=%0d data=%h rsp_beat=%0d", index,
               burst.rdata, burst.rsp_beat);
      end
      @(posedge clk_i);
      @(negedge clk_i);
      while ((index != 3) && !burst.rsp_valid) @(negedge clk_i);
    end

    $display("RIB burst SRAM pipeline test passed");
    $finish;
  end
endmodule
