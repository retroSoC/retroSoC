// Copyright (c) 2026 Yuchi Miao; SPDX-License-Identifier: MulanPSL-2.0
`timescale 1ns / 1ps
`include "xpi_define.svh"
module xpi_error_report_tb;
  import xpi_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = !clk;
  apb4_if apb (
      clk,
      rst_n
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi (
      .aclk   (clk),
      .aresetn(rst_n)
  );
  xpi_if pins ();
  logic irq, idle_signal;
  logic   [31:0] value;
  integer        scenario = 0;
  assign pins.io_di_i = 4'd0;
  apb4_xpi u_dut (
      .clk_i           (clk),
      .rst_n_i         (rst_n),
      .dma_xfer_done_i (1'b0),
      .lifecycle_idle_o(idle_signal),
      .dma_tx_stall_o  (),
      .dma_rx_stall_o  (),
      .irq_o           (irq),
      .apb4            (apb),
      .mem_axi4        (axi),
      .xpi             (pins)
  );

  task automatic access (input bit write, input logic [11:0] address, input logic [31:0] data,
                         output logic [31:0] result);
    @(negedge clk);
    apb.psel    = 1;
    apb.penable = 0;
    apb.pwrite  = write;
    apb.paddr   = {20'd0, address};
    apb.pwdata  = data;
    apb.pstrb   = 4'hf;
    @(negedge clk);
    apb.penable = 1;
    do @(posedge clk); while (!apb.pready);
    if (apb.pslverr) $fatal(1, "SIM_TEST_FAIL APB %h", address);
    result = apb.prdata;
    @(negedge clk);
    apb.psel    = 0;
    apb.penable = 0;
  endtask
  task automatic wr(input logic [11:0] address, input logic [31:0] data);
    logic [31:0] ignored;
    access (1, address, data, ignored);
  endtask
  task automatic expect_reg(input logic [11:0] address, input logic [31:0] expected);
    logic [31:0] got;
    access (0, address, 0, got);
    if (got !== expected)
      $fatal(1, "SIM_TEST_FAIL addr=%h got=%h expected=%h", address, got, expected);
  endtask
  task automatic idle;
    do access (0, 12'h010, 0, value); while ((value & 14) != 0);
  endtask
  task automatic clear_error;
    wr(12'h018, 32'h80000000);
    wr(12'h024, 255);
    expect_reg(12'h018, 0);
    expect_reg(12'h01c, 0);
    expect_reg(12'h020, 0);
  endtask
  task automatic expect_error(input int code, input logic [31:0] address, input int slot,
                              input int pc, input logic [31:0] interrupt_bit);
    expect_reg(12'h018, 32'h80000000 | 32'(code));
    expect_reg(12'h01c, address);
    expect_reg(12'h020, 32'((pc << 6) | (slot << 4) | code));
    access (0, 12'h024, 0, value);
    if ((value & interrupt_bit) != interrupt_bit || !irq)
      $fatal(1, "SIM_TEST_FAIL IRQ code=%0d state=%h irq=%b", code, value, irq);
  endtask
  task automatic indirect_error;
    wr(12'h048, 32'h00001234);
    wr(12'h04c, 0);
    wr(12'h050, 32'h13);
    wr(12'h014, 1);
    idle();
  endtask
  task automatic poll(input bit bad_lut, input int limit, input int interval_cycles);
    wr(`APB4_XPI__POLL_CFG, bad_lut ? 32'h12 : 32'h22);
    wr(`APB4_XPI__POLL_MASK, 1);
    wr(`APB4_XPI__POLL_MATCH, 1);
    wr(`APB4_XPI__POLL_INTERVAL, 32'(interval_cycles));
    wr(`APB4_XPI__POLL_TIMEOUT, 32'(limit));
    wr(12'h014, 2);
    idle();
  endtask
  task automatic read_error(input logic [31:0] address);
    @(negedge clk);
    axi.araddr  = address;
    axi.arvalid = 1;
    do @(posedge clk); while (!axi.arready);
    @(negedge clk);
    axi.arvalid = 0;
    do @(posedge clk); while (!axi.rvalid);
    if (axi.rresp !== 2 || !axi.rlast) $fatal(1, "SIM_TEST_FAIL expected read SLVERR");
    @(negedge clk);
    idle();
  endtask
  task automatic write_error(input logic [31:0] address, input bit bad_last);
    @(negedge clk);
    axi.awaddr  = address;
    axi.awvalid = 1;
    do @(posedge clk); while (!axi.awready);
    @(negedge clk);
    axi.awvalid = 0;
    axi.wvalid  = 1;
    axi.wlast   = !bad_last;
    do @(posedge clk); while (!axi.wready);
    @(negedge clk);
    axi.wvalid = 0;
    if (bad_last) begin
      // Complete the drain after a missing WLAST on the only declared beat.
      axi.wvalid = 1;
      axi.wlast  = 1;
      do @(posedge clk); while (!axi.wready);
      @(negedge clk);
      axi.wvalid = 0;
    end
    do @(posedge clk); while (!axi.bvalid);
    if (axi.bresp !== 2) $fatal(1, "SIM_TEST_FAIL expected write SLVERR");
    repeat (4) begin
      @(negedge clk);
      if (!axi.bvalid || axi.bresp !== 2) $fatal(1, "SIM_TEST_FAIL held B changed");
    end
    axi.bready = 1;
    @(posedge clk);
    @(negedge clk);
    axi.bready = 0;
    idle();
  endtask

  initial begin
    #1000000;
    $fatal(1, "SIM_TEST_TIMEOUT XPI error report");
  end
  initial begin
    apb.psel     = 0;
    apb.penable  = 0;
    apb.pwrite   = 0;
    apb.paddr    = 0;
    apb.pwdata   = 0;
    apb.pstrb    = 0;
    apb.pprot    = 0;
    axi.awid     = 0;
    axi.awaddr   = 0;
    axi.awlen    = 0;
    axi.awsize   = 2;
    axi.awburst  = 1;
    axi.awlock   = 0;
    axi.awcache  = 0;
    axi.awprot   = 0;
    axi.awqos    = 0;
    axi.awregion = 0;
    axi.awuser   = 0;
    axi.awvalid  = 0;
    axi.wdata    = 32'h12345678;
    axi.wstrb    = 15;
    axi.wlast    = 1;
    axi.wuser    = 0;
    axi.wvalid   = 0;
    axi.bready   = 0;
    axi.arid     = 0;
    axi.araddr   = 0;
    axi.arlen    = 0;
    axi.arsize   = 2;
    axi.arburst  = 1;
    axi.arlock   = 0;
    axi.arcache  = 0;
    axi.arprot   = 0;
    axi.arqos    = 0;
    axi.arregion = 0;
    axi.aruser   = 0;
    axi.arvalid  = 0;
    axi.rready   = 1;
    if ($value$plusargs("case=%d", scenario)) begin
    end
    repeat (5) @(negedge clk);
    rst_n = 1;
    wr(12'h00c, 0);
    for (int slot = 1; slot < 4; slot++) begin
      wr(12'(12'h100 + slot * 32), 7);
      wr(12'(12'h104 + slot * 32), 32'h10000);
      wr(12'(12'h108 + slot * 32), 32'h11);
      wr(12'(12'h10c + slot * 32), 32'h01010100);
      wr(12'(12'h110 + slot * 32), 4096);
      wr(12'(12'h114 + slot * 32), 1024);
    end
    // Dummy then illegal opcode: real sequencer error at PC 1.
    wr(12'h210, {16'hf000, xpi_instr(XpiInstrDummy, 0, 1)});
    wr(12'h214, 0);
    wr(12'h218, 0);
    wr(12'h21c, 0);
    // Deterministic all-zero external input for polling, with no backdoor.
    wr(12'h220, {16'd0, xpi_instr(XpiInstrReceive, 0, 4)});
    wr(12'h224, 0);
    wr(12'h228, 0);
    wr(12'h22c, 0);
    wr(12'h028, 32'h70);
    wr(12'h00c, 1);
    case (scenario)
      0: begin
        expect_reg(12'h018, 0);
      end
      1: begin
        write_error(32'h54010000, 0);
        expect_error(3, 32'h54010000, 1, 0, 16);
      end
      2: begin
        indirect_error();
        expect_error(4, 32'h1234, 3, 1, 32);
      end
      3: begin
        poll(1, 1000, 0);
        expect_error(4, 0, 2, 1, 32);
      end
      4: begin
        poll(0, 1, 0);
        expect_error(5, 0, 2, 0, 64);
      end
      5: begin
        poll(0, 1000, 2000);
        expect_error(5, 0, 2, 0, 64);
      end
      6: begin
        indirect_error();
        expect_error(4, 32'h1234, 3, 1, 32);
        clear_error();
        read_error(32'h58010000);
        expect_error(3, 32'h58010000, 2, 0, 16);
        // A second cause must set its IRQ without replacing the first snapshot.
        poll(0, 1, 0);
        expect_error(3, 32'h58010000, 2, 0, 80);
        clear_error();
        poll(1, 1000, 0);
        expect_error(4, 0, 2, 1, 32);
        clear_error();
        poll(0, 1000, 2000);
        expect_error(5, 0, 2, 0, 64);
      end
      7: begin
        indirect_error();
        clear_error();
        write_error(32'h54000020, 1);
        expect_error(1, 32'h54000020, 1, 0, 16);
      end
      8: begin
        // A normal indirect RX completes without an error report or error IRQ.
        wr(12'h048, 0);
        wr(12'h04c, 4);
        wr(12'h050, 32'h22);
        wr(12'h014, 1);
        idle();
        expect_reg(12'h018, 0);
        expect_reg(12'h044, 0);
        if (irq) $fatal(1, "SIM_TEST_FAIL false error IRQ");
        read_error(32'h54010000);
        expect_error(3, 32'h54010000, 1, 0, 16);
        @(negedge clk);
        rst_n = 0;
        repeat (5) @(negedge clk);
        rst_n = 1;
        expect_reg(12'h018, 0);
        expect_reg(12'h01c, 0);
        expect_reg(12'h020, 0);
        if (irq) $fatal(1, "SIM_TEST_FAIL reset retained IRQ");
      end
      9: begin
        read_error(32'h54010000);
        wr(12'h024, 255);
        // Preserve the existing ERROR_STATE W1C priority on an exact collision.
        @(negedge clk);
        apb.psel    = 1;
        apb.penable = 0;
        apb.pwrite  = 1;
        apb.paddr   = 32'h018;
        apb.pwdata  = 32'h80000000;
        apb.pstrb   = 15;
        @(negedge clk);
        apb.penable = 1;
        axi.araddr  = 32'h58010000;
        axi.arvalid = 1;
        @(posedge clk);
        if (!axi.arready) $fatal(1, "SIM_TEST_FAIL W1C collision setup");
        @(negedge clk);
        axi.arvalid = 0;
        if (!axi.rvalid || axi.rresp !== 2) $fatal(1, "SIM_TEST_FAIL collision response");
        do @(posedge clk); while (!apb.pready);
        @(negedge clk);
        apb.psel    = 0;
        apb.penable = 0;
        expect_reg(12'h018, 0);
        expect_reg(12'h01c, 0);
        expect_reg(12'h020, 0);
        access (0, 12'h024, 0, value);
        if ((value & 16) == 0 || !irq) $fatal(1, "SIM_TEST_FAIL collision IRQ lost");
      end
      10: begin
        read_error(32'h54000040);
        expect_error(4, 32'h54000040, 1, 1, 32);
      end
      11: begin
        wr(12'h00c, 0);
        wr(12'h130, 1);
        wr(12'h00c, 1);
        write_error(32'h54000040, 0);
        expect_error(5, 32'h54000040, 1, 0, 64);
      end
      12: begin
        axi.awsize = 0;
        axi.wstrb  = 15;
        write_error(32'h54000021, 0);
        expect_error(1, 32'h54000021, 1, 0, 16);
      end
      default: $fatal(1, "SIM_TEST_FAIL unknown case");
    endcase
    $display("SIM_TEST_PASS XPI error report case=%0d", scenario);
    $finish;
  end
endmodule
