// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// NPU-P3 job decoder: bounded linear fetch and full ABI-1.0 validation of the
// 128-byte descriptor records of one job (docs/ip/npu.md "Descriptor ABI 1.0"
// and "Job submission and ordering"). Each record is fetched through the
// npu_dma read channel into 32 private staging words, validated in the exact
// check order of the golden host validator scripts/npu_descriptors.py
// (structural record, opcode support, unused fields, geometry, operator,
// strides/spans, alignment, overlap) with widened no-wrap arithmetic, and is
// then emitted to the scheduler as a typed execute record. Records are
// fetched, validated, executed and retired strictly in order; a validation
// failure or a fetch bus fault is terminal for the job and earlier records
// are not rolled back.
//
// Fault metadata conventions: a validation fault reports the record fetch
// address plus 4*word (the ABI word index) on fault_addr_o; overlap faults
// and the descriptor-region wrap carry no single word and report the record
// base. A fetch fault forwards the DMA code (AXI_READ or AXI_PROTOCOL), the
// failing beat address and the AXI response, with FAULT_INFO direction=read
// and the not-applicable lane 255. A descriptor address or region that wraps
// the 32-bit space is refused locally as RANGE before any bus request.
`include "npu_define.svh"

module npu_job_decoder (
    input  logic        clk_hp_i,
    input  logic        rst_hp_n_i,
    // coordinated cancel from npu_core (abort/quiesce/reset/flush): stop at
    // the current segment boundary, drain the in-flight fetch, then idle
    input  logic        clear_i,
    input  logic        block_new_i,
    output logic        pause_ok_o,
    // job launch from npu_core
    input  logic        job_start_i,
    input  logic [31:0] job_base_i,
    input  logic [15:0] job_count_i,
    // npu_dma read command channel (owned while fetching)
    output logic        read_req_valid_o,
    input  logic        read_req_ready_i,
    output logic [31:0] read_addr_o,
    output logic [31:0] read_bytes_o,
    // npu_dma read stream
    input  logic        read_data_valid_i,
    output logic        read_data_ready_o,
    input  logic [63:0] read_data_i,
    input  logic        read_last_i,
    // npu_dma status
    input  logic        dma_read_busy_i,
    input  logic        dma_fault_i,
    input  logic [ 3:0] dma_fault_code_i,
    input  logic [31:0] dma_fault_addr_i,
    input  logic [ 1:0] dma_fault_resp_i,
    // validated execute record to the scheduler
    output logic        rec_valid_o,
    input  logic        rec_ready_i,
    output logic [ 3:0] rec_opcode_o,
    output logic [12:0] rec_h_o,
    output logic [12:0] rec_w_o,
    output logic [12:0] rec_cin_o,
    output logic [12:0] rec_cout_o,
    output logic [12:0] rec_oh_o,
    output logic [12:0] rec_ow_o,
    output logic [31:0] rec_input0_base_o,
    output logic [31:0] rec_output_base_o,
    output logic [31:0] rec_weight_base_o,
    output logic [31:0] rec_param_base_o,
    output logic [31:0] rec_input0_row_bytes_o,
    output logic [31:0] rec_output_row_bytes_o,
    output logic [ 7:0] rec_kh_o,
    output logic [ 7:0] rec_kw_o,
    output logic [ 7:0] rec_sh_o,
    output logic [ 7:0] rec_sw_o,
    output logic [ 7:0] rec_pad_top_o,
    output logic [ 7:0] rec_pad_left_o,
    output logic [ 7:0] rec_input0_zero_o,
    // P4 compute fields of the same validated record
    output logic [ 7:0] rec_tile_h_o,
    output logic [ 7:0] rec_tile_w_o,
    output logic [15:0] rec_k_slice_o,
    output logic [31:0] rec_input1_base_o,
    output logic [31:0] rec_input1_row_bytes_o,
    output logic [ 7:0] rec_input1_zero_o,
    output logic [ 7:0] rec_output_zero_o,
    output logic [ 7:0] rec_act_min_o,
    output logic [ 7:0] rec_act_max_o,
    output logic [31:0] rec_weight_bytes_o,
    output logic [31:0] rec_param_bytes_o,
    output logic [15:0] rec_desc_index_o,
    // scheduler retirement handshake
    input  logic        retired_i,
    output logic        all_done_o,
    output logic        busy_o,
    output logic [15:0] cur_desc_index_o,
    // one-cycle progress pulse for the job no-progress watchdog
    output logic        progress_o,
    // terminal fault report (held until clear_i)
    output logic        fault_req_o,
    output logic [ 3:0] fault_code_o,
    output logic [31:0] fault_addr_o,
    output logic [31:0] fault_info_o,
    output logic [31:0] fault_desc_o
);
  localparam logic [31:0] FaultInfoInternal = {16'd0, 8'd255, 4'd0, 2'd0, 2'd0};

  typedef enum logic [4:0] {
    DecIdle,
    DecFetchCmd,
    DecFetchData,
    DecDrain,
    DecCompute,
    DecCompute2,
    DecCompute3,
    DecStruct1,
    DecStruct2,
    DecStruct3,
    DecStruct4,
    DecOpcode,
    DecUnused,
    DecGeom1,
    DecGeom2,
    DecOper,
    DecOperCommon,
    DecStride,
    DecAlign,
    DecOverlap,
    DecEmit,
    DecWaitRetire,
    DecFault
  } state_e;

  state_e s_state_d, s_state_q;
  logic [31:0] s_words_q[32];
  logic [31:0] s_base_d, s_base_q;
  logic [15:0] s_count_d, s_count_q;
  logic [15:0] s_index_d, s_index_q;
  logic [ 4:0] s_beat_q;
  logic [ 3:0] s_fault_code_q;
  logic [31:0] s_fault_addr_q;
  logic [31:0] s_fault_info_q;
  logic [15:0] s_fault_index_q;
  logic [31:0] s_desc_addr;
  logic        s_fetch_wrap;
  logic        s_cmd_accept;
  logic        s_stream_accept;
  logic        s_last_accept;

  // decoded record views of the staged words
  logic [ 7:0] s_opcode;
  logic [15:0] s_dim_h, s_dim_w, s_dim_cin, s_dim_cout, s_dim_oh, s_dim_ow;
  logic [7:0] s_kh, s_kw, s_sh, s_sw;
  logic [7:0] s_pad_t, s_pad_b, s_pad_l, s_pad_r;
  logic [7:0] s_tile_h, s_tile_w;
  logic               s_is_kernel_op;
  logic               s_is_weighted_op;
  logic               s_is_param_op;
  logic               s_is_add;
  logic               s_is_gap;
  logic signed [31:0] s_extent_h;
  logic signed [31:0] s_extent_w;
  logic        [15:0] s_khkw;
  logic        [63:0] s_full_k;
  logic        [63:0] s_weight_expect;
  logic        [63:0] s_span_in0;
  logic        [63:0] s_span_in1;
  logic        [63:0] s_span_out;
  logic        [63:0] s_min_row_in;
  logic        [63:0] s_min_row_out;
  logic        [63:0] s_region_end;

  // registered derived quantities (staged across DecCompute..DecCompute3 with
  // at most one multiply level per stage, consumed by the check sequencer:
  // keeps the wide multiplies/compares off the FSM path)
  logic signed [31:0] s_extent_h_q;
  logic signed [31:0] s_extent_w_q;
  logic        [15:0] s_khkw_q;
  logic        [63:0] s_full_k_q;
  logic        [63:0] s_weight_expect_q;
  logic        [63:0] s_span_in0_q;
  logic        [63:0] s_span_in1_q;
  logic        [63:0] s_span_out_q;
  logic        [63:0] s_min_row_in_q;
  logic        [63:0] s_min_row_out_q;
  logic        [63:0] s_region_end_q;
  logic        [63:0] s_rng_base_q      [6];
  logic        [63:0] s_rng_end_q       [6];
  logic               s_overlap_pair_q;

  // per-check-state combinational verdict
  logic               s_chk_fail;
  logic        [ 3:0] s_chk_code;
  logic        [ 5:0] s_chk_word;
  logic               s_chk_wordless;

  // overlap ranges
  logic        [63:0] s_rng_base        [6];
  logic        [63:0] s_rng_end         [6];
  logic        [ 5:0] s_rng_valid;
  logic               s_overlap_pair;

  assign s_desc_addr = s_base_q + {9'd0, s_index_q, 7'd0};
  assign s_fetch_wrap = ({1'b0, s_desc_addr} + 33'd128) > 33'h1_0000_0000;
  assign s_cmd_accept = read_req_valid_o && read_req_ready_i;
  assign s_stream_accept = read_data_valid_i && read_data_ready_o;
  assign s_last_accept = s_stream_accept && read_last_i;

  assign s_opcode = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_VERSION_OPCODE][7:0];
  assign s_dim_h = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT_HW][15:0];
  assign s_dim_w = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT_HW][31:16];
  assign s_dim_cin = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_CHANNELS][15:0];
  assign s_dim_cout = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_CHANNELS][31:16];
  assign s_dim_oh = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_OUTPUT_HW][15:0];
  assign s_dim_ow = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_OUTPUT_HW][31:16];
  assign s_kh = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_KERNEL_STRIDE][7:0];
  assign s_kw = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_KERNEL_STRIDE][15:8];
  assign s_sh = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_KERNEL_STRIDE][23:16];
  assign s_sw = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_KERNEL_STRIDE][31:24];
  assign s_pad_t = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_PADDING][7:0];
  assign s_pad_b = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_PADDING][15:8];
  assign s_pad_l = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_PADDING][23:16];
  assign s_pad_r = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_PADDING][31:24];
  assign s_tile_h = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_TILE_HW][7:0];
  assign s_tile_w = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_TILE_HW][15:8];

  assign s_is_kernel_op = (s_opcode == `APB4_NPU__OP_CONV2D) ||
      (s_opcode == `APB4_NPU__OP_DEPTHWISE3X3) || (s_opcode == `APB4_NPU__OP_MAX_POOL) ||
      (s_opcode == `APB4_NPU__OP_AVERAGE_POOL);
  assign s_is_weighted_op = (s_opcode == `APB4_NPU__OP_CONV2D) ||
      (s_opcode == `APB4_NPU__OP_DEPTHWISE3X3) || (s_opcode == `APB4_NPU__OP_FULLY_CONNECTED);
  assign s_is_param_op = s_is_weighted_op || (s_opcode == `APB4_NPU__OP_ADD);
  assign s_is_add = (s_opcode == `APB4_NPU__OP_ADD);
  assign s_is_gap = (s_opcode == `APB4_NPU__OP_GLOBAL_AVERAGE_POOL);

  // Computed output extent: positive floor semantics reproduced with the
  // multiply-frame equivalence floor(t/s)+1 == e  <=>  t >= 0 &&
  // (e-1)*s <= t < e*s for s > 0, which avoids a hardware divider.
  assign s_extent_h = $signed(
      {16'd0, s_dim_h}
  ) + $signed(
      {24'd0, s_pad_t}
  ) + $signed(
      {24'd0, s_pad_b}
  ) - $signed(
      {24'd0, s_kh}
  );
  assign s_extent_w = $signed(
      {16'd0, s_dim_w}
  ) + $signed(
      {24'd0, s_pad_l}
  ) + $signed(
      {24'd0, s_pad_r}
  ) - $signed(
      {24'd0, s_kw}
  );

  // Kernel-position count: kh*kw is the first multiply level, registered in
  // DecCompute; the per-opcode reduction below completes in DecCompute2.
  assign s_khkw = {8'd0, s_kh} * {8'd0, s_kw};
  always_comb begin
    unique case (s_opcode)
      `APB4_NPU__OP_CONV2D: begin
        s_full_k = {48'd0, s_khkw_q} * {48'd0, s_dim_cin};
      end
      `APB4_NPU__OP_DEPTHWISE3X3:        s_full_k = 64'd9;
      `APB4_NPU__OP_FULLY_CONNECTED:     s_full_k = {48'd0, s_dim_cin};
      `APB4_NPU__OP_MAX_POOL, `APB4_NPU__OP_AVERAGE_POOL: begin
        s_full_k = {48'd0, s_khkw_q};
      end
      `APB4_NPU__OP_GLOBAL_AVERAGE_POOL: s_full_k = {48'd0, s_dim_h} * {48'd0, s_dim_w};
      default:                           s_full_k = 64'd1;
    endcase
  end

  // Expected weight bytes: the last multiply level, registered in DecCompute3.
  always_comb begin
    if (s_opcode == `APB4_NPU__OP_DEPTHWISE3X3) begin
      s_weight_expect = (({48'd0, s_dim_cin} + 64'd7) >> 3) * 64'd72;
    end else begin
      s_weight_expect = (({48'd0, s_dim_cout} + 64'd7) >> 3) * s_full_k_q * 64'd8;
    end
  end

  assign s_min_row_in = {48'd0, s_dim_w} * {48'd0, s_dim_cin};
  assign s_min_row_out = {48'd0, s_dim_ow} * {48'd0, s_dim_cout};
  assign s_span_in0 = ({48'd0, s_dim_h} - 64'd1) *
      {32'd0, s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT0_ROW_BYTES]} + s_min_row_in_q;
  assign s_span_in1 = ({48'd0, s_dim_h} - 64'd1) *
      {32'd0, s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT1_ROW_BYTES]} + s_min_row_in_q;
  assign s_span_out = ({48'd0, s_dim_oh} - 64'd1) *
      {32'd0, s_words_q[`APB4_NPU__DESCRIPTOR_WORD_OUTPUT_ROW_BYTES]} + s_min_row_out_q;
  assign s_region_end = {32'd0, s_base_q} + {41'd0, s_count_q, 7'd0};

  // Overlap ranges in the golden validator's membership order: input0,
  // output, input1 (ADD only), weights, parameters, descriptor region.
  always_comb begin
    s_rng_base[0]  = {32'd0, s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT0_BASE]};
    s_rng_end[0]   = s_rng_base[0] + {32'd0, s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT0_BYTES]};
    s_rng_base[1]  = {32'd0, s_words_q[`APB4_NPU__DESCRIPTOR_WORD_OUTPUT_BASE]};
    s_rng_end[1]   = s_rng_base[1] + {32'd0, s_words_q[`APB4_NPU__DESCRIPTOR_WORD_OUTPUT_BYTES]};
    s_rng_base[2]  = {32'd0, s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT1_BASE]};
    s_rng_end[2]   = s_rng_base[2] + {32'd0, s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT1_BYTES]};
    s_rng_base[3]  = {32'd0, s_words_q[`APB4_NPU__DESCRIPTOR_WORD_WEIGHT_BASE]};
    s_rng_end[3]   = s_rng_base[3] + {32'd0, s_words_q[`APB4_NPU__DESCRIPTOR_WORD_WEIGHT_BYTES]};
    s_rng_base[4]  = {32'd0, s_words_q[`APB4_NPU__DESCRIPTOR_WORD_PARAM_BASE]};
    s_rng_end[4]   = s_rng_base[4] + {32'd0, s_words_q[`APB4_NPU__DESCRIPTOR_WORD_PARAM_BYTES]};
    s_rng_base[5]  = {32'd0, s_base_q};
    s_rng_end[5]   = s_region_end;
    s_rng_valid[0] = 1'b1;
    s_rng_valid[1] = 1'b1;
    s_rng_valid[2] = s_is_add;
    s_rng_valid[3] = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_WEIGHT_BYTES] != 32'd0;
    s_rng_valid[4] = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_PARAM_BYTES] != 32'd0;
    s_rng_valid[5] = 1'b1;
    s_overlap_pair = 1'b0;
    for (int unsigned range_a = 0; range_a < 5; range_a++) begin
      for (int unsigned range_b = range_a + 1; range_b < 6; range_b++) begin
        if (s_rng_valid[range_a] && s_rng_valid[range_b] &&
            !(s_is_add && (range_a == 0) && (range_b == 2))) begin
          if ((s_rng_base[range_a] < s_rng_end[range_b]) &&
              (s_rng_base[range_b] < s_rng_end[range_a])) begin
            s_overlap_pair = 1'b1;
          end
        end
      end
    end
  end

  // Validation check sequencer: one state per golden-validator stage, with the
  // intra-stage priority matching the script's first-fault order.
  always_comb begin
    logic [31:0] s_w0;
    logic [31:0] s_w1;
    logic [31:0] s_w3;
    logic [31:0] s_w5;
    logic [31:0] s_w11;
    logic [31:0] s_w12;
    logic [31:0] s_w13;
    logic [31:0] s_w14;
    logic [31:0] s_w15;
    logic [31:0] s_word16;
    logic [31:0] s_w17;
    logic [31:0] s_w18;
    logic [31:0] s_w19;
    logic [31:0] s_w20;
    logic [31:0] s_w21;
    logic [31:0] s_w22;
    logic [31:0] s_w23;
    logic [31:0] s_w24;
    logic [31:0] s_w25;
    logic        s_extent_h_pos;
    logic        s_extent_w_pos;
    logic        s_extent_h_match;
    logic        s_extent_w_match;
    logic [31:0] s_extent_h_u;
    logic [31:0] s_extent_w_u;
    s_w0 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_VERSION_OPCODE];
    s_w1 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_RESERVED];
    s_w3 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT1_BASE];
    s_w5 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_PARAM_BASE];
    s_w11 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT1_ROW_BYTES];
    s_w12 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_KERNEL_STRIDE];
    s_w13 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_PADDING];
    s_w14 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_TILE_HW];
    s_w15 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_K_SLICE];
    s_word16 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT0_BYTES];
    s_w17 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT1_BYTES];
    s_w18 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_OUTPUT_BYTES];
    s_w19 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_PARAM_BYTES];
    s_w20 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT0_ZERO];
    s_w21 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT1_ZERO];
    s_w22 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_OUTPUT_ZERO];
    s_w23 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_ACTIVATION_BOUNDS];
    s_w24 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_WEIGHT_BASE];
    s_w25 = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_WEIGHT_BYTES];
    s_extent_h_pos = !s_extent_h_q[31];
    s_extent_w_pos = !s_extent_w_q[31];
    s_extent_h_u = {1'b0, s_extent_h_q[30:0]};
    s_extent_w_u = {1'b0, s_extent_w_q[30:0]};
    s_extent_h_match = (({16'd0, s_dim_oh} - 32'd1) * {24'd0, s_sh} <= s_extent_h_u) &&
        (s_extent_h_u < {16'd0, s_dim_oh} * {24'd0, s_sh});
    s_extent_w_match = (({16'd0, s_dim_ow} - 32'd1) * {24'd0, s_sw} <= s_extent_w_u) &&
        (s_extent_w_u < {16'd0, s_dim_ow} * {24'd0, s_sw});

    s_chk_fail = 1'b0;
    s_chk_code = `APB4_NPU__FAULT_CODE_DESCRIPTOR;
    s_chk_word = 6'd0;
    s_chk_wordless = 1'b0;
    unique case (s_state_q)
      DecStruct1: begin
        if (s_w0[31:16] != `APB4_NPU__DESCRIPTOR_VERSION) begin
          s_chk_fail = 1'b1;
        end else if (s_w0[15:8] != 8'd0) begin
          s_chk_fail = 1'b1;
        end else if (s_w1 != 32'd0) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd1;
        end
      end
      DecStruct2: begin
        for (int unsigned word = 26; word < 32; word++) begin
          if (!s_chk_fail && (s_words_q[word] != 32'd0)) begin
            s_chk_fail = 1'b1;
            s_chk_word = 6'(word);
          end
        end
      end
      DecStruct3: begin
        if (s_w14[31:16] != 16'd0) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd14;
        end else if (s_w20[31:8] != 24'd0) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd20;
        end else if (s_w22[31:8] != 24'd0) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd22;
        end else if (s_w23[31:16] != 16'd0) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd23;
        end else if ($signed(s_w23[7:0]) > $signed(s_w23[15:8])) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd23;
        end
      end
      DecStruct4: begin
        if ((s_tile_h == 8'd0) || (s_tile_h > 8'd8) || (s_tile_w == 8'd0) ||
            (s_tile_w > 8'd8)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd14;
        end else if ({24'd0, s_tile_h} * {24'd0, s_tile_w} > 32'd8) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd14;
        end else if ((s_w15 == 32'd0) || (s_w15 > 32'd1024)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd15;
        end
      end
      DecOpcode: begin
        if ((s_opcode == 8'd0) || (s_opcode > 8'd8)) begin
          s_chk_fail = 1'b1;
          s_chk_code = `APB4_NPU__FAULT_CODE_UNSUPPORTED;
        end
      end
      DecUnused: begin
        if (!s_is_add && (s_w3 != 32'd0)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd3;
        end else if (!s_is_add && (s_w11 != 32'd0)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd11;
        end else if (!s_is_add && (s_w17 != 32'd0)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd17;
        end else if (!s_is_add && (s_w21 != 32'd0)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd21;
        end else if (!s_is_weighted_op && (s_w24 != 32'd0)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd24;
        end else if (!s_is_weighted_op && (s_w25 != 32'd0)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd25;
        end else if (!s_is_param_op && (s_w5 != 32'd0)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd5;
        end else if (!s_is_param_op && (s_w19 != 32'd0)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd19;
        end else if (s_is_gap && (s_w12 != 32'd0)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd12;
        end else if (s_is_gap && (s_w13 != 32'd0)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd13;
        end
      end
      DecGeom1: begin
        s_chk_code = `APB4_NPU__FAULT_CODE_RANGE;
        if ((s_dim_h == 16'd0) || (s_dim_h > 16'd4096)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd6;
        end else if ((s_dim_w == 16'd0) || (s_dim_w > 16'd4096)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd6;
        end else if ((s_dim_cin == 16'd0) || (s_dim_cin > 16'd4096)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd7;
        end else if ((s_dim_cout == 16'd0) || (s_dim_cout > 16'd4096)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd7;
        end else if ((s_dim_oh == 16'd0) || (s_dim_oh > 16'd4096)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd8;
        end else if ((s_dim_ow == 16'd0) || (s_dim_ow > 16'd4096)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd8;
        end
      end
      DecGeom2: begin
        if (s_is_kernel_op) begin
          s_chk_code = `APB4_NPU__FAULT_CODE_RANGE;
          if ((s_kh == 8'd0) || (s_kw == 8'd0) || (s_sh == 8'd0) || (s_sw == 8'd0)) begin
            s_chk_fail = 1'b1;
            s_chk_word = 6'd12;
          end else if (({24'd0, s_pad_t} >= {24'd0, s_kh}) ||
                       ({24'd0, s_pad_b} >= {24'd0, s_kh}) ||
                       ({24'd0, s_pad_l} >= {24'd0, s_kw}) ||
                       ({24'd0, s_pad_r} >= {24'd0, s_kw})) begin
            s_chk_fail = 1'b1;
            s_chk_word = 6'd13;
          end else if (!s_extent_h_pos || !s_extent_w_pos) begin
            s_chk_fail = 1'b1;
            s_chk_word = 6'd8;
          end else if (!s_extent_h_match || !s_extent_w_match) begin
            s_chk_fail = 1'b1;
            s_chk_word = 6'd8;
          end
        end
      end
      DecOper: begin
        unique case (s_opcode)
          `APB4_NPU__OP_CONV2D: begin
            s_chk_code = `APB4_NPU__FAULT_CODE_UNSUPPORTED;
            if ((s_kh > 8'd16) || (s_kw > 8'd16)) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd12;
            end else if (((s_sh != 8'd1) && (s_sh != 8'd2)) ||
                         ((s_sw != 8'd1) && (s_sw != 8'd2))) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd12;
            end
          end
          `APB4_NPU__OP_DEPTHWISE3X3: begin
            s_chk_code = `APB4_NPU__FAULT_CODE_UNSUPPORTED;
            if ((s_kh != 8'd3) || (s_kw != 8'd3)) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd12;
            end else if (((s_sh != 8'd1) && (s_sh != 8'd2)) ||
                         ((s_sw != 8'd1) && (s_sw != 8'd2))) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd12;
            end else if (s_dim_cout != s_dim_cin) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd7;
            end
          end
          `APB4_NPU__OP_FULLY_CONNECTED: begin
            s_chk_code = `APB4_NPU__FAULT_CODE_UNSUPPORTED;
            if ((s_dim_h != 16'd1) || (s_dim_w != 16'd1)) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd6;
            end else if ((s_dim_oh != 16'd1) || (s_dim_ow != 16'd1)) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd8;
            end else if (s_w12 != 32'h0101_0101) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd12;
            end else if (s_w13 != 32'd0) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd13;
            end
          end
          `APB4_NPU__OP_ADD: begin
            if (s_w21[31:8] != 24'd0) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd21;
            end else if (s_w3 == 32'd0) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd3;
            end else begin
              s_chk_code = `APB4_NPU__FAULT_CODE_UNSUPPORTED;
              if ((s_dim_oh != s_dim_h) || (s_dim_ow != s_dim_w)) begin
                s_chk_fail = 1'b1;
                s_chk_word = 6'd8;
              end else if (s_dim_cout != s_dim_cin) begin
                s_chk_fail = 1'b1;
                s_chk_word = 6'd7;
              end else if (s_w12 != 32'h0101_0101) begin
                s_chk_fail = 1'b1;
                s_chk_word = 6'd12;
              end else if (s_w13 != 32'd0) begin
                s_chk_fail = 1'b1;
                s_chk_word = 6'd13;
              end
            end
          end
          `APB4_NPU__OP_MAX_POOL, `APB4_NPU__OP_AVERAGE_POOL: begin
            s_chk_code = `APB4_NPU__FAULT_CODE_UNSUPPORTED;
            if ((s_kh > 8'd16) || (s_kw > 8'd16)) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd12;
            end else if (((s_sh != 8'd1) && (s_sh != 8'd2)) ||
                         ((s_sw != 8'd1) && (s_sw != 8'd2))) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd12;
            end else if (s_dim_cout != s_dim_cin) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd7;
            end else if (s_w20[7:0] != s_w22[7:0]) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd22;
            end
          end
          `APB4_NPU__OP_GLOBAL_AVERAGE_POOL: begin
            s_chk_code = `APB4_NPU__FAULT_CODE_UNSUPPORTED;
            if ((s_dim_oh != 16'd1) || (s_dim_ow != 16'd1)) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd8;
            end else if (s_dim_cout != s_dim_cin) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd7;
            end else if (s_w20[7:0] != s_w22[7:0]) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd22;
            end
          end
          default: begin
            // CLAMP
            s_chk_code = `APB4_NPU__FAULT_CODE_UNSUPPORTED;
            if ((s_dim_oh != s_dim_h) || (s_dim_ow != s_dim_w)) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd8;
            end else if (s_dim_cout != s_dim_cin) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd7;
            end else if (s_w20[7:0] != s_w22[7:0]) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd22;
            end else if (s_w12 != 32'h0101_0101) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd12;
            end else if (s_w13 != 32'd0) begin
              s_chk_fail = 1'b1;
              s_chk_word = 6'd13;
            end
          end
        endcase
      end
      DecOperCommon: begin
        if ({32'd0, s_w15} > s_full_k_q) begin
          s_chk_fail = 1'b1;
          s_chk_code = `APB4_NPU__FAULT_CODE_UNSUPPORTED;
          s_chk_word = 6'd15;
        end else if (({24'd0, s_tile_h} > {16'd0, s_dim_oh}) ||
                     ({24'd0, s_tile_w} > {16'd0, s_dim_ow})) begin
          s_chk_fail = 1'b1;
          s_chk_code = `APB4_NPU__FAULT_CODE_RANGE;
          s_chk_word = 6'd14;
        end else if (s_is_weighted_op) begin
          if (s_w24 == 32'd0) begin
            s_chk_fail = 1'b1;
            s_chk_word = 6'd24;
          end else if ({32'd0, s_w25} != s_weight_expect_q) begin
            s_chk_fail = 1'b1;
            s_chk_word = 6'd25;
          end else if (s_w5 == 32'd0) begin
            s_chk_fail = 1'b1;
            s_chk_word = 6'd5;
          end else if ({32'd0, s_w19} != ({48'd0, s_dim_cout} * 64'd16)) begin
            s_chk_fail = 1'b1;
            s_chk_word = 6'd19;
          end
        end else if (s_is_add) begin
          if (s_w5 == 32'd0) begin
            s_chk_fail = 1'b1;
            s_chk_word = 6'd5;
          end else if (s_w19 != 32'd32) begin
            s_chk_fail = 1'b1;
            s_chk_word = 6'd19;
          end
        end
      end
      DecStride: begin
        s_chk_code = `APB4_NPU__FAULT_CODE_RANGE;
        if ({32'd0, s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT0_ROW_BYTES]} < s_min_row_in_q) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd9;
        end else if ({32'd0, s_words_q[`APB4_NPU__DESCRIPTOR_WORD_OUTPUT_ROW_BYTES]} <
                     s_min_row_out_q) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd10;
        end else if (s_is_add && ({32'd0, s_w11} < s_min_row_in_q)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd11;
        end else if (s_span_in0_q > {32'd0, s_word16}) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd16;
        end else if ((s_rng_base_q[0] + s_span_in0_q) > 64'h1_0000_0000) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd2;
        end else if (s_rng_end_q[0] > 64'h1_0000_0000) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd2;
        end else if (s_is_add && (s_span_in1_q > {32'd0, s_w17})) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd17;
        end else if (s_is_add && ((s_rng_base_q[2] + s_span_in1_q) > 64'h1_0000_0000)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd3;
        end else if (s_is_add && (s_rng_end_q[2] > 64'h1_0000_0000)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd3;
        end else if (s_span_out_q > {32'd0, s_w18}) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd18;
        end else if ((s_rng_base_q[1] + s_span_out_q) > 64'h1_0000_0000) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd4;
        end else if (s_rng_end_q[1] > 64'h1_0000_0000) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd4;
        end else if ((s_w25 != 32'd0) && (s_rng_end_q[3] > 64'h1_0000_0000)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd24;
        end else if ((s_w19 != 32'd0) && (s_rng_end_q[4] > 64'h1_0000_0000)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd5;
        end
      end
      DecAlign: begin
        if ((s_w5 != 32'd0) && (s_w5[5:0] != 6'd0)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd5;
        end else if ((s_w24 != 32'd0) && (s_w24[5:0] != 6'd0)) begin
          s_chk_fail = 1'b1;
          s_chk_word = 6'd24;
        end
      end
      DecOverlap: begin
        s_chk_code     = `APB4_NPU__FAULT_CODE_RANGE;
        s_chk_wordless = 1'b1;
        if (s_region_end_q > 64'h1_0000_0000) begin
          s_chk_fail = 1'b1;
        end else if (s_overlap_pair_q) begin
          s_chk_fail = 1'b1;
        end
      end
      default: begin
      end
    endcase
  end

  assign read_req_valid_o = (s_state_q == DecFetchCmd) && !s_fetch_wrap && !clear_i;
  assign read_addr_o = s_desc_addr;
  assign read_bytes_o = 32'd128;
  assign read_data_ready_o = ((s_state_q == DecFetchData) || (s_state_q == DecDrain)) && !clear_i;

  assign busy_o = (s_state_q != DecIdle);
  assign pause_ok_o = (s_state_q != DecFetchData) && (s_state_q != DecDrain);
  assign cur_desc_index_o = s_index_q;
  assign progress_o = s_stream_accept || (rec_valid_o && rec_ready_i) || retired_i;
  assign fault_req_o = (s_state_q == DecFault);
  assign rec_valid_o = (s_state_q == DecEmit) && !clear_i;

  // all_done pulses when the final record retires; the core owns publication.
  assign all_done_o = (s_state_q == DecWaitRetire) && retired_i &&
      ((s_index_q + 16'd1) == s_count_q);

  assign fault_code_o = s_fault_code_q;
  assign fault_addr_o = s_fault_addr_q;
  assign fault_info_o = s_fault_info_q;
  assign fault_desc_o = {16'd0, s_fault_index_q};

  assign rec_opcode_o = 4'(s_opcode);
  assign rec_h_o = 13'(s_dim_h);
  assign rec_w_o = 13'(s_dim_w);
  assign rec_cin_o = 13'(s_dim_cin);
  assign rec_cout_o = 13'(s_dim_cout);
  assign rec_oh_o = 13'(s_dim_oh);
  assign rec_ow_o = 13'(s_dim_ow);
  assign rec_input0_base_o = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT0_BASE];
  assign rec_output_base_o = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_OUTPUT_BASE];
  assign rec_weight_base_o = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_WEIGHT_BASE];
  assign rec_param_base_o = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_PARAM_BASE];
  assign rec_input0_row_bytes_o = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT0_ROW_BYTES];
  assign rec_output_row_bytes_o = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_OUTPUT_ROW_BYTES];
  assign rec_kh_o = s_kh;
  assign rec_kw_o = s_kw;
  assign rec_sh_o = s_sh;
  assign rec_sw_o = s_sw;
  assign rec_pad_top_o = s_pad_t;
  assign rec_pad_left_o = s_pad_l;
  assign rec_input0_zero_o = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT0_ZERO][7:0];
  assign rec_tile_h_o = s_tile_h;
  assign rec_tile_w_o = s_tile_w;
  assign rec_k_slice_o = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_K_SLICE][15:0];
  assign rec_input1_base_o = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT1_BASE];
  assign rec_input1_row_bytes_o = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT1_ROW_BYTES];
  assign rec_input1_zero_o = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_INPUT1_ZERO][7:0];
  assign rec_output_zero_o = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_OUTPUT_ZERO][7:0];
  assign rec_act_min_o = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_ACTIVATION_BOUNDS][7:0];
  assign rec_act_max_o = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_ACTIVATION_BOUNDS][15:8];
  assign rec_weight_bytes_o = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_WEIGHT_BYTES];
  assign rec_param_bytes_o = s_words_q[`APB4_NPU__DESCRIPTOR_WORD_PARAM_BYTES];
  assign rec_desc_index_o = s_index_q;

  always_comb begin
    s_state_d = s_state_q;
    s_base_d  = s_base_q;
    s_count_d = s_count_q;
    s_index_d = s_index_q;
    unique case (s_state_q)
      DecIdle: begin
        if (job_start_i) begin
          s_base_d  = job_base_i;
          s_count_d = job_count_i;
          s_index_d = 16'd0;
          s_state_d = DecFetchCmd;
        end
      end
      DecFetchCmd: begin
        // A wrapped record address is a local RANGE rejection, never a bus
        // request; the DMA is never asked to fetch outside the 32-bit space.
        if (s_fetch_wrap || dma_fault_i) begin
          s_state_d = DecFault;
        end else if (s_cmd_accept) begin
          s_state_d = DecFetchData;
        end
      end
      DecFetchData: begin
        if (dma_fault_i) begin
          s_state_d = DecFault;
        end else if (s_last_accept) begin
          s_state_d = DecCompute;
        end
      end
      // Three pipeline cycles that register every wide derived quantity (one
      // multiply level each); the check sequencer below consumes registers.
      DecCompute:    s_state_d = DecCompute2;
      DecCompute2:   s_state_d = DecCompute3;
      DecCompute3:   s_state_d = DecStruct1;
      DecStruct1:    s_state_d = s_chk_fail ? DecFault : DecStruct2;
      DecStruct2:    s_state_d = s_chk_fail ? DecFault : DecStruct3;
      DecStruct3:    s_state_d = s_chk_fail ? DecFault : DecStruct4;
      DecStruct4:    s_state_d = s_chk_fail ? DecFault : DecOpcode;
      DecOpcode:     s_state_d = s_chk_fail ? DecFault : DecUnused;
      DecUnused:     s_state_d = s_chk_fail ? DecFault : DecGeom1;
      DecGeom1:      s_state_d = s_chk_fail ? DecFault : DecGeom2;
      DecGeom2:      s_state_d = s_chk_fail ? DecFault : DecOper;
      DecOper:       s_state_d = s_chk_fail ? DecFault : DecOperCommon;
      DecOperCommon: s_state_d = s_chk_fail ? DecFault : DecStride;
      DecStride:     s_state_d = s_chk_fail ? DecFault : DecAlign;
      DecAlign:      s_state_d = s_chk_fail ? DecFault : DecOverlap;
      DecOverlap:    s_state_d = s_chk_fail ? DecFault : DecEmit;
      DecEmit: begin
        if (rec_ready_i) begin
          s_state_d = DecWaitRetire;
        end
      end
      DecWaitRetire: begin
        if (retired_i) begin
          if ((s_index_q + 16'd1) == s_count_q) begin
            s_state_d = DecIdle;
          end else begin
            s_index_d = s_index_q + 16'd1;
            s_state_d = DecFetchCmd;
          end
        end
      end
      DecDrain: begin
        // Coordinated-cancel fetch drain: the accepted read segment always
        // runs out; after a DMA fault the stream is consumed while it lasts.
        if (s_last_accept || (!dma_read_busy_i && !read_data_valid_i)) begin
          s_state_d = DecIdle;
        end
      end
      DecFault: begin
        // Terminal until the core's coordinated cancel.
      end
      default:       s_state_d = DecIdle;
    endcase
    if (clear_i) begin
      unique case (s_state_q)
        // A presented-but-unaccepted fetch is withdrawn; an accepted one is
        // drained like any other in-flight segment.
        DecFetchCmd:  s_state_d = s_cmd_accept ? DecDrain : DecIdle;
        DecFetchData: s_state_d = DecDrain;
        default:      s_state_d = DecIdle;
      endcase
    end
  end

  always_ff @(posedge clk_hp_i or negedge rst_hp_n_i) begin
    if (!rst_hp_n_i) begin
      s_state_q         <= DecIdle;
      s_base_q          <= '0;
      s_count_q         <= '0;
      s_index_q         <= '0;
      s_beat_q          <= '0;
      s_fault_code_q    <= '0;
      s_fault_addr_q    <= '0;
      s_fault_info_q    <= '0;
      s_fault_index_q   <= '0;
      s_extent_h_q      <= '0;
      s_extent_w_q      <= '0;
      s_khkw_q          <= '0;
      s_full_k_q        <= '0;
      s_weight_expect_q <= '0;
      s_span_in0_q      <= '0;
      s_span_in1_q      <= '0;
      s_span_out_q      <= '0;
      s_min_row_in_q    <= '0;
      s_min_row_out_q   <= '0;
      s_region_end_q    <= '0;
      s_overlap_pair_q  <= 1'b0;
      for (int unsigned range = 0; range < 6; range++) begin
        s_rng_base_q[range] <= '0;
        s_rng_end_q[range]  <= '0;
      end
      for (int unsigned word = 0; word < 32; word++) begin
        s_words_q[word] <= '0;
      end
    end else begin
      s_state_q <= s_state_d;
      s_base_q  <= s_base_d;
      s_count_q <= s_count_d;
      s_index_q <= s_index_d;
      if (s_cmd_accept) begin
        s_beat_q <= 5'd0;
      end else if ((s_state_q == DecFetchData) && s_stream_accept) begin
        s_beat_q <= s_beat_q + 5'd1;
      end
      if ((s_state_q == DecFetchData) && s_stream_accept) begin
        s_words_q[{s_beat_q[3:0], 1'b0}] <= read_data_i[31:0];
        s_words_q[{s_beat_q[3:0], 1'b1}] <= read_data_i[63:32];
      end
      if (s_state_q == DecCompute) begin
        s_extent_h_q     <= s_extent_h;
        s_extent_w_q     <= s_extent_w;
        s_khkw_q         <= s_khkw;
        s_min_row_in_q   <= s_min_row_in;
        s_min_row_out_q  <= s_min_row_out;
        s_region_end_q   <= s_region_end;
        s_overlap_pair_q <= s_overlap_pair;
        for (int unsigned range = 0; range < 6; range++) begin
          s_rng_base_q[range] <= s_rng_base[range];
          s_rng_end_q[range]  <= s_rng_end[range];
        end
      end
      if (s_state_q == DecCompute2) begin
        s_full_k_q   <= s_full_k;
        s_span_in0_q <= s_span_in0;
        s_span_in1_q <= s_span_in1;
        s_span_out_q <= s_span_out;
      end
      if (s_state_q == DecCompute3) begin
        s_weight_expect_q <= s_weight_expect;
      end
      if ((s_state_q != DecFault) && (s_state_d == DecFault)) begin
        if (s_fetch_wrap) begin
          // Local wrap rejection: RANGE with no single offending word.
          s_fault_code_q <= `APB4_NPU__FAULT_CODE_RANGE;
          s_fault_addr_q <= s_desc_addr;
          s_fault_info_q <= FaultInfoInternal;
        end else if (dma_fault_i) begin
          // Bus fault while fetching: forward code/address/response.
          s_fault_code_q <= dma_fault_code_i;
          s_fault_addr_q <= dma_fault_addr_i;
          s_fault_info_q <= {16'd0, 8'd255, 4'd0, 2'd1, dma_fault_resp_i};
        end else begin
          s_fault_code_q <= s_chk_code;
          s_fault_addr_q <= s_chk_wordless ? s_desc_addr :
              (s_desc_addr + {24'd0, s_chk_word, 2'b00});
          s_fault_info_q <= FaultInfoInternal;
        end
        s_fault_index_q <= s_index_q;
      end
    end
  end

`ifndef SV_ASSRT_DISABLE
  logic       s_rec_wait_q;
  logic [4:0] s_beat_seen_q;

  always_ff @(posedge clk_hp_i or negedge rst_hp_n_i) begin
    if (!rst_hp_n_i) begin
      s_rec_wait_q  <= 1'b0;
      s_beat_seen_q <= 5'd0;
    end else begin
      s_rec_wait_q <= rec_valid_o && !rec_ready_i;
      if (s_state_q == DecFetchCmd) begin
        s_beat_seen_q <= 5'd0;
      end else if ((s_state_q == DecFetchData) && s_stream_accept) begin
        s_beat_seen_q <= s_beat_seen_q + 5'd1;
      end
      // A presented record holds stable until the scheduler accepts it.
      if (s_rec_wait_q) begin
        assert (rec_valid_o);
      end
      // A descriptor fetch is exactly sixteen 64-bit beats.
      if ((s_state_q == DecFetchData) && (s_state_d == DecCompute)) begin
        assert (s_beat_seen_q == 5'd15);
      end
      // The staging writes stay inside the 32-word record.
      if ((s_state_q == DecFetchData) && s_stream_accept) begin
        assert (s_beat_q < 5'd16);
      end
    end
  end
`endif
endmodule
