// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module crypto_montgomery #(
    parameter int Bits      = 2048,
    parameter int LimbWidth = 32
) (
    // verilog_format: off -- wide arithmetic operands are intentionally aligned.
    input  logic            clk_i,
    input  logic            rst_n_i,
    input  logic            zeroize_i,
    input  logic            start_i,
    input  logic [Bits-1:0] left_i,
    input  logic [Bits-1:0] right_i,
    input  logic [Bits-1:0] modulus_i,
    input  logic [     31:0] n0_prime_i,
    output logic            busy_o,
    output logic            done_o,
    output logic [Bits-1:0] result_o
    // verilog_format: on
);
  localparam int NumLimbs = Bits / LimbWidth;
  localparam int IndexWidth = (NumLimbs > 1) ? $clog2(NumLimbs) : 1;
  localparam int AccumulatorIndexWidth = $clog2(NumLimbs + 1);

  typedef enum logic [3:0] {
    MontIdle,
    MontOuterStart,
    MontMultiplyLeft,
    MontLeftTail,
    MontMultiplyModulus,
    MontTail,
    MontCompare,
    MontSubtract,
    MontSelect
  } mont_state_e;

  mont_state_e                  s_state_q;
  logic        [ LimbWidth-1:0] s_accumulator_q    [  0:NumLimbs];
  logic        [ LimbWidth-1:0] s_subtracted_q     [0:NumLimbs-1];
  logic        [IndexWidth-1:0] s_outer_q;
  logic        [IndexWidth-1:0] s_inner_q;
  logic        [IndexWidth-1:0] s_compare_q;
  logic        [          32:0] s_carry_q;
  logic                         s_borrow_q;
  logic                         s_greater_q;
  logic                         s_less_q;
  logic                         s_use_subtracted_q;
  logic                         s_extra_high_q;
  logic        [          31:0] s_factor_q;
  logic        [          31:0] s_left_limb;
  logic        [          31:0] s_right_limb;
  logic        [          31:0] s_modulus_limb;
  logic        [          64:0] s_sum;
  logic        [          32:0] s_difference;
  logic        [          32:0] s_tail_sum;
  logic                         s_next_borrow;
  logic                         s_next_greater;
  logic                         s_next_less;

