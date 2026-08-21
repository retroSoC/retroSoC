// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`timescale 1ns / 1ps

interface sdio_if ();
  logic       sck_o;
  logic       cmd_oe_o;
  logic       cmd_di_i;
  logic       cmd_do_o;
  logic [3:0] dat_oe_o;
  logic [3:0] dat_di_i;
  logic [3:0] dat_do_o;
  logic       irq_o;

  modport dut(
      output sck_o,
      output cmd_oe_o,
      input cmd_di_i,
      output cmd_do_o,
      output dat_oe_o,
      input dat_di_i,
      output dat_do_o,
      output irq_o
  );

  modport core(
      output sck_o,
      output cmd_oe_o,
      input cmd_di_i,
      output cmd_do_o,
      output dat_oe_o,
      input dat_di_i,
      output dat_do_o
  );
endinterface
