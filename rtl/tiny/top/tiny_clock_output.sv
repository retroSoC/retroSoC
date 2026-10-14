// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

// SYSCTRL validates the source/divisor and requires disable-before-change.
// Synchronize enable to the selected source, configuring the divider while
// disabled. Both package routes consume this one output and enable.
module tiny_clock_output (
    input  logic        clk_ref_i,
    input  logic        clk_sys_i,
    input  logic        clk_mem_i,
    input  logic        clk_periph_i,
    input  logic        rst_n_i,
    input  logic [31:0] control_i,
    output logic        clk_o,
    output logic        enable_o
);
  logic s_src_clk, s_enabled, s_en_req;
  logic [19:0] s_cfg_d, s_cfg_q;
  // Retain the source/divisor through disable acknowledgement. Source zero
  // only disables the output; it does not change a still-running clock.
  assign s_cfg_d = control_i[2:0] != 0 ?
      {1'b1, control_i[23:8], control_i[2:0]} : {1'b0, s_cfg_q[18:0]};
  dffrc #(
      .DATA_WIDTH(20),
      .RESET_VAL ({1'b0, 16'd1, 3'd1})
  ) u_config (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cfg_d),
      .dat_o  (s_cfg_q)
  );
  assign s_src_clk = s_cfg_q[2:0] == 3 ? clk_mem_i :
      s_cfg_q[2:0] == 4 ? clk_periph_i : s_cfg_q[2:0] == 2 ? clk_sys_i : clk_ref_i;
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_enable_sync (
      .clk_i  (s_src_clk),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cfg_q[19]),
      .dat_o  (s_en_req)
  );
  // Finish the current output high pulse before disabling the Common divider.
  ndffr #(
      .DATA_WIDTH(1)
  ) u_enable (
      .clk_i  (s_src_clk),
      .rst_n_i(rst_n_i),
      .dat_i  (s_en_req || clk_o),
      .dat_o  (s_enabled)
  );
  clock_divider #(
      .DIV_WIDTH(16),
      .RESET_DIV(16'd1)
  ) u_divider (
      .clk_i      (s_src_clk),
      .rst_n_i    (rst_n_i),
      .enable_i   (s_enabled),
      .div_i      (s_cfg_q[18:3]),
      .div_valid_i(!s_enabled),
      .div_ready_o(),
      .clk_o      (clk_o),
      .count_o    ()
  );
  assign enable_o = s_enabled;
endmodule
