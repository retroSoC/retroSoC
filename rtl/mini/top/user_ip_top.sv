// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.


`include "user_extensions.svh"

module user_ip_top (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic                         clk_i,
    input  logic                         rst_n_i,
    input  logic [`USER_IPSEL_WIDTH-1:0] sel_i,
    user_gpio_if.user_ip                 gpio,
    apb4_if.slave                        apb
    // verilog_format: on
);

  // Generated bindings preserve scalar user-IP interfaces and isolation.
  `include "user_ip_bindings.svh"

endmodule
