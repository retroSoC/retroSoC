// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef NATV_SPISD_DEF_SV
`define NATV_SPISD_DEF_SV

// verilog_format: off
`define NATV_SPISD_MODE   8'h00
`define NATV_SPISD_CLKDIV 8'h04
`define NATV_SPISD_ADDR   8'h08
`define NATV_SPISD_TXDATA 8'h0C
`define NATV_SPISD_RXDATA 8'h10
`define NATV_SPISD_STATUS 8'h14
`define NATV_SPISD_SYNC   8'h18
// verilog_format: on

`endif

module spisd_reg (
    // verilog_format: off
    input logic        clk_i,
    input logic        rst_n_i,
    input logic        init_done_i,
    output logic       mode_o,
    output logic [1:0] clkdiv_o,
    nmi_if.slave       nmi,
    nmi_if.master      byp_nmi
    // verilog_format: on
);
  // nmi
  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;
  // reg
  logic s_spisd_mode_en;
  logic s_spisd_mode_d, s_spisd_mode_q;
  logic s_spisd_clkdiv_en;
  logic [1:0] s_spisd_clkdiv_d, s_spisd_clkdiv_q;
  logic s_spisd_addr_en;
  logic [31:0] s_spisd_addr_d, s_spisd_addr_q;
  logic s_spisd_status_d, s_spisd_status_q;
  // common
  logic s_wr_byp, s_rd_byp;

  // nmi
  assign s_nmi_wr_hdshk  = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk  = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign s_wr_byp        = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_SPISD_TXDATA;
  assign s_rd_byp        = s_nmi_rd_hdshk && nmi.addr[7:0] == `NATV_SPISD_RXDATA;
  assign nmi.ready       = (s_wr_byp || s_rd_byp) ? byp_nmi.ready : s_nmi_ready_q;
  assign nmi.rdata       = (s_wr_byp || s_rd_byp) ? byp_nmi.rdata : s_nmi_rdata_q;
  // common
  assign mode_o          = s_spisd_mode_q;
  assign clkdiv_o        = s_spisd_clkdiv_q;
  // byp
  assign byp_nmi.valid   = s_wr_byp || s_rd_byp;
  assign byp_nmi.addr    = s_spisd_addr_q;
  assign byp_nmi.wdata   = nmi.wdata;
  assign byp_nmi.wstrb   = nmi.wstrb;


  assign s_spisd_mode_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_SPISD_MODE;
  assign s_spisd_mode_d  = nmi.wdata[0];
  dffer #(1) u_spisd_mode_dffer (
      clk_i,
      rst_n_i,
      s_spisd_mode_en,
      s_spisd_mode_d,
      s_spisd_mode_q
  );

  assign s_spisd_clkdiv_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_SPISD_CLKDIV;
  assign s_spisd_clkdiv_d  = nmi.wdata[1:0];
  dffer #(2) u_spisd_clkdiv_dffer (
      clk_i,
      rst_n_i,
      s_spisd_clkdiv_en,
      s_spisd_clkdiv_d,
      s_spisd_clkdiv_q
  );

  assign s_spisd_addr_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_SPISD_ADDR;
  always_comb begin
    s_spisd_addr_d = s_spisd_addr_q;
    if (nmi.wstrb[0]) s_spisd_addr_d[7:0] = nmi.wdata[7:0];
    if (nmi.wstrb[1]) s_spisd_addr_d[15:8] = nmi.wdata[15:8];
    if (nmi.wstrb[2]) s_spisd_addr_d[23:16] = nmi.wdata[23:16];
    if (nmi.wstrb[3]) s_spisd_addr_d[31:24] = nmi.wdata[31:24];
  end
  dffer #(32) u_spisd_addr_dffer (
      clk_i,
      rst_n_i,
      s_spisd_addr_en,
      s_spisd_addr_d,
      s_spisd_addr_q
  );

  // [0] init done
  assign s_spisd_status_d = init_done_i;
  dffr #(1) u_spisd_status_dffr (
      clk_i,
      rst_n_i,
      s_spisd_status_d,
      s_spisd_status_q
  );

  assign s_nmi_ready_d = nmi.valid && (~s_nmi_ready_q);
  dffr #(1) u_nmi_ready_dffr (
      clk_i,
      rst_n_i,
      s_nmi_ready_d,
      s_nmi_ready_q
  );

  assign s_nmi_rdata_en = s_nmi_rd_hdshk;
  always_comb begin
    s_nmi_rdata_d = s_nmi_rdata_q;
    unique case (nmi.addr[7:0])
      `NATV_SPISD_MODE:   s_nmi_rdata_d = {31'd0, s_spisd_mode_q};
      `NATV_SPISD_CLKDIV: s_nmi_rdata_d = {30'd0, s_spisd_clkdiv_q};
      `NATV_SPISD_ADDR:   s_nmi_rdata_d = s_spisd_addr_q;
      `NATV_SPISD_STATUS: s_nmi_rdata_d = {31'd0, s_spisd_status_q};
      default:            s_nmi_rdata_d = s_nmi_rdata_q;
    endcase
  end
  dffer #(32) u_nmi_rdata_dffer (
      clk_i,
      rst_n_i,
      s_nmi_rdata_en,
      s_nmi_rdata_d,
      s_nmi_rdata_q
  );

endmodule
