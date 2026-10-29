module piolite_stream_bfm (
    input  logic        clk_i,
    input  logic        rst_n_i,
    output logic        tx_valid_o,
    input  logic        tx_ready_i,
    output logic [31:0] tx_data_o,
    output logic [ 3:0] tx_keep_o,
    output logic [ 3:0] tx_strb_o,
    output logic        tx_id_o,
    output logic        tx_dest_o,
    output logic        tx_user_o,
    output logic        tx_last_o,
    input  logic        rx_valid_i,
    output logic        rx_ready_o,
    input  logic [31:0] rx_data_i,
    input  logic [ 3:0] rx_keep_i,
    input  logic [ 3:0] rx_strb_i,
    input  logic        rx_last_i,
    input  logic        rx_id_i,
    input  logic        rx_dest_i,
    input  logic        rx_user_i,
    output logic [31:0] tx_accepted_count_o,
    output logic [31:0] rx_accepted_count_o
);
  logic        s_rx_wait_q;
  logic [31:0] s_rx_data_q;
  logic        s_allow_rx;

  assign rx_ready_o = s_allow_rx;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      tx_accepted_count_o <= 32'd0;
      rx_accepted_count_o <= 32'd0;
      s_rx_wait_q         <= 1'b0;
      s_rx_data_q         <= 32'd0;
    end else begin
      if (tx_valid_o && tx_ready_i) tx_accepted_count_o <= tx_accepted_count_o + 32'd1;
      if (rx_valid_i && rx_ready_o) rx_accepted_count_o <= rx_accepted_count_o + 32'd1;
      if (s_rx_wait_q) begin
        if (!rx_valid_i || (rx_data_i !== s_rx_data_q))
          $fatal(
              1,
              "PIOLITE RX changed under backpressure valid=%b data=%h previous=%h",
              rx_valid_i,
              rx_data_i,
              s_rx_data_q
          );
        if ((rx_keep_i !== 4'hf) || (rx_strb_i !== 4'hf) || rx_last_i || rx_id_i ||
            rx_dest_i || rx_user_i)
          $fatal(1, "PIOLITE RX sidebands changed under backpressure");
      end
      s_rx_wait_q <= rx_valid_i && !rx_ready_o;
      s_rx_data_q <= rx_data_i;
      if (rx_valid_i && ((rx_keep_i !== 4'hf) || (rx_strb_i !== 4'hf) || rx_last_i ||
          rx_id_i || rx_dest_i || rx_user_i))
        $fatal(1, "PIOLITE RX constant sidebands are invalid");
    end
  end

  task automatic reset_bfm;
    tx_valid_o = 1'b0;
    tx_data_o  = 32'd0;
    tx_keep_o  = 4'hf;
    tx_strb_o  = 4'hf;
    tx_id_o    = 1'b0;
    tx_dest_o  = 1'b0;
    tx_user_o  = 1'b0;
    tx_last_o  = 1'b0;
    s_allow_rx = 1'b0;
  endtask

  task automatic send_tx(input logic [31:0] word, input logic [3:0] keep, input logic [3:0] strb,
                         input logic identity);
    @(negedge clk_i);
    tx_data_o  = word;
    tx_keep_o  = keep;
    tx_strb_o  = strb;
    tx_id_o    = identity;
    tx_dest_o  = 1'b0;
    tx_user_o  = 1'b0;
    tx_valid_o = 1'b1;
    do @(posedge clk_i); while (!tx_ready_i);
    @(negedge clk_i);
    tx_valid_o = 1'b0;
    tx_keep_o  = 4'hf;
    tx_strb_o  = 4'hf;
    tx_id_o    = 1'b0;
  endtask

  task automatic expect_rx(input logic [31:0] expected, input integer timeout_cycles);
    integer cycles;
    logic   observed;
    cycles     = 0;
    observed   = 1'b0;
    s_allow_rx = 1'b0;
    while (!observed && (cycles < timeout_cycles)) begin
      @(negedge clk_i);
      cycles++;
      if (rx_valid_i) begin
        if (rx_data_i !== expected) $fatal(1, "PIOLITE RX got=%h expected=%h", rx_data_i, expected);
        observed = 1'b1;
      end
    end
    if (!observed) $fatal(1, "PIOLITE RX timeout");
    s_allow_rx = 1'b1;
    @(negedge clk_i);
    s_allow_rx = 1'b0;
  endtask
endmodule
