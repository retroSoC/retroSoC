// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

interface clint_if #(
    parameter int HART_NUM = 1
) ();
  logic [HART_NUM-1:0] timer_irq_o;
  logic [HART_NUM-1:0] software_irq_o;

  modport dut(output timer_irq_o, output software_irq_o);
endinterface
