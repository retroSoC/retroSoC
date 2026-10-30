`include "ppalite_define.svh"

module ppalite_core (
    input  logic                  clk_i,
    input  logic                  rst_n_i,
    input  logic                  in_valid_i,
    output logic                  in_ready_o,
    input  logic           [31:0] in_data_i,
    input  logic           [ 3:0] in_keep_i,
    input  logic           [ 3:0] in_strb_i,
    input  logic                  in_id_i,
    input  logic                  in_dest_i,
    input  logic                  in_user_i,
    input  logic                  in_last_i,
    output logic                  out_valid_o,
    input  logic                  out_ready_i,
    output logic           [31:0] out_data_o,
    output logic           [ 3:0] out_keep_o,
    output logic           [ 3:0] out_strb_o,
    output logic                  out_last_o,
    output logic                  out_id_o,
    output logic                  out_dest_o,
    output logic                  out_user_o,
           ppalite_if.core        ctrl
);
  logic        s_active_q;
  logic        s_clear;
  logic        s_flush;
  logic        s_slot_valid;
  logic        s_slot_pop;
  logic [31:0] s_slot_data;
  logic        s_slot_halfword;
  logic        s_pixel_index_q;
  logic [15:0] s_x_q;
  logic [15:0] s_y_q;
  logic [15:0] s_pixel;
  logic        s_consume;
  logic        s_pixel_last;
  logic        s_packer_ready;
  logic        s_packer_idle;
  logic        s_sel;
  logic        s_line_sel;
  logic [15:0] s_sample;
  logic [ 7:0] s_guard_err;
  logic [31:0] s_guard_position;
  logic        s_framing_event;
  logic [31:0] s_framing_position;
  logic        s_excess_err;
  logic [31:0] s_excess_position;
  logic [ 7:0] s_output_err_q;
  logic [31:0] s_output_position_q;
  logic        s_out_fire;
  logic        s_all_consumed;

  assign s_clear = ctrl.cmd[`PPALITE_COMMAND_ARM] ||
      ctrl.cmd[`PPALITE_COMMAND_RECOVER] || ctrl.cmd[`PPALITE_COMMAND_RESET];
  assign s_flush = s_clear || ctrl.cmd[`PPALITE_COMMAND_RELEASE];
  assign s_pixel = s_pixel_index_q ? s_slot_data[31:16] : s_slot_data[15:0];
  assign s_pixel_last = s_slot_halfword || s_pixel_index_q;
  assign s_consume = s_active_q && (ctrl.state != `PPALITE_STATE_CLOSING) && !ctrl.close &&
      (s_guard_err == 8'd0) && (s_output_err_q == 8'd0) && s_slot_valid && s_packer_ready;
  assign s_slot_pop = s_consume && s_pixel_last;
  assign s_out_fire = out_valid_o && out_ready_i;
  assign s_all_consumed = ctrl.input_done && !s_slot_valid;
  assign ctrl.started = s_active_q && (ctrl.input_words != 32'd0);
  assign ctrl.local_idle = !out_valid_o;
  assign ctrl.pipe_done = s_active_q && s_all_consumed && s_packer_idle &&
      (ctrl.output_words == ctrl.expected_words) &&
      (ctrl.output_lines == {16'd0, ctrl.output_size[31:16]});
  logic        s_output_fault;
  logic [ 7:0] s_output_live_err;
  logic [31:0] s_output_live_position;

  assign s_output_fault = s_active_q && s_all_consumed && s_packer_idle &&
      ((ctrl.output_words != ctrl.expected_words) ||
       (ctrl.output_lines != {16'd0, ctrl.output_size[31:16]})) && (s_output_err_q == 8'd0);
  assign s_output_live_err = s_output_fault ? `PPALITE_ERROR_OUTPUT : 8'd0;
  assign s_output_live_position = s_output_fault ? {s_y_q, s_x_q} : s_output_position_q;

  always_comb begin
    ctrl.core_err     = (s_output_err_q != 8'd0) ? s_output_err_q : s_output_live_err;
    ctrl.err_position = (s_output_err_q != 8'd0) ? s_output_position_q : s_output_live_position;
    if ((s_guard_err != 8'd0) && ((ctrl.core_err == 8'd0) || (s_guard_err <= ctrl.core_err))) begin
      ctrl.core_err     = s_guard_err;
      ctrl.err_position = s_guard_position;
    end
    if (s_excess_err && ((ctrl.core_err == 8'd0) || (ctrl.core_err > 8'd4))) begin
      ctrl.core_err     = `PPALITE_ERROR_GEOMETRY;
      ctrl.err_position = s_excess_position;
    end
    if (s_framing_event && ((ctrl.core_err == 8'd0) || (ctrl.core_err > 8'd3))) begin
      ctrl.core_err     = `PPALITE_ERROR_FRAMING;
      ctrl.err_position = s_framing_position;
    end
  end
  assign ctrl.output_stall_event = out_valid_o && !out_ready_i;
  assign ctrl.excess             = s_excess_err;
  assign ctrl.excess_position    = s_excess_position;

  logic        s_active_d;
  logic        s_pixel_index_d;
  logic [15:0] s_x_d;
  logic [15:0] s_y_d;
  logic [31:0] s_input_pixels_d;
  logic [31:0] s_input_lines_d;
  logic [31:0] s_sel_pixels_d;
  logic [31:0] s_output_words_d;
  logic [31:0] s_output_lines_d;
  logic [31:0] s_output_stall_cycles_d;
  logic [ 3:0] s_output_high_water_d;
  logic [ 7:0] s_output_err_d;
  logic [31:0] s_output_position_d;

  always_comb begin
    s_active_d = s_active_q;
    if (!rst_n_i) begin
      s_active_d = 1'b0;
    end else if (ctrl.cmd[`PPALITE_COMMAND_ARM]) begin
      s_active_d = 1'b1;
    end else if (ctrl.close || ctrl.cmd[`PPALITE_COMMAND_RELEASE] ||
        ctrl.cmd[`PPALITE_COMMAND_ABORT] || ctrl.cmd[`PPALITE_COMMAND_RECOVER] ||
        ctrl.cmd[`PPALITE_COMMAND_RESET] || (s_guard_err != 8'd0) ||
        (s_output_err_q != 8'd0)) begin
      s_active_d = 1'b0;
    end
  end

  always_comb begin
    s_pixel_index_d         = s_pixel_index_q;
    s_x_d                   = s_x_q;
    s_y_d                   = s_y_q;
    s_input_pixels_d        = ctrl.input_pixels;
    s_input_lines_d         = ctrl.input_lines;
    s_sel_pixels_d          = ctrl.sel_pixels;
    s_output_words_d        = ctrl.output_words;
    s_output_lines_d        = ctrl.output_lines;
    s_output_stall_cycles_d = ctrl.output_stall_cycles;
    s_output_high_water_d   = ctrl.output_high_water;
    s_output_err_d          = s_output_err_q;
    s_output_position_d     = s_output_position_q;
    if (!rst_n_i || s_clear) begin
      s_pixel_index_d         = 1'b0;
      s_x_d                   = 16'd0;
      s_y_d                   = 16'd0;
      s_input_pixels_d        = 32'd0;
      s_input_lines_d         = 32'd0;
      s_sel_pixels_d          = 32'd0;
      s_output_words_d        = 32'd0;
      s_output_lines_d        = 32'd0;
      s_output_stall_cycles_d = 32'd0;
      s_output_high_water_d   = 4'd0;
      s_output_err_d          = 8'd0;
      s_output_position_d     = 32'd0;
    end else begin
      if (s_consume) begin
        s_input_pixels_d = ctrl.input_pixels + 32'd1;
        if (s_sel) s_sel_pixels_d = ctrl.sel_pixels + 32'd1;
        s_pixel_index_d = !s_pixel_last;
        if (s_x_q + 16'd1 == ctrl.input_size[15:0]) begin
          s_x_d           = 16'd0;
          s_y_d           = s_y_q + 16'd1;
          s_input_lines_d = ctrl.input_lines + 32'd1;
        end else begin
          s_x_d = s_x_q + 16'd1;
        end
      end
      if (s_out_fire) begin
        s_output_words_d = ctrl.output_words + 32'd1;
        if (out_last_o) s_output_lines_d = ctrl.output_lines + 32'd1;
      end
      if (out_valid_o && !out_ready_i && (ctrl.output_stall_cycles != 32'hffff_ffff)) begin
        s_output_stall_cycles_d = ctrl.output_stall_cycles + 32'd1;
      end
      if (ctrl.output_level > ctrl.output_high_water) begin
        s_output_high_water_d = ctrl.output_level;
      end
      if (s_active_q && s_all_consumed && s_packer_idle &&
          ((ctrl.output_words != ctrl.expected_words) ||
           (ctrl.output_lines != {16'd0, ctrl.output_size[31:16]})) &&
          (s_output_err_q == 8'd0)) begin
        s_output_err_d      = `PPALITE_ERROR_OUTPUT;
        s_output_position_d = {s_y_q, s_x_q};
      end
    end
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_active_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_active_d),
      .dat_o  (s_active_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_pixel_index_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pixel_index_d),
      .dat_o  (s_pixel_index_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_x_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_x_d),
      .dat_o  (s_x_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_y_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_y_d),
      .dat_o  (s_y_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_input_pixels_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_input_pixels_d),
      .dat_o  (ctrl.input_pixels)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_input_lines_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_input_lines_d),
      .dat_o  (ctrl.input_lines)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_sel_pixels_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sel_pixels_d),
      .dat_o  (ctrl.sel_pixels)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_output_words_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_output_words_d),
      .dat_o  (ctrl.output_words)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_output_lines_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_output_lines_d),
      .dat_o  (ctrl.output_lines)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_output_stall_cycles_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_output_stall_cycles_d),
      .dat_o  (ctrl.output_stall_cycles)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_output_high_water_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_output_high_water_d),
      .dat_o  (ctrl.output_high_water)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_output_err_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_output_err_d),
      .dat_o  (s_output_err_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_output_position_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_output_position_d),
      .dat_o  (s_output_position_q)
  );

  ppalite_stream_guard u_stream_guard (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .clear_i           (s_clear),
      .flush_i           (s_flush),
      .active_i          (s_active_q && (ctrl.state != `PPALITE_STATE_CLOSING) && !ctrl.close),
      .width_i           (ctrl.input_size[15:0]),
      .height_i          (ctrl.input_size[31:16]),
      .valid_i           (in_valid_i),
      .ready_o           (in_ready_o),
      .data_i            (in_data_i),
      .keep_i            (in_keep_i),
      .strb_i            (in_strb_i),
      .id_i              (in_id_i),
      .dest_i            (in_dest_i),
      .user_i            (in_user_i),
      .last_i            (in_last_i),
      .slot_valid_o      (s_slot_valid),
      .slot_pop_i        (s_slot_pop),
      .slot_data_o       (s_slot_data),
      .slot_halfword_o   (s_slot_halfword),
      .input_done_o      (ctrl.input_done),
      .input_done_event_o(ctrl.input_done_event),
      .framing_event_o   (s_framing_event),
      .framing_position_o(s_framing_position),
      .excess_o          (s_excess_err),
      .excess_position_o (s_excess_position),
      .input_words_o     (ctrl.input_words),
      .stall_cycles_o    (ctrl.input_stall_cycles),
      .level_o           (ctrl.input_level),
      .err_o             (s_guard_err),
      .err_position_o    (s_guard_position)
  );

  ppalite_decimator u_decimator (
      .format_i          (ctrl.cfg[2:0]),
      .gray8_i           (ctrl.cfg[3]),
      .rgb_swap_i        (ctrl.cfg[4]),
      .output_byte_swap_i(ctrl.cfg[5]),
      .step_x_i          (ctrl.sampling[1:0]),
      .step_y_i          (ctrl.sampling[3:2]),
      .phase_x_i         (ctrl.sampling[9:8]),
      .phase_y_i         (ctrl.sampling[11:10]),
      .x_i               (s_x_q),
      .y_i               (s_y_q),
      .pixel_i           (s_pixel),
      .sel_o             (s_sel),
      .line_sel_o        (s_line_sel),
      .sample_o          (s_sample)
  );

  ppalite_packer u_packer (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .flush_i    (s_flush),
      .gray8_i    (ctrl.cfg[3]),
      .row_bytes_i(ctrl.row_bytes),
      .valid_i    (s_consume),
      .ready_o    (s_packer_ready),
      .sel_i      (s_sel),
      .line_sel_i (s_line_sel),
      .line_end_i (s_x_q + 16'd1 == ctrl.input_size[15:0]),
      .sample_i   (s_sample),
      .valid_o    (out_valid_o),
      .ready_i    (out_ready_i),
      .data_o     (out_data_o),
      .keep_o     (out_keep_o),
      .strb_o     (out_strb_o),
      .last_o     (out_last_o),
      .id_o       (out_id_o),
      .dest_o     (out_dest_o),
      .user_o     (out_user_o),
      .level_o    (ctrl.output_level),
      .idle_o     (s_packer_idle)
  );

`ifdef FORMAL
  always_ff @(posedge clk_i) begin
    if (rst_n_i && s_active_q) begin
      assert (s_x_q < ctrl.input_size[15:0]);
      if (out_valid_o && $past(out_valid_o && !out_ready_i)) begin
        assert (out_valid_o && $stable({out_data_o, out_last_o, out_user_o}));
      end
    end
    if (rst_n_i && s_framing_event) begin
      assert (!s_consume);
      assert (ctrl.core_err == `PPALITE_ERROR_FRAMING);
    end
    if (rst_n_i && s_excess_err && !s_framing_event) begin
      assert (ctrl.core_err == `PPALITE_ERROR_GEOMETRY);
    end
  end
`endif
endmodule
