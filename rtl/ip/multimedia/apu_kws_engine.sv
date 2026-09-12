// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_kws_engine (
    // verilog_format: off -- preserve the KWS lifecycle, DMA, model, and result columns
    input  logic                    clk_i,
    input  logic                    rst_n_i,
    input  logic                    soft_reset_i,
    input  logic                    resource_reset_i,
    input  logic                    counter_clear_i,
    input  logic                    xrun_clear_i,
    input  logic                    abort_i,
    input  logic                    quiesce_i,
    input  logic                    disable_i,
    input  logic                    flush_busy_i,
    input  logic                    enable_i,
    input  logic                    memory_window_i,
    input  logic                    clear_history_i,
    input  logic                    model_valid_i,
    input  logic                    model_lock_i,
    input  logic [31:0]             sequencer_timeout_i,
    input  logic                    memory_start_i,
    output logic                    memory_start_ready_o,
    input  logic [31:0]             memory_address_i,
    output logic                    memory_dma_request_valid_o,
    input  logic                    memory_dma_request_ready_i,
    output logic [31:0]             memory_dma_request_address_o,
    output logic [31:0]             memory_dma_request_bytes_o,
    input  logic [31:0]             memory_dma_data_i,
    input  logic [ 3:0]             memory_dma_keep_i,
    input  logic                    memory_dma_last_i,
    input  logic                    memory_dma_valid_i,
    output logic                    memory_dma_ready_o,
    input  logic                    memory_dma_done_i,
    input  logic                    memory_dma_error_i,
    input  logic [ 5:0]             memory_dma_error_code_i,
    input  logic [ 3:0]             memory_dma_error_stage_i,
    input  logic [ 1:0]             memory_dma_error_resp_i,
    input  logic [31:0]             memory_dma_error_address_i,
    output logic                    memory_done_o,
    output logic                    memory_error_o,
    output logic [ 5:0]             memory_error_code_o,
    output logic [ 3:0]             memory_error_stage_o,
    output logic [ 1:0]             memory_error_resp_o,
    output logic [31:0]             memory_error_address_o,
    output logic [31:0]             memory_error_detail_o,
    output logic [31:0]             memory_input_used_o,
    input  logic [15:0]             kws_config_i,
    input  logic [31:0]             input_config_i,
    output logic [15:0][14:0]       model_addr_o,
    input  logic [15:0][ 7:0]       model_data_i,
    output logic                    scratch_clear_o,
    output logic [19:0][15:0]       scratch_read_addr_o,
    input  logic [19:0][31:0]       scratch_read_data_i,
    output logic [ 5:0]             scratch_write_valid_o,
    output logic [ 5:0][15:0]       scratch_write_addr_o,
    output logic [ 5:0][31:0]       scratch_write_data_o,
    output logic [ 5:0][ 3:0]       scratch_write_strb_o,
    input  logic                    scratch_access_err_i,
    axi4_stream_if.sink             stream_i,
    output logic                    rx_ready_o,
    output logic [31:0]             status_o,
    output logic [31:0]             result_o,
    output logic [31:0]             timestamp_lo_o,
    output logic [31:0]             timestamp_hi_o,
    output logic [31:0]             frame_count_o,
    output logic [31:0]             inference_count_o,
    output logic [31:0]             hit_count_o,
    output logic [31:0]             overrun_count_o,
    output logic [31:0]             model_status_o,
    output logic [31:0]             model_actual_crc_o,
    output logic [10:0]             irq_set_o,
    output logic                    fault_valid_o,
    output logic [5:0]              fault_code_o,
    output logic [3:0]              fault_stage_o,
    output logic [1:0]              fault_resp_o,
    output logic [7:0]              fault_index_o,
    output logic [31:0]             fault_addr_o,
    output logic [31:0]             fault_detail_o,
    output logic                    model_valid_o,
    output logic                    model_lock_o,
    output logic                    busy_o,
    output logic                    idle_o
    // verilog_format: on
);
  `include "apu_kws_rom.svh"

  localparam logic [15:0] ScratchFftRealBase = `RETROSOC_APU_KWS__SCRATCH_FFT_REAL_BASE;
  localparam logic [15:0] ScratchFftImagBase = `RETROSOC_APU_KWS__SCRATCH_FFT_IMAG_BASE;
  localparam logic [15:0] ScratchSoftmaxBase = `RETROSOC_APU_KWS__SCRATCH_SOFTMAX_BASE;

  typedef enum logic [3:0] {
    FrontIdle,
    FrontFir,
    FrontFftLoad,
    FrontFftRun,
    FrontMagnitude,
    FrontMel,
    FrontPeak,
    FrontLog,
    FrontDct
  } front_state_e;

  typedef enum logic [3:0] {
    InferIdle,
    InferBias,
    InferMac,
    InferQuant,
    InferPool,
    InferSoftmaxMax,
    InferSoftmaxSum,
    InferSoftmaxScale,
    InferComplete
  } infer_state_e;

  front_state_e       s_front_state_q;
  infer_state_e       s_infer_state_q;

  logic         [9:0] s_ingress_write_q;
  logic [5:0] s_fir_write_q, s_fir_tap_q;
  logic        [ 2:0] s_fir_phase_q;
  logic signed [15:0] s_fir_sample_q;
  logic signed [63:0] s_fir_acc_q;
  logic [31:0] s_epoch_samples_q, s_next_frame_q, s_next_window_q;
  logic [ 7:0] s_block_samples_q;
  logic [15:0] s_block_peak_q;
  logic [ 6:0] s_peak_write_q;
  logic [5:0] s_mel_write_q, s_mel_count_q;
  logic s_frame_pending_q, s_window_pending_q;
  logic [9:0] s_frame_start_q;
  logic [5:0] s_snapshot_start_q;
  logic [9:0] s_front_index_q;
  logic [9:0] s_fft_len_q;
  logic [8:0] s_fft_group_q, s_fft_half_q;
  logic [ 7:0] s_fft_j_q;
  logic [ 7:0] s_mel_band_q;
  logic [ 8:0] s_mel_bin_q;
  logic [63:0] s_mel_acc_q;
  logic [ 6:0] s_peak_scan_q;
  logic [15:0] s_window_peak_q;
  logic [5:0] s_mfcc_row_q, s_mfcc_band_q;
  logic        [ 3:0] s_mfcc_coefficient_q;
  logic signed [63:0] s_dct_acc_q;

  logic        [ 3:0] s_operator_q;
  logic        [13:0] s_output_q;
  logic        [ 7:0] s_term_q;
  logic signed [63:0] s_mac_q;
  logic        [ 3:0] s_softmax_index_q;
  logic signed [ 7:0] s_softmax_max_q;
  logic        [31:0] s_softmax_sum_q;
  logic signed [31:0] s_softmax_scale_q;
  logic signed [ 5:0] s_softmax_bits_q;
  logic [7:0] s_debounce_run_q, s_last_class_q;
  logic s_last_match_q, s_stable_hit_q;

  logic [31:0] s_frame_count_q, s_inference_count_q, s_hit_count_q, s_overrun_count_q;
  logic [31:0] s_result_q, s_timestamp_lo_q, s_timestamp_hi_q, s_timestamp_q;
  logic s_result_valid_q, s_overrun_sticky_q, s_stop_latched_q, s_flush_seen_q;
  logic s_hit_irq_q, s_overrun_irq_q;

  logic s_mem_req_q, s_mem_dma_active_q, s_mem_job_q, s_mem_dma_done_q;
  logic s_mem_word_valid_q, s_mem_high_q, s_mem_done_q, s_mem_err_q;
  logic [31:0] s_mem_word_q, s_mem_received_q;
  logic [5:0] s_mem_err_code_q;
  logic [3:0] s_mem_err_stage_q;
  logic [1:0] s_mem_err_resp_q;
  logic [31:0] s_mem_err_addr_q, s_mem_err_detail_q;

  logic       s_fault_q;
  logic [5:0] s_fault_code_q;
  logic [3:0] s_fault_stage_q;
  logic [31:0] s_fault_addr_q, s_fault_detail_q;
  logic [31:0] s_front_watchdog_q, s_infer_watchdog_q;
  logic s_front_progress, s_infer_progress;

  logic s_config_valid, s_continuous_active, s_listening, s_capture_available;
  logic s_stream_accept, s_stream_legal, s_window_deadline, s_mel_overwrite;
  logic               s_commit_valid;
  logic signed [15:0] s_commit_sample;
  logic signed [24:0] s_stereo_sum;
  logic signed [23:0] s_s24_first_q;
  logic               s_s24_pending_q;
  logic signed [63:0] s_fir_term, s_fir_total;
  logic signed [15:0] s_fir_output;
  logic        [ 2:0] s_decimation;
  logic        [31:0] s_next_samples;
  logic [15:0] s_pos_sample, s_next_peak;
  logic [9:0] s_next_write;

  logic [8:0] s_fft_left_index, s_fft_right_index;
  logic        [ 7:0] s_twiddle_index;
  logic signed [63:0] s_windowed;
  logic signed [63:0] s_fft_product_real, s_fft_product_imag;
  logic signed [31:0] s_fft_twiddled_real, s_fft_twiddled_imag;
  logic signed [31:0] s_fft_left_real, s_fft_left_imag;
  logic signed [63:0] s_fft_sum_real, s_fft_sum_imag, s_fft_diff_real, s_fft_diff_imag;
  logic [63:0] s_magnitude_square;
  logic [63:0] s_mel_product, s_mel_total;
  logic signed [63:0] s_dct_product, s_dct_total;
  logic        [ 6:0] s_log_row_sum;
  logic        [ 5:0] s_log_row_index;
  logic signed [63:0] s_dct_coefficient;

  logic signed [63:0] s_lane_sum, s_pool_sum;
  logic [7:0] s_term_count;
  logic signed [31:0] s_bias_word, s_multiplier_word, s_shift_word;
  logic signed [63:0] s_mac_total, s_requant_shifted;
  logic signed [ 7:0] s_output_value;
  logic               s_requant_overflow;
  logic        [13:0] s_output_count;
  logic        [ 5:0] s_output_channel;
  logic        [ 2:0] s_output_width_index;
  logic        [ 4:0] s_output_height_index;
  logic        [ 7:0] s_output_spatial_index;
  logic [14:0] s_weight_base, s_bias_base, s_multiplier_base, s_shift_base;
  logic signed [8:0] s_input_zero, s_output_zero;
  logic        [ 8:0] s_lane_term        [0:15];
  logic        [12:0] s_lane_input_index [0:15];
  logic        [14:0] s_lane_weight_index[0:15];
  logic signed [ 6:0] s_lane_input_h     [0:15];
  logic signed [ 4:0] s_lane_input_w     [0:15];
  logic signed [15:0] s_lane_input_value [0:15];
  logic        [15:0] s_lane_active;
  logic               s_relu;
  logic s_en_q, s_quiesce_seen_q;
  logic signed [8:0] s_softmax_sum_diff, s_softmax_scale_diff;
  logic [5:0] s_softmax_headroom;
  logic signed [31:0] s_softmax_shifted_sum, s_softmax_exp_value, s_softmax_prob;
  logic [7:0] s_best_class, s_best_score;
  logic [8:0] s_next_debounce_run;
  logic s_match, s_same_match, s_hit_event, s_stable_hit;
  logic signed [15:0] s_fir_history_data, s_ingress_data;
  logic [15:0] s_peak_data;
  logic [31:0] s_mel_data, s_magnitude_data;
  logic signed [31:0] s_fft_left_real_data, s_fft_left_imag_data;
  logic signed [31:0] s_fft_right_real_data, s_fft_right_imag_data;
  logic signed [31:0] s_log_data;
  logic signed [7:0] s_logit_data, s_softmax_data[0:11];
  logic s_fft_overflow;

  function automatic logic signed [63:0] rne_shift(input logic signed [63:0] value_i,
                                                   input logic [5:0] shift_i);
    logic negative;
    logic [63:0] magnitude, quotient, remainder, mask, half;
    begin
      if (shift_i == 0) begin
        return value_i;
      end
      negative  = value_i < 0;
      magnitude = negative ? -value_i : value_i;
      mask      = (64'd1 << shift_i) - 1'b1;
      half      = 64'd1 << (shift_i - 1'b1);
      quotient  = magnitude >> shift_i;
      remainder = magnitude & mask;
      if ((remainder > half) || ((remainder == half) && quotient[0])) quotient = quotient + 1'b1;
      return negative ? -$signed(quotient) : $signed(quotient);
    end
  endfunction

  function automatic logic signed [31:0] rounding_divide_pot(input logic signed [31:0] value_i,
                                                             input logic [5:0] exponent_i);
    logic [31:0] mask, remainder, threshold;
    logic signed [31:0] quotient;
    begin
      if (exponent_i == 0) return value_i;
      mask      = (32'd1 << exponent_i) - 1'b1;
      remainder = value_i & mask;
      threshold = (mask >> 1) + {31'd0, (value_i < 0)};
      quotient  = $signed(value_i) >>> exponent_i;
      return quotient + $signed({31'd0, (remainder > threshold)});
    end
  endfunction

  function automatic logic signed [31:0] saturating_high_mul(input logic signed [31:0] left_i,
                                                             input logic signed [31:0] right_i);
    logic signed [63:0] product, adjusted;
    begin
      if ((left_i == -32'sh8000_0000) && (right_i == -32'sh8000_0000)) begin
        return 32'sh7fff_ffff;
      end
      product  = left_i * right_i;
      adjusted = product + ((product >= 0) ? 64'sd1073741824 : -64'sd1073741823);
      return 32'(adjusted / 64'sd2147483648);
    end
  endfunction

  function automatic logic signed [31:0] multiply_quantized(input logic signed [31:0] value_i,
                                                            input logic signed [31:0] multiplier_i,
                                                            input logic signed [31:0] shift_i);
    logic signed [63:0] shifted;
    logic signed [31:0] high;
    logic [5:0] left_shift, right_shift;
    begin
      left_shift  = (shift_i > 0) ? shift_i[5:0] : 6'd0;
      right_shift = (shift_i < 0) ? (-shift_i[5:0]) : 6'd0;
      shifted     = $signed({{32{value_i[31]}}, value_i}) <<< left_shift;
      if ((shifted > 64'sh0000_0000_7fff_ffff) || (shifted < -64'sh0000_0000_8000_0000)) begin
        high = (shifted < 0) ? -32'sh8000_0000 : 32'sh7fff_ffff;
      end else begin
        high = saturating_high_mul(shifted[31:0], multiplier_i);
      end
      return rounding_divide_pot(high, right_shift);
    end
  endfunction

  function automatic logic signed [31:0] rounding_half_sum(input logic signed [31:0] left_i,
                                                           input logic signed [31:0] right_i);
    logic signed [32:0] sum;
    begin
      sum = left_i + right_i;
      return 32'((sum + ((sum >= 0) ? 33'sd1 : -33'sd1)) / 33'sd2);
    end
  endfunction

  function automatic logic signed [31:0] reciprocal_q31(input logic signed [31:0] value_i);
    logic signed [31:0] half_denominator, estimate, product, correction;
    begin
      half_denominator = rounding_half_sum(value_i, 32'sh7fff_ffff);
      estimate         = 32'sd1515870810 + saturating_high_mul(half_denominator, -32'sd1010580540);
      for (int iteration = 0; iteration < 3; iteration++) begin
        product    = saturating_high_mul(half_denominator, estimate);
        correction = 32'sh2000_0000 - product;
        estimate   = estimate + saturating_high_mul(estimate, correction);
      end
      if (estimate > 32'sh3fff_ffff) return 32'sh7fff_ffff;
      if (estimate < -32'sh4000_0000) return -32'sh8000_0000;
      return estimate <<< 1;
    end
  endfunction

  function automatic logic [5:0] count_leading_zero(input logic [31:0] value_i);
    logic found;
    begin
      count_leading_zero = 6'd32;
      found              = 1'b0;
      for (int bit_index = 31; bit_index >= 0; bit_index--) begin
        if (!found && value_i[bit_index]) begin
          count_leading_zero = 6'(31 - bit_index);
          found              = 1'b1;
        end
      end
    end
  endfunction

  function automatic logic [31:0] nearest_isqrt(input logic [63:0] value_i);
    logic [63:0] root, candidate, floor_square, ceil_square, lower, upper;
    begin
      root = 64'd0;
      for (int bit_index = 31; bit_index >= 0; bit_index--) begin
        candidate = root | (64'd1 << bit_index);
        if ((candidate * candidate) <= value_i) root = candidate;
      end
      floor_square = root * root;
      candidate    = root + 1'b1;
      ceil_square  = candidate * candidate;
      lower        = value_i - floor_square;
      upper        = ceil_square - value_i;
      if ((upper < lower) || ((upper == lower) && root[0])) root = candidate;
      return root[31:0];
    end
  endfunction

  function automatic logic [8:0] bit_reverse9(input logic [8:0] value_i);
    for (int bit_index = 0; bit_index < 9; bit_index++) begin
      bit_reverse9[bit_index] = value_i[8-bit_index];
    end
  endfunction

  function automatic logic signed [15:0] saturate_s16(input logic signed [63:0] value_i);
    if (value_i > 64'sd32767) return 16'sh7fff;
    if (value_i < -64'sd32768) return -16'sh8000;
    return value_i[15:0];
  endfunction

  function automatic logic signed [7:0] scratch_s8(input logic [31:0] data_i,
                                                   input logic [1:0] addr_i);
    return $signed(data_i[8*addr_i+:8]);
  endfunction

  function automatic logic signed [15:0] scratch_s16(input logic [31:0] data_i,
                                                     input logic addr_half_i);
    return addr_half_i ? $signed(data_i[31:16]) : $signed(data_i[15:0]);
  endfunction

  function automatic logic [9:0] ingress_add(input logic [9:0] base_i, input logic [9:0] add_i);
    logic [10:0] sum;
    begin
      sum = base_i + add_i;
      return 10'((sum >= 11'd768) ? sum - 11'd768 : sum);
    end
  endfunction

  function automatic logic [5:0] fir_history_index(input logic [5:0] write_i,
                                                   input logic [5:0] tap_i);
    logic [6:0] index;
    begin
      index = {1'b0, write_i} + 7'd62 - {1'b0, tap_i};
      return 6'((index >= 7'd63) ? index - 7'd63 : index);
    end
  endfunction

  function automatic logic [7:0] fft_twiddle_index(input logic [9:0] length_i,
                                                   input logic [7:0] index_i);
    unique case (length_i)
      10'd2:   fft_twiddle_index = 8'd0;
      10'd4:   fft_twiddle_index = {index_i[0], 7'd0};
      10'd8:   fft_twiddle_index = {index_i[1:0], 6'd0};
      10'd16:  fft_twiddle_index = {index_i[2:0], 5'd0};
      10'd32:  fft_twiddle_index = {index_i[3:0], 4'd0};
      10'd64:  fft_twiddle_index = {index_i[4:0], 3'd0};
      10'd128: fft_twiddle_index = {index_i[5:0], 2'd0};
      10'd256: fft_twiddle_index = {index_i[6:0], 1'd0};
      default: fft_twiddle_index = index_i;
    endcase
  endfunction

  function automatic logic signed [31:0] rne_shift_s32(input logic signed [63:0] value_i,
                                                       input logic [5:0] shift_i);
    begin
      return 32'(rne_shift(value_i, shift_i));
    end
  endfunction

  function automatic logic signed [63:0] lane_product(input logic signed [15:0] input_i,
                                                      input logic signed [8:0] zero_i,
                                                      input logic signed [7:0] weight_i);
    logic signed [16:0] centered;
    logic signed [24:0] centered_extended, weight_extended, product;
    begin
      centered          = 17'(input_i) - 17'(zero_i);
      centered_extended = 25'(centered);
      weight_extended   = 25'(weight_i);
      product           = centered_extended * weight_extended;
      return 64'(product);
    end
  endfunction

  function automatic logic signed [31:0] log_mel_q24(input logic [31:0] mel_i,
                                                     input logic [15:0] peak_i);
    logic [95:0] numerator, denominator, normalized_denominator;
    logic [95:0] scaled, remainder;
    logic signed [ 7:0] exponent;
    logic        [10:0] index;
    logic        [16:0] fraction;
    logic [95:0] fraction_scaled, fraction_quotient, fraction_remainder;
    logic signed [63:0] interpolation;
    begin
      numerator   = 96'd1000000 * mel_i + 96'd16 * peak_i;
      denominator = 96'd16000000 * peak_i;
      exponent    = 0;
      if (numerator >= denominator) begin
        normalized_denominator = denominator;
        for (int iteration = 0; iteration < 95; iteration++) begin
          if (numerator >= (normalized_denominator << 1)) begin
            normalized_denominator = normalized_denominator << 1;
            exponent               = exponent + 1'b1;
          end
        end
      end else begin
        normalized_denominator = denominator;
        for (int iteration = 0; iteration < 95; iteration++) begin
          if (numerator < normalized_denominator) begin
            numerator = numerator << 1;
            exponent  = exponent - 1'b1;
          end
        end
      end
      scaled             = (numerator - normalized_denominator) * 96'd1024;
      index              = 11'(scaled / normalized_denominator);
      remainder          = scaled - index * normalized_denominator;
      fraction_scaled    = remainder * 96'd65536;
      fraction_quotient  = fraction_scaled / normalized_denominator;
      fraction_remainder = fraction_scaled - fraction_quotient * normalized_denominator;
      if ((fraction_remainder * 2 > normalized_denominator) ||
          ((fraction_remainder * 2 == normalized_denominator) && fraction_quotient[0])) begin
        fraction_quotient = fraction_quotient + 1'b1;
      end
      fraction = fraction_quotient[16:0];
      interpolation = 64'($signed(apu_kws_log_q24(index + 11'd1))) -
          64'($signed(apu_kws_log_q24(index)));
      interpolation = rne_shift(interpolation * $signed({1'b0, fraction}), 16);
      return 32'(64'($signed(
          exponent
      )) * 64'(ApuKwsLn2Q24) + 64'($signed(
          apu_kws_log_q24(index)
      )) + interpolation);
    end
  endfunction

  function automatic logic [31:0] rne_uq32(input logic [63:0] value_i);
    logic [31:0] quotient, remainder;
    begin
      quotient  = value_i[63:32];
      remainder = value_i[31:0];
      if ((remainder > 32'h8000_0000) || ((remainder == 32'h8000_0000) && quotient[0])) begin
        quotient = quotient + 1'b1;
      end
      return quotient;
    end
  endfunction

  function automatic logic [14:0] operator_weight_base(input logic [3:0] operator_i);
    case (operator_i)
      4'd0:    operator_weight_base = 15'h0500;
      4'd1:    operator_weight_base = 15'h1200;
      4'd2:    operator_weight_base = 15'h1740;
      4'd3:    operator_weight_base = 15'h2a40;
      4'd4:    operator_weight_base = 15'h2f80;
      4'd5:    operator_weight_base = 15'h4280;
      4'd6:    operator_weight_base = 15'h47c0;
      4'd7:    operator_weight_base = 15'h5ac0;
      4'd8:    operator_weight_base = 15'h6000;
      4'd10:   operator_weight_base = 15'h7300;
      default: operator_weight_base = 15'd0;
    endcase
  endfunction

  function automatic logic [14:0] operator_bias_base(input logic [3:0] operator_i);
    case (operator_i)
      4'd0:    operator_bias_base = 15'h0f00;
      4'd1:    operator_bias_base = 15'h1440;
      4'd2:    operator_bias_base = 15'h2740;
      4'd3:    operator_bias_base = 15'h2c80;
      4'd4:    operator_bias_base = 15'h3f80;
      4'd5:    operator_bias_base = 15'h44c0;
      4'd6:    operator_bias_base = 15'h57c0;
      4'd7:    operator_bias_base = 15'h5d00;
      4'd8:    operator_bias_base = 15'h7000;
      4'd10:   operator_bias_base = 15'h7600;
      default: operator_bias_base = 15'd0;
    endcase
  endfunction

  function automatic logic [14:0] operator_multiplier_base(input logic [3:0] operator_i);
    case (operator_i)
      4'd0:    operator_multiplier_base = 15'h1000;
      4'd1:    operator_multiplier_base = 15'h1540;
      4'd2:    operator_multiplier_base = 15'h2840;
      4'd3:    operator_multiplier_base = 15'h2d80;
      4'd4:    operator_multiplier_base = 15'h4080;
      4'd5:    operator_multiplier_base = 15'h45c0;
      4'd6:    operator_multiplier_base = 15'h58c0;
      4'd7:    operator_multiplier_base = 15'h5e00;
      4'd8:    operator_multiplier_base = 15'h7100;
      4'd10:   operator_multiplier_base = 15'h7630;
      default: operator_multiplier_base = 15'd0;
    endcase
  endfunction

  function automatic logic [14:0] operator_shift_base(input logic [3:0] operator_i);
    case (operator_i)
      4'd0:    operator_shift_base = 15'h1100;
      4'd1:    operator_shift_base = 15'h1640;
      4'd2:    operator_shift_base = 15'h2940;
      4'd3:    operator_shift_base = 15'h2e80;
      4'd4:    operator_shift_base = 15'h4180;
      4'd5:    operator_shift_base = 15'h46c0;
      4'd6:    operator_shift_base = 15'h59c0;
      4'd7:    operator_shift_base = 15'h5f00;
      4'd8:    operator_shift_base = 15'h7200;
      4'd10:   operator_shift_base = 15'h7660;
      default: operator_shift_base = 15'd0;
    endcase
  endfunction

  assign s_config_valid = (input_config_i[31:26] == 6'd0) && !input_config_i[19] &&
      (input_config_i[18:17] == 2'd2) &&
      ((input_config_i[16:0] == 17'd16000) || (input_config_i[16:0] == 17'd48000) ||
       (input_config_i[16:0] == 17'd96000)) &&
      ((input_config_i[25:20] == 6'd16) || (input_config_i[25:20] == 6'd24));
  assign s_decimation = (input_config_i[16:0] == 17'd96000) ? 3'd6 :
      ((input_config_i[16:0] == 17'd48000) ? 3'd3 : 3'd1);
  assign s_continuous_active = enable_i && !disable_i && !memory_window_i && !quiesce_i &&
      !s_stop_latched_q && model_valid_i && model_lock_i && s_config_valid;
  assign s_listening = s_continuous_active && s_en_q && !flush_busy_i;
  assign s_capture_available = (s_front_state_q == FrontIdle) && !s_frame_pending_q &&
      !s_window_pending_q && (s_fir_tap_q == 6'd0);
  assign rx_ready_o = s_listening && s_capture_available;
  assign s_stream_accept = stream_i.tvalid && rx_ready_o;
  assign s_stream_legal = (stream_i.tkeep == 4'hf) && (stream_i.tstrb == 4'hf) && !stream_i.tlast;
  assign s_window_deadline = s_commit_valid &&
      ((s_epoch_samples_q + 1'b1) == s_next_window_q) &&
      (s_window_pending_q || (s_infer_state_q != InferIdle));
  assign s_mel_overwrite = (s_front_state_q == FrontMel) &&
      (s_mel_bin_q == 9'd256) && (s_mel_band_q == 8'd39) &&
      s_window_pending_q && (s_mel_write_q == s_snapshot_start_q);

  always_comb begin
    unique case (s_front_state_q)
      FrontFir:       s_front_progress = s_fir_tap_q == 6'd62;
      FrontFftRun:    s_front_progress = 1'b1;
      FrontMagnitude: s_front_progress = s_front_index_q == 10'd256;
      FrontMel:       s_front_progress = s_mel_bin_q == 9'd256;
      FrontPeak:      s_front_progress = s_peak_scan_q == 7'd99;
      FrontLog:       s_front_progress = 1'b1;
      FrontDct:       s_front_progress = s_mfcc_band_q == 6'd39;
      default:        s_front_progress = 1'b0;
    endcase
    unique case (s_infer_state_q)
      InferMac, InferQuant, InferPool, InferSoftmaxMax, InferSoftmaxSum, InferComplete:
      s_infer_progress = 1'b1;
      InferSoftmaxScale: s_infer_progress = s_softmax_index_q != 4'd0;
      default: s_infer_progress = 1'b0;
    endcase
  end

  always_comb begin
    s_stereo_sum = 25'sd0;
    if (input_config_i[25:20] == 6'd16) begin
      s_stereo_sum = 25'($signed(stream_i.tdata[15:0])) + 25'($signed(stream_i.tdata[31:16]));
    end else begin
      s_stereo_sum = 25'($signed(s_s24_first_q)) + 25'($signed(stream_i.tdata[23:0]));
    end
  end

  assign s_fir_history_data = scratch_s16(scratch_read_data_i[0], scratch_read_addr_o[0][1]);
  assign s_ingress_data = scratch_s16(scratch_read_data_i[0], scratch_read_addr_o[0][1]);
  assign s_peak_data = scratch_read_addr_o[0][1] ?
      scratch_read_data_i[0][31:16] : scratch_read_data_i[0][15:0];
  assign s_mel_data = scratch_read_data_i[0];
  assign s_magnitude_data = scratch_read_data_i[0];
  assign s_log_data = $signed(scratch_read_data_i[0]);
  assign s_fft_left_real_data = $signed(scratch_read_data_i[0]);
  assign s_fft_left_imag_data = $signed(scratch_read_data_i[1]);
  assign s_fft_right_real_data = $signed(scratch_read_data_i[2]);
  assign s_fft_right_imag_data = $signed(scratch_read_data_i[3]);

  assign s_fir_term = $signed(
      (s_fir_tap_q == 0) ? s_fir_sample_q : s_fir_history_data
  ) * $signed(
      (s_decimation == 3'd3) ? apu_kws_fir3_q30(s_fir_tap_q) : apu_kws_fir6_q30(s_fir_tap_q)
  );
  assign s_fir_total = s_fir_acc_q + s_fir_term;
  assign s_fir_output = saturate_s16(rne_shift(s_fir_total, 30));
  assign s_next_samples = s_epoch_samples_q + 32'd1;
  assign s_pos_sample = (s_commit_sample > 0) ? 16'($unsigned(s_commit_sample)) : 16'd1;
  assign s_next_peak = (s_pos_sample > s_block_peak_q) ? s_pos_sample : s_block_peak_q;
  assign s_next_write = (s_ingress_write_q == 10'd767) ? 10'd0 : s_ingress_write_q + 10'd1;

  always_comb begin
    s_commit_valid  = 1'b0;
    s_commit_sample = 16'sd0;
    if ((s_front_state_q == FrontFir) && (s_fir_tap_q == 6'd62) &&
        (s_fir_phase_q == (s_decimation - 1'b1))) begin
      s_commit_valid  = 1'b1;
      s_commit_sample = s_fir_output;
    end else if (s_capture_available && s_mem_word_valid_q) begin
      s_commit_valid  = 1'b1;
      s_commit_sample = s_mem_high_q ? $signed(s_mem_word_q[31:16]) : $signed(s_mem_word_q[15:0]);
    end else if (s_stream_accept && s_stream_legal &&
                 (input_config_i[25:20] == 6'd16) &&
                 (s_decimation == 3'd1)) begin
      s_commit_valid  = 1'b1;
      s_commit_sample = s_stereo_sum[16:1];
    end else if (s_stream_accept && s_stream_legal &&
                 (input_config_i[25:20] == 6'd24) &&
                 s_s24_pending_q && (s_decimation == 3'd1)) begin
      s_commit_valid  = 1'b1;
      s_commit_sample = saturate_s16(64'($signed(s_stereo_sum)) >>> 9);
    end
  end

  assign s_fft_left_index = s_fft_group_q + {1'b0, s_fft_j_q};
  assign s_fft_right_index = s_fft_left_index + s_fft_half_q;
  assign s_twiddle_index = fft_twiddle_index(s_fft_len_q, s_fft_j_q);
  assign s_windowed = (s_front_index_q < 10'd480) ? 64'($signed(
      s_ingress_data
  )) * 64'($signed(
      apu_kws_hann_q30(s_front_index_q[8:0])
  )) : 64'sd0;
  assign s_fft_product_real = $signed(
      s_fft_right_real_data
  ) * $signed(
      apu_kws_twiddle_real_q30(s_twiddle_index)
  ) - $signed(
      s_fft_right_imag_data
  ) * $signed(
      apu_kws_twiddle_imag_q30(s_twiddle_index)
  );
  assign s_fft_product_imag = $signed(
      s_fft_right_real_data
  ) * $signed(
      apu_kws_twiddle_imag_q30(s_twiddle_index)
  ) + $signed(
      s_fft_right_imag_data
  ) * $signed(
      apu_kws_twiddle_real_q30(s_twiddle_index)
  );
  assign s_fft_twiddled_real = rne_shift_s32(s_fft_product_real, 6'd30);
  assign s_fft_twiddled_imag = rne_shift_s32(s_fft_product_imag, 6'd30);
  assign s_fft_left_real = s_fft_left_real_data;
  assign s_fft_left_imag = s_fft_left_imag_data;
  assign s_fft_sum_real = rne_shift(
      64'($signed(s_fft_left_real)) + 64'($signed(s_fft_twiddled_real)), 6'd1
  );
  assign s_fft_sum_imag = rne_shift(
      64'($signed(s_fft_left_imag)) + 64'($signed(s_fft_twiddled_imag)), 6'd1
  );
  assign s_fft_diff_real = rne_shift(
      64'($signed(s_fft_left_real)) - 64'($signed(s_fft_twiddled_real)), 6'd1
  );
  assign s_fft_diff_imag = rne_shift(
      64'($signed(s_fft_left_imag)) - 64'($signed(s_fft_twiddled_imag)), 6'd1
  );
  assign s_magnitude_square = $unsigned(
      64'($signed(s_fft_left_real_data)) * 64'($signed(s_fft_left_real_data))
  ) + $unsigned(
      64'($signed(s_fft_left_imag_data)) * 64'($signed(s_fft_left_imag_data))
  );
  assign s_mel_product = s_magnitude_data * apu_kws_mel_q30(
      14'(s_mel_band_q) * 14'd257 + 14'(s_mel_bin_q)
  );
  assign s_mel_total = s_mel_acc_q + s_mel_product;
  assign s_dct_product = $signed(
      s_log_data
  ) * $signed(
      apu_kws_dct_q30(9'(s_mfcc_coefficient_q) * 9'd40 + 9'(s_mfcc_band_q))
  );
  assign s_dct_total = s_dct_acc_q + s_dct_product;
  assign s_log_row_sum = {1'b0, s_snapshot_start_q} + {1'b0, s_mfcc_row_q};
  assign s_log_row_index = (s_log_row_sum >= 7'd50) ? 6'(s_log_row_sum - 7'd50) : 6'(s_log_row_sum);
  assign s_dct_coefficient = rne_shift(s_dct_total, 30);

  assign s_weight_base = operator_weight_base(s_operator_q);
  assign s_bias_base = operator_bias_base(s_operator_q);
  assign s_multiplier_base = operator_multiplier_base(s_operator_q);
  assign s_shift_base = operator_shift_base(s_operator_q);
  assign s_output_channel = s_output_q[5:0];
  assign s_output_spatial_index = s_output_q[13:6];
  assign s_output_width_index = 3'(s_output_spatial_index % 8'd5);
  assign s_output_height_index = 5'(s_output_spatial_index / 8'd5);
  assign s_term_count = (s_operator_q == 4'd0) ? 8'd40 :
      (((s_operator_q == 4'd1) || (s_operator_q == 4'd3) ||
        (s_operator_q == 4'd5) || (s_operator_q == 4'd7)) ? 8'd9 : 8'd64);
  assign s_output_count = (s_operator_q < 4'd9) ? 14'd8000 :
      ((s_operator_q == 4'd9) ? 14'd64 : 14'd12);
  assign s_input_zero = (s_operator_q == 4'd0) ? 9'sd83 : -9'sd128;
  assign s_output_zero = (s_operator_q == 4'd10) ? 9'sd14 : -9'sd128;
  assign s_relu = s_operator_q < 4'd9;
  assign s_bias_word = $signed(
      {model_data_i[3], model_data_i[2], model_data_i[1], model_data_i[0]}
  );
  assign s_multiplier_word = $signed(
      {model_data_i[3], model_data_i[2], model_data_i[1], model_data_i[0]}
  );
  assign s_shift_word = $signed(
      {model_data_i[7], model_data_i[6], model_data_i[5], model_data_i[4]}
  );
  assign s_mac_total = s_mac_q + s_lane_sum;

  always_comb begin
    model_addr_o        = '0;
    scratch_read_addr_o = '0;
    s_lane_active       = 16'd0;
    for (int lane = 0; lane < 16; lane++) begin
      s_lane_term[lane]         = {1'b0, s_term_q} + 9'(lane);
      s_lane_input_index[lane]  = 13'd0;
      s_lane_weight_index[lane] = 15'd0;
      s_lane_input_h[lane]      = 7'sd0;
      s_lane_input_w[lane]      = 5'sd0;
    end
    unique case (s_front_state_q)
      FrontFir: begin
        scratch_read_addr_o[0] = `RETROSOC_APU_KWS__SCRATCH_FIR_BASE +
            {9'd0, fir_history_index(s_fir_write_q, s_fir_tap_q), 1'b0};
      end
      FrontFftLoad: begin
        scratch_read_addr_o[0] = `RETROSOC_APU_KWS__SCRATCH_INGRESS_BASE +
            16'(ingress_add(s_frame_start_q, s_front_index_q) * 2);
      end
      FrontFftRun: begin
        scratch_read_addr_o[0] =
            `RETROSOC_APU_KWS__SCRATCH_FFT_REAL_BASE + 16'(s_fft_left_index * 4);
        scratch_read_addr_o[1] =
            `RETROSOC_APU_KWS__SCRATCH_FFT_IMAG_BASE + 16'(s_fft_left_index * 4);
        scratch_read_addr_o[2] =
            `RETROSOC_APU_KWS__SCRATCH_FFT_REAL_BASE + 16'(s_fft_right_index * 4);
        scratch_read_addr_o[3] =
            `RETROSOC_APU_KWS__SCRATCH_FFT_IMAG_BASE + 16'(s_fft_right_index * 4);
      end
      FrontMagnitude: begin
        scratch_read_addr_o[0] =
            `RETROSOC_APU_KWS__SCRATCH_FFT_REAL_BASE + 16'(s_front_index_q * 4);
        scratch_read_addr_o[1] =
            `RETROSOC_APU_KWS__SCRATCH_FFT_IMAG_BASE + 16'(s_front_index_q * 4);
      end
      FrontMel: begin
        scratch_read_addr_o[0] = `RETROSOC_APU_KWS__SCRATCH_FFT_REAL_BASE + 16'(s_mel_bin_q * 4);
      end
      FrontPeak: begin
        scratch_read_addr_o[0] = `RETROSOC_APU_KWS__SCRATCH_PEAK_BASE + 16'(s_peak_scan_q * 2);
      end
      FrontLog: begin
        scratch_read_addr_o[0] = `RETROSOC_APU_KWS__SCRATCH_MEL_BASE +
            16'((16'(s_log_row_index) * 16'd40 + 16'(s_mfcc_band_q)) * 16'd4);
      end
      FrontDct: begin
        scratch_read_addr_o[0] = `RETROSOC_APU_KWS__SCRATCH_FFT_IMAG_BASE + 16'(s_mfcc_band_q * 4);
      end
      default: begin
      end
    endcase
    if (s_infer_state_q == InferPool) begin
      for (int lane = 0; lane < 16; lane++) begin
        if (({1'b0, s_term_q} + 9'(lane)) < 9'd125) begin
          scratch_read_addr_o[lane+4] = `RETROSOC_APU_KWS__SCRATCH_A_BASE +
              16'((32'(s_term_q) + 32'(lane)) * 32'd64 + 32'(s_output_q));
        end
      end
    end else if ((s_infer_state_q == InferSoftmaxMax) || (s_infer_state_q == InferSoftmaxSum)) begin
      scratch_read_addr_o[4] = `RETROSOC_APU_KWS__SCRATCH_LOGITS_BASE + 16'(s_softmax_index_q);
    end else if ((s_infer_state_q == InferSoftmaxScale) && (s_softmax_index_q > 0)) begin
      scratch_read_addr_o[4] =
          `RETROSOC_APU_KWS__SCRATCH_LOGITS_BASE + 16'(s_softmax_index_q - 1'b1);
    end else if (s_infer_state_q == InferComplete) begin
      for (int class_index = 0; class_index < 12; class_index++) begin
        scratch_read_addr_o[class_index+4] =
            `RETROSOC_APU_KWS__SCRATCH_SOFTMAX_BASE + 16'(class_index);
      end
    end
    if (s_infer_state_q == InferBias) begin
      for (int lane = 0; lane < 4; lane++) begin
        model_addr_o[lane] = s_bias_base + 15'(s_output_channel) * 15'd4 + 15'(lane);
      end
    end else if (s_infer_state_q == InferQuant) begin
      for (int lane = 0; lane < 4; lane++) begin
        model_addr_o[lane]   = s_multiplier_base + 15'(s_output_channel) * 15'd4 + 15'(lane);
        model_addr_o[lane+4] = s_shift_base + 15'(s_output_channel) * 15'd4 + 15'(lane);
      end
    end else if (s_infer_state_q == InferMac) begin
      for (int lane = 0; lane < 16; lane++) begin
        if (s_lane_term[lane] < {1'b0, s_term_count}) begin
          s_lane_active[lane] = 1'b1;
          if (s_operator_q == 4'd0) begin
            s_lane_input_h[lane] = 7'($signed({1'b0, s_output_height_index})) * 7'sd2 +
                7'($signed(s_lane_term[lane] / 9'd4)) - 7'sd4;
            s_lane_input_w[lane] = 5'($signed({1'b0, s_output_width_index})) * 5'sd2 +
                5'($signed(s_lane_term[lane] % 9'd4)) - 5'sd1;
            s_lane_weight_index[lane] = 15'(s_output_channel) * 15'd40 + 15'(s_lane_term[lane]);
            if ((s_lane_input_h[lane] >= 0) && (s_lane_input_h[lane] < 7'sd49) &&
                (s_lane_input_w[lane] >= 0) && (s_lane_input_w[lane] < 5'sd10)) begin
              s_lane_input_index[lane] =
                  13'(s_lane_input_h[lane]) * 13'd10 + 13'(s_lane_input_w[lane]);
              scratch_read_addr_o[lane+4] =
                  `RETROSOC_APU_KWS__SCRATCH_MFCC_BASE + 16'(s_lane_input_index[lane]);
            end
          end else if ((s_operator_q == 4'd1) || (s_operator_q == 4'd3) ||
                       (s_operator_q == 4'd5) || (s_operator_q == 4'd7)) begin
            s_lane_input_h[lane] = 7'($signed({1'b0, s_output_height_index})) +
                7'($signed(s_lane_term[lane] / 9'd3)) - 7'sd1;
            s_lane_input_w[lane] = 5'($signed({1'b0, s_output_width_index})) +
                5'($signed(s_lane_term[lane] % 9'd3)) - 5'sd1;
            s_lane_weight_index[lane] = 15'(s_lane_term[lane]) * 15'd64 + 15'(s_output_channel);
            if ((s_lane_input_h[lane] >= 0) && (s_lane_input_h[lane] < 7'sd25) &&
                (s_lane_input_w[lane] >= 0) && (s_lane_input_w[lane] < 5'sd5)) begin
              s_lane_input_index[lane] =
                  (13'(s_lane_input_h[lane]) * 13'd5 + 13'(s_lane_input_w[lane])) *
                  13'd64 + 13'(s_output_channel);
              scratch_read_addr_o[lane+4] = `RETROSOC_APU_KWS__SCRATCH_A_BASE +
                  16'(s_lane_input_index[lane]);
            end
          end else begin
            s_lane_input_index[lane] = (s_operator_q == 4'd10) ?
                13'(s_lane_term[lane]) :
                (13'(s_output_spatial_index) * 13'd64 + 13'(s_lane_term[lane]));
            s_lane_weight_index[lane] = 15'(s_output_channel) * 15'd64 + 15'(s_lane_term[lane]);
            scratch_read_addr_o[lane+4] = (s_operator_q == 4'd10) ?
                (`RETROSOC_APU_KWS__SCRATCH_B_BASE + 16'(s_lane_input_index[lane])) :
                ((s_operator_q[0] ? `RETROSOC_APU_KWS__SCRATCH_A_BASE :
                                    `RETROSOC_APU_KWS__SCRATCH_B_BASE) +
                 16'(s_lane_input_index[lane]));
          end
          model_addr_o[lane] = s_weight_base + s_lane_weight_index[lane];
        end
      end
    end
  end

  always_comb begin
    for (int lane = 0; lane < 16; lane++) begin
      s_lane_input_value[lane] = 16'($signed(s_input_zero));
      if (s_lane_active[lane]) begin
        if (s_operator_q == 4'd0) begin
          if ((s_lane_input_h[lane] >= 0) && (s_lane_input_h[lane] < 7'sd49) &&
              (s_lane_input_w[lane] >= 0) && (s_lane_input_w[lane] < 5'sd10)) begin
            s_lane_input_value[lane] =
                16'(scratch_s8(scratch_read_data_i[lane+4], scratch_read_addr_o[lane+4][1:0]));
          end
        end else if ((s_operator_q == 4'd1) || (s_operator_q == 4'd3) ||
                     (s_operator_q == 4'd5) || (s_operator_q == 4'd7)) begin
          if ((s_lane_input_h[lane] >= 0) && (s_lane_input_h[lane] < 7'sd25) &&
              (s_lane_input_w[lane] >= 0) && (s_lane_input_w[lane] < 5'sd5)) begin
            s_lane_input_value[lane] =
                16'(scratch_s8(scratch_read_data_i[lane+4], scratch_read_addr_o[lane+4][1:0]));
          end
        end else begin
          s_lane_input_value[lane] =
              16'(scratch_s8(scratch_read_data_i[lane+4], scratch_read_addr_o[lane+4][1:0]));
        end
      end
    end
  end

  always_comb begin
    s_lane_sum = 64'sd0;
    for (int lane = 0; lane < 16; lane++) begin
      if (s_lane_active[lane]) begin
        s_lane_sum +=
            lane_product(s_lane_input_value[lane], s_input_zero, $signed(model_data_i[lane]));
      end
    end
  end

  always_comb begin
    s_pool_sum = s_mac_q;
    for (int lane = 0; lane < 16; lane++) begin
      if (({1'b0, s_term_q} + 9'(lane)) < 9'd125) begin
        s_pool_sum +=
            64'($signed(scratch_s8(scratch_read_data_i[lane+4], scratch_read_addr_o[lane+4][1:0])));
      end
    end
  end

  always_comb begin
    logic signed [63:0] scaled;
    s_requant_shifted = $signed({{32{s_mac_q[31]}}, s_mac_q[31:0]}) <<
        ((s_shift_word > 0) ? s_shift_word[5:0] : 6'd0);
    s_requant_overflow = ((s_shift_word > 31) && (s_mac_q[31:0] != 0)) ||
        (s_requant_shifted > 64'sh0000_0000_7fff_ffff) ||
        (s_requant_shifted < -64'sh0000_0000_8000_0000);
    scaled = 64'($signed(multiply_quantized(s_mac_q[31:0], s_multiplier_word, s_shift_word))) +
        64'($signed(s_output_zero));
    if (s_relu && (scaled < 64'($signed(s_output_zero)))) begin
      s_output_value = 8'(s_output_zero);
    end else if (scaled < -64'sd128) begin
      s_output_value = -8'sd128;
    end else if (scaled > 64'sd127) begin
      s_output_value = 8'sd127;
    end else begin
      s_output_value = scaled[7:0];
    end
  end

  assign s_logit_data = scratch_s8(scratch_read_data_i[4], scratch_read_addr_o[4][1:0]);
  for (genvar class_index = 0; class_index < 12; class_index++) begin : gen_softmax_read
    assign s_softmax_data[class_index] = scratch_s8(
        scratch_read_data_i[class_index+4], scratch_read_addr_o[class_index+4][1:0]
    );
  end

  always_comb begin
    s_softmax_sum_diff   = 9'($signed(s_logit_data)) - 9'($signed(s_softmax_max_q));
    s_softmax_scale_diff = 9'sd0;
    if ((s_softmax_index_q > 0) && (s_softmax_index_q <= 4'd12)) begin
      s_softmax_scale_diff = 9'($signed(s_logit_data)) - 9'($signed(s_softmax_max_q));
    end
    s_softmax_headroom = count_leading_zero(s_softmax_sum_q);
    s_softmax_shifted_sum = 32'($unsigned(s_softmax_sum_q) << s_softmax_headroom) - 32'h8000_0000;
    s_softmax_exp_value = (s_softmax_scale_diff >= -9'sd124) ?
        apu_kws_softmax_exp_q31(-s_softmax_scale_diff[6:0]) : 32'sd0;
    s_softmax_prob = rounding_divide_pot(
        saturating_high_mul(s_softmax_scale_q, s_softmax_exp_value), s_softmax_bits_q + 6'd23);
    if (s_softmax_prob > 32'sd255) s_softmax_prob = 32'sd255;
    if (s_softmax_prob < 0) s_softmax_prob = 32'sd0;
  end

  always_comb begin
    s_best_class = 8'd0;
    s_best_score = 8'(9'($signed(s_softmax_data[0])) + 9'sd128);
    for (int class_idx = 1; class_idx < 12; class_idx++) begin
      if (8'(9'($signed(s_softmax_data[class_idx])) + 9'sd128) > s_best_score) begin
        s_best_score = 8'(9'($signed(s_softmax_data[class_idx])) + 9'sd128);
        s_best_class = 8'(class_idx);
      end
    end
    s_match             = (s_best_class < 8'd10) && (s_best_score >= kws_config_i[7:0]);
    s_same_match        = s_match && s_last_match_q && (s_last_class_q == s_best_class);
    s_next_debounce_run = s_same_match ? {1'b0, s_debounce_run_q} + 9'd1 : (s_match ? 9'd1 : 9'd0);
    if (s_next_debounce_run > {1'b0, kws_config_i[15:8]}) begin
      s_next_debounce_run = {1'b0, kws_config_i[15:8]};
    end
    s_stable_hit = s_same_match ? s_stable_hit_q : 1'b0;
    s_hit_event  = s_match && !s_stable_hit && (s_next_debounce_run >= {1'b0, kws_config_i[15:8]});
    if (s_hit_event) s_stable_hit = 1'b1;
  end

  assign s_fft_overflow =
      (s_fft_sum_real > 64'sh0000_0000_7fff_ffff) ||
      (s_fft_sum_real < -64'sh0000_0000_8000_0000) ||
      (s_fft_sum_imag > 64'sh0000_0000_7fff_ffff) ||
      (s_fft_sum_imag < -64'sh0000_0000_8000_0000) ||
      (s_fft_diff_real > 64'sh0000_0000_7fff_ffff) ||
      (s_fft_diff_real < -64'sh0000_0000_8000_0000) ||
      (s_fft_diff_imag > 64'sh0000_0000_7fff_ffff) ||
      (s_fft_diff_imag < -64'sh0000_0000_8000_0000);

  always_comb begin
    scratch_clear_o       = soft_reset_i || resource_reset_i || abort_i ||
        (enable_i && !s_en_q) || clear_history_i ||
        (quiesce_i && (s_front_state_q == FrontIdle) && (s_infer_state_q == InferIdle)) ||
        (s_stream_accept && !s_stream_legal) ||
        (flush_busy_i && !s_flush_seen_q && s_continuous_active);
    scratch_write_valid_o = 6'd0;
    scratch_write_addr_o = '0;
    scratch_write_data_o = '0;
    scratch_write_strb_o = '0;
    if (rst_n_i && !(soft_reset_i || resource_reset_i || abort_i)) begin
      if (s_stream_accept && s_stream_legal && (s_decimation != 3'd1) &&
          ((input_config_i[25:20] == 6'd16) ||
           ((input_config_i[25:20] == 6'd24) && s_s24_pending_q))) begin
        scratch_write_valid_o[0] = 1'b1;
        scratch_write_addr_o[0] = `RETROSOC_APU_KWS__SCRATCH_FIR_BASE + 16'(s_fir_write_q * 2);
        scratch_write_data_o[0] = {
            2{(input_config_i[25:20] == 6'd16) ? saturate_s16(64'($signed(s_stereo_sum)) >>> 1) :
              saturate_s16(64'($signed(s_stereo_sum)) >>> 9)}};
        scratch_write_strb_o[0] = s_fir_write_q[0] ? 4'b1100 : 4'b0011;
      end
      if (s_commit_valid) begin
        scratch_write_valid_o[0] = 1'b1;
        scratch_write_addr_o[0] =
            `RETROSOC_APU_KWS__SCRATCH_INGRESS_BASE + 16'(s_ingress_write_q * 2);
        scratch_write_data_o[0] = {2{s_commit_sample}};
        scratch_write_strb_o[0] = s_ingress_write_q[0] ? 4'b1100 : 4'b0011;
        if (s_block_samples_q == 8'd159) begin
          scratch_write_valid_o[1] = 1'b1;
          scratch_write_addr_o[1]  = `RETROSOC_APU_KWS__SCRATCH_PEAK_BASE + 16'(s_peak_write_q * 2);
          scratch_write_data_o[1]  = {2{s_next_peak}};
          scratch_write_strb_o[1]  = s_peak_write_q[0] ? 4'b1100 : 4'b0011;
        end
      end
      unique case (s_front_state_q)
        FrontFftLoad: begin
          scratch_write_valid_o[0] = 1'b1;
          scratch_write_addr_o[0] = `RETROSOC_APU_KWS__SCRATCH_FFT_REAL_BASE +
              16'(bit_reverse9(s_front_index_q[8:0]) * 4);
          scratch_write_data_o[0] = rne_shift_s32(s_windowed, 6'd15);
          scratch_write_strb_o[0] = 4'hf;
          scratch_write_valid_o[1] = 1'b1;
          scratch_write_addr_o[1] = `RETROSOC_APU_KWS__SCRATCH_FFT_IMAG_BASE +
              16'(bit_reverse9(s_front_index_q[8:0]) * 4);
          scratch_write_data_o[1] = 32'd0;
          scratch_write_strb_o[1] = 4'hf;
        end
        FrontFftRun: begin
          if (!s_fft_overflow) begin
            scratch_write_valid_o[0] = 1'b1;
            scratch_write_addr_o[0]  = ScratchFftRealBase + 16'(s_fft_left_index * 4);
            scratch_write_data_o[0]  = s_fft_sum_real[31:0];
            scratch_write_strb_o[0]  = 4'hf;
            scratch_write_valid_o[1] = 1'b1;
            scratch_write_addr_o[1]  = ScratchFftImagBase + 16'(s_fft_left_index * 4);
            scratch_write_data_o[1]  = s_fft_sum_imag[31:0];
            scratch_write_strb_o[1]  = 4'hf;
            scratch_write_valid_o[2] = 1'b1;
            scratch_write_addr_o[2]  = ScratchFftRealBase + 16'(s_fft_right_index * 4);
            scratch_write_data_o[2]  = s_fft_diff_real[31:0];
            scratch_write_strb_o[2]  = 4'hf;
            scratch_write_valid_o[3] = 1'b1;
            scratch_write_addr_o[3]  = ScratchFftImagBase + 16'(s_fft_right_index * 4);
            scratch_write_data_o[3]  = s_fft_diff_imag[31:0];
            scratch_write_strb_o[3]  = 4'hf;
          end
        end
        FrontMagnitude: begin
          scratch_write_valid_o[0] = 1'b1;
          scratch_write_addr_o[0] =
              `RETROSOC_APU_KWS__SCRATCH_FFT_REAL_BASE + 16'(s_front_index_q * 4);
          scratch_write_data_o[0] = nearest_isqrt(s_magnitude_square);
          scratch_write_strb_o[0] = 4'hf;
        end
        FrontMel: begin
          if (!s_mel_overwrite && (s_mel_bin_q == 9'd256) && (s_mel_total >= s_mel_acc_q)) begin
            scratch_write_valid_o[0] = 1'b1;
            scratch_write_addr_o[0] = `RETROSOC_APU_KWS__SCRATCH_MEL_BASE +
                16'((16'(s_mel_write_q) * 16'd40 + 16'(s_mel_band_q)) * 16'd4);
            scratch_write_data_o[0] = rne_uq32(s_mel_total);
            scratch_write_strb_o[0] = 4'hf;
          end
        end
        FrontLog: begin
          scratch_write_valid_o[0] = 1'b1;
          scratch_write_addr_o[0] =
              `RETROSOC_APU_KWS__SCRATCH_FFT_IMAG_BASE + 16'(s_mfcc_band_q * 4);
          scratch_write_data_o[0] = log_mel_q24(s_mel_data, s_window_peak_q);
          scratch_write_strb_o[0] = 4'hf;
        end
        FrontDct: begin
          if (s_mfcc_band_q == 6'd39) begin
            scratch_write_valid_o[0] = 1'b1;
            scratch_write_addr_o[0] = `RETROSOC_APU_KWS__SCRATCH_MFCC_BASE +
                16'(9'(s_mfcc_row_q) * 9'd10 + 9'(s_mfcc_coefficient_q));
            scratch_write_data_o[0] = {4{8'(s_dct_coefficient / 64'sh0095_af17 + 64'sd83)}};
            scratch_write_strb_o[0] = 4'b0001 << scratch_write_addr_o[0][1:0];
          end
        end
        default: begin
        end
      endcase
      if ((s_infer_state_q == InferQuant) && !s_requant_overflow) begin
        scratch_write_valid_o[4] = 1'b1;
        scratch_write_addr_o[4] = ((s_operator_q[0] && (s_operator_q != 4'd10)) ?
            `RETROSOC_APU_KWS__SCRATCH_B_BASE : `RETROSOC_APU_KWS__SCRATCH_A_BASE) +
            16'(s_output_q);
        scratch_write_data_o[4] = {4{s_output_value}};
        scratch_write_strb_o[4] = 4'b0001 << scratch_write_addr_o[4][1:0];
        if (s_operator_q == 4'd10) begin
          scratch_write_valid_o[5] = 1'b1;
          scratch_write_addr_o[5]  = `RETROSOC_APU_KWS__SCRATCH_LOGITS_BASE + 16'(s_output_q);
          scratch_write_data_o[5]  = {4{s_output_value}};
          scratch_write_strb_o[5]  = 4'b0001 << scratch_write_addr_o[5][1:0];
        end
      end else if ((s_infer_state_q == InferPool) && (s_term_q + 8'd16 >= 8'd125)) begin
        scratch_write_valid_o[4] = 1'b1;
        scratch_write_addr_o[4] = `RETROSOC_APU_KWS__SCRATCH_B_BASE + 16'(s_output_q);
        scratch_write_data_o[4] = {
          4
          {
            8'((s_pool_sum >= 0) ? (s_pool_sum + 64'sd62) / 64'sd125 :
                                   (s_pool_sum - 64'sd62) / 64'sd125)
          }
        };
        scratch_write_strb_o[4] = 4'b0001 << scratch_write_addr_o[4][1:0];
      end else if ((s_infer_state_q == InferSoftmaxScale) && (s_softmax_index_q != 0)) begin
        scratch_write_valid_o[4] = 1'b1;
        scratch_write_addr_o[4]  = ScratchSoftmaxBase + 16'(s_softmax_index_q - 1'b1);
        scratch_write_data_o[4]  = {4{s_softmax_prob[7:0] - 8'd128}};
        scratch_write_strb_o[4]  = 4'b0001 << scratch_write_addr_o[4][1:0];
      end
    end
  end

  assign memory_dma_request_valid_o = s_mem_req_q;
  assign memory_start_ready_o = enable_i && memory_window_i && model_valid_i && model_lock_i &&
      !abort_i && !soft_reset_i && !resource_reset_i && !s_mem_job_q &&
      (s_infer_state_q == InferIdle) && (s_front_state_q == FrontIdle);
  assign memory_dma_request_address_o = memory_address_i;
  assign memory_dma_request_bytes_o = 32'd32000;
  assign memory_dma_ready_o = s_mem_dma_active_q && !s_mem_word_valid_q;
  assign memory_done_o = s_mem_done_q;
  assign memory_error_o = s_mem_err_q;
  assign memory_error_code_o = s_mem_err_code_q;
  assign memory_error_stage_o = s_mem_err_stage_q;
  assign memory_error_resp_o = s_mem_err_resp_q;
  assign memory_error_address_o = s_mem_err_addr_q;
  assign memory_error_detail_o = s_mem_err_detail_q;
  assign memory_input_used_o = s_epoch_samples_q << 1;

  assign model_valid_o = model_valid_i;
  assign model_lock_o = model_lock_i;
  assign model_status_o = {29'd0, model_lock_i, model_valid_i, 1'b0};
  assign model_actual_crc_o = 32'd0;
  assign status_o = {
    24'd0,
    s_result_valid_q,
    model_lock_i,
    model_valid_i,
    s_overrun_sticky_q,
    s_result_q[16],
    (s_epoch_samples_q >= 32'd16000),
    (s_infer_state_q != InferIdle) || (s_front_state_q != FrontIdle) ||
        s_frame_pending_q || s_window_pending_q,
    s_listening
  };
  assign result_o = s_result_q;
  assign timestamp_lo_o = s_timestamp_lo_q;
  assign timestamp_hi_o = s_timestamp_hi_q;
  assign frame_count_o = s_frame_count_q;
  assign inference_count_o = s_inference_count_q;
  assign hit_count_o = s_hit_count_q;
  assign overrun_count_o = s_overrun_count_q;
  assign irq_set_o = {1'd0, s_overrun_irq_q, 6'd0, s_hit_irq_q, 2'd0};
  assign fault_valid_o = s_fault_q;
  assign fault_code_o = s_fault_code_q;
  assign fault_stage_o = s_fault_stage_q;
  assign fault_resp_o = 2'd0;
  assign fault_index_o = 8'd0;
  assign fault_addr_o = s_mem_err_q ? s_mem_err_addr_q : s_fault_addr_q;
  assign fault_detail_o = s_fault_detail_q;
  assign busy_o = s_listening || (s_front_state_q != FrontIdle) ||
      (s_infer_state_q != InferIdle) || s_frame_pending_q || s_window_pending_q ||
      s_mem_req_q || s_mem_dma_active_q || s_mem_job_q;
  assign idle_o = !busy_o;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_front_state_q      <= FrontIdle;
      s_infer_state_q      <= InferIdle;
      s_ingress_write_q    <= 10'd0;
      s_fir_write_q        <= 6'd0;
      s_fir_tap_q          <= 6'd0;
      s_fir_phase_q        <= 3'd0;
      s_fir_sample_q       <= 16'sd0;
      s_fir_acc_q          <= 64'sd0;
      s_epoch_samples_q    <= 32'd0;
      s_next_frame_q       <= 32'd480;
      s_next_window_q      <= 32'd16000;
      s_block_samples_q    <= 8'd0;
      s_block_peak_q       <= 16'd1;
      s_peak_write_q       <= 7'd0;
      s_mel_write_q        <= 6'd0;
      s_mel_count_q        <= 6'd0;
      s_frame_pending_q    <= 1'b0;
      s_window_pending_q   <= 1'b0;
      s_frame_start_q      <= 10'd0;
      s_snapshot_start_q   <= 6'd0;
      s_front_index_q      <= 10'd0;
      s_fft_len_q          <= 10'd2;
      s_fft_half_q         <= 9'd1;
      s_fft_group_q        <= 9'd0;
      s_fft_j_q            <= 8'd0;
      s_mel_band_q         <= 8'd0;
      s_mel_bin_q          <= 9'd0;
      s_mel_acc_q          <= 64'd0;
      s_peak_scan_q        <= 7'd0;
      s_window_peak_q      <= 16'd1;
      s_mfcc_row_q         <= 6'd0;
      s_mfcc_band_q        <= 6'd0;
      s_mfcc_coefficient_q <= 4'd0;
      s_dct_acc_q          <= 64'sd0;
      s_operator_q         <= 4'd0;
      s_output_q           <= 14'd0;
      s_term_q             <= 8'd0;
      s_mac_q              <= 64'sd0;
      s_softmax_index_q    <= 4'd0;
      s_softmax_max_q      <= -8'sd128;
      s_softmax_sum_q      <= 32'd0;
      s_softmax_scale_q    <= 32'sd0;
      s_softmax_bits_q     <= 6'sd0;
      s_debounce_run_q     <= 8'd0;
      s_last_class_q       <= 8'hff;
      s_last_match_q       <= 1'b0;
      s_stable_hit_q       <= 1'b0;
      s_frame_count_q      <= 32'd0;
      s_inference_count_q  <= 32'd0;
      s_hit_count_q        <= 32'd0;
      s_overrun_count_q    <= 32'd0;
      s_result_q           <= 32'd0;
      s_timestamp_lo_q     <= 32'd0;
      s_timestamp_hi_q     <= 32'd0;
      s_timestamp_q        <= 32'd0;
      s_result_valid_q     <= 1'b0;
      s_overrun_sticky_q   <= 1'b0;
      s_stop_latched_q     <= 1'b0;
      s_flush_seen_q       <= 1'b0;
      s_hit_irq_q          <= 1'b0;
      s_overrun_irq_q      <= 1'b0;
      s_mem_req_q          <= 1'b0;
      s_mem_dma_active_q   <= 1'b0;
      s_mem_job_q          <= 1'b0;
      s_mem_dma_done_q     <= 1'b0;
      s_mem_word_valid_q   <= 1'b0;
      s_mem_high_q         <= 1'b0;
      s_mem_done_q         <= 1'b0;
      s_mem_err_q          <= 1'b0;
      s_mem_word_q         <= 32'd0;
      s_mem_received_q     <= 32'd0;
      s_mem_err_code_q     <= 6'd0;
      s_mem_err_stage_q    <= 4'd0;
      s_mem_err_resp_q     <= 2'd0;
      s_mem_err_addr_q     <= 32'd0;
      s_mem_err_detail_q   <= 32'd0;
      s_s24_first_q        <= 24'sd0;
      s_s24_pending_q      <= 1'b0;
      s_fault_q            <= 1'b0;
      s_fault_code_q       <= 6'd0;
      s_fault_stage_q      <= 4'd0;
      s_fault_addr_q       <= 32'd0;
      s_fault_detail_q     <= 32'd0;
      s_front_watchdog_q   <= 32'd0;
      s_infer_watchdog_q   <= 32'd0;
      s_en_q               <= 1'b0;
      s_quiesce_seen_q     <= 1'b0;
    end else begin
      s_hit_irq_q     <= 1'b0;
      s_overrun_irq_q <= 1'b0;
      s_mem_done_q    <= 1'b0;
      s_fault_q       <= 1'b0;
      s_en_q          <= enable_i;

      if (counter_clear_i) begin
        s_frame_count_q     <= 32'd0;
        s_inference_count_q <= 32'd0;
        s_hit_count_q       <= 32'd0;
        s_overrun_count_q   <= 32'd0;
      end
      if (xrun_clear_i) s_overrun_sticky_q <= 1'b0;

      if (!enable_i) s_stop_latched_q <= 1'b0;
      if (!flush_busy_i) s_flush_seen_q <= 1'b0;
      if (!quiesce_i) s_quiesce_seen_q <= 1'b0;

      if (soft_reset_i || resource_reset_i || abort_i) begin
        s_front_state_q    <= FrontIdle;
        s_infer_state_q    <= InferIdle;
        s_epoch_samples_q  <= 32'd0;
        s_next_frame_q     <= 32'd480;
        s_next_window_q    <= 32'd16000;
        s_block_samples_q  <= 8'd0;
        s_block_peak_q     <= 16'd1;
        s_peak_write_q     <= 7'd0;
        s_mel_write_q      <= 6'd0;
        s_mel_count_q      <= 6'd0;
        s_frame_pending_q  <= 1'b0;
        s_window_pending_q <= 1'b0;
        s_result_q         <= 32'd0;
        s_result_valid_q   <= 1'b0;
        s_debounce_run_q   <= 8'd0;
        s_last_class_q     <= 8'hff;
        s_last_match_q     <= 1'b0;
        s_stable_hit_q     <= 1'b0;
        s_s24_pending_q    <= 1'b0;
        s_mem_req_q        <= 1'b0;
        s_mem_dma_active_q <= 1'b0;
        s_mem_job_q        <= 1'b0;
        s_mem_dma_done_q   <= 1'b0;
        s_mem_word_valid_q <= 1'b0;
        s_stop_latched_q   <= abort_i;
        s_front_watchdog_q <= 32'd0;
        s_infer_watchdog_q <= 32'd0;
        s_en_q             <= 1'b0;
        s_quiesce_seen_q   <= quiesce_i;
        if (soft_reset_i || resource_reset_i) begin
          s_frame_count_q     <= 32'd0;
          s_inference_count_q <= 32'd0;
          s_hit_count_q       <= 32'd0;
          s_overrun_count_q   <= 32'd0;
          s_overrun_sticky_q  <= 1'b0;
          s_mem_err_q         <= 1'b0;
          s_mem_err_code_q    <= 6'd0;
          s_mem_err_stage_q   <= 4'd0;
          s_mem_err_resp_q    <= 2'd0;
          s_mem_err_addr_q    <= 32'd0;
          s_mem_err_detail_q  <= 32'd0;
        end
      end else begin
        if (s_front_state_q == FrontIdle || s_front_progress) begin
          s_front_watchdog_q <= 32'd0;
        end else if (!(&s_front_watchdog_q)) begin
          s_front_watchdog_q <= s_front_watchdog_q + 1'b1;
        end
        if (s_infer_state_q == InferIdle || s_infer_progress) begin
          s_infer_watchdog_q <= 32'd0;
        end else if (!(&s_infer_watchdog_q)) begin
          s_infer_watchdog_q <= s_infer_watchdog_q + 1'b1;
        end

        if (enable_i && !s_en_q) begin
          s_epoch_samples_q  <= 32'd0;
          s_next_frame_q     <= 32'd480;
          s_next_window_q    <= 32'd16000;
          s_block_samples_q  <= 8'd0;
          s_block_peak_q     <= 16'd1;
          s_peak_write_q     <= 7'd0;
          s_mel_write_q      <= 6'd0;
          s_mel_count_q      <= 6'd0;
          s_frame_pending_q  <= 1'b0;
          s_window_pending_q <= 1'b0;
          s_fir_write_q      <= 6'd0;
          s_fir_tap_q        <= 6'd0;
          s_fir_phase_q      <= 3'd0;
          s_debounce_run_q   <= 8'd0;
          s_last_class_q     <= 8'hff;
          s_last_match_q     <= 1'b0;
          s_stable_hit_q     <= 1'b0;
          s_result_valid_q   <= 1'b0;
          s_s24_pending_q    <= 1'b0;
        end

        if (quiesce_i && !s_quiesce_seen_q) begin
          s_quiesce_seen_q <= 1'b1;
          if ((s_epoch_samples_q != 0) || s_frame_pending_q || s_window_pending_q ||
              (s_front_state_q != FrontIdle) || (s_infer_state_q != InferIdle)) begin
            if (!counter_clear_i) begin
              s_overrun_count_q <= (s_overrun_count_q == 32'hffff_ffff) ?
                s_overrun_count_q : s_overrun_count_q + 1'b1;
            end
          end
        end

        if (clear_history_i || (quiesce_i && (s_front_state_q == FrontIdle) &&
                                (s_infer_state_q == InferIdle))) begin
          s_epoch_samples_q  <= 32'd0;
          s_next_frame_q     <= 32'd480;
          s_next_window_q    <= 32'd16000;
          s_block_samples_q  <= 8'd0;
          s_block_peak_q     <= 16'd1;
          s_peak_write_q     <= 7'd0;
          s_mel_write_q      <= 6'd0;
          s_mel_count_q      <= 6'd0;
          s_frame_pending_q  <= 1'b0;
          s_window_pending_q <= 1'b0;
          s_debounce_run_q   <= 8'd0;
          s_last_class_q     <= 8'hff;
          s_last_match_q     <= 1'b0;
          s_stable_hit_q     <= 1'b0;
          s_result_valid_q   <= 1'b0;
          s_s24_pending_q    <= 1'b0;
          s_fir_write_q      <= 6'd0;
          s_fir_tap_q        <= 6'd0;
          s_fir_phase_q      <= 3'd0;
        end

        if (memory_start_i && memory_start_ready_o) begin
          s_mem_req_q        <= 1'b1;
          s_mem_job_q        <= 1'b1;
          s_mem_err_q        <= 1'b0;
          s_mem_received_q   <= 32'd0;
          s_mem_dma_done_q   <= 1'b0;
          s_mem_word_valid_q <= 1'b0;
          s_mem_high_q       <= 1'b0;
          s_mem_err_code_q   <= 6'd0;
          s_mem_err_stage_q  <= 4'd0;
          s_mem_err_resp_q   <= 2'd0;
          s_mem_err_addr_q   <= 32'd0;
          s_mem_err_detail_q <= 32'd0;
          s_epoch_samples_q  <= 32'd0;
          s_next_frame_q     <= 32'd480;
          s_next_window_q    <= 32'd16000;
          s_block_samples_q  <= 8'd0;
          s_block_peak_q     <= 16'd1;
          s_peak_write_q     <= 7'd0;
          s_mel_write_q      <= 6'd0;
          s_mel_count_q      <= 6'd0;
          s_result_valid_q   <= 1'b0;
        end
        if (s_mem_req_q && memory_dma_request_ready_i) begin
          s_mem_req_q        <= 1'b0;
          s_mem_dma_active_q <= 1'b1;
        end
        if (memory_dma_valid_i && memory_dma_ready_o) begin
          if ((memory_dma_keep_i != 4'hf) || (s_mem_received_q >= 32'd32000) ||
              (memory_dma_last_i != (s_mem_received_q == 32'd31996))) begin
            s_mem_err_q        <= 1'b1;
            s_mem_err_code_q   <= `APB4_APU__ERROR_CODE_STREAM_OVERRUN;
            s_mem_err_stage_q  <= `APB4_APU__ERROR_STAGE_KWS_FRONTEND;
            s_mem_err_resp_q   <= 2'd0;
            s_mem_err_addr_q   <= memory_address_i + s_mem_received_q;
            s_mem_err_detail_q <= 32'h0700_01ff;
          end else begin
            s_mem_word_q       <= memory_dma_data_i;
            s_mem_word_valid_q <= 1'b1;
            s_mem_high_q       <= 1'b0;
            s_mem_received_q   <= s_mem_received_q + 32'd4;
          end
        end
        if (memory_dma_done_i && s_mem_dma_active_q) begin
          s_mem_dma_active_q <= 1'b0;
          s_mem_dma_done_q   <= 1'b1;
          if (memory_dma_error_i) begin
            s_mem_err_q        <= 1'b1;
            s_mem_err_code_q   <= memory_dma_error_code_i;
            s_mem_err_stage_q  <= memory_dma_error_stage_i;
            s_mem_err_resp_q   <= memory_dma_error_resp_i;
            s_mem_err_addr_q   <= memory_dma_error_address_i;
            s_mem_err_detail_q <= 32'd0;
          end
        end

        if (s_stream_accept && ((stream_i.tkeep != 4'hf) ||
                                (stream_i.tstrb != 4'hf) || stream_i.tlast)) begin
          if (!counter_clear_i) begin
            s_overrun_count_q <= (s_overrun_count_q == 32'hffff_ffff) ?
                s_overrun_count_q : s_overrun_count_q + 1'b1;
          end
          s_overrun_sticky_q <= 1'b1;
          s_overrun_irq_q    <= 1'b1;
          s_stop_latched_q   <= 1'b1;
          s_fault_q          <= 1'b1;
          s_fault_code_q     <= `APB4_APU__ERROR_CODE_STREAM_OVERRUN;
          s_fault_stage_q    <= `APB4_APU__ERROR_STAGE_KWS_FRONTEND;
          s_fault_detail_q   <= 32'h0700_0013;
        end else if (s_stream_accept && (input_config_i[25:20] == 6'd24) && !s_s24_pending_q) begin
          s_s24_first_q   <= stream_i.tdata[23:0];
          s_s24_pending_q <= 1'b1;
        end else if (s_stream_accept && (s_decimation != 3'd1) &&
                     ((input_config_i[25:20] == 6'd16) || s_s24_pending_q)) begin
          s_fir_sample_q <= (input_config_i[25:20] == 6'd16) ? saturate_s16(
              64'($signed(s_stereo_sum)) >>> 1
          ) : saturate_s16(
              64'($signed(s_stereo_sum)) >>> 9
          );
          s_fir_write_q <= (s_fir_write_q == 6'd62) ? 6'd0 : s_fir_write_q + 1'b1;
          s_fir_tap_q <= 6'd0;
          s_fir_acc_q <= 64'sd0;
          s_front_state_q <= FrontFir;
          s_s24_pending_q <= 1'b0;
        end else if (s_stream_accept && (input_config_i[25:20] == 6'd24)) begin
          s_s24_pending_q <= 1'b0;
        end

        if (s_commit_valid) begin
          s_ingress_write_q <= s_next_write;
          s_epoch_samples_q <= s_next_samples;
          s_timestamp_q     <= s_timestamp_q + 1'b1;
          if (s_block_samples_q == 8'd159) begin
            s_peak_write_q    <= (s_peak_write_q == 7'd99) ? 7'd0 : s_peak_write_q + 1'b1;
            s_block_samples_q <= 8'd0;
            s_block_peak_q    <= 16'd1;
          end else begin
            s_block_samples_q <= s_block_samples_q + 1'b1;
            s_block_peak_q    <= s_next_peak;
          end
          if (s_next_samples == s_next_frame_q) begin
            s_frame_pending_q <= 1'b1;
            s_frame_start_q   <= ingress_add(s_next_write, 10'd288);
            s_next_frame_q    <= s_next_frame_q + 32'd320;
          end
          if (s_next_samples == s_next_window_q) begin
            if (!s_window_deadline) begin
              s_window_pending_q <= 1'b1;
              s_snapshot_start_q <= (s_mel_write_q >= 6'd49) ?
                  s_mel_write_q - 6'd49 : s_mel_write_q + 6'd1;
            end
            s_next_window_q <= s_next_window_q + 32'd1600;
          end
          if (s_mem_word_valid_q) begin
            if (!s_mem_high_q) begin
              s_mem_high_q <= 1'b1;
            end else begin
              s_mem_word_valid_q <= 1'b0;
              s_mem_high_q       <= 1'b0;
            end
          end
        end

        unique case (s_front_state_q)
          FrontIdle: begin
            if (s_frame_pending_q) begin
              s_frame_pending_q <= 1'b0;
              s_front_index_q   <= 10'd0;
              s_front_state_q   <= FrontFftLoad;
            end else if (s_window_pending_q && (s_mel_count_q >= 6'd49) &&
                         (s_infer_state_q == InferIdle)) begin
              s_window_pending_q <= 1'b0;
              s_peak_scan_q      <= 7'd0;
              s_window_peak_q    <= 16'd1;
              s_front_state_q    <= FrontPeak;
            end
          end
          FrontFir: begin
            if (s_fir_tap_q == 6'd62) begin
              s_fir_tap_q <= 6'd0;
              s_fir_acc_q <= 64'sd0;
              s_fir_phase_q <= (s_fir_phase_q == (s_decimation - 1'b1)) ?
                  3'd0 : s_fir_phase_q + 1'b1;
              s_front_state_q <= FrontIdle;
            end else begin
              s_fir_acc_q <= s_fir_total;
              s_fir_tap_q <= s_fir_tap_q + 1'b1;
            end
          end
          FrontFftLoad: begin
            if (s_front_index_q == 10'd511) begin
              s_fft_len_q     <= 10'd2;
              s_fft_half_q    <= 9'd1;
              s_fft_group_q   <= 9'd0;
              s_fft_j_q       <= 8'd0;
              s_front_state_q <= FrontFftRun;
            end else begin
              s_front_index_q <= s_front_index_q + 1'b1;
            end
          end
          FrontFftRun: begin
            if (s_fft_overflow) begin
              s_fault_q        <= 1'b1;
              s_fault_code_q   <= `APB4_APU__ERROR_CODE_KWS_ARITHMETIC;
              s_fault_stage_q  <= `APB4_APU__ERROR_STAGE_KWS_FRONTEND;
              s_fault_detail_q <= 32'h0700_0014;
              s_stop_latched_q <= 1'b1;
              s_front_state_q  <= FrontIdle;
            end else begin
              if (s_fft_j_q + 1'b1 == s_fft_half_q) begin
                s_fft_j_q <= 8'd0;
                if (s_fft_group_q + s_fft_len_q == 10'd512) begin
                  s_fft_group_q <= 9'd0;
                  if (s_fft_len_q == 10'd512) begin
                    s_front_index_q <= 10'd0;
                    s_front_state_q <= FrontMagnitude;
                  end else begin
                    s_fft_len_q  <= s_fft_len_q << 1;
                    s_fft_half_q <= s_fft_half_q << 1;
                  end
                end else begin
                  s_fft_group_q <= 9'(s_fft_group_q + s_fft_len_q);
                end
              end else begin
                s_fft_j_q <= s_fft_j_q + 1'b1;
              end
            end
          end
          FrontMagnitude: begin
            if (s_front_index_q == 10'd256) begin
              s_mel_band_q    <= 8'd0;
              s_mel_bin_q     <= 9'd0;
              s_mel_acc_q     <= 64'd0;
              s_front_state_q <= FrontMel;
            end else begin
              s_front_index_q <= s_front_index_q + 1'b1;
            end
          end
          FrontMel: begin
            if (s_mel_total < s_mel_acc_q) begin
              s_fault_q        <= 1'b1;
              s_fault_code_q   <= `APB4_APU__ERROR_CODE_KWS_ARITHMETIC;
              s_fault_stage_q  <= `APB4_APU__ERROR_STAGE_KWS_FRONTEND;
              s_fault_detail_q <= 32'h0700_0015;
              s_stop_latched_q <= 1'b1;
              s_front_state_q  <= FrontIdle;
            end else if (s_mel_overwrite) begin
              s_front_state_q <= FrontIdle;
            end else if (s_mel_bin_q == 9'd256) begin
              s_mel_bin_q <= 9'd0;
              s_mel_acc_q <= 64'd0;
              if (s_mel_band_q == 8'd39) begin
                s_mel_band_q  <= 8'd0;
                s_mel_write_q <= (s_mel_write_q == 6'd49) ? 6'd0 : s_mel_write_q + 1'b1;
                if (s_mel_count_q < 6'd50) s_mel_count_q <= s_mel_count_q + 1'b1;
                if (!counter_clear_i) begin
                  s_frame_count_q <= (s_frame_count_q == 32'hffff_ffff) ?
                      s_frame_count_q : s_frame_count_q + 1'b1;
                end
                s_front_state_q <= FrontIdle;
              end else begin
                s_mel_band_q <= s_mel_band_q + 1'b1;
              end
            end else begin
              s_mel_acc_q <= s_mel_total;
              s_mel_bin_q <= s_mel_bin_q + 1'b1;
            end
          end
          FrontPeak: begin
            if (s_peak_data > s_window_peak_q) begin
              s_window_peak_q <= s_peak_data;
            end
            if (s_peak_scan_q == 7'd99) begin
              s_mfcc_row_q    <= 6'd0;
              s_mfcc_band_q   <= 6'd0;
              s_front_state_q <= FrontLog;
            end else begin
              s_peak_scan_q <= s_peak_scan_q + 1'b1;
            end
          end
          FrontLog: begin
            if (s_mfcc_band_q == 6'd39) begin
              s_mfcc_band_q        <= 6'd0;
              s_mfcc_coefficient_q <= 4'd0;
              s_dct_acc_q          <= 64'sd0;
              s_front_state_q      <= FrontDct;
            end else begin
              s_mfcc_band_q <= s_mfcc_band_q + 1'b1;
            end
          end
          FrontDct: begin
            if (s_mfcc_band_q == 6'd39) begin
              s_mfcc_band_q <= 6'd0;
              s_dct_acc_q   <= 64'sd0;
              if (s_mfcc_coefficient_q == 4'd9) begin
                s_mfcc_coefficient_q <= 4'd0;
                if (s_mfcc_row_q == 6'd48) begin
                  s_operator_q    <= 4'd0;
                  s_output_q      <= 14'd0;
                  s_infer_state_q <= InferBias;
                  s_front_state_q <= FrontIdle;
                end else begin
                  s_mfcc_row_q    <= s_mfcc_row_q + 1'b1;
                  s_front_state_q <= FrontLog;
                end
              end else begin
                s_mfcc_coefficient_q <= s_mfcc_coefficient_q + 1'b1;
              end
            end else begin
              s_dct_acc_q   <= s_dct_total;
              s_mfcc_band_q <= s_mfcc_band_q + 1'b1;
            end
          end
          default: s_front_state_q <= FrontIdle;
        endcase

        unique case (s_infer_state_q)
          InferIdle: begin
          end
          InferBias: begin
            s_mac_q         <= 64'($signed(s_bias_word));
            s_term_q        <= 8'd0;
            s_infer_state_q <= InferMac;
          end
          InferMac: begin
            if ((s_mac_total > 64'sh0000_0000_7fff_ffff) ||
                (s_mac_total < -64'sh0000_0000_8000_0000)) begin
              s_fault_q        <= 1'b1;
              s_fault_code_q   <= `APB4_APU__ERROR_CODE_KWS_ARITHMETIC;
              s_fault_stage_q  <= `APB4_APU__ERROR_STAGE_KWS_INFERENCE;
              s_fault_detail_q <= 32'h0700_0016;
              s_stop_latched_q <= 1'b1;
              s_infer_state_q  <= InferIdle;
            end else if (s_term_q + 8'd16 >= s_term_count) begin
              s_mac_q         <= s_mac_total;
              s_infer_state_q <= InferQuant;
            end else begin
              s_mac_q  <= s_mac_total;
              s_term_q <= s_term_q + 8'd16;
            end
          end
          InferQuant: begin
            if (s_requant_overflow) begin
              s_fault_q        <= 1'b1;
              s_fault_code_q   <= `APB4_APU__ERROR_CODE_KWS_ARITHMETIC;
              s_fault_stage_q  <= `APB4_APU__ERROR_STAGE_KWS_INFERENCE;
              s_fault_detail_q <= 32'h0700_0017;
              s_stop_latched_q <= 1'b1;
              s_infer_state_q  <= InferIdle;
            end else begin
              if (s_output_q + 1'b1 == s_output_count) begin
                s_output_q <= 14'd0;
                if (s_operator_q == 4'd8) begin
                  s_operator_q    <= 4'd9;
                  s_term_q        <= 8'd0;
                  s_mac_q         <= 64'sd0;
                  s_infer_state_q <= InferPool;
                end else if (s_operator_q == 4'd10) begin
                  s_operator_q      <= 4'd11;
                  s_softmax_index_q <= 4'd0;
                  s_softmax_max_q   <= -8'sd128;
                  s_infer_state_q   <= InferSoftmaxMax;
                end else begin
                  s_operator_q    <= s_operator_q + 1'b1;
                  s_infer_state_q <= InferBias;
                end
              end else begin
                s_output_q      <= s_output_q + 1'b1;
                s_infer_state_q <= InferBias;
              end
            end
          end
          InferPool: begin
            if (s_term_q + 8'd16 >= 8'd125) begin
              s_term_q <= 8'd0;
              s_mac_q  <= 64'sd0;
              if (s_output_q == 14'd63) begin
                s_output_q      <= 14'd0;
                s_operator_q    <= 4'd10;
                s_infer_state_q <= InferBias;
              end else begin
                s_output_q <= s_output_q + 1'b1;
              end
            end else begin
              s_mac_q  <= s_pool_sum;
              s_term_q <= s_term_q + 8'd16;
            end
          end
          InferSoftmaxMax: begin
            if (s_logit_data > s_softmax_max_q) begin
              s_softmax_max_q <= s_logit_data;
            end
            if (s_softmax_index_q == 4'd11) begin
              s_softmax_index_q <= 4'd0;
              s_softmax_sum_q   <= 32'd0;
              s_infer_state_q   <= InferSoftmaxSum;
            end else begin
              s_softmax_index_q <= s_softmax_index_q + 1'b1;
            end
          end
          InferSoftmaxSum: begin
            if (s_softmax_sum_diff >= -9'sd124) begin
              s_softmax_sum_q <= s_softmax_sum_q +
                  rounding_divide_pot(apu_kws_softmax_exp_q31(-s_softmax_sum_diff[6:0]), 12);
            end
            if (s_softmax_index_q == 4'd11) begin
              s_softmax_index_q <= 4'd0;
              s_infer_state_q   <= InferSoftmaxScale;
            end else begin
              s_softmax_index_q <= s_softmax_index_q + 1'b1;
            end
          end
          InferSoftmaxScale: begin
            if (s_softmax_index_q == 0) begin
              s_softmax_scale_q <= reciprocal_q31(s_softmax_shifted_sum);
              s_softmax_bits_q  <= 6'(7'sd12 - $signed({1'b0, s_softmax_headroom}));
            end
            if (s_softmax_index_q == 4'd12) begin
              s_softmax_index_q <= 4'd0;
              s_infer_state_q   <= InferComplete;
            end else begin
              s_softmax_index_q <= s_softmax_index_q + 1'b1;
            end
          end
          InferComplete: begin
            s_result_q       <= {15'd0, s_stable_hit, s_best_score, s_best_class};
            s_result_valid_q <= 1'b1;
            s_timestamp_lo_q <= s_timestamp_q;
            s_timestamp_hi_q <= 32'd0;
            if (!counter_clear_i) begin
              s_inference_count_q <= (s_inference_count_q == 32'hffff_ffff) ?
                  s_inference_count_q : s_inference_count_q + 1'b1;
            end
            s_debounce_run_q <= s_next_debounce_run[7:0];
            s_last_class_q   <= s_best_class;
            s_last_match_q   <= s_match;
            s_stable_hit_q   <= s_stable_hit;
            if (s_hit_event) begin
              if (!counter_clear_i) begin
                s_hit_count_q <= (s_hit_count_q == 32'hffff_ffff) ?
                    s_hit_count_q : s_hit_count_q + 1'b1;
              end
              s_hit_irq_q <= 1'b1;
            end
            s_infer_state_q <= InferIdle;
            if (s_mem_job_q) begin
              s_mem_job_q  <= 1'b0;
              s_mem_done_q <= 1'b1;
            end
          end
          default: s_infer_state_q <= InferIdle;
        endcase

        if ((s_mem_job_q && s_mem_dma_done_q && !s_mem_word_valid_q) &&
            ((s_mem_received_q != 32'd32000) || s_mem_err_q)) begin
          s_mem_job_q  <= 1'b0;
          s_mem_done_q <= 1'b1;
          if (!s_mem_err_q) begin
            s_mem_err_q        <= 1'b1;
            s_mem_err_code_q   <= `APB4_APU__ERROR_CODE_STREAM_OVERRUN;
            s_mem_err_stage_q  <= `APB4_APU__ERROR_STAGE_KWS_FRONTEND;
            s_mem_err_addr_q   <= memory_address_i + s_mem_received_q;
            s_mem_err_detail_q <= 32'h0700_01ff;
          end
        end

        if ((sequencer_timeout_i != 0) && (s_front_state_q != FrontIdle) &&
            !s_front_progress && (s_front_watchdog_q >= sequencer_timeout_i - 1'b1)) begin
          s_fault_q        <= 1'b1;
          s_fault_code_q   <= `APB4_APU__ERROR_CODE_KWS_ARITHMETIC;
          s_fault_stage_q  <= `APB4_APU__ERROR_STAGE_KWS_FRONTEND;
          s_fault_detail_q <= 32'h0700_000e;
          s_stop_latched_q <= 1'b1;
          s_front_state_q  <= FrontIdle;
        end
        if ((sequencer_timeout_i != 0) && (s_infer_state_q != InferIdle) &&
            !s_infer_progress && (s_infer_watchdog_q >= sequencer_timeout_i - 1'b1)) begin
          s_fault_q        <= 1'b1;
          s_fault_code_q   <= `APB4_APU__ERROR_CODE_KWS_ARITHMETIC;
          s_fault_stage_q  <= `APB4_APU__ERROR_STAGE_KWS_INFERENCE;
          s_fault_detail_q <= 32'h0700_000e;
          s_stop_latched_q <= 1'b1;
          s_infer_state_q  <= InferIdle;
        end

        if (s_window_deadline) begin
          if (!counter_clear_i) begin
            s_overrun_count_q <= (s_overrun_count_q == 32'hffff_ffff) ?
                s_overrun_count_q : s_overrun_count_q + 1'b1;
          end
          s_overrun_sticky_q <= 1'b1;
          s_overrun_irq_q    <= 1'b1;
          s_fault_q          <= 1'b1;
          s_fault_code_q     <= `APB4_APU__ERROR_CODE_STREAM_OVERRUN;
          s_fault_stage_q    <= `APB4_APU__ERROR_STAGE_KWS_FRONTEND;
          s_fault_detail_q   <= 32'h0700_0013;
          s_stop_latched_q   <= 1'b1;
          s_front_state_q    <= FrontIdle;
          s_infer_state_q    <= InferIdle;
          s_frame_pending_q  <= 1'b0;
          s_window_pending_q <= 1'b0;
        end

        if (s_mel_overwrite) begin
          if (!counter_clear_i) begin
            s_overrun_count_q <= (s_overrun_count_q == 32'hffff_ffff) ?
                s_overrun_count_q : s_overrun_count_q + 1'b1;
          end
          s_overrun_sticky_q <= 1'b1;
          s_overrun_irq_q    <= 1'b1;
          s_fault_q          <= 1'b1;
          s_fault_code_q     <= `APB4_APU__ERROR_CODE_STREAM_OVERRUN;
          s_fault_stage_q    <= `APB4_APU__ERROR_STAGE_KWS_FRONTEND;
          s_fault_detail_q   <= 32'h0700_0013;
          s_stop_latched_q   <= 1'b1;
          s_front_state_q    <= FrontIdle;
          s_infer_state_q    <= InferIdle;
          s_frame_pending_q  <= 1'b0;
          s_window_pending_q <= 1'b0;
        end

        if (s_stream_accept && !s_stream_legal) begin
          s_front_state_q    <= FrontIdle;
          s_infer_state_q    <= InferIdle;
          s_epoch_samples_q  <= 32'd0;
          s_next_frame_q     <= 32'd480;
          s_next_window_q    <= 32'd16000;
          s_block_samples_q  <= 8'd0;
          s_block_peak_q     <= 16'd1;
          s_mel_count_q      <= 6'd0;
          s_frame_pending_q  <= 1'b0;
          s_window_pending_q <= 1'b0;
          s_debounce_run_q   <= 8'd0;
          s_last_match_q     <= 1'b0;
          s_stable_hit_q     <= 1'b0;
          s_result_valid_q   <= 1'b0;
          s_s24_pending_q    <= 1'b0;
          s_fir_write_q      <= 6'd0;
          s_fir_tap_q        <= 6'd0;
          s_fir_phase_q      <= 3'd0;
        end

        if (flush_busy_i) begin
          s_s24_pending_q <= 1'b0;
          if (!s_flush_seen_q && s_continuous_active) begin
            if (!counter_clear_i) begin
              s_overrun_count_q <= (s_overrun_count_q == 32'hffff_ffff) ?
                  s_overrun_count_q : s_overrun_count_q + 1'b1;
            end
            s_overrun_sticky_q <= 1'b1;
            s_overrun_irq_q    <= 1'b1;
            s_stop_latched_q   <= 1'b1;
            s_front_state_q    <= FrontIdle;
            s_infer_state_q    <= InferIdle;
            s_epoch_samples_q  <= 32'd0;
            s_next_frame_q     <= 32'd480;
            s_next_window_q    <= 32'd16000;
            s_block_samples_q  <= 8'd0;
            s_block_peak_q     <= 16'd1;
            s_mel_count_q      <= 6'd0;
            s_frame_pending_q  <= 1'b0;
            s_window_pending_q <= 1'b0;
            s_debounce_run_q   <= 8'd0;
            s_last_match_q     <= 1'b0;
            s_stable_hit_q     <= 1'b0;
            s_result_valid_q   <= 1'b0;
            s_fir_write_q      <= 6'd0;
            s_fir_tap_q        <= 6'd0;
            s_fir_phase_q      <= 3'd0;
          end
          s_flush_seen_q <= 1'b1;
        end

        if (scratch_access_err_i) begin
          s_fault_q        <= 1'b1;
          s_fault_code_q   <= `APB4_APU__ERROR_CODE_KWS_ARITHMETIC;
          s_fault_stage_q  <= `APB4_APU__ERROR_STAGE_KWS_INFERENCE;
          s_fault_detail_q <= 32'h0700_0018;
          s_stop_latched_q <= 1'b1;
          s_front_state_q  <= FrontIdle;
          s_infer_state_q  <= InferIdle;
        end
      end
    end
  end
endmodule
