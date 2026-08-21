`timescale 1ns / 1ps

module sdio_crc_tb;
  logic [39:0] crc7_data;
  logic [ 6:0] crc7_value;
  logic [15:0] crc16_value;
  logic [15:0] crc16_seed;
  logic [ 7:0] crc16_data;

  sdio_crc7 u_sdio_crc7 (
      .data_i(crc7_data),
      .crc_o (crc7_value)
  );
  sdio_crc16 u_sdio_crc16 (
      .crc_i (crc16_seed),
      .data_i(crc16_data),
      .crc_o (crc16_value)
  );

  initial begin
    crc7_data = {1'b0, 1'b1, 6'd0, 32'd0};
    #1;
    if (crc7_value != 7'h4A) begin
      $fatal(1, "CMD0 CRC7 mismatch: %h", crc7_value);
    end

    crc7_data = {1'b0, 1'b1, 6'd8, 32'h0000_01AA};
    #1;
    if (crc7_value != 7'h43) begin
      $fatal(1, "CMD8 CRC7 mismatch: %h", crc7_value);
    end

    crc16_seed = 16'h0000;
    crc16_data = "1";
    #1;
    crc16_seed = crc16_value;
    crc16_data = "2";
    #1;
    crc16_seed = crc16_value;
    crc16_data = "3";
    #1;
    crc16_seed = crc16_value;
    crc16_data = "4";
    #1;
    crc16_seed = crc16_value;
    crc16_data = "5";
    #1;
    crc16_seed = crc16_value;
    crc16_data = "6";
    #1;
    crc16_seed = crc16_value;
    crc16_data = "7";
    #1;
    crc16_seed = crc16_value;
    crc16_data = "8";
    #1;
    crc16_seed = crc16_value;
    crc16_data = "9";
    #1;
    if (crc16_value != 16'h31C3) begin
      $fatal(1, "CRC16 mismatch: %h", crc16_value);
    end
    $display("SDIO CRC vectors passed");
    $finish;
  end
endmodule
