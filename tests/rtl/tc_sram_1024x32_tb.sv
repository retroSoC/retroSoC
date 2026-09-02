`timescale 1ns / 1ps

module tc_sram_1024x32_tb;
  logic        clk_i = 1'b0;
  logic        cs_i = 1'b0;
  logic [ 9:0] addr_i = '0;
  logic [31:0] data_i = '0;
  logic [ 3:0] mask_i = '0;
  logic        wren_i = 1'b0;
  logic [31:0] data_o;

  always #5 clk_i = ~clk_i;

  tc_sram_1024x32 u_dut (
      .clk_i (clk_i),
      .cs_i  (cs_i),
      .addr_i(addr_i),
      .data_i(data_i),
      .mask_i(mask_i),
      .wren_i(wren_i),
      .data_o(data_o)
  );

  task automatic write_word(input logic [9:0] address, input logic [31:0] data,
                            input logic [3:0] mask);
    begin
      @(negedge clk_i);
      cs_i   = 1'b1;
      addr_i = address;
      data_i = data;
      mask_i = mask;
      wren_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      cs_i   = 1'b0;
      wren_i = 1'b0;
      mask_i = '0;
    end
  endtask

  task automatic read_word(input logic [9:0] address, input logic [31:0] expected);
    begin
      @(negedge clk_i);
      cs_i   = 1'b1;
      addr_i = address;
      wren_i = 1'b0;
      @(posedge clk_i);
      @(negedge clk_i);
      if (data_o !== expected) begin
        $fatal(1, "1024x32 SRAM data=%08x expected=%08x", data_o, expected);
      end
      cs_i = 1'b0;
    end
  endtask

  task automatic expect_read_hold(input logic [9:0] idle_address, input logic [31:0] expected);
    begin
      @(negedge clk_i);
      cs_i   = 1'b0;
      addr_i = idle_address;
      @(posedge clk_i);
      @(negedge clk_i);
      if (data_o !== expected) begin
        $fatal(1, "1024x32 SRAM held data=%08x expected=%08x", data_o, expected);
      end
    end
  endtask

  initial begin
    write_word(10'h000, 32'hCAFE_BABE, 4'hF);
    write_word(10'h155, 32'h1122_3344, 4'hF);
    write_word(10'h155, 32'hAABB_CCDD, 4'b0101);
    write_word(10'h1FF, 32'h0102_0304, 4'hF);
    write_word(10'h200, 32'h1122_3344, 4'hF);
    write_word(10'h3FF, 32'hA5A5_5A5A, 4'hF);
    read_word(10'h000, 32'hCAFE_BABE);
    read_word(10'h155, 32'h11BB_33DD);
    read_word(10'h1FF, 32'h0102_0304);
    expect_read_hold(10'h200, 32'h0102_0304);
    read_word(10'h200, 32'h1122_3344);
    read_word(10'h3FF, 32'hA5A5_5A5A);
    $display("1024x32 SRAM wrapper test passed");
    $finish;
  end
endmodule
