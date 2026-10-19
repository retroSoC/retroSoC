// Common FIFO inputs are pre-qualified: full plus pop does NOT accept a push.
module spi_word_packer (
    input  logic        clk_i,
    rst_n_i,
    clear_i,
    frame16_i,
    input  logic [ 1:0] direction_i,
    input  logic [31:0] quota_i,
    tx_data_i,
    input  logic        tx_push_i,
    rx_pop_i,
    frame_start_i,
    frame_done_i,
    last_frame_i,
    input  logic [15:0] rx_frame_i,
    output logic [15:0] tx_frame_o,
    output logic [31:0] rx_data_o,
    tx_words_o,
    rx_words_o,
    rx_removed_o,
    output logic        tx_ready_o,
    rx_ready_o,
    tx_frame_ready_o,
    rx_frame_ready_o,
    empty_o,
    output logic [ 3:0] tx_level_o,
    rx_level_o
);
  typedef struct packed {
    logic [31:0] tx_word,  rx_word, accepted, produced, removed;
    logic [1:0]  tx_lane,  rx_lane;
    logic        tx_valid;
  } packing_t;
  packing_t s_pack_d, s_pack_q;
  logic s_tx_full, s_tx_empty, s_rx_full, s_rx_empty;
  logic s_tx_pop, s_rx_push;
  logic [31:0] s_tx_head, s_tx_word, s_rx_word;
  logic [1:0] s_last_lane;
  logic [4:0] s_tx_shift, s_rx_shift;
  assign s_last_lane = frame16_i ? 2'd1 : 2'd3;
  assign s_tx_shift = frame16_i ? {s_pack_q.tx_lane[0], 4'd0} : {s_pack_q.tx_lane, 3'd0};
  assign s_rx_shift = frame16_i ? {s_pack_q.rx_lane[0], 4'd0} : {s_pack_q.rx_lane, 3'd0};
  assign s_tx_word = s_pack_q.tx_valid ? s_pack_q.tx_word : s_tx_head;
  assign tx_frame_o = 16'(s_tx_word >> s_tx_shift);
  assign s_rx_word = s_pack_q.rx_word |
      ((frame16_i ? {16'd0, rx_frame_i} : {24'd0, rx_frame_i[7:0]}) << s_rx_shift);
  assign tx_ready_o = !s_tx_full && (s_pack_q.accepted < quota_i);
  assign rx_ready_o = !s_rx_empty && (s_pack_q.removed < quota_i);
  assign tx_frame_ready_o = (direction_i == 2'd2) || s_pack_q.tx_valid || !s_tx_empty;
  assign rx_frame_ready_o = (direction_i == 2'd0) || (s_pack_q.rx_lane != 2'd0) || !s_rx_full;
  assign s_tx_pop = frame_start_i && (direction_i != 2'd2) && !s_pack_q.tx_valid;
  assign s_rx_push = frame_done_i && (direction_i != 2'd0) &&
      ((s_pack_q.rx_lane == s_last_lane) || last_frame_i);
  assign empty_o = s_tx_empty && s_rx_empty && !s_pack_q.tx_valid && (s_pack_q.rx_lane == 2'd0);
  assign tx_words_o = s_pack_q.accepted;
  assign rx_words_o = s_pack_q.produced;
  assign rx_removed_o = s_pack_q.removed;
  always_comb begin
    s_pack_d = s_pack_q;
    if (tx_push_i && tx_ready_o) s_pack_d.accepted = s_pack_q.accepted + 32'd1;
    if (rx_pop_i && rx_ready_o) s_pack_d.removed = s_pack_q.removed + 32'd1;
    if (frame_start_i && (direction_i != 2'd2)) begin
      s_pack_d.tx_word  = s_tx_word;
      s_pack_d.tx_valid = !last_frame_i && (s_pack_q.tx_lane != s_last_lane);
      s_pack_d.tx_lane  = s_pack_d.tx_valid ? s_pack_q.tx_lane + 2'd1 : 2'd0;
    end
    if (frame_done_i && (direction_i != 2'd0)) begin
      s_pack_d.rx_word = s_rx_push ? 32'd0 : s_rx_word;
      s_pack_d.rx_lane = s_rx_push ? 2'd0 : s_pack_q.rx_lane + 2'd1;
      if (s_rx_push) s_pack_d.produced = s_pack_q.produced + 32'd1;
    end
    if (clear_i) s_pack_d = '0;
  end
  dffr #(
      .DATA_WIDTH($bits(packing_t))
  ) u_packing (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pack_d),
      .dat_o  (s_pack_q)
  );
  fifo #(
      .DATA_WIDTH  (32),
      .BUFFER_DEPTH(8)
  ) u_tx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(clear_i),
      .push_i (tx_push_i && tx_ready_o),
      .full_o (s_tx_full),
      .dat_i  (tx_data_i),
      .pop_i  (s_tx_pop && !s_tx_empty),
      .empty_o(s_tx_empty),
      .dat_o  (s_tx_head),
      .cnt_o  (tx_level_o)
  );
  fifo #(
      .DATA_WIDTH  (32),
      .BUFFER_DEPTH(8)
  ) u_rx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(clear_i),
      .push_i (s_rx_push && !s_rx_full),
      .full_o (s_rx_full),
      .dat_i  (s_rx_word),
      .pop_i  (rx_pop_i && rx_ready_o),
      .empty_o(s_rx_empty),
      .dat_o  (rx_data_o),
      .cnt_o  (rx_level_o)
  );
endmodule
