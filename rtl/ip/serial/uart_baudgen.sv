// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module uart_baudgen (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        enable_i,
    input  logic [23:0] baud_int_i,
    input  logic [ 7:0] baud_frac_i,
    output logic        sample_tick_o,
    output logic        bit_tick_o
    // verilog_format: on
);

  localparam logic [31:0] SampleStep = 32'd4096;

  logic [31:0] s_period;
  logic [31:0] s_phase_d, s_phase_q;
  logic [3:0] s_sample_count_d, s_sample_count_q;
  logic [32:0] s_phase_sum;

  assign s_period      = {baud_int_i, baud_frac_i};
  assign s_phase_sum   = {1'b0, s_phase_q} + {1'b0, SampleStep};
  assign sample_tick_o = enable_i && (s_period >= SampleStep) && (s_phase_sum >= {1'b0, s_period});
  assign bit_tick_o    = sample_tick_o && (s_sample_count_q == 4'd15);

  always_comb begin
    s_phase_d        = s_phase_q;
    s_sample_count_d = s_sample_count_q;
    if (!enable_i || (s_period < SampleStep)) begin
      s_phase_d        = '0;
      s_sample_count_d = '0;
    end else if (sample_tick_o) begin
      s_phase_d        = 32'(s_phase_sum - {1'b0, s_period});
      s_sample_count_d = s_sample_count_q + 1'b1;
    end else begin
      s_phase_d = 32'(s_phase_sum);
    end
  end

  dffr #(
      .DATA_WIDTH(32)
  ) u_phase_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_phase_d),
      .dat_o  (s_phase_q)
  );

  dffr #(
      .DATA_WIDTH(4)
  ) u_sample_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sample_count_d),
      .dat_o  (s_sample_count_q)
  );

endmodule
