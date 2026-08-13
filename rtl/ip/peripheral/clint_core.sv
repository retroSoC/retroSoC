// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module clint_core #(
    parameter int HartNum = 1
) (
    // verilog_format: off
    input  logic                clk_i,
    input  logic                rst_n_i,
    input  logic                tick_i,
    input  logic                mtime_load_i,
    input  logic [63:0]         mtime_load_value_i,
    input  logic [63:0]         mtimecmp_i [0:HartNum-1],
    output logic [63:0]         mtime_o,
    output logic [HartNum-1:0] timer_irq_o
    // verilog_format: on
);

  logic [HartNum-1:0] s_timer_irq_d, s_timer_irq_q;

  initial begin
    if ((HartNum < 1) || (HartNum > 4095)) begin
      $fatal(1, "clint_core: HartNum must be between 1 and 4095");
    end
  end

  // MTIME wraps modulo 2^64, so the Common carry output is intentionally unused.
  /* verilator lint_off PINCONNECTEMPTY */
  rs_counter #(
      .DATA_WIDTH(64)
  ) u_mtime_counter (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .clr_i  (1'b0),
      .en_i   (tick_i),
      .load_i (mtime_load_i),
      .down_i (1'b0),
      .dat_i  (mtime_load_value_i),
      .dat_o  (mtime_o),
      .ovf_o  ()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always_comb begin
    for (int hart = 0; hart < HartNum; hart++) begin
      s_timer_irq_d[hart] = mtime_o >= mtimecmp_i[hart];
    end
  end
  dffr #(
      .DATA_WIDTH(HartNum)
  ) u_timer_irq_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timer_irq_d),
      .dat_o  (s_timer_irq_q)
  );

  assign timer_irq_o = s_timer_irq_q;

endmodule
