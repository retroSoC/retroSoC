// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module crypto_sha2_core (
    // verilog_format: off -- hash state and block ports remain visually grouped.
    input  logic         clk_i,
    input  logic         rst_n_i,
    input  logic         zeroize_i,
    input  logic         start_i,
    input  logic [255:0] state_i,
    input  logic [511:0] block_i,
    output logic         busy_o,
    output logic         done_o,
    output logic [255:0] state_o
    // verilog_format: on
);
  import crypto_pkg::*;

  logic [ 31:0] s_schedule_q      [0:15];
  logic [  5:0] s_round_q;
  logic [ 31:0] s_a_q;
  logic [ 31:0] s_b_q;
  logic [ 31:0] s_c_q;
  logic [ 31:0] s_d_q;
  logic [ 31:0] s_e_q;
  logic [ 31:0] s_f_q;
  logic [ 31:0] s_g_q;
  logic [ 31:0] s_h_q;
  logic [255:0] s_initial_state_q;
  logic [ 31:0] s_word;
  logic [ 31:0] s_choice;
  logic [ 31:0] s_majority;
  logic [ 31:0] s_temp1;
  logic [ 31:0] s_temp2;

  always_comb begin
    s_word     = '0;
    s_choice   = '0;
    s_majority = '0;
    s_temp1    = '0;
    s_temp2    = '0;
    if (busy_o) begin
      if (s_round_q < 6'd16) begin
        s_word = s_schedule_q[s_round_q[3:0]];
      end else begin
        s_word = sha2_sigma1(s_schedule_q[4'(s_round_q-6'd2)]) + s_schedule_q[4'(s_round_q-6'd7)] +
            sha2_sigma0(s_schedule_q[4'(s_round_q-6'd15)]) + s_schedule_q[s_round_q[3:0]];
      end
      s_choice   = (s_e_q & s_f_q) ^ ((~s_e_q) & s_g_q);
      s_majority = (s_a_q & s_b_q) ^ (s_a_q & s_c_q) ^ (s_b_q & s_c_q);
      s_temp1    = s_h_q + sha2_sum1(s_e_q) + s_choice + sha2_k(s_round_q) + s_word;
      s_temp2    = sha2_sum0(s_a_q) + s_majority;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      busy_o            <= 1'b0;
      done_o            <= 1'b0;
      state_o           <= '0;
      s_round_q         <= '0;
      s_a_q             <= '0;
      s_b_q             <= '0;
      s_c_q             <= '0;
      s_d_q             <= '0;
      s_e_q             <= '0;
      s_f_q             <= '0;
      s_g_q             <= '0;
      s_h_q             <= '0;
      s_initial_state_q <= '0;
    end else begin
      done_o <= 1'b0;
      if (zeroize_i) begin
        busy_o            <= 1'b0;
        state_o           <= '0;
        s_round_q         <= '0;
        s_a_q             <= '0;
        s_b_q             <= '0;
        s_c_q             <= '0;
        s_d_q             <= '0;
        s_e_q             <= '0;
        s_f_q             <= '0;
        s_g_q             <= '0;
        s_h_q             <= '0;
        s_initial_state_q <= '0;
        for (int unsigned index = 0; index < 16; index++) begin
          s_schedule_q[index] <= '0;
        end
      end else if (start_i && !busy_o) begin
        for (int unsigned index = 0; index < 16; index++) begin
          s_schedule_q[index] <= block_i[511-index*32-:32];
        end
        s_a_q             <= state_i[255:224];
        s_b_q             <= state_i[223:192];
        s_c_q             <= state_i[191:160];
        s_d_q             <= state_i[159:128];
        s_e_q             <= state_i[127:96];
        s_f_q             <= state_i[95:64];
        s_g_q             <= state_i[63:32];
        s_h_q             <= state_i[31:0];
        s_initial_state_q <= state_i;
        s_round_q         <= '0;
        busy_o            <= 1'b1;
      end else if (busy_o) begin
        if (s_round_q >= 6'd16) begin
          s_schedule_q[s_round_q[3:0]] <= s_word;
        end
        s_h_q <= s_g_q;
        s_g_q <= s_f_q;
        s_f_q <= s_e_q;
        s_e_q <= s_d_q + s_temp1;
        s_d_q <= s_c_q;
        s_c_q <= s_b_q;
        s_b_q <= s_a_q;
        s_a_q <= s_temp1 + s_temp2;
        if (s_round_q == 6'd63) begin
          state_o <= {
            s_initial_state_q[255:224] + s_temp1 + s_temp2,
            s_initial_state_q[223:192] + s_a_q,
            s_initial_state_q[191:160] + s_b_q,
            s_initial_state_q[159:128] + s_c_q,
            s_initial_state_q[127:96] + s_d_q + s_temp1,
            s_initial_state_q[95:64] + s_e_q,
            s_initial_state_q[63:32] + s_f_q,
            s_initial_state_q[31:0] + s_g_q
          };
          busy_o <= 1'b0;
          done_o <= 1'b1;
        end else begin
          s_round_q <= s_round_q + 1'b1;
        end
      end
    end
  end
endmodule
