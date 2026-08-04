`timescale 1ns / 1ps

module soc_rib_ram_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic   [31:0] memory         [0:31];
  logic   [31:0] expected       [ 0:3];
  integer        index;
  soc_rib_if rib ();
  ram_if ram ();

  always #5 clk_i = ~clk_i;

  always_ff @(posedge clk_i) begin
    ram.rdata <= memory[ram.addr];
    if (ram.wstrb[0]) memory[ram.addr][7:0] <= ram.wdata[7:0];
    if (ram.wstrb[1]) memory[ram.addr][15:8] <= ram.wdata[15:8];
    if (ram.wstrb[2]) memory[ram.addr][23:16] <= ram.wdata[23:16];
    if (ram.wstrb[3]) memory[ram.addr][31:24] <= ram.wdata[31:24];
  end

  soc_rib_ram u_dut (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .rib    (rib),
      .ram    (ram)
  );

  task automatic issue_command(input logic write);
    begin
      @(negedge clk_i);
      rib.cmd_addr  = 32'h3000_0000;
      rib.cmd_write = write;
      rib.cmd_len   = `SOC_RIB_LEN_INCR4;
      rib.cmd_valid = 1'b1;
      while (!rib.cmd_ready) @(posedge clk_i);
      @(negedge clk_i);
      rib.cmd_valid = 1'b0;
    end
  endtask

  initial begin
    for (index = 0; index < 32; index = index + 1) memory[index] = '0;
    for (index = 0; index < 4; index = index + 1) begin
      expected[index] = 32'hA500_1000 + index;
    end
    rib.cmd_valid = 1'b0;
    rib.cmd_addr  = '0;
    rib.cmd_write = 1'b0;
    rib.cmd_len   = '0;
    rib.w_valid   = 1'b0;
    rib.wdata     = '0;
    rib.wstrb     = '0;
    rib.wlast     = 1'b0;
    rib.rsp_ready = 1'b1;

    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_n_i = 1'b1;

    issue_command(1'b1);
    for (index = 0; index < 4; index = index + 1) begin
      rib.w_valid = 1'b1;
      rib.wdata   = expected[index];
      rib.wstrb   = 4'hF;
      rib.wlast   = index == 3;
      while (!rib.w_ready) @(posedge clk_i);
      @(negedge clk_i);
    end
    rib.w_valid = 1'b0;
    rib.wlast   = 1'b0;
    while (!rib.rsp_valid) @(posedge clk_i);
    if (rib.resp_err || !rib.rsp_last || rib.rsp_beat != 2'd3) begin
      $fatal(1, "invalid SRAM write response");
    end
    @(negedge clk_i);

    rib.rsp_ready = 1'b0;
    issue_command(1'b0);
    while (!rib.rsp_valid) @(negedge clk_i);
    rib.rsp_ready = 1'b1;
    for (index = 0; index < 4; index = index + 1) begin
      if (rib.rdata !== expected[index] || rib.rsp_beat !== index[1:0] ||
          rib.rsp_last !== (index == 3) || rib.resp_err) begin
        $fatal(1, "invalid SRAM read response beat=%0d data=%h expected=%h rsp_beat=%0d last=%0b",
               index, rib.rdata, expected[index], rib.rsp_beat, rib.rsp_last);
      end
      @(posedge clk_i);
      @(negedge clk_i);
      if ((index != 3) && !rib.rsp_valid) begin
        $fatal(1, "SRAM inserted a response bubble at beat %0d", index + 1);
      end
    end

    rib.rsp_ready = 1'b0;
    issue_command(1'b0);
    while (!rib.rsp_valid) @(negedge clk_i);
    repeat (4) begin
      @(posedge clk_i);
      if (!rib.rsp_valid || rib.rdata !== expected[0] || rib.rsp_beat != 2'd0) begin
        $fatal(1, "SRAM response changed while stalled");
      end
    end
    @(negedge clk_i);
    rib.rsp_ready = 1'b1;
    for (index = 0; index < 4; index = index + 1) begin
      if (rib.rdata !== expected[index] || rib.rsp_beat !== index[1:0]) begin
        $fatal(1, "SRAM lost data after backpressure beat=%0d data=%h rsp_beat=%0d", index,
               rib.rdata, rib.rsp_beat);
      end
      @(posedge clk_i);
      @(negedge clk_i);
      while ((index != 3) && !rib.rsp_valid) @(negedge clk_i);
    end

    $display("RIB SRAM pipeline test passed");
    $finish;
  end
endmodule
