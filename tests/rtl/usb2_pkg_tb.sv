// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module usb2_pkg_tb;
  logic [15:0] s_crc16;

  initial begin
    if (usb2_pkg::usb2_pid_byte(usb2_pkg::Usb2PidOut) != 8'hE1) begin
      $fatal(1, "USB2 OUT PID encoding mismatch");
    end
    if (!usb2_pkg::usb2_pid_valid(8'hD2) || usb2_pkg::usb2_pid_valid(8'h52)) begin
      $fatal(1, "USB2 PID complement validation mismatch");
    end
    if (usb2_pkg::usb2_token_crc5(
            11'd0
        ) != 5'h02 || usb2_pkg::usb2_token_crc5(
            11'd1
        ) != 5'h1D) begin
      $fatal(1, "USB2 token CRC5 vector mismatch");
    end

    s_crc16 = 16'hFFFF;
    s_crc16 = usb2_pkg::usb2_crc16_byte(s_crc16, "1");
    s_crc16 = usb2_pkg::usb2_crc16_byte(s_crc16, "2");
    s_crc16 = usb2_pkg::usb2_crc16_byte(s_crc16, "3");
    s_crc16 = usb2_pkg::usb2_crc16_byte(s_crc16, "4");
    s_crc16 = usb2_pkg::usb2_crc16_byte(s_crc16, "5");
    s_crc16 = usb2_pkg::usb2_crc16_byte(s_crc16, "6");
    s_crc16 = usb2_pkg::usb2_crc16_byte(s_crc16, "7");
    s_crc16 = usb2_pkg::usb2_crc16_byte(s_crc16, "8");
    s_crc16 = usb2_pkg::usb2_crc16_byte(s_crc16, "9");
    if (usb2_pkg::usb2_crc16_finish(s_crc16) != 16'hB4C8) begin
      $fatal(1, "USB2 CRC16 vector mismatch");
    end
    $display("USB2 PID and CRC vectors passed");
    $finish;
  end
endmodule
