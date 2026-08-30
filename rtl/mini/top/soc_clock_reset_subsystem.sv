// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module soc_clock_reset_subsystem #(
    parameter int unsigned RefClkHz        = 24_000_000,
    parameter int unsigned ClintTimebaseHz = 1_000_000
) (
    // verilog_format: off -- preserve the domain clock/reset contract columns
    input  logic           ref24_clk_i,
    input  logic           ext72_clk_i,
    input  logic           aud_clk_i,
    input  logic           ext_rst_n_i,
    input  logic           wdg_reset_req_i,
    input  logic           hp_idle_i,
    input  logic           pclk_idle_i,
    pll_ctrl_if.rcu        pll_ctrl,
    clock_ctrl_if.rcu      clock_ctrl,
    output logic           aon_clk_o,
    output logic           aon_rst_n_o,
    output logic           lp_clk_o,
    output logic           lp_rst_n_o,
    output logic           hp_clk_o,
    output logic           hp_core_clk_o,
    output logic           hp_rst_n_o,
    output logic           pclk_o,
    output logic           pclk_rst_n_o,
    output logic           mem_clk_o,
    output logic           mem_rst_n_o,
    output logic           aud_clk_o,
    output logic           aud_rst_n_o,
    output logic           lp_clkdiv4_o,
    output logic           timebase_tick_o,
    output logic           hp_block_o,
    output logic           pll_fault_o,
    output logic     [1:0] mem_pad_mode_o,
    output logic           mem_pad_lock_o
    // verilog_format: on
);
  logic        s_ref24_clk_buf;
  logic        s_ext72_clk_buf;
  logic        s_aud_clk_buf;
  logic        s_aon_rst_n;
  logic        s_domain_reset_source_n;
  logic        s_pll_clk;
  logic        s_pll_clk_buf;
  logic        s_pll_lock;
  logic        s_pll_capable;
  logic [ 2:0] s_pll_sel;
  logic        s_pll_apply;
  logic        s_sel_ext_clk;
  logic        s_pll_force_lp_ref;
  logic        s_lp_force_ref;
  logic        s_hp_root_clk;
  logic        s_hp_core_clk;
  logic        s_hp_div2_clk;
  logic        s_hp_div4_clk;
  logic        s_lp_perf_div2_or_more_clk;
  logic        s_lp_perf_clk;
  logic        s_lp_root_clk;
  logic        s_pclk;
  logic        s_mem_clk_div2;
  logic        s_lp_clk_div4;
  logic [ 1:0] s_lp_mode;
  logic [ 1:0] s_lp_div;
  logic [ 2:0] s_pclk_div;
  logic [ 7:0] s_gate_mask;
  logic [15:0] s_timeout;
  logic        s_pclk_update;
  logic        s_force_safe;
  logic        s_clear_fault;
  logic [ 1:0] s_req_lp_div;
  logic [ 1:0] s_effective_lp_div;
  logic [ 2:0] s_pclk_cfg_data;
  logic        s_pclk_cfg_valid;
  logic        s_pclk_cfg_ready;
  logic        s_pclk_cfg_src_ready;
  logic [ 4:0] s_pclk_div_value;
  logic        s_pclk_div_done;
  logic [ 4:0] s_pclk_count;
  logic        s_pclk_first_trigger;
  logic        s_pclk_second_trigger;
  logic        s_hp_idle_aon;
  logic        s_pclk_idle_aon;
  logic        s_pll_fault;
  logic [ 3:0] s_clock_alive;
  logic [ 3:0] s_clock_fault;
  logic [63:0] s_clock_edge_delta;

  tc_clk_buf u_ref24_clk_buf (
      .clk_i(ref24_clk_i),
      .clk_o(s_ref24_clk_buf)
  );
  tc_clk_buf u_ext72_clk_buf (
      .clk_i(ext72_clk_i),
      .clk_o(s_ext72_clk_buf)
  );
  tc_clk_buf u_aud_clk_buf (
      .clk_i(aud_clk_i),
      .clk_o(s_aud_clk_buf)
  );

  rst_sync #(
      .STAGE(5)
  ) u_aon_rst_sync (
      .clk_i  (s_ref24_clk_buf),
      .rst_n_i(ext_rst_n_i),
      .rst_n_o(s_aon_rst_n)
  );

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_hp_idle_sync (
      .clk_i  (s_ref24_clk_buf),
      .rst_n_i(s_aon_rst_n),
      .dat_i  (hp_idle_i),
      .dat_o  (s_hp_idle_aon)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_pclk_idle_sync (
      .clk_i  (s_ref24_clk_buf),
      .rst_n_i(s_aon_rst_n),
      .dat_i  (pclk_idle_i),
      .dat_o  (s_pclk_idle_aon)
  );

`ifdef HAVE_PLL
  tc_pll u_tc_pll (
      .fref_i       (s_ref24_clk_buf),
      .rst_n_i      (s_aon_rst_n),
      .cfg_sel_i    (s_pll_sel),
      .cfg_apply_i  (s_pll_apply),
      .pll_capable_o(s_pll_capable),
      .pll_lock_o   (s_pll_lock),
      .pll_clk_o    (s_pll_clk)
  );
`else
  assign s_pll_capable = 1'b0;
  assign s_pll_lock    = 1'b0;
  assign s_pll_clk     = s_ext72_clk_buf;
`endif

  tc_clk_buf u_pll_clk_buf (
      .clk_i(s_pll_clk),
      .clk_o(s_pll_clk_buf)
  );

  safe_clock_mux u_hp_root_mux (
      .clk0_i  (s_pll_clk_buf),
      .clk1_i  (s_ext72_clk_buf),
      .rst_n_i (s_aon_rst_n),
      .select_i(s_sel_ext_clk),
      .clk_o   (s_hp_root_clk)
  );

  soc_clock_gate u_hp_core_clock_gate (
      .clk_i    (s_hp_root_clk),
      .en_i     (!s_gate_mask[0]),
      .test_en_i(1'b0),
      .clk_o    (s_hp_core_clk)
  );

  clk_int_even_div_static #(
      .DIV_VALUE_WIDTH(1)
  ) u_hp_div2 (
      .clk_i  (s_hp_root_clk),
      .rst_n_i(s_aon_rst_n),
      .clk_o  (s_hp_div2_clk)
  );

  clk_int_even_div_static #(
      .DIV_VALUE_WIDTH(2)
  ) u_hp_div4 (
      .clk_i  (s_hp_root_clk),
      .rst_n_i(s_aon_rst_n),
      .clk_o  (s_hp_div4_clk)
  );

  always_comb begin
    if (s_sel_ext_clk || (s_pll_sel == 3'd0)) begin
      s_req_lp_div = 2'd0;
    end else if (s_pll_sel <= 3'd3) begin
      s_req_lp_div = 2'd1;
    end else begin
      s_req_lp_div = 2'd2;
    end
    if (s_lp_mode == 2'd1) begin
      s_effective_lp_div = s_req_lp_div;
    end else if (s_lp_div < s_req_lp_div) begin
      s_effective_lp_div = s_req_lp_div;
    end else begin
      s_effective_lp_div = s_lp_div;
    end
  end

  safe_clock_mux u_lp_perf_div2_mux (
      .clk0_i  (s_hp_root_clk),
      .clk1_i  (s_hp_div2_clk),
      .rst_n_i (s_aon_rst_n),
      .select_i(s_effective_lp_div != 2'd0),
      .clk_o   (s_lp_perf_div2_or_more_clk)
  );

  safe_clock_mux u_lp_perf_div4_mux (
      .clk0_i  (s_lp_perf_div2_or_more_clk),
      .clk1_i  (s_hp_div4_clk),
      .rst_n_i (s_aon_rst_n),
      .select_i(s_effective_lp_div == 2'd2),
      .clk_o   (s_lp_perf_clk)
  );

  assign s_lp_force_ref = s_pll_force_lp_ref || (s_lp_mode == 2'd0);

  safe_clock_mux u_lp_root_mux (
      .clk0_i  (s_ref24_clk_buf),
      .clk1_i  (s_lp_perf_clk),
      .rst_n_i (s_aon_rst_n),
      .select_i(!s_lp_force_ref),
      .clk_o   (s_lp_root_clk)
  );

  cdc_2phase #(
      .DATA_WIDTH(3)
  ) u_pclk_cfg_cdc (
      .src_clk_i  (s_ref24_clk_buf),
      .src_rst_n_i(s_aon_rst_n),
      .src_data_i (s_pclk_div),
      .src_valid_i(s_pclk_update),
      .src_ready_o(s_pclk_cfg_src_ready),
      .dst_clk_i  (s_lp_root_clk),
      .dst_rst_n_i(lp_rst_n_o),
      .dst_data_o (s_pclk_cfg_data),
      .dst_valid_o(s_pclk_cfg_valid),
      .dst_ready_i(s_pclk_cfg_ready)
  );

  always_comb begin
    unique case (s_pclk_cfg_data)
      3'd0:    s_pclk_div_value = 5'd0;
      3'd1:    s_pclk_div_value = 5'd1;
      3'd2:    s_pclk_div_value = 5'd3;
      3'd3:    s_pclk_div_value = 5'd7;
      default: s_pclk_div_value = 5'd15;
    endcase
  end

  clk_int_div_simple #(
      .DIV_VALUE_WIDTH (5),
      .DONE_DELAY_WIDTH(3)
  ) u_pclk_divider (
      .clk_i        (s_lp_root_clk),
      .rst_n_i      (s_aon_rst_n),
      .div_i        (s_pclk_div_value),
      .clk_init_i   (1'b0),
      .div_valid_i  (s_pclk_cfg_valid),
      .div_ready_o  (s_pclk_cfg_ready),
      .div_done_o   (s_pclk_div_done),
      .clk_cnt_o    (s_pclk_count),
      .clk_fir_trg_o(s_pclk_first_trigger),
      .clk_sec_trg_o(s_pclk_second_trigger),
      .clk_o        (s_pclk)
  );

  clk_int_even_div_static #(
      .DIV_VALUE_WIDTH(1)
  ) u_mem_clk_div2 (
      .clk_i  (s_ext72_clk_buf),
      .rst_n_i(s_aon_rst_n),
      .clk_o  (s_mem_clk_div2)
  );

  clk_int_even_div_static #(
      .DIV_VALUE_WIDTH(2)
  ) u_lp_clk_div4 (
      .clk_i  (s_lp_root_clk),
      .rst_n_i(s_aon_rst_n),
      .clk_o  (s_lp_clk_div4)
  );

  clock_frequency_monitor u_ext72_monitor (
      .ref_clk_i        (s_ref24_clk_buf),
      .ref_rst_n_i      (s_aon_rst_n),
      .monitored_clk_i  (s_ext72_clk_buf),
      .monitored_rst_n_i(s_aon_rst_n),
      .clear_fault_i    (s_clear_fault),
      .alive_o          (s_clock_alive[0]),
      .fault_o          (s_clock_fault[0]),
      .edge_delta_o     (s_clock_edge_delta[15:0])
  );
  clock_frequency_monitor u_hp_monitor (
      .ref_clk_i        (s_ref24_clk_buf),
      .ref_rst_n_i      (s_aon_rst_n),
      .monitored_clk_i  (s_hp_root_clk),
      .monitored_rst_n_i(s_aon_rst_n),
      .clear_fault_i    (s_clear_fault),
      .alive_o          (s_clock_alive[1]),
      .fault_o          (s_clock_fault[1]),
      .edge_delta_o     (s_clock_edge_delta[31:16])
  );
  clock_frequency_monitor u_pclk_monitor (
      .ref_clk_i        (s_ref24_clk_buf),
      .ref_rst_n_i      (s_aon_rst_n),
      .monitored_clk_i  (s_pclk),
      .monitored_rst_n_i(s_aon_rst_n),
      .clear_fault_i    (s_clear_fault),
      .alive_o          (s_clock_alive[2]),
      .fault_o          (s_clock_fault[2]),
      .edge_delta_o     (s_clock_edge_delta[47:32])
  );
  clock_frequency_monitor u_memory_monitor (
      .ref_clk_i        (s_ref24_clk_buf),
      .ref_rst_n_i      (s_aon_rst_n),
      .monitored_clk_i  (s_mem_clk_div2),
      .monitored_rst_n_i(s_aon_rst_n),
      .clear_fault_i    (s_clear_fault),
      .alive_o          (s_clock_alive[3]),
      .fault_o          (s_clock_fault[3]),
      .edge_delta_o     (s_clock_edge_delta[63:48])
  );

  pll_rcu_controller u_pll_rcu_controller (
      .sys_clk_i     (s_pclk),
      .sys_rst_n_i   (pclk_rst_n_o),
      .ext_clk_i     (s_ref24_clk_buf),
      .ext_rst_n_i   (s_aon_rst_n),
      .pll_lock_i    (s_pll_lock),
      .pll_capable_i (s_pll_capable),
      .hp_idle_i     (s_hp_idle_aon),
      .pclk_idle_i   (s_pclk_idle_aon),
      .timeout_i     (s_timeout),
      .force_safe_i  (s_force_safe),
      .clear_fault_i (s_clear_fault),
      .pll_sel_o     (s_pll_sel),
      .pll_apply_o   (s_pll_apply),
      .sel_ext_clk_o (s_sel_ext_clk),
      .hp_block_o    (hp_block_o),
      .lp_force_ref_o(s_pll_force_lp_ref),
      .pll_fault_o   (s_pll_fault),
      .pll_ctrl      (pll_ctrl)
  );

  clock_config_controller u_clock_config_controller (
      .ctrl_clk_i    (s_pclk),
      .ctrl_rst_n_i  (pclk_rst_n_o),
      .aon_clk_i     (s_ref24_clk_buf),
      .aon_rst_n_i   (s_aon_rst_n),
      .hp_pstate_i   (s_pll_sel),
      .hp_pll_sel_i  (!s_sel_ext_clk),
      .pll_fault_i   (s_pll_fault || (|s_clock_fault)),
      .pclk_idle_i   (s_pclk_idle_aon),
      .clock_ctrl    (clock_ctrl),
      .lp_mode_o     (s_lp_mode),
      .lp_div_o      (s_lp_div),
      .pclk_div_o    (s_pclk_div),
      .gate_mask_o   (s_gate_mask),
      .timeout_o     (s_timeout),
      .pclk_update_o (s_pclk_update),
      .force_safe_o  (s_force_safe),
      .clear_fault_o (s_clear_fault),
      .mem_pad_mode_o(mem_pad_mode_o),
      .mem_pad_lock_o(mem_pad_lock_o)
  );

  assign s_domain_reset_source_n = ext_rst_n_i && !wdg_reset_req_i && s_aon_rst_n;

  rst_sync #(
      .STAGE(5)
  ) u_lp_rst_sync (
      .clk_i  (s_lp_root_clk),
      .rst_n_i(s_domain_reset_source_n),
      .rst_n_o(lp_rst_n_o)
  );
  rst_sync #(
      .STAGE(5)
  ) u_hp_rst_sync (
      .clk_i  (s_hp_root_clk),
      .rst_n_i(s_domain_reset_source_n),
      .rst_n_o(hp_rst_n_o)
  );
  rst_sync #(
      .STAGE(5)
  ) u_pclk_rst_sync (
      .clk_i  (s_pclk),
      .rst_n_i(s_domain_reset_source_n),
      .rst_n_o(pclk_rst_n_o)
  );
  rst_sync #(
      .STAGE(5)
  ) u_mem_rst_sync (
      .clk_i  (s_mem_clk_div2),
      .rst_n_i(s_domain_reset_source_n),
      .rst_n_o(mem_rst_n_o)
  );
  rst_sync #(
      .STAGE(5)
  ) u_aud_rst_sync (
      .clk_i  (s_aud_clk_buf),
      .rst_n_i(s_domain_reset_source_n),
      .rst_n_o(aud_rst_n_o)
  );

  clint_timebase #(
      .RefClkHz  (RefClkHz),
      .TimebaseHz(ClintTimebaseHz)
  ) u_clint_timebase (
      .ref_clk_i  (s_ref24_clk_buf),
      .ref_rst_n_i(s_aon_rst_n),
      .sys_clk_i  (s_lp_root_clk),
      .sys_rst_n_i(lp_rst_n_o),
      .tick_o     (timebase_tick_o)
  );

  assign aon_clk_o     = s_ref24_clk_buf;
  assign aon_rst_n_o   = s_aon_rst_n;
  assign lp_clk_o      = s_lp_root_clk;
  assign hp_clk_o      = s_hp_root_clk;
  assign hp_core_clk_o = s_hp_core_clk;
  assign pclk_o        = s_pclk;
  assign mem_clk_o     = s_mem_clk_div2;
  assign aud_clk_o     = s_aud_clk_buf;
  assign lp_clkdiv4_o  = s_lp_clk_div4;
  assign pll_fault_o   = s_pll_fault || (|s_clock_fault);

  logic [16:0] s_unused_clock_config;
  assign s_unused_clock_config = {
    2'd0,
    s_gate_mask,
    s_pclk_count,
    ^{s_pclk_div_done, s_pclk_first_trigger, s_pclk_second_trigger, s_pclk_cfg_src_ready,
      s_pll_apply},
    ^{s_clock_alive, s_clock_edge_delta}
  };

`ifndef SYNTHESIS
  initial begin
    if ((RefClkHz != 24_000_000) || ((RefClkHz % ClintTimebaseHz) != 0)) begin
      $fatal(1, "soc_clock_reset_subsystem: REF24/timebase contract is invalid");
    end
  end
`endif
endmodule
