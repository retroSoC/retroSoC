// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_kernel_engine (
    // verilog_format: off -- preserve request, local-memory, and result columns
    input  logic                  clk_i,
    input  logic                  rst_n_i,
    input  logic                  flush_i,
    input  logic                  req_valid_i,
    output logic                  req_ready_o,
    input  logic [ 3:0]           opcode_i,
    input  logic [ 7:0]           aux_i,
    input  logic [15:0]           count_i,
    input  logic [ 3:0]           dst_i,
    input  logic [31:0]           input_offset_i,
    input  logic [31:0]           parameter_offset_i,
    input  logic [31:0]           output_offset_i,
    input  logic [16:0]           scratch_base_i,
    input  logic [16:0]           scratch_bytes_i,
    input  logic [15:0]           table_offset_i,
    input  logic [15:0]           table_bytes_i,
    output logic                  memory_req_o,
    output logic                  memory_write_o,
    output logic [16:0]           memory_addr_o,
    output logic [31:0]           memory_data_o,
    output logic [ 3:0]           memory_strb_o,
    input  logic                  memory_valid_i,
    input  logic [31:0]           memory_data_i,
    input  logic                  memory_error_i,
    output logic                  done_o,
    output logic                  error_o,
    output logic [ 5:0]           error_code_o,
    output logic [ 3:0]           error_stage_o,
    output logic [ 7:0]           error_reason_o,
    output logic [ 3:0]           result_dst_o,
    output logic [31:0]           result_count_o,
    output logic [31:0]           cycles_o,
    output logic                  busy_o
    // verilog_format: on
);
  typedef enum logic [5:0] {
    Idle,
    ParameterRequest,
    ParameterWait,
    Validate,
    Ready,
    RequantInputRequest,
    RequantInputWait,
    RequantScaleRequest,
    RequantScaleWait,
    RequantWrite,
    StereoFirstRequest,
    StereoFirstWait,
    StereoSecondRequest,
    StereoSecondWait,
    StereoWriteFirst,
    StereoWriteSecond,
    HistoryRequest,
    HistoryWait,
    CoefficientRequest,
    CoefficientWait,
    PredictInputRequest,
    PredictInputWait,
    PredictWrite,
    HistoryWrite,
    TransformInputRequest,
    TransformInputWait,
    TransformCoefficientRequest,
    TransformCoefficientWait,
    TransformWrite,
    DctHistoryRequest,
    DctHistoryWait,
    DctWindowRequest,
    DctWindowWait,
    DctOutputWrite,
    DctPhaseWrite,
    ResampleCopyRequest,
    ResampleCopyWait,
    ResampleCopyWrite,
    ResampleSampleRequest,
    ResampleSampleWait,
    ResampleCoefficientRequest,
    ResampleCoefficientWait,
    ResampleWrite,
    ResampleStateWrite,
    PcmInputRequest,
    PcmInputWait,
    PcmWrite,
    PcmDuplicateWrite,
    Finish,
    Failed
  } state_e;

  state_e s_state_q;
  logic [3:0] s_opcode_q, s_dst_q;
  logic [ 7:0] s_aux_q;
  logic [15:0] s_count_q;
  logic [31:0] s_input_offset_q, s_parameter_offset_q, s_output_offset_q;
  logic [16:0] s_scratch_base_q, s_scratch_bytes_q;
  logic [15:0] s_table_offset_q, s_table_bytes_q;
  logic [7:0][31:0] s_parameter_q;
  logic [3:0] s_parameter_words_q, s_parameter_index_q;
  logic [31:0] s_element_q, s_block_q, s_row_q, s_tap_q, s_channel_q;
  logic [31:0] s_read_issue_q, s_read_receive_q;
  logic s_pair_issue_second_q, s_pair_return_second_q, s_transform_preload_q;
  logic       s_resample_profile_valid_q;
  logic [3:0] s_resample_profile_q;
  logic [31:0] s_produced_q, s_cycles_q;
  logic [31:0] s_value0_q, s_value1_q, s_history_value_q;
  logic signed [71:0] s_accumulator_q;
  logic signed [31:0] s_vector_q      [0:31];
  logic signed [31:0] s_coefficient_q [0:31];
  logic signed [31:0] s_history_q     [0:31];
  logic [63:0] s_next_output_q, s_input_base_q;
  logic [15:0] s_ratio_l, s_ratio_m;
  logic [ 5:0] s_resample_phase;
  logic [63:0] s_resample_source_index;
  logic [31:0] s_resample_channels;
  logic [31:0] s_transform_order;
  logic [31:0] s_input_addr, s_parameter_addr, s_output_addr;
  logic [32:0] s_input_addr_full, s_parameter_addr_full, s_output_addr_full;
  logic [31:0] s_reference_addr[0:2];
  logic s_alignment_ok, s_validation_ok;
  logic s_semantic_err;
  logic [32:0] s_output_bytes, s_input_bytes;
  logic [32:0] s_resample_output_frames;
  logic [63:0] s_resample_limit_num, s_resample_remaining_num;
  logic [32:0] s_resample_history_bytes, s_resample_input_bytes;
  logic [32:0] s_resample_input_start;
  logic [31:0] s_predict_order;
  logic [ 3:0] s_dct_history_phase;
  logic signed [31:0] s_reconstruction_result0, s_reconstruction_result1;
  logic s_reconstruction_overflow;
  logic signed [31:0] s_stereo_live_result0, s_stereo_live_result1;
  logic               s_stereo_live_overflow;
  logic signed [31:0] s_transform_result;
  logic               s_transform_overflow;
  logic signed [31:0] s_transform_coefficient  [0:31];
  logic               s_transform_final_return;
  logic        [31:0] s_pcm_word;
  logic        [ 3:0] s_pcm_strb;
  logic        [ 1:0] s_pcm_lane;
  logic               s_unused;

  function automatic logic range_valid(input logic [31:0] address_i, input logic [32:0] bytes_i,
                                       input logic [31:0] base_i, input logic [31:0] size_i);
    logic [32:0] s_end;
    logic [32:0] s_limit;
    begin
      s_end   = {1'b0, address_i} + bytes_i;
      s_limit = {1'b0, base_i} + {1'b0, size_i};
      return !s_end[32] && (address_i >= base_i) && (s_end <= s_limit);
    end
  endfunction

  function automatic logic reference_valid(
      input logic [31:0] reference_i, input logic [32:0] bytes_i, input logic state_only_i,
      input logic [16:0] scratch_base_arg, input logic [16:0] scratch_bytes_arg,
      input logic [15:0] table_offset_arg, input logic [15:0] table_bytes_arg);
    logic        s_table;
    logic [31:0] s_offset;
    logic [31:0] s_address;
    logic        s_reserved_ok;
    begin
      s_table = reference_i[31];
      s_offset = s_table ? {16'd0, reference_i[15:0]} : {15'd0, reference_i[16:0]};
      s_address = s_table ? ({16'd0, table_offset_arg} + s_offset) :
          ({15'd0, scratch_base_arg} + s_offset);
      s_reserved_ok = s_table ? (reference_i[30:16] == 15'd0) : (reference_i[30:17] == 14'd0);
      return s_reserved_ok && (reference_i[1:0] == 2'd0) && (!state_only_i || !s_table) &&
          (s_table ? range_valid(
          s_address, bytes_i, {16'd0, table_offset_arg}, {16'd0, table_bytes_arg}
      ) : range_valid(
          s_address, bytes_i, {15'd0, scratch_base_arg}, {15'd0, scratch_bytes_arg}
      ));
    end
  endfunction

  function automatic logic [31:0] reference_address(input logic [31:0] reference_i,
                                                    input logic [16:0] scratch_base_arg,
                                                    input logic [15:0] table_offset_arg);
    logic s_reserved_unused;
    begin
      s_reserved_unused = ^reference_i[30:17];
      return (reference_i[31] ?
          ({16'd0, table_offset_arg} + {16'd0, reference_i[15:0]}) :
          ({15'd0, scratch_base_arg} + {15'd0, reference_i[16:0]})) |
          {32{s_reserved_unused && 1'b0}};
    end
  endfunction

  function automatic logic signed [63:0] rne64(input logic signed [63:0] value_i,
                                               input logic [5:0] shift_i);
    logic signed [63:0] s_magnitude;
    logic signed [63:0] s_quotient;
    logic [63:0] s_remainder, s_half;
    begin
      if (shift_i == 6'd0) return value_i;
      s_magnitude = (value_i < 0) ? -value_i : value_i;
      s_quotient  = s_magnitude >>> shift_i;
      s_remainder = s_magnitude & ((64'd1 << shift_i) - 1'b1);
      s_half      = 64'd1 << (shift_i - 1'b1);
      if ((s_remainder > s_half) || ((s_remainder == s_half) && s_quotient[0])) begin
        s_quotient = s_quotient + 1'b1;
      end
      return (value_i < 0) ? -s_quotient : s_quotient;
    end
  endfunction

  function automatic logic signed [31:0] sat32(input logic signed [71:0] value_i);
    if (value_i > 72'sh0000_0000_7fff_ffff) return 32'sh7fff_ffff;
    if (value_i < -72'sh0000_0000_8000_0000) return -32'sh8000_0000;
    return value_i[31:0];
  endfunction

  function automatic logic signed [71:0] rne72(input logic signed [71:0] value_i,
                                               input logic [5:0] shift_i);
    logic signed [71:0] s_magnitude;
    logic signed [71:0] s_quotient;
    logic [71:0] s_remainder, s_half;
    begin
      if (shift_i == 6'd0) return value_i;
      s_magnitude = (value_i < 0) ? -value_i : value_i;
      s_quotient  = s_magnitude >>> shift_i;
      s_remainder = s_magnitude & ((72'd1 << shift_i) - 1'b1);
      s_half      = 72'd1 << (shift_i - 1'b1);
      if ((s_remainder > s_half) || ((s_remainder == s_half) && s_quotient[0])) begin
        s_quotient = s_quotient + 1'b1;
      end
      return (value_i < 0) ? -s_quotient : s_quotient;
    end
  endfunction

  assign busy_o = s_state_q != Idle;
  assign s_unused = ^s_stereo_live_result1 && 1'b0;
  assign req_ready_o = s_state_q == Ready;
  assign s_input_addr_full = {16'd0, s_scratch_base_q} + {1'b0, s_input_offset_q};
  assign s_parameter_addr_full = {16'd0, s_scratch_base_q} + {1'b0, s_parameter_offset_q};
  assign s_output_addr_full = {16'd0, s_scratch_base_q} + {1'b0, s_output_offset_q};
  assign s_input_addr = s_input_addr_full[31:0];
  assign s_parameter_addr = s_parameter_addr_full[31:0];
  assign s_output_addr = s_output_addr_full[31:0];
  assign s_transform_order = (s_opcode_q == `APB4_APU__MC_KERNEL_IMDCT6) ? 32'd6 :
      ((s_opcode_q == `APB4_APU__MC_KERNEL_IMDCT18) ? 32'd18 : 32'd32);
  assign s_resample_channels = s_parameter_q[7];
  assign s_reference_addr[0] = reference_address(
      s_parameter_q[0], s_scratch_base_q, s_table_offset_q
  );
  assign s_reference_addr[1] = reference_address(
      s_parameter_q[1], s_scratch_base_q, s_table_offset_q
  );
  assign s_reference_addr[2] = reference_address(
      s_parameter_q[2], s_scratch_base_q, s_table_offset_q
  );
  assign s_predict_order = (s_opcode_q == `APB4_APU__MC_KERNEL_LPC) ?
      {26'd0, s_aux_q[5:0]} : {29'd0, s_aux_q[2:0]};
  assign s_dct_history_phase = s_parameter_q[3][3:0] - s_tap_q[3:0];

  apu_reconstruction_engine u_reconstruction_engine (
      .opcode_i         (s_opcode_q),
      .aux_i            (s_aux_q),
      .value0_i         (s_value0_q),
      .value1_i         (s_value1_q),
      .scale_i          (s_coefficient_q[0]),
      .residual_i       (s_value0_q),
      .predictor_shift_i(s_parameter_q[2]),
      .history_i        (s_history_q),
      .coefficient_i    (s_coefficient_q),
      .result0_o        (s_reconstruction_result0),
      .result1_o        (s_reconstruction_result1),
      .overflow_o       (s_reconstruction_overflow)
  );

  apu_reconstruction_engine u_stereo_live_engine (
      .opcode_i         (s_opcode_q),
      .aux_i            (s_aux_q),
      .value0_i         (s_value0_q),
      .value1_i         (memory_data_i),
      .scale_i          (32'sd0),
      .residual_i       (32'sd0),
      .predictor_shift_i(32'sd0),
      .history_i        (s_history_q),
      .coefficient_i    (s_coefficient_q),
      .result0_o        (s_stereo_live_result0),
      .result1_o        (s_stereo_live_result1),
      .overflow_o       (s_stereo_live_overflow)
  );

  apu_transform_engine u_transform_engine (
      .order_i      (s_transform_order[5:0]),
      .sample_i     (s_vector_q),
      .coefficient_i(s_transform_coefficient),
      .result_o     (s_transform_result),
      .overflow_o   (s_transform_overflow)
  );

  always_comb begin
    for (int index = 0; index < 32; index++) begin
      s_transform_coefficient[index] = s_coefficient_q[index];
    end
    if ((s_state_q == TransformCoefficientRequest) && memory_valid_i &&
        (s_read_receive_q < 32'd32)) begin
      s_transform_coefficient[s_read_receive_q[4:0]] = memory_data_i;
    end
    s_transform_final_return = (s_state_q == TransformCoefficientRequest) &&
        memory_valid_i && (s_read_receive_q + 1'b1 >= s_transform_order);
  end

  always_comb begin
    s_semantic_err = 1'b0;
    unique case (s_opcode_q)
      `APB4_APU__MC_KERNEL_DCT32_POLY: s_semantic_err = s_parameter_q[3][31:4] != 28'd0;
      `APB4_APU__MC_KERNEL_LPC:
      s_semantic_err = ($signed(s_parameter_q[2]) < -32'sd31) ||
          ($signed(s_parameter_q[2]) > 32'sd31);
      `APB4_APU__MC_KERNEL_RESAMPLE:
      s_semantic_err = !(s_resample_channels inside {32'd1, 32'd2}) ||
          (s_resample_profile_valid_q && (s_aux_q[3:0] != s_resample_profile_q));
      `APB4_APU__MC_KERNEL_PCM_PACK:
      s_semantic_err = !(s_parameter_q[1] inside {32'd1, 32'd2}) ||
          (s_aux_q[2] && (s_parameter_q[1] != 32'd1));
      default: s_semantic_err = 1'b0;
    endcase
  end

  apu_resampler u_resampler (
      .profile_i        (s_aux_q[3:0]),
      .next_output_num_i(s_next_output_q),
      .ratio_l_o        (s_ratio_l),
      .ratio_m_o        (s_ratio_m),
      .phase_o          (s_resample_phase),
      .source_index_o   (s_resample_source_index)
  );

  always_comb begin
    s_resample_limit_num = (s_input_base_q + {48'd0, s_count_q}) * s_ratio_l;
    s_resample_remaining_num = (s_next_output_q < s_resample_limit_num) ?
        (s_resample_limit_num - s_next_output_q) : 64'd0;
    s_resample_output_frames = 33'((s_resample_remaining_num + {48'd0, s_ratio_m} -
        64'd1) / {48'd0, s_ratio_m});
    s_resample_history_bytes = ({1'b0, s_resample_channels} * 33'd7) << 2;
    s_resample_input_bytes = (({17'd0, s_count_q} + 33'd16) * {1'b0, s_resample_channels}) << 2;
    s_resample_input_start = {1'b0, s_input_addr} - s_resample_history_bytes;
    s_input_bytes = 33'd0;
    s_output_bytes = 33'd0;
    unique case (s_opcode_q)
      `APB4_APU__MC_KERNEL_REQUANT, `APB4_APU__MC_KERNEL_FIXED, `APB4_APU__MC_KERNEL_LPC: begin
        s_input_bytes  = {17'd0, s_count_q} << 2;
        s_output_bytes = {17'd0, s_count_q} << 2;
      end
      `APB4_APU__MC_KERNEL_STEREO, `APB4_APU__MC_KERNEL_DECORRELATE: begin
        s_input_bytes  = {17'd0, s_count_q} << 2;
        s_output_bytes = {17'd0, s_count_q} << 3;
      end
      `APB4_APU__MC_KERNEL_IMDCT6: begin
        s_input_bytes  = ({17'd0, s_count_q} * 33'd6) << 2;
        s_output_bytes = ({17'd0, s_count_q} * 33'd12) << 2;
      end
      `APB4_APU__MC_KERNEL_IMDCT18: begin
        s_input_bytes  = ({17'd0, s_count_q} * 33'd18) << 2;
        s_output_bytes = ({17'd0, s_count_q} * 33'd36) << 2;
      end
      `APB4_APU__MC_KERNEL_DCT32_POLY: begin
        s_input_bytes  = ({17'd0, s_count_q} * 33'd32) << 2;
        s_output_bytes = ({17'd0, s_count_q} * 33'd32) << 2;
      end
      `APB4_APU__MC_KERNEL_RESAMPLE: begin
        s_input_bytes = (s_aux_q[3:0] == 4'd0) ?
            (({17'd0, s_count_q} * {1'b0, s_resample_channels}) << 2) :
            s_resample_input_bytes;
        s_output_bytes = (s_aux_q[3:0] == 4'd0) ?
            (({17'd0, s_count_q} * {1'b0, s_resample_channels}) << 2) :
            ((s_resample_output_frames * {1'b0, s_resample_channels}) << 2);
      end
      default: begin
        s_input_bytes = ({17'd0, s_count_q} * {1'b0, s_parameter_q[1]}) << 2;
        s_output_bytes = ({17'd0, s_count_q} * {1'b0, s_parameter_q[1]}) <<
            ((s_aux_q[1:0] == 2'd0) ? 1 : 2);
        if (s_aux_q[2]) s_output_bytes = s_output_bytes << 1;
      end
    endcase
  end

  always_comb begin
    logic [32:0] s_scale_bytes;
    logic [32:0] s_transform_bytes;
    logic [32:0] s_history_bytes;
    s_scale_bytes = {17'd0, s_count_q} << 2;
    s_transform_bytes = ({1'b0, s_transform_order} * {1'b0, s_transform_order} * 33'd2) << 2;
    s_history_bytes = {27'd0, s_aux_q[5:0]} << 2;
    s_alignment_ok = (s_scratch_base_q[1:0] == 2'd0) &&
        (s_input_offset_q[1:0] == 2'd0) && (s_parameter_offset_q[1:0] == 2'd0) &&
        ((s_opcode_q != `APB4_APU__MC_KERNEL_PCM_PACK) ?
         (s_output_offset_q[1:0] == 2'd0) :
         ((s_aux_q[1:0] == 2'd0) ? !s_output_offset_q[0] :
          (s_output_offset_q[1:0] == 2'd0)));
    s_validation_ok = s_alignment_ok && !s_input_addr_full[32] && !s_parameter_addr_full[32] &&
        !s_output_addr_full[32] &&
        range_valid(
      s_parameter_addr,
      {29'd0, s_parameter_words_q} << 2,
      {15'd0, s_scratch_base_q},
      {15'd0, s_scratch_bytes_q}
    ) && range_valid(
      ((s_opcode_q == `APB4_APU__MC_KERNEL_RESAMPLE) && (s_aux_q[3:0] != 4'd0)) ?
                    s_resample_input_start[31:0] : s_input_addr,
      s_input_bytes,
      {15'd0, s_scratch_base_q},
      {15'd0, s_scratch_bytes_q}
    ) && range_valid(
      s_output_addr, s_output_bytes, {15'd0, s_scratch_base_q}, {15'd0, s_scratch_bytes_q}
    );
    unique case (s_opcode_q)
      `APB4_APU__MC_KERNEL_REQUANT:
      s_validation_ok = s_validation_ok && reference_valid(
        s_parameter_q[0],
        s_scale_bytes,
        1'b0,
        s_scratch_base_q,
        s_scratch_bytes_q,
        s_table_offset_q,
        s_table_bytes_q
      );
      `APB4_APU__MC_KERNEL_STEREO, `APB4_APU__MC_KERNEL_DECORRELATE:
      s_validation_ok = s_validation_ok && reference_valid(
        s_parameter_q[0],
        {17'd0, s_count_q} << 2,
        1'b1,
        s_scratch_base_q,
        s_scratch_bytes_q,
        s_table_offset_q,
        s_table_bytes_q
      );
      `APB4_APU__MC_KERNEL_IMDCT6, `APB4_APU__MC_KERNEL_IMDCT18:
      s_validation_ok = s_validation_ok && reference_valid(
        s_parameter_q[0],
        s_transform_bytes,
        1'b0,
        s_scratch_base_q,
        s_scratch_bytes_q,
        s_table_offset_q,
        s_table_bytes_q
      );
      `APB4_APU__MC_KERNEL_DCT32_POLY:
      s_validation_ok = s_validation_ok && (s_parameter_q[3][31:4] == 28'd0) && reference_valid(
        s_parameter_q[0],
        33'd4096,
        1'b0,
        s_scratch_base_q,
        s_scratch_bytes_q,
        s_table_offset_q,
        s_table_bytes_q
      ) && reference_valid(
        s_parameter_q[1],
        33'd2048,
        1'b0,
        s_scratch_base_q,
        s_scratch_bytes_q,
        s_table_offset_q,
        s_table_bytes_q
      ) && reference_valid(
        s_parameter_q[2],
        33'd2048,
        1'b1,
        s_scratch_base_q,
        s_scratch_bytes_q,
        s_table_offset_q,
        s_table_bytes_q
      );
      `APB4_APU__MC_KERNEL_FIXED:
      s_validation_ok = s_validation_ok && reference_valid(
        s_parameter_q[0],
        (s_aux_q[2:0] == 3'd0) ? 33'd0 : ({30'd0, s_aux_q[2:0]} << 2),
        1'b1,
        s_scratch_base_q,
        s_scratch_bytes_q,
        s_table_offset_q,
        s_table_bytes_q
      );
      `APB4_APU__MC_KERNEL_LPC:
      s_validation_ok = s_validation_ok && ($signed(
          s_parameter_q[2]
      ) >= -32'sd31) && ($signed(
          s_parameter_q[2]
      ) <= 32'sd31) && reference_valid(
        s_parameter_q[0],
        s_history_bytes,
        1'b0,
        s_scratch_base_q,
        s_scratch_bytes_q,
        s_table_offset_q,
        s_table_bytes_q
      ) && reference_valid(
        s_parameter_q[1],
        s_history_bytes,
        1'b1,
        s_scratch_base_q,
        s_scratch_bytes_q,
        s_table_offset_q,
        s_table_bytes_q
      );
      `APB4_APU__MC_KERNEL_RESAMPLE:
      s_validation_ok = s_validation_ok && (s_resample_channels inside {32'd1, 32'd2}) &&
          ((s_aux_q[3:0] == 4'd0) ||
           (!s_resample_input_start[32] &&
            ({1'b0, s_input_addr} >= s_resample_history_bytes))) &&
          ((s_aux_q[3:0] == 4'd0) || reference_valid(
        s_parameter_q[(s_aux_q[3:0] inside {4'd1, 4'd2})?2 : ((s_aux_q[3:0]==4'd14)?1 : 0)],
        33'd2048,
        1'b0,
        s_scratch_base_q,
        s_scratch_bytes_q,
        s_table_offset_q,
        s_table_bytes_q
      ));
      default:
      s_validation_ok = s_validation_ok && (s_parameter_q[1] inside {32'd1, 32'd2}) &&
          (!s_aux_q[2] || (s_parameter_q[1] == 32'd1));
    endcase
  end

  always_comb begin
    memory_req_o   = 1'b0;
    memory_write_o = 1'b0;
    memory_addr_o  = 17'd0;
    memory_data_o  = 32'd0;
    memory_strb_o  = 4'hf;
    unique case (s_state_q)
      ParameterRequest: begin
        memory_req_o  = 1'b1;
        memory_addr_o = 17'(s_parameter_addr + ({28'd0, s_parameter_index_q} << 2));
      end
      RequantInputRequest, StereoFirstRequest, PredictInputRequest, PcmInputRequest: begin
        memory_req_o  = 1'b1;
        memory_addr_o = 17'(s_input_addr + (s_element_q << 2));
      end
      RequantInputWait, RequantScaleRequest: begin
        memory_req_o  = 1'b1;
        memory_addr_o = 17'(s_reference_addr[0] + (s_element_q << 2));
      end
      RequantWrite, PredictWrite: begin
        memory_req_o   = 1'b1;
        memory_write_o = 1'b1;
        memory_addr_o  = 17'(s_output_addr + (s_element_q << 2));
        memory_data_o  = s_reconstruction_result0;
      end
      StereoFirstWait, StereoSecondRequest: begin
        memory_req_o  = 1'b1;
        memory_addr_o = 17'(s_reference_addr[0] + (s_element_q << 2));
      end
      StereoSecondWait: begin
        memory_req_o = memory_valid_i &&
            !((s_opcode_q == `APB4_APU__MC_KERNEL_DECORRELATE) && s_stereo_live_overflow);
        memory_write_o = memory_req_o;
        memory_addr_o = 17'(s_output_addr + (s_element_q << 2));
        memory_data_o = s_stereo_live_result0;
      end
      StereoWriteFirst, StereoWriteSecond: begin
        memory_req_o = 1'b1;
        memory_write_o = 1'b1;
        memory_addr_o = 17'(s_output_addr + (((s_state_q == StereoWriteSecond) ?
            ({16'd0, s_count_q} + s_element_q) : s_element_q) << 2));
        memory_data_o = (s_state_q == StereoWriteSecond) ?
            s_reconstruction_result1 : s_reconstruction_result0;
      end
      HistoryRequest: begin
        memory_req_o = s_read_issue_q < s_predict_order;
        memory_addr_o = 17'(s_reference_addr[(s_opcode_q ==
            `APB4_APU__MC_KERNEL_LPC) ? 1 : 0] + (s_read_issue_q << 2));
      end
      CoefficientRequest: begin
        memory_req_o  = s_read_issue_q < s_predict_order;
        memory_addr_o = 17'(s_reference_addr[0] + (s_read_issue_q << 2));
      end
      HistoryWrite: begin
        memory_req_o = 1'b1;
        memory_write_o = 1'b1;
        memory_addr_o = 17'(s_reference_addr[(s_opcode_q ==
            `APB4_APU__MC_KERNEL_LPC) ? 1 : 0] + (s_tap_q << 2));
        memory_data_o = s_history_q[s_tap_q[4:0]];
      end
      TransformInputRequest: begin
        memory_req_o = s_read_issue_q < s_transform_order;
        memory_addr_o = 17'(s_input_addr +
            (((s_block_q * s_transform_order) + s_read_issue_q) << 2));
      end
      TransformCoefficientRequest: begin
        memory_req_o = s_transform_final_return || (s_read_issue_q < s_transform_order);
        memory_write_o = s_transform_final_return;
        memory_addr_o = s_transform_final_return ?
            ((s_opcode_q == `APB4_APU__MC_KERNEL_DCT32_POLY) ?
             17'(s_reference_addr[2] +
                 (((s_parameter_q[3][3:0] * 32) + s_row_q) << 2)) :
             17'(s_output_addr +
                 (((s_block_q * s_transform_order * 2) + s_row_q) << 2))) :
            17'(s_reference_addr[0] +
                (((s_row_q * s_transform_order) + s_read_issue_q) << 2));
        memory_data_o = s_transform_result;
      end
      TransformWrite: begin
        memory_req_o = 1'b1;
        memory_write_o = 1'b1;
        memory_addr_o = (s_opcode_q == `APB4_APU__MC_KERNEL_DCT32_POLY) ?
            17'(s_reference_addr[2] + (((s_parameter_q[3][3:0] * 32) + s_row_q) << 2)) :
            17'(s_output_addr + (((s_block_q * s_transform_order * 2) + s_row_q) << 2));
        memory_data_o = s_transform_result;
      end
      DctHistoryRequest: begin
        memory_req_o = s_tap_q < 32'd16;
        memory_addr_o = s_pair_issue_second_q ?
            17'(s_reference_addr[1] + (((s_tap_q * 32) + s_row_q) << 2)) :
            17'(s_reference_addr[2] +
                ((({28'd0, s_dct_history_phase} * 32'd32) + s_row_q) << 2));
      end
      DctOutputWrite: begin
        memory_req_o   = 1'b1;
        memory_write_o = 1'b1;
        memory_addr_o  = 17'(s_output_addr + (((s_block_q * 32) + s_row_q) << 2));
        memory_data_o  = sat32(rne72(s_accumulator_q, 6'd30));
      end
      DctPhaseWrite: begin
        memory_req_o   = 1'b1;
        memory_write_o = 1'b1;
        memory_addr_o  = 17'(s_parameter_addr + 32'd12);
        memory_data_o  = {28'd0, s_parameter_q[3][3:0] + 1'b1};
      end
      ResampleCopyRequest: begin
        memory_req_o  = 1'b1;
        memory_addr_o = 17'(s_input_addr + (s_element_q << 2));
      end
      ResampleCopyWait, ResampleCopyWrite: begin
        memory_req_o   = (s_state_q == ResampleCopyWrite) || memory_valid_i;
        memory_write_o = memory_req_o;
        memory_addr_o  = 17'(s_output_addr + (s_element_q << 2));
        memory_data_o  = (s_state_q == ResampleCopyWrite) ? s_value0_q : memory_data_i;
      end
      ResampleSampleRequest: begin
        memory_req_o = (s_resample_source_index < s_input_base_q + {48'd0, s_count_q}) &&
            (s_tap_q < 32'd16);
        memory_addr_o = s_pair_issue_second_q ?
            17'(s_reference_addr[(s_aux_q[3:0] inside {4'd1, 4'd2}) ? 2 :
                ((s_aux_q[3:0] == 4'd14) ? 1 : 0)] +
                (((s_resample_phase * 16) + s_tap_q) << 2)) :
            17'(s_input_addr +
                (((s_resample_source_index - s_input_base_q + {32'd0, s_tap_q} - 64'd7) *
                  {32'd0, s_resample_channels} + {32'd0, s_channel_q}) << 2));
      end
      ResampleWrite: begin
        memory_req_o = 1'b1;
        memory_write_o = 1'b1;
        memory_addr_o = 17'(s_output_addr +
            (((s_produced_q * s_resample_channels) + s_channel_q) << 2));
        memory_data_o = sat32(rne72(s_accumulator_q, 6'd30));
      end
      ResampleStateWrite: begin
        memory_req_o   = 1'b1;
        memory_write_o = 1'b1;
        memory_addr_o  = 17'(s_parameter_addr + 32'd12 + (s_tap_q << 2));
        unique case (s_tap_q[1:0])
          2'd0:    memory_data_o = s_next_output_q[31:0];
          2'd1:    memory_data_o = s_next_output_q[63:32];
          2'd2:    memory_data_o = s_input_base_q[31:0];
          default: memory_data_o = s_input_base_q[63:32];
        endcase
      end
      PcmWrite, PcmDuplicateWrite: begin
        memory_req_o   = 1'b1;
        memory_write_o = 1'b1;
        memory_addr_o  = 17'((s_output_addr + s_produced_q) & 32'hffff_fffc);
        memory_data_o  = s_pcm_word;
        memory_strb_o  = s_pcm_strb;
      end
      default: begin
      end
    endcase
  end

  always_comb begin
    logic signed [63:0] s_scaled;
    logic signed [31:0] s_packed;
    s_scaled = rne64($signed(s_value0_q) * $signed(s_parameter_q[0]), 6'd30);
    if (s_aux_q[1:0] == 2'd0) begin
      if (s_scaled > 64'sd32767) s_packed = 32'sd32767;
      else if (s_scaled < -64'sd32768) s_packed = -32'sd32768;
      else s_packed = s_scaled[31:0];
      s_pcm_lane = 2'(s_output_addr + s_produced_q) & 2'd2;
      s_pcm_word = $unsigned(s_packed) << (s_pcm_lane * 8);
      s_pcm_strb = 4'b0011 << s_pcm_lane;
    end else begin
      if (s_scaled > 64'sd8388607) s_packed = 32'sd8388607;
      else if (s_scaled < -64'sd8388608) s_packed = -32'sd8388608;
      else s_packed = s_scaled[31:0];
      s_pcm_lane = 2'd0;
      s_pcm_word = s_packed;
      s_pcm_strb = 4'hf;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q                  <= Idle;
      s_opcode_q                 <= 4'd0;
      s_aux_q                    <= 8'd0;
      s_count_q                  <= 16'd0;
      s_dst_q                    <= 4'd0;
      s_input_offset_q           <= 32'd0;
      s_parameter_offset_q       <= 32'd0;
      s_output_offset_q          <= 32'd0;
      s_scratch_base_q           <= 17'd0;
      s_scratch_bytes_q          <= 17'd0;
      s_table_offset_q           <= 16'd0;
      s_table_bytes_q            <= 16'd0;
      s_parameter_q              <= '0;
      s_parameter_words_q        <= 4'd0;
      s_parameter_index_q        <= 4'd0;
      s_element_q                <= 32'd0;
      s_block_q                  <= 32'd0;
      s_row_q                    <= 32'd0;
      s_tap_q                    <= 32'd0;
      s_channel_q                <= 32'd0;
      s_read_issue_q             <= 32'd0;
      s_read_receive_q           <= 32'd0;
      s_pair_issue_second_q      <= 1'b0;
      s_pair_return_second_q     <= 1'b0;
      s_transform_preload_q      <= 1'b0;
      s_resample_profile_valid_q <= 1'b0;
      s_resample_profile_q       <= 4'd0;
      s_produced_q               <= 32'd0;
      s_cycles_q                 <= 32'd0;
      s_value0_q                 <= 32'd0;
      s_value1_q                 <= 32'd0;
      s_history_value_q          <= 32'd0;
      s_accumulator_q            <= 72'sd0;
      s_next_output_q            <= 64'd0;
      s_input_base_q             <= 64'd0;
      done_o                     <= 1'b0;
      error_o                    <= 1'b0;
      error_code_o               <= 6'd0;
      error_stage_o              <= 4'd0;
      error_reason_o             <= 8'd0;
      result_dst_o               <= 4'd0;
      result_count_o             <= 32'd0;
      cycles_o                   <= 32'd0;
      for (int index = 0; index < 32; index++) begin
        s_vector_q[index]      <= 32'sd0;
        s_coefficient_q[index] <= 32'sd0;
        s_history_q[index]     <= 32'sd0;
      end
    end else if (flush_i) begin
      s_state_q                  <= Idle;
      s_resample_profile_valid_q <= 1'b0;
      done_o                     <= 1'b0;
      error_o                    <= 1'b0;
      s_cycles_q                 <= 32'd0;
    end else begin
      done_o  <= 1'b0;
      error_o <= 1'b0;
      if (s_state_q != Idle) s_cycles_q <= s_cycles_q + 1'b1;
      if (memory_error_i && memory_req_o) begin
        s_state_q      <= Failed;
        error_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;
        error_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
        error_reason_o <= 8'd5;
      end else begin
        unique case (s_state_q)
          Idle: begin
            if (req_valid_i) begin
              s_opcode_q           <= opcode_i;
              s_aux_q              <= aux_i;
              s_count_q            <= count_i;
              s_dst_q              <= dst_i;
              s_input_offset_q     <= input_offset_i;
              s_parameter_offset_q <= parameter_offset_i;
              s_output_offset_q    <= output_offset_i;
              s_scratch_base_q     <= scratch_base_i;
              s_scratch_bytes_q    <= scratch_bytes_i;
              s_table_offset_q     <= table_offset_i;
              s_table_bytes_q      <= table_bytes_i;
              s_parameter_index_q  <= 4'd0;
              s_cycles_q           <= 32'd0;
              result_dst_o         <= dst_i;
              unique case (opcode_i)
                `APB4_APU__MC_KERNEL_LPC:        s_parameter_words_q <= 4'd3;
                `APB4_APU__MC_KERNEL_DCT32_POLY: s_parameter_words_q <= 4'd4;
                `APB4_APU__MC_KERNEL_RESAMPLE:   s_parameter_words_q <= 4'd8;
                `APB4_APU__MC_KERNEL_PCM_PACK:   s_parameter_words_q <= 4'd2;
                default:                         s_parameter_words_q <= 4'd1;
              endcase
              s_state_q <= ParameterRequest;
            end
          end
          ParameterRequest:    s_state_q <= ParameterWait;
          ParameterWait: begin
            if (memory_valid_i) begin
              s_parameter_q[s_parameter_index_q] <= memory_data_i;
              if (s_parameter_index_q + 1'b1 >= s_parameter_words_q) begin
                s_state_q <= Validate;
              end else begin
                s_parameter_index_q <= s_parameter_index_q + 1'b1;
                s_state_q           <= ParameterRequest;
              end
            end
          end
          Validate: begin
            if (s_semantic_err) begin
              error_code_o <= `APB4_APU__ERROR_CODE_RECONSTRUCTION;
              error_stage_o  <= (s_opcode_q inside {`APB4_APU__MC_KERNEL_RESAMPLE,
                                                     `APB4_APU__MC_KERNEL_PCM_PACK}) ?
                  `APB4_APU__ERROR_STAGE_RESAMPLER :
                  `APB4_APU__ERROR_STAGE_RECONSTRUCTION;
              error_reason_o <= 8'd9;
              s_state_q <= Failed;
            end else if (!s_validation_ok) begin
              error_code_o   <= `APB4_APU__ERROR_CODE_SEQUENCER;
              error_stage_o  <= `APB4_APU__ERROR_STAGE_LIFECYCLE;
              error_reason_o <= 8'd5;
              s_state_q      <= Failed;
            end else if (s_opcode_q inside {`APB4_APU__MC_KERNEL_IMDCT6,
                                            `APB4_APU__MC_KERNEL_IMDCT18,
                                            `APB4_APU__MC_KERNEL_DCT32_POLY}) begin
              s_transform_preload_q <= 1'b1;
              s_read_issue_q        <= 32'd0;
              s_read_receive_q      <= 32'd0;
              s_state_q             <= TransformInputRequest;
            end else if (s_opcode_q == `APB4_APU__MC_KERNEL_LPC) begin
              s_read_issue_q   <= 32'd0;
              s_read_receive_q <= 32'd0;
              s_state_q        <= CoefficientRequest;
            end else if ((s_opcode_q == `APB4_APU__MC_KERNEL_FIXED) &&
                         (s_predict_order != 32'd0)) begin
              s_read_issue_q   <= 32'd0;
              s_read_receive_q <= 32'd0;
              s_state_q        <= HistoryRequest;
            end else begin
              s_state_q <= Ready;
            end
          end
          Ready: begin
            if (req_valid_i) begin
              s_element_q            <= 32'd0;
              s_block_q              <= 32'd0;
              s_row_q                <= 32'd0;
              s_tap_q                <= 32'd0;
              s_channel_q            <= 32'd0;
              s_produced_q           <= 32'd0;
              s_read_issue_q         <= 32'd0;
              s_read_receive_q       <= 32'd0;
              s_pair_issue_second_q  <= 1'b0;
              s_pair_return_second_q <= 1'b0;
              s_transform_preload_q  <= 1'b0;
              s_cycles_q             <= 32'd1;
              unique case (s_opcode_q)
                `APB4_APU__MC_KERNEL_REQUANT: s_state_q <= RequantInputRequest;
                `APB4_APU__MC_KERNEL_STEREO, `APB4_APU__MC_KERNEL_DECORRELATE:
                s_state_q <= StereoFirstRequest;
                `APB4_APU__MC_KERNEL_IMDCT6,
                `APB4_APU__MC_KERNEL_IMDCT18,
                `APB4_APU__MC_KERNEL_DCT32_POLY:
                s_state_q <= TransformCoefficientRequest;
                `APB4_APU__MC_KERNEL_FIXED, `APB4_APU__MC_KERNEL_LPC:
                s_state_q <= PredictInputRequest;
                `APB4_APU__MC_KERNEL_RESAMPLE: begin
                  s_resample_profile_valid_q <= 1'b1;
                  s_resample_profile_q <= s_aux_q[3:0];
                  s_next_output_q <= {s_parameter_q[4], s_parameter_q[3]};
                  s_input_base_q <= {s_parameter_q[6], s_parameter_q[5]};
                  s_state_q <= (s_aux_q[3:0] == 4'd0) ? ResampleCopyRequest : ResampleSampleRequest;
                end
                default: s_state_q <= PcmInputRequest;
              endcase
            end
          end
          RequantInputRequest: s_state_q <= RequantInputWait;
          RequantInputWait:
          if (memory_valid_i) begin
            s_value0_q <= memory_data_i;
            s_state_q  <= RequantScaleWait;
          end
          RequantScaleRequest: s_state_q <= RequantScaleWait;
          RequantScaleWait:
          if (memory_valid_i) begin
            s_coefficient_q[0] <= memory_data_i;
            s_state_q          <= RequantWrite;
          end
          RequantWrite: begin
            if (s_element_q + 1'b1 >= s_count_q) begin
              s_produced_q <= {16'd0, s_count_q};
              s_state_q    <= Finish;
            end else begin
              s_element_q <= s_element_q + 1'b1;
              s_state_q   <= RequantInputRequest;
            end
          end
          StereoFirstRequest:  s_state_q <= StereoFirstWait;
          StereoFirstWait:
          if (memory_valid_i) begin
            s_value0_q <= memory_data_i;
            s_state_q  <= StereoSecondWait;
          end
          StereoSecondRequest: s_state_q <= StereoSecondWait;
          StereoSecondWait:
          if (memory_valid_i) begin
            s_value1_q <= memory_data_i;
            if ((s_opcode_q == `APB4_APU__MC_KERNEL_DECORRELATE) && s_stereo_live_overflow) begin
              error_code_o   <= `APB4_APU__ERROR_CODE_RECONSTRUCTION;
              error_stage_o  <= `APB4_APU__ERROR_STAGE_RECONSTRUCTION;
              error_reason_o <= 8'd9;
              s_state_q      <= Failed;
            end else begin
              s_state_q <= StereoWriteSecond;
            end
          end
          StereoWriteSecond: begin
            if (s_element_q + 1'b1 >= s_count_q) begin
              s_produced_q <= {15'd0, s_count_q, 1'b0};
              s_state_q    <= Finish;
            end else begin
              s_element_q <= s_element_q + 1'b1;
              s_state_q   <= StereoFirstRequest;
            end
          end
          HistoryRequest: begin
            if (memory_req_o) s_read_issue_q <= s_read_issue_q + 1'b1;
            if (memory_valid_i) begin
              s_history_q[s_read_receive_q[4:0]] <= memory_data_i;
              if (s_read_receive_q + 1'b1 >= s_predict_order) begin
                s_read_issue_q   <= 32'd0;
                s_read_receive_q <= 32'd0;
                s_state_q        <= Ready;
              end else begin
                s_read_receive_q <= s_read_receive_q + 1'b1;
              end
            end
          end
          CoefficientRequest: begin
            if (memory_req_o) s_read_issue_q <= s_read_issue_q + 1'b1;
            if (memory_valid_i) begin
              s_coefficient_q[s_read_receive_q[4:0]] <= memory_data_i;
              if (s_read_receive_q + 1'b1 >= s_predict_order) begin
                s_read_issue_q   <= 32'd0;
                s_read_receive_q <= 32'd0;
                s_state_q        <= HistoryRequest;
              end else begin
                s_read_receive_q <= s_read_receive_q + 1'b1;
              end
            end
          end
          PredictInputRequest: s_state_q <= PredictInputWait;
          PredictInputWait:
          if (memory_valid_i) begin
            s_value0_q <= memory_data_i;
            s_state_q  <= PredictWrite;
          end
          PredictWrite: begin
            if (s_reconstruction_overflow) begin
              error_code_o   <= `APB4_APU__ERROR_CODE_RECONSTRUCTION;
              error_stage_o  <= `APB4_APU__ERROR_STAGE_RECONSTRUCTION;
              error_reason_o <= 8'd9;
              s_state_q      <= Failed;
            end else begin
              for (int index = 31; index > 0; index--) begin
                if (index < s_predict_order) begin
                  s_history_q[index] <= s_history_q[index-1];
                end
              end
              if (s_predict_order != 32'd0) begin
                s_history_q[0] <= s_reconstruction_result0;
              end
              if (s_element_q + 1'b1 >= s_count_q) begin
                s_tap_q      <= 32'd0;
                s_state_q    <= (s_predict_order == 32'd0) ? Finish : HistoryWrite;
                s_produced_q <= {16'd0, s_count_q};
              end else begin
                s_element_q <= s_element_q + 1'b1;
                s_state_q   <= PredictInputRequest;
              end
            end
          end
          HistoryWrite: begin
            if (s_tap_q + 1'b1 >= s_predict_order) begin
              s_state_q <= Finish;
            end else begin
              s_tap_q <= s_tap_q + 1'b1;
            end
          end
          TransformInputRequest: begin
            if (memory_req_o) s_read_issue_q <= s_read_issue_q + 1'b1;
            if (memory_valid_i) begin
              s_vector_q[s_read_receive_q[4:0]] <= memory_data_i;
              if (s_read_receive_q + 1'b1 >= s_transform_order) begin
                s_read_issue_q   <= 32'd0;
                s_read_receive_q <= 32'd0;
                s_row_q          <= 32'd0;
                if (s_transform_preload_q) begin
                  s_transform_preload_q <= 1'b0;
                  s_state_q             <= Ready;
                end else begin
                  s_state_q <= TransformCoefficientRequest;
                end
              end else begin
                s_read_receive_q <= s_read_receive_q + 1'b1;
              end
            end
          end
          TransformCoefficientRequest: begin
            if (memory_req_o) s_read_issue_q <= s_read_issue_q + 1'b1;
            if (memory_valid_i) begin
              s_coefficient_q[s_read_receive_q[4:0]] <= memory_data_i;
              if (s_read_receive_q + 1'b1 >= s_transform_order) begin
                s_read_issue_q   <= 32'd0;
                s_read_receive_q <= 32'd0;
                if (s_transform_overflow) begin
                  error_code_o   <= `APB4_APU__ERROR_CODE_OVERFLOW;
                  error_stage_o  <= `APB4_APU__ERROR_STAGE_RECONSTRUCTION;
                  error_reason_o <= 8'd9;
                  s_state_q      <= Failed;
                end else if (s_row_q + 1'b1 >= ((s_opcode_q ==
                             `APB4_APU__MC_KERNEL_DCT32_POLY) ? 32'd32 :
                             (s_transform_order << 1))) begin
                  s_row_q <= 32'd0;
                  if (s_opcode_q == `APB4_APU__MC_KERNEL_DCT32_POLY) begin
                    s_tap_q                <= 32'd0;
                    s_accumulator_q        <= 72'sd0;
                    s_pair_issue_second_q  <= 1'b0;
                    s_pair_return_second_q <= 1'b0;
                    s_state_q              <= DctHistoryRequest;
                  end else if (s_block_q + 1'b1 >= s_count_q) begin
                    s_produced_q <= s_count_q * (s_transform_order << 1);
                    s_state_q    <= Finish;
                  end else begin
                    s_block_q <= s_block_q + 1'b1;
                    s_state_q <= TransformInputRequest;
                  end
                end else begin
                  s_row_q   <= s_row_q + 1'b1;
                  s_state_q <= TransformCoefficientRequest;
                end
              end else begin
                s_read_receive_q <= s_read_receive_q + 1'b1;
              end
            end
          end
          TransformWrite: begin
            if (s_transform_overflow) begin
              error_code_o  <= `APB4_APU__ERROR_CODE_OVERFLOW;
              error_stage_o <= `APB4_APU__ERROR_STAGE_RECONSTRUCTION;
              s_state_q     <= Failed;
            end else if (s_row_q + 1'b1 >= ((s_opcode_q ==
                         `APB4_APU__MC_KERNEL_DCT32_POLY) ? 32'd32 :
                         (s_transform_order << 1))) begin
              s_row_q <= 32'd0;
              if (s_opcode_q == `APB4_APU__MC_KERNEL_DCT32_POLY) begin
                s_tap_q                <= 32'd0;
                s_accumulator_q        <= 72'sd0;
                s_pair_issue_second_q  <= 1'b0;
                s_pair_return_second_q <= 1'b0;
                s_state_q              <= DctHistoryRequest;
              end else if (s_block_q + 1'b1 >= s_count_q) begin
                s_produced_q <= s_count_q * (s_transform_order << 1);
                s_state_q    <= Finish;
              end else begin
                s_block_q <= s_block_q + 1'b1;
                s_tap_q   <= 32'd0;
                s_state_q <= TransformInputRequest;
              end
            end else begin
              s_row_q   <= s_row_q + 1'b1;
              s_tap_q   <= 32'd0;
              s_state_q <= TransformCoefficientRequest;
            end
          end
          DctHistoryRequest: begin
            if (memory_req_o) begin
              s_pair_return_second_q <= s_pair_issue_second_q;
              s_pair_issue_second_q  <= !s_pair_issue_second_q;
              if (s_pair_issue_second_q) s_tap_q <= s_tap_q + 1'b1;
            end
            if (memory_valid_i) begin
              if (s_pair_return_second_q) begin
                s_accumulator_q <= s_accumulator_q + $signed(
                    s_history_value_q
                ) * $signed(
                    memory_data_i
                );
                if (s_tap_q == 32'd16) s_state_q <= DctOutputWrite;
              end else begin
                s_history_value_q <= memory_data_i;
              end
            end
          end
          DctOutputWrite: begin
            s_tap_q                <= 32'd0;
            s_accumulator_q        <= 72'sd0;
            s_pair_issue_second_q  <= 1'b0;
            s_pair_return_second_q <= 1'b0;
            if (s_row_q == 32'd31) begin
              s_state_q <= DctPhaseWrite;
            end else begin
              s_row_q   <= s_row_q + 1'b1;
              s_state_q <= DctHistoryRequest;
            end
          end
          DctPhaseWrite: begin
            s_parameter_q[3][3:0] <= s_parameter_q[3][3:0] + 1'b1;
            if (s_block_q + 1'b1 >= s_count_q) begin
              s_produced_q <= s_count_q * 32;
              s_state_q    <= Finish;
            end else begin
              s_block_q <= s_block_q + 1'b1;
              s_tap_q   <= 32'd0;
              s_state_q <= TransformInputRequest;
            end
          end
          ResampleCopyRequest: s_state_q <= ResampleCopyWait;
          ResampleCopyWait:
          if (memory_valid_i) begin
            if (s_element_q + 1'b1 >= s_count_q * s_resample_channels) begin
              s_next_output_q <= s_next_output_q + {48'd0, s_count_q};
              s_input_base_q  <= s_input_base_q + {48'd0, s_count_q};
              s_produced_q    <= {16'd0, s_count_q};
              s_tap_q         <= 32'd0;
              s_state_q       <= ResampleStateWrite;
            end else begin
              s_element_q <= s_element_q + 1'b1;
              s_state_q   <= ResampleCopyRequest;
            end
          end
          ResampleSampleRequest: begin
            if (s_resample_source_index >= s_input_base_q + {48'd0, s_count_q}) begin
              s_input_base_q <= s_input_base_q + {48'd0, s_count_q};
              s_tap_q        <= 32'd0;
              s_state_q      <= ResampleStateWrite;
            end else begin
              if (memory_req_o) begin
                s_pair_return_second_q <= s_pair_issue_second_q;
                s_pair_issue_second_q  <= !s_pair_issue_second_q;
                if (s_pair_issue_second_q) s_tap_q <= s_tap_q + 1'b1;
              end
              if (memory_valid_i) begin
                if (s_pair_return_second_q) begin
                  s_accumulator_q <= s_accumulator_q + $signed(s_value0_q) * $signed(memory_data_i);
                  if (s_tap_q == 32'd16) s_state_q <= ResampleWrite;
                end else begin
                  s_value0_q <= memory_data_i;
                end
              end
            end
          end
          ResampleWrite: begin
            s_tap_q                <= 32'd0;
            s_accumulator_q        <= 72'sd0;
            s_pair_issue_second_q  <= 1'b0;
            s_pair_return_second_q <= 1'b0;
            if (s_channel_q + 1'b1 >= s_resample_channels) begin
              s_channel_q     <= 32'd0;
              s_produced_q    <= s_produced_q + 1'b1;
              s_next_output_q <= s_next_output_q + {48'd0, s_ratio_m};
            end else begin
              s_channel_q <= s_channel_q + 1'b1;
            end
            s_state_q <= ResampleSampleRequest;
          end
          ResampleStateWrite: begin
            if (s_tap_q == 32'd3) begin
              s_state_q <= Finish;
            end else begin
              s_tap_q <= s_tap_q + 1'b1;
            end
          end
          PcmInputRequest:     s_state_q <= PcmInputWait;
          PcmInputWait:
          if (memory_valid_i) begin
            s_value0_q <= memory_data_i;
            s_state_q  <= PcmWrite;
          end
          PcmWrite: begin
            s_produced_q <= s_produced_q + ((s_aux_q[1:0] == 2'd0) ? 32'd2 : 32'd4);
            if (s_aux_q[2]) begin
              s_state_q <= PcmDuplicateWrite;
            end else if (s_element_q + 1'b1 >= s_count_q * s_parameter_q[1]) begin
              s_state_q <= Finish;
            end else begin
              s_element_q <= s_element_q + 1'b1;
              s_state_q   <= PcmInputRequest;
            end
          end
          PcmDuplicateWrite: begin
            s_produced_q <= s_produced_q + ((s_aux_q[1:0] == 2'd0) ? 32'd2 : 32'd4);
            if (s_element_q + 1'b1 >= s_count_q * s_parameter_q[1]) begin
              s_state_q <= Finish;
            end else begin
              s_element_q <= s_element_q + 1'b1;
              s_state_q   <= PcmInputRequest;
            end
          end
          Finish: begin
            done_o         <= 1'b1;
            result_dst_o   <= s_dst_q;
            result_count_o <= s_produced_q;
            unique case (s_opcode_q)
              `APB4_APU__MC_KERNEL_REQUANT: cycles_o <= 32'd8 + ({16'd0, s_count_q} << 2);
              `APB4_APU__MC_KERNEL_STEREO, `APB4_APU__MC_KERNEL_DECORRELATE:
              cycles_o <= 32'd8 + ({16'd0, s_count_q} << 2);
              `APB4_APU__MC_KERNEL_IMDCT6: cycles_o <= 32'd8 + (s_count_q * 32'd94);
              `APB4_APU__MC_KERNEL_IMDCT18: cycles_o <= 32'd8 + (s_count_q * 32'd706);
              `APB4_APU__MC_KERNEL_DCT32_POLY: cycles_o <= 32'd8 + (s_count_q * 32'd2304);
              `APB4_APU__MC_KERNEL_FIXED:
              cycles_o <= 32'd8 + (s_count_q * ({29'd0, s_aux_q[2:0]} + 32'd4));
              `APB4_APU__MC_KERNEL_LPC:
              cycles_o <= 32'd8 + (s_count_q * (({26'd0, s_aux_q[5:0]} << 1) + 32'd5));
              `APB4_APU__MC_KERNEL_RESAMPLE:
              cycles_o <= 32'd8 + ((s_count_q * s_resample_channels) << 1) +
                  ((s_aux_q[3:0] == 4'd0) ? 32'd0 :
                   (s_produced_q * s_resample_channels * 32'd36));
              default:
              cycles_o <= 32'd8 + (s_produced_q * 32'd5 / ((s_aux_q[1:0] == 2'd0) ? 32'd2 : 32'd4));
            endcase
            s_state_q <= Idle;
          end
          Failed: begin
            done_o    <= 1'b1;
            error_o   <= 1'b1;
            cycles_o  <= s_cycles_q;
            s_state_q <= Idle;
          end
          default:             s_state_q <= Idle;
        endcase
      end
    end
  end
endmodule
