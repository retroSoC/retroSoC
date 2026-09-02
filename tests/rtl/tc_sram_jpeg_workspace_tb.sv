`timescale 1ns / 1ps

module tc_sram_jpeg_workspace_tb;
  logic        clk = 1'b0;
  logic        row_cs;
  logic [ 5:0] row_addr;
  logic [63:0] row_data_i;
  logic        row_wren;
  logic [63:0] row_data_o;
  logic        coeff_a_cs;
  logic [ 5:0] coeff_a_addr;
  logic [31:0] coeff_a_data_i;
  logic        coeff_a_wren;
  logic [31:0] coeff_a_data_o;
  logic        coeff_b_cs;
  logic [ 5:0] coeff_b_addr;
  logic [31:0] coeff_b_data_i;
  logic        coeff_b_wren;
  logic [31:0] coeff_b_data_o;

  always #5 clk = ~clk;

  tc_sram_64x64 u_row_sram (
      .clk_i (clk),
      .cs_i  (row_cs),
      .addr_i(row_addr),
      .data_i(row_data_i),
      .wren_i(row_wren),
      .data_o(row_data_o)
  );

  tc_sram_64x32_2p u_coeff_sram (
      .clk_i   (clk),
      .a_cs_i  (coeff_a_cs),
      .a_addr_i(coeff_a_addr),
      .a_data_i(coeff_a_data_i),
      .a_wren_i(coeff_a_wren),
      .a_data_o(coeff_a_data_o),
      .b_cs_i  (coeff_b_cs),
      .b_addr_i(coeff_b_addr),
      .b_data_i(coeff_b_data_i),
      .b_wren_i(coeff_b_wren),
      .b_data_o(coeff_b_data_o)
  );

  initial begin
    row_cs         = 1'b0;
    row_addr       = '0;
    row_data_i     = '0;
    row_wren       = 1'b0;
    coeff_a_cs     = 1'b0;
    coeff_a_addr   = '0;
    coeff_a_data_i = '0;
    coeff_a_wren   = 1'b0;
    coeff_b_cs     = 1'b0;
    coeff_b_addr   = '0;
    coeff_b_data_i = '0;
    coeff_b_wren   = 1'b0;

    @(negedge clk);
    row_cs         = 1'b1;
    row_wren       = 1'b1;
    row_addr       = 6'd47;
    row_data_i     = 64'h0123_4567_89ab_cdef;
    coeff_a_cs     = 1'b1;
    coeff_a_wren   = 1'b1;
    coeff_a_addr   = 6'd3;
    coeff_a_data_i = 32'h1122_3344;
    coeff_b_cs     = 1'b1;
    coeff_b_wren   = 1'b1;
    coeff_b_addr   = 6'd61;
    coeff_b_data_i = 32'haabb_ccdd;

    @(negedge clk);
    row_wren     = 1'b0;
    coeff_a_wren = 1'b0;
    coeff_b_wren = 1'b0;

    @(negedge clk);
    if (row_data_o !== 64'h0123_4567_89ab_cdef || coeff_a_data_o !== 32'h1122_3344 ||
        coeff_b_data_o !== 32'haabb_ccdd) begin
      $fatal(1, "JPEG SRAM wrapper data mismatch");
    end
    row_cs     = 1'b0;
    coeff_a_cs = 1'b0;
    coeff_b_cs = 1'b0;
    $display("JPEG SRAM workspace wrapper test passed");
    $finish;
  end
endmodule
