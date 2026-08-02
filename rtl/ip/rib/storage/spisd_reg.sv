// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RIB_SPISD_DEF_SV
`define RIB_SPISD_DEF_SV

// verilog_format: off
`define RIB_SPISD_MODE   8'h00
`define RIB_SPISD_CLKDIV 8'h04
`define RIB_SPISD_ADDR   8'h08
`define RIB_SPISD_TXDATA 8'h0C
`define RIB_SPISD_RXDATA 8'h10
`define RIB_SPISD_STATUS 8'h14
`define RIB_SPISD_SYNC   8'h18
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
    rib_if.slave       rib,
    rib_if.master      byp_rib
    // verilog_format: on
);
  // rib
  logic s_rib_wr_hdshk, s_rib_rd_hdshk;
  logic s_rib_ready_d, s_rib_ready_q;
  logic s_rib_rdata_en;
  logic [31:0] s_rib_rdata_d, s_rib_rdata_q;
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

  // rib
  assign s_rib_wr_hdshk  = rib.valid && (~s_rib_ready_q) && (|rib.wstrb);
  assign s_rib_rd_hdshk  = rib.valid && (~s_rib_ready_q) && (~(|rib.wstrb));
  assign s_wr_byp        = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_SPISD_TXDATA;
  assign s_rd_byp        = s_rib_rd_hdshk && rib.addr[7:0] == `RIB_SPISD_RXDATA;
  assign rib.ready       = (s_wr_byp || s_rd_byp) ? byp_rib.ready : s_rib_ready_q;
  assign rib.rdata       = (s_wr_byp || s_rd_byp) ? byp_rib.rdata : s_rib_rdata_q;
  // common
  assign mode_o          = s_spisd_mode_q;
  assign clkdiv_o        = s_spisd_clkdiv_q;
  // byp
  assign byp_rib.valid   = s_wr_byp || s_rd_byp;
  assign byp_rib.addr    = s_spisd_addr_q;
  assign byp_rib.wdata   = rib.wdata;
  assign byp_rib.wstrb   = rib.wstrb;


  assign s_spisd_mode_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_SPISD_MODE;
  assign s_spisd_mode_d  = rib.wdata[0];
  dffer #(1) u_spisd_mode_dffer (
      clk_i,
      rst_n_i,
      s_spisd_mode_en,
      s_spisd_mode_d,
      s_spisd_mode_q
  );

  assign s_spisd_clkdiv_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_SPISD_CLKDIV;
  assign s_spisd_clkdiv_d  = rib.wdata[1:0];
  dffer #(2) u_spisd_clkdiv_dffer (
      clk_i,
      rst_n_i,
      s_spisd_clkdiv_en,
      s_spisd_clkdiv_d,
      s_spisd_clkdiv_q
  );

  assign s_spisd_addr_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_SPISD_ADDR;
  always_comb begin
    s_spisd_addr_d = s_spisd_addr_q;
    if (rib.wstrb[0]) s_spisd_addr_d[7:0] = rib.wdata[7:0];
    if (rib.wstrb[1]) s_spisd_addr_d[15:8] = rib.wdata[15:8];
    if (rib.wstrb[2]) s_spisd_addr_d[23:16] = rib.wdata[23:16];
    if (rib.wstrb[3]) s_spisd_addr_d[31:24] = rib.wdata[31:24];
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
    end else if (s_spisd_status_q[1] && s_rib_rd_hdshk && rib.addr[7:0] == `RIB_SPISD_STATUS) begin
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
  assign wr_sync_o     = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_SPISD_SYNC;


  assign s_rib_ready_d = rib.valid && (~s_rib_ready_q);
  dffr #(1) u_rib_ready_dffr (
      clk_i,
      rst_n_i,
      s_rib_ready_d,
      s_rib_ready_q
  );

  assign s_rib_rdata_en = s_rib_rd_hdshk;
  always_comb begin
    s_rib_rdata_d = s_rib_rdata_q;
    unique case (rib.addr[7:0])
      `RIB_SPISD_MODE:   s_rib_rdata_d = {31'd0, s_spisd_mode_q};
      `RIB_SPISD_CLKDIV: s_rib_rdata_d = {30'd0, s_spisd_clkdiv_q};
      `RIB_SPISD_ADDR:   s_rib_rdata_d = s_spisd_addr_q;
      `RIB_SPISD_STATUS: s_rib_rdata_d = {30'd0, s_spisd_status_q};
      default:           s_rib_rdata_d = s_rib_rdata_q;
    endcase
  end
  dffer #(32) u_rib_rdata_dffer (
      clk_i,
      rst_n_i,
      s_rib_rdata_en,
      s_rib_rdata_d,
      s_rib_rdata_q
  );

endmodule
