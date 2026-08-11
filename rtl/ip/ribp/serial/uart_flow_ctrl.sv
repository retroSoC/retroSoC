// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module uart_flow_ctrl (
    // verilog_format: off
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       cts_n_async_i,
    input  logic       auto_cts_enable_i,
    input  logic       auto_rts_enable_i,
    input  logic       tx_enable_i,
    input  logic       rx_enable_i,
    input  logic       loopback_i,
    input  logic       tx_data_valid_i,
    input  logic       tx_busy_i,
    input  logic [6:0] rx_level_i,
    input  logic [6:0] rts_assert_level_i,
    input  logic [6:0] rts_deassert_level_i,
    output logic       cts_asserted_o,
    output logic       rts_asserted_o,
    output logic       tx_start_allowed_o,
    output logic       tx_flow_blocked_o,
    output logic       cts_change_o,
    output logic       rts_n_o
    // verilog_format: on
);

  logic s_cts_rise;
  logic s_cts_fall;
  logic s_rts_asserted_d, s_rts_asserted_q;

  // Synchronize the logical asserted state so reset is fail-safe: not clear to send.
  edge_det #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_cts_edge_det (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (~cts_n_async_i),
      .dat_o  (cts_asserted_o),
      .re_o   (s_cts_rise),
      .fe_o   (s_cts_fall)
  );

  always_comb begin
    s_rts_asserted_d = s_rts_asserted_q;
    if (!auto_rts_enable_i || !rx_enable_i) begin
      s_rts_asserted_d = 1'b0;
    end else if (rx_level_i >= rts_deassert_level_i) begin
      s_rts_asserted_d = 1'b0;
    end else if (rx_level_i <= rts_assert_level_i) begin
      s_rts_asserted_d = 1'b1;
    end
  end

  dffr #(1) u_rts_asserted_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rts_asserted_d),
      .dat_o  (s_rts_asserted_q)
  );

  assign rts_asserted_o = auto_rts_enable_i && rx_enable_i && s_rts_asserted_q;
  assign rts_n_o = ~rts_asserted_o;
  assign tx_start_allowed_o = loopback_i || !auto_cts_enable_i || cts_asserted_o;
  assign tx_flow_blocked_o  = auto_cts_enable_i && tx_enable_i && tx_data_valid_i &&
                              !tx_busy_i && !cts_asserted_o && !loopback_i;
  assign cts_change_o = auto_cts_enable_i && (s_cts_rise || s_cts_fall);

endmodule
