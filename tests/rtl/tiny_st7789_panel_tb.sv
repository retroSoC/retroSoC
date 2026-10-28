`timescale 1ns / 1ps

module tiny_st7789_panel_tb;
  logic sck_i = 1'b0;
  logic csn_i = 1'b1;
  logic mosi_i = 1'b1;
  logic dc_i = 1'b0;
  logic test_done_i = 1'b0;

  tiny_st7789_panel u_dut (
      .sck_i      (sck_i),
      .csn_i      (csn_i),
      .mosi_i     (mosi_i),
      .dc_i       (dc_i),
      .test_done_i(test_done_i)
  );

  task automatic drive_bit(input logic value);
    begin
      mosi_i = value;
      #5 sck_i = 1'b1;
      #5 sck_i = 1'b0;
    end
  endtask

  task automatic drive_bits(input logic [7:0] value, input integer count);
    begin
      for (integer index = count - 1; index >= 0; index--) drive_bit(value[index]);
    end
  endtask

  task automatic drive_byte(input logic [7:0] value);
    begin
      drive_bits(value, 8);
    end
  endtask

  task automatic start_window;
    begin
      csn_i = 1'b0;
      dc_i  = 1'b0;
      drive_byte(8'h2c);
      dc_i = 1'b1;
    end
  endtask

  task automatic close_window;
    begin
      #1 csn_i = 1'b1;
      #1;
    end
  endtask

  initial begin
    #2;
    csn_i = 1'b0;
    drive_byte(8'h11);
    drive_byte(8'h29);
    start_window();
    drive_bits(8'ha, 4);
    close_window();
    if (u_dut.s_violations != 0) $fatal(1, "Partial-byte abort was rejected");

    start_window();
    drive_byte(8'ha5);
    drive_bits(8'h2, 3);
    close_window();
    if (u_dut.s_violations != 0) $fatal(1, "Odd-byte abort was rejected");

    start_window();
    drive_byte(8'h12);
    drive_byte(8'h34);
    drive_bits(8'h1, 1);
    close_window();
    if (u_dut.s_violations != 1) $fatal(1, "Complete window with residual bits was accepted");

    start_window();
    drive_byte(8'h12);
    drive_byte(8'h34);
    drive_byte(8'h56);
    close_window();
    if (u_dut.s_violations != 2) $fatal(1, "Complete window with odd pixel bytes was accepted");

    csn_i = 1'b0;
    dc_i  = 1'b0;
    drive_bits(8'h1, 1);
    close_window();
    if (u_dut.s_violations != 3) $fatal(1, "Non-pixel residual bits were accepted");
    if (u_dut.s_windows != 4 || u_dut.s_pixels != 2)
      $fatal(1, "Unexpected window or pixel accounting");

    test_done_i = 1'b1;
    #1 test_done_i = 1'b0;
    #1;
    $display(
        "SIM_TEST_PASS ST7789_ORACLE partial_abort=2 residual_rejected=2 odd_pixel_rejected=1");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "SIM_TEST_TIMEOUT tiny_st7789_panel_tb");
  end
endmodule
