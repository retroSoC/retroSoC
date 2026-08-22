// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// See LICENSE for the complete license text.

interface spi_if ();
  logic sck_o;
  logic nss_o;
  logic mosi_o;
  logic miso_i;
  logic irq_o;

  modport dut(output sck_o, output nss_o, output mosi_o, input miso_i, output irq_o);

  // verilog_format: off -- preserve the signal-per-line testbench modport layout
  modport tb(
      input sck_o,
      input nss_o,
      input mosi_o,
      output miso_i,
      input irq_o
  );
  // verilog_format: on
endinterface
