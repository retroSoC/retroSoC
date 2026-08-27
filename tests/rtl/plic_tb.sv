`timescale 1ns / 1ps

module plic_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic [31:0] source_i = '0;
  logic [ 1:0] context_irq_o;
  logic [31:0] value;
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  apb4_plic u_dut (
      .clk_i,
      .rst_n_i,
      .source_i,
      .apb4,
      .context_irq_o
  );

  task automatic apb_write(input logic [31:0] address, input logic [31:0] data);
    begin
      @(negedge clk_i);
      apb4.paddr   = address;
      apb4.pwdata  = data;
      apb4.pstrb   = 4'hf;
      apb4.pwrite  = 1'b1;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr) $fatal(1, "PLIC write failed at %h", address);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
    end
  endtask

  task automatic apb_read(input logic [31:0] address, output logic [31:0] data);
    begin
      @(negedge clk_i);
      apb4.paddr   = address;
      apb4.pstrb   = '0;
      apb4.pwrite  = 1'b0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr) $fatal(1, "PLIC read failed at %h", address);
      data         = apb4.prdata;
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  initial begin
    apb4.psel    = 1'b0;
    apb4.penable = 1'b0;
    apb4.pwrite  = 1'b0;
    apb4.paddr   = '0;
    apb4.pwdata  = '0;
    apb4.pstrb   = '0;
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;

    apb_write(32'h0000_0004, 32'd3);
    apb_write(32'h0000_0008, 32'd5);
    apb_write(32'h0000_2080, 32'h0000_0006);
    apb_write(32'h0020_1000, 32'd0);
    source_i[1] = 1'b1;
    source_i[2] = 1'b1;
    repeat (2) @(posedge clk_i);
    if (!context_irq_o[1]) $fatal(1, "supervisor context IRQ did not assert");
    apb_read(32'h0020_1004, value);
    if (value != 32'd2) $fatal(1, "highest-priority source was not claimed");
    source_i[2] = 1'b0;
    apb_write(32'h0020_1004, 32'd2);
    repeat (2) @(posedge clk_i);
    apb_read(32'h0020_1004, value);
    if (value != 32'd1) $fatal(1, "remaining source was not claimed");
    source_i[1] = 1'b0;
    apb_write(32'h0020_1004, 32'd1);
    repeat (2) @(posedge clk_i);
    if (context_irq_o[1]) $fatal(1, "supervisor context IRQ did not clear");

    $display("PLIC priority, claim, and completion test passed");
    $finish;
  end
endmodule

