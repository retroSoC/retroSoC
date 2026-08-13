// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module clint_timebase #(
    parameter int REF_CLK_HZ  = 72_000_000,
    parameter int TIMEBASE_HZ = 1_000_000,
    parameter int CDC_STAGE   = 2
) (
    // verilog_format: off
    input  logic ref_clk_i,
    input  logic ref_rst_n_i,
    input  logic sys_clk_i,
    input  logic sys_rst_n_i,
    output logic tick_o
    // verilog_format: on
);

  localparam int DIVISOR = REF_CLK_HZ / TIMEBASE_HZ;
  localparam int DIV_WIDTH = DIVISOR > 1 ? $clog2(DIVISOR) : 1;

  logic [DIV_WIDTH-1:0] s_div_count;
  logic                 s_div_terminal;
  logic s_tick_toggle_d, s_tick_toggle_q;
  logic s_tick_toggle_sync;
  logic s_tick_re, s_tick_fe;

  initial begin
    if ((REF_CLK_HZ <= 0) || (TIMEBASE_HZ <= 0) || (REF_CLK_HZ < TIMEBASE_HZ) ||
        ((REF_CLK_HZ % TIMEBASE_HZ) != 0)) begin
      $fatal(1, "clint_timebase: REF_CLK_HZ must be a positive multiple of TIMEBASE_HZ");
    end
  end

  assign s_div_terminal = s_div_count == DIV_WIDTH'(DIVISOR - 1);

  // The divider clears before its natural carry; the Common carry output is intentionally unused.
  /* verilator lint_off PINCONNECTEMPTY */
  rs_counter #(
      .DATA_WIDTH(DIV_WIDTH)
  ) u_div_counter (
      .clk_i  (ref_clk_i),
      .rst_n_i(ref_rst_n_i),
      .clr_i  (s_div_terminal),
      .en_i   (1'b1),
      .load_i (1'b0),
      .down_i (1'b0),
      .dat_i  ('0),
      .dat_o  (s_div_count),
      .ovf_o  ()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  assign s_tick_toggle_d = s_div_terminal ? ~s_tick_toggle_q : s_tick_toggle_q;
  dffr #(
      .DATA_WIDTH(1)
  ) u_tick_toggle_dffr (
      .clk_i  (ref_clk_i),
      .rst_n_i(ref_rst_n_i),
      .dat_i  (s_tick_toggle_d),
      .dat_o  (s_tick_toggle_q)
  );

  edge_det #(
      .STAGE(CDC_STAGE)
  ) u_tick_edge_det (
      .clk_i  (sys_clk_i),
      .rst_n_i(sys_rst_n_i),
      .dat_i  (s_tick_toggle_q),
      .dat_o  (s_tick_toggle_sync),
      .re_o   (s_tick_re),
      .fe_o   (s_tick_fe)
  );

  assign tick_o = (s_tick_re && !s_tick_toggle_sync) || (s_tick_fe && s_tick_toggle_sync);

endmodule
