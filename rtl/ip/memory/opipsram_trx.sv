// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module opipsram_trx (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic       clk_phy_i,
    input  logic       rst_phy_n_i,
    input  logic       rx_flush_i,
    input  logic       rx_enable_i,
    input  logic [7:0] rx_delay_i,
    input  logic       cs_n_i,
    input  logic [7:0] dq_i,
    input  logic       rwds_i,
    input  logic       tx_enable_i,
    input  logic [7:0] tx_data_i,
    input  logic       tx_rwds_enable_i,
    input  logic       tx_rwds_i,
    output logic [7:0] dq_oe_o,
    output logic [7:0] dq_o,
    output logic       rwds_oe_o,
    output logic       rwds_o,
    output logic       rwds_delayed_o,
    output logic       rx_byte_valid_o,
    input  logic       rx_byte_ready_i,
    output logic [7:0] rx_byte_o,
    output logic       rx_overflow_o
    // verilog_format: on
);

  logic        s_rwds_delayed;
  logic        s_rwds_inverted;
  logic [ 7:0] s_rx_delay_value_q;
  logic        s_first_valid_q;
  logic [ 7:0] s_first_byte_q;
  logic        s_fifo_wr_clk;
  logic        s_fifo_wr_en;
  logic        s_fifo_full;
  logic [15:0] s_fifo_wr_data;
  logic [15:0] s_fifo_rd_data;
  logic        s_fifo_rd_en;
  logic        s_fifo_empty;
  logic        s_fifo_rst_n;
  logic        s_word_valid_q;
  logic        s_word_pending_q;
  logic [15:0] s_word_q;
  logic        s_word_second_q;
  logic [ 7:0] s_tx_data_q;
  logic        s_tx_rwds_q;
  logic        s_tx_en_q;
  logic        s_tx_rwds_en_q;
  logic        s_fifo_overflow_q;
  logic        s_fifo_overflow_sync1_q;
  logic        s_fifo_overflow_sync2_q;
  logic [ 3:0] unused_fifo_elements;

`ifdef SV_ASSRT_DISABLE
  logic s_rwds_prev_q;
  logic s_rwds_inverted_prev_q;
  logic s_formal_posedge;
  logic s_formal_negedge;
`endif

  assign s_fifo_rst_n    = rst_phy_n_i && !rx_flush_i;
  assign s_fifo_wr_data  = {s_first_byte_q, dq_i};
  assign s_fifo_rd_en    = !s_word_valid_q && !s_word_pending_q && !s_fifo_empty;
  assign rx_byte_valid_o = s_word_valid_q;
  assign rx_byte_o       = s_word_second_q ? s_word_q[7:0] : s_word_q[15:8];
  assign rwds_delayed_o  = s_rwds_delayed;
  assign dq_oe_o         = cs_n_i ? 8'd0 : (s_tx_en_q ? 8'hFF : 8'd0);
  assign dq_o            = s_tx_data_q;
  assign rwds_oe_o       = cs_n_i ? 1'b0 : s_tx_rwds_en_q;
  assign rwds_o          = s_tx_rwds_q;

`ifdef SV_ASSRT_DISABLE
  assign s_fifo_wr_clk    = clk_phy_i;
  assign s_formal_posedge = s_rwds_delayed && !s_rwds_prev_q;
  assign s_formal_negedge = s_rwds_inverted && !s_rwds_inverted_prev_q;
  assign s_fifo_wr_en     = rx_enable_i && s_formal_negedge && s_first_valid_q && !s_fifo_full;
`else
  assign s_fifo_wr_clk = s_rwds_inverted;
  assign s_fifo_wr_en  = rx_enable_i && s_first_valid_q && !s_fifo_full;
