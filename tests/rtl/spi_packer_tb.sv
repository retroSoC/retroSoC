`timescale 1ns / 1ps
module spi_packer_tb;
  logic clk_i = 0, rst_n_i = 0, clear_i = 0, frame16_i = 0;
  logic [1:0] direction_i = 0;
  logic [31:0] quota_i = 10, tx_data_i = 0;
  logic tx_push_i = 0, rx_pop_i = 0, request_start = 0, frame_done_i = 0, last_frame_i = 0;
  logic [15:0] rx_frame_i = 0, tx_frame_o;
  logic [31:0] rx_data_o, tx_words_o, rx_words_o, rx_removed_o;
  logic tx_ready_o, rx_ready_o, tx_frame_ready_o, rx_frame_ready_o, empty_o;
  logic [3:0] tx_level_o, rx_level_o;
  always #20.833 clk_i = ~clk_i;
  spi_word_packer u_packer (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .clear_i         (clear_i),
      .frame16_i       (frame16_i),
      .direction_i     (direction_i),
      .quota_i         (quota_i),
      .tx_data_i       (tx_data_i),
      .tx_push_i       (tx_push_i),
      .rx_pop_i        (rx_pop_i),
      .frame_start_i   (request_start && tx_frame_ready_o && rx_frame_ready_o),
      .frame_done_i    (frame_done_i),
      .last_frame_i    (last_frame_i),
      .rx_frame_i      (rx_frame_i),
      .tx_frame_o      (tx_frame_o),
      .rx_data_o       (rx_data_o),
      .tx_words_o      (tx_words_o),
      .rx_words_o      (rx_words_o),
      .rx_removed_o    (rx_removed_o),
      .tx_ready_o      (tx_ready_o),
      .rx_ready_o      (rx_ready_o),
      .tx_frame_ready_o(tx_frame_ready_o),
      .rx_frame_ready_o(rx_frame_ready_o),
      .empty_o         (empty_o),
      .tx_level_o      (tx_level_o),
      .rx_level_o      (rx_level_o)
  );
  initial begin
    repeat (3) @(negedge clk_i);
    rst_n_i = 1;
    for (integer index = 0; index < 8; index++) begin
      tx_push_i = 1;
      tx_data_i = 32'(index);
      @(negedge clk_i);
    end
    if (tx_level_o != 8 || tx_ready_o) $fatal(1, "SPI full FIFO eligibility");
    request_start = 1;
    tx_push_i     = 1;
    @(negedge clk_i);
    request_start = 0;
    tx_push_i     = 0;
    if (tx_level_o != 7 || tx_words_o != 8) $fatal(1, "SPI full lookahead admitted extra word");
    clear_i = 1;
    @(negedge clk_i);
    clear_i       = 0;
    request_start = 1;
    tx_push_i     = 1;
    if (tx_frame_ready_o) $fatal(1, "SPI empty fallthrough");
    @(negedge clk_i);
    request_start = 0;
    tx_push_i     = 0;
    if (tx_level_o != 1 || tx_words_o != 1) $fatal(1, "SPI empty simultaneous push/pop");
    clear_i = 1;
    @(negedge clk_i);
    clear_i     = 0;
    direction_i = 2;
    frame16_i   = 1;
    for (integer frame = 0; frame < 16; frame++) begin
      request_start = 1;
      @(negedge clk_i);
      request_start = 0;
      frame_done_i  = 1;
      rx_frame_i    = 16'(frame);
      @(negedge clk_i);
      frame_done_i = 0;
    end
    if (rx_level_o != 8 || rx_frame_ready_o) $fatal(1, "SPI RX reservation at full");
    request_start = 1;
    rx_pop_i      = 1;
    @(negedge clk_i);
    request_start = 0;
    rx_pop_i      = 0;
    if (rx_level_o != 7 || rx_words_o != 8 || rx_removed_o != 1) $fatal(1, "SPI RX full pop");
    $display("SPI_P1_PASS spi_packer_tb");
    $finish;
  end
  initial begin
    #100000;
    $fatal(1, "SIM_TEST_TIMEOUT SPI packer");
  end
endmodule
