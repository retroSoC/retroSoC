// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module crypto_rsa_core #(
    parameter int Bits = 2048
) (
    // verilog_format: off -- RSA command, operand, and observation ports are grouped.
    input  logic            clk_i,
    input  logic            rst_n_i,
    input  logic            zeroize_i,
    input  logic            abort_i,
    input  logic            prepare_i,
    input  logic            start_i,
    input  logic            private_i,
    input  logic [      11:0] exponent_bits_i,
    input  logic [Bits-1:0] modulus_i,
    input  logic [Bits-1:0] exponent_i,
    input  logic [Bits-1:0] base_i,
    output logic            busy_o,
    output logic            done_o,
    output logic            error_o,
    output logic            prepared_o,
    output logic            result_valid_o,
    output logic [Bits-1:0] result_o,
    output logic [      31:0] cycles_o,
    output logic [      31:0] progress_o
    // verilog_format: on
);
  localparam int ExponentIndexWidth = $clog2(Bits);
  localparam int WindowCount = Bits / 2;
  localparam int WindowIndexWidth = $clog2(WindowCount);
  localparam int PrepareWordCount = Bits / 32;
  localparam int PrepareWordIndexWidth = $clog2(PrepareWordCount);
  localparam logic [16:0] VerifyExponent = 17'h10001;

  typedef enum logic [5:0] {
    RsaIdle,
    RsaPrepareInverse,
    RsaPrepareR2Double,
    RsaPrepareR2Compare,
    RsaPrepareR2Subtract,
    RsaConvertBaseStart,
    RsaConvertBaseWait,
    RsaConvertOneStart,
    RsaConvertOneWait,
    RsaPublicSquareStart,
    RsaPublicSquareWait,
    RsaPublicMultiplyStart,
    RsaPublicMultiplyWait,
    RsaPrivateTable2Start,
    RsaPrivateTable2Wait,
    RsaPrivateTable3Start,
    RsaPrivateTable3Wait,
    RsaPrivateSquare1Start,
    RsaPrivateSquare1Wait,
    RsaPrivateSquare2Start,
    RsaPrivateSquare2Wait,
    RsaPrivateMultiplyStart,
    RsaPrivateMultiplyWait,
    RsaConvertOutStart,
    RsaConvertOutWait,
    RsaVerifyConvertStart,
    RsaVerifyConvertWait,
    RsaVerifySquareStart,
    RsaVerifySquareWait,
    RsaVerifyMultiplyStart,
    RsaVerifyMultiplyWait,
    RsaVerifyOutStart,
    RsaVerifyOutWait
  } rsa_state_e;

  rsa_state_e                             s_state_q;
  logic       [                 Bits-1:0] s_modulus_q;
  logic       [                 Bits-1:0] s_exponent_q;
  logic       [                 Bits-1:0] s_base_q;
  logic       [                 Bits-1:0] s_r2_q;
  logic       [                 Bits-1:0] s_base_mont_q;
  logic       [                 Bits-1:0] s_one_mont_q;
  logic       [                 Bits-1:0] s_result_mont_q;
  logic       [                 Bits-1:0] s_table2_q;
  logic       [                 Bits-1:0] s_table3_q;
  logic       [                 Bits-1:0] s_candidate_q;
  logic       [                 Bits-1:0] s_verify_base_mont_q;
  logic       [                 Bits-1:0] s_selected_table;
  logic       [                   Bits:0] s_prepare_double_q;
  logic       [                 Bits-1:0] s_prepare_modulus_q;
  logic       [                     31:0] s_prepare_double_word;
  logic       [                     31:0] s_prepare_modulus_word;
  logic       [                     32:0] s_prepare_difference;
  logic                                   s_prepare_greater_q;
  logic                                   s_prepare_less_q;
  logic                                   s_prepare_next_greater;
  logic                                   s_prepare_next_less;
  logic                                   s_prepare_borrow_q;
  logic       [PrepareWordIndexWidth-1:0] s_prepare_word_q;
  logic       [                     31:0] s_inverse_q;
  logic       [                     31:0] s_inverse_next;
  logic       [                     31:0] s_n0_prime_q;
  logic       [                      2:0] s_inverse_round_q;
  logic       [       $clog2(2*Bits)-1:0] s_prepare_round_q;
  logic       [   ExponentIndexWidth-1:0] s_exponent_index_q;
  logic       [     WindowIndexWidth-1:0] s_window_index_q;
  logic       [                      4:0] s_verify_index_q;
  logic       [                     11:0] s_exponent_bits_q;
  logic                                   s_private_q;

  logic                                   s_mont_start_q;
  logic                                   s_mont_busy;
  logic                                   s_mont_done;
  logic       [                 Bits-1:0] s_mont_left_q;
  logic       [                 Bits-1:0] s_mont_right_q;
  logic       [                 Bits-1:0] s_mont_result;

