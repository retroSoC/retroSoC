// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "gpio_define.svh"

interface user_gpio_if #(
    parameter int DataWidth = `APB4_GPIO_NUM
) ();
  logic [DataWidth-1:0] do_o;
  logic [DataWidth-1:0] oe_o;
  logic [DataWidth-1:0] di_i;

  modport user_ip(output do_o, output oe_o, input di_i);
  modport padctrl(input do_o, input oe_o, output di_i);
endinterface
