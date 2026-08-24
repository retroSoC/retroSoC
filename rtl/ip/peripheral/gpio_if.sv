// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "gpio_define.svh"

interface gpio_if #(
    parameter int DataWidth = `APB4_GPIO_NUM
) ();
  logic [DataWidth-1:0] oe_o;
  logic [DataWidth-1:0] cs_o;
  logic [DataWidth-1:0] pu_o;
  logic [DataWidth-1:0] pd_o;
  logic [DataWidth-1:0] do_o;
  logic [DataWidth-1:0] di_i;
  logic [DataWidth-1:0] alt0_do_i;
  logic [DataWidth-1:0] alt0_oe_i;
  logic [DataWidth-1:0] alt1_do_i;
  logic [DataWidth-1:0] alt1_oe_i;
  logic                 irq_o;

  modport dut(
      output oe_o,
      output cs_o,
      output pu_o,
      output pd_o,
      output do_o,
      input di_i,
      input alt0_do_i,
      input alt0_oe_i,
      input alt1_do_i,
      input alt1_oe_i,
      output irq_o
  );

  modport pad(input oe_o, input cs_o, input pu_o, input pd_o, input do_o, output di_i);
  modport soc_pad(output oe_o, output cs_o, output pu_o, output pd_o, output do_o, input di_i);
endinterface
