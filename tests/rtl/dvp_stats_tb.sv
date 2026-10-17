// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
`timescale 1ns / 1ps
module dvp_stats_tb;
  logic clk = 0, pixel_clk = 0, rst_n = 0, host_run = 1;
  always #5 if (host_run) clk = !clk;
  always #7 pixel_clk = !pixel_clk;
  apb4_if apb (
      clk,
      rst_n
  );
  axi4_stream_if #(
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .DEST_WIDTH(1),
      .USER_WIDTH(1)
  ) stream (
      clk,
      rst_n
  );
  dvp_if camera ();
  logic href = 0, vsync = 0;
  logic [7:0] data = 0;
  wire        irq;
  assign camera.pclk_i  = pixel_clk;
  assign camera.href_i  = href;
  assign camera.vsync_i = vsync;
  assign camera.dat_i   = data;
  assign stream.tready  = 1;
  axi4s_dvp u_dut (
      .clk_i  (clk),
      .rst_n_i(rst_n),
      .apb4   (apb),
      .rx_axis(stream),
      .dvp    (camera),
      .irq_o  (irq)
  );
  integer width = 4, height = 2, case_id = 0;
  integer        received = 0;
  integer        expected_words = 0;
  logic          checking = 0;
  logic   [31:0] value;

  task automatic access (input bit write, input logic [31:0] address, input logic [31:0] wdata,
                         output logic [31:0] rdata);
    @(negedge clk);
    apb.psel    = 1;
    apb.penable = 0;
    apb.pwrite  = write;
    apb.paddr   = address;
    apb.pwdata  = wdata;
    apb.pstrb   = write ? 4'hf : 4'h0;
    @(negedge clk);
    apb.penable = 1;
    do @(negedge clk); while (!apb.pready);
    rdata = apb.prdata;
    if (apb.pslverr) $fatal(1, "SIM_TEST_FAIL stats APB error addr=%h", address);
    apb.psel    = 0;
    apb.penable = 0;
  endtask
  task automatic put(input logic [31:0] address, input logic [31:0] wdata);
    logic [31:0] ignored;
    access (1, address, wdata, ignored);
  endtask
  task automatic expect_reg(input logic [31:0] address, input logic [31:0] expected);
    logic [31:0] got;
    access (0, address, 0, got);
    if (got !== expected)
      $fatal(1, "SIM_TEST_FAIL stats addr=%h got=%0d expected=%0d", address, got, expected);
  endtask

  always @(posedge clk) begin : check_words
    integer row, column;
    logic [ 7:0] first;
    logic [31:0] expected;
    logic        partial;
    if (checking && stream.tvalid && stream.tready) begin
      row = received / ((width + 1) / 2);
      column = received % ((width + 1) / 2);
      first = 8'(row * 3 + column * 4);
      partial = (width % 2 != 0) && (column == width / 2);
      expected = partial ? {16'd0, first, 8'(first + 1)} :
                           {8'(first + 2), 8'(first + 3), first, 8'(first + 1)};
      if (received >= expected_words || stream.tdata !== expected ||
          stream.tkeep !== (partial ? 4'h3 : 4'hf) ||
          stream.tstrb !== (partial ? 4'h3 : 4'hf) ||
          stream.tlast !== (column == (width + 1) / 2 - 1) ||
          stream.tuser !== (received == 0))
        $fatal(
            1,
            "SIM_TEST_FAIL stats payload/sideband word=%0d got=%h expected=%h",
            received,
            stream.tdata,
            expected
        );
      received++;
    end
  end

  task automatic capture(input integer frame_index, input integer previous_words);
    put(0, 0);
    repeat (80) @(negedge pixel_clk);
    put('h18, {16'(height), 16'(width)});
    put('h10, $test$plusargs("yuv") ? 1 : 0);
    put('hc, 1);
    put(0, 3);
    repeat (80) @(negedge pixel_clk);
    received       = 0;
    expected_words = ((width + 1) / 2) * height;
    checking       = 1;
    vsync          = 1;
    repeat (3) @(negedge pixel_clk);
    vsync = 0;
    repeat (3) @(negedge pixel_clk);
    for (int row = 0; row < height; row++) begin
      href = 1;
      for (int byte_index = 0; byte_index < width * 2; byte_index++) begin
        data = 8'(row * 3 + byte_index);
        @(negedge pixel_clk);
      end
      href = 0;
      repeat (3) @(negedge pixel_clk);
      if (row == 0) begin
        expect_reg('h30, 32'(previous_words));
        expect_reg('h24, 32'(frame_index - 1));
        @(negedge pixel_clk);
      end
    end
    repeat (40) @(negedge pixel_clk);
    if (received != expected_words) $fatal(1, "SIM_TEST_FAIL stats incomplete stream");
    // The actual mailbox must retain the completed frame while its receiver
    // clock is stopped. No internal DUT state or valid/ready signal is forced.
    if ($test$plusargs("pause_host")) begin
      @(negedge clk);
      host_run = 0;
    end
    @(negedge pixel_clk);
    vsync = 1;
    repeat (3) @(negedge pixel_clk);
    vsync = 0;
    repeat (80) @(negedge pixel_clk);
    host_run = 1;
    repeat (100) @(negedge clk);
    expect_reg('h24, 32'(frame_index));
    expect_reg('h28, 32'(height));
    expect_reg('h2c, 32'(width * height));
    expect_reg('h30, 32'(expected_words));
    expect_reg('h34, 0);
    expect_reg('h38, 0);
    repeat (40) @(negedge pixel_clk);
    expect_reg('h30, 32'(expected_words));
    checking = 0;
    $display("DVP_STATS_FRAME frame=%0d width=%0d height=%0d words=%0d pixels=%0d", frame_index,
             width, height, received, width * height);
  endtask

  initial begin
    #30000000;
    $fatal(1, "SIM_TEST_TIMEOUT DVP statistics");
  end
  initial begin
    apb.psel    = 0;
    apb.penable = 0;
    apb.pwrite  = 0;
    apb.paddr   = 0;
    apb.pwdata  = 0;
    apb.pstrb   = 0;
    apb.pprot   = 0;
    if ($value$plusargs("case=%d", case_id)) begin
    end
    case (case_id)
      0: begin
        width  = 4;
        height = 2;
      end
      1: begin
        width  = 510;
        height = 257;
      end
      2: begin
        width  = 512;
        height = 256;
      end
      3: begin
        width  = 640;
        height = 480;
      end
      4: begin
        width  = 511;
        height = 256;
      end
      5: begin
        width  = 65535;
        height = 1;
      end
      default: $fatal(1, "SIM_TEST_FAIL unknown stats case");
    endcase
    repeat (5) @(negedge clk);
    rst_n = 1;
    repeat (100) @(negedge clk);
    capture(1, 0);
    value  = 32'(expected_words);
    width  = 4;
    height = 2;
    capture(2, int'(value));
    $display("SIM_TEST_PASS DVP statistics case=%0d", case_id);
    $finish;
  end
endmodule
