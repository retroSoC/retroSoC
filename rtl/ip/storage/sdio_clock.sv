// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`timescale 1ns / 1ps

module sdio_clock #(
    parameter int CounterWidth = 16
) (
    input  logic                    clk_i,
    input  logic                    rst_n_i,
    input  logic                    enable_i,
    input  logic [CounterWidth-1:0] half_period_i,
    output logic                    sck_o,
    output logic                    launch_tick_o,
    output logic                    sample_tick_o,
    output logic                    running_o
);
  logic [CounterWidth-1:0] s_phase_count_d, s_phase_count_q;
  logic s_sck_d, s_sck_q;
  logic [CounterWidth-1:0] s_half_period;
  logic                    s_phase_end;

  always_comb begin
    s_half_period   = (half_period_i == '0) ? {{(CounterWidth - 1) {1'b0}}, 1'b1} : half_period_i;
    s_phase_end     = s_phase_count_q + 1'b1 >= s_half_period;
    s_phase_count_d = s_phase_count_q;
    s_sck_d         = s_sck_q;
    if (!enable_i && !s_sck_q) begin
      s_phase_count_d = '0;
      s_sck_d         = 1'b0;
    end else if (s_phase_end) begin
      s_phase_count_d = '0;
      s_sck_d         = ~s_sck_q;
    end else begin
      s_phase_count_d = s_phase_count_q + 1'b1;
    end
  end

  assign launch_tick_o = s_phase_end && enable_i && !s_sck_q;
  assign sample_tick_o = s_phase_end && s_sck_q;
  assign sck_o         = s_sck_q;
  assign running_o     = s_sck_q || enable_i;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_phase_count_q <= '0;
      s_sck_q         <= 1'b0;
    end else begin
      s_phase_count_q <= s_phase_count_d;
      s_sck_q         <= s_sck_d;
    end
  end

`ifndef SYNTHESIS
  initial begin
    if (CounterWidth < 1) begin
      $fatal(1, "sdio_clock: CounterWidth must be positive");
    end
  end
`endif
endmodule
