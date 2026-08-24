// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
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
