// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module xpi_clkgen (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       mode3_i,
    input  logic [7:0] div_i,
    input  logic       enable_i,
    output logic       sclk_o,
    output logic       sample_edge_o,
    output logic       shift_edge_o
    // verilog_format: on
);

  logic [7:0] s_div_cnt_d, s_div_cnt_q;
  logic s_sclk_d, s_sclk_q;
  logic s_edge_due;

  assign s_edge_due    = enable_i && (s_div_cnt_q == div_i);
  assign sample_edge_o = s_edge_due && (s_sclk_q == mode3_i);
  assign shift_edge_o  = s_edge_due && (s_sclk_q != mode3_i);
  assign sclk_o        = s_sclk_q;

  always_comb begin
    s_div_cnt_d = s_div_cnt_q;
    s_sclk_d    = s_sclk_q;
    if (!enable_i) begin
      s_div_cnt_d = '0;
      s_sclk_d    = mode3_i;
    end else if (s_edge_due) begin
      s_div_cnt_d = '0;
      s_sclk_d    = ~s_sclk_q;
    end else begin
      s_div_cnt_d = s_div_cnt_q + 1'b1;
    end
  end

  dffr #(
      .DATA_WIDTH(8)
  ) u_div_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_div_cnt_d),
      .dat_o  (s_div_cnt_q)
  );

  dffr #(
      .DATA_WIDTH(1)
  ) u_sclk_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sclk_d),
      .dat_o  (s_sclk_q)
  );

endmodule
