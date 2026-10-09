// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
// Digital output-clock qualification only; the macro has no analog LOCK pin.
// REFCLK must remain live. System source switching belongs to the Tiny RCU.
module tc_pll_ics55_ecos #(
    parameter bit Parked = 1'b0
) (
    input  logic       fref_i,
    input  logic       rst_n_i,
    input  logic [2:0] cfg_sel_i,
    input  logic       cfg_apply_i,
    output logic       pll_capable_o,
    output logic       pll_lock_o,
    output logic       pll_clk_o
);
  logic s_ref_rst_n, s_monitor_rst_n, s_pll_rst_n;
  logic s_apply_seen_q, s_apply, s_valid_q, s_enable;
  logic [ 2:0] s_selection_q;
  logic [ 1:0] s_restart_q;
  logic [ 9:0] s_settle_q;
  logic [12:0] s_budget_q;
  logic [ 6:0] s_window_q;
  logic s_discard_q, s_lock_q;
  logic [2:0] s_good_q;
  logic [15:0] s_count_q, s_count_next, s_gray_q, s_gray_next;
  logic [15:0] s_gray_ref, s_count_ref, s_last_q, s_delta;
  logic [15:0] s_expected, s_tolerance;
  logic [7:0] s_n;
  // Ideal functional supply connections, not a physical rail/ground merge.
  wire        s_vdd = 1'b1;
  wire        s_vss = 1'b0;

  rst_sync #(
      .STAGE(5)
  ) u_ref_reset (
      .clk_i  (fref_i),
      .rst_n_i(rst_n_i),
      .rst_n_o(s_ref_rst_n)
  );
  assign s_apply = cfg_apply_i && !s_apply_seen_q;
  assign s_enable      = !Parked && rst_n_i && s_ref_rst_n && s_valid_q && (s_restart_q == 0) && !s_apply;
  assign s_n = (!Parked && s_selection_q == 3'd7) ? 8'd40 : 8'd32;
  assign pll_capable_o = 1'b1;
  assign pll_lock_o = s_lock_q && s_enable;
  (* keep = 1, dont_touch = "true" *)
  PLL_TOP u_PLL_TOP (
      .AVDD    (s_vdd),
      .AVSS    (s_vss),
      .DVDD    (s_vdd),
      .DVSS    (s_vss),
      .DVDD_DRV(s_vdd),
      .DVSS_DRV(s_vss),
      .EN      (s_enable),
      .BP      (1'b0),
      .N       (s_n),
      .SELECT  (1'b0),
      .OD      (2'd2),
      .REFCLK  (fref_i),
      .CKOUT1  (pll_clk_o),
      .CKOUT2  (),
      .CKTST   ()            // No extra functional domain or package pin.
  );

  assign s_monitor_rst_n = s_enable && (s_settle_q == 10'd512);
  rst_sync #(
      .STAGE(5)
  ) u_pll_reset (
      .clk_i  (pll_clk_o),
      .rst_n_i(s_monitor_rst_n),
      .rst_n_o(s_pll_rst_n)
  );
  assign s_count_next = s_count_q + 16'd1;
  bin2gray #(
      .DATA_WIDTH(16)
  ) u_encode (
      .bin_i (s_count_next),
      .gray_o(s_gray_next)
  );
  // Register Gray in the source domain: combinational binary-to-Gray glitches
  // must not cross into REFCLK. All bits belong to one Gray-coded counter.
  always_ff @(posedge pll_clk_o or negedge s_pll_rst_n) begin
    if (!s_pll_rst_n) begin
      s_count_q <= '0;
      s_gray_q  <= '0;
    end else begin
      s_count_q <= s_count_next;
      s_gray_q  <= s_gray_next;
    end
  end
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(16)
  ) u_count_sync (
      .clk_i  (fref_i),
      .rst_n_i(s_monitor_rst_n),
      .dat_i  (s_gray_q),
      .dat_o  (s_gray_ref)
  );
  gray2bin #(
      .DATA_WIDTH(16)
  ) u_decode (
      .gray_i(s_gray_ref),
      .bin_o (s_count_ref)
  );
  assign s_delta     = s_count_ref - s_last_q;
  assign s_expected  = (s_selection_q == 3'd7) ? 16'd1280 : 16'd1024;
  assign s_tolerance = (s_selection_q == 3'd7) ? 16'd20 : 16'd16;

  always_ff @(posedge fref_i or negedge s_ref_rst_n) begin
    if (!s_ref_rst_n) begin
      s_apply_seen_q <= 1'b0;
      s_selection_q  <= '0;
      s_valid_q      <= 1'b0;
      s_restart_q    <= '0;
      s_settle_q     <= '0;
      s_budget_q     <= '0;
      s_window_q     <= '0;
      s_discard_q    <= 1'b1;
      s_good_q       <= '0;
      s_lock_q       <= 1'b0;
      s_last_q       <= '0;
    end else begin
      s_apply_seen_q <= cfg_apply_i;
      if (s_apply) begin
        s_selection_q <= cfg_sel_i;
        s_valid_q     <= (cfg_sel_i == 3'd5) || (cfg_sel_i == 3'd7);
        s_restart_q   <= 2'd2;
        s_settle_q    <= '0;
        s_budget_q    <= '0;
        s_window_q    <= '0;
        s_discard_q   <= 1'b1;
        s_good_q      <= '0;
        s_lock_q      <= 1'b0;
        s_last_q      <= '0;
      end else if (s_valid_q) begin
        if (s_restart_q != 0) begin
          s_restart_q <= s_restart_q - 2'd1;
        end else begin
          if (!s_lock_q) s_budget_q <= s_budget_q + 13'd1;
          else s_budget_q <= '0;
          if (!s_lock_q && s_budget_q == 13'd4095) begin
            s_valid_q <= 1'b0;
            s_lock_q  <= 1'b0;
          end else if (s_settle_q != 10'd512) begin
            s_settle_q <= s_settle_q + 10'd1;
          end else if (s_window_q == 7'd127) begin
            s_window_q  <= '0;
            s_last_q    <= s_count_ref;
            s_discard_q <= 1'b0;
            if (s_discard_q) begin
              s_good_q <= '0;
            end else if ((s_delta >= s_expected - s_tolerance) &&
                         (s_delta <= s_expected + s_tolerance)) begin
              if (s_good_q < 3'd4) s_good_q <= s_good_q + 3'd1;
              if (s_good_q >= 3'd3) s_lock_q <= 1'b1;
            end else begin
              s_good_q <= '0;
              s_lock_q <= 1'b0;
            end
          end else begin
            s_window_q <= s_window_q + 7'd1;
          end
        end
      end
    end
  end
endmodule
