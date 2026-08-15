// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module ribp_clint #(
    parameter int HartNum = 1
) (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic  clk_i,
    input  logic  rst_n_i,
    input  logic  timebase_tick_i,
    ribp_if.slave ribp,
    clint_if.dut  clint
    // verilog_format: on
);

  logic               s_mtime_load;
  logic [       63:0] s_mtime_load_value;
  logic [       63:0] s_mtime;
  logic [HartNum-1:0] s_msip;
  logic [       63:0] s_mtimecmp         [0:HartNum-1];
  logic [HartNum-1:0] s_timer_irq;

  clint_reg #(
      .HartNum(HartNum)
  ) u_clint_reg (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .ribp              (ribp),
      .mtime_i           (s_mtime),
      .mtime_load_o      (s_mtime_load),
      .mtime_load_value_o(s_mtime_load_value),
      .msip_o            (s_msip),
      .mtimecmp_o        (s_mtimecmp)
  );

  clint_core #(
      .HartNum(HartNum)
  ) u_clint_core (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .tick_i            (timebase_tick_i),
      .mtime_load_i      (s_mtime_load),
      .mtime_load_value_i(s_mtime_load_value),
      .mtimecmp_i        (s_mtimecmp),
      .mtime_o           (s_mtime),
      .timer_irq_o       (s_timer_irq)
  );

  assign clint.software_irq_o = s_msip;
  assign clint.timer_irq_o    = s_timer_irq;

endmodule
