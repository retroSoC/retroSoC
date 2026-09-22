// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// Scalar pipelined numerical-profile-1 requantizer, bit-exact with
// scripts/npu_reference.py. Each item applies, in this exact order: checked
// left shift by max(shift,0) (an out-of-INT32 result flags the item, data
// 8'sd0, never wrapped), SaturatingRoundingDoublingHighMul with the
// multiplier (2^30 nudge for p >= 0, 1-2^30 for p < 0, division by 2^31
// truncating toward zero, INT32_MIN-times-INT32_MIN saturation), then
// RoundingDivideByPOT by max(-shift,0), then a widened add of the output zero
// point and a clamp to [act_min, act_max]. This is the pinned double-rounding
// profile; no single-rounding substitution is made. Five elastic valid/ready
// register stages (shift, 32x32 multiply, nudge+truncating divide,
// RoundingDivideByPOT, zero-point add+clamp) carry the per-item
// configuration and fault flag; req_ready_o is high only when stage 0 is
// free or shifting out.
module npu_requantizer (
    input  logic               clk_i,
    input  logic               rst_n_i,
    input  logic               req_valid_i,
    output logic               req_ready_o,
    input  logic signed [31:0] req_acc_i,
    input  logic        [31:0] req_multiplier_i,
    input  logic signed [ 7:0] req_shift_i,
    input  logic signed [ 7:0] req_zout_i,
    input  logic signed [ 7:0] req_act_min_i,
    input  logic signed [ 7:0] req_act_max_i,
    output logic               resp_valid_o,
    input  logic               resp_ready_i,
    output logic signed [ 7:0] resp_data_o,
    output logic               resp_fault_o
);
  // Stage 0 (checked left shift) registers and combinational results.
  logic               s_shift_valid_q;
  logic signed [31:0] s_shift_data_q;
  logic               s_shift_fault_q;
  logic        [31:0] s_shift_multiplier_q;
  logic signed [ 7:0] s_shift_shift_q;
  logic signed [ 7:0] s_shift_zout_q;
  logic signed [ 7:0] s_shift_act_min_q;
  logic signed [ 7:0] s_shift_act_max_q;
  logic signed [31:0] s_shift_data_d;
  logic               s_shift_fault_d;
  logic signed [63:0] s_shifted_wide;
  // Stage 1 (32x32 to 64-bit signed multiply) registers and result.
  logic               s_mul_valid_q;
  logic signed [63:0] s_mul_product_q;
  logic               s_mul_fault_q;
  logic signed [ 7:0] s_mul_shift_q;
  logic signed [ 7:0] s_mul_zout_q;
  logic signed [ 7:0] s_mul_act_min_q;
  logic signed [ 7:0] s_mul_act_max_q;
  logic signed [63:0] s_mul_product_d;
  // Stage 2 (nudge and truncating division by 2^31) registers and result.
  logic               s_nud_valid_q;
  logic signed [31:0] s_nud_data_q;
  logic               s_nud_fault_q;
  logic signed [ 7:0] s_nud_shift_q;
  logic signed [ 7:0] s_nud_zout_q;
  logic signed [ 7:0] s_nud_act_min_q;
  logic signed [ 7:0] s_nud_act_max_q;
  logic signed [31:0] s_nud_data_d;
  // Stage 3 (RoundingDivideByPOT) registers and result.
  logic               s_rdp_valid_q;
  logic signed [31:0] s_rdp_data_q;
  logic               s_rdp_fault_q;
  logic signed [ 7:0] s_rdp_zout_q;
  logic signed [ 7:0] s_rdp_act_min_q;
  logic signed [ 7:0] s_rdp_act_max_q;
  logic signed [31:0] s_rdp_data_d;
  logic signed [ 7:0] s_rdp_exponent;
  // Stage 4 (widened zero-point add and clamp) registers and result.
  logic               s_out_valid_q;
  logic signed [ 7:0] s_out_data_q;
  logic               s_out_fault_q;
  logic signed [ 7:0] s_out_data_d;
  logic signed [32:0] s_zout_sum;
  logic signed [32:0] s_act_min_ext;
  logic signed [32:0] s_act_max_ext;
  logic               s_shift_ready;
  logic               s_mul_ready;
  logic               s_nud_ready;
  logic               s_rdp_ready;

  // Pinned Q31 nudge and trunc-toward-zero division by 2^31. The
  // INT32_MIN-times-INT32_MIN saturation is the only way to reach
  // product_i == 2^62, so the product value identifies the special case.
  function automatic logic signed [31:0] nudge_truncate(input logic signed [63:0] product_i);
    logic signed [63:0] s_nudged;
    logic signed [63:0] s_quotient;
    begin
      if (product_i == 64'sh4000_0000_0000_0000) begin
        return 32'sh7fff_ffff;
      end
      s_nudged = product_i + ((product_i >= 64'sd0) ? 64'sd1073741824 : -64'sd1073741823);
      if (s_nudged < 64'sd0) begin
        s_quotient = -((-s_nudged) >>> 31);
      end else begin
        s_quotient = s_nudged >>> 31;
      end
      return 32'(s_quotient);
    end
  endfunction

  // Pinned correctly rounded division by 2^exponent_i (exponent 0 returns value_i).
  function automatic logic signed [31:0] rounding_divide_by_pot(input logic signed [31:0] value_i,
                                                                input logic [4:0] exponent_i);
    logic        [31:0] s_mask;
    logic        [31:0] s_remainder;
    logic        [31:0] s_threshold;
    logic signed [31:0] s_quotient;
    begin
      if (exponent_i == 5'd0) begin
        return value_i;
      end
      s_mask      = (32'd1 << exponent_i) - 32'd1;
      s_remainder = value_i & s_mask;
      s_threshold = (s_mask >> 1) + ((value_i < 32'sd0) ? 32'd1 : 32'd0);
      s_quotient  = value_i >>> exponent_i;
      return s_quotient + ((s_remainder > s_threshold) ? 32'sd1 : 32'sd0);
    end
  endfunction

  // Stage 0: checked left shift; the 64-bit intermediate detects any result
  // outside signed INT32 without wrapping. Valid shifts are -31..30.
  always_comb begin
    s_shift_data_d  = req_acc_i;
    s_shift_fault_d = 1'b0;
    s_shifted_wide  = 64'(req_acc_i);
    if (req_shift_i > 8'sd0) begin
      s_shifted_wide  = 64'(req_acc_i) <<< req_shift_i[5:0];
      s_shift_data_d  = s_shifted_wide[31:0];
      s_shift_fault_d = s_shifted_wide != 64'($signed(s_shifted_wide[31:0]));
    end
  end

  // Stage 1: the multiplier is consumed as a nonnegative signed INT32 value;
  // multiplier 0 is the flushed case. The full 64-bit product is registered.
  always_comb begin
    s_mul_product_d = s_shift_data_q * $signed(s_shift_multiplier_q);
  end

  // Stage 2: nudge and truncating division by 2^31 (SRDHM back half).
  always_comb begin
    s_nud_data_d = nudge_truncate(s_mul_product_q);
  end

  // Stage 3: RoundingDivideByPOT applies only for negative shifts, r = -shift.
  always_comb begin
    s_rdp_exponent = -s_nud_shift_q;
    s_rdp_data_d   = s_nud_data_q;
    if (s_nud_shift_q < 8'sd0) begin
      s_rdp_data_d = rounding_divide_by_pot(s_nud_data_q, s_rdp_exponent[4:0]);
    end
  end

  // Stage 4: widened 33-bit zero-point add, then clamp to the signed bounds;
  // a flagged item publishes 8'sd0 with resp_fault_o set.
  always_comb begin
    s_zout_sum    = {s_rdp_data_q[31], s_rdp_data_q} + {{25{s_rdp_zout_q[7]}}, s_rdp_zout_q};
    s_act_min_ext = {{25{s_rdp_act_min_q[7]}}, s_rdp_act_min_q};
    s_act_max_ext = {{25{s_rdp_act_max_q[7]}}, s_rdp_act_max_q};
    s_out_data_d  = s_zout_sum[7:0];
    if (s_zout_sum > s_act_max_ext) begin
      s_out_data_d = s_rdp_act_max_q;
    end else if (s_zout_sum < s_act_min_ext) begin
      s_out_data_d = s_rdp_act_min_q;
    end
    if (s_rdp_fault_q) begin
      s_out_data_d = 8'sd0;
    end
  end

  assign s_shift_ready = !s_mul_valid_q || s_mul_ready;
  assign s_mul_ready   = !s_nud_valid_q || s_nud_ready;
  assign s_nud_ready   = !s_rdp_valid_q || s_rdp_ready;
  assign s_rdp_ready   = !s_out_valid_q || resp_ready_i;
  assign req_ready_o   = !s_shift_valid_q || s_shift_ready;

  assign resp_valid_o  = s_out_valid_q;
  assign resp_data_o   = s_out_data_q;
  assign resp_fault_o  = s_out_fault_q;

  // Datapath registers load only when their stage transfers, so they need no
  // reset; only the per-stage valid bits are reset.
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_shift_valid_q <= 1'b0;
      s_mul_valid_q   <= 1'b0;
      s_nud_valid_q   <= 1'b0;
      s_rdp_valid_q   <= 1'b0;
      s_out_valid_q   <= 1'b0;
    end else begin
      if (req_valid_i && req_ready_o) begin
        s_shift_valid_q <= 1'b1;
      end else if (s_shift_ready) begin
        s_shift_valid_q <= 1'b0;
      end
      if (s_shift_valid_q && s_shift_ready) begin
        s_mul_valid_q <= 1'b1;
      end else if (s_mul_ready) begin
        s_mul_valid_q <= 1'b0;
      end
      if (s_mul_valid_q && s_mul_ready) begin
        s_nud_valid_q <= 1'b1;
      end else if (s_nud_ready) begin
        s_nud_valid_q <= 1'b0;
      end
      if (s_nud_valid_q && s_nud_ready) begin
        s_rdp_valid_q <= 1'b1;
      end else if (s_rdp_ready) begin
        s_rdp_valid_q <= 1'b0;
      end
      if (s_rdp_valid_q && s_rdp_ready) begin
        s_out_valid_q <= 1'b1;
      end else if (resp_ready_i) begin
        s_out_valid_q <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (req_valid_i && req_ready_o) begin
      s_shift_data_q       <= s_shift_data_d;
      s_shift_fault_q      <= s_shift_fault_d;
      s_shift_multiplier_q <= req_multiplier_i;
      s_shift_shift_q      <= req_shift_i;
      s_shift_zout_q       <= req_zout_i;
      s_shift_act_min_q    <= req_act_min_i;
      s_shift_act_max_q    <= req_act_max_i;
    end
    if (s_shift_valid_q && s_shift_ready) begin
      s_mul_product_q <= s_mul_product_d;
      s_mul_fault_q   <= s_shift_fault_q;
      s_mul_shift_q   <= s_shift_shift_q;
      s_mul_zout_q    <= s_shift_zout_q;
      s_mul_act_min_q <= s_shift_act_min_q;
      s_mul_act_max_q <= s_shift_act_max_q;
    end
    if (s_mul_valid_q && s_mul_ready) begin
      s_nud_data_q    <= s_nud_data_d;
      s_nud_fault_q   <= s_mul_fault_q;
      s_nud_shift_q   <= s_mul_shift_q;
      s_nud_zout_q    <= s_mul_zout_q;
      s_nud_act_min_q <= s_mul_act_min_q;
      s_nud_act_max_q <= s_mul_act_max_q;
    end
    if (s_nud_valid_q && s_nud_ready) begin
      s_rdp_data_q    <= s_rdp_data_d;
      s_rdp_fault_q   <= s_nud_fault_q;
      s_rdp_zout_q    <= s_nud_zout_q;
      s_rdp_act_min_q <= s_nud_act_min_q;
      s_rdp_act_max_q <= s_nud_act_max_q;
    end
    if (s_rdp_valid_q && s_rdp_ready) begin
      s_out_data_q  <= s_out_data_d;
      s_out_fault_q <= s_rdp_fault_q;
    end
  end

`ifndef SV_ASSRT_DISABLE
  logic s_req_stall_q;
  logic s_resp_stall_q;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_req_stall_q  <= 1'b0;
      s_resp_stall_q <= 1'b0;
    end else begin
      s_req_stall_q  <= req_valid_i && !req_ready_o;
      s_resp_stall_q <= resp_valid_o && !resp_ready_i;
      if (s_req_stall_q) begin
        assert ($stable(req_acc_i));
        assert ($stable(req_multiplier_i));
        assert ($stable(req_shift_i));
        assert ($stable(req_zout_i));
        assert ($stable(req_act_min_i));
        assert ($stable(req_act_max_i));
      end
      if (s_resp_stall_q) begin
        assert ($stable(resp_data_o));
        assert ($stable(resp_fault_o));
      end
    end
  end
`endif
endmodule