`ifndef SYNTHESIS
  initial begin
    if ((Bits < 64) || ((Bits % 32) != 0) || ((Bits % 2) != 0)) begin
      $fatal(1, "crypto_rsa_core: Bits must be an even multiple of 32 and at least 64");
    end
  end
`endif

  crypto_montgomery #(
      .Bits(Bits)
  ) u_crypto_montgomery (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .zeroize_i (zeroize_i || abort_i),
      .start_i   (s_mont_start_q),
      .left_i    (s_mont_left_q),
      .right_i   (s_mont_right_q),
      .modulus_i (s_modulus_q),
      .n0_prime_i(s_n0_prime_q),
      .busy_o    (s_mont_busy),
      .done_o    (s_mont_done),
      .result_o  (s_mont_result)
  );

  always_comb begin
    s_prepare_double_word = s_prepare_double_q[Bits-1-:32];
    s_prepare_modulus_word = s_prepare_modulus_q[Bits-1-:32];
    s_prepare_difference =
        {1'b0, s_prepare_double_q[31:0]} - {1'b0, s_prepare_modulus_q[31:0]} -
        {{32{1'b0}}, s_prepare_borrow_q};
    s_prepare_next_greater = s_prepare_greater_q;
    s_prepare_next_less = s_prepare_less_q;
    s_inverse_next = '0;
    s_selected_table = '0;
    if (s_state_q == RsaPrepareR2Compare) begin
      if (!s_prepare_greater_q && !s_prepare_less_q) begin
        if (s_prepare_double_word > s_prepare_modulus_word) begin
          s_prepare_next_greater = 1'b1;
        end else if (s_prepare_double_word < s_prepare_modulus_word) begin
          s_prepare_next_less = 1'b1;
        end
      end
    end else if (s_state_q == RsaPrepareInverse) begin
      s_inverse_next = s_inverse_q * (32'd2 - (s_modulus_q[31:0] * s_inverse_q));
    end else if (s_state_q == RsaPrivateMultiplyStart) begin
      unique case (s_exponent_q[s_window_index_q*2+:2])
        2'd0:    s_selected_table = s_one_mont_q;
        2'd1:    s_selected_table = s_base_mont_q;
        2'd2:    s_selected_table = s_table2_q;
        default: s_selected_table = s_table3_q;
      endcase
    end
  end

  assign busy_o     = (s_state_q != RsaIdle) || s_mont_busy;
  assign progress_o = {20'd0, s_exponent_index_q[10:0], s_private_q};

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q            <= RsaIdle;
      s_modulus_q          <= '0;
      s_exponent_q         <= '0;
      s_base_q             <= '0;
      s_r2_q               <= '0;
      s_base_mont_q        <= '0;
      s_one_mont_q         <= '0;
      s_result_mont_q      <= '0;
      s_table2_q           <= '0;
      s_table3_q           <= '0;
      s_candidate_q        <= '0;
      s_verify_base_mont_q <= '0;
      s_prepare_double_q   <= '0;
      s_prepare_modulus_q  <= '0;
      s_prepare_greater_q  <= 1'b0;
      s_prepare_less_q     <= 1'b0;
      s_prepare_borrow_q   <= 1'b0;
      s_prepare_word_q     <= '0;
      s_inverse_q          <= '0;
      s_n0_prime_q         <= '0;
      s_inverse_round_q    <= '0;
      s_prepare_round_q    <= '0;
      s_exponent_index_q   <= '0;
      s_window_index_q     <= '0;
      s_verify_index_q     <= '0;
      s_exponent_bits_q    <= '0;
      s_private_q          <= 1'b0;
      s_mont_start_q       <= 1'b0;
      s_mont_left_q        <= '0;
      s_mont_right_q       <= '0;
      done_o               <= 1'b0;
      error_o              <= 1'b0;
      prepared_o           <= 1'b0;
      result_valid_o       <= 1'b0;
      result_o             <= '0;
      cycles_o             <= '0;
    end else begin
      done_o         <= 1'b0;
      s_mont_start_q <= 1'b0;
      if (busy_o) begin
        cycles_o <= cycles_o + 1'b1;
      end
      if (zeroize_i || abort_i) begin
        s_state_q            <= RsaIdle;
        s_modulus_q          <= '0;
        s_exponent_q         <= '0;
        s_base_q             <= '0;
        s_r2_q               <= '0;
        s_base_mont_q        <= '0;
        s_one_mont_q         <= '0;
        s_result_mont_q      <= '0;
        s_table2_q           <= '0;
        s_table3_q           <= '0;
        s_candidate_q        <= '0;
        s_verify_base_mont_q <= '0;
        s_prepare_double_q   <= '0;
        s_prepare_modulus_q  <= '0;
        s_prepare_greater_q  <= 1'b0;
        s_prepare_less_q     <= 1'b0;
        s_prepare_borrow_q   <= 1'b0;
        s_prepare_word_q     <= '0;
        s_inverse_q          <= '0;
        s_n0_prime_q         <= '0;
        prepared_o           <= 1'b0;
        result_valid_o       <= 1'b0;
        result_o             <= '0;
        error_o              <= 1'b0;
      end else begin
        unique case (s_state_q)
          RsaIdle: begin
            if (prepare_i) begin
              result_valid_o <= 1'b0;
              error_o        <= 1'b0;
              cycles_o       <= '0;
              if (!modulus_i[0] || !modulus_i[Bits-1]) begin
                error_o <= 1'b1;
                done_o  <= 1'b1;
              end else begin
                s_modulus_q       <= modulus_i;
                s_inverse_q       <= 32'd1;
                s_inverse_round_q <= '0;
                prepared_o        <= 1'b0;
                s_state_q         <= RsaPrepareInverse;
              end
            end else if (start_i) begin
              result_valid_o <= 1'b0;
              error_o        <= 1'b0;
              cycles_o       <= '0;
              if (!prepared_o || (base_i >= s_modulus_q) ||
                  (!private_i &&
                   ((exponent_bits_i == 0) || (exponent_bits_i > 12'(Bits))))) begin
                error_o <= 1'b1;
                done_o  <= 1'b1;
              end else begin
                s_base_q          <= base_i;
                s_exponent_q      <= exponent_i;
                s_private_q       <= private_i;
                s_exponent_bits_q <= private_i ? 12'(Bits) : exponent_bits_i;
                s_state_q         <= RsaConvertBaseStart;
              end
            end
          end
          RsaPrepareInverse: begin
            s_inverse_q <= s_inverse_next;
            if (s_inverse_round_q == 3'd4) begin
              s_n0_prime_q      <= (~s_inverse_next) + 1'b1;
              s_r2_q            <= {{(Bits - 1) {1'b0}}, 1'b1};
              s_prepare_round_q <= '0;
              s_state_q         <= RsaPrepareR2Double;
            end else begin
              s_inverse_round_q <= s_inverse_round_q + 1'b1;
            end
          end
          RsaPrepareR2Double: begin
            s_prepare_double_q  <= {s_r2_q, 1'b0};
            s_prepare_modulus_q <= s_modulus_q;
            s_prepare_greater_q <= s_r2_q[Bits-1];
            s_prepare_less_q    <= 1'b0;
            s_prepare_borrow_q  <= 1'b0;
            if (s_r2_q[Bits-1]) begin
              s_prepare_word_q <= '0;
              s_state_q        <= RsaPrepareR2Subtract;
            end else begin
              s_prepare_word_q <= PrepareWordIndexWidth'(PrepareWordCount - 1);
              s_state_q        <= RsaPrepareR2Compare;
            end
          end
          RsaPrepareR2Compare: begin
            s_prepare_greater_q <= s_prepare_next_greater;
            s_prepare_less_q    <= s_prepare_next_less;
            if (s_prepare_word_q == '0) begin
              if (s_prepare_next_less) begin
                s_r2_q              <= {s_r2_q[Bits-2:0], 1'b0};
                s_prepare_double_q  <= '0;
                s_prepare_modulus_q <= '0;
                if (s_prepare_round_q == $clog2(2 * Bits)'(2 * Bits - 1)) begin
                  prepared_o <= 1'b1;
                  done_o     <= 1'b1;
                  s_state_q  <= RsaIdle;
                end else begin
                  s_prepare_round_q <= s_prepare_round_q + 1'b1;
                  s_state_q         <= RsaPrepareR2Double;
                end
              end else begin
                s_prepare_double_q  <= {s_r2_q, 1'b0};
                s_prepare_modulus_q <= s_modulus_q;
                s_prepare_borrow_q  <= 1'b0;
                s_prepare_word_q    <= '0;
                s_state_q           <= RsaPrepareR2Subtract;
              end
            end else begin
              s_prepare_double_q  <= {s_prepare_double_q[Bits-32:0], 32'b0};
              s_prepare_modulus_q <= {s_prepare_modulus_q[Bits-33:0], 32'b0};
              s_prepare_word_q    <= s_prepare_word_q - 1'b1;
            end
          end
          RsaPrepareR2Subtract: begin
            s_prepare_double_q  <= {32'b0, s_prepare_double_q[Bits:32]};
            s_prepare_modulus_q <= {32'b0, s_prepare_modulus_q[Bits-1:32]};
            s_prepare_borrow_q  <= s_prepare_difference[32];
            s_r2_q              <= {s_prepare_difference[31:0], s_r2_q[Bits-1:32]};
            if (s_prepare_word_q == PrepareWordIndexWidth'(PrepareWordCount - 1)) begin
              s_prepare_double_q  <= '0;
              s_prepare_modulus_q <= '0;
              if (s_prepare_round_q == $clog2(2 * Bits)'(2 * Bits - 1)) begin
                prepared_o <= 1'b1;
                done_o     <= 1'b1;
                s_state_q  <= RsaIdle;
              end else begin
                s_prepare_round_q <= s_prepare_round_q + 1'b1;
                s_state_q         <= RsaPrepareR2Double;
              end
            end else begin
              s_prepare_word_q <= s_prepare_word_q + 1'b1;
            end
          end
          RsaConvertBaseStart: begin
            s_mont_left_q  <= s_base_q;
            s_mont_right_q <= s_r2_q;
            s_mont_start_q <= 1'b1;
            s_state_q      <= RsaConvertBaseWait;
          end
          RsaConvertBaseWait: begin
            if (s_mont_done) begin
              s_base_mont_q <= s_mont_result;
              s_state_q     <= RsaConvertOneStart;
            end
          end
          RsaConvertOneStart: begin
            s_mont_left_q  <= {{(Bits - 1) {1'b0}}, 1'b1};
            s_mont_right_q <= s_r2_q;
            s_mont_start_q <= 1'b1;
            s_state_q      <= RsaConvertOneWait;
          end
          RsaConvertOneWait: begin
            if (s_mont_done) begin
              s_one_mont_q    <= s_mont_result;
              s_result_mont_q <= s_mont_result;
              if (s_private_q) begin
                s_state_q <= RsaPrivateTable2Start;
              end else begin
                s_exponent_index_q <= ExponentIndexWidth'(s_exponent_bits_q - 1'b1);
                s_state_q          <= RsaPublicSquareStart;
              end
            end
          end
          RsaPublicSquareStart: begin
            s_mont_left_q  <= s_result_mont_q;
            s_mont_right_q <= s_result_mont_q;
            s_mont_start_q <= 1'b1;
            s_state_q      <= RsaPublicSquareWait;
          end
          RsaPublicSquareWait: begin
            if (s_mont_done) begin
              s_result_mont_q <= s_mont_result;
              if (s_exponent_q[s_exponent_index_q]) begin
                s_state_q <= RsaPublicMultiplyStart;
              end else if (s_exponent_index_q == '0) begin
                s_state_q <= RsaConvertOutStart;
              end else begin
                s_exponent_index_q <= s_exponent_index_q - 1'b1;
                s_state_q          <= RsaPublicSquareStart;
              end
            end
          end
          RsaPublicMultiplyStart: begin
            s_mont_left_q  <= s_result_mont_q;
            s_mont_right_q <= s_base_mont_q;
            s_mont_start_q <= 1'b1;
            s_state_q      <= RsaPublicMultiplyWait;
          end
          RsaPublicMultiplyWait: begin
            if (s_mont_done) begin
              s_result_mont_q <= s_mont_result;
              if (s_exponent_index_q == '0) begin
                s_state_q <= RsaConvertOutStart;
              end else begin
                s_exponent_index_q <= s_exponent_index_q - 1'b1;
                s_state_q          <= RsaPublicSquareStart;
              end
            end
          end
          RsaPrivateTable2Start: begin
            s_mont_left_q  <= s_base_mont_q;
            s_mont_right_q <= s_base_mont_q;
            s_mont_start_q <= 1'b1;
            s_state_q      <= RsaPrivateTable2Wait;
          end
          RsaPrivateTable2Wait: begin
            if (s_mont_done) begin
              s_table2_q <= s_mont_result;
              s_state_q  <= RsaPrivateTable3Start;
            end
          end
          RsaPrivateTable3Start: begin
            s_mont_left_q  <= s_table2_q;
            s_mont_right_q <= s_base_mont_q;
            s_mont_start_q <= 1'b1;
            s_state_q      <= RsaPrivateTable3Wait;
          end
          RsaPrivateTable3Wait: begin
            if (s_mont_done) begin
              s_table3_q       <= s_mont_result;
              s_window_index_q <= WindowIndexWidth'(WindowCount - 1);
              s_state_q        <= RsaPrivateSquare1Start;
            end
          end
          RsaPrivateSquare1Start: begin
            s_mont_left_q  <= s_result_mont_q;
            s_mont_right_q <= s_result_mont_q;
            s_mont_start_q <= 1'b1;
            s_state_q      <= RsaPrivateSquare1Wait;
          end
          RsaPrivateSquare1Wait: begin
            if (s_mont_done) begin
              s_result_mont_q <= s_mont_result;
              s_state_q       <= RsaPrivateSquare2Start;
            end
          end
          RsaPrivateSquare2Start: begin
            s_mont_left_q  <= s_result_mont_q;
            s_mont_right_q <= s_result_mont_q;
            s_mont_start_q <= 1'b1;
            s_state_q      <= RsaPrivateSquare2Wait;
          end
          RsaPrivateSquare2Wait: begin
            if (s_mont_done) begin
              s_result_mont_q <= s_mont_result;
              s_state_q       <= RsaPrivateMultiplyStart;
            end
          end
          RsaPrivateMultiplyStart: begin
            s_mont_left_q  <= s_result_mont_q;
            s_mont_right_q <= s_selected_table;
            s_mont_start_q <= 1'b1;
            s_state_q      <= RsaPrivateMultiplyWait;
          end
          RsaPrivateMultiplyWait: begin
            if (s_mont_done) begin
              s_result_mont_q <= s_mont_result;
              if (s_window_index_q == '0) begin
                s_state_q <= RsaConvertOutStart;
              end else begin
                s_window_index_q <= s_window_index_q - 1'b1;
                s_state_q        <= RsaPrivateSquare1Start;
              end
            end
          end
          RsaConvertOutStart: begin
            s_mont_left_q  <= s_result_mont_q;
            s_mont_right_q <= {{(Bits - 1) {1'b0}}, 1'b1};
            s_mont_start_q <= 1'b1;
            s_state_q      <= RsaConvertOutWait;
          end
          RsaConvertOutWait: begin
            if (s_mont_done) begin
              if (s_private_q) begin
                s_candidate_q <= s_mont_result;
                s_state_q     <= RsaVerifyConvertStart;
              end else begin
                result_o       <= s_mont_result;
                result_valid_o <= 1'b1;
                done_o         <= 1'b1;
                s_state_q      <= RsaIdle;
              end
            end
          end
          RsaVerifyConvertStart: begin
            s_mont_left_q  <= s_candidate_q;
            s_mont_right_q <= s_r2_q;
            s_mont_start_q <= 1'b1;
            s_state_q      <= RsaVerifyConvertWait;
          end
          RsaVerifyConvertWait: begin
            if (s_mont_done) begin
              s_verify_base_mont_q <= s_mont_result;
              s_result_mont_q      <= s_one_mont_q;
              s_verify_index_q     <= 5'd16;
              s_state_q            <= RsaVerifySquareStart;
            end
          end
          RsaVerifySquareStart: begin
            s_mont_left_q  <= s_result_mont_q;
            s_mont_right_q <= s_result_mont_q;
            s_mont_start_q <= 1'b1;
            s_state_q      <= RsaVerifySquareWait;
          end
          RsaVerifySquareWait: begin
            if (s_mont_done) begin
              s_result_mont_q <= s_mont_result;
              if (VerifyExponent[s_verify_index_q]) begin
                s_state_q <= RsaVerifyMultiplyStart;
              end else if (s_verify_index_q == '0) begin
                s_state_q <= RsaVerifyOutStart;
              end else begin
                s_verify_index_q <= s_verify_index_q - 1'b1;
                s_state_q        <= RsaVerifySquareStart;
              end
            end
          end
          RsaVerifyMultiplyStart: begin
            s_mont_left_q  <= s_result_mont_q;
            s_mont_right_q <= s_verify_base_mont_q;
            s_mont_start_q <= 1'b1;
            s_state_q      <= RsaVerifyMultiplyWait;
          end
          RsaVerifyMultiplyWait: begin
            if (s_mont_done) begin
              s_result_mont_q <= s_mont_result;
              if (s_verify_index_q == '0) begin
                s_state_q <= RsaVerifyOutStart;
              end else begin
                s_verify_index_q <= s_verify_index_q - 1'b1;
                s_state_q        <= RsaVerifySquareStart;
              end
            end
          end
          RsaVerifyOutStart: begin
            s_mont_left_q  <= s_result_mont_q;
            s_mont_right_q <= {{(Bits - 1) {1'b0}}, 1'b1};
            s_mont_start_q <= 1'b1;
            s_state_q      <= RsaVerifyOutWait;
          end
          default: begin
            if (s_mont_done) begin
              if (s_mont_result == s_base_q) begin
                result_o       <= s_candidate_q;
                result_valid_o <= 1'b1;
              end else begin
                result_o       <= '0;
                result_valid_o <= 1'b0;
                error_o        <= 1'b1;
              end
              s_exponent_q         <= '0;
              s_table2_q           <= '0;
              s_table3_q           <= '0;
              s_result_mont_q      <= '0;
              s_verify_base_mont_q <= '0;
              done_o               <= 1'b1;
              s_state_q            <= RsaIdle;
            end
          end
        endcase
      end
    end
  end
endmodule
