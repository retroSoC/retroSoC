// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

// Passive ST7789VI four-wire SPI panel observer for the Tiny SPI-P4 flow.
// The model never drives the display pads and stays fully dormant unless
// +tiny_spi_p4 is set. It decodes the mode-0 MSB-first byte stream, tracks
// command/parameter chains and RAMWR pixel windows, and emits the records
// consumed by scripts/spi_p4.py; plain numeric fields are hexadecimal.
module tiny_st7789_panel (
    input logic sck_i,
    input logic csn_i,
    input logic mosi_i,
    input logic dc_i,
    input logic test_done_i
);
  bit            s_enabled;
  bit            s_cmd_active;
  bit            s_pixel_mode;
  bit            s_seen_slpout;
  bit            s_seen_dispon;
  bit            s_panel_done;
  logic   [ 7:0] s_shift;
  logic   [ 7:0] s_cmd_code;
  logic   [ 7:0] s_madctl;
  logic   [15:0] s_param_shift;
  logic   [31:0] s_win_fnv;
  logic   [31:0] s_panel_fnv;
  integer        s_bit_count;
  integer        s_param_count;
  integer        s_win_bytes;
  integer        s_win_x0;
  integer        s_win_y0;
  integer        s_win_x1;
  integer        s_win_y1;
  integer        s_commands;
  integer        s_windows;
  integer        s_pixels;
  integer        s_violations;

  task automatic record_violation(input integer code_i);
    begin
      s_violations = s_violations + 1;
      $display("SPI_P4_VIOLATION code=%0h", code_i);
    end
  endtask

  task automatic complete_command;
    begin
      $display("SPI_P4_CMD code=%02h params=%0h madctl=%02h", s_cmd_code, s_param_count, s_madctl);
      s_commands   = s_commands + 1;
      s_cmd_active = 1'b0;
    end
  endtask

  task automatic close_window;
    integer pairs;
    integer expected;
    integer aborted;
    begin
      pairs    = s_win_bytes / 2;
      expected = (s_win_x1 - s_win_x0 + 1) * (s_win_y1 - s_win_y0 + 1);
      aborted  = (pairs < expected) ? 1 : 0;
      if ((s_win_bytes % 2) != 0 && !aborted) record_violation(4);
      s_windows = s_windows + 1;
      s_pixels  = s_pixels + pairs;
      $display(
          "SPI_P4_WINDOW seq=%0h x0=%0h y0=%0h x1=%0h y1=%0h pixels=%0h fnv1a=%08h aborted=%0h",
          s_windows, s_win_x0, s_win_y0, s_win_x1, s_win_y1, pairs, s_win_fnv, aborted);
      s_pixel_mode = 1'b0;
    end
  endtask

  task automatic accept_byte(input logic [7:0] byte_i);
    begin
      if (!dc_i) begin
        if (s_pixel_mode) close_window;
        if (s_cmd_active) complete_command;
        s_cmd_active  = 1'b1;
        s_cmd_code    = byte_i;
        s_param_count = 0;
        s_param_shift = 16'h0000;
        if (byte_i == 8'h11) s_seen_slpout = 1'b1;
        if (byte_i == 8'h29) s_seen_dispon = 1'b1;
        if (byte_i == 8'h2c) begin
          if (!s_seen_slpout) record_violation(2);
          // RAMWR takes no parameters; its pixel stream closes the window.
          complete_command;
          s_pixel_mode = 1'b1;
          s_win_bytes  = 0;
          s_win_fnv    = 32'd2166136261;
        end
      end else if (s_pixel_mode) begin
        s_win_bytes = s_win_bytes + 1;
        s_win_fnv   = (s_win_fnv ^ {24'd0, byte_i}) * 32'd16777619;
        s_panel_fnv = (s_panel_fnv ^ {24'd0, byte_i}) * 32'd16777619;
      end else if (s_cmd_active) begin
        s_param_count = s_param_count + 1;
        s_param_shift = {s_param_shift[7:0], byte_i};
        if ((s_cmd_code == 8'h36) && (s_param_count == 1)) s_madctl = byte_i;
        if ((s_cmd_code == 8'h2a) && (s_param_count == 2)) s_win_x0 = {16'd0, s_param_shift};
        if ((s_cmd_code == 8'h2a) && (s_param_count == 4)) s_win_x1 = {16'd0, s_param_shift};
        if ((s_cmd_code == 8'h2b) && (s_param_count == 2)) s_win_y0 = {16'd0, s_param_shift};
        if ((s_cmd_code == 8'h2b) && (s_param_count == 4)) s_win_y1 = {16'd0, s_param_shift};
      end else begin
        record_violation(3);
      end
    end
  endtask

  initial begin
    s_enabled     = $test$plusargs("tiny_spi_p4");
    s_cmd_active  = 1'b0;
    s_pixel_mode  = 1'b0;
    s_seen_slpout = 1'b0;
    s_seen_dispon = 1'b0;
    s_panel_done  = 1'b0;
    s_shift       = 8'h00;
    s_cmd_code    = 8'h00;
    s_madctl      = 8'h00;
    s_param_shift = 16'h0000;
    s_win_fnv     = 32'd2166136261;
    s_panel_fnv   = 32'd2166136261;
    s_bit_count   = 0;
    s_param_count = 0;
    s_win_bytes   = 0;
    s_win_x0      = 0;
    s_win_y0      = 0;
    s_win_x1      = 0;
    s_win_y1      = 0;
    s_commands    = 0;
    s_windows     = 0;
    s_pixels      = 0;
    s_violations  = 0;
  end

  always @(posedge sck_i) begin
    if (s_enabled && !csn_i) begin
      if (s_bit_count == 7) begin
        s_bit_count = 0;
        accept_byte({s_shift[6:0], mosi_i});
        s_shift = 8'h00;
      end else begin
        s_shift     = {s_shift[6:0], mosi_i};
        s_bit_count = s_bit_count + 1;
      end
    end
  end

  always @(posedge csn_i) begin
    if (s_enabled) begin
      if (s_bit_count != 0) begin
        if (!s_pixel_mode ||
            ((s_win_bytes / 2) >=
             ((s_win_x1 - s_win_x0 + 1) * (s_win_y1 - s_win_y0 + 1))))
          record_violation(1);
        s_bit_count = 0;
      end
      if (s_pixel_mode) close_window;
      if (s_cmd_active) complete_command;
    end
  end

  always @(negedge csn_i) begin
    if (s_enabled) s_bit_count = 0;
  end

  always @(posedge test_done_i) begin
    if (s_enabled && !s_panel_done) begin
      s_panel_done = 1'b1;
      $display("SPI_P4_PANEL commands=%0h windows=%0h pixels=%0h fnv1a=%08h violations=%0h",
               s_commands, s_windows, s_pixels, s_panel_fnv, s_violations);
    end
  end
endmodule
