`timescale 1ns / 1ps
// Synthetic pins test the oracle itself, without a DUT or implementation state.
module spi_pin_checker_tb;
  logic clk_i = 0, begin_i = 0, enabled_i = 1, abort_i = 0, pause_i = 0, segment_i = 0;
  logic cpol_i = 0, cpha_i = 0, lsb_i = 0, frame16_i = 0;
  logic cs_n_i = 1, sck_i = 0, mosi_i = 1, miso_o;
  logic [8:0] faults_o;
  integer frames_o, edges_o;
  always #20.833 clk_i = !clk_i;
  spi_pin_bfm u_checker (
      .clk_i      (clk_i),
      .begin_i    (begin_i),
      .enabled_i  (enabled_i),
      .abort_i    (abort_i),
      .pause_i    (pause_i),
      .segment_i  (segment_i),
      .divider_i  (16'd2),
      .setup_i    (16'd2),
      .hold_i     (16'd2),
      .inactive_i (16'd2),
      .cpol_i     (cpol_i),
      .cpha_i     (cpha_i),
      .lsb_i      (lsb_i),
      .frame16_i  (frame16_i),
      .direction_i(2'd2),
      .dummy_i    (16'hffff),
      .cs_n_i     (cs_n_i),
      .sck_i      (sck_i),
      .mosi_i     (mosi_i),
      .miso_o     (miso_o),
      .frames_o   (frames_o),
      .edges_o    (edges_o),
      .faults_o   (faults_o)
  );
  task automatic tick;
    @(negedge clk_i);
    #1;
  endtask
  task automatic drive(input logic cs, sck, mosi);
    @(posedge clk_i);
    #1;
    cs_n_i = cs;
    sck_i  = sck;
    mosi_i = mosi;
    tick();
  endtask
  task automatic reset_checker;
    @(posedge clk_i);
    #1;
    begin_i   = 1;
    abort_i   = 0;
    pause_i   = 0;
    segment_i = 0;
    cs_n_i    = 1;
    sck_i     = cpol_i;
    mosi_i    = 1;
    tick();
    @(posedge clk_i);
    #1;
    begin_i   = 0;
    segment_i = 1;
    cs_n_i    = 0;
    tick();
    segment_i = 0;
  endtask
  task automatic frame_edges(input integer number, input logic data_bit);
    for (integer edge_number = 0; edge_number < number; edge_number++) begin
      drive(0, sck_i, data_bit);
      drive(0, !sck_i, data_bit);
    end
  endtask
  task automatic check(input logic [8:0] expected, input integer case_id);
    if (faults_o !== expected)
      $fatal(1, "SPI checker selftest case=%0d got=%h expected=%h", case_id, faults_o, expected);
    $display("SPI_CHECKER_CASE id=%0d faults=%h", case_id, faults_o);
  endtask
  initial begin
    for (integer mode = 0; mode < 4; mode++) begin
      cpol_i = 1'(mode / 2);
      cpha_i = 1'(mode % 2);
      for (integer width_case = 0; width_case < 2; width_case++) begin
        frame16_i = 1'(width_case);
        for (integer order = 0; order < 2; order++) begin
          lsb_i = 1'(order);
          reset_checker();
          frame_edges(frame16_i ? 32 : 16, 1);
          drive(0, cpol_i, 1);
          drive(1, cpol_i, 1);
          check(0, 100 + mode * 4 + width_case * 2 + order);
        end
      end
    end
    cpol_i    = 0;
    cpha_i    = 0;
    frame16_i = 0;
    lsb_i     = 0;
    reset_checker();
    frame_edges(1, 1);
    drive(0, 0, 1);
    check(9'h001, 0);
    reset_checker();
    frame_edges(1, 1);
    repeat (3) drive(0, 1, 1);
    check(9'h001, 1);
    reset_checker();
    drive(0, 1, 1);
    check(9'h002, 2);
    reset_checker();
    drive(0, 0, 0);
    drive(0, 1, 1);
    check(9'h004, 3);
    reset_checker();
    frame_edges(15, 1);
    drive(0, 1, 1);
    drive(1, 1, 1);
    check(9'h008, 4);
    reset_checker();
    frame_edges(16, 1);
    drive(1, 0, 1);
    check(9'h010, 5);
    reset_checker();
    frame_edges(16, 1);
    drive(0, 0, 1);
    drive(1, 0, 1);
    drive(0, 0, 1);
    check(9'h020, 6);
    reset_checker();
    frame_edges(2, 1);
    abort_i = 1;
    drive(0, 0, 1);
    drive(0, 1, 1);
    check(9'h040, 7);
    reset_checker();
    frame_edges(1, 1);
    pause_i = 1;
    drive(0, 1, 1);
    check(9'h080, 8);
    reset_checker();
    frame_edges(16, 0);
    check(9'h100, 9);
    // Normal abort permits the remaining trailing edge, but no new leading edge.
    reset_checker();
    frame_edges(1, 1);
    abort_i = 1;
    drive(0, 1, 1);
    drive(0, 0, 1);
    drive(0, 0, 1);
    drive(1, 0, 1);
    check(0, 10);
    reset_checker();
    frame_edges(1, 1);
    abort_i = 1;
    drive(0, 0, 1);
    check(9'h001, 11);
    $display("SPI_P1_PASS spi_pin_checker_tb");
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1, "SIM_TEST_TIMEOUT SPI pin checker");
  end
endmodule
