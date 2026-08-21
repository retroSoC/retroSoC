`timescale 1ns / 1ps

module spisd_crc_tb;
  logic [15:0] s_crc16;

  initial begin
    if (spisd_pkg::spisd_crc7_calc({2'b01, 6'd0, 32'd0}) != 7'h4A) begin
      $fatal(1, "CMD0 CRC7 vector failed");
    end
    if (spisd_pkg::spisd_crc7_calc({2'b01, 6'd8, 32'h0000_01AA}) != 7'h43) begin
      $fatal(1, "CMD8 CRC7 vector failed");
    end
    s_crc16 = 16'h0000;
    s_crc16 = spisd_pkg::spisd_crc16_byte(s_crc16, "1");
    s_crc16 = spisd_pkg::spisd_crc16_byte(s_crc16, "2");
    s_crc16 = spisd_pkg::spisd_crc16_byte(s_crc16, "3");
    s_crc16 = spisd_pkg::spisd_crc16_byte(s_crc16, "4");
    s_crc16 = spisd_pkg::spisd_crc16_byte(s_crc16, "5");
    s_crc16 = spisd_pkg::spisd_crc16_byte(s_crc16, "6");
    s_crc16 = spisd_pkg::spisd_crc16_byte(s_crc16, "7");
    s_crc16 = spisd_pkg::spisd_crc16_byte(s_crc16, "8");
    s_crc16 = spisd_pkg::spisd_crc16_byte(s_crc16, "9");
    if (s_crc16 != 16'h31C3) begin
      $fatal(1, "CRC16 vector failed: %h", s_crc16);
    end
    $display("SPISD CRC vectors passed");
    $finish;
  end
endmodule
