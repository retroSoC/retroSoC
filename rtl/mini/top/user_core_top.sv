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

module user_core_top (
    // verilog_format: off
    input  logic                           clk_i,
    input  logic                           rst_n_i,
    input  logic [                   31:0] irq_i,
    input  logic [`USER_CORESEL_WIDTH-1:0] sel_i,
    nmi_if.master                          nmi
    // verilog_format: on
);

  nmi_if u_user_1_nmi_if ();
  nmi_if u_user_2_nmi_if ();
  logic [31:0] s_user_1_irq, s_user_2_irq;

  always_comb begin
    nmi.valid             = '0;
    nmi.addr              = '0;
    nmi.wdata             = '0;
    nmi.wstrb             = '0;
    u_user_1_nmi_if.rdata = '0;
    u_user_1_nmi_if.ready = '0;
    s_user_1_irq          = '0;
    u_user_2_nmi_if.rdata = '0;
    u_user_2_nmi_if.ready = '0;
    s_user_2_irq          = '0;
    unique case (sel_i)
      5'd1: begin
        nmi.valid             = u_user_1_nmi_if.valid;
        nmi.addr              = u_user_1_nmi_if.addr;
        nmi.wdata             = u_user_1_nmi_if.wdata;
        nmi.wstrb             = u_user_1_nmi_if.wstrb;
        u_user_1_nmi_if.rdata = nmi.rdata;
        u_user_1_nmi_if.ready = nmi.ready;
        s_user_1_irq          = irq_i;
      end
      5'd2: begin
        nmi.valid             = u_user_2_nmi_if.valid;
        nmi.addr              = u_user_2_nmi_if.addr;
        nmi.wdata             = u_user_2_nmi_if.wdata;
        nmi.wstrb             = u_user_2_nmi_if.wstrb;
        u_user_2_nmi_if.rdata = nmi.rdata;
        u_user_2_nmi_if.ready = nmi.ready;
        s_user_2_irq          = irq_i;
      end
      default: begin
        nmi.valid             = '0;
        nmi.addr              = '0;
        nmi.wdata             = '0;
        nmi.wstrb             = '0;
        u_user_1_nmi_if.rdata = '0;
        u_user_1_nmi_if.ready = '0;
        s_user_1_irq          = '0;
        u_user_2_nmi_if.rdata = '0;
        u_user_2_nmi_if.ready = '0;
        s_user_2_irq          = '0;
      end
    endcase
  end


  user_core_design #(1) u_user_1_core_design (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .irq_i  (s_user_1_irq),
      .nmi    (u_user_1_nmi_if)
  );

  user_core_design #(2) u_user_2_core_design (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .irq_i  (s_user_2_irq),
      .nmi    (u_user_2_nmi_if)
  );

endmodule
