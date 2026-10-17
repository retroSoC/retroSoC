// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

// Deterministic Tiny P9 camera source. The model drives the existing GPIO12-22
// camera profile and remains electrically idle unless +tiny_p9_camera is set.
module tiny_dvp_camera (
    output logic       pclk_o,
    output logic       href_o,
    output logic       vsync_o,
    output logic [7:0] dat_o
);
  integer pixel_half_ns = 500;
  integer h_active;
  integer v_active;
  integer line_count;
  integer byte_count;
  integer frame_count;
  bit     enabled;
  integer state;
  // Verification-only control, written by the opt-in recovery board observer.
  // 0: run, 1: stop low, 2: stop high. Normal camera workloads retain zero.
  integer recovery_pause = 0;

  initial begin
    if ($value$plusargs("tiny_p9_half_ns=%d", pixel_half_ns)) begin
    end
    if (pixel_half_ns < 1) $fatal(1, "invalid Tiny P9 pixel half-period");
    h_active = $test$plusargs("tiny_p9_small") ? 16 : ($test$plusargs("tiny_p9_vga") ? 640 : 320);
    v_active = $test$plusargs("tiny_p9_small") ? 8 : ($test$plusargs("tiny_p9_vga") ? 480 : 240);
    enabled = $test$plusargs("tiny_p9_camera");
    pclk_o = 1'b0;
    href_o = 1'b0;
    vsync_o = 1'b0;
    dat_o = 8'h00;
    line_count = 0;
    byte_count = 0;
    frame_count = 0;
    state = 0;
  end

  always #(pixel_half_ns) begin
    if (enabled && !$test$plusargs("tiny_p9_no_pixclk")) begin
      if (recovery_pause == 0 || (recovery_pause == 1 && pclk_o) ||
          (recovery_pause == 2 && !pclk_o))
        pclk_o = !pclk_o;
    end else if (enabled) begin
      pclk_o = $test$plusargs("tiny_p9_pixclk_high");
    end else begin
      pclk_o = 1'b0;
    end
  end

  always @(posedge pclk_o) begin
    if (!enabled) begin
      href_o  <= 1'b0;
      vsync_o <= 1'b0;
      dat_o   <= 8'h00;
    end else if (state == 0) begin
      vsync_o <= 1'b1;
      href_o  <= 1'b0;
      state   <= 1;
    end else if (state == 1) begin
      vsync_o    <= 1'b0;
      href_o     <= 1'b0;
      line_count <= 0;
      byte_count <= 0;
      state      <= 2;
    end else if (line_count < v_active) begin
      if (byte_count < (h_active * 2)) begin
        href_o     <= 1'b1;
        dat_o      <= 8'(byte_count + (line_count * 3));
        byte_count <= byte_count + 1;
      end else begin
        href_o     <= 1'b0;
        byte_count <= 0;
        line_count <= line_count + 1;
      end
    end else begin
      href_o      <= 1'b0;
      frame_count <= frame_count + 1;
      line_count  <= 0;
      state       <= 0;
    end
  end
endmodule
