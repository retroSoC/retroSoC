// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RIBP_SPISD_DEF_SV
`define RIBP_SPISD_DEF_SV

// verilog_format: off
`define RIBP_SPISD_MODE   8'h00
`define RIBP_SPISD_CLKDIV 8'h04
`define RIBP_SPISD_ADDR   8'h08
`define RIBP_SPISD_TXDATA 8'h0C
`define RIBP_SPISD_RXDATA 8'h10
`define RIBP_SPISD_STATUS 8'h14
`define RIBP_SPISD_SYNC   8'h18
// verilog_format: on

`endif

module spisd_reg (
    // verilog_format: off
    input logic        clk_i,
    input logic        rst_n_i,
    input logic        init_done_i,
    output logic       wr_sync_o,
    input logic        wr_sync_done_i,
    output logic       mode_o,
    output logic [1:0] clkdiv_o,
    ribp_if.slave       ribp,
    ribp_if.master      byp_rib
    // verilog_format: on
);
  // ribp
  logic s_ribp_wr_hdshk, s_ribp_rd_hdshk;
  logic s_ribp_ready_d, s_ribp_ready_q;
  logic s_ribp_rdata_en;
  logic [31:0] s_ribp_rdata_d, s_ribp_rdata_q;
  // reg
  logic s_spisd_mode_en;
  logic s_spisd_mode_d, s_spisd_mode_q;
  logic s_spisd_clkdiv_en;
  logic [1:0] s_spisd_clkdiv_d, s_spisd_clkdiv_q;
  logic s_spisd_addr_en;
  logic [31:0] s_spisd_addr_d, s_spisd_addr_q;
  logic [1:0] s_spisd_status_d, s_spisd_status_q;
  // common
  logic s_wr_byp, s_rd_byp;

  // ribp
  assign s_ribp_wr_hdshk = ribp.valid && (~s_ribp_ready_q) && (|ribp.wstrb);
  assign s_ribp_rd_hdshk = ribp.valid && (~s_ribp_ready_q) && (~(|ribp.wstrb));
  assign s_wr_byp        = s_ribp_wr_hdshk && ribp.addr[7:0] == `RIBP_SPISD_TXDATA;
  assign s_rd_byp        = s_ribp_rd_hdshk && ribp.addr[7:0] == `RIBP_SPISD_RXDATA;
  assign ribp.ready      = (s_wr_byp || s_rd_byp) ? byp_rib.ready : s_ribp_ready_q;
  assign ribp.rdata      = (s_wr_byp || s_rd_byp) ? byp_rib.rdata : s_ribp_rdata_q;
  // common
  assign mode_o          = s_spisd_mode_q;
  assign clkdiv_o        = s_spisd_clkdiv_q;
  // byp
  assign byp_rib.valid   = s_wr_byp || s_rd_byp;
  assign byp_rib.addr    = s_spisd_addr_q;
  assign byp_rib.wdata   = ribp.wdata;
  assign byp_rib.wstrb   = ribp.wstrb;


  assign s_spisd_mode_en = s_ribp_wr_hdshk && ribp.addr[7:0] == `RIBP_SPISD_MODE;
  assign s_spisd_mode_d  = ribp.wdata[0];
  dffer #(1) u_spisd_mode_dffer (
      clk_i,
      rst_n_i,
      s_spisd_mode_en,
      s_spisd_mode_d,
      s_spisd_mode_q
  );

  assign s_spisd_clkdiv_en = s_ribp_wr_hdshk && ribp.addr[7:0] == `RIBP_SPISD_CLKDIV;
  assign s_spisd_clkdiv_d  = ribp.wdata[1:0];
  dffer #(2) u_spisd_clkdiv_dffer (
      clk_i,
      rst_n_i,
      s_spisd_clkdiv_en,
      s_spisd_clkdiv_d,
      s_spisd_clkdiv_q
  );

  assign s_spisd_addr_en = s_ribp_wr_hdshk && ribp.addr[7:0] == `RIBP_SPISD_ADDR;
  always_comb begin
    s_spisd_addr_d = s_spisd_addr_q;
    if (ribp.wstrb[0]) s_spisd_addr_d[7:0] = ribp.wdata[7:0];
    if (ribp.wstrb[1]) s_spisd_addr_d[15:8] = ribp.wdata[15:8];
    if (ribp.wstrb[2]) s_spisd_addr_d[23:16] = ribp.wdata[23:16];
    if (ribp.wstrb[3]) s_spisd_addr_d[31:24] = ribp.wdata[31:24];
  end
  dffer #(32) u_spisd_addr_dffer (
      clk_i,
      rst_n_i,
      s_spisd_addr_en,
      s_spisd_addr_d,
      s_spisd_addr_q
  );

  // 0: init done
  // 1: wr sync done
  always_comb begin
    s_spisd_status_d    = s_spisd_status_q;
    s_spisd_status_d[0] = init_done_i;
    if (wr_sync_done_i && ~s_spisd_status_q[1]) begin
      s_spisd_status_d[1] = 1'b1;
    end else if (s_spisd_status_q[1] && s_ribp_rd_hdshk && ribp.addr[7:0] == `RIBP_SPISD_STATUS) begin
      s_spisd_status_d[1] = 1'b0;
    end
  end
  dffr #(2) u_spisd_status_dffr (
      clk_i,
      rst_n_i,
      s_spisd_status_d,
      s_spisd_status_q
  );

  // software wr sync
  assign wr_sync_o      = s_ribp_wr_hdshk && ribp.addr[7:0] == `RIBP_SPISD_SYNC;


  assign s_ribp_ready_d = ribp.valid && (~s_ribp_ready_q);
  dffr #(1) u_ribp_ready_dffr (
      clk_i,
      rst_n_i,
      s_ribp_ready_d,
      s_ribp_ready_q
  );

  assign s_ribp_rdata_en = s_ribp_rd_hdshk;
  always_comb begin
    s_ribp_rdata_d = s_ribp_rdata_q;
    unique case (ribp.addr[7:0])
      `RIBP_SPISD_MODE:   s_ribp_rdata_d = {31'd0, s_spisd_mode_q};
      `RIBP_SPISD_CLKDIV: s_ribp_rdata_d = {30'd0, s_spisd_clkdiv_q};
      `RIBP_SPISD_ADDR:   s_ribp_rdata_d = s_spisd_addr_q;
      `RIBP_SPISD_STATUS: s_ribp_rdata_d = {30'd0, s_spisd_status_q};
      default:            s_ribp_rdata_d = s_ribp_rdata_q;
    endcase
  end
  dffer #(32) u_ribp_rdata_dffer (
      clk_i,
      rst_n_i,
      s_ribp_rdata_en,
      s_ribp_rdata_d,
      s_ribp_rdata_q
  );

endmodule
