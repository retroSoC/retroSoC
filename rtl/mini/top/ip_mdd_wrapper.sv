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

module ip_mdd_wrapper (
    // verilog_format: off
    input  logic                         clk_i,
    input  logic                         rst_n_i,
    input  logic [`USER_IPSEL_WIDTH-1:0] sel_i,
    user_gpio_if.dut                     gpio,
    apb4_if.slave                        apb
    // verilog_format: on
);

  // verilog_format: off
  apb4_if       u_demo_apb4_if(clk_i, rst_n_i);
  apb4_if       u_user_apb4_if(clk_i, rst_n_i);
  apb4_archinfo u_apb4_archinfo_ip(u_demo_apb4_if);
  // verilog_format: on

  assign apb.pready             = |sel_i ? u_demo_apb4_if.pready : u_user_apb4_if.pready;
  assign apb.prdata             = |sel_i ? u_demo_apb4_if.prdata : u_user_apb4_if.prdata;

  assign u_demo_apb4_if.paddr   = ~(|sel_i) ? apb.paddr : '0;
  assign u_demo_apb4_if.pprot   = ~(|sel_i) ? apb.pprot : '0;
  assign u_demo_apb4_if.psel    = ~(|sel_i) ? apb.psel : '0;
  assign u_demo_apb4_if.penable = ~(|sel_i) ? apb.penable : '0;
  assign u_demo_apb4_if.pwrite  = ~(|sel_i) ? apb.pwrite : '0;
  assign u_demo_apb4_if.pwdata  = ~(|sel_i) ? apb.pwdata : '0;
  assign u_demo_apb4_if.pstrb   = ~(|sel_i) ? apb.pstrb : '0;

  assign u_user_apb4_if.paddr   = |sel_i ? apb.paddr : '0;
  assign u_user_apb4_if.pprot   = |sel_i ? apb.pprot : '0;
  assign u_user_apb4_if.psel    = |sel_i ? apb.psel : '0;
  assign u_user_apb4_if.penable = |sel_i ? apb.penable : '0;
  assign u_user_apb4_if.pwrite  = |sel_i ? apb.pwrite : '0;
  assign u_user_apb4_if.pwdata  = |sel_i ? apb.pwdata : '0;
  assign u_user_apb4_if.pstrb   = |sel_i ? apb.pstrb : '0;

  user_ip_wrapper u_user_ip_wrapper (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .sel_i  (sel_i),
      .gpio   (gpio),
      .apb    (u_user_apb4_if)
  );


endmodule
