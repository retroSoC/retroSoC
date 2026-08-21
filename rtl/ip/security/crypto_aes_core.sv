// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module crypto_aes_core (
    // verilog_format: off -- crypto datapath ports are grouped by operation phase.
    input  logic         clk_i,
    input  logic         rst_n_i,
    input  logic         zeroize_i,
    input  logic         key_commit_i,
    input  logic [  1:0] key_size_i,
    input  logic [255:0] key_i,
    output logic         key_valid_o,
    input  logic         start_i,
    input  logic         decrypt_i,
    input  logic [127:0] block_i,
    output logic         busy_o,
    output logic         done_o,
    output logic [127:0] block_o
    // verilog_format: on
);
  import crypto_pkg::*;

  typedef enum logic [1:0] {
    AesIdle,
    AesKeyExpand,
    AesBlock
  } aes_state_e;

  aes_state_e         s_state_q;
  logic       [ 31:0] s_round_key_q     [0:59];
  logic       [  5:0] s_word_index_q;
  logic       [  5:0] s_total_words_q;
  logic       [  3:0] s_num_rounds_q;
  logic       [  3:0] s_round_q;
  logic       [  3:0] s_num_key_words_q;
  logic               s_decrypt_q;
  logic       [127:0] s_block_q;
  logic       [127:0] s_round_key;
  logic       [127:0] s_sub_shift;
  logic       [127:0] s_next_block;
  logic       [ 31:0] s_key_temp;
  logic       [ 31:0] s_expanded_word;

  always_comb begin
    s_round_key     = '0;
    s_key_temp      = '0;
    s_expanded_word = '0;
    s_sub_shift     = s_block_q;
    s_next_block    = s_block_q;

    if (s_state_q == AesKeyExpand) begin
      s_key_temp = s_round_key_q[s_word_index_q-6'd1];
      if ((s_word_index_q % 6'(s_num_key_words_q)) == 0) begin
        s_key_temp = aes_sub_word({s_key_temp[23:0], s_key_temp[31:24]}) ^
            {aes_rcon(4'(s_word_index_q / s_num_key_words_q)), 24'd0};
      end else if ((s_num_key_words_q == 4'd8) &&
                   ((s_word_index_q % 6'(s_num_key_words_q)) == 4)) begin
        s_key_temp = aes_sub_word(s_key_temp);
      end
      s_expanded_word = s_round_key_q[s_word_index_q-6'(s_num_key_words_q)] ^ s_key_temp;
    end else if (s_state_q == AesBlock) begin
      s_round_key = {
        s_round_key_q[{s_round_q, 2'b00}],
        s_round_key_q[{s_round_q, 2'b00}+6'd1],
        s_round_key_q[{s_round_q, 2'b00}+6'd2],
        s_round_key_q[{s_round_q, 2'b00}+6'd3]
      };
      if (s_decrypt_q) begin
        s_sub_shift = aes_inverse_sub_bytes(aes_inverse_shift_rows(s_block_q));
        if (s_round_q == 4'd0) begin
          s_next_block = s_sub_shift ^ s_round_key;
        end else begin
          s_next_block = aes_inverse_mix_columns(s_sub_shift ^ s_round_key);
        end
      end else begin
        s_sub_shift = aes_shift_rows(aes_sub_bytes(s_block_q));
        if (s_round_q == s_num_rounds_q) begin
          s_next_block = s_sub_shift ^ s_round_key;
        end else begin
          s_next_block = aes_mix_columns(s_sub_shift) ^ s_round_key;
        end
      end
    end
  end

  assign busy_o = s_state_q != AesIdle;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q         <= AesIdle;
      s_word_index_q    <= '0;
      s_total_words_q   <= '0;
      s_num_rounds_q    <= '0;
      s_round_q         <= '0;
      s_num_key_words_q <= '0;
      s_decrypt_q       <= 1'b0;
      s_block_q         <= '0;
      block_o           <= '0;
      key_valid_o       <= 1'b0;
      done_o            <= 1'b0;
    end else begin
      done_o <= 1'b0;
      if (zeroize_i) begin
        s_state_q   <= AesIdle;
        s_block_q   <= '0;
        block_o     <= '0;
        key_valid_o <= 1'b0;
        for (int unsigned index = 0; index < 60; index++) begin
          s_round_key_q[index] <= '0;
        end
      end else begin
        unique case (s_state_q)
          AesIdle: begin
            if (key_commit_i) begin
              unique case (key_size_i)
                AES_KEY_128: begin
                  s_num_key_words_q <= 4'd4;
                  s_num_rounds_q    <= 4'd10;
                  s_total_words_q   <= 6'd44;
                  s_word_index_q    <= 6'd4;
                end
                AES_KEY_192: begin
                  s_num_key_words_q <= 4'd6;
                  s_num_rounds_q    <= 4'd12;
                  s_total_words_q   <= 6'd52;
                  s_word_index_q    <= 6'd6;
                end
                AES_KEY_256: begin
                  s_num_key_words_q <= 4'd8;
                  s_num_rounds_q    <= 4'd14;
                  s_total_words_q   <= 6'd60;
                  s_word_index_q    <= 6'd8;
                end
                default: begin
                  s_num_key_words_q <= 4'd8;
                  s_num_rounds_q    <= 4'd14;
                  s_total_words_q   <= 6'd60;
                  s_word_index_q    <= 6'd8;
                end
              endcase
              for (int unsigned index = 0; index < 8; index++) begin
                s_round_key_q[index] <= key_i[255-index*32-:32];
              end
              key_valid_o <= 1'b0;
              s_state_q   <= AesKeyExpand;
            end else if (start_i && key_valid_o) begin
              s_decrypt_q <= decrypt_i;
              if (decrypt_i) begin
                s_round_q <= s_num_rounds_q - 1'b1;
                s_block_q <= block_i ^ {
                  s_round_key_q[{s_num_rounds_q, 2'b00}],
                  s_round_key_q[{s_num_rounds_q, 2'b00} + 6'd1],
                  s_round_key_q[{s_num_rounds_q, 2'b00} + 6'd2],
                  s_round_key_q[{s_num_rounds_q, 2'b00} + 6'd3]
                };
              end else begin
                s_round_q <= 4'd1;
                s_block_q <= block_i ^ {s_round_key_q[0], s_round_key_q[1],
                                        s_round_key_q[2], s_round_key_q[3]};
              end
              s_state_q <= AesBlock;
            end
          end
          AesKeyExpand: begin
            s_round_key_q[s_word_index_q] <= s_expanded_word;
            if (s_word_index_q == (s_total_words_q - 1'b1)) begin
              key_valid_o <= 1'b1;
              s_state_q   <= AesIdle;
            end else begin
              s_word_index_q <= s_word_index_q + 1'b1;
            end
          end
          default: begin
            s_block_q <= s_next_block;
            if ((!s_decrypt_q && (s_round_q == s_num_rounds_q)) ||
                (s_decrypt_q && (s_round_q == 4'd0))) begin
              block_o   <= s_next_block;
              done_o    <= 1'b1;
              s_state_q <= AesIdle;
            end else if (s_decrypt_q) begin
              s_round_q <= s_round_q - 1'b1;
            end else begin
              s_round_q <= s_round_q + 1'b1;
            end
          end
        endcase
      end
    end
  end
endmodule
