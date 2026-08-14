// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module i2c_filter (
    // verilog_format: off
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic [3:0] scl_filter_cycles_i,
    input  logic [3:0] sda_filter_cycles_i,
    input  logic       scl_async_i,
    input  logic       sda_async_i,
    output logic       scl_o,
    output logic       sda_o
    // verilog_format: on
);

  logic [1:0] s_line_sync;
  logic [3:0] s_scl_count_d, s_scl_count_q;
  logic [3:0] s_sda_count_d, s_sda_count_q;
  logic s_scl_d, s_scl_q;
  logic s_sda_d, s_sda_q;

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(2)
  ) u_line_cdc_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  ({sda_async_i, scl_async_i}),
      .dat_o  (s_line_sync)
  );

  always_comb begin
    s_scl_d       = s_scl_q;
    s_scl_count_d = s_scl_count_q;
    if (s_line_sync[0] == s_scl_q) begin
      s_scl_count_d = '0;
    end else if ((scl_filter_cycles_i == 4'd0) ||
                 (s_scl_count_q >= (scl_filter_cycles_i - 1'b1))) begin
      s_scl_d       = s_line_sync[0];
      s_scl_count_d = '0;
    end else begin
      s_scl_count_d = s_scl_count_q + 1'b1;
    end
  end

  always_comb begin
    s_sda_d       = s_sda_q;
    s_sda_count_d = s_sda_count_q;
    if (s_line_sync[1] == s_sda_q) begin
      s_sda_count_d = '0;
    end else if ((sda_filter_cycles_i == 4'd0) ||
                 (s_sda_count_q >= (sda_filter_cycles_i - 1'b1))) begin
      s_sda_d       = s_line_sync[1];
      s_sda_count_d = '0;
    end else begin
      s_sda_count_d = s_sda_count_q + 1'b1;
    end
  end

  dffrc #(
      .DATA_WIDTH(1),
      .RESET_VAL (1'b1)
  ) u_scl_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_scl_d),
      .dat_o  (s_scl_q)
  );

  dffrc #(
      .DATA_WIDTH(1),
      .RESET_VAL (1'b1)
  ) u_sda_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sda_d),
      .dat_o  (s_sda_q)
  );

  dffr #(
      .DATA_WIDTH(4)
  ) u_scl_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_scl_count_d),
      .dat_o  (s_scl_count_q)
  );

  dffr #(
      .DATA_WIDTH(4)
  ) u_sda_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sda_count_d),
      .dat_o  (s_sda_count_q)
  );

  assign scl_o = s_scl_q;
  assign sda_o = s_sda_q;

endmodule
