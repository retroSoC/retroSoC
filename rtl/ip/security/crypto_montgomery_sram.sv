// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// CIOS Montgomery multiply, 64 little-endian limbs. All operand, accumulator,
// subtraction and result storage is in bank 5; only one MAC is live in flops.
module crypto_montgomery_sram (
    input  logic                                    clk_i,
    rst_n_i,
    clear_i,
    start_i,
    input  logic                             [31:0] n0_prime_i,
    output logic                                    busy_o,
    done_o,
    output crypto_mem_pkg::crypto_mem_req_t         req_o,
    input  crypto_mem_pkg::crypto_mem_resp_t        resp_i
);
  import crypto_mem_pkg::*;
  typedef enum logic [4:0] {
    MontIdle,
    MontClear,
    MontRightRead,
    MontRightWait,
    MontOperandRead,
    MontOperandWait,
    MontAccumulatorRead,
    MontAccumulatorWait,
    MontMacWrite,
    MontTailRead,
    MontTailWait,
    MontTailWrite,
    MontHighWrite,
    MontFactorRead,
    MontFactorWait,
    MontSubtractRead,
    MontSubtractWait,
    MontModulusRead,
    MontModulusWait,
    MontSubtractWrite,
    MontSelectRead,
    MontSelectWait,
    MontCandidateRead,
    MontCandidateWait,
    MontSelectWrite,
    MontDone
  } mont_state_e;
  typedef struct packed {
    mont_state_e state;
    logic [6:0]  index;
    logic [5:0]  outer_index;
    logic        reduction,   extra_high, borrow, use_subtracted;
    logic [31:0] operand,     right_word, factor, word,           accumulator;
    logic [32:0] carry;
  } mont_registers_t;
  mont_registers_t s_regs_d, s_regs_q;
  logic [64:0] s_sum;
  logic [32:0] s_tail, s_difference;
  dffr #(
      .DATA_WIDTH($bits(mont_registers_t))
  ) u_state (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_regs_d),
      .dat_o  (s_regs_q)
  );
  assign busy_o = s_regs_q.state != MontIdle;
  assign done_o = s_regs_q.state == MontDone;
  assign s_sum =
      (65'(s_regs_q.operand) * 65'(s_regs_q.reduction ? s_regs_q.factor : s_regs_q.right_word)) +
      65'(s_regs_q.accumulator) + 65'(s_regs_q.carry);
  assign s_tail = {1'b0, resp_i.data} + s_regs_q.carry;
  assign s_difference = {1'b0, s_regs_q.accumulator} - {1'b0, resp_i.data} - 33'(s_regs_q.borrow);
  always_comb begin
    s_regs_d = s_regs_q;
    req_o    = '0;
    unique case (s_regs_q.state)
      MontIdle:
      if (start_i) begin
        s_regs_d       = '0;
        s_regs_d.state = MontClear;
      end
      MontClear: begin
        req_o = mem_write(10'd192 + 10'(s_regs_q.index), 32'd0);
        if (s_regs_q.index == 7'd64) begin
          s_regs_d.index = '0;
          s_regs_d.state = MontRightRead;
        end else s_regs_d.index = s_regs_q.index + 1'b1;
      end
      MontRightRead: begin
        req_o          = mem_read(10'd64 + 10'(s_regs_q.outer_index));
        s_regs_d.state = MontRightWait;
      end
      MontRightWait:
      if (resp_i.valid) begin
        s_regs_d.right_word = resp_i.data;
        s_regs_d.index      = '0;
        s_regs_d.carry      = '0;
        s_regs_d.reduction  = 1'b0;
        s_regs_d.state      = MontOperandRead;
      end
      MontOperandRead: begin
        req_o          = mem_read((s_regs_q.reduction ? 10'd128 : 10'd0) + 10'(s_regs_q.index));
        s_regs_d.state = MontOperandWait;
      end
      MontOperandWait:
      if (resp_i.valid) begin
        s_regs_d.operand = resp_i.data;
        s_regs_d.state   = MontAccumulatorRead;
      end
      MontAccumulatorRead: begin
        req_o          = mem_read(10'd192 + 10'(s_regs_q.index));
        s_regs_d.state = MontAccumulatorWait;
      end
      MontAccumulatorWait:
      if (resp_i.valid) begin
        s_regs_d.accumulator = resp_i.data;
        s_regs_d.state       = MontMacWrite;
      end
      MontMacWrite: begin
        if (!s_regs_q.reduction || (s_regs_q.index != 0))
          req_o = mem_write(10'd192 + 10'(s_regs_q.index) - 10'(s_regs_q.reduction), s_sum[31:0]);
        s_regs_d.carry = s_sum[64:32];
        if (s_regs_q.index == 7'd63) s_regs_d.state = MontTailRead;
        else begin
          s_regs_d.index = s_regs_q.index + 1'b1;
          s_regs_d.state = MontOperandRead;
        end
      end
      MontTailRead: begin
        req_o          = mem_read(10'd256);
        s_regs_d.state = MontTailWait;
      end
      MontTailWait:
      if (resp_i.valid) begin
        s_regs_d.word  = s_tail[31:0];
        s_regs_d.carry = {32'd0, s_tail[32]};
        if (!s_regs_q.reduction) s_regs_d.extra_high = s_tail[32];
        s_regs_d.state = MontTailWrite;
      end
      MontTailWrite: begin
        req_o          = mem_write(s_regs_q.reduction ? 10'd255 : 10'd256, s_regs_q.word);
        s_regs_d.state = s_regs_q.reduction ? MontHighWrite : MontFactorRead;
      end
      MontHighWrite: begin
        req_o = mem_write(10'd256, 32'(s_regs_q.extra_high) + 32'(s_regs_q.carry[0]));
        s_regs_d.use_subtracted = s_regs_q.extra_high || s_regs_q.carry[0];
        s_regs_d.index = '0;
        s_regs_d.borrow = 1'b0;
        if (s_regs_q.outer_index == 6'd63) s_regs_d.state = MontSubtractRead;
        else begin
          s_regs_d.outer_index = s_regs_q.outer_index + 1'b1;
          s_regs_d.state       = MontRightRead;
        end
      end
      MontFactorRead: begin
        req_o          = mem_read(10'd192);
        s_regs_d.state = MontFactorWait;
      end
      MontFactorWait:
      if (resp_i.valid) begin
        s_regs_d.factor    = resp_i.data * n0_prime_i;
        s_regs_d.index     = '0;
        s_regs_d.carry     = '0;
        s_regs_d.reduction = 1'b1;
        s_regs_d.state     = MontOperandRead;
      end
      MontSubtractRead: begin
        req_o          = mem_read(10'd192 + 10'(s_regs_q.index));
        s_regs_d.state = MontSubtractWait;
      end
      MontSubtractWait:
      if (resp_i.valid) begin
        s_regs_d.accumulator = resp_i.data;
        s_regs_d.state       = MontModulusRead;
      end
      MontModulusRead: begin
        req_o          = mem_read(10'd128 + 10'(s_regs_q.index));
        s_regs_d.state = MontModulusWait;
      end
      MontModulusWait:
      if (resp_i.valid) begin
        s_regs_d.word   = s_difference[31:0];
        s_regs_d.borrow = s_difference[32];
        s_regs_d.state  = MontSubtractWrite;
      end
      MontSubtractWrite: begin
        req_o = mem_write(10'd257 + 10'(s_regs_q.index), s_regs_q.word);
        if (s_regs_q.index == 7'd63) begin
          s_regs_d.use_subtracted = s_regs_q.use_subtracted || !s_regs_q.borrow;
          s_regs_d.index          = '0;
          s_regs_d.state          = MontSelectRead;
        end else begin
          s_regs_d.index = s_regs_q.index + 1'b1;
          s_regs_d.state = MontSubtractRead;
        end
      end
      MontSelectRead: begin
        req_o          = mem_read(10'd192 + 10'(s_regs_q.index));
        s_regs_d.state = MontSelectWait;
      end
      MontSelectWait:
      if (resp_i.valid) begin
        s_regs_d.word  = resp_i.data;
        s_regs_d.state = MontCandidateRead;
      end
      MontCandidateRead: begin
        req_o          = mem_read(10'd257 + 10'(s_regs_q.index));
        s_regs_d.state = MontCandidateWait;
      end
      MontCandidateWait:
      if (resp_i.valid) begin
        if (s_regs_q.use_subtracted) s_regs_d.word = resp_i.data;
        s_regs_d.state = MontSelectWrite;
      end
      MontSelectWrite: begin
        req_o = mem_write(10'd321 + 10'(s_regs_q.index), s_regs_q.word);
        if (s_regs_q.index == 7'd63) s_regs_d.state = MontDone;
        else begin
          s_regs_d.index = s_regs_q.index + 1'b1;
          s_regs_d.state = MontSelectRead;
        end
      end
      MontDone: begin
        // The public product remains in SRAM. Revoke all scalar intermediates.
        s_regs_d = '0;
      end
      default: s_regs_d = '0;
    endcase
    if (clear_i) begin
      s_regs_d = '0;
      req_o    = '0;
    end
  end
endmodule
