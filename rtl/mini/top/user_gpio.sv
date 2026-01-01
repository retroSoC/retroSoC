// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.


`include "mdd_config.svh"

interface user_gpio_if ();
  logic [`USER_GPIO_NUM-1:0] gpio_out;
  logic [`USER_GPIO_NUM-1:0] gpio_in;
  logic [`USER_GPIO_NUM-1:0] gpio_oe;

  modport dut(output gpio_out, input gpio_in, output gpio_oe);
endinterface
