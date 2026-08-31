// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

`include "jpeg_define.svh"

module jpeg_reg (
    // verilog_format: off -- preserve APB, engine, ring, and table interface columns
    input  logic          clk_i,
    input  logic          rst_n_i,
    apb4_if.slave         apb4,
    input  logic          busy_i,
    input  logic          ring_active_i,
    input  logic          encode_i,
    input  logic          quiesce_i,
    input  logic          job_done_i,
    input  logic          ring_event_i,
    input  logic          header_ready_i,
    input  logic          abort_done_i,
    input  logic          error_event_i,
    input  logic [ 4:0]   error_code_i,
    input  logic [ 3:0]   error_stage_i,
    input  logic [ 1:0]   error_axi_resp_i,
    input  logic [31:0]   error_addr_i,
    input  logic [31:0]   error_detail_i,
    input  logic [63:0]   cycles_i,
    input  logic [31:0]   pixels_i,
    input  logic [31:0]   input_bytes_i,
    input  logic [31:0]   output_bytes_i,
    input  logic [31:0]   read_stall_i,
    input  logic [31:0]   write_stall_i,
    input  logic [31:0]   result_size_i,
    input  logic [31:0]   result_image_size_i,
    input  logic [31:0]   result_format_i,
    input  logic [31:0]   result_markers_i,
    input  logic [31:0]   ring_head_i,
    input  logic [31:0]   ring_status_i,
    input  logic [31:0]   table_data_i,
    input  logic [31:0]   table_status_i,
    output logic          start_o,
    output logic          abort_o,
    output logic          soft_reset_o,
    output logic          ring_kick_o,
    output logic [31:0]   job_config_o,
    output logic [31:0]   image_size_o,
    output logic [31:0]   input_format_o,
    output logic [31:0]   output_format_o,
    output logic [31:0]   encode_config_o,
    output logic [31:0]   restart_interval_o,
    output logic [31:0]   bitstream_addr_o,
    output logic [31:0]   bitstream_size_o,
    output logic [31:0]   plane0_addr_o,
    output logic [31:0]   plane0_stride_o,
    output logic [31:0]   plane1_addr_o,
    output logic [31:0]   plane1_stride_o,
    output logic [31:0]   plane2_addr_o,
    output logic [31:0]   plane2_stride_o,
    output logic [31:0]   metadata_addr_o,
    output logic [31:0]   metadata_length_o,
    output logic [31:0]   ring_base_o,
    output logic [31:0]   ring_size_o,
    output logic [31:0]   ring_tail_o,
    output logic [31:0]   ring_control_o,
    output logic [31:0]   irq_coalesce_o,
    output logic [ 1:0]   table_context_o,
    output logic [ 3:0]   table_kind_o,
    output logic [ 7:0]   table_index_o,
    output logic [31:0]   table_write_data_o,
    output logic          table_write_o,
    output logic          table_commit_o,
    output logic          table_default_o,
    output logic          table_clear_o,
    output logic          perf_enable_o,
    output logic          perf_clear_o,
    output logic          irq_o
    // verilog_format: on
);
  localparam logic [31:0] IpId = 32'h4a504547;
  localparam logic [31:0] IpVersion = 32'h00010000;
  localparam logic [31:0] Capability0 = 32'h001f0f3f;
  localparam logic [31:0] Capability1 = 32'h08400800;

  logic              s_req;
  logic              s_write;
  logic              s_req_accept;
  logic              s_access_err;
  logic [11:0]       s_offset;
  logic [31:0]       s_read_data;
  logic [31:0]       s_write_value;
  logic [ 4:0]       s_irq_state_d;
  logic [ 4:0]       s_irq_state_q;
  logic [ 4:0]       s_irq_en_d;
  logic [ 4:0]       s_irq_en_q;
  logic [ 4:0]       s_irq_event;
  logic [ 4:0]       s_irq_clear;
  logic [31:0]       s_err_stat_d;
  logic [31:0]       s_err_stat_q;
  logic [31:0]       s_err_addr_d;
  logic [31:0]       s_err_addr_q;
  logic [31:0]       s_err_detail_d;
  logic [31:0]       s_err_detail_q;
  logic [ 1:0]       s_perf_control_d;
  logic [ 1:0]       s_perf_control_q;
  logic [15:0][31:0] s_cfg_d;
  logic [15:0][31:0] s_cfg_q;
  logic [ 4:0][31:0] s_ring_d;
  logic [ 4:0][31:0] s_ring_q;
  logic [ 1:0]       s_table_context_d;
  logic [ 1:0]       s_table_context_q;
  logic [ 3:0]       s_table_kind_d;
  logic [ 3:0]       s_table_kind_q;
  logic [ 7:0]       s_table_index_d;
  logic [ 7:0]       s_table_index_q;

  function automatic logic [31:0] apply_wstrb(
      input logic [31:0] previous_i, input logic [31:0] value_i, input logic [3:0] strobe_i);
    logic [31:0] s_value;
    begin
      s_value = previous_i;
      for (int unsigned byte_index = 0; byte_index < 4; byte_index++) begin
        if (strobe_i[byte_index]) begin
          s_value[byte_index*8+:8] = value_i[byte_index*8+:8];
        end
      end
      return s_value;
    end
  endfunction

  assign s_req = apb4.psel && apb4.penable;
  assign s_write = s_req && apb4.pwrite;
  assign s_req_accept = s_req;
  assign s_offset = apb4.paddr[11:0];
  assign s_write_value = apb4.pwdata;
  assign apb4.pready = s_req_accept;
  assign apb4.pslverr = s_access_err;
  assign apb4.prdata = s_read_data;

  assign s_irq_event = {error_event_i, abort_done_i, header_ready_i, ring_event_i, job_done_i};
  assign irq_o = |(s_irq_state_q & s_irq_en_q);
  assign perf_enable_o = s_perf_control_q[0];

  assign job_config_o = s_cfg_q[0];
  assign image_size_o = s_cfg_q[1];
  assign input_format_o = s_cfg_q[2];
  assign output_format_o = s_cfg_q[3];
  assign encode_config_o = s_cfg_q[4];
  assign restart_interval_o = s_cfg_q[5];
  assign bitstream_addr_o = s_cfg_q[6];
  assign bitstream_size_o = s_cfg_q[7];
  assign plane0_addr_o = s_cfg_q[8];
  assign plane0_stride_o = s_cfg_q[9];
  assign plane1_addr_o = s_cfg_q[10];
  assign plane1_stride_o = s_cfg_q[11];
  assign plane2_addr_o = s_cfg_q[12];
  assign plane2_stride_o = s_cfg_q[13];
  assign metadata_addr_o = s_cfg_q[14];
  assign metadata_length_o = s_cfg_q[15];
  assign ring_base_o = s_ring_q[0];
  assign ring_size_o = s_ring_q[1];
  assign ring_tail_o = s_ring_q[2];
  assign ring_control_o = s_ring_q[3];
  assign irq_coalesce_o = s_ring_q[4];
  assign table_context_o = s_table_context_q;
  assign table_kind_o = s_table_kind_q;
  assign table_index_o = s_table_index_q;

  always_comb begin
    s_read_data = 32'd0;
    unique case (s_offset)
      `APB4_JPEG__IP_ID: s_read_data = IpId;
      `APB4_JPEG__IP_VERSION: s_read_data = IpVersion;
      `APB4_JPEG__CAPABILITY0: s_read_data = Capability0;
      `APB4_JPEG__CAPABILITY1: s_read_data = Capability1;
      `APB4_JPEG__STATUS: s_read_data = {28'd0, !busy_i, encode_i, ring_active_i, busy_i};
      `APB4_JPEG__IRQ_STATE: s_read_data = {27'd0, s_irq_state_q};
      `APB4_JPEG__IRQ_ENABLE: s_read_data = {27'd0, s_irq_en_q};
      `APB4_JPEG__ERROR_STATUS: s_read_data = s_err_stat_q;
      `APB4_JPEG__ERROR_ADDRESS: s_read_data = s_err_addr_q;
      `APB4_JPEG__ERROR_DETAIL: s_read_data = s_err_detail_q;
      `APB4_JPEG__PERF_CONTROL: s_read_data = {30'd0, s_perf_control_q};
      `APB4_JPEG__CYCLES_LO: s_read_data = cycles_i[31:0];
      `APB4_JPEG__CYCLES_HI: s_read_data = cycles_i[63:32];
      `APB4_JPEG__PIXELS: s_read_data = pixels_i;
      `APB4_JPEG__INPUT_BYTES: s_read_data = input_bytes_i;
      `APB4_JPEG__OUTPUT_BYTES: s_read_data = output_bytes_i;
      `APB4_JPEG__READ_STALL: s_read_data = read_stall_i;
      `APB4_JPEG__WRITE_STALL: s_read_data = write_stall_i;
      `APB4_JPEG__JOB_CONFIG: s_read_data = s_cfg_q[0];
      `APB4_JPEG__IMAGE_SIZE: s_read_data = s_cfg_q[1];
      `APB4_JPEG__INPUT_FORMAT: s_read_data = s_cfg_q[2];
      `APB4_JPEG__OUTPUT_FORMAT: s_read_data = s_cfg_q[3];
      `APB4_JPEG__ENCODE_CONFIG: s_read_data = s_cfg_q[4];
      `APB4_JPEG__RESTART_INTERVAL: s_read_data = s_cfg_q[5];
      `APB4_JPEG__BITSTREAM_ADDR: s_read_data = s_cfg_q[6];
      `APB4_JPEG__BITSTREAM_SIZE: s_read_data = s_cfg_q[7];
      `APB4_JPEG__PLANE0_ADDR: s_read_data = s_cfg_q[8];
      `APB4_JPEG__PLANE0_STRIDE: s_read_data = s_cfg_q[9];
      `APB4_JPEG__PLANE1_ADDR: s_read_data = s_cfg_q[10];
      `APB4_JPEG__PLANE1_STRIDE: s_read_data = s_cfg_q[11];
      `APB4_JPEG__PLANE2_ADDR: s_read_data = s_cfg_q[12];
      `APB4_JPEG__PLANE2_STRIDE: s_read_data = s_cfg_q[13];
      `APB4_JPEG__METADATA_ADDR: s_read_data = s_cfg_q[14];
      `APB4_JPEG__METADATA_LENGTH: s_read_data = s_cfg_q[15];
      `APB4_JPEG__RESULT_SIZE: s_read_data = result_size_i;
      `APB4_JPEG__RESULT_IMAGE_SIZE: s_read_data = result_image_size_i;
      `APB4_JPEG__RESULT_FORMAT: s_read_data = result_format_i;
      `APB4_JPEG__RESULT_MARKERS: s_read_data = result_markers_i;
      `APB4_JPEG__RING_BASE: s_read_data = s_ring_q[0];
      `APB4_JPEG__RING_SIZE: s_read_data = s_ring_q[1];
      `APB4_JPEG__RING_HEAD: s_read_data = ring_head_i;
      `APB4_JPEG__RING_TAIL: s_read_data = s_ring_q[2];
      `APB4_JPEG__RING_CONTROL: s_read_data = s_ring_q[3];
      `APB4_JPEG__RING_STATUS: s_read_data = ring_status_i;
      `APB4_JPEG__IRQ_COALESCE: s_read_data = s_ring_q[4];
      `APB4_JPEG__TABLE_CONTEXT: s_read_data = {30'd0, s_table_context_q};
      `APB4_JPEG__TABLE_KIND: s_read_data = {28'd0, s_table_kind_q};
      `APB4_JPEG__TABLE_INDEX: s_read_data = {24'd0, s_table_index_q};
      `APB4_JPEG__TABLE_DATA: s_read_data = table_data_i;
      `APB4_JPEG__TABLE_STATUS: s_read_data = table_status_i;
      default: s_read_data = 32'd0;
    endcase
  end

  always_comb begin
    s_access_err = 1'b0;
    if (s_req && (apb4.paddr[1:0] != 2'b00)) begin
      s_access_err = 1'b1;
    end
    if (s_write) begin
      unique case (s_offset)
        `APB4_JPEG__COMMAND, `APB4_JPEG__IRQ_STATE, `APB4_JPEG__IRQ_ENABLE,
        `APB4_JPEG__IRQ_TEST, `APB4_JPEG__ERROR_STATUS, `APB4_JPEG__PERF_CONTROL,
        `APB4_JPEG__JOB_CONFIG, `APB4_JPEG__IMAGE_SIZE, `APB4_JPEG__INPUT_FORMAT,
        `APB4_JPEG__OUTPUT_FORMAT, `APB4_JPEG__ENCODE_CONFIG,
        `APB4_JPEG__RESTART_INTERVAL, `APB4_JPEG__BITSTREAM_ADDR,
        `APB4_JPEG__BITSTREAM_SIZE, `APB4_JPEG__PLANE0_ADDR,
        `APB4_JPEG__PLANE0_STRIDE, `APB4_JPEG__PLANE1_ADDR,
        `APB4_JPEG__PLANE1_STRIDE, `APB4_JPEG__PLANE2_ADDR,
        `APB4_JPEG__PLANE2_STRIDE, `APB4_JPEG__METADATA_ADDR,
        `APB4_JPEG__METADATA_LENGTH, `APB4_JPEG__RING_BASE, `APB4_JPEG__RING_SIZE,
        `APB4_JPEG__RING_TAIL, `APB4_JPEG__RING_CONTROL, `APB4_JPEG__IRQ_COALESCE,
        `APB4_JPEG__DOORBELL, `APB4_JPEG__TABLE_CONTEXT, `APB4_JPEG__TABLE_KIND,
        `APB4_JPEG__TABLE_INDEX, `APB4_JPEG__TABLE_DATA, `APB4_JPEG__TABLE_COMMAND: begin
          s_access_err = s_access_err;
        end
        default: s_access_err = 1'b1;
      endcase
      if (busy_i && (((s_offset >= `APB4_JPEG__JOB_CONFIG) &&
                      (s_offset <= `APB4_JPEG__METADATA_LENGTH)) ||
                     (s_offset == `APB4_JPEG__RING_BASE) ||
                     (s_offset == `APB4_JPEG__RING_SIZE) ||
                     (s_offset == `APB4_JPEG__RING_CONTROL) ||
                     (s_offset == `APB4_JPEG__IRQ_COALESCE) ||
                     ((s_offset >= `APB4_JPEG__TABLE_CONTEXT) &&
                      (s_offset <= `APB4_JPEG__TABLE_COMMAND)))) begin
        s_access_err = 1'b1;
      end
      if ((s_offset == `APB4_JPEG__COMMAND) &&
          ((s_write_value[`APB4_JPEG__COMMAND_START] && (busy_i || quiesce_i)) ||
           (s_write_value[`APB4_JPEG__COMMAND_ABORT] && !busy_i) ||
           (s_write_value[`APB4_JPEG__COMMAND_SOFT_RESET] && busy_i))) begin
        s_access_err = 1'b1;
      end
      if ((s_offset == `APB4_JPEG__TABLE_CONTEXT) && (s_write_value > 32'd3)) begin
        s_access_err = 1'b1;
      end
      if ((s_offset == `APB4_JPEG__TABLE_KIND) && (s_write_value > 32'd11)) begin
        s_access_err = 1'b1;
      end
    end else if (s_req) begin
      unique case (s_offset)
        `APB4_JPEG__IP_ID, `APB4_JPEG__IP_VERSION, `APB4_JPEG__CAPABILITY0,
        `APB4_JPEG__CAPABILITY1, `APB4_JPEG__STATUS, `APB4_JPEG__IRQ_STATE,
        `APB4_JPEG__IRQ_ENABLE, `APB4_JPEG__ERROR_STATUS, `APB4_JPEG__ERROR_ADDRESS,
        `APB4_JPEG__ERROR_DETAIL, `APB4_JPEG__PERF_CONTROL, `APB4_JPEG__CYCLES_LO,
        `APB4_JPEG__CYCLES_HI, `APB4_JPEG__PIXELS, `APB4_JPEG__INPUT_BYTES,
        `APB4_JPEG__OUTPUT_BYTES, `APB4_JPEG__READ_STALL, `APB4_JPEG__WRITE_STALL,
        `APB4_JPEG__JOB_CONFIG, `APB4_JPEG__IMAGE_SIZE, `APB4_JPEG__INPUT_FORMAT,
        `APB4_JPEG__OUTPUT_FORMAT, `APB4_JPEG__ENCODE_CONFIG,
        `APB4_JPEG__RESTART_INTERVAL, `APB4_JPEG__BITSTREAM_ADDR,
        `APB4_JPEG__BITSTREAM_SIZE, `APB4_JPEG__PLANE0_ADDR,
        `APB4_JPEG__PLANE0_STRIDE, `APB4_JPEG__PLANE1_ADDR,
        `APB4_JPEG__PLANE1_STRIDE, `APB4_JPEG__PLANE2_ADDR,
        `APB4_JPEG__PLANE2_STRIDE, `APB4_JPEG__METADATA_ADDR,
        `APB4_JPEG__METADATA_LENGTH, `APB4_JPEG__RESULT_SIZE,
        `APB4_JPEG__RESULT_IMAGE_SIZE, `APB4_JPEG__RESULT_FORMAT,
        `APB4_JPEG__RESULT_MARKERS, `APB4_JPEG__RING_BASE, `APB4_JPEG__RING_SIZE,
        `APB4_JPEG__RING_HEAD, `APB4_JPEG__RING_TAIL, `APB4_JPEG__RING_CONTROL,
        `APB4_JPEG__RING_STATUS, `APB4_JPEG__IRQ_COALESCE,
        `APB4_JPEG__TABLE_CONTEXT, `APB4_JPEG__TABLE_KIND,
        `APB4_JPEG__TABLE_INDEX, `APB4_JPEG__TABLE_DATA, `APB4_JPEG__TABLE_STATUS: begin
          s_access_err = s_access_err;
        end
        default: s_access_err = 1'b1;
      endcase
    end
  end

  always_comb begin
    s_irq_clear        = 5'd0;
    s_irq_state_d      = s_irq_state_q | s_irq_event;
    s_irq_en_d         = s_irq_en_q;
    s_err_stat_d       = s_err_stat_q;
    s_err_addr_d       = s_err_addr_q;
    s_err_detail_d     = s_err_detail_q;
    s_perf_control_d   = s_perf_control_q;
    s_cfg_d            = s_cfg_q;
    s_ring_d           = s_ring_q;
    s_table_context_d  = s_table_context_q;
    s_table_kind_d     = s_table_kind_q;
    s_table_index_d    = s_table_index_q;
    start_o            = 1'b0;
    abort_o            = 1'b0;
    soft_reset_o       = 1'b0;
    ring_kick_o        = 1'b0;
    table_write_data_o = s_write_value;
    table_write_o      = 1'b0;
    table_commit_o     = 1'b0;
    table_default_o    = 1'b0;
    table_clear_o      = 1'b0;
    perf_clear_o       = 1'b0;

    if (s_write && !s_access_err) begin
      unique case (s_offset)
        `APB4_JPEG__COMMAND: begin
          start_o      = s_write_value[`APB4_JPEG__COMMAND_START];
          abort_o      = s_write_value[`APB4_JPEG__COMMAND_ABORT];
          soft_reset_o = s_write_value[`APB4_JPEG__COMMAND_SOFT_RESET];
          ring_kick_o  = s_write_value[`APB4_JPEG__COMMAND_RING_KICK];
        end
        `APB4_JPEG__IRQ_STATE: s_irq_clear = s_write_value[4:0];
        `APB4_JPEG__IRQ_ENABLE:
        s_irq_en_d = 5'(apply_wstrb({27'd0, s_irq_en_q}, s_write_value, apb4.pstrb));
        `APB4_JPEG__IRQ_TEST: s_irq_state_d |= s_write_value[4:0];
        `APB4_JPEG__ERROR_STATUS: begin
          if (s_write_value[0]) begin
            s_err_stat_d   = 32'd0;
            s_err_addr_d   = 32'd0;
            s_err_detail_d = 32'd0;
          end
        end
        `APB4_JPEG__PERF_CONTROL: begin
          s_perf_control_d = 2'(apply_wstrb({30'd0, s_perf_control_q}, s_write_value, apb4.pstrb));
          perf_clear_o     = s_write_value[1];
        end
        `APB4_JPEG__JOB_CONFIG: s_cfg_d[0] = apply_wstrb(s_cfg_q[0], s_write_value, apb4.pstrb);
        `APB4_JPEG__IMAGE_SIZE: s_cfg_d[1] = apply_wstrb(s_cfg_q[1], s_write_value, apb4.pstrb);
        `APB4_JPEG__INPUT_FORMAT: s_cfg_d[2] = apply_wstrb(s_cfg_q[2], s_write_value, apb4.pstrb);
        `APB4_JPEG__OUTPUT_FORMAT: s_cfg_d[3] = apply_wstrb(s_cfg_q[3], s_write_value, apb4.pstrb);
        `APB4_JPEG__ENCODE_CONFIG: s_cfg_d[4] = apply_wstrb(s_cfg_q[4], s_write_value, apb4.pstrb);
        `APB4_JPEG__RESTART_INTERVAL:
        s_cfg_d[5] = apply_wstrb(s_cfg_q[5], s_write_value, apb4.pstrb);
        `APB4_JPEG__BITSTREAM_ADDR: s_cfg_d[6] = apply_wstrb(s_cfg_q[6], s_write_value, apb4.pstrb);
        `APB4_JPEG__BITSTREAM_SIZE: s_cfg_d[7] = apply_wstrb(s_cfg_q[7], s_write_value, apb4.pstrb);
        `APB4_JPEG__PLANE0_ADDR: s_cfg_d[8] = apply_wstrb(s_cfg_q[8], s_write_value, apb4.pstrb);
        `APB4_JPEG__PLANE0_STRIDE: s_cfg_d[9] = apply_wstrb(s_cfg_q[9], s_write_value, apb4.pstrb);
        `APB4_JPEG__PLANE1_ADDR: s_cfg_d[10] = apply_wstrb(s_cfg_q[10], s_write_value, apb4.pstrb);
        `APB4_JPEG__PLANE1_STRIDE:
        s_cfg_d[11] = apply_wstrb(s_cfg_q[11], s_write_value, apb4.pstrb);
        `APB4_JPEG__PLANE2_ADDR: s_cfg_d[12] = apply_wstrb(s_cfg_q[12], s_write_value, apb4.pstrb);
        `APB4_JPEG__PLANE2_STRIDE:
        s_cfg_d[13] = apply_wstrb(s_cfg_q[13], s_write_value, apb4.pstrb);
        `APB4_JPEG__METADATA_ADDR:
        s_cfg_d[14] = apply_wstrb(s_cfg_q[14], s_write_value, apb4.pstrb);
        `APB4_JPEG__METADATA_LENGTH:
        s_cfg_d[15] = apply_wstrb(s_cfg_q[15], s_write_value, apb4.pstrb);
        `APB4_JPEG__RING_BASE: s_ring_d[0] = apply_wstrb(s_ring_q[0], s_write_value, apb4.pstrb);
        `APB4_JPEG__RING_SIZE: s_ring_d[1] = apply_wstrb(s_ring_q[1], s_write_value, apb4.pstrb);
        `APB4_JPEG__RING_TAIL: s_ring_d[2] = apply_wstrb(s_ring_q[2], s_write_value, apb4.pstrb);
        `APB4_JPEG__RING_CONTROL: s_ring_d[3] = apply_wstrb(s_ring_q[3], s_write_value, apb4.pstrb);
        `APB4_JPEG__IRQ_COALESCE: s_ring_d[4] = apply_wstrb(s_ring_q[4], s_write_value, apb4.pstrb);
        `APB4_JPEG__DOORBELL: ring_kick_o = s_write_value[0];
        `APB4_JPEG__TABLE_CONTEXT: s_table_context_d = s_write_value[1:0];
        `APB4_JPEG__TABLE_KIND: s_table_kind_d = s_write_value[3:0];
        `APB4_JPEG__TABLE_INDEX: s_table_index_d = s_write_value[7:0];
        `APB4_JPEG__TABLE_DATA: begin
          table_write_o   = 1'b1;
          s_table_index_d = s_table_index_q + 1'b1;
        end
        `APB4_JPEG__TABLE_COMMAND: begin
          table_commit_o  = s_write_value[`APB4_JPEG__TABLE_COMMAND_COMMIT];
          table_default_o = s_write_value[`APB4_JPEG__TABLE_COMMAND_DEFAULT];
          table_clear_o   = s_write_value[`APB4_JPEG__TABLE_COMMAND_CLEAR];
        end
        default: begin
        end
      endcase
    end
    s_irq_state_d = (s_irq_state_d & ~s_irq_clear) | s_irq_event;
    if (error_event_i && !s_err_stat_q[0]) begin
      s_err_stat_d   = {20'd0, error_axi_resp_i, error_stage_i, error_code_i, 1'b1};
      s_err_addr_d   = error_addr_i;
      s_err_detail_d = error_detail_i;
    end
    if (soft_reset_o) begin
      s_irq_state_d  = 5'd0;
      s_err_stat_d   = 32'd0;
      s_err_addr_d   = 32'd0;
      s_err_detail_d = 32'd0;
    end
  end

  dffr #(
      .DATA_WIDTH(5)
  ) u_irq_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_irq_state_d),
      .dat_o  (s_irq_state_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_irq_en_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_irq_en_d),
      .dat_o  (s_irq_en_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_err_stat_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_stat_d),
      .dat_o  (s_err_stat_q)
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
  dffr #(
      .DATA_WIDTH(2)
  ) u_perf_control_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_control_d),
      .dat_o  (s_perf_control_q)
  );
  dffr #(
      .DATA_WIDTH(16 * 32)
  ) u_cfg_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cfg_d),
      .dat_o  (s_cfg_q)
  );
  dffr #(
      .DATA_WIDTH(5 * 32)
  ) u_ring_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ring_d),
      .dat_o  (s_ring_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_table_context_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_table_context_d),
      .dat_o  (s_table_context_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_table_kind_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_table_kind_d),
      .dat_o  (s_table_kind_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_table_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_table_index_d),
      .dat_o  (s_table_index_q)
  );
endmodule
