`timescale 1ns / 1ps

`include "rib_defs.svh"

module rib2apb_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        rng_ready = 1'b0;
  logic        rng_slverr = 1'b0;
  logic [31:0] rng_rdata = 32'h1234_5678;

  rib_if rib ();
  apb4_pure_if archinfo ();
  apb4_pure_if rng ();
  apb4_pure_if uart ();
  apb4_pure_if pwm ();
  apb4_pure_if ps2 ();
  apb4_pure_if rtc ();
  apb4_pure_if wdg ();
  apb4_pure_if crc ();
  apb4_pure_if tmr ();
  apb4_pure_if user_ip ();

  always #5 clk_i = ~clk_i;

  assign archinfo.pready  = 1'b0;
  assign archinfo.prdata  = '0;
  assign archinfo.pslverr = 1'b0;
  assign rng.pready       = rng_ready;
  assign rng.prdata       = rng_rdata;
  assign rng.pslverr      = rng_slverr;
  assign uart.pready      = 1'b0;
  assign uart.prdata      = '0;
  assign uart.pslverr     = 1'b0;
  assign pwm.pready       = 1'b0;
  assign pwm.prdata       = '0;
  assign pwm.pslverr      = 1'b0;
  assign ps2.pready       = 1'b0;
  assign ps2.prdata       = '0;
  assign ps2.pslverr      = 1'b0;
  assign rtc.pready       = 1'b0;
  assign rtc.prdata       = '0;
  assign rtc.pslverr      = 1'b0;
  assign wdg.pready       = 1'b0;
  assign wdg.prdata       = '0;
  assign wdg.pslverr      = 1'b0;
  assign crc.pready       = 1'b0;
  assign crc.prdata       = '0;
  assign crc.pslverr      = 1'b0;
  assign tmr.pready       = 1'b0;
  assign tmr.prdata       = '0;
  assign tmr.pslverr      = 1'b0;
  assign user_ip.pready   = 1'b0;
  assign user_ip.prdata   = '0;
  assign user_ip.pslverr  = 1'b0;

  rib2apb u_rib2apb (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .rib     (rib),
      .archinfo(archinfo),
      .rng     (rng),
      .uart    (uart),
      .pwm     (pwm),
      .ps2     (ps2),
      .rtc     (rtc),
      .wdg     (wdg),
      .crc     (crc),
      .tmr     (tmr),
      .user_ip (user_ip)
  );

  task automatic send_command(input logic [31:0] address, input logic write,
                              input logic [1:0] length);
    begin
      @(negedge clk_i);
      rib.cmd_addr  = address;
      rib.cmd_write = write;
      rib.cmd_len   = length;
      rib.cmd_valid = 1'b1;
      while (!rib.cmd_ready) @(posedge clk_i);
      @(negedge clk_i);
      rib.cmd_valid = 1'b0;
    end
  endtask

  task automatic send_write(input logic [31:0] data, input logic [3:0] strobes, input logic last);
    begin
      @(negedge clk_i);
      rib.wdata   = data;
      rib.wstrb   = strobes;
      rib.wlast   = last;
      rib.w_valid = 1'b1;
      while (!rib.w_ready) @(posedge clk_i);
      @(negedge clk_i);
      rib.w_valid = 1'b0;
    end
  endtask

  task automatic wait_for_rng_enable;
    begin
      while (!(rng.psel && rng.penable)) @(posedge clk_i);
    end
  endtask

  task automatic expect_response(input logic expected_error, input logic [2:0] expected_code,
                                 input logic [31:0] expected_data);
    begin
      while (!rib.rsp_valid) @(posedge clk_i);
      #1;
      if (rib.resp_err !== expected_error || rib.resp_code !== expected_code ||
          rib.rdata !== expected_data || rib.rsp_beat !== 2'd0 || !rib.rsp_last) begin
        $fatal(1, "unexpected RIB response error=%b/%b code=%0d/%0d data=%h/%h fsm=%0d",
               rib.resp_err, expected_error, rib.resp_code, expected_code, rib.rdata,
               expected_data, u_rib2apb.s_fsm_q);
      end
    end
  endtask

  initial begin
    rib.cmd_valid = 1'b0;
    rib.cmd_addr  = '0;
    rib.cmd_write = 1'b0;
    rib.cmd_len   = `RIB_LEN_INCR1;
    rib.w_valid   = 1'b0;
    rib.wdata     = '0;
    rib.wstrb     = '0;
    rib.wlast     = 1'b0;
    rib.rsp_ready = 1'b1;

    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;

    send_command(32'h2000_1000, 1'b0, `RIB_LEN_INCR1);
    while (!(rng.psel && !rng.penable)) @(posedge clk_i);
    wait_for_rng_enable();
    if (rng.paddr !== 32'h2000_1000 || rng.pwrite || rng.pstrb !== 4'd0) begin
      $fatal(1, "read APB setup was not held from the RIB command");
    end
    repeat (2) begin
      @(posedge clk_i);
      if (!(rng.psel && rng.penable) || rng.paddr !== 32'h2000_1000) begin
        $fatal(1, "APB read request changed while PREADY was low");
      end
    end
    rib.rsp_ready = 1'b0;
    @(negedge clk_i);
    rng_ready = 1'b1;
    expect_response(1'b0, `RIB_RESP_OK, 32'h1234_5678);
    repeat (2) begin
      @(posedge clk_i);
      if (!rib.rsp_valid || rib.rdata !== 32'h1234_5678) begin
        $fatal(1, "response did not remain stable under RIB backpressure");
      end
    end
    rib.rsp_ready = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    rng_ready = 1'b0;

    send_command(32'h2000_1000, 1'b1, `RIB_LEN_INCR1);
    send_write(32'hA5A5_5A5A, 4'hC, 1'b1);
    wait_for_rng_enable();
    if (!rng.pwrite || rng.pwdata !== 32'hA5A5_5A5A || rng.pstrb !== 4'hC) begin
      $fatal(1, "APB write data was not held from the RIB write channel");
    end
    @(negedge clk_i);
    rng_ready = 1'b1;
    expect_response(1'b0, `RIB_RESP_OK, 32'd0);
    @(posedge clk_i);
    @(negedge clk_i);
    rng_ready  = 1'b0;

    rng_slverr = 1'b1;
    send_command(32'h2000_1000, 1'b0, `RIB_LEN_INCR1);
    wait_for_rng_enable();
    @(negedge clk_i);
    rng_ready = 1'b1;
    expect_response(1'b1, `RIB_RESP_SLVERR, 32'h1234_5678);
    @(posedge clk_i);
    @(negedge clk_i);
    rng_ready  = 1'b0;
    rng_slverr = 1'b0;

    send_command(32'h2000_1000, 1'b1, `RIB_LEN_INCR4);
    send_write(32'h0000_0001, 4'hF, 1'b0);
    send_write(32'h0000_0002, 4'hF, 1'b0);
    send_write(32'h0000_0003, 4'hF, 1'b0);
    send_write(32'h0000_0004, 4'hF, 1'b1);
    if (rng.psel) $fatal(1, "illegal RIB burst reached the APB target");
    expect_response(1'b1, `RIB_RESP_BURSTERR, 32'd0);
    @(posedge clk_i);

    $display("RIB2APB direct bridge test passed");
    $finish;
  end
endmodule
