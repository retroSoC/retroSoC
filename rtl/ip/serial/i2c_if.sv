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

interface i2c_if ();
  logic scl_i;
  logic scl_o;
  logic scl_oe_o;
  logic sda_i;
  logic sda_o;
  logic sda_oe_o;
  logic irq_o;

  modport dut(
      input scl_i,
      output scl_o,
      output scl_oe_o,
      input sda_i,
      output sda_o,
      output sda_oe_o,
      output irq_o
  );

  modport tb(
      output scl_i,
      input scl_o,
      input scl_oe_o,
      output sda_i,
      input sda_o,
      input sda_oe_o,
      input irq_o
  );
endinterface
