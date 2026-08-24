// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
// See LICENSE for the complete license text.

`timescale 1ns / 1ps

module spisd_clock #(
    parameter int CounterWidth = 16
) (
    // verilog_format: off -- preserve the reviewed clock-phase port alignment
    input  logic                    clk_i,
    input  logic                    rst_n_i,
    input  logic                    enable_i,
    input  logic                    pause_i,
    input  logic [CounterWidth-1:0] half_period_i,
    output logic                    sck_o,
    output logic                    rise_tick_o,
    output logic                    fall_tick_o,
    output logic                    running_o
    // verilog_format: on
);
  logic [CounterWidth-1:0] s_phase_cnt_d, s_phase_cnt_q;
  logic s_sck_d, s_sck_q;
  logic [CounterWidth-1:0] s_half_period;
  logic                    s_phase_end;
  logic                    s_hold_low;

  assign s_half_period = (half_period_i == '0) ? CounterWidth'(1) : half_period_i;
  assign s_phase_end   = (s_phase_cnt_q + 1'b1) >= s_half_period;
  assign s_hold_low    = !s_sck_q && (!enable_i || pause_i);
  assign rise_tick_o   = s_phase_end && enable_i && !pause_i && !s_sck_q;
  assign fall_tick_o   = s_phase_end && s_sck_q;
  assign sck_o         = s_sck_q;
  assign running_o     = s_sck_q || enable_i;

  always_comb begin
    s_phase_cnt_d = s_phase_cnt_q;
    s_sck_d       = s_sck_q;
    if (s_hold_low) begin
      s_phase_cnt_d = '0;
      s_sck_d       = 1'b0;
    end else if (s_phase_end) begin
      s_phase_cnt_d = '0;
      s_sck_d       = ~s_sck_q;
    end else begin
      s_phase_cnt_d = s_phase_cnt_q + 1'b1;
    end
  end

  dffr #(
      .DATA_WIDTH(CounterWidth)
  ) u_phase_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_phase_cnt_d),
      .dat_o  (s_phase_cnt_q)
  );

  dffr u_sck_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sck_d),
      .dat_o  (s_sck_q)
  );

`ifndef SYNTHESIS
  initial begin
    if (CounterWidth < 1) $fatal(1, "spisd_clock: CounterWidth must be positive");
  end
`endif
endmodule
