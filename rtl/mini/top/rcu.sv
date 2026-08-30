// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// Compatibility wrapper around the product clock/reset subsystem. sys_clk_o
// remains the LP clock for older integration consumers.
module rcu #(
    parameter int unsigned RefClkHz        = 24_000_000,
    parameter int unsigned ClintTimebaseHz = 1_000_000
) (
    // verilog_format: off -- preserve the domain clock/reset contract columns
    input  logic           ref24_clk_i,
    input  logic           ext_clk_i,
    input  logic           aud_clk_i,
    input  logic           ext_rst_n_i,
    input  logic           wdg_reset_req_i,
    input  logic           hp_idle_i,
    input  logic           pclk_idle_i,
    pll_ctrl_if.rcu        pll_ctrl,
    clock_ctrl_if.rcu      clock_ctrl,
    output logic           aon_clk_o,
    output logic           aon_rst_n_o,
    output logic           sys_clk_o,
    output logic           sys_rst_n_o,
    output logic           hp_clk_o,
    output logic           hp_rst_n_o,
    output logic           pclk_o,
    output logic           pclk_rst_n_o,
    output logic           mem_clk_o,
    output logic           mem_rst_n_o,
    output logic           aud_clk_o,
    output logic           aud_rst_n_o,
    output logic           sys_clkdiv4_o,
    output logic           timebase_tick_o,
    output logic           hp_block_o,
    output logic           pll_fault_o,
    output logic     [1:0] mem_pad_mode_o,
    output logic           mem_pad_lock_o
    // verilog_format: on
);
  soc_clock_reset_subsystem #(
      .RefClkHz       (RefClkHz),
      .ClintTimebaseHz(ClintTimebaseHz)
  ) u_clock_reset_subsystem (
      .ref24_clk_i    (ref24_clk_i),
      .ext72_clk_i    (ext_clk_i),
      .aud_clk_i      (aud_clk_i),
      .ext_rst_n_i    (ext_rst_n_i),
      .wdg_reset_req_i(wdg_reset_req_i),
      .hp_idle_i      (hp_idle_i),
      .pclk_idle_i    (pclk_idle_i),
      .pll_ctrl       (pll_ctrl),
      .clock_ctrl     (clock_ctrl),
      .aon_clk_o      (aon_clk_o),
      .aon_rst_n_o    (aon_rst_n_o),
      .lp_clk_o       (sys_clk_o),
      .lp_rst_n_o     (sys_rst_n_o),
      .hp_clk_o       (hp_clk_o),
      .hp_rst_n_o     (hp_rst_n_o),
      .pclk_o         (pclk_o),
      .pclk_rst_n_o   (pclk_rst_n_o),
      .mem_clk_o      (mem_clk_o),
      .mem_rst_n_o    (mem_rst_n_o),
      .aud_clk_o      (aud_clk_o),
      .aud_rst_n_o    (aud_rst_n_o),
      .lp_clkdiv4_o   (sys_clkdiv4_o),
      .timebase_tick_o(timebase_tick_o),
      .hp_block_o     (hp_block_o),
      .pll_fault_o    (pll_fault_o),
      .mem_pad_mode_o (mem_pad_mode_o),
      .mem_pad_lock_o (mem_pad_lock_o)
  );
endmodule