`endif

  assign rx_overflow_o = s_fifo_overflow_sync2_q;

  tc_opipsram_delay u_rwds_delay (
      .data_i  (rwds_i),
      .fine_i  (s_rx_delay_value_q[4:0]),
      .coarse_i(s_rx_delay_value_q[7:5]),
      .data_o  (s_rwds_delayed)
  );

  tc_clk_inv u_rwds_inv (
      .clk_i(s_rwds_delayed),
      .clk_o(s_rwds_inverted)
  );

  async_fifo #(
      .DataWidth (16),
      .DepthPower(3)
  ) u_rx_fifo (
      .wr_clk_i  (s_fifo_wr_clk),
      .wr_rst_n_i(s_fifo_rst_n),
      .wr_en_i   (s_fifo_wr_en),
      .wr_data_i (s_fifo_wr_data),
      .wr_full_o (s_fifo_full),
      .rd_clk_i  (clk_phy_i),
      .rd_rst_n_i(s_fifo_rst_n),
      .rd_en_i   (s_fifo_rd_en),
      .rd_data_o (s_fifo_rd_data),
      .rd_empty_o(s_fifo_empty),
      .elem_num_o(unused_fifo_elements)
  );

`ifdef SV_ASSRT_DISABLE
  always_ff @(posedge clk_phy_i or negedge rst_phy_n_i) begin
    if (!rst_phy_n_i) begin
      s_rwds_prev_q          <= 1'b0;
      s_rwds_inverted_prev_q <= 1'b1;
      s_first_valid_q        <= 1'b0;
      s_first_byte_q         <= 8'd0;
    end else begin
      s_rwds_prev_q          <= s_rwds_delayed;
      s_rwds_inverted_prev_q <= s_rwds_inverted;
      if (!rx_enable_i) begin
        s_first_valid_q <= 1'b0;
      end else begin
        if (s_formal_posedge) begin
          s_first_byte_q  <= dq_i;
          s_first_valid_q <= 1'b1;
        end
        if (s_formal_negedge && s_first_valid_q) s_first_valid_q <= 1'b0;
      end
    end
  end
`else
  always_ff @(posedge s_rwds_delayed or negedge s_fifo_rst_n) begin
    if (!s_fifo_rst_n) begin
      s_first_valid_q <= 1'b0;
      s_first_byte_q  <= 8'd0;
    end else if (rx_enable_i) begin
      s_first_valid_q <= 1'b1;
      s_first_byte_q  <= dq_i;
    end else begin
      s_first_valid_q <= 1'b0;
    end
  end
`endif

  always_ff @(posedge s_fifo_wr_clk or negedge s_fifo_rst_n) begin
    if (!s_fifo_rst_n) begin
      s_fifo_overflow_q <= 1'b0;
    end else if (rx_enable_i && s_first_valid_q && s_fifo_full) begin
      s_fifo_overflow_q <= 1'b1;
    end
  end

  always_ff @(posedge clk_phy_i or negedge rst_phy_n_i) begin
    if (!rst_phy_n_i) begin
      s_rx_delay_value_q      <= 8'd0;
      s_word_valid_q          <= 1'b0;
      s_word_pending_q        <= 1'b0;
      s_word_q                <= 16'd0;
      s_word_second_q         <= 1'b0;
      s_fifo_overflow_sync1_q <= 1'b0;
      s_fifo_overflow_sync2_q <= 1'b0;
    end else begin
      s_fifo_overflow_sync1_q <= s_fifo_overflow_q;
      s_fifo_overflow_sync2_q <= s_fifo_overflow_sync1_q;
      if (!rx_enable_i) begin
        s_rx_delay_value_q      <= rx_delay_i;
        s_word_valid_q          <= 1'b0;
        s_word_pending_q        <= 1'b0;
        s_word_second_q         <= 1'b0;
        s_fifo_overflow_sync1_q <= 1'b0;
        s_fifo_overflow_sync2_q <= 1'b0;
      end else begin
        if (s_fifo_rd_en) s_word_pending_q <= 1'b1;
        if (s_word_pending_q) begin
          s_word_q         <= s_fifo_rd_data;
          s_word_pending_q <= 1'b0;
          s_word_valid_q   <= 1'b1;
          s_word_second_q  <= 1'b0;
        end
        if (rx_byte_valid_o && rx_byte_ready_i) begin
          if (!s_word_second_q) begin
            s_word_second_q <= 1'b1;
          end else begin
            s_word_second_q <= 1'b0;
            s_word_valid_q  <= 1'b0;
          end
        end
      end
    end
  end

`ifdef SV_ASSRT_DISABLE
  `define RETROSOC_OPIPSRAM__TRX_TX_EDGE posedge clk_phy_i
`else
  `define RETROSOC_OPIPSRAM__TRX_TX_EDGE negedge clk_phy_i
`endif
  always_ff @(`RETROSOC_OPIPSRAM__TRX_TX_EDGE or negedge rst_phy_n_i) begin
    if (!rst_phy_n_i) begin
      s_tx_data_q    <= 8'd0;
      s_tx_rwds_q    <= 1'b0;
      s_tx_en_q      <= 1'b0;
      s_tx_rwds_en_q <= 1'b0;
    end else begin
      s_tx_data_q    <= tx_data_i;
      s_tx_rwds_q    <= tx_rwds_i;
      s_tx_en_q      <= tx_enable_i;
      s_tx_rwds_en_q <= tx_rwds_enable_i;
    end
  end
  `undef RETROSOC_OPIPSRAM__TRX_TX_EDGE

endmodule
