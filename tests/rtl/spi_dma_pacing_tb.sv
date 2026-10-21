`timescale 1ns / 1ps
module spi_dma_pacing_tb;
  logic clk_i = 0, rst_n_i = 0, enable_i = 1, dma_error_i = 0;
  logic [31:0] tx_binding_i = 32'h80000003, rx_binding_i = 32'h80000002;
  logic [1:0] dma_start_pending_i = 0, dma_status_i = 0;
  logic [1:0] credit_valid_i = 0, credit_retire_i = 0, credit_commit_i = 0;
  logic [1:0] credit_valid_o, credit_retire_o, credit_pending_o;
  logic [3:0] dma_status_o;
  logic credit_fault_o, busy_o;
  always #5 clk_i = !clk_i;
  spi_dma_pacing u_dut (.*);
  task automatic tick;
    @(posedge clk_i);
    #1;
  endtask
  initial begin
    repeat (2) tick();
    rst_n_i = 1;
    tick();
    credit_valid_i = 2'b01;
    #1;
    if (credit_valid_o != 2'b01 || credit_pending_o != 2'b01) $fatal(1, "credit admission");
    credit_commit_i = 2'b01;
    tick();
    credit_valid_i  = 0;
    credit_commit_i = 0;
    #1;
    if (credit_pending_o != 2'b01 || credit_valid_o != 0 || !busy_o) $fatal(1, "credit commit");
    credit_retire_i = 2'b01;
    tick();
    credit_retire_i = 0;
    if (credit_pending_o != 0 || busy_o) $fatal(1, "credit retire");
    tx_binding_i = 32'h80000002;
    #1;
    if (!credit_fault_o) $fatal(1, "binding conflict");
    tx_binding_i   = 32'h80000003;
    enable_i       = 0;
    credit_valid_i = 2'b10;
    #1;
    if (!credit_fault_o || credit_valid_o != 0) $fatal(1, "disabled admission");
    $display("SPI_P2_PASS spi_dma_pacing_tb");
    $finish;
  end
  initial begin
    #1000;
    $fatal(1, "SIM_TEST_TIMEOUT spi_dma_pacing_tb");
  end
endmodule
