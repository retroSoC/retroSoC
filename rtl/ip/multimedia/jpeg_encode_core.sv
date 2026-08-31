// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_encode_core (
    // verilog_format: off -- preserve command, tables, pixel input, and JPEG output columns
    input  logic              clk_i,
    input  logic              rst_n_i,
    input  logic              start_i,
    input  logic [15:0]       width_i,
    input  logic [15:0]       height_i,
    input  logic [ 1:0]       sampling_i,
    input  logic [ 2:0]       input_format_i,
    input  logic [15:0]       restart_interval_i,
    input  logic [511:0]      luma_quant_i,
    input  logic [1599:0]     luma_reciprocal_i,
    input  logic [191:0]      luma_dc_code_i,
    input  logic [ 59:0]      luma_dc_length_i,
    input  logic [4095:0]     luma_ac_code_i,
    input  logic [1279:0]     luma_ac_length_i,
    input  logic [511:0]      chroma_quant_i,
    input  logic [1599:0]     chroma_reciprocal_i,
    input  logic [191:0]      chroma_dc_code_i,
    input  logic [ 59:0]      chroma_dc_length_i,
    input  logic [4095:0]     chroma_ac_code_i,
    input  logic [1279:0]     chroma_ac_length_i,
    axi4_stream_if.sink       pixel_axis,
    axi4_stream_if.source     bitstream_axis,
    output logic              start_ready_o,
    output logic              busy_o,
    output logic              done_o,
    output logic              error_o
    // verilog_format: on
);
  typedef enum logic [3:0] {
    Idle,
    Header,
    McuStart,
    BlockStart,
    BlockWait,
    FlushRequest,
    FlushWait,
    RestartMarker,
    Eoi,
    OutputDrain,
    Done
  } state_e;

  state_e                     s_state_d;
  state_e                     s_state_q;
  logic        [   3:0]       s_state_bits_q;
  logic        [  15:0]       s_width_d;
  logic        [  15:0]       s_width_q;
  logic        [  15:0]       s_height_d;
  logic        [  15:0]       s_height_q;
  logic        [   1:0]       s_sampling_d;
  logic        [   1:0]       s_sampling_q;
  logic        [   2:0]       s_format_d;
  logic        [   2:0]       s_format_q;
  logic        [  15:0]       s_restart_interval_d;
  logic        [  15:0]       s_restart_interval_q;
  logic        [  15:0]       s_restart_cnt_d;
  logic        [  15:0]       s_restart_cnt_q;
  logic        [   2:0][23:0] s_dc_predictor_d;
  logic        [   2:0][23:0] s_dc_predictor_q;
  logic        [  11:0]       s_mcu_col_d;
  logic        [  11:0]       s_mcu_col_q;
  logic        [  11:0]       s_mcu_row_d;
  logic        [  11:0]       s_mcu_row_q;
  logic        [   2:0]       s_component_d;
  logic        [   2:0]       s_component_q;
  logic                       s_block_last_d;
  logic                       s_block_last_q;
  logic        [   2:0]       s_restart_index_d;
  logic        [   2:0]       s_restart_index_q;
  logic                       s_flush_restart_d;
  logic                       s_flush_restart_q;
  logic                       s_err_d;
  logic                       s_err_q;

  logic        [   4:0]       s_mcu_width;
  logic        [   4:0]       s_mcu_height;
  logic        [  11:0]       s_mcu_columns;
  logic        [  11:0]       s_mcu_rows;
  logic        [  15:0]       s_mcu_x_base;
  logic        [  15:0]       s_mcu_y_base;
  logic        [   4:0]       s_valid_width;
  logic        [   4:0]       s_valid_height;
  logic                       s_last_mcu;
  logic        [   2:0]       s_block_component;

  logic                       s_header_start;
  logic        [   7:0]       s_header_byte;
  logic                       s_header_valid;
  logic                       s_header_ready;
  logic                       s_header_done;
  logic                       s_header_err;
  logic                       s_builder_start;
  logic                       s_builder_start_ready;
  logic        [ 511:0]       s_builder_block;
  logic                       s_builder_block_valid;
  logic                       s_builder_block_ready;
  logic                       s_builder_block_last;
  logic                       s_builder_done;
  logic                       s_builder_err;
  logic                       s_block_encoder_start;
  logic        [ 127:0]       s_token_bits;
  logic        [  23:0]       s_token_len;
  logic        [   2:0]       s_token_cnt;
  logic                       s_token_valid;
  logic                       s_token_last;
  logic                       s_token_ready;
  logic                       s_packer_token_ready;
  logic        [ 155:0]       s_token_payload_in;
  logic        [ 155:0]       s_token_payload_out;
  logic                       s_token_spill_valid;
  logic signed [  23:0]       s_block_dc;
  logic                       s_block_result_valid;
  logic                       s_block_result_ready;
  logic                       s_block_err;
  logic                       s_packer_flush;
  logic                       s_packer_flush_ready;
  logic                       s_packer_flush_done;
  logic        [  63:0]       s_packer_data;
  logic        [   7:0]       s_packer_keep;
  logic                       s_packer_valid;
  logic                       s_packer_last;
  logic                       s_packer_ready;
  logic                       s_packer_err;
  logic        [  63:0]       s_join_data;
  logic        [   7:0]       s_join_keep;
  logic                       s_join_valid;
  logic                       s_join_ready;
  logic                       s_join_last;
  logic                       s_join_err;
  logic                       s_join_accept;
  logic        [ 511:0]       s_selected_quant;
  logic        [1599:0]       s_selected_reciprocal;
  logic        [ 191:0]       s_selected_dc_code;
  logic        [  59:0]       s_selected_dc_len;
  logic        [4095:0]       s_selected_ac_code;
  logic        [1279:0]       s_selected_ac_len;

  always_comb begin
    unique case (s_sampling_q)
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
    s_mcu_columns = 12'((s_width_q + 16'(s_mcu_width) - 1'b1) / 16'(s_mcu_width));
    s_mcu_rows = 12'((s_height_q + 16'(s_mcu_height) - 1'b1) / 16'(s_mcu_height));
    s_mcu_x_base = s_mcu_col_q * s_mcu_width;
    s_mcu_y_base = s_mcu_row_q * s_mcu_height;
    s_valid_width = ((s_width_q - s_mcu_x_base) >= 16'(s_mcu_width)) ?
                        s_mcu_width : 5'(s_width_q - s_mcu_x_base);
    s_valid_height = ((s_height_q - s_mcu_y_base) >= 16'(s_mcu_height)) ?
                         s_mcu_height : 5'(s_height_q - s_mcu_y_base);
    s_last_mcu = (s_mcu_col_q + 1'b1 == s_mcu_columns) && (s_mcu_row_q + 1'b1 == s_mcu_rows);
    if (s_sampling_q == 2'd0) begin
      s_block_component = 3'd0;
    end else if ((s_sampling_q == 2'd1) && (s_component_q != 3'd0)) begin
      s_block_component = s_component_q;
    end else if ((s_sampling_q == 2'd2) && (s_component_q >= 3'd2)) begin
      s_block_component = s_component_q - 1'b1;
    end else if ((s_sampling_q == 2'd3) && (s_component_q >= 3'd4)) begin
      s_block_component = s_component_q - 3'd3;
    end else begin
      s_block_component = 3'd0;
    end
  end

  assign s_selected_quant = (s_block_component == 3'd0) ? luma_quant_i : chroma_quant_i;
  assign s_selected_reciprocal = (s_block_component == 3'd0) ?
                                     luma_reciprocal_i : chroma_reciprocal_i;
  assign s_selected_dc_code = (s_block_component == 3'd0) ? luma_dc_code_i : chroma_dc_code_i;
  assign s_selected_dc_len = (s_block_component == 3'd0) ? luma_dc_length_i : chroma_dc_length_i;
  assign s_selected_ac_code = (s_block_component == 3'd0) ? luma_ac_code_i : chroma_ac_code_i;
  assign s_selected_ac_len = (s_block_component == 3'd0) ? luma_ac_length_i : chroma_ac_length_i;

  assign s_state_q = state_e'(s_state_bits_q);
  assign start_ready_o = s_state_q == Idle;
  assign busy_o = (s_state_q != Idle) && (s_state_q != Done);
  assign done_o = s_state_q == Done;
  assign error_o = s_err_q;
  assign s_header_start = (s_state_q == Idle) && start_i;
  assign s_builder_start = (s_state_q == McuStart) && s_builder_start_ready;
  assign s_block_encoder_start = (s_state_q == BlockStart) && s_builder_block_valid;
  assign s_builder_block_ready = s_block_encoder_start;
  assign s_block_result_ready = s_state_q == BlockWait;
  assign s_token_payload_in = {s_token_last, s_token_cnt, s_token_len, s_token_bits};
  assign s_packer_flush = (s_state_q == FlushRequest) && s_packer_flush_ready;
  assign s_join_accept = s_join_valid && s_join_ready;

  always_comb begin
    s_join_data    = 64'd0;
    s_join_keep    = 8'd0;
    s_join_valid   = 1'b0;
    s_join_last    = 1'b0;
    s_header_ready = 1'b0;
    s_packer_ready = 1'b0;
    if (s_state_q == Header) begin
      s_join_data[7:0] = s_header_byte;
      s_join_keep      = 8'h01;
      s_join_valid     = s_header_valid;
      s_header_ready   = s_join_ready;
    end else if ((s_state_q == BlockStart) || (s_state_q == BlockWait) ||
                 (s_state_q == FlushRequest) || (s_state_q == FlushWait)) begin
      s_join_data    = s_packer_data;
      s_join_keep    = s_packer_keep;
      s_join_valid   = s_packer_valid;
      s_packer_ready = s_join_ready;
    end else if (s_state_q == RestartMarker) begin
      s_join_data[15:0] = {8'(8'hd0 + s_restart_index_q), 8'hff};
      s_join_keep       = 8'h03;
      s_join_valid      = 1'b1;
    end else if (s_state_q == Eoi) begin
      s_join_data[15:0] = 16'hd9ff;
      s_join_keep       = 8'h03;
      s_join_valid      = 1'b1;
      s_join_last       = 1'b1;
    end
  end

  always_comb begin
    s_state_d            = s_state_q;
    s_width_d            = s_width_q;
    s_height_d           = s_height_q;
    s_sampling_d         = s_sampling_q;
    s_format_d           = s_format_q;
    s_restart_interval_d = s_restart_interval_q;
    s_restart_cnt_d      = s_restart_cnt_q;
    s_dc_predictor_d     = s_dc_predictor_q;
    s_mcu_col_d          = s_mcu_col_q;
    s_mcu_row_d          = s_mcu_row_q;
    s_component_d        = s_component_q;
    s_block_last_d       = s_block_last_q;
    s_restart_index_d    = s_restart_index_q;
    s_flush_restart_d    = s_flush_restart_q;
    s_err_d              = s_err_q;
    unique case (s_state_q)
      Idle: begin
        if (start_i) begin
          s_width_d = width_i;
          s_height_d = height_i;
          s_sampling_d = sampling_i;
          s_format_d = input_format_i;
          s_restart_interval_d = restart_interval_i;
          s_restart_cnt_d = 16'd0;
          s_dc_predictor_d = '0;
          s_mcu_col_d = 12'd0;
          s_mcu_row_d = 12'd0;
          s_component_d = 3'd0;
          s_restart_index_d = 3'd0;
          s_flush_restart_d = 1'b0;
          s_err_d = (width_i == 16'd0) || (height_i == 16'd0) ||
                    (width_i > 16'd2048) || (height_i > 16'd2048) ||
                    (input_format_i > 3'd4);
          s_state_d = Header;
        end
      end
      Header: begin
        if (s_header_done) begin
          s_err_d |= s_header_err;
          s_state_d = McuStart;
        end
      end
      McuStart: begin
        if (s_builder_start_ready) begin
          s_component_d = 3'd0;
          s_state_d     = BlockStart;
        end
      end
      BlockStart: begin
        if (s_block_encoder_start) begin
          s_block_last_d = s_builder_block_last;
          s_state_d      = BlockWait;
        end
      end
      BlockWait: begin
        if (s_block_result_valid) begin
          s_dc_predictor_d[s_block_component] = s_block_dc;
          s_err_d |= s_block_err;
          if (!s_block_last_q) begin
            s_component_d = s_component_q + 1'b1;
            s_state_d     = BlockStart;
          end else if (s_last_mcu) begin
            s_flush_restart_d = 1'b0;
            s_state_d         = FlushRequest;
          end else if ((s_restart_interval_q != 16'd0) &&
                       (s_restart_cnt_q + 1'b1 >= s_restart_interval_q)) begin
            s_flush_restart_d = 1'b1;
            s_state_d         = FlushRequest;
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
      FlushRequest: begin
        if (s_packer_flush_ready) begin
          s_state_d = FlushWait;
        end
      end
      FlushWait: begin
        if (s_packer_flush_done) begin
          if (s_flush_restart_q) begin
            s_state_d = RestartMarker;
          end else begin
            s_state_d = Eoi;
          end
        end
      end
      RestartMarker: begin
        if (s_join_accept) begin
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
      Eoi: begin
        if (s_join_accept) begin
          s_state_d = OutputDrain;
        end
      end
      OutputDrain: begin
        if (bitstream_axis.tvalid && bitstream_axis.tready && bitstream_axis.tlast) begin
          s_err_d |= s_builder_err || s_packer_err || s_join_err;
          s_state_d = Done;
        end
      end
      Done:    s_state_d = Idle;
      default: s_state_d = Idle;
    endcase
  end

  jpeg_header_writer u_header_writer (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .start_i           (s_header_start),
      .width_i           (width_i),
      .height_i          (height_i),
      .sampling_i        (sampling_i),
      .restart_interval_i(restart_interval_i),
      .luma_quant_i      (luma_quant_i),
      .chroma_quant_i    (chroma_quant_i),
      .start_ready_o     (),
      .byte_o            (s_header_byte),
      .byte_valid_o      (s_header_valid),
      .byte_ready_i      (s_header_ready),
      .done_o            (s_header_done),
      .error_o           (s_header_err)
  );

  jpeg_mcu_builder u_mcu_builder (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .start_i       (s_builder_start),
      .sampling_i    (s_sampling_q),
      .format_i      (s_format_q),
      .valid_width_i (s_valid_width),
      .valid_height_i(s_valid_height),
      .pixel_axis    (pixel_axis),
      .start_ready_o (s_builder_start_ready),
      .block_o       (s_builder_block),
      .block_valid_o (s_builder_block_valid),
      .block_ready_i (s_builder_block_ready),
      .block_last_o  (s_builder_block_last),
      .done_o        (s_builder_done),
      .error_o       (s_builder_err)
  );

  jpeg_block_encoder u_block_encoder (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .start_i       (s_block_encoder_start),
      .block_i       (s_builder_block),
      .previous_dc_i (s_dc_predictor_q[s_block_component]),
      .quant_i       (s_selected_quant),
      .reciprocal_i  (s_selected_reciprocal),
      .dc_code_i     (s_selected_dc_code),
      .dc_length_i   (s_selected_dc_len),
      .ac_code_i     (s_selected_ac_code),
      .ac_length_i   (s_selected_ac_len),
      .start_ready_o (),
      .token_bits_o  (s_token_bits),
      .token_length_o(s_token_len),
      .token_count_o (s_token_cnt),
      .token_valid_o (s_token_valid),
      .token_last_o  (s_token_last),
      .token_ready_i (s_token_ready),
      .dc_o          (s_block_dc),
      .result_valid_o(s_block_result_valid),
      .result_ready_i(s_block_result_ready),
      .error_o       (s_block_err)
  );

  jpeg_bit_packer u_bit_packer (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .token_bits_i  (s_token_payload_out[127:0]),
      .token_length_i(s_token_payload_out[151:128]),
      .token_count_i (s_token_payload_out[154:152]),
      .token_valid_i (s_token_spill_valid),
      .token_ready_o (s_packer_token_ready),
      .flush_i       (s_packer_flush),
      .flush_ready_o (s_packer_flush_ready),
      .flush_done_o  (s_packer_flush_done),
      .byte_data_o   (s_packer_data),
      .byte_keep_o   (s_packer_keep),
      .byte_valid_o  (s_packer_valid),
      .byte_last_o   (s_packer_last),
      .byte_ready_i  (s_packer_ready),
      .error_o       (s_packer_err)
  );

  spill_register #(
      .DATA_WIDTH(156),
      .BYPASS    (1'b0)
  ) u_token_spill (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(1'b0),
      .valid_i(s_token_valid),
      .ready_o(s_token_ready),
      .data_i (s_token_payload_in),
      .valid_o(s_token_spill_valid),
      .ready_i(s_packer_token_ready),
      .data_o (s_token_payload_out)
  );

  jpeg_byte_joiner u_byte_joiner (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .input_data_i (s_join_data),
      .input_keep_i (s_join_keep),
      .input_valid_i(s_join_valid),
      .input_ready_o(s_join_ready),
      .input_last_i (s_join_last),
      .output_axis  (bitstream_axis),
      .error_o      (s_join_err)
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
      .DATA_WIDTH(16)
  ) u_width_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_width_d),
      .dat_o  (s_width_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_height_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_height_d),
      .dat_o  (s_height_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_sampling_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sampling_d),
      .dat_o  (s_sampling_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_format_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_format_d),
      .dat_o  (s_format_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_restart_interval_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_restart_interval_d),
      .dat_o  (s_restart_interval_q)
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
      .DATA_WIDTH(3 * 24)
  ) u_dc_predictor_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dc_predictor_d),
      .dat_o  (s_dc_predictor_q)
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
  ) u_component_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_component_d),
      .dat_o  (s_component_q)
  );
  dffr u_block_last_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_block_last_d),
      .dat_o  (s_block_last_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_restart_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_restart_index_d),
      .dat_o  (s_restart_index_q)
  );
  dffr u_flush_restart_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_flush_restart_d),
      .dat_o  (s_flush_restart_q)
  );
  dffr u_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
endmodule
