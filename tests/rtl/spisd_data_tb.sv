`timescale 1ns / 1ps

module spisd_data_tb;
  logic                                    clk_i = 1'b0;
  logic                                    rst_n_i = 1'b0;
  logic                                    rise_tick_i = 1'b0;
  logic                                    fall_tick_i = 1'b0;
  logic                                    start_i = 1'b0;
  logic                                    abort_i = 1'b0;
  spisd_pkg::spisd_data_direction_e        direction_i = spisd_pkg::SpisdDataFromCard;
  logic                                    multi_block_i = 1'b0;
  logic                                    crc_check_i = 1'b1;
  logic                             [15:0] block_size_i = 16'd4;
  logic                             [15:0] block_count_i = 16'd1;
  logic                             [31:0] timeout_cycles_i = 32'd1000;
  logic                             [31:0] busy_timeout_cycles_i = 32'd1000;
  logic                                    miso_i = 1'b1;
  logic                                    mosi_o;
  logic                                    clock_pause_o;
  logic                                    tx_valid_i = 1'b0;
  logic                                    tx_ready_o;
  logic                             [31:0] tx_data_i = 32'd0;
  logic                             [ 3:0] tx_strb_i = 4'd0;
  logic                                    tx_last_i = 1'b0;
  logic                                    rx_valid_o;
  logic                                    rx_ready_i = 1'b0;
  logic                             [31:0] rx_data_o;
  logic                             [ 3:0] rx_strb_o;
  logic                                    rx_last_o;
  logic                                    busy_o;
  logic                                    done_o;
  logic                                    error_o;
  logic                                    timeout_o;
  logic                                    crc_error_o;
  logic                                    busy_timeout_o;
  logic                             [ 7:0] error_code_o;
  logic                             [15:0] blocks_done_o;
  logic                             [87:0] s_write_serial;
  logic                             [15:0] s_write_crc;

  always #1 clk_i = ~clk_i;

  spisd_data u_spisd_data (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .rise_tick_i          (rise_tick_i),
      .fall_tick_i          (fall_tick_i),
      .start_i              (start_i),
      .abort_i              (abort_i),
      .direction_i          (direction_i),
      .multi_block_i        (multi_block_i),
      .crc_check_i          (crc_check_i),
      .block_size_i         (block_size_i),
      .block_count_i        (block_count_i),
      .timeout_cycles_i     (timeout_cycles_i),
      .busy_timeout_cycles_i(busy_timeout_cycles_i),
      .miso_i               (miso_i),
      .mosi_o               (mosi_o),
      .clock_pause_o        (clock_pause_o),
      .tx_valid_i           (tx_valid_i),
      .tx_ready_o           (tx_ready_o),
      .tx_data_i            (tx_data_i),
      .tx_strb_i            (tx_strb_i),
      .tx_last_i            (tx_last_i),
      .rx_valid_o           (rx_valid_o),
      .rx_ready_i           (rx_ready_i),
      .rx_data_o            (rx_data_o),
      .rx_strb_o            (rx_strb_o),
      .rx_last_o            (rx_last_o),
      .busy_o               (busy_o),
      .done_o               (done_o),
      .error_o              (error_o),
      .timeout_o            (timeout_o),
      .crc_error_o          (crc_error_o),
      .busy_timeout_o       (busy_timeout_o),
      .error_code_o         (error_code_o),
      .blocks_done_o        (blocks_done_o)
  );

  task automatic pulse_start;
    begin
      @(negedge clk_i);
      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
    end
  endtask

  task automatic rise_bit(input logic value);
    begin
      @(negedge clk_i);
      miso_i      = value;
      rise_tick_i = 1'b1;
      @(negedge clk_i);
      rise_tick_i = 1'b0;
    end
  endtask

  task automatic rise_byte(input logic [7:0] value);
    begin
      for (integer bit_index = 7; bit_index >= 0; bit_index--) begin
        rise_bit(value[bit_index]);
      end
    end
  endtask

  task automatic fall_capture;
    begin
      @(negedge clk_i);
      s_write_serial = {s_write_serial[86:0], mosi_o};
      fall_tick_i    = 1'b1;
      @(negedge clk_i);
      fall_tick_i = 1'b0;
    end
  endtask

  task automatic consume_read_word;
    begin
      wait (rx_valid_o);
      if ((rx_data_o != 32'h4433_2211) || (rx_strb_o != 4'hF) || !rx_last_o || !clock_pause_o) begin
        $fatal(1, "read stream packing/backpressure failed: data=%h strb=%h last=%b pause=%b",
               rx_data_o, rx_strb_o, rx_last_o, clock_pause_o);
      end
      @(negedge clk_i);
      rx_ready_i = 1'b1;
      @(negedge clk_i);
      rx_ready_i = 1'b0;
    end
  endtask

  initial begin
    repeat (2) @(posedge clk_i);
    rst_n_i     = 1'b1;

    direction_i = spisd_pkg::SpisdDataFromCard;
    pulse_start();
    rise_byte(8'hFF);
    rise_byte(8'hFE);
    rise_byte(8'h11);
    rise_byte(8'h22);
    rise_byte(8'h33);
    rise_byte(8'h44);
    consume_read_word();
    rise_byte(8'hDD);
    rise_byte(8'h33);
    wait (done_o);
    if (error_o || (blocks_done_o != 16'd1)) begin
      $fatal(1, "valid read block failed: err=%b code=%h blocks=%0d", error_o, error_code_o,
             blocks_done_o);
    end
    @(posedge clk_i);
    wait (!done_o);

    direction_i = spisd_pkg::SpisdDataFromCard;
    pulse_start();
    rise_byte(8'hFE);
    rise_byte(8'h11);
    rise_byte(8'h22);
    rise_byte(8'h33);
    rise_byte(8'h44);
    consume_read_word();
    rise_byte(8'h00);
    rise_byte(8'h00);
    wait (done_o);
    if (!error_o || !crc_error_o || (error_code_o != spisd_pkg::SpisdErrDataCrc)) begin
      $fatal(1, "read CRC fault was not classified");
    end
    @(posedge clk_i);
    wait (!done_o);

    direction_i    = spisd_pkg::SpisdDataToCard;
    block_size_i   = 16'd8;
    tx_data_i      = 32'h4433_2211;
    tx_strb_i      = 4'hF;
    tx_last_i      = 1'b0;
    s_write_crc    = 16'h0000;
    s_write_crc    = spisd_pkg::spisd_crc16_byte(s_write_crc, 8'h11);
    s_write_crc    = spisd_pkg::spisd_crc16_byte(s_write_crc, 8'h22);
    s_write_crc    = spisd_pkg::spisd_crc16_byte(s_write_crc, 8'h33);
    s_write_crc    = spisd_pkg::spisd_crc16_byte(s_write_crc, 8'h44);
    s_write_crc    = spisd_pkg::spisd_crc16_byte(s_write_crc, 8'h55);
    s_write_crc    = spisd_pkg::spisd_crc16_byte(s_write_crc, 8'h66);
    s_write_crc    = spisd_pkg::spisd_crc16_byte(s_write_crc, 8'h77);
    s_write_crc    = spisd_pkg::spisd_crc16_byte(s_write_crc, 8'h88);
    s_write_serial = '0;
    pulse_start();
    wait (tx_ready_o);
    @(negedge clk_i);
    tx_valid_i = 1'b1;
    @(negedge clk_i);
    tx_valid_i = 1'b0;
    repeat (40) fall_capture();
    wait (tx_ready_o);
    tx_data_i = 32'h8877_6655;
    tx_last_i = 1'b1;
    @(negedge clk_i);
    tx_valid_i = 1'b1;
    @(negedge clk_i);
    tx_valid_i = 1'b0;
    repeat (48) fall_capture();
    if (s_write_serial != {8'hFE, 64'h1122_3344_5566_7788, s_write_crc}) begin
      $fatal(1, "write token/payload/CRC serialization failed: got=%h crc=%h", s_write_serial,
             s_write_crc);
    end
    rise_bit(1'b0);
    rise_bit(1'b0);
    rise_bit(1'b1);
    rise_bit(1'b0);
    rise_bit(1'b1);
    rise_bit(1'b0);
    rise_bit(1'b1);
    wait (done_o);
    if (error_o || timeout_o || busy_timeout_o || (blocks_done_o != 16'd1)) begin
      $fatal(1, "write response/busy completion failed: err=%b code=%h blocks=%0d", error_o,
             error_code_o, blocks_done_o);
    end
    $display("SPISD read/write data, CRC, and backpressure test passed");
    $finish;
  end
endmodule