`ifndef SYNTHESIS
  initial begin
    if ((Bits < 64) || (LimbWidth != 32) || ((Bits % LimbWidth) != 0)) begin
      $fatal(1, "crypto_montgomery: Bits must be a multiple of 32 and at least 64");
    end
  end
`endif

  always_comb begin
    s_left_limb    = '0;
    s_right_limb   = '0;
    s_modulus_limb = '0;
    s_sum          = '0;
    s_difference   = '0;
    s_tail_sum     = '0;
    s_next_borrow  = s_borrow_q;
    s_next_greater = s_greater_q;
    s_next_less    = s_less_q;
    unique case (s_state_q)
      MontMultiplyLeft: begin
        s_left_limb = left_i[s_inner_q*LimbWidth+:LimbWidth];
        s_right_limb = right_i[s_outer_q*LimbWidth+:LimbWidth];
        s_sum = ({33'd0, s_left_limb} * {33'd0, s_right_limb}) +
                {33'd0, s_accumulator_q[AccumulatorIndexWidth'(s_inner_q)]} +
                {{32{1'b0}}, s_carry_q};
      end
      MontMultiplyModulus: begin
        s_modulus_limb = modulus_i[s_inner_q*LimbWidth+:LimbWidth];
        s_sum = ({33'd0, s_factor_q} * {33'd0, s_modulus_limb}) +
                {33'd0, s_accumulator_q[AccumulatorIndexWidth'(s_inner_q)]} +
                {{32{1'b0}}, s_carry_q};
      end
      MontLeftTail, MontTail: begin
        s_tail_sum = {1'b0, s_accumulator_q[NumLimbs]} + s_carry_q;
      end
      MontCompare: begin
        s_modulus_limb = modulus_i[s_compare_q*LimbWidth+:LimbWidth];
        if (!s_greater_q && !s_less_q) begin
          if (s_accumulator_q[AccumulatorIndexWidth'(s_compare_q)] > s_modulus_limb) begin
            s_next_greater = 1'b1;
          end else if (s_accumulator_q[AccumulatorIndexWidth'(s_compare_q)] < s_modulus_limb) begin
            s_next_less = 1'b1;
          end
        end
      end
      MontSubtract: begin
        s_modulus_limb = modulus_i[s_inner_q*LimbWidth+:LimbWidth];
        s_difference = {1'b0, s_accumulator_q[AccumulatorIndexWidth'(s_inner_q)]} -
                       {1'b0, s_modulus_limb} - s_borrow_q;
        s_next_borrow = s_difference[32];
      end
      default: begin
      end
    endcase
  end

  assign busy_o = s_state_q != MontIdle;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q          <= MontIdle;
      s_outer_q          <= '0;
      s_inner_q          <= '0;
      s_compare_q        <= '0;
      s_carry_q          <= '0;
      s_borrow_q         <= 1'b0;
      s_greater_q        <= 1'b0;
      s_less_q           <= 1'b0;
      s_use_subtracted_q <= 1'b0;
      s_extra_high_q     <= 1'b0;
      s_factor_q         <= '0;
      done_o             <= 1'b0;
      result_o           <= '0;
    end else begin
      done_o <= 1'b0;
      if (zeroize_i) begin
        s_state_q          <= MontIdle;
        s_outer_q          <= '0;
        s_inner_q          <= '0;
        s_compare_q        <= '0;
        s_carry_q          <= '0;
        s_borrow_q         <= 1'b0;
        s_greater_q        <= 1'b0;
        s_less_q           <= 1'b0;
        s_use_subtracted_q <= 1'b0;
        s_extra_high_q     <= 1'b0;
        s_factor_q         <= '0;
        result_o           <= '0;
        for (int unsigned index = 0; index <= NumLimbs; index++) begin
          s_accumulator_q[index] <= '0;
        end
        for (int unsigned index = 0; index < NumLimbs; index++) begin
          s_subtracted_q[index] <= '0;
        end
      end else begin
        unique case (s_state_q)
          MontIdle: begin
            if (start_i) begin
              for (int unsigned index = 0; index <= NumLimbs; index++) begin
                s_accumulator_q[index] <= '0;
              end
              s_outer_q <= '0;
              s_state_q <= MontOuterStart;
            end
          end
          MontOuterStart: begin
            s_inner_q <= '0;
            s_carry_q <= '0;
            s_state_q <= MontMultiplyLeft;
          end
          MontMultiplyLeft: begin
            s_accumulator_q[AccumulatorIndexWidth'(s_inner_q)] <= s_sum[31:0];
            if (s_inner_q == IndexWidth'(NumLimbs - 1)) begin
              s_carry_q <= s_sum[64:32];
              s_state_q <= MontLeftTail;
            end else begin
              s_inner_q <= s_inner_q + 1'b1;
              s_carry_q <= s_sum[64:32];
            end
          end
          MontLeftTail: begin
            s_accumulator_q[NumLimbs] <= s_tail_sum[31:0];
            s_extra_high_q            <= s_tail_sum[32];
            s_factor_q                <= s_accumulator_q[0] * n0_prime_i;
            s_inner_q                 <= '0;
            s_carry_q                 <= '0;
            s_state_q                 <= MontMultiplyModulus;
          end
          MontMultiplyModulus: begin
            s_carry_q <= s_sum[64:32];
            if (s_inner_q != '0) begin
              s_accumulator_q[AccumulatorIndexWidth'(s_inner_q-1'b1)] <= s_sum[31:0];
            end
            if (s_inner_q == IndexWidth'(NumLimbs - 1)) begin
              s_state_q <= MontTail;
            end else begin
              s_inner_q <= s_inner_q + 1'b1;
            end
          end
          MontTail: begin
            s_accumulator_q[NumLimbs-1] <= s_tail_sum[31:0];
            s_accumulator_q[NumLimbs] <= {{31{1'b0}}, s_extra_high_q} +
                                             {{31{1'b0}}, s_tail_sum[32]};
            if (s_outer_q == IndexWidth'(NumLimbs - 1)) begin
              s_compare_q <= IndexWidth'(NumLimbs - 1);
              s_greater_q <= s_extra_high_q || s_tail_sum[32];
              s_less_q    <= 1'b0;
              s_state_q   <= MontCompare;
            end else begin
              s_outer_q <= s_outer_q + 1'b1;
              s_state_q <= MontOuterStart;
            end
          end
          MontCompare: begin
            s_greater_q <= s_next_greater;
            s_less_q    <= s_next_less;
            if (s_compare_q == '0) begin
              s_use_subtracted_q <= !s_next_less;
              s_inner_q          <= '0;
              s_borrow_q         <= 1'b0;
              s_state_q          <= MontSubtract;
            end else begin
              s_compare_q <= s_compare_q - 1'b1;
            end
          end
          MontSubtract: begin
            s_subtracted_q[s_inner_q] <= s_difference[31:0];
            s_borrow_q                <= s_next_borrow;
            if (s_inner_q == IndexWidth'(NumLimbs - 1)) begin
              s_state_q <= MontSelect;
            end else begin
              s_inner_q <= s_inner_q + 1'b1;
            end
          end
          default: begin
            for (int unsigned index = 0; index < NumLimbs; index++) begin
              if (s_use_subtracted_q) begin
                s_accumulator_q[index]               <= s_subtracted_q[index];
                result_o[index*LimbWidth+:LimbWidth] <= s_subtracted_q[index];
              end else begin
                result_o[index*LimbWidth+:LimbWidth] <= s_accumulator_q[index];
              end
            end
            s_accumulator_q[NumLimbs] <= '0;
            done_o                    <= 1'b1;
            s_state_q                 <= MontIdle;
          end
        endcase
      end
    end
  end
endmodule
