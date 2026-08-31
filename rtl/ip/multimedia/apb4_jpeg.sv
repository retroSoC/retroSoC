// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

`include "jpeg_define.svh"

module apb4_jpeg (
    // verilog_format: off -- preserve clock, lifecycle, APB, AXI, and interrupt columns
    input  logic          clk_i,
    input  logic          rst_n_i,
    input  logic          quiesce_i,
    input  logic          resource_reset_i,
    apb4_if.slave         apb4,
    axi4_if.master        axi4,
    output logic          idle_o,
    output logic          irq_o
    // verilog_format: on
);
  typedef enum logic [3:0] {
    Idle,
    EncodeCacheLumaStart,
    EncodeCacheLumaWait,
    EncodeCacheChromaStart,
    EncodeCacheChromaWait,
    EncodeStart,
    EncodeRun,
    DecodeStart,
    DecodeRun,
    AbortDrain,
    RingFetchStart,
    RingFetchRun,
    RingParse,
    RingWriteStart,
    RingWriteRun
  } state_e;

  state_e          s_state_d;
  state_e          s_state_q;
  logic   [   3:0] s_state_bits_q;
  logic            s_engine_rst_n;
  logic            s_core_rst_n;
  logic            s_reg_start;
  logic            s_reg_abort;
  logic            s_reg_soft_reset;
  logic            s_reg_ring_kick;
  logic   [  31:0] s_reg_job_config;
  logic   [  31:0] s_reg_image_size;
  logic   [  31:0] s_reg_input_format;
  logic   [  31:0] s_reg_output_format;
  logic   [  31:0] s_reg_encode_config;
  logic   [  31:0] s_reg_restart_interval;
  logic   [  31:0] s_reg_bitstream_addr;
  logic   [  31:0] s_reg_bitstream_size;
  logic   [  31:0] s_reg_plane0_addr;
  logic   [  31:0] s_reg_plane0_stride;
  logic   [  31:0] s_reg_plane1_addr;
  logic   [  31:0] s_reg_plane1_stride;
  logic   [  31:0] s_reg_plane2_addr;
  logic   [  31:0] s_reg_plane2_stride;
  logic   [  31:0] s_reg_metadata_addr;
  logic   [  31:0] s_reg_metadata_length;
  logic   [  31:0] s_job_config;
  logic   [  31:0] s_image_size;
  logic   [  31:0] s_input_format;
  logic   [  31:0] s_output_format;
  logic   [  31:0] s_encode_config;
  logic   [  31:0] s_restart_interval;
  logic   [  31:0] s_bitstream_addr;
  logic   [  31:0] s_bitstream_size;
  logic   [  31:0] s_plane0_addr;
  logic   [  31:0] s_plane0_stride;
  logic   [  31:0] s_plane1_addr;
  logic   [  31:0] s_plane1_stride;
  logic   [  31:0] s_plane2_addr;
  logic   [  31:0] s_plane2_stride;
  logic   [  31:0] s_metadata_addr;
  logic   [  31:0] s_metadata_length;
  logic   [  31:0] s_ring_base;
  logic   [  31:0] s_ring_size;
  logic   [  31:0] s_ring_tail;
  logic   [  31:0] s_ring_control;
  logic   [  31:0] s_irq_coalesce;
  logic   [   1:0] s_table_context;
  logic   [   3:0] s_table_kind;
  logic   [   7:0] s_table_index;
  logic   [  31:0] s_table_write_data;
  logic            s_table_write;
  logic            s_table_commit;
  logic            s_table_default;
  logic            s_table_clear;
  logic            s_perf_enable;
  logic            s_perf_clear;
  logic   [  31:0] s_table_read_data;
  logic   [  31:0] s_table_status;

  logic            s_cache_start;
  logic   [   1:0] s_cache_quant_id;
  logic   [   1:0] s_cache_dc_id;
  logic   [   1:0] s_cache_ac_id;
  logic            s_table_lookup;
  logic   [   1:0] s_table_lookup_context;
  logic   [   3:0] s_table_lookup_kind;
  logic   [   7:0] s_table_lookup_index;
  logic   [  31:0] s_table_lookup_data;
  logic            s_table_lookup_valid;
  logic            s_table_lookup_err;
  logic   [ 511:0] s_cache_quant;
  logic   [1599:0] s_cache_reciprocal;
  logic   [ 191:0] s_cache_dc_code;
  logic   [  59:0] s_cache_dc_len;
  logic   [4095:0] s_cache_ac_code;
  logic   [1279:0] s_cache_ac_len;
  logic            s_cache_valid;
  logic            s_cache_ready;
  logic            s_cache_err;
  logic   [ 511:0] s_luma_quant_d;
  logic   [ 511:0] s_luma_quant_q;
  logic   [1599:0] s_luma_reciprocal_d;
  logic   [1599:0] s_luma_reciprocal_q;
  logic   [ 191:0] s_luma_dc_code_d;
  logic   [ 191:0] s_luma_dc_code_q;
  logic   [  59:0] s_luma_dc_len_d;
  logic   [  59:0] s_luma_dc_len_q;
  logic   [4095:0] s_luma_ac_code_d;
  logic   [4095:0] s_luma_ac_code_q;
  logic   [1279:0] s_luma_ac_len_d;
  logic   [1279:0] s_luma_ac_len_q;
  logic   [ 511:0] s_chroma_quant_d;
  logic   [ 511:0] s_chroma_quant_q;
  logic   [1599:0] s_chroma_reciprocal_d;
  logic   [1599:0] s_chroma_reciprocal_q;
  logic   [ 191:0] s_chroma_dc_code_d;
  logic   [ 191:0] s_chroma_dc_code_q;
  logic   [  59:0] s_chroma_dc_len_d;
  logic   [  59:0] s_chroma_dc_len_q;
  logic   [4095:0] s_chroma_ac_code_d;
  logic   [4095:0] s_chroma_ac_code_q;
  logic   [1279:0] s_chroma_ac_len_d;
  logic   [1279:0] s_chroma_ac_len_q;

  axi4_stream_if #(
      .DATA_WIDTH(64)
  ) u_dma_read_axis (
      .aclk   (clk_i),
      .aresetn(s_engine_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(64)
  ) u_dma_write_axis (
      .aclk   (clk_i),
      .aresetn(s_engine_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(64)
  ) u_encode_pixel_axis (
      .aclk   (clk_i),
      .aresetn(s_engine_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(64)
  ) u_encode_bitstream_axis (
      .aclk   (clk_i),
      .aresetn(s_engine_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(64)
  ) u_decode_bitstream_axis (
      .aclk   (clk_i),
      .aresetn(s_engine_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(64)
  ) u_decode_pixel_axis (
      .aclk   (clk_i),
      .aresetn(s_engine_rst_n)
  );

  logic          s_dma_read_start;
  logic [  31:0] s_dma_read_addr;
  logic [  31:0] s_dma_read_line_bytes;
  logic [  31:0] s_dma_read_stride;
  logic [  15:0] s_dma_read_lines;
  logic          s_dma_read_busy;
  logic          s_dma_read_done;
  logic          s_dma_write_start;
  logic [  31:0] s_dma_write_addr;
  logic [  31:0] s_dma_write_line_bytes;
  logic [  31:0] s_dma_write_stride;
  logic [  15:0] s_dma_write_lines;
  logic          s_dma_write_busy;
  logic          s_dma_write_done;
  logic          s_dma_err;
  logic          s_dma_err_read;
  logic [   1:0] s_dma_err_resp;
  logic [  31:0] s_dma_err_addr;
  logic [  31:0] s_dma_read_bytes;
  logic [  31:0] s_dma_write_bytes;
  logic [  31:0] s_dma_read_stall;
  logic [  31:0] s_dma_write_stall;

  logic          s_encode_start;
  logic          s_encode_busy;
  logic          s_encode_done;
  logic          s_encode_err;
  logic          s_decode_start;
  logic          s_decode_busy;
  logic          s_decode_done;
  logic [  15:0] s_decode_width;
  logic [  15:0] s_decode_height;
  logic [   1:0] s_decode_sampling;
  logic          s_decode_err;
  logic [   4:0] s_decode_err_code;

  logic [  11:0] s_read_mcu_col_d;
  logic [  11:0] s_read_mcu_col_q;
  logic [  11:0] s_read_mcu_row_d;
  logic [  11:0] s_read_mcu_row_q;
  logic          s_read_uv_d;
  logic          s_read_uv_q;
  logic          s_read_pending_d;
  logic          s_read_pending_q;
  logic          s_decode_read_issued_d;
  logic          s_decode_read_issued_q;
  logic          s_all_reads_done_d;
  logic          s_all_reads_done_q;
  logic [  11:0] s_write_mcu_col_d;
  logic [  11:0] s_write_mcu_col_q;
  logic [  11:0] s_write_mcu_row_d;
  logic [  11:0] s_write_mcu_row_q;
  logic          s_write_uv_d;
  logic          s_write_uv_q;
  logic          s_surface_write_pending_d;
  logic          s_surface_write_pending_q;
  logic          s_all_surface_writes_done_d;
  logic          s_all_surface_writes_done_q;
  logic [  63:0] s_encode_output_data_d;
  logic [  63:0] s_encode_output_data_q;
  logic [   7:0] s_encode_output_keep_d;
  logic [   7:0] s_encode_output_keep_q;
  logic          s_encode_output_last_d;
  logic          s_encode_output_last_q;
  logic          s_encode_output_pending_d;
  logic          s_encode_output_pending_q;
  logic          s_encode_output_started_d;
  logic          s_encode_output_started_q;
  logic          s_encode_output_done_d;
  logic          s_encode_output_done_q;
  logic          s_core_done_d;
  logic          s_core_done_q;
  logic [  31:0] s_result_size_d;
  logic [  31:0] s_result_size_q;
  logic [  63:0] s_cycles_d;
  logic [  63:0] s_cycles_q;
  logic [  31:0] s_pixels_d;
  logic [  31:0] s_pixels_q;
  logic          s_job_done_d;
  logic          s_job_done_q;
  logic          s_abort_done_d;
  logic          s_abort_done_q;
  logic          s_err_event_d;
  logic          s_err_event_q;
  logic [   4:0] s_err_code_d;
  logic [   4:0] s_err_code_q;
  logic [   3:0] s_err_stage_d;
  logic [   3:0] s_err_stage_q;
  logic [  31:0] s_err_addr_d;
  logic [  31:0] s_err_addr_q;
  logic [  31:0] s_err_detail_d;
  logic [  31:0] s_err_detail_q;
  logic [1023:0] s_descriptor_d;
  logic [1023:0] s_descriptor_q;
  logic [   4:0] s_descriptor_beat_d;
  logic [   4:0] s_descriptor_beat_q;
  logic [  31:0] s_ring_head_d;
  logic [  31:0] s_ring_head_q;
  logic          s_ring_job_active_d;
  logic          s_ring_job_active_q;
  logic          s_ring_stalled_d;
  logic          s_ring_stalled_q;
  logic          s_ring_err_d;
  logic          s_ring_err_q;
  logic          s_ring_event_d;
  logic          s_ring_event_q;
  logic [  15:0] s_ring_completed_d;
  logic [  15:0] s_ring_completed_q;
  logic [  31:0] s_ring_status;
  logic [  31:0] s_ring_next_head;
  logic          s_ring_config_valid;

  logic          s_encode_mode;
  logic [  15:0] s_job_width;
  logic [  15:0] s_job_height;
  logic [   2:0] s_job_input_format;
  logic [   2:0] s_job_output_format;
  logic [   1:0] s_job_sampling;
  logic [   4:0] s_mcu_width;
  logic [   4:0] s_mcu_height;
  logic [  11:0] s_read_mcu_columns;
  logic [  11:0] s_read_mcu_rows;
  logic [  15:0] s_read_x_base;
  logic [  15:0] s_read_y_base;
  logic [   4:0] s_read_valid_width;
  logic [   4:0] s_read_valid_height;
  logic [  11:0] s_write_mcu_columns;
  logic [  11:0] s_write_mcu_rows;
  logic [  15:0] s_write_x_base;
  logic [  15:0] s_write_y_base;
  logic [   4:0] s_write_valid_width;
  logic [   4:0] s_write_valid_height;
  logic [   2:0] s_input_bytes_per_pixel;
  logic [   2:0] s_output_bytes_per_pixel;
  logic [   3:0] s_encode_output_bytes;
  logic          s_start_valid;

  function automatic logic [2:0] bytes_per_pixel(input logic [2:0] format_i);
    unique case (format_i)
      3'd0, 3'd4: return 3'd1;
      3'd1, 3'd3: return 3'd2;
      3'd2:       return 3'd3;
      default:    return 3'd0;
    endcase
  endfunction

  function automatic logic [3:0] keep_byte_count(input logic [7:0] keep_i);
    logic [3:0] s_count;
    begin
      s_count = 4'd0;
      for (int unsigned lane = 0; lane < 8; lane++) begin
        s_count += keep_i[lane];
      end
      return s_count;
    end
  endfunction

  always_comb begin
    s_job_config       = s_reg_job_config;
    s_image_size       = s_reg_image_size;
    s_input_format     = s_reg_input_format;
    s_output_format    = s_reg_output_format;
    s_encode_config    = s_reg_encode_config;
    s_restart_interval = s_reg_restart_interval;
    s_bitstream_addr   = s_reg_bitstream_addr;
    s_bitstream_size   = s_reg_bitstream_size;
    s_plane0_addr      = s_reg_plane0_addr;
    s_plane0_stride    = s_reg_plane0_stride;
    s_plane1_addr      = s_reg_plane1_addr;
    s_plane1_stride    = s_reg_plane1_stride;
    s_plane2_addr      = s_reg_plane2_addr;
    s_plane2_stride    = s_reg_plane2_stride;
    s_metadata_addr    = s_reg_metadata_addr;
    s_metadata_length  = s_reg_metadata_length;
    if (s_ring_job_active_q) begin
      s_job_config = 32'd0;
      s_job_config[`APB4_JPEG__JOB_CONFIG_ENCODE] = s_descriptor_q[`APB4_JPEG__DESCRIPTOR_ENCODE];
      s_job_config[`APB4_JPEG__JOB_CONFIG_AUTO_HEADER] =
          s_descriptor_q[`APB4_JPEG__DESCRIPTOR_AUTO_HEADER];
      s_job_config[`APB4_JPEG__JOB_CONFIG_STRICT] = s_descriptor_q[`APB4_JPEG__DESCRIPTOR_STRICT];
      s_job_config[`APB4_JPEG__JOB_CONFIG_METADATA] =
          s_descriptor_q[`APB4_JPEG__DESCRIPTOR_METADATA];
      s_job_config[9:8] = s_descriptor_q[9:8];
      s_image_size = s_descriptor_q[95:64];
      s_input_format = {29'd0, s_descriptor_q[14:12]};
      s_output_format = {29'd0, s_descriptor_q[18:16]};
      s_encode_config = s_descriptor_q[127:96];
      s_encode_config[9:8] = s_descriptor_q[21:20];
      s_restart_interval = s_descriptor_q[159:128];
      s_bitstream_addr = s_descriptor_q[191:160];
      s_bitstream_size = s_descriptor_q[223:192];
      s_plane0_addr = s_descriptor_q[287:256];
      s_plane0_stride = s_descriptor_q[319:288];
      s_plane1_addr = s_descriptor_q[351:320];
      s_plane1_stride = s_descriptor_q[383:352];
      s_plane2_addr = s_descriptor_q[415:384];
      s_plane2_stride = s_descriptor_q[447:416];
      s_metadata_addr = s_descriptor_q[479:448];
      s_metadata_length = s_descriptor_q[511:480];
    end
  end

  assign s_state_q = state_e'(s_state_bits_q);
  assign s_encode_mode = s_job_config[`APB4_JPEG__JOB_CONFIG_ENCODE];
  assign s_job_width = s_image_size[15:0];
  assign s_job_height = s_image_size[31:16];
  assign s_job_input_format = s_input_format[2:0];
  assign s_job_output_format = s_output_format[2:0];
  assign s_job_sampling = s_encode_config[9:8];
  assign s_input_bytes_per_pixel = bytes_per_pixel(s_job_input_format);
  assign s_output_bytes_per_pixel = bytes_per_pixel(s_job_output_format);
  assign s_encode_output_bytes = keep_byte_count(u_encode_bitstream_axis.tkeep);
  assign idle_o = s_state_q == Idle;
  assign s_engine_rst_n = rst_n_i;
  assign s_core_rst_n = rst_n_i && (s_state_q != AbortDrain) && !s_reg_soft_reset;
  assign s_ring_next_head = (s_ring_head_q + 1'b1) & (s_ring_size - 1'b1);
  assign s_ring_config_valid = s_ring_control[`APB4_JPEG__RING_CONTROL_ENABLE] &&
                               (s_ring_base[6:0] == 7'd0) &&
                               (s_ring_size >= 32'd2) && (s_ring_size <= 32'd256) &&
                               ((s_ring_size & (s_ring_size - 1'b1)) == 32'd0) &&
                               (s_ring_tail < s_ring_size);
  assign s_ring_status = {
    28'd0, s_ring_err_q, s_ring_stalled_q, s_ring_head_q == s_ring_tail, s_ring_job_active_q
  };

  always_comb begin
    unique case (s_job_sampling)
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
    s_read_mcu_columns = 12'((s_job_width + 16'(s_mcu_width) - 1'b1) / 16'(s_mcu_width));
    s_read_mcu_rows = 12'((s_job_height + 16'(s_mcu_height) - 1'b1) / 16'(s_mcu_height));
    s_read_x_base = 16'(s_read_mcu_col_q * 16'(s_mcu_width));
    s_read_y_base = 16'(s_read_mcu_row_q * 16'(s_mcu_height));
    s_read_valid_width = ((s_job_width - s_read_x_base) >= 16'(s_mcu_width)) ?
                             s_mcu_width : 5'(s_job_width - s_read_x_base);
    s_read_valid_height = ((s_job_height - s_read_y_base) >= 16'(s_mcu_height)) ?
                              s_mcu_height : 5'(s_job_height - s_read_y_base);

    unique case (s_decode_sampling)
      2'd0, 2'd1: begin
        s_write_mcu_columns = 12'((s_decode_width + 16'd7) / 16'd8);
        s_write_mcu_rows = 12'((s_decode_height + 16'd7) / 16'd8);
        s_write_x_base = 16'(s_write_mcu_col_q * 16'd8);
        s_write_y_base = 16'(s_write_mcu_row_q * 16'd8);
        s_write_valid_width = ((s_decode_width - s_write_x_base) >= 16'd8) ?
                                  5'd8 : 5'(s_decode_width - s_write_x_base);
        s_write_valid_height = ((s_decode_height - s_write_y_base) >= 16'd8) ?
                                   5'd8 : 5'(s_decode_height - s_write_y_base);
      end
      2'd2: begin
        s_write_mcu_columns = 12'((s_decode_width + 16'd15) / 16'd16);
        s_write_mcu_rows = 12'((s_decode_height + 16'd7) / 16'd8);
        s_write_x_base = 16'(s_write_mcu_col_q * 16'd16);
        s_write_y_base = 16'(s_write_mcu_row_q * 16'd8);
        s_write_valid_width = ((s_decode_width - s_write_x_base) >= 16'd16) ?
                                  5'd16 : 5'(s_decode_width - s_write_x_base);
        s_write_valid_height = ((s_decode_height - s_write_y_base) >= 16'd8) ?
                                   5'd8 : 5'(s_decode_height - s_write_y_base);
      end
      default: begin
        s_write_mcu_columns = 12'((s_decode_width + 16'd15) / 16'd16);
        s_write_mcu_rows = 12'((s_decode_height + 16'd15) / 16'd16);
        s_write_x_base = 16'(s_write_mcu_col_q * 16'd16);
        s_write_y_base = 16'(s_write_mcu_row_q * 16'd16);
        s_write_valid_width = ((s_decode_width - s_write_x_base) >= 16'd16) ?
                                  5'd16 : 5'(s_decode_width - s_write_x_base);
        s_write_valid_height = ((s_decode_height - s_write_y_base) >= 16'd16) ?
                                   5'd16 : 5'(s_decode_height - s_write_y_base);
      end
    endcase
  end

  assign s_cache_start = (s_state_q == EncodeCacheLumaStart) ||
                         (s_state_q == EncodeCacheChromaStart);
  assign s_cache_quant_id = (s_state_q == EncodeCacheLumaStart) ? 2'd0 : 2'd1;
  assign s_cache_dc_id = (s_state_q == EncodeCacheLumaStart) ? 2'd0 : 2'd1;
  assign s_cache_ac_id = (s_state_q == EncodeCacheLumaStart) ? 2'd0 : 2'd1;
  assign s_cache_ready = (s_state_q == EncodeCacheLumaWait) || (s_state_q == EncodeCacheChromaWait);
  assign s_encode_start = s_state_q == EncodeStart;
  assign s_decode_start = s_state_q == DecodeStart;
  assign s_start_valid = (s_job_width != 16'd0) && (s_job_height != 16'd0) &&
                         (s_job_width <= 16'd2048) && (s_job_height <= 16'd2048) &&
                         (s_bitstream_addr[2:0] == 3'd0) && (s_bitstream_size != 32'd0) &&
                         (s_plane0_addr[2:0] == 3'd0) && (s_job_input_format <= 3'd4) &&
                         (s_job_output_format <= 3'd4) &&
                         !s_job_config[`APB4_JPEG__JOB_CONFIG_METADATA] &&
                         (s_metadata_addr == 32'd0) && (s_metadata_length == 32'd0) &&
                         (!s_encode_mode || s_job_config[`APB4_JPEG__JOB_CONFIG_AUTO_HEADER]);

  always_comb begin
    u_encode_pixel_axis.tdata = u_dma_read_axis.tdata;
    u_encode_pixel_axis.tkeep = u_dma_read_axis.tkeep;
    u_encode_pixel_axis.tstrb = u_dma_read_axis.tstrb;
    u_encode_pixel_axis.tlast = u_dma_read_axis.tlast;
    u_encode_pixel_axis.tid = u_dma_read_axis.tid;
    u_encode_pixel_axis.tdest = u_dma_read_axis.tdest;
    u_encode_pixel_axis.tuser = u_dma_read_axis.tuser;
    u_encode_pixel_axis.tvalid = (s_state_q == EncodeRun) && u_dma_read_axis.tvalid;
    u_decode_bitstream_axis.tdata = u_dma_read_axis.tdata;
    u_decode_bitstream_axis.tkeep = u_dma_read_axis.tkeep;
    u_decode_bitstream_axis.tstrb = u_dma_read_axis.tstrb;
    u_decode_bitstream_axis.tlast = u_dma_read_axis.tlast;
    u_decode_bitstream_axis.tid = u_dma_read_axis.tid;
    u_decode_bitstream_axis.tdest = u_dma_read_axis.tdest;
    u_decode_bitstream_axis.tuser = u_dma_read_axis.tuser;
    u_decode_bitstream_axis.tvalid = (s_state_q == DecodeRun) && u_dma_read_axis.tvalid;
    u_dma_read_axis.tready = (s_state_q == EncodeRun) ? u_encode_pixel_axis.tready :
                             (s_state_q == DecodeRun) ? u_decode_bitstream_axis.tready :
                             (s_state_q == RingFetchRun);

    u_dma_write_axis.tdata = '0;
    u_dma_write_axis.tkeep = '0;
    u_dma_write_axis.tstrb = '0;
    u_dma_write_axis.tlast = 1'b0;
    u_dma_write_axis.tid = '0;
    u_dma_write_axis.tdest = '0;
    u_dma_write_axis.tuser = '0;
    u_dma_write_axis.tvalid = 1'b0;
    u_encode_bitstream_axis.tready = 1'b0;
    u_decode_pixel_axis.tready = 1'b0;
    if (s_state_q == EncodeRun) begin
      u_encode_bitstream_axis.tready = !s_encode_output_pending_q &&
                                       ((s_result_size_q + 32'(s_encode_output_bytes)) <=
                                        s_bitstream_size);
      u_dma_write_axis.tdata = s_encode_output_data_q;
      u_dma_write_axis.tkeep = s_encode_output_keep_q;
      u_dma_write_axis.tstrb = s_encode_output_keep_q;
      u_dma_write_axis.tlast = 1'b1;
      u_dma_write_axis.tvalid = s_encode_output_pending_q;
    end else if (s_state_q == DecodeRun) begin
      u_dma_write_axis.tdata     = u_decode_pixel_axis.tdata;
      u_dma_write_axis.tkeep     = u_decode_pixel_axis.tkeep;
      u_dma_write_axis.tstrb     = u_decode_pixel_axis.tstrb;
      u_dma_write_axis.tlast     = u_decode_pixel_axis.tlast;
      u_dma_write_axis.tid       = u_decode_pixel_axis.tid;
      u_dma_write_axis.tdest     = u_decode_pixel_axis.tdest;
      u_dma_write_axis.tuser     = u_decode_pixel_axis.tuser;
      u_dma_write_axis.tvalid    = u_decode_pixel_axis.tvalid;
      u_decode_pixel_axis.tready = u_dma_write_axis.tready;
    end else if (s_state_q == RingWriteRun) begin
      u_dma_write_axis.tdata  = s_descriptor_q[s_descriptor_beat_q*64+:64];
      u_dma_write_axis.tkeep  = 8'hff;
      u_dma_write_axis.tstrb  = 8'hff;
      u_dma_write_axis.tlast  = s_descriptor_beat_q == 5'd15;
      u_dma_write_axis.tvalid = s_descriptor_beat_q < 5'd16;
    end
  end

  always_comb begin
    s_dma_read_start      = 1'b0;
    s_dma_read_addr       = 32'd0;
    s_dma_read_line_bytes = 32'd0;
    s_dma_read_stride     = 32'd0;
    s_dma_read_lines      = 16'd0;
    if ((s_state_q == RingFetchStart) && !s_dma_read_busy) begin
      s_dma_read_start      = 1'b1;
      s_dma_read_addr       = s_ring_base + (s_ring_head_q << 7);
      s_dma_read_line_bytes = 32'd128;
      s_dma_read_stride     = 32'd128;
      s_dma_read_lines      = 16'd1;
    end else if ((s_state_q == EncodeRun) && s_read_pending_q && !s_dma_read_busy) begin
      s_dma_read_start = 1'b1;
      if ((s_job_input_format == 3'd4) && s_read_uv_q) begin
        s_dma_read_addr = s_plane1_addr + ((32'(s_read_y_base) >> 1) * s_plane1_stride) +
                          ((32'(s_read_x_base) >> 1) * 32'd2);
        s_dma_read_line_bytes = (32'(s_read_valid_width) + 1'b1) & 32'hffff_fffe;
        s_dma_read_stride = s_plane1_stride;
        s_dma_read_lines = (16'(s_read_valid_height) + 1'b1) >> 1;
      end else begin
        s_dma_read_addr = s_plane0_addr + (s_read_y_base * s_plane0_stride) +
                          (s_read_x_base * s_input_bytes_per_pixel);
        s_dma_read_line_bytes = 32'(s_read_valid_width) * 32'(s_input_bytes_per_pixel);
        s_dma_read_stride = s_plane0_stride;
        s_dma_read_lines = 16'(s_read_valid_height);
      end
    end else if ((s_state_q == DecodeRun) && !s_decode_read_issued_q && !s_dma_read_busy) begin
      s_dma_read_start      = 1'b1;
      s_dma_read_addr       = s_bitstream_addr;
      s_dma_read_line_bytes = s_bitstream_size;
      s_dma_read_stride     = s_bitstream_size;
      s_dma_read_lines      = 16'd1;
    end
  end

  always_comb begin
    s_dma_write_start      = 1'b0;
    s_dma_write_addr       = 32'd0;
    s_dma_write_line_bytes = 32'd0;
    s_dma_write_stride     = 32'd0;
    s_dma_write_lines      = 16'd0;
    if ((s_state_q == RingWriteStart) && !s_dma_write_busy) begin
      s_dma_write_start      = 1'b1;
      s_dma_write_addr       = s_ring_base + (s_ring_head_q << 7);
      s_dma_write_line_bytes = 32'd128;
      s_dma_write_stride     = 32'd128;
      s_dma_write_lines      = 16'd1;
    end else if ((s_state_q == EncodeRun) && s_encode_output_pending_q &&
        !s_encode_output_started_q && !s_dma_write_busy) begin
      s_dma_write_start      = 1'b1;
      s_dma_write_addr       = s_bitstream_addr + s_result_size_q;
      s_dma_write_line_bytes = 32'(keep_byte_count(s_encode_output_keep_q));
      s_dma_write_stride     = 32'(keep_byte_count(s_encode_output_keep_q));
      s_dma_write_lines      = 16'd1;
    end else if ((s_state_q == DecodeRun) && s_surface_write_pending_q && !s_dma_write_busy) begin
      s_dma_write_start = 1'b1;
      if ((s_job_output_format == 3'd4) && s_write_uv_q) begin
        s_dma_write_addr = s_plane1_addr + ((32'(s_write_y_base) >> 1) * s_plane1_stride) +
                           ((32'(s_write_x_base) >> 1) * 32'd2);
        s_dma_write_line_bytes = (32'(s_write_valid_width) + 1'b1) & 32'hffff_fffe;
        s_dma_write_stride = s_plane1_stride;
        s_dma_write_lines = (16'(s_write_valid_height) + 1'b1) >> 1;
      end else begin
        s_dma_write_addr = s_plane0_addr + (s_write_y_base * s_plane0_stride) +
                           (s_write_x_base * s_output_bytes_per_pixel);
        s_dma_write_line_bytes = 32'(s_write_valid_width) * 32'(s_output_bytes_per_pixel);
        s_dma_write_stride = s_plane0_stride;
        s_dma_write_lines = 16'(s_write_valid_height);
      end
    end
  end

  always_comb begin
    s_state_d                   = s_state_q;
    s_luma_quant_d              = s_luma_quant_q;
    s_luma_reciprocal_d         = s_luma_reciprocal_q;
    s_luma_dc_code_d            = s_luma_dc_code_q;
    s_luma_dc_len_d             = s_luma_dc_len_q;
    s_luma_ac_code_d            = s_luma_ac_code_q;
    s_luma_ac_len_d             = s_luma_ac_len_q;
    s_chroma_quant_d            = s_chroma_quant_q;
    s_chroma_reciprocal_d       = s_chroma_reciprocal_q;
    s_chroma_dc_code_d          = s_chroma_dc_code_q;
    s_chroma_dc_len_d           = s_chroma_dc_len_q;
    s_chroma_ac_code_d          = s_chroma_ac_code_q;
    s_chroma_ac_len_d           = s_chroma_ac_len_q;
    s_read_mcu_col_d            = s_read_mcu_col_q;
    s_read_mcu_row_d            = s_read_mcu_row_q;
    s_read_uv_d                 = s_read_uv_q;
    s_read_pending_d            = s_read_pending_q;
    s_decode_read_issued_d      = s_decode_read_issued_q;
    s_all_reads_done_d          = s_all_reads_done_q;
    s_write_mcu_col_d           = s_write_mcu_col_q;
    s_write_mcu_row_d           = s_write_mcu_row_q;
    s_write_uv_d                = s_write_uv_q;
    s_surface_write_pending_d   = s_surface_write_pending_q;
    s_all_surface_writes_done_d = s_all_surface_writes_done_q;
    s_encode_output_data_d      = s_encode_output_data_q;
    s_encode_output_keep_d      = s_encode_output_keep_q;
    s_encode_output_last_d      = s_encode_output_last_q;
    s_encode_output_pending_d   = s_encode_output_pending_q;
    s_encode_output_started_d   = s_encode_output_started_q;
    s_encode_output_done_d      = s_encode_output_done_q;
    s_core_done_d               = s_core_done_q;
    s_result_size_d             = s_result_size_q;
    s_cycles_d                  = s_cycles_q;
    s_pixels_d                  = s_pixels_q;
    s_job_done_d                = 1'b0;
    s_abort_done_d              = 1'b0;
    s_err_event_d               = 1'b0;
    s_err_code_d                = s_err_code_q;
    s_err_stage_d               = s_err_stage_q;
    s_err_addr_d                = s_err_addr_q;
    s_err_detail_d              = s_err_detail_q;
    s_descriptor_d              = s_descriptor_q;
    s_descriptor_beat_d         = s_descriptor_beat_q;
    s_ring_head_d               = s_ring_head_q;
    s_ring_job_active_d         = s_ring_job_active_q;
    s_ring_stalled_d            = s_ring_stalled_q;
    s_ring_err_d                = s_ring_err_q;
    s_ring_event_d              = 1'b0;
    s_ring_completed_d          = s_ring_completed_q;

    if (s_state_q != Idle && s_perf_enable) begin
      s_cycles_d = s_cycles_q + 1'b1;
    end
    if (s_dma_read_start) begin
      s_read_pending_d = 1'b0;
      if (s_state_q == DecodeRun) begin
        s_decode_read_issued_d = 1'b1;
      end
    end
    if (s_dma_write_start) begin
      if (s_state_q == EncodeRun) begin
        s_encode_output_started_d = 1'b1;
      end else if (s_state_q == DecodeRun) begin
        s_surface_write_pending_d = 1'b0;
      end
    end
    if ((s_state_q == RingFetchRun) && u_dma_read_axis.tvalid && u_dma_read_axis.tready) begin
      s_descriptor_d[s_descriptor_beat_q*64+:64] = u_dma_read_axis.tdata;
      s_descriptor_beat_d = s_descriptor_beat_q + 1'b1;
    end
    if ((s_state_q == RingWriteRun) && u_dma_write_axis.tvalid && u_dma_write_axis.tready) begin
      s_descriptor_beat_d = s_descriptor_beat_q + 1'b1;
    end

    unique case (s_state_q)
      Idle: begin
        s_ring_job_active_d = 1'b0;
        if (s_reg_start) begin
          s_cycles_d                  = 64'd0;
          s_pixels_d                  = 32'd0;
          s_result_size_d             = 32'd0;
          s_core_done_d               = 1'b0;
          s_all_reads_done_d          = 1'b0;
          s_all_surface_writes_done_d = 1'b0;
          s_encode_output_done_d      = 1'b0;
          s_decode_read_issued_d      = 1'b0;
          s_encode_output_pending_d   = 1'b0;
          s_encode_output_started_d   = 1'b0;
          s_read_pending_d            = 1'b0;
          s_surface_write_pending_d   = 1'b0;
          if (!s_start_valid || quiesce_i || resource_reset_i) begin
            s_err_event_d = 1'b1;
            s_err_code_d  = 5'd1;
            s_err_stage_d = 4'd1;
          end else if (s_encode_mode) begin
            s_state_d = EncodeCacheLumaStart;
          end else begin
            s_state_d = DecodeStart;
          end
        end else if (s_reg_ring_kick) begin
          s_ring_stalled_d = 1'b0;
          s_ring_err_d = 1'b0;
          s_ring_completed_d = 16'd0;
          if (!s_ring_config_valid || quiesce_i || resource_reset_i) begin
            s_err_event_d = 1'b1;
            s_err_code_d  = 5'd2;
            s_err_stage_d = 4'd1;
            s_ring_err_d  = 1'b1;
          end else if (s_ring_head_q != s_ring_tail) begin
            s_descriptor_beat_d = 5'd0;
            s_ring_job_active_d = 1'b1;
            s_state_d = RingFetchStart;
          end
        end
      end
      RingFetchStart: begin
        if (!s_dma_read_busy) begin
          s_descriptor_beat_d = 5'd0;
          s_state_d = RingFetchRun;
        end
      end
      RingFetchRun: begin
        if (s_dma_read_done) begin
          s_state_d = RingParse;
        end
      end
      RingParse: begin
        s_cycles_d                  = 64'd0;
        s_pixels_d                  = 32'd0;
        s_result_size_d             = 32'd0;
        s_core_done_d               = 1'b0;
        s_all_reads_done_d          = 1'b0;
        s_all_surface_writes_done_d = 1'b0;
        s_encode_output_done_d      = 1'b0;
        s_decode_read_issued_d      = 1'b0;
        s_encode_output_pending_d   = 1'b0;
        s_encode_output_started_d   = 1'b0;
        s_read_pending_d            = 1'b0;
        s_surface_write_pending_d   = 1'b0;
        if (!s_descriptor_q[`APB4_JPEG__DESCRIPTOR_OWN]) begin
          s_ring_stalled_d = 1'b1;
          s_ring_event_d = 1'b1;
          s_ring_job_active_d = 1'b0;
          s_state_d = Idle;
        end else if (!s_start_valid) begin
          s_descriptor_d[`APB4_JPEG__DESCRIPTOR_OWN] = 1'b0;
          s_descriptor_d[63:32] = 32'd0;
          s_descriptor_d[32+`APB4_JPEG__DESCRIPTOR_STATUS_DONE] = 1'b1;
          s_descriptor_d[32+`APB4_JPEG__DESCRIPTOR_STATUS_ERR] = 1'b1;
          s_descriptor_d[40+:5] = 5'd1;
          s_err_event_d = 1'b1;
          s_err_code_d = 5'd1;
          s_err_stage_d = 4'd1;
          s_ring_err_d = 1'b1;
          s_descriptor_beat_d = 5'd0;
          s_state_d = RingWriteStart;
        end else if (s_encode_mode) begin
          s_state_d = EncodeCacheLumaStart;
        end else begin
          s_state_d = DecodeStart;
        end
      end
      EncodeCacheLumaStart:   s_state_d = EncodeCacheLumaWait;
      EncodeCacheLumaWait: begin
        if (s_cache_valid) begin
          s_luma_quant_d      = s_cache_quant;
          s_luma_reciprocal_d = s_cache_reciprocal;
          s_luma_dc_code_d    = s_cache_dc_code;
          s_luma_dc_len_d     = s_cache_dc_len;
          s_luma_ac_code_d    = s_cache_ac_code;
          s_luma_ac_len_d     = s_cache_ac_len;
          if (s_cache_err) begin
            s_err_event_d = 1'b1;
            s_err_code_d  = 5'd3;
            s_err_stage_d = 4'd1;
            if (s_ring_job_active_q) begin
              s_descriptor_d[`APB4_JPEG__DESCRIPTOR_OWN] = 1'b0;
              s_descriptor_d[63:32] = 32'd3;
              s_descriptor_d[40+:5] = 5'd3;
              s_descriptor_beat_d = 5'd0;
              s_ring_err_d = 1'b1;
              s_state_d = RingWriteStart;
            end else begin
              s_state_d = Idle;
            end
          end else if (s_job_sampling == 2'd0) begin
            s_chroma_quant_d      = s_cache_quant;
            s_chroma_reciprocal_d = s_cache_reciprocal;
            s_chroma_dc_code_d    = s_cache_dc_code;
            s_chroma_dc_len_d     = s_cache_dc_len;
            s_chroma_ac_code_d    = s_cache_ac_code;
            s_chroma_ac_len_d     = s_cache_ac_len;
            s_state_d             = EncodeStart;
          end else begin
            s_state_d = EncodeCacheChromaStart;
          end
        end
      end
      EncodeCacheChromaStart: s_state_d = EncodeCacheChromaWait;
      EncodeCacheChromaWait: begin
        if (s_cache_valid) begin
          s_chroma_quant_d      = s_cache_quant;
          s_chroma_reciprocal_d = s_cache_reciprocal;
          s_chroma_dc_code_d    = s_cache_dc_code;
          s_chroma_dc_len_d     = s_cache_dc_len;
          s_chroma_ac_code_d    = s_cache_ac_code;
          s_chroma_ac_len_d     = s_cache_ac_len;
          if (s_cache_err) begin
            s_err_event_d = 1'b1;
            s_err_code_d  = 5'd3;
            s_err_stage_d = 4'd1;
            if (s_ring_job_active_q) begin
              s_descriptor_d[`APB4_JPEG__DESCRIPTOR_OWN] = 1'b0;
              s_descriptor_d[63:32] = 32'd3;
              s_descriptor_d[40+:5] = 5'd3;
              s_descriptor_beat_d = 5'd0;
              s_ring_err_d = 1'b1;
              s_state_d = RingWriteStart;
            end else begin
              s_state_d = Idle;
            end
          end else begin
            s_state_d = EncodeStart;
          end
        end
      end
      EncodeStart: begin
        s_read_mcu_col_d = 12'd0;
        s_read_mcu_row_d = 12'd0;
        s_read_uv_d      = 1'b0;
        s_read_pending_d = 1'b1;
        s_state_d        = EncodeRun;
      end
      EncodeRun: begin
        if (u_encode_bitstream_axis.tvalid && u_encode_bitstream_axis.tready) begin
          s_encode_output_data_d    = u_encode_bitstream_axis.tdata;
          s_encode_output_keep_d    = u_encode_bitstream_axis.tkeep;
          s_encode_output_last_d    = u_encode_bitstream_axis.tlast;
          s_encode_output_pending_d = 1'b1;
          s_encode_output_started_d = 1'b0;
        end
        if (s_dma_read_done) begin
          if ((s_job_input_format == 3'd4) && !s_read_uv_q) begin
            s_read_uv_d      = 1'b1;
            s_read_pending_d = 1'b1;
          end else begin
            s_read_uv_d = 1'b0;
            if ((s_read_mcu_col_q + 1'b1 == s_read_mcu_columns) &&
                (s_read_mcu_row_q + 1'b1 == s_read_mcu_rows)) begin
              s_all_reads_done_d = 1'b1;
            end else begin
              if (s_read_mcu_col_q + 1'b1 == s_read_mcu_columns) begin
                s_read_mcu_col_d = 12'd0;
                s_read_mcu_row_d = s_read_mcu_row_q + 1'b1;
              end else begin
                s_read_mcu_col_d = s_read_mcu_col_q + 1'b1;
              end
              s_read_pending_d = 1'b1;
            end
          end
        end
        if (s_dma_write_done && s_encode_output_started_q) begin
          s_result_size_d = s_result_size_q + 32'(keep_byte_count(s_encode_output_keep_q));
          s_encode_output_pending_d = 1'b0;
          s_encode_output_started_d = 1'b0;
          if (s_encode_output_last_q) begin
            s_encode_output_done_d = 1'b1;
          end
        end
        if (s_encode_done) begin
          s_core_done_d = 1'b1;
        end
        if ((s_core_done_q || s_encode_done) && s_encode_output_done_d && s_all_reads_done_d) begin
          s_pixels_d   = s_job_width * s_job_height;
          s_job_done_d = 1'b1;
          if (s_ring_job_active_q) begin
            s_descriptor_d[`APB4_JPEG__DESCRIPTOR_OWN] = 1'b0;
            s_descriptor_d[63:32] = 32'd1;
            s_descriptor_d[255:224] = s_result_size_d;
            s_descriptor_d[607:576] = {s_job_height, s_job_width};
            s_descriptor_d[639:608] = {27'd0, s_job_sampling, s_job_output_format};
            s_descriptor_d[671:640] = s_cycles_d[31:0];
            s_descriptor_d[703:672] = s_cycles_d[63:32];
            s_descriptor_d[735:704] = s_dma_read_bytes;
            s_descriptor_d[767:736] = s_result_size_d;
            s_descriptor_beat_d = 5'd0;
            s_state_d = RingWriteStart;
          end else begin
            s_state_d = Idle;
          end
        end
      end
      DecodeStart: begin
        s_write_mcu_col_d      = 12'd0;
        s_write_mcu_row_d      = 12'd0;
        s_write_uv_d           = 1'b0;
        s_decode_read_issued_d = 1'b0;
        s_state_d              = DecodeRun;
      end
      DecodeRun: begin
        if (s_dma_read_done) begin
          s_all_reads_done_d = 1'b1;
        end
        if ((s_decode_width != 16'd0) && !s_surface_write_pending_q &&
            !s_dma_write_busy && !s_all_surface_writes_done_q &&
            (s_dma_write_bytes == 32'd0 || s_dma_write_done)) begin
          s_surface_write_pending_d = 1'b1;
        end
        if (s_dma_write_done) begin
          if ((s_job_output_format == 3'd4) && !s_write_uv_q && (s_decode_sampling != 2'd0)) begin
            s_write_uv_d              = 1'b1;
            s_surface_write_pending_d = 1'b1;
          end else begin
            s_write_uv_d = 1'b0;
            if ((s_write_mcu_col_q + 1'b1 == s_write_mcu_columns) &&
                (s_write_mcu_row_q + 1'b1 == s_write_mcu_rows)) begin
              s_all_surface_writes_done_d = 1'b1;
            end else begin
              if (s_write_mcu_col_q + 1'b1 == s_write_mcu_columns) begin
                s_write_mcu_col_d = 12'd0;
                s_write_mcu_row_d = s_write_mcu_row_q + 1'b1;
              end else begin
                s_write_mcu_col_d = s_write_mcu_col_q + 1'b1;
              end
              s_surface_write_pending_d = 1'b1;
            end
          end
        end
        if (s_decode_done) begin
          s_core_done_d = 1'b1;
        end
        if ((s_core_done_q || s_decode_done) && s_all_surface_writes_done_d &&
            s_all_reads_done_d) begin
          s_pixels_d      = s_decode_width * s_decode_height;
          s_result_size_d = s_dma_write_bytes;
          s_job_done_d    = 1'b1;
          if (s_ring_job_active_q) begin
            s_descriptor_d[`APB4_JPEG__DESCRIPTOR_OWN] = 1'b0;
            s_descriptor_d[63:32] = 32'd1;
            s_descriptor_d[255:224] = s_dma_write_bytes;
            s_descriptor_d[607:576] = {s_decode_height, s_decode_width};
            s_descriptor_d[639:608] = {27'd0, s_decode_sampling, s_job_output_format};
            s_descriptor_d[671:640] = s_cycles_d[31:0];
            s_descriptor_d[703:672] = s_cycles_d[63:32];
            s_descriptor_d[735:704] = s_dma_read_bytes;
            s_descriptor_d[767:736] = s_dma_write_bytes;
            s_descriptor_beat_d = 5'd0;
            s_state_d = RingWriteStart;
          end else begin
            s_state_d = Idle;
          end
        end
      end
      AbortDrain: begin
        if (!s_dma_read_busy && !s_dma_write_busy) begin
          s_abort_done_d = 1'b1;
          if (s_ring_job_active_q) begin
            s_descriptor_beat_d = 5'd0;
            s_state_d = RingWriteStart;
          end else begin
            s_state_d = Idle;
          end
        end
      end
      RingWriteStart: begin
        if (!s_dma_write_busy) begin
          s_descriptor_beat_d = 5'd0;
          s_state_d = RingWriteRun;
        end
      end
      RingWriteRun: begin
        if (s_dma_write_done) begin
          s_ring_head_d = s_ring_next_head;
          s_ring_completed_d = s_ring_completed_q + 1'b1;
          if (s_descriptor_q[`APB4_JPEG__DESCRIPTOR_IOC] ||
              (s_irq_coalesce[15:0] == 16'd0) ||
              (s_ring_completed_q + 1'b1 >= s_irq_coalesce[15:0])) begin
            s_ring_event_d = 1'b1;
            s_ring_completed_d = 16'd0;
          end
          s_ring_job_active_d = 1'b0;
          if (s_ring_next_head != s_ring_tail &&
              s_ring_control[`APB4_JPEG__RING_CONTROL_ENABLE] &&
              !(s_ring_err_q && s_ring_control[`APB4_JPEG__RING_CONTROL_STOP_ERR])) begin
            s_ring_job_active_d = 1'b1;
            s_descriptor_beat_d = 5'd0;
            s_state_d = RingFetchStart;
          end else begin
            s_state_d = Idle;
          end
        end
      end
      default:                s_state_d = Idle;
    endcase

    if (s_reg_soft_reset && (s_state_q == Idle)) begin
      s_ring_head_d = 32'd0;
      s_ring_job_active_d = 1'b0;
      s_ring_stalled_d = 1'b0;
      s_ring_err_d = 1'b0;
      s_ring_completed_d = 16'd0;
    end

    if ((s_reg_abort || resource_reset_i) && (s_state_q != Idle)) begin
      if (s_ring_job_active_q &&
          ((s_state_q == EncodeCacheLumaStart) || (s_state_q == EncodeCacheLumaWait) ||
           (s_state_q == EncodeCacheChromaStart) || (s_state_q == EncodeCacheChromaWait) ||
           (s_state_q == EncodeStart) || (s_state_q == EncodeRun) ||
           (s_state_q == DecodeStart) || (s_state_q == DecodeRun))) begin
        s_descriptor_d[`APB4_JPEG__DESCRIPTOR_OWN] = 1'b0;
        s_descriptor_d[63:32] = 32'd5;
      end else begin
        s_ring_job_active_d = 1'b0;
      end
      s_state_d = AbortDrain;
    end
    if (s_dma_err && (s_state_q != Idle) && (s_state_q != AbortDrain)) begin
      s_err_event_d  = 1'b1;
      s_err_code_d   = s_dma_err_read ? 5'd13 : 5'd14;
      s_err_stage_d  = s_dma_err_read ? 4'd3 : 4'd8;
      s_err_addr_d   = s_dma_err_addr;
      s_err_detail_d = {30'd0, s_dma_err_resp};
      s_ring_err_d   = s_ring_job_active_q;
      if (s_ring_job_active_q && ((s_state_q == EncodeRun) || (s_state_q == DecodeRun))) begin
        s_descriptor_d[`APB4_JPEG__DESCRIPTOR_OWN] = 1'b0;
        s_descriptor_d[63:32] = 32'd3;
        s_descriptor_d[40+:5] = s_dma_err_read ? 5'd13 : 5'd14;
      end else begin
        s_ring_job_active_d = 1'b0;
      end
      s_state_d = AbortDrain;
    end else if ((s_encode_err || s_decode_err) &&
                 ((s_state_q == EncodeRun) || (s_state_q == DecodeRun))) begin
      s_err_event_d = 1'b1;
      s_err_code_d  = s_encode_err ? 5'd18 : s_decode_err_code;
      s_err_stage_d = 4'd7;
      if (s_ring_job_active_q) begin
        s_descriptor_d[`APB4_JPEG__DESCRIPTOR_OWN] = 1'b0;
        s_descriptor_d[63:32] = 32'd3;
        s_descriptor_d[40+:5] = s_encode_err ? 5'd18 : s_decode_err_code;
        s_ring_err_d = 1'b1;
      end
      s_state_d = AbortDrain;
    end
  end

  jpeg_reg u_reg (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .apb4               (apb4),
      .busy_i             (s_state_q != Idle),
      .ring_active_i      (s_ring_job_active_q),
      .encode_i           (s_encode_mode),
      .quiesce_i          (quiesce_i),
      .job_done_i         (s_job_done_q),
      .ring_event_i       (s_ring_event_q),
      .header_ready_i     (1'b0),
      .abort_done_i       (s_abort_done_q),
      .error_event_i      (s_err_event_q),
      .error_code_i       (s_err_code_q),
      .error_stage_i      (s_err_stage_q),
      .error_axi_resp_i   (s_dma_err_resp),
      .error_addr_i       (s_err_addr_q),
      .error_detail_i     (s_err_detail_q),
      .cycles_i           (s_cycles_q),
      .pixels_i           (s_pixels_q),
      .input_bytes_i      (s_dma_read_bytes),
      .output_bytes_i     (s_result_size_q),
      .read_stall_i       (s_dma_read_stall),
      .write_stall_i      (s_dma_write_stall),
      .result_size_i      (s_result_size_q),
      .result_image_size_i({s_decode_height, s_decode_width}),
      .result_format_i    ({27'd0, s_decode_sampling, s_job_output_format}),
      .result_markers_i   (32'd0),
      .ring_head_i        (s_ring_head_q),
      .ring_status_i      (s_ring_status),
      .table_data_i       (s_table_read_data),
      .table_status_i     (s_table_status),
      .start_o            (s_reg_start),
      .abort_o            (s_reg_abort),
      .soft_reset_o       (s_reg_soft_reset),
      .ring_kick_o        (s_reg_ring_kick),
      .job_config_o       (s_reg_job_config),
      .image_size_o       (s_reg_image_size),
      .input_format_o     (s_reg_input_format),
      .output_format_o    (s_reg_output_format),
      .encode_config_o    (s_reg_encode_config),
      .restart_interval_o (s_reg_restart_interval),
      .bitstream_addr_o   (s_reg_bitstream_addr),
      .bitstream_size_o   (s_reg_bitstream_size),
      .plane0_addr_o      (s_reg_plane0_addr),
      .plane0_stride_o    (s_reg_plane0_stride),
      .plane1_addr_o      (s_reg_plane1_addr),
      .plane1_stride_o    (s_reg_plane1_stride),
      .plane2_addr_o      (s_reg_plane2_addr),
      .plane2_stride_o    (s_reg_plane2_stride),
      .metadata_addr_o    (s_reg_metadata_addr),
      .metadata_length_o  (s_reg_metadata_length),
      .ring_base_o        (s_ring_base),
      .ring_size_o        (s_ring_size),
      .ring_tail_o        (s_ring_tail),
      .ring_control_o     (s_ring_control),
      .irq_coalesce_o     (s_irq_coalesce),
      .table_context_o    (s_table_context),
      .table_kind_o       (s_table_kind),
      .table_index_o      (s_table_index),
      .table_write_data_o (s_table_write_data),
      .table_write_o      (s_table_write),
      .table_commit_o     (s_table_commit),
      .table_default_o    (s_table_default),
      .table_clear_o      (s_table_clear),
      .perf_enable_o      (s_perf_enable),
      .perf_clear_o       (s_perf_clear),
      .irq_o              (irq_o)
  );

  jpeg_table_store u_encode_table_store (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .portal_context_i   (s_table_context),
      .portal_kind_i      (s_table_kind),
      .portal_index_i     (s_table_index),
      .portal_write_data_i(s_table_write_data),
      .portal_write_i     (s_table_write),
      .portal_commit_i    (s_table_commit),
      .portal_default_i   (s_table_default),
      .portal_clear_i     (s_table_clear),
      .portal_read_data_o (s_table_read_data),
      .portal_status_o    (s_table_status),
      .lookup_i           (s_table_lookup),
      .lookup_context_i   (s_table_lookup_context),
      .lookup_kind_i      (s_table_lookup_kind),
      .lookup_index_i     (s_table_lookup_index),
      .lookup_data_o      (s_table_lookup_data),
      .lookup_valid_o     (s_table_lookup_valid),
      .lookup_err_o       (s_table_lookup_err)
  );

  jpeg_table_cache u_encode_table_cache (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .start_i         (s_cache_start),
      .context_i       (s_job_config[9:8]),
      .quant_id_i      (s_cache_quant_id),
      .dc_id_i         (s_cache_dc_id),
      .ac_id_i         (s_cache_ac_id),
      .start_ready_o   (),
      .lookup_o        (s_table_lookup),
      .lookup_context_o(s_table_lookup_context),
      .lookup_kind_o   (s_table_lookup_kind),
      .lookup_index_o  (s_table_lookup_index),
      .lookup_data_i   (s_table_lookup_data),
      .lookup_valid_i  (s_table_lookup_valid),
      .lookup_err_i    (s_table_lookup_err),
      .quant_o         (s_cache_quant),
      .reciprocal_o    (s_cache_reciprocal),
      .dc_code_o       (s_cache_dc_code),
      .dc_length_o     (s_cache_dc_len),
      .ac_code_o       (s_cache_ac_code),
      .ac_length_o     (s_cache_ac_len),
      .result_valid_o  (s_cache_valid),
      .result_ready_i  (s_cache_ready),
      .error_o         (s_cache_err)
  );

  jpeg_dma u_dma (
      .clk_i             (clk_i),
      .rst_n_i           (s_engine_rst_n),
      .abort_i           (s_state_q == AbortDrain),
      .quiesce_i         (quiesce_i),
      .read_start_i      (s_dma_read_start),
      .read_addr_i       (s_dma_read_addr),
      .read_line_bytes_i (s_dma_read_line_bytes),
      .read_stride_i     (s_dma_read_stride),
      .read_lines_i      (s_dma_read_lines),
      .read_busy_o       (s_dma_read_busy),
      .read_done_o       (s_dma_read_done),
      .read_axis         (u_dma_read_axis),
      .write_start_i     (s_dma_write_start),
      .write_addr_i      (s_dma_write_addr),
      .write_line_bytes_i(s_dma_write_line_bytes),
      .write_stride_i    (s_dma_write_stride),
      .write_lines_i     (s_dma_write_lines),
      .write_busy_o      (s_dma_write_busy),
      .write_done_o      (s_dma_write_done),
      .write_axis        (u_dma_write_axis),
      .error_o           (s_dma_err),
      .error_read_o      (s_dma_err_read),
      .error_resp_o      (s_dma_err_resp),
      .error_addr_o      (s_dma_err_addr),
      .read_bytes_o      (s_dma_read_bytes),
      .write_bytes_o     (s_dma_write_bytes),
      .read_stall_o      (s_dma_read_stall),
      .write_stall_o     (s_dma_write_stall),
      .axi4              (axi4)
  );

  jpeg_encode_core u_encode_core (
      .clk_i              (clk_i),
      .rst_n_i            (s_core_rst_n),
      .start_i            (s_encode_start),
      .width_i            (s_job_width),
      .height_i           (s_job_height),
      .sampling_i         (s_job_sampling),
      .input_format_i     (s_job_input_format),
      .restart_interval_i (s_restart_interval[15:0]),
      .luma_quant_i       (s_luma_quant_q),
      .luma_reciprocal_i  (s_luma_reciprocal_q),
      .luma_dc_code_i     (s_luma_dc_code_q),
      .luma_dc_length_i   (s_luma_dc_len_q),
      .luma_ac_code_i     (s_luma_ac_code_q),
      .luma_ac_length_i   (s_luma_ac_len_q),
      .chroma_quant_i     (s_chroma_quant_q),
      .chroma_reciprocal_i(s_chroma_reciprocal_q),
      .chroma_dc_code_i   (s_chroma_dc_code_q),
      .chroma_dc_length_i (s_chroma_dc_len_q),
      .chroma_ac_code_i   (s_chroma_ac_code_q),
      .chroma_ac_length_i (s_chroma_ac_len_q),
      .pixel_axis         (u_encode_pixel_axis),
      .bitstream_axis     (u_encode_bitstream_axis),
      .start_ready_o      (),
      .busy_o             (s_encode_busy),
      .done_o             (s_encode_done),
      .error_o            (s_encode_err)
  );

  jpeg_decode_core u_decode_core (
      .clk_i          (clk_i),
      .rst_n_i        (s_core_rst_n),
      .start_i        (s_decode_start),
      .output_format_i(s_job_output_format),
      .bitstream_axis (u_decode_bitstream_axis),
      .pixel_axis     (u_decode_pixel_axis),
      .start_ready_o  (),
      .busy_o         (s_decode_busy),
      .done_o         (s_decode_done),
      .width_o        (s_decode_width),
      .height_o       (s_decode_height),
      .sampling_o     (s_decode_sampling),
      .error_o        (s_decode_err),
      .error_code_o   (s_decode_err_code)
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
      .DATA_WIDTH(1024)
  ) u_descriptor_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_descriptor_d),
      .dat_o  (s_descriptor_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_descriptor_beat_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_descriptor_beat_d),
      .dat_o  (s_descriptor_beat_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_ring_head_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ring_head_d),
      .dat_o  (s_ring_head_q)
  );
  dffr u_ring_job_active_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ring_job_active_d),
      .dat_o  (s_ring_job_active_q)
  );
  dffr u_ring_stalled_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ring_stalled_d),
      .dat_o  (s_ring_stalled_q)
  );
  dffr u_ring_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ring_err_d),
      .dat_o  (s_ring_err_q)
  );
  dffr u_ring_event_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ring_event_d),
      .dat_o  (s_ring_event_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_ring_completed_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ring_completed_d),
      .dat_o  (s_ring_completed_q)
  );
  dffr #(
      .DATA_WIDTH(512)
  ) u_luma_quant_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_luma_quant_d),
      .dat_o  (s_luma_quant_q)
  );
  dffr #(
      .DATA_WIDTH(1600)
  ) u_luma_reciprocal_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_luma_reciprocal_d),
      .dat_o  (s_luma_reciprocal_q)
  );
  dffr #(
      .DATA_WIDTH(192)
  ) u_luma_dc_code_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_luma_dc_code_d),
      .dat_o  (s_luma_dc_code_q)
  );
  dffr #(
      .DATA_WIDTH(60)
  ) u_luma_dc_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_luma_dc_len_d),
      .dat_o  (s_luma_dc_len_q)
  );
  dffr #(
      .DATA_WIDTH(4096)
  ) u_luma_ac_code_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_luma_ac_code_d),
      .dat_o  (s_luma_ac_code_q)
  );
  dffr #(
      .DATA_WIDTH(1280)
  ) u_luma_ac_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_luma_ac_len_d),
      .dat_o  (s_luma_ac_len_q)
  );
  dffr #(
      .DATA_WIDTH(512)
  ) u_chroma_quant_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_chroma_quant_d),
      .dat_o  (s_chroma_quant_q)
  );
  dffr #(
      .DATA_WIDTH(1600)
  ) u_chroma_reciprocal_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_chroma_reciprocal_d),
      .dat_o  (s_chroma_reciprocal_q)
  );
  dffr #(
      .DATA_WIDTH(192)
  ) u_chroma_dc_code_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_chroma_dc_code_d),
      .dat_o  (s_chroma_dc_code_q)
  );
  dffr #(
      .DATA_WIDTH(60)
  ) u_chroma_dc_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_chroma_dc_len_d),
      .dat_o  (s_chroma_dc_len_q)
  );
  dffr #(
      .DATA_WIDTH(4096)
  ) u_chroma_ac_code_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_chroma_ac_code_d),
      .dat_o  (s_chroma_ac_code_q)
  );
  dffr #(
      .DATA_WIDTH(1280)
  ) u_chroma_ac_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_chroma_ac_len_d),
      .dat_o  (s_chroma_ac_len_q)
  );
  dffr #(
      .DATA_WIDTH(12)
  ) u_read_mcu_col_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_mcu_col_d),
      .dat_o  (s_read_mcu_col_q)
  );
  dffr #(
      .DATA_WIDTH(12)
  ) u_read_mcu_row_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_mcu_row_d),
      .dat_o  (s_read_mcu_row_q)
  );
  dffr u_read_uv_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_uv_d),
      .dat_o  (s_read_uv_q)
  );
  dffr u_read_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_pending_d),
      .dat_o  (s_read_pending_q)
  );
  dffr u_decode_read_issued_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_decode_read_issued_d),
      .dat_o  (s_decode_read_issued_q)
  );
  dffr u_all_reads_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_all_reads_done_d),
      .dat_o  (s_all_reads_done_q)
  );
  dffr #(
      .DATA_WIDTH(12)
  ) u_write_mcu_col_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_mcu_col_d),
      .dat_o  (s_write_mcu_col_q)
  );
  dffr #(
      .DATA_WIDTH(12)
  ) u_write_mcu_row_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_mcu_row_d),
      .dat_o  (s_write_mcu_row_q)
  );
  dffr u_write_uv_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_uv_d),
      .dat_o  (s_write_uv_q)
  );
  dffr u_surface_write_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_surface_write_pending_d),
      .dat_o  (s_surface_write_pending_q)
  );
  dffr u_all_surface_writes_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_all_surface_writes_done_d),
      .dat_o  (s_all_surface_writes_done_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_encode_output_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_encode_output_data_d),
      .dat_o  (s_encode_output_data_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_encode_output_keep_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_encode_output_keep_d),
      .dat_o  (s_encode_output_keep_q)
  );
  dffr u_encode_output_last_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_encode_output_last_d),
      .dat_o  (s_encode_output_last_q)
  );
  dffr u_encode_output_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_encode_output_pending_d),
      .dat_o  (s_encode_output_pending_q)
  );
  dffr u_encode_output_started_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_encode_output_started_d),
      .dat_o  (s_encode_output_started_q)
  );
  dffr u_encode_output_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_encode_output_done_d),
      .dat_o  (s_encode_output_done_q)
  );
  dffr u_core_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_core_done_d),
      .dat_o  (s_core_done_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_result_size_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_result_size_d),
      .dat_o  (s_result_size_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_cycles_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cycles_d),
      .dat_o  (s_cycles_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_pixels_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pixels_d),
      .dat_o  (s_pixels_q)
  );
  dffr u_job_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_job_done_d),
      .dat_o  (s_job_done_q)
  );
  dffr u_abort_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_abort_done_d),
      .dat_o  (s_abort_done_q)
  );
  dffr u_err_event_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_event_d),
      .dat_o  (s_err_event_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_err_code_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_code_d),
      .dat_o  (s_err_code_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_err_stage_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_stage_d),
      .dat_o  (s_err_stage_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_err_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_addr_d),
      .dat_o  (s_err_addr_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_err_detail_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_detail_d),
      .dat_o  (s_err_detail_q)
  );
endmodule
