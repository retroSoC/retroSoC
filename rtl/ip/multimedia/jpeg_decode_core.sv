// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_decode_core #(
    parameter bit ExternalCoefficientEngine = 1'b0
) (
    // verilog_format: off -- preserve command, JPEG input, pixel output, and result columns
    input  logic              clk_i,
    input  logic              rst_n_i,
    input  logic              start_i,
    input  logic [ 2:0]       output_format_i,
    output logic              coefficient_start_o,
    output logic [1535:0]     coefficient_block_o,
    output logic [ 511:0]     coefficient_quant_o,
    output logic [1599:0]     coefficient_reciprocal_o,
    input  logic              coefficient_start_ready_i,
    input  logic [1535:0]     coefficient_result_i,
    input  logic              coefficient_result_valid_i,
    output logic              coefficient_result_ready_o,
    input  logic              coefficient_table_err_i,
    input  logic              coefficient_overflow_i,
    axi4_stream_if.sink       bitstream_axis,
    axi4_stream_if.source     pixel_axis,
    output logic              start_ready_o,
    output logic              busy_o,
    output logic              done_o,
    output logic [15:0]       width_o,
    output logic [15:0]       height_o,
    output logic [ 1:0]       sampling_o,
    output logic              error_o,
    output logic [ 4:0]       error_code_o
    // verilog_format: on
);
  typedef enum logic [3:0] {
    Idle,
    Parse,
    CacheLumaStart,
    CacheLumaWait,
    CacheChromaStart,
    CacheChromaWait,
    McuStart,
    BlockStart,
    BlockWait,
    McuOutput,
    RestartWait,
    EoiWait,
    Done,
    Error
  } state_e;

  state_e                     s_state_d;
  state_e                     s_state_q;
  logic        [   3:0]       s_state_bits_q;
  logic        [   2:0]       s_output_format_d;
  logic        [   2:0]       s_output_format_q;
  logic        [  11:0]       s_mcu_col_d;
  logic        [  11:0]       s_mcu_col_q;
  logic        [  11:0]       s_mcu_row_d;
  logic        [  11:0]       s_mcu_row_q;
  logic        [   2:0]       s_block_index_d;
  logic        [   2:0]       s_block_index_q;
  logic        [  15:0]       s_restart_cnt_d;
  logic        [  15:0]       s_restart_cnt_q;
  logic        [   2:0]       s_restart_index_d;
  logic        [   2:0]       s_restart_index_q;
  logic        [   2:0][23:0] s_dc_predictor_d;
  logic        [   2:0][23:0] s_dc_predictor_q;
  logic                       s_err_d;
  logic                       s_err_q;
  logic        [   4:0]       s_err_code_d;
  logic        [   4:0]       s_err_code_q;

  logic        [   7:0]       s_input_byte;
  logic                       s_input_byte_valid;
  logic                       s_input_byte_ready;
  logic                       s_input_byte_last;
  logic                       s_unpack_err;
  logic                       s_parser_start;
  logic                       s_parser_byte_ready;
  logic        [   1:0]       s_parser_table_context;
  logic        [   3:0]       s_parser_table_kind;
  logic        [   7:0]       s_parser_table_index;
  logic        [  31:0]       s_parser_table_data;
  logic                       s_parser_table_write;
  logic                       s_parser_table_commit;
  logic                       s_parser_header_valid;
  logic                       s_parser_header_ready;
  logic                       s_parser_entropy;
  logic        [  15:0]       s_width;
  logic        [  15:0]       s_height;
  logic        [   1:0]       s_sampling;
  logic        [   1:0]       s_component_cnt;
  logic        [  23:0]       s_component_id;
  logic        [  23:0]       s_component_factor;
  logic        [   5:0]       s_quant_table;
  logic        [   5:0]       s_dc_table;
  logic        [   5:0]       s_ac_table;
  logic        [  15:0]       s_restart_interval;
  logic                       s_parser_err;
  logic        [   4:0]       s_parser_err_code;

  logic        [  31:0]       s_table_portal_data;
  logic        [  31:0]       s_table_portal_status;
  logic                       s_table_lookup;
  logic        [   1:0]       s_table_lookup_context;
  logic        [   3:0]       s_table_lookup_kind;
  logic        [   7:0]       s_table_lookup_index;
  logic        [  31:0]       s_table_lookup_data;
  logic                       s_table_lookup_valid;
  logic                       s_table_lookup_err;
  logic                       s_cache_start;
  logic        [   1:0]       s_cache_quant_id;
  logic        [   1:0]       s_cache_dc_id;
  logic        [   1:0]       s_cache_ac_id;
  logic        [   3:0]       s_cache_entry_kind;
  logic        [   7:0]       s_cache_entry_index;
  logic        [  31:0]       s_cache_entry_data;
  logic        [  24:0]       s_cache_entry_reciprocal;
  logic                       s_cache_entry_valid;
  logic                       s_cache_valid;
  logic                       s_cache_ready;
  logic                       s_cache_err;
  logic        [ 511:0]       s_luma_quant_q;
  logic        [1599:0]       s_luma_reciprocal_q;
  logic        [ 191:0]       s_luma_dc_code_q;
  logic        [  59:0]       s_luma_dc_len_q;
  logic        [4095:0]       s_luma_ac_code_q;
  logic        [1279:0]       s_luma_ac_len_q;
  logic        [ 511:0]       s_chroma_quant_q;
  logic        [1599:0]       s_chroma_reciprocal_q;
  logic        [ 191:0]       s_chroma_dc_code_q;
  logic        [  59:0]       s_chroma_dc_len_q;
  logic        [4095:0]       s_chroma_ac_code_q;
  logic        [1279:0]       s_chroma_ac_len_q;

  logic        [  31:0]       s_bit_window;
  logic        [   5:0]       s_bit_count;
  logic        [   5:0]       s_bit_consume;
  logic                       s_bit_consume_valid;
  logic                       s_bit_align;
  logic                       s_bit_byte_ready;
  logic                       s_marker_valid;
  logic        [   7:0]       s_marker;
  logic                       s_marker_ready;
  logic                       s_bit_err;

  logic        [   4:0]       s_mcu_width;
  logic        [   4:0]       s_mcu_height;
  logic        [  11:0]       s_mcu_columns;
  logic        [  11:0]       s_mcu_rows;
  logic        [  15:0]       s_mcu_x_base;
  logic        [  15:0]       s_mcu_y_base;
  logic        [   4:0]       s_valid_width;
  logic        [   4:0]       s_valid_height;
  logic        [   2:0]       s_expected_blocks;
  logic        [   2:0]       s_block_component;
  logic                       s_last_mcu;
  logic        [ 511:0]       s_selected_quant;
  logic        [1599:0]       s_selected_reciprocal;
  logic        [ 191:0]       s_selected_dc_code;
  logic        [  59:0]       s_selected_dc_len;
  logic        [4095:0]       s_selected_ac_code;
  logic        [1279:0]       s_selected_ac_len;
  logic                       s_block_start;
  logic        [ 511:0]       s_decoded_block;
  logic signed [  23:0]       s_decoded_dc;
  logic                       s_block_valid;
  logic                       s_block_ready;
  logic                       s_block_err;
  logic                       s_reconstructor_start;
  logic                       s_reconstructor_block_ready;
  logic                       s_reconstructor_done;
  logic                       s_reconstructor_err;

  always_comb begin
    unique case (s_sampling)
      2'd0, 2'd1: begin
        s_mcu_width  = 5'd8;
        s_mcu_height = 5'd8;
      end
      2'd2: begin
        s_mcu_width  = 5'd16;
        s_mcu_height = 5'd8;
      end
      default: begin
        s_mcu_width  = 5'd16;
        s_mcu_height = 5'd16;
      end
    endcase
    s_mcu_columns = 12'((s_width + 16'(s_mcu_width) - 1'b1) / 16'(s_mcu_width));
    s_mcu_rows = 12'((s_height + 16'(s_mcu_height) - 1'b1) / 16'(s_mcu_height));
    s_mcu_x_base = s_mcu_col_q * s_mcu_width;
    s_mcu_y_base = s_mcu_row_q * s_mcu_height;
    s_valid_width = ((s_width - s_mcu_x_base) >= 16'(s_mcu_width)) ?
                        s_mcu_width : 5'(s_width - s_mcu_x_base);
    s_valid_height = ((s_height - s_mcu_y_base) >= 16'(s_mcu_height)) ?
                         s_mcu_height : 5'(s_height - s_mcu_y_base);
    unique case (s_sampling)
      2'd0:    s_expected_blocks = 3'd1;
      2'd1:    s_expected_blocks = 3'd3;
      2'd2:    s_expected_blocks = 3'd4;
      default: s_expected_blocks = 3'd6;
    endcase
    if (s_sampling == 2'd0) begin
      s_block_component = 3'd0;
    end else if ((s_sampling == 2'd1) && (s_block_index_q != 3'd0)) begin
      s_block_component = s_block_index_q;
    end else if ((s_sampling == 2'd2) && (s_block_index_q >= 3'd2)) begin
      s_block_component = s_block_index_q - 1'b1;
    end else if ((s_sampling == 2'd3) && (s_block_index_q >= 3'd4)) begin
      s_block_component = s_block_index_q - 3'd3;
    end else begin
      s_block_component = 3'd0;
    end
    s_last_mcu = (s_mcu_col_q + 1'b1 == s_mcu_columns) && (s_mcu_row_q + 1'b1 == s_mcu_rows);
  end

  assign s_selected_quant = (s_block_component == 3'd0) ? s_luma_quant_q : s_chroma_quant_q;
  assign s_selected_reciprocal = (s_block_component == 3'd0) ?
                                     s_luma_reciprocal_q : s_chroma_reciprocal_q;
  assign coefficient_quant_o = s_selected_quant;
  assign coefficient_reciprocal_o = s_selected_reciprocal;
  assign s_selected_dc_code = (s_block_component == 3'd0) ? s_luma_dc_code_q : s_chroma_dc_code_q;
  assign s_selected_dc_len = (s_block_component == 3'd0) ? s_luma_dc_len_q : s_chroma_dc_len_q;
  assign s_selected_ac_code = (s_block_component == 3'd0) ? s_luma_ac_code_q : s_chroma_ac_code_q;
  assign s_selected_ac_len = (s_block_component == 3'd0) ? s_luma_ac_len_q : s_chroma_ac_len_q;

  assign s_state_q = state_e'(s_state_bits_q);
  assign start_ready_o = s_state_q == Idle;
  assign busy_o = (s_state_q != Idle) && (s_state_q != Done) && (s_state_q != Error);
  assign done_o = s_state_q == Done;
  assign width_o = s_width;
  assign height_o = s_height;
  assign sampling_o = s_sampling;
  assign error_o = s_err_q;
  assign error_code_o = s_err_code_q;
  assign s_parser_start = (s_state_q == Idle) && start_i;
  assign s_input_byte_ready = s_parser_entropy ? s_bit_byte_ready : s_parser_byte_ready;
  assign s_parser_header_ready = ((s_state_q == CacheLumaWait) && s_cache_valid &&
                                  (s_component_cnt == 2'd1)) ||
                                 ((s_state_q == CacheChromaWait) && s_cache_valid);
  assign s_cache_start = (s_state_q == CacheLumaStart) || (s_state_q == CacheChromaStart);
  assign s_cache_quant_id = (s_state_q == CacheLumaStart) ? s_quant_table[1:0] : s_quant_table[3:2];
  assign s_cache_dc_id = (s_state_q == CacheLumaStart) ? s_dc_table[1:0] : s_dc_table[3:2];
  assign s_cache_ac_id = (s_state_q == CacheLumaStart) ? s_ac_table[1:0] : s_ac_table[3:2];
  assign s_cache_ready = (s_state_q == CacheLumaWait) || (s_state_q == CacheChromaWait);
  assign s_bit_align = (s_state_q == RestartWait) || (s_state_q == EoiWait);
  assign s_marker_ready = ((s_state_q == RestartWait) && s_marker_valid &&
                           (s_marker == (8'hd0 + {5'd0, s_restart_index_q}))) ||
                          ((s_state_q == EoiWait) && s_marker_valid && (s_marker == 8'hd9));
  assign s_reconstructor_start = s_state_q == McuStart;
  assign s_block_start = s_state_q == BlockStart;
  assign s_block_ready = (s_state_q == BlockWait) && s_reconstructor_block_ready;

  always_comb begin
    s_state_d         = s_state_q;
    s_output_format_d = s_output_format_q;
    s_mcu_col_d       = s_mcu_col_q;
    s_mcu_row_d       = s_mcu_row_q;
    s_block_index_d   = s_block_index_q;
    s_restart_cnt_d   = s_restart_cnt_q;
    s_restart_index_d = s_restart_index_q;
    s_dc_predictor_d  = s_dc_predictor_q;
    s_err_d           = s_err_q;
    s_err_code_d      = s_err_code_q;
    unique case (s_state_q)
      Idle: begin
        if (start_i) begin
          s_output_format_d = output_format_i;
          s_mcu_col_d       = 12'd0;
          s_mcu_row_d       = 12'd0;
          s_block_index_d   = 3'd0;
          s_restart_cnt_d   = 16'd0;
          s_restart_index_d = 3'd0;
          s_dc_predictor_d  = '0;
          s_err_d           = output_format_i > 3'd4;
          s_err_code_d      = 5'd0;
          s_state_d         = Parse;
        end
      end
      Parse: begin
        if (s_parser_err || s_unpack_err) begin
          s_err_d      = 1'b1;
          s_err_code_d = s_parser_err ? s_parser_err_code : 5'd10;
          s_state_d    = Error;
        end else if (s_parser_header_valid) begin
          if ((s_width == 16'd0) || (s_height == 16'd0) || (s_width > 16'd2048) ||
              (s_height > 16'd2048) ||
              ((s_component_cnt == 2'd3) &&
               ((s_quant_table[5:4] != s_quant_table[3:2]) ||
                (s_dc_table[5:4] != s_dc_table[3:2]) ||
                (s_ac_table[5:4] != s_ac_table[3:2])))) begin
            s_err_d      = 1'b1;
            s_err_code_d = 5'd7;
            s_state_d    = Error;
          end else begin
            s_state_d = CacheLumaStart;
          end
        end
      end
      CacheLumaStart:   s_state_d = CacheLumaWait;
      CacheLumaWait: begin
        if (s_cache_valid) begin
          if (s_cache_err) begin
            s_err_d      = 1'b1;
            s_err_code_d = 5'd3;
            s_state_d    = Error;
          end else if (s_component_cnt == 2'd1) begin
            s_state_d = McuStart;
          end else begin
            s_state_d = CacheChromaStart;
          end
        end
      end
      CacheChromaStart: s_state_d = CacheChromaWait;
      CacheChromaWait: begin
        if (s_cache_valid) begin
          if (s_cache_err) begin
            s_err_d      = 1'b1;
            s_err_code_d = 5'd3;
            s_state_d    = Error;
          end else begin
            s_state_d = McuStart;
          end
        end
      end
      McuStart: begin
        s_block_index_d = 3'd0;
        s_state_d       = BlockStart;
      end
      BlockStart: begin
        if (s_block_start) begin
          s_state_d = BlockWait;
        end
      end
      BlockWait: begin
        if (s_block_valid && s_reconstructor_block_ready) begin
          s_dc_predictor_d[s_block_component] = s_decoded_dc;
          if (s_block_err) begin
            s_err_d      = 1'b1;
            s_err_code_d = 5'd9;
            s_state_d    = Error;
          end else if (s_block_index_q + 1'b1 == s_expected_blocks) begin
            s_state_d = McuOutput;
          end else begin
            s_block_index_d = s_block_index_q + 1'b1;
            s_state_d       = BlockStart;
          end
        end
      end
      McuOutput: begin
        if (s_reconstructor_done) begin
          if (s_reconstructor_err) begin
            s_err_d      = 1'b1;
            s_err_code_d = 5'd18;
            s_state_d    = Error;
          end else if (s_last_mcu) begin
            s_state_d = EoiWait;
          end else if ((s_restart_interval != 16'd0) &&
                       (s_restart_cnt_q + 1'b1 >= s_restart_interval)) begin
            s_state_d = RestartWait;
          end else begin
            s_restart_cnt_d = s_restart_cnt_q + 1'b1;
            if (s_mcu_col_q + 1'b1 == s_mcu_columns) begin
              s_mcu_col_d = 12'd0;
              s_mcu_row_d = s_mcu_row_q + 1'b1;
            end else begin
              s_mcu_col_d = s_mcu_col_q + 1'b1;
            end
            s_state_d = McuStart;
          end
        end
      end
      RestartWait: begin
        if (s_marker_valid) begin
          if (s_marker != (8'hd0 + {5'd0, s_restart_index_q})) begin
            s_err_d      = 1'b1;
            s_err_code_d = 5'd11;
            s_state_d    = Error;
          end else begin
            s_dc_predictor_d  = '0;
            s_restart_cnt_d   = 16'd0;
            s_restart_index_d = s_restart_index_q + 1'b1;
            if (s_mcu_col_q + 1'b1 == s_mcu_columns) begin
              s_mcu_col_d = 12'd0;
              s_mcu_row_d = s_mcu_row_q + 1'b1;
            end else begin
              s_mcu_col_d = s_mcu_col_q + 1'b1;
            end
            s_state_d = McuStart;
          end
        end
      end
      EoiWait: begin
        if (s_marker_valid) begin
          if (s_marker != 8'hd9) begin
            s_err_d      = 1'b1;
            s_err_code_d = 5'd4;
            s_state_d    = Error;
          end else begin
            s_err_d |= s_bit_err;
            s_state_d = Done;
          end
        end
      end
      Done:             s_state_d = Idle;
      Error:            s_state_d = Error;
      default:          s_state_d = Error;
    endcase
  end

  jpeg_byte_unpacker u_byte_unpacker (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .input_axis  (bitstream_axis),
      .byte_o      (s_input_byte),
      .byte_valid_o(s_input_byte_valid),
      .byte_ready_i(s_input_byte_ready),
      .byte_last_o (s_input_byte_last),
      .error_o     (s_unpack_err)
  );

  jpeg_marker_parser u_marker_parser (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .start_i           (s_parser_start),
      .table_context_i   (2'd0),
      .byte_i            (s_input_byte),
      .byte_valid_i      (s_input_byte_valid && !s_parser_entropy),
      .byte_ready_o      (s_parser_byte_ready),
      .table_context_o   (s_parser_table_context),
      .table_kind_o      (s_parser_table_kind),
      .table_index_o     (s_parser_table_index),
      .table_data_o      (s_parser_table_data),
      .table_write_o     (s_parser_table_write),
      .table_commit_o    (s_parser_table_commit),
      .header_valid_o    (s_parser_header_valid),
      .header_ready_i    (s_parser_header_ready),
      .entropy_o         (s_parser_entropy),
      .width_o           (s_width),
      .height_o          (s_height),
      .sampling_o        (s_sampling),
      .component_count_o (s_component_cnt),
      .component_id_o    (s_component_id),
      .component_factor_o(s_component_factor),
      .quant_table_o     (s_quant_table),
      .dc_table_o        (s_dc_table),
      .ac_table_o        (s_ac_table),
      .restart_interval_o(s_restart_interval),
      .marker_count_o    (),
      .error_o           (s_parser_err),
      .error_code_o      (s_parser_err_code)
  );

  jpeg_table_store u_table_store (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .portal_context_i   (s_parser_table_context),
      .portal_kind_i      (s_parser_table_kind),
      .portal_index_i     (s_parser_table_index),
      .portal_write_data_i(s_parser_table_data),
      .portal_write_i     (s_parser_table_write),
      .portal_commit_i    (s_parser_table_commit),
      .portal_default_i   (1'b0),
      .portal_clear_i     (s_parser_start),
      .portal_read_data_o (s_table_portal_data),
      .portal_status_o    (s_table_portal_status),
      .lookup_i           (s_table_lookup),
      .lookup_context_i   (s_table_lookup_context),
      .lookup_kind_i      (s_table_lookup_kind),
      .lookup_index_i     (s_table_lookup_index),
      .lookup_data_o      (s_table_lookup_data),
      .lookup_valid_o     (s_table_lookup_valid),
      .lookup_err_o       (s_table_lookup_err)
  );

  jpeg_table_cache u_table_cache (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .start_i           (s_cache_start),
      .context_i         (2'd0),
      .quant_id_i        (s_cache_quant_id),
      .dc_id_i           (s_cache_dc_id),
      .ac_id_i           (s_cache_ac_id),
      .start_ready_o     (),
      .lookup_o          (s_table_lookup),
      .lookup_context_o  (s_table_lookup_context),
      .lookup_kind_o     (s_table_lookup_kind),
      .lookup_index_o    (s_table_lookup_index),
      .lookup_data_i     (s_table_lookup_data),
      .lookup_valid_i    (s_table_lookup_valid),
      .lookup_err_i      (s_table_lookup_err),
      .entry_kind_o      (s_cache_entry_kind),
      .entry_index_o     (s_cache_entry_index),
      .entry_data_o      (s_cache_entry_data),
      .entry_reciprocal_o(s_cache_entry_reciprocal),
      .entry_valid_o     (s_cache_entry_valid),
      .entry_ready_i     (1'b1),
      .result_valid_o    (s_cache_valid),
      .result_ready_i    (s_cache_ready),
      .error_o           (s_cache_err)
  );

  jpeg_table_register_bank u_luma_table_register_bank (
      .clk_i             (clk_i),
      .write_i           (s_cache_entry_valid && (s_state_q == CacheLumaWait)),
      .entry_kind_i      (s_cache_entry_kind),
      .entry_index_i     (s_cache_entry_index),
      .entry_data_i      (s_cache_entry_data),
      .entry_reciprocal_i(s_cache_entry_reciprocal),
      .quant_o           (s_luma_quant_q),
      .reciprocal_o      (s_luma_reciprocal_q),
      .dc_code_o         (s_luma_dc_code_q),
      .dc_length_o       (s_luma_dc_len_q),
      .ac_code_o         (s_luma_ac_code_q),
      .ac_length_o       (s_luma_ac_len_q)
  );

  jpeg_table_register_bank u_chroma_table_register_bank (
      .clk_i             (clk_i),
      .write_i           (s_cache_entry_valid && (s_state_q == CacheChromaWait)),
      .entry_kind_i      (s_cache_entry_kind),
      .entry_index_i     (s_cache_entry_index),
      .entry_data_i      (s_cache_entry_data),
      .entry_reciprocal_i(s_cache_entry_reciprocal),
      .quant_o           (s_chroma_quant_q),
      .reciprocal_o      (s_chroma_reciprocal_q),
      .dc_code_o         (s_chroma_dc_code_q),
      .dc_length_o       (s_chroma_dc_len_q),
      .ac_code_o         (s_chroma_ac_code_q),
      .ac_length_o       (s_chroma_ac_len_q)
  );

  jpeg_bit_reader u_bit_reader (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .byte_i             (s_input_byte),
      .byte_valid_i       (s_input_byte_valid && s_parser_entropy),
      .byte_ready_o       (s_bit_byte_ready),
      .byte_last_i        (s_input_byte_last),
      .bit_consume_i      (s_bit_consume),
      .bit_consume_valid_i(s_bit_consume_valid),
      .align_i            (s_bit_align),
      .bit_window_o       (s_bit_window),
      .bit_count_o        (s_bit_count),
      .marker_valid_o     (s_marker_valid),
      .marker_o           (s_marker),
      .marker_ready_i     (s_marker_ready),
      .error_o            (s_bit_err)
  );

  jpeg_block_decoder #(
      .ExternalCoefficientEngine(ExternalCoefficientEngine)
  ) u_block_decoder (
      .clk_i                     (clk_i),
      .rst_n_i                   (rst_n_i),
      .start_i                   (s_block_start),
      .previous_dc_i             (s_dc_predictor_q[s_block_component]),
      .quant_i                   (s_selected_quant),
      .reciprocal_i              (s_selected_reciprocal),
      .dc_code_i                 (s_selected_dc_code),
      .dc_length_i               (s_selected_dc_len),
      .ac_code_i                 (s_selected_ac_code),
      .ac_length_i               (s_selected_ac_len),
      .bit_window_i              (s_bit_window),
      .bit_count_i               (s_bit_count),
      .coefficient_start_o       (coefficient_start_o),
      .coefficient_block_o       (coefficient_block_o),
      .coefficient_start_ready_i (coefficient_start_ready_i),
      .coefficient_result_i      (coefficient_result_i),
      .coefficient_result_valid_i(coefficient_result_valid_i),
      .coefficient_result_ready_o(coefficient_result_ready_o),
      .coefficient_table_err_i   (coefficient_table_err_i),
      .coefficient_overflow_i    (coefficient_overflow_i),
      .bit_consume_o             (s_bit_consume),
      .bit_consume_valid_o       (s_bit_consume_valid),
      .start_ready_o             (),
      .block_o                   (s_decoded_block),
      .dc_o                      (s_decoded_dc),
      .result_valid_o            (s_block_valid),
      .result_ready_i            (s_block_ready),
      .error_o                   (s_block_err)
  );

  jpeg_mcu_reconstructor u_mcu_reconstructor (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .start_i       (s_reconstructor_start),
      .sampling_i    (s_sampling),
      .format_i      (s_output_format_q),
      .valid_width_i (s_valid_width),
      .valid_height_i(s_valid_height),
      .block_i       (s_decoded_block),
      .block_valid_i (s_block_valid),
      .block_ready_o (s_reconstructor_block_ready),
      .start_ready_o (),
      .pixel_axis    (pixel_axis),
      .done_o        (s_reconstructor_done),
      .error_o       (s_reconstructor_err)
  );

  dffr #(
      .DATA_WIDTH(4)
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_output_format_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_output_format_d),
      .dat_o  (s_output_format_q)
  );
  dffr #(
      .DATA_WIDTH(12)
  ) u_mcu_col_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mcu_col_d),
      .dat_o  (s_mcu_col_q)
  );
  dffr #(
      .DATA_WIDTH(12)
  ) u_mcu_row_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mcu_row_d),
      .dat_o  (s_mcu_row_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_block_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_block_index_d),
      .dat_o  (s_block_index_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_restart_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_restart_cnt_d),
      .dat_o  (s_restart_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_restart_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_restart_index_d),
      .dat_o  (s_restart_index_q)
  );
  dffr #(
      .DATA_WIDTH(3 * 24)
  ) u_dc_predictor_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dc_predictor_d),
      .dat_o  (s_dc_predictor_q)
  );
  dffr u_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_err_code_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_code_d),
      .dat_o  (s_err_code_q)
  );
endmodule
