// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module apb4_apu (
    // verilog_format: off -- preserve the APB and lifecycle boundary columns
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [1:0]  owner_i,
    input  logic        owner_lock_i,
    input  logic        quiesce_i,
    input  logic        resource_reset_i,
    apb4_if.slave       apb4,
    output logic        idle_o,
    output logic        irq_o
    // verilog_format: on
);
  apu_reg u_apu_reg (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .owner_i         (owner_i),
      .owner_lock_i    (owner_lock_i),
      .quiesce_i       (quiesce_i),
      .resource_reset_i(resource_reset_i),
      .apb4            (apb4),
      .idle_o          (idle_o),
      .irq_o           (irq_o)
  );
endmodule
