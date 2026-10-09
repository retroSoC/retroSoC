`timescale 1ns / 1ps
module tc_ics55_gpio_readback_tb;
  logic drive = 0, value = 0, external_value = 0;
  wire tiny_read, legacy_read;
  tri tiny_pad, legacy_pad;
  assign tiny_pad   = drive ? 1'bz : external_value;
  assign legacy_pad = drive ? 1'bz : external_value;
  tc_io_tri_full_pad #(
      .ReadWhileDriving(1'b1)
  ) u_tiny (
      .pad   (tiny_pad),
      .c2p   (value),
      .c2p_en(drive),
      .p2c   (tiny_read),
      .cs    (1'b1),
      .pu    (1'b0),
      .pd    (1'b0)
  );
  tc_io_tri_full_pad u_legacy (
      .pad   (legacy_pad),
      .c2p   (value),
      .c2p_en(drive),
      .p2c   (legacy_read),
      .cs    (1'b1),
      .pu    (1'b0),
      .pd    (1'b0)
  );
  initial begin
    #20;
    if ({tiny_read, legacy_read} !== 2'b00) $fatal(1, "input low");
    external_value = 1;
    #20;
    if ({tiny_read, legacy_read} !== 2'b11) $fatal(1, "input high");
    drive = 1;
    value = 1;
    #20;
    if (tiny_pad !== 1'b1 || legacy_pad !== 1'b1 || tiny_read !== 1'b1 || legacy_read !== 1'b0)
      $fatal(1, "output readback or legacy behavior");
    value = 0;
    #20;
    if ({tiny_pad, legacy_pad, tiny_read, legacy_read} !== 4'b0000) $fatal(1, "output low");
    $display("SIM_TEST_PASS ICS55 GPIO readback and legacy compatibility");
    $finish;
  end
endmodule
