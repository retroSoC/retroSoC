// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "dvp_define.svh"

module dvp_core (
    // verilog_format: off
    input  logic         clk_i,
    input  logic         rst_n_i,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [127:0] config_i,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic         config_valid_i,
    input  logic [  1:0] command_i,
    output logic         config_ready_o,
    input  logic         push_ready_i,
    output logic         push_valid_o,
    output logic [ 41:0] push_data_o,
    output logic         active_o,
    output logic         frame_start_toggle_o,
    output logic         line_done_toggle_o,
    output logic         frame_done_toggle_o,
    output logic         error_toggle_o,
    output logic [  5:0] error_flags_o,
    output logic [127:0] frame_stats_o,
    output logic         frame_stats_valid_o,
    input  logic         frame_stats_ready_i,
    input  logic         href_i,
    input  logic         vsync_i,
    input  logic [  7:0] dat_i
    // verilog_format: on
);
  logic        s_en;
  logic        s_snap;
  logic        s_crop_en;
  logic        s_byte_swap;
  logic [ 1:0] s_format;
  logic        s_pixel_swap;
  logic [15:0] s_frm_width;
  logic [15:0] s_frm_height;
  logic [15:0] s_crop_x;
  logic [15:0] s_crop_y;
  logic [15:0] s_crop_width;
  logic [15:0] s_crop_height;
  logic        s_vsync_low;
  logic        s_href_low;

  logic        s_vsync_q;
  logic        s_href_q;
  logic        s_frm_active_q;
  logic [15:0] s_line_q;
  logic [15:0] s_pixel_q;
  logic        s_byte_phase_q;
  logic        s_word_phase_q;
  logic [ 7:0] s_first_byte_q;
  logic [15:0] s_word_q;
  logic [31:0] s_frm_seq_q;
  logic [31:0] s_pixel_total_q;
  logic [15:0] s_word_total_q;
  logic [31:0] s_drop_count_q;
  logic [ 5:0] s_err_flags_q;
  logic        s_out_valid_q;
  logic [41:0] s_out_data_q;
  logic        s_stat_pending_q;
  logic        s_first_word_q;

  logic        s_vsync_active;
  logic        s_href_active;
  logic        s_vsync_rise;
  logic        s_href_fall;
  logic        s_crop_line;
  logic        s_crop_pixel;
  logic        s_last_pixel;
  logic [15:0] s_pixel_word;

  assign s_vsync_active = s_vsync_low ? !vsync_i : vsync_i;
  assign s_href_active = s_href_low ? !href_i : href_i;
  assign s_vsync_rise = s_vsync_active && !s_vsync_q;
  assign s_href_fall = s_href_q && !s_href_active;
  assign s_crop_line    = !s_crop_en ||
                          ((s_line_q >= s_crop_y) &&
                           (s_line_q < (s_crop_y + s_crop_height)));
  assign s_crop_pixel   = !s_crop_en ||
                          ((s_pixel_q >= s_crop_x) &&
                           (s_pixel_q < (s_crop_x + s_crop_width)));
  assign s_last_pixel   = s_crop_en ?
                              (s_pixel_q + 16'd1 >= s_crop_x + s_crop_width) :
                              (s_pixel_q + 16'd1 >= s_frm_width);
  assign s_pixel_word   = s_pixel_swap ?
                              {s_byte_swap ? dat_i : s_first_byte_q,
                               s_byte_swap ? s_first_byte_q : dat_i} :
                              (s_byte_swap ? {dat_i, s_first_byte_q} :
                                              {s_first_byte_q, dat_i});

  assign config_ready_o = !s_stat_pending_q;
  assign push_valid_o = s_out_valid_q;
  assign push_data_o = s_out_data_q;
  assign active_o = s_frm_active_q;

  always_comb begin
    s_en          = config_i[96];
    s_snap        = config_i[97];
    s_crop_en     = config_i[98];
    s_byte_swap   = config_i[102];
    s_vsync_low   = config_i[104];
    s_href_low    = config_i[105];
    s_frm_width   = config_i[15:0];
    s_frm_height  = config_i[31:16];
    s_crop_x      = config_i[47:32];
    s_crop_y      = config_i[63:48];
    s_crop_width  = config_i[79:64];
    s_crop_height = config_i[95:80];
    s_format      = config_i[101:100];
    s_pixel_swap  = config_i[103];
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_vsync_q            <= 1'b0;
      s_href_q             <= 1'b0;
      s_frm_active_q       <= 1'b0;
      s_line_q             <= '0;
      s_pixel_q            <= '0;
      s_byte_phase_q       <= 1'b0;
      s_word_phase_q       <= 1'b0;
      s_first_byte_q       <= '0;
      s_word_q             <= '0;
      s_frm_seq_q          <= '0;
      s_pixel_total_q      <= '0;
      s_word_total_q       <= '0;
      s_drop_count_q       <= '0;
      s_err_flags_q        <= '0;
      s_out_valid_q        <= 1'b0;
      s_out_data_q         <= '0;
      s_stat_pending_q     <= 1'b0;
      s_first_word_q       <= 1'b0;
      frame_start_toggle_o <= 1'b0;
      line_done_toggle_o   <= 1'b0;
      frame_done_toggle_o  <= 1'b0;
      error_toggle_o       <= 1'b0;
      frame_stats_o        <= '0;
      frame_stats_valid_o  <= 1'b0;
    end else begin
      s_vsync_q           <= s_vsync_active;
      s_href_q            <= s_href_active;
      frame_stats_valid_o <= 1'b0;

      if (s_out_valid_q && push_ready_i) s_out_valid_q <= 1'b0;
      if (s_stat_pending_q && frame_stats_ready_i) begin
        s_stat_pending_q    <= 1'b0;
        frame_stats_valid_o <= 1'b1;
      end

      if (config_valid_i && !s_frm_active_q) begin
        if ((s_frm_width == 0) || (s_frm_height == 0) || (s_format > 2'd1) ||
            (s_crop_en && ((s_crop_width == 0) || (s_crop_height == 0)))) begin
          s_err_flags_q[`DVP_ERROR_CONFIG] <= 1'b1;
          error_toggle_o                   <= ~error_toggle_o;
        end
        if (!s_en) s_frm_active_q <= 1'b0;
      end
      if (command_i[`DVP_COMMAND_ABORT]) begin
        s_frm_active_q                  <= 1'b0;
        s_err_flags_q[`DVP_ERROR_ABORT] <= 1'b1;
        error_toggle_o                  <= ~error_toggle_o;
      end
      if (command_i[`DVP_COMMAND_FLUSH]) begin
        s_out_valid_q  <= 1'b0;
        s_byte_phase_q <= 1'b0;
        s_word_phase_q <= 1'b0;
      end

      if (s_en && s_vsync_rise) begin
        if (s_frm_active_q) begin
          frame_done_toggle_o <= ~frame_done_toggle_o;
          frame_stats_o <= {
            s_drop_count_q, s_word_total_q, s_pixel_total_q, s_line_q, s_frm_seq_q + 1'b1
          };
          s_stat_pending_q <= 1'b1;
          s_frm_seq_q <= s_frm_seq_q + 1'b1;
          if (s_snap) begin
            s_frm_active_q <= 1'b0;
          end else begin
            s_line_q        <= '0;
            s_pixel_q       <= '0;
            s_pixel_total_q <= '0;
            s_word_total_q  <= '0;
          end
        end else begin
          s_frm_active_q       <= 1'b1;
          frame_start_toggle_o <= ~frame_start_toggle_o;
          s_first_word_q       <= 1'b1;
          s_line_q             <= '0;
          s_pixel_q            <= '0;
          s_pixel_total_q      <= '0;
          s_word_total_q       <= '0;
        end
      end

      if (s_frm_active_q && s_href_active) begin
        if (!s_byte_phase_q) begin
          s_first_byte_q <= dat_i;
          s_byte_phase_q <= 1'b1;
        end else begin
          if (s_crop_line && s_crop_pixel) begin
            if (!s_word_phase_q) begin
              s_word_q       <= s_pixel_word;
              s_word_phase_q <= 1'b1;
            end else if (!s_out_valid_q || push_ready_i) begin
              s_out_data_q <= {
                s_first_word_q, s_last_pixel, 4'b1111, 4'b1111, s_pixel_word, s_word_q
              };
              s_out_valid_q <= 1'b1;
              s_first_word_q <= 1'b0;
              s_word_phase_q <= 1'b0;
              s_word_total_q <= s_word_total_q + 1'b1;
            end else begin
              s_err_flags_q[`DVP_ERROR_OVERFLOW] <= 1'b1;
              s_drop_count_q                     <= s_drop_count_q + 1'b1;
              error_toggle_o                     <= ~error_toggle_o;
              s_frm_active_q                     <= 1'b0;
            end
            s_pixel_total_q <= s_pixel_total_q + 1'b1;
          end
          s_byte_phase_q <= 1'b0;
          s_pixel_q      <= s_pixel_q + 1'b1;
        end
      end

      if (s_frm_active_q && s_href_fall) begin
        line_done_toggle_o <= ~line_done_toggle_o;
        s_line_q           <= s_line_q + 1'b1;
        s_pixel_q          <= '0;
        s_byte_phase_q     <= 1'b0;
        if (s_word_phase_q && (!s_out_valid_q || push_ready_i)) begin
          s_out_data_q   <= {s_first_word_q, 1'b1, 4'b0011, 4'b0011, 16'd0, s_word_q[15:0]};
          s_out_valid_q  <= 1'b1;
          s_first_word_q <= 1'b0;
          s_word_phase_q <= 1'b0;
          s_word_total_q <= s_word_total_q + 1'b1;
        end else if (s_word_phase_q) begin
          s_err_flags_q[`DVP_ERROR_OVERFLOW] <= 1'b1;
          error_toggle_o                     <= ~error_toggle_o;
          s_frm_active_q                     <= 1'b0;
        end
      end
    end
  end

  assign error_flags_o = s_err_flags_q;
endmodule
