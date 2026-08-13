// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

interface uart_if ();
  logic rx_i;
  logic cts_n_i;
  logic tx_o;
  logic rts_n_o;
  logic irq_o;

  modport dut(input rx_i, input cts_n_i, output tx_o, output rts_n_o, output irq_o);

  modport tb(output rx_i, output cts_n_i, input tx_o, input rts_n_o, input irq_o);
endinterface
