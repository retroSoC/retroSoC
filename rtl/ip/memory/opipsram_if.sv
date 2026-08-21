// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

interface opipsram_if ();
  logic       ck_o;
  logic       cs_n_o;
  logic [7:0] dq_oe_o;
  logic [7:0] dq_i;
  logic [7:0] dq_o;
  logic       rwds_oe_o;
  logic       rwds_i;
  logic       rwds_o;
  logic       irq_o;

  modport dut(
      output ck_o,
      output cs_n_o,
      output dq_oe_o,
      input dq_i,
      output dq_o,
      output rwds_oe_o,
      input rwds_i,
      output rwds_o,
      output irq_o
  );
endinterface
