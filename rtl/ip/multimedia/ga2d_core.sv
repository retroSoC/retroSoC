// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "ga2d_define.svh"
`include "mmap_define.svh"

module ga2d_core (
    // All state is PCLK-local.  bridge_epoch_i is consumed only at the existing
    // PCLK source endpoint, where a changed epoch invalidates local ownership.
    input  logic                          clk_i,
    input  logic                          rst_n_i,
    input  logic                          start_i,
    input  logic                          abort_i,
    input  logic                          soft_reset_i,
    input  logic                          resource_stop_i,
    input  logic                          bridge_clear_busy_i,
    input  logic                   [ 7:0] bridge_epoch_i,
    input  logic                          data_ready_i,
    input  logic                   [ 1:0] mem_pad_mode_i,
    /* verilator lint_off UNUSEDSIGNAL */
    input  ga2d_pkg::ga2d_config_t        config_i,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic                          busy_o,
    output logic                          draining_o,
    output logic                          done_o,
    output logic                          aborted_o,
    output logic                          error_o,
    output logic                          recovery_required_o,
    output logic                          safe_idle_o,
    output logic                   [ 2:0] irq_event_o,
    output logic                          error_valid_o,
    output logic                   [ 6:0] error_code_o,
    output logic                   [ 3:0] error_stage_o,
    output logic                   [ 1:0] error_axi_response_o,
    output logic                   [31:0] error_address_o,
    output logic                   [63:0] cycles_o,
    output logic                   [63:0] read_bytes_o,
    output logic                   [63:0] write_bytes_o,
    output logic                   [63:0] read_stalls_o,
    output logic                   [63:0] write_stalls_o,
    output logic                   [63:0] pipe_stalls_o,
    output logic                   [15:0] lines_done_o,
           axi4_if.master                 axi4
);
  import ga2d_pkg::ga2d_config_t;

  typedef enum logic [1:0] {
    Idle,
    Validate,
    Run,
    Drain
  } state_e;

  localparam logic [2:0] IrqDoneEvent = 3'b001 << `APB4_GA2D__IRQ_DONE;
  localparam logic [2:0] IrqErrorEvent = 3'b001 << `APB4_GA2D__IRQ_ERROR;
  localparam logic [2:0] IrqAbortDoneEvent = 3'b001 << `APB4_GA2D__IRQ_ABORT_DONE;

  state_e              s_state_q;
  ga2d_config_t        s_job_q;
  logic         [ 7:0] s_epoch_seen_q;
  logic                s_recovery_q;
  logic                s_recovery_seen_not_ready_q;
  logic                s_done_q;
  logic                s_aborted_q;
  logic                s_abort_reqed_q;
  logic                s_err_q;
  logic         [31:0] s_timeout_count_q;
  logic         [63:0] s_cycles_q;
  logic         [63:0] s_read_bytes_q;
  logic         [63:0] s_write_bytes_q;
  logic         [63:0] s_read_stalls_q;
  logic         [63:0] s_write_stalls_q;
  logic         [63:0] s_pipe_stalls_q;
  logic         [15:0] s_lines_done_q;
  logic         [ 2:0] s_irq_event_q;
  logic                s_err_valid_q;
  logic         [ 6:0] s_err_code_q;
  logic         [ 3:0] s_err_stage_q;
  logic         [ 1:0] s_err_axi_rsp_q;
  logic         [31:0] s_err_addr_q;
  logic                s_validation_err;
  logic         [ 6:0] s_validation_code;
  logic         [ 3:0] s_validation_stage;
  logic         [31:0] s_validation_addr;
  logic         [ 2:0] s_dst_bpp;
  logic         [ 2:0] s_fg_bpp;
  logic         [ 2:0] s_bg_bpp;
  logic         [31:0] s_dst_row_bytes;
  logic         [31:0] s_fg_row_bytes;
  logic         [31:0] s_bg_row_bytes;
  logic         [64:0] s_dst_end;
  logic         [64:0] s_fg_end;
  logic         [64:0] s_bg_end;
  logic                s_op_fill;
  logic                s_op_copy;
  logic                s_op_blend;
  logic                s_fg_used;
  logic                s_bg_used;
  logic                s_fg_color_format;
  logic                s_bg_color_format;
  logic                s_dst_color_format;
  logic                s_bg_dst_exact;
  logic                s_epoch_changed;
  logic                s_dma_clear;
  logic                s_dma_start;
  logic                s_dma_stop;
  logic                unused_dma_busy;
  logic                s_dma_draining;
  logic                s_dma_idle;
  logic                s_dma_done;
  logic                s_dma_aborted;
  logic                s_dma_err_valid;
  logic         [ 6:0] s_dma_err_code;
  logic         [ 3:0] s_dma_err_stage;
  logic         [ 1:0] s_dma_err_rsp;
  logic         [31:0] s_dma_err_addr;
  logic                s_dma_progress;
  logic         [ 7:0] s_dma_read_bytes;
  logic         [ 7:0] s_dma_write_bytes;
  logic                s_dma_line_done;
  logic                s_dma_read_stall;
  logic                s_dma_write_stall;
  logic                s_dma_pipe_stall;
  logic                s_timeout_expired;
  logic                s_runtime_stop;

  function automatic logic [2:0] bytes_per_pixel(input logic [2:0] format_i);
    unique case (format_i)
      `APB4_GA2D__FORMAT_RGB565:                                return 3'd2;
      `APB4_GA2D__FORMAT_RGB888:                                return 3'd3;
      `APB4_GA2D__FORMAT_XRGB8888, `APB4_GA2D__FORMAT_ARGB8888: return 3'd4;
      `APB4_GA2D__FORMAT_A8:                                    return 3'd1;
      default:                                                  return '0;
    endcase
  endfunction

  function automatic logic color_format(input logic [2:0] format_i);
    return (format_i == `APB4_GA2D__FORMAT_RGB565) ||
           (format_i == `APB4_GA2D__FORMAT_RGB888) ||
           (format_i == `APB4_GA2D__FORMAT_XRGB8888) ||
           (format_i == `APB4_GA2D__FORMAT_ARGB8888);
  endfunction

  function automatic logic naturally_aligned(input logic [31:0] value_i, input logic [2:0] bytes_i);
    unique case (bytes_i)
      3'd1:    return 1'b1;
      3'd2:    return value_i[0] == 1'b0;
      3'd3:    return 1'b1;
      3'd4:    return value_i[1:0] == 2'd0;
      default: return 1'b0;
    endcase
  endfunction

  function automatic logic [64:0] plane_end(input logic [31:0] base_i, input logic [31:0] pitch_i,
                                            input logic [31:0] row_bytes_i,
                                            input logic [15:0] height_i);
    logic [64:0] s_rows;
    logic [64:0] s_pitch;
    begin
      s_rows  = {49'd0, height_i} - 1'b1;
      s_pitch = {33'd0, pitch_i};
      return {33'd0, base_i} + (s_rows * s_pitch) + {33'd0, row_bytes_i};
    end
  endfunction

  function automatic logic range_allowed(input logic [31:0] base_i, input logic [64:0] end_i,
                                         input logic write_i);
    logic [64:0] s_sram_end;
    logic [64:0] s_sdram_end;
    logic [64:0] s_psram_end;
    logic [64:0] s_opipsram_end;
    logic [64:0] s_xpi_end;
    begin
      s_sram_end     = {33'd0, `SOC_ADDR_SRAM_BASE} + {33'd0, `SOC_ADDR_SRAM_SIZE};
      s_sdram_end    = {33'd0, `SOC_ADDR_SDRAM_BASE} + {33'd0, `SOC_ADDR_SDRAM_SIZE};
      s_psram_end    = {33'd0, `SOC_ADDR_PSRAM_BASE} + {33'd0, `SOC_ADDR_PSRAM_SIZE};
      s_opipsram_end = {33'd0, `SOC_ADDR_OPIPSRAM_BASE} + {33'd0, `SOC_ADDR_OPIPSRAM_SIZE};
      s_xpi_end      = {33'd0, `SOC_ADDR_XPI_BASE} + {33'd0, `SOC_ADDR_XPI_SIZE};
      if ((base_i >= `SOC_ADDR_SRAM_BASE) && (end_i <= s_sram_end)) begin
        return 1'b1;
      end
      if ((base_i >= `SOC_ADDR_SDRAM_BASE) && (end_i <= s_sdram_end)) begin
        return 1'b1;
      end
      if ((mem_pad_mode_i == 2'd1) && (base_i >= `SOC_ADDR_PSRAM_BASE) &&
          (end_i <= s_psram_end)) begin
        return 1'b1;
      end
      if ((mem_pad_mode_i == 2'd2) && (base_i >= `SOC_ADDR_OPIPSRAM_BASE) &&
          (end_i <= s_opipsram_end)) begin
        return 1'b1;
      end
      if (!write_i && (base_i >= `SOC_ADDR_XPI_BASE) && (end_i <= s_xpi_end)) begin
        return 1'b1;
      end
      return 1'b0;
    end
  endfunction

  function automatic logic [63:0] saturating_add(input logic [63:0] value_i,
                                                 input logic [7:0] increment_i);
    logic [64:0] s_sum;
    begin
      s_sum = {1'b0, value_i} + {57'd0, increment_i};
      return s_sum[64] ? 64'hffff_ffff_ffff_ffff : s_sum[63:0];
    end
  endfunction

  function automatic logic [15:0] saturating_line_add(input logic [15:0] value_i,
                                                      input logic increment_i);
    if (increment_i && (&value_i)) begin
      return value_i;
    end
    return value_i + increment_i;
  endfunction

  assign s_op_fill = s_job_q.job_config[1:0] == `APB4_GA2D__OP_FILL;
  assign s_op_copy = s_job_q.job_config[1:0] == `APB4_GA2D__OP_COPY;
  assign s_op_blend = s_job_q.job_config[1:0] == `APB4_GA2D__OP_BLEND;
  assign s_fg_used = !s_op_fill;
  assign s_bg_used = s_op_blend;
  assign s_dst_color_format = color_format(s_job_q.dst_format[2:0]);
  assign s_fg_color_format = color_format(s_job_q.fg_format[2:0]);
  assign s_bg_color_format = color_format(s_job_q.bg_format[2:0]);
  assign s_dst_bpp = bytes_per_pixel(s_job_q.dst_format[2:0]);
  assign s_fg_bpp = bytes_per_pixel(s_job_q.fg_format[2:0]);
  assign s_bg_bpp = bytes_per_pixel(s_job_q.bg_format[2:0]);
  assign s_dst_row_bytes = {16'd0, s_job_q.size[15:0]} * {29'd0, s_dst_bpp};
  assign s_fg_row_bytes = {16'd0, s_job_q.size[15:0]} * {29'd0, s_fg_bpp};
  assign s_bg_row_bytes = {16'd0, s_job_q.size[15:0]} * {29'd0, s_bg_bpp};
  assign s_dst_end = plane_end(
      s_job_q.dst_address, s_job_q.dst_pitch, s_dst_row_bytes, s_job_q.size[31:16]
  );
  assign s_fg_end = plane_end(
      s_job_q.fg_address, s_job_q.fg_pitch, s_fg_row_bytes, s_job_q.size[31:16]
  );
  assign s_bg_end = plane_end(
      s_job_q.bg_address, s_job_q.bg_pitch, s_bg_row_bytes, s_job_q.size[31:16]
  );
  assign s_bg_dst_exact = (s_job_q.bg_address == s_job_q.dst_address) &&
                          (s_job_q.bg_pitch == s_job_q.dst_pitch) &&
                          (s_job_q.bg_format == s_job_q.dst_format);
  assign s_epoch_changed = bridge_epoch_i != s_epoch_seen_q;
  assign s_dma_clear = bridge_clear_busy_i || s_epoch_changed;
  assign s_dma_start = (s_state_q == Validate) && !s_validation_err;
  assign s_runtime_stop = abort_i || resource_stop_i || bridge_clear_busy_i || s_epoch_changed;
  assign s_dma_stop = (s_state_q == Drain) || ((s_state_q == Run) && s_runtime_stop);
  assign s_timeout_expired = (s_state_q == Run) && !s_dma_progress &&
                             (s_timeout_count_q == (s_job_q.timeout_cycles - 1'b1));

  ga2d_dma u_dma (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .clear_i              (s_dma_clear),
      .start_i              (s_dma_start),
      .stop_i               (s_dma_stop),
      .operation_i          (s_job_q.job_config[1:0]),
      .width_i              (s_job_q.size[15:0]),
      .height_i             (s_job_q.size[31:16]),
      .foreground_format_i  (s_job_q.fg_format[2:0]),
      .foreground_address_i (s_job_q.fg_address),
      .foreground_pitch_i   (s_job_q.fg_pitch),
      .background_format_i  (s_job_q.bg_format[2:0]),
      .background_address_i (s_job_q.bg_address),
      .background_pitch_i   (s_job_q.bg_pitch),
      .destination_format_i (s_job_q.dst_format[2:0]),
      .destination_address_i(s_job_q.dst_address),
      .destination_pitch_i  (s_job_q.dst_pitch),
      .color_i              (s_job_q.color),
      .global_alpha_i       (s_job_q.global_alpha[7:0]),
      .inplace_background_i (s_op_blend && s_bg_dst_exact),
      .busy_o               (unused_dma_busy),
      .draining_o           (s_dma_draining),
      .idle_o               (s_dma_idle),
      .done_o               (s_dma_done),
      .aborted_o            (s_dma_aborted),
      .error_valid_o        (s_dma_err_valid),
      .error_code_o         (s_dma_err_code),
      .error_stage_o        (s_dma_err_stage),
      .error_response_o     (s_dma_err_rsp),
      .error_address_o      (s_dma_err_addr),
      .progress_o           (s_dma_progress),
      .read_bytes_o         (s_dma_read_bytes),
      .write_bytes_o        (s_dma_write_bytes),
      .line_done_o          (s_dma_line_done),
      .read_stall_o         (s_dma_read_stall),
      .write_stall_o        (s_dma_write_stall),
      .pipe_stall_o         (s_dma_pipe_stall),
      .axi4                 (axi4)
  );

  always_comb begin
    s_validation_err   = 1'b0;
    s_validation_code  = `APB4_GA2D__ERROR_NONE;
    s_validation_stage = `APB4_GA2D__ERROR_STAGE_VALIDATE;
    s_validation_addr  = '0;
    if ((s_job_q.size[15:0] == 16'd0) || (s_job_q.size[31:16] == 16'd0)) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_INVALID_SIZE;
    end else if (!s_dst_color_format) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_INVALID_FORMAT;
    end else if (s_fg_used &&
                 ((!s_fg_color_format && !(s_op_blend &&
                                            (s_job_q.fg_format[2:0] ==
                                             `APB4_GA2D__FORMAT_A8))) ||
                  (s_op_copy && (s_job_q.fg_format[2:0] != s_job_q.dst_format[2:0])))) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_INVALID_FORMAT;
    end else if (s_bg_used && !s_bg_color_format) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_INVALID_FORMAT;
    end else if (!naturally_aligned(s_job_q.dst_address, s_dst_bpp)) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_INVALID_ALIGNMENT;
      s_validation_addr = s_job_q.dst_address;
    end else if (s_fg_used && !naturally_aligned(s_job_q.fg_address, s_fg_bpp)) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_INVALID_ALIGNMENT;
      s_validation_addr = s_job_q.fg_address;
    end else if (s_bg_used && !naturally_aligned(s_job_q.bg_address, s_bg_bpp)) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_INVALID_ALIGNMENT;
      s_validation_addr = s_job_q.bg_address;
    end else if ((s_job_q.dst_pitch < s_dst_row_bytes) || !naturally_aligned(
            s_job_q.dst_pitch, s_dst_bpp
        )) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_INVALID_PITCH;
      s_validation_addr = s_job_q.dst_address;
    end else if (s_fg_used && ((s_job_q.fg_pitch < s_fg_row_bytes) || !naturally_aligned(
            s_job_q.fg_pitch, s_fg_bpp
        ))) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_INVALID_PITCH;
      s_validation_addr = s_job_q.fg_address;
    end else if (s_bg_used && ((s_job_q.bg_pitch < s_bg_row_bytes) || !naturally_aligned(
            s_job_q.bg_pitch, s_bg_bpp
        ))) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_INVALID_PITCH;
      s_validation_addr = s_job_q.bg_address;
    end else if (s_dst_end > 65'h1_0000_0000) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_ADDRESS_OVERFLOW;
      s_validation_addr = s_job_q.dst_address;
    end else if (s_fg_used && (s_fg_end > 65'h1_0000_0000)) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_ADDRESS_OVERFLOW;
      s_validation_addr = s_job_q.fg_address;
    end else if (s_bg_used && (s_bg_end > 65'h1_0000_0000)) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_ADDRESS_OVERFLOW;
      s_validation_addr = s_job_q.bg_address;
    end else if (!range_allowed(s_job_q.dst_address, s_dst_end, 1'b1)) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_ADDRESS_RANGE;
      s_validation_addr = s_job_q.dst_address;
    end else if (s_fg_used && !range_allowed(s_job_q.fg_address, s_fg_end, 1'b0)) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_ADDRESS_RANGE;
      s_validation_addr = s_job_q.fg_address;
    end else if (s_bg_used && !range_allowed(s_job_q.bg_address, s_bg_end, 1'b0)) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_ADDRESS_RANGE;
      s_validation_addr = s_job_q.bg_address;
    end else if (s_fg_used && ({33'd0, s_job_q.dst_address} < s_fg_end) &&
                 ({33'd0, s_job_q.fg_address} < s_dst_end)) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_OVERLAP;
      s_validation_addr = s_job_q.dst_address;
    end else if (s_bg_used && !s_bg_dst_exact &&
                 ({33'd0, s_job_q.dst_address} < s_bg_end) &&
                 ({33'd0, s_job_q.bg_address} < s_dst_end)) begin
      s_validation_err  = 1'b1;
      s_validation_code = `APB4_GA2D__ERROR_OVERLAP;
      s_validation_addr = s_job_q.dst_address;
    end
  end

  assign busy_o = s_state_q != Idle;
  assign draining_o = (s_state_q == Drain) || ((s_state_q == Run) && s_runtime_stop) ||
                      s_dma_draining;
  assign done_o = s_done_q;
  assign aborted_o = s_aborted_q;
  assign error_o = s_err_q;
  assign recovery_required_o = s_recovery_q || bridge_clear_busy_i || !data_ready_i ||
                               s_epoch_changed;
  assign safe_idle_o = (s_state_q == Idle) && s_dma_idle;
  assign irq_event_o = s_irq_event_q;
  assign error_valid_o = s_err_valid_q;
  assign error_code_o = s_err_code_q;
  assign error_stage_o = s_err_stage_q;
  assign error_axi_response_o = s_err_axi_rsp_q;
  assign error_address_o = s_err_addr_q;
  assign cycles_o = s_cycles_q;
  assign read_bytes_o = s_read_bytes_q;
  assign write_bytes_o = s_write_bytes_q;
  assign read_stalls_o = s_read_stalls_q;
  assign write_stalls_o = s_write_stalls_q;
  assign pipe_stalls_o = s_pipe_stalls_q;
  assign lines_done_o = s_lines_done_q;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q                   <= Idle;
      s_job_q                     <= '0;
      s_epoch_seen_q              <= '0;
      s_recovery_q                <= 1'b0;
      s_recovery_seen_not_ready_q <= 1'b0;
      s_done_q                    <= 1'b0;
      s_aborted_q                 <= 1'b0;
      s_abort_reqed_q             <= 1'b0;
      s_err_q                     <= 1'b0;
      s_timeout_count_q           <= '0;
      s_cycles_q                  <= '0;
      s_read_bytes_q              <= '0;
      s_write_bytes_q             <= '0;
      s_read_stalls_q             <= '0;
      s_write_stalls_q            <= '0;
      s_pipe_stalls_q             <= '0;
      s_lines_done_q              <= '0;
      s_irq_event_q               <= '0;
      s_err_valid_q               <= 1'b0;
      s_err_code_q                <= '0;
      s_err_stage_q               <= '0;
      s_err_axi_rsp_q             <= '0;
      s_err_addr_q                <= '0;
    end else begin
      s_epoch_seen_q <= bridge_epoch_i;
      s_irq_event_q  <= '0;
      s_err_valid_q  <= 1'b0;

      if (!data_ready_i) begin
        s_recovery_seen_not_ready_q <= 1'b1;
      end
      if (s_epoch_changed || bridge_clear_busy_i) begin
        s_recovery_q <= 1'b1;
      end else if (s_recovery_q && s_recovery_seen_not_ready_q && data_ready_i &&
                   (s_state_q == Idle) && s_dma_idle) begin
        s_recovery_q                <= 1'b0;
        s_recovery_seen_not_ready_q <= 1'b0;
      end

      if (soft_reset_i) begin
        s_state_q         <= Idle;
        s_done_q          <= 1'b0;
        s_aborted_q       <= 1'b0;
        s_abort_reqed_q   <= 1'b0;
        s_err_q           <= 1'b0;
        s_timeout_count_q <= '0;
        s_cycles_q        <= '0;
        s_read_bytes_q    <= '0;
        s_write_bytes_q   <= '0;
        s_read_stalls_q   <= '0;
        s_write_stalls_q  <= '0;
        s_pipe_stalls_q   <= '0;
        s_lines_done_q    <= '0;
      end else begin
        if (s_state_q != Idle) begin
          s_cycles_q <= saturating_add(s_cycles_q, 8'd1);
          if (s_dma_read_stall) begin
            s_read_stalls_q <= saturating_add(s_read_stalls_q, 8'd1);
          end
          if (s_dma_write_stall) begin
            s_write_stalls_q <= saturating_add(s_write_stalls_q, 8'd1);
          end
          if (s_dma_pipe_stall) begin
            s_pipe_stalls_q <= saturating_add(s_pipe_stalls_q, 8'd1);
          end
          s_read_bytes_q  <= saturating_add(s_read_bytes_q, s_dma_read_bytes);
          s_write_bytes_q <= saturating_add(s_write_bytes_q, s_dma_write_bytes);
          s_lines_done_q  <= saturating_line_add(s_lines_done_q, s_dma_line_done);
          if ((s_state_q == Validate) || s_dma_progress) begin
            s_timeout_count_q <= '0;
          end else if (s_timeout_count_q != 32'hffff_ffff) begin
            s_timeout_count_q <= s_timeout_count_q + 1'b1;
          end
        end else begin
          s_timeout_count_q <= '0;
        end

        unique case (s_state_q)
          Idle: begin
            if (start_i && data_ready_i && !resource_stop_i && !s_recovery_q &&
                !bridge_clear_busy_i && !s_epoch_changed) begin
              s_job_q.timeout_cycles <= config_i.timeout_cycles;
              s_job_q.job_config     <= config_i.job_config;
              s_job_q.global_alpha   <= config_i.global_alpha;
              s_job_q.color          <= config_i.color;
              s_job_q.size           <= config_i.size;
              s_job_q.fg_address     <= config_i.fg_address;
              s_job_q.fg_pitch       <= config_i.fg_pitch;
              s_job_q.fg_format      <= config_i.fg_format;
              s_job_q.bg_address     <= config_i.bg_address;
              s_job_q.bg_pitch       <= config_i.bg_pitch;
              s_job_q.bg_format      <= config_i.bg_format;
              s_job_q.dst_address    <= config_i.dst_address;
              s_job_q.dst_pitch      <= config_i.dst_pitch;
              s_job_q.dst_format     <= config_i.dst_format;
              s_done_q               <= 1'b0;
              s_aborted_q            <= 1'b0;
              s_abort_reqed_q        <= 1'b0;
              s_err_q                <= 1'b0;
              s_cycles_q             <= '0;
              s_read_bytes_q         <= '0;
              s_write_bytes_q        <= '0;
              s_read_stalls_q        <= '0;
              s_write_stalls_q       <= '0;
              s_pipe_stalls_q        <= '0;
              s_lines_done_q         <= '0;
              s_timeout_count_q      <= '0;
              s_state_q              <= Validate;
            end
          end
          Validate: begin
            if (s_validation_err) begin
              s_err_q         <= 1'b1;
              s_err_valid_q   <= 1'b1;
              s_err_code_q    <= s_validation_code;
              s_err_stage_q   <= s_validation_stage;
              s_err_axi_rsp_q <= '0;
              s_err_addr_q    <= s_validation_addr;
              s_irq_event_q   <= IrqErrorEvent;
              s_state_q       <= Idle;
            end else if (s_runtime_stop) begin
              s_abort_reqed_q <= abort_i || resource_stop_i;
              s_state_q       <= Drain;
            end else begin
              s_state_q <= Run;
            end
          end
          Run: begin
            if (s_epoch_changed || bridge_clear_busy_i) begin
              s_err_q         <= 1'b1;
              s_err_valid_q   <= 1'b1;
              s_err_code_q    <= `APB4_GA2D__ERROR_EPOCH_LOST;
              s_err_stage_q   <= `APB4_GA2D__ERROR_STAGE_LIFECYCLE;
              s_err_axi_rsp_q <= '0;
              s_err_addr_q    <= '0;
              s_irq_event_q   <= IrqErrorEvent;
              s_state_q       <= Drain;
            end else if (s_dma_err_valid) begin
              s_abort_reqed_q <= abort_i || resource_stop_i;
              s_err_q         <= 1'b1;
              s_err_valid_q   <= 1'b1;
              s_err_code_q    <= s_dma_err_code;
              s_err_stage_q   <= s_dma_err_stage;
              s_err_axi_rsp_q <= s_dma_err_rsp;
              s_err_addr_q    <= s_dma_err_addr;
              s_irq_event_q   <= IrqErrorEvent;
              if (s_dma_err_code == `APB4_GA2D__ERROR_AXI_PROTOCOL) begin
                s_recovery_q <= 1'b1;
              end
              s_state_q <= Drain;
            end else if (abort_i || resource_stop_i) begin
              s_abort_reqed_q <= 1'b1;
              s_state_q       <= Drain;
            end else if (s_timeout_expired) begin
              s_err_q         <= 1'b1;
              s_err_valid_q   <= 1'b1;
              s_err_code_q    <= `APB4_GA2D__ERROR_TIMEOUT;
              s_err_stage_q   <= `APB4_GA2D__ERROR_STAGE_LIFECYCLE;
              s_err_axi_rsp_q <= '0;
              s_err_addr_q    <= '0;
              s_irq_event_q   <= IrqErrorEvent;
              s_recovery_q    <= 1'b1;
              s_state_q       <= Drain;
            end else if (s_dma_done) begin
              s_done_q      <= 1'b1;
              s_irq_event_q <= IrqDoneEvent;
              s_state_q     <= Idle;
            end
          end
          Drain: begin
            // A later abort is still meaningful while an earlier error drains.
            // Include the live inputs below to cover the final-retirement cycle.
            if (abort_i || resource_stop_i) begin
              s_abort_reqed_q <= 1'b1;
            end
            if (s_dma_err_valid && (s_dma_err_code == `APB4_GA2D__ERROR_AXI_PROTOCOL)) begin
              s_recovery_q <= 1'b1;
            end
            if (s_dma_err_valid && !s_err_q) begin
              s_err_q         <= 1'b1;
              s_err_valid_q   <= 1'b1;
              s_err_code_q    <= s_dma_err_code;
              s_err_stage_q   <= s_dma_err_stage;
              s_err_axi_rsp_q <= s_dma_err_rsp;
              s_err_addr_q    <= s_dma_err_addr;
              s_irq_event_q   <= IrqErrorEvent;
            end
            if (s_dma_idle) begin
              if (s_dma_aborted || s_recovery_q || s_abort_reqed_q || abort_i ||
                  resource_stop_i) begin
                if (s_abort_reqed_q || abort_i || resource_stop_i) begin
                  s_aborted_q   <= 1'b1;
                  s_irq_event_q <= s_irq_event_q | IrqAbortDoneEvent;
                end
                s_state_q <= Idle;
              end
            end
          end
          default: begin
            s_err_q         <= 1'b1;
            s_err_valid_q   <= 1'b1;
            s_err_code_q    <= `APB4_GA2D__ERROR_INTERNAL;
            s_err_stage_q   <= `APB4_GA2D__ERROR_STAGE_LIFECYCLE;
            s_err_axi_rsp_q <= '0;
            s_err_addr_q    <= '0;
            s_irq_event_q   <= IrqErrorEvent;
            s_state_q       <= Drain;
          end
        endcase
      end
    end
  end
endmodule
