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

module user_core_wrapper (
    // verilog_format: off
    input  logic                           clk_i,
    input  logic                           rst_n_i,
    input  logic [                   31:0] irq_i,
    input  logic [`USER_CORESEL_WIDTH-1:0] sel_i,
    nmi_if.master                          nmi
    // verilog_format: on
);

  nmi_if u_mgmt_nmi_if ();
  nmi_if u_user_nmi_if ();
  logic [31:0] s_mgmt_irq, s_user_irq;

  assign nmi.valid           = ~(|sel_i) ? u_mgmt_nmi_if.valid : u_user_nmi_if.valid;
  assign nmi.addr            = ~(|sel_i) ? u_mgmt_nmi_if.addr : u_user_nmi_if.addr;
  assign nmi.wdata           = ~(|sel_i) ? u_mgmt_nmi_if.wdata : u_user_nmi_if.wdata;
  assign nmi.wstrb           = ~(|sel_i) ? u_mgmt_nmi_if.wstrb : u_user_nmi_if.wstrb;

  assign u_mgmt_nmi_if.rdata = ~(|sel_i) ? nmi.rdata : '0;
  assign u_mgmt_nmi_if.ready = ~(|sel_i) ? nmi.ready : '0;
  assign s_mgmt_irq          = ~(|sel_i) ? irq_i : '0;

  assign u_user_nmi_if.rdata = (|sel_i) ? nmi.rdata : '0;
  assign u_user_nmi_if.ready = (|sel_i) ? nmi.ready : '0;
  assign s_user_irq          = (|sel_i) ? irq_i : '0;


  mgmt_core_wrapper u_mgmt_core_wrapper (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .irq_i  (s_mgmt_irq),
      .nmi    (u_mgmt_nmi_if)
  );

  user_core_top u_user_core_top (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .irq_i  (s_user_irq),
      .sel_i  (sel_i),
      .nmi    (u_user_nmi_if)
  );

endmodule
