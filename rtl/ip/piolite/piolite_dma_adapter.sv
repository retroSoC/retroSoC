module piolite_dma_adapter (
    input  logic                            clk_i,
    input  logic                            rst_n_i,
    input  logic                            block_reset_i,
    input  logic                     [ 1:0] sm_reset_i,
    input  piolite_pkg::sm_runtime_t        runtime_i           [0:1],
    input  logic                     [31:0] tx_bind_i,
    input  logic                     [31:0] rx_bind_i,
    input  logic                     [ 1:0] guard_fault_i,
    input  logic                     [ 3:0] rx_level_i          [0:1],
    input  logic                            tx_valid_i,
    output logic                            tx_ready_o,
    input  logic                     [31:0] tx_data_i,
    input  logic                     [ 3:0] tx_keep_i,
    input  logic                     [ 3:0] tx_strb_i,
    input  logic                            tx_id_i,
    input  logic                            tx_dest_i,
    input  logic                            tx_user_i,
    input  logic                            tx_last_i,
    output logic                            tx_fifo_push_o,
    output logic                     [31:0] tx_fifo_data_o,
    output logic                            tx_fifo_sm_o,
    input  logic                            tx_fifo_accept_i,
    output logic                            rx_fifo_pop_o,
    output logic                            rx_fifo_sm_o,
    input  logic                     [31:0] rx_fifo_data_i,
    input  logic                            rx_fifo_accept_i,
    output logic                            rx_valid_o,
    input  logic                            rx_ready_i,
    output logic                     [31:0] rx_data_o,
    output logic                     [ 3:0] rx_keep_o,
    output logic                     [ 3:0] rx_strb_o,
    output logic                            rx_last_o,
    output logic                            rx_id_o,
    output logic                            rx_dest_o,
    output logic                            rx_user_o,
    output logic                            tx_held_o,
    output logic                            rx_held_o,
    output logic                            tx_closing_o,
    output logic                            rx_closing_o,
    output logic                            stream_fault_valid_o,
    output logic                            stream_fault_sm_o
);
  logic        s_tx_held_d;
  logic        s_tx_held_q;
  logic        s_tx_sm_d;
  logic        s_tx_sm_q;
  logic [31:0] s_tx_data_d;
  logic [31:0] s_tx_data_q;
  logic        s_rx_held_d;
  logic        s_rx_held_q;
  logic        s_rx_sm_d;
  logic        s_rx_sm_q;
  logic [31:0] s_rx_data_d;
  logic [31:0] s_rx_data_q;
  logic        s_tx_closing;
  logic        s_rx_closing;
  logic        s_tx_accept;
  logic        s_rx_accept;
  logic        s_tx_beat_valid;
  logic        s_unused;

  assign s_tx_closing = s_tx_held_q ? (runtime_i[s_tx_sm_q].state == piolite_pkg::Closing) :
      (tx_bind_i[31] && (runtime_i[tx_bind_i[0]].state == piolite_pkg::Closing));
  assign s_rx_closing = s_rx_held_q ? (runtime_i[s_rx_sm_q].state == piolite_pkg::Closing) :
      (rx_bind_i[31] && (runtime_i[rx_bind_i[0]].state == piolite_pkg::Closing));
  assign tx_ready_o = tx_bind_i[31] && (s_tx_closing ||
      (!s_tx_held_q && !guard_fault_i[tx_bind_i[0]]));
  assign s_tx_accept = tx_valid_i && tx_ready_o;
  assign s_tx_beat_valid = (tx_keep_i == 4'hf) && (tx_strb_i == 4'hf) &&
      !tx_id_i && !tx_dest_i && !tx_user_i;
  assign s_rx_accept = rx_valid_o && rx_ready_i;
  assign tx_fifo_push_o = s_tx_held_q && !s_tx_closing;
  assign tx_fifo_data_o = s_tx_data_q;
  assign tx_fifo_sm_o = s_tx_sm_q;
  assign rx_fifo_pop_o = !s_rx_held_q && rx_bind_i[31] && !s_rx_closing &&
      !guard_fault_i[rx_bind_i[0]] && (rx_level_i[rx_bind_i[0]] != 4'd0);
  assign rx_fifo_sm_o = rx_bind_i[0];
  assign rx_valid_o = s_rx_held_q;
  assign rx_data_o = s_rx_data_q;
  assign rx_keep_o = 4'hf;
  assign rx_strb_o = 4'hf;
  assign rx_last_o = 1'b0;
  assign rx_id_o = 1'b0;
  assign rx_dest_o = 1'b0;
  assign rx_user_o = 1'b0;
  assign tx_held_o = s_tx_held_q;
  assign rx_held_o = s_rx_held_q;
  assign tx_closing_o = s_tx_closing;
  assign rx_closing_o = s_rx_closing;
  assign stream_fault_valid_o = s_tx_accept && !s_tx_closing && !s_tx_beat_valid;
  assign stream_fault_sm_o = tx_bind_i[0];
  assign s_unused = tx_last_i ^ ^{tx_bind_i[30:1], rx_bind_i[30:1]};

  always_comb begin
    s_tx_held_d = s_tx_held_q;
    s_tx_sm_d   = s_tx_sm_q;
    s_tx_data_d = s_tx_data_q;
    s_rx_held_d = s_rx_held_q;
    s_rx_sm_d   = s_rx_sm_q;
    s_rx_data_d = s_rx_data_q;
    if (tx_fifo_accept_i) s_tx_held_d = 1'b0;
    if (s_tx_accept) begin
      if (!s_tx_closing && s_tx_beat_valid) begin
        s_tx_held_d = 1'b1;
        s_tx_sm_d   = tx_bind_i[0];
        s_tx_data_d = tx_data_i;
      end else begin
        s_tx_held_d = 1'b0;
      end
    end
    if (s_tx_closing) s_tx_held_d = 1'b0;
    if (s_rx_accept) s_rx_held_d = 1'b0;
    if (rx_fifo_accept_i) begin
      s_rx_held_d = 1'b1;
      s_rx_sm_d   = rx_fifo_sm_o;
      s_rx_data_d = rx_fifo_data_i;
    end
    if ((s_tx_held_q && sm_reset_i[s_tx_sm_q]) || block_reset_i) s_tx_held_d = 1'b0;
    if ((s_rx_held_q && sm_reset_i[s_rx_sm_q]) || block_reset_i) s_rx_held_d = 1'b0;
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_tx_held (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_held_d),
      .dat_o  (s_tx_held_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_tx_sm (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_sm_d),
      .dat_o  (s_tx_sm_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_tx_data (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_data_d),
      .dat_o  (s_tx_data_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rx_held (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_held_d),
      .dat_o  (s_rx_held_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rx_sm (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_sm_d),
      .dat_o  (s_rx_sm_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_rx_data (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_data_d),
      .dat_o  (s_rx_data_q)
  );
endmodule
