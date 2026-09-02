`timescale 1ns / 1ps

module hp_mailbox_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        lp_irq_o;
  logic        hp_irq_o;
  logic [31:0] value;
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  apb4_hp_mailbox u_dut (
      .clk_i,
      .rst_n_i,
      .apb4,
      .lp_irq_o,
      .hp_irq_o
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

    apb_read(32'h0, value);
    if (value != 32'h0001_0000) $fatal(1, "mailbox version mismatch");
    apb_write(32'h44, 32'h1);
    apb_write(32'h10, 32'h1);
    apb_write(32'h18, 32'h1234);
    apb_write(32'h1c, 32'h1);
    if (!hp_irq_o) $fatal(1, "LP-to-HP doorbell did not assert");
    apb_read(32'h18, value);
    if (value != 32'h1234) $fatal(1, "LP sequence did not persist");
    apb_write(32'h40, 32'h1);
    if (hp_irq_o) $fatal(1, "HP interrupt did not clear");

    apb_write(32'h34, 32'h1);
    apb_write(32'h20, 32'h1);
    apb_write(32'h2c, 32'h1);
    if (!lp_irq_o) $fatal(1, "HP-to-LP doorbell did not assert");
    apb_write(32'h30, 32'h1);
    if (lp_irq_o) $fatal(1, "LP interrupt did not clear");

    $display("HP mailbox register and doorbell test passed");
    $finish;
  end
endmodule

