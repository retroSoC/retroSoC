// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef APB4_SPISD_DEF_SV
`define APB4_SPISD_DEF_SV

// verilog_format: off -- preserve reviewed column alignment
`define APB4_SPISD_MODE   8'h00
`define APB4_SPISD_CLKDIV 8'h04
`define APB4_SPISD_ADDR   8'h08
`define APB4_SPISD_TXDATA 8'h0C
`define APB4_SPISD_RXDATA 8'h10
`define APB4_SPISD_STATUS 8'h14
`define APB4_SPISD_SYNC   8'h18
// verilog_format: on

`endif

module spisd_reg (
    // verilog_format: off -- preserve reviewed column alignment
    input logic         clk_i,
    input logic         rst_n_i,
    input logic         init_done_i,
    output logic        wr_sync_o,
    input logic         wr_sync_done_i,
    output logic        mode_o,
    output logic [1:0]  clkdiv_o,
    apb4_if.slave       apb4,
    output logic        byp_valid_o,
    input  logic        byp_ready_i,
    output logic [31:0] byp_addr_o,
    output logic [31:0] byp_wdata_o,
    output logic [ 3:0] byp_wstrb_o,
    input  logic [31:0] byp_rdata_i,
    input  logic        byp_resp_err_i
    // verilog_format: on
);
  // apb4
  logic s_apb4_wr_hdshk, s_apb4_rd_hdshk;
  logic s_apb4_ready_d, s_apb4_ready_q;
  logic s_apb4_rdata_en;
  logic [31:0] s_apb4_rdata_d, s_apb4_rdata_q;
  // reg
  logic s_spisd_mode_en;
  logic s_spisd_mode_d, s_spisd_mode_q;
  logic s_spisd_clkdiv_en;
  logic [1:0] s_spisd_clkdiv_d, s_spisd_clkdiv_q;
  logic s_spisd_addr_en;
  logic [31:0] s_spisd_addr_d, s_spisd_addr_q;
  logic [1:0] s_spisd_stat_d, s_spisd_stat_q;
  // common
  logic s_wr_byp, s_rd_byp;

  // apb4
  assign s_apb4_wr_hdshk = apb4.psel && apb4.penable && (~s_apb4_ready_q) && apb4.pwrite;
  assign s_apb4_rd_hdshk = apb4.psel && apb4.penable && (~s_apb4_ready_q) && (~apb4.pwrite);
  assign s_wr_byp        = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_SPISD_TXDATA;
  assign s_rd_byp        = s_apb4_rd_hdshk && apb4.paddr[7:0] == `APB4_SPISD_RXDATA;
  assign apb4.pready     = (s_wr_byp || s_rd_byp) ? byp_ready_i : s_apb4_ready_q;
  assign apb4.prdata     = (s_wr_byp || s_rd_byp) ? byp_rdata_i : s_apb4_rdata_q;
  assign apb4.pslverr    = (s_wr_byp || s_rd_byp) ? byp_resp_err_i : 1'b0;
  // common
  assign mode_o          = s_spisd_mode_q;
  assign clkdiv_o        = s_spisd_clkdiv_q;
  // byp
  assign byp_valid_o     = s_wr_byp || s_rd_byp;
  assign byp_addr_o      = s_spisd_addr_q;
  assign byp_wdata_o     = apb4.pwdata;
  assign byp_wstrb_o     = apb4.pstrb;


  assign s_spisd_mode_en = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_SPISD_MODE;
  assign s_spisd_mode_d  = apb4.pwdata[0];
  dffer #(
      .DATA_WIDTH(1)
  ) u_spisd_mode_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_spisd_mode_en),
      .dat_i  (s_spisd_mode_d),
      .dat_o  (s_spisd_mode_q)
  );

  assign s_spisd_clkdiv_en = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_SPISD_CLKDIV;
  assign s_spisd_clkdiv_d  = apb4.pwdata[1:0];
  dffer #(
      .DATA_WIDTH(2)
  ) u_spisd_clkdiv_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_spisd_clkdiv_en),
      .dat_i  (s_spisd_clkdiv_d),
      .dat_o  (s_spisd_clkdiv_q)
  );

  assign s_spisd_addr_en = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_SPISD_ADDR;
  always_comb begin
    s_spisd_addr_d = s_spisd_addr_q;
    if (apb4.pstrb[0]) s_spisd_addr_d[7:0] = apb4.pwdata[7:0];
    if (apb4.pstrb[1]) s_spisd_addr_d[15:8] = apb4.pwdata[15:8];
    if (apb4.pstrb[2]) s_spisd_addr_d[23:16] = apb4.pwdata[23:16];
    if (apb4.pstrb[3]) s_spisd_addr_d[31:24] = apb4.pwdata[31:24];
  end
  dffer #(
      .DATA_WIDTH(32)
  ) u_spisd_addr_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_spisd_addr_en),
      .dat_i  (s_spisd_addr_d),
      .dat_o  (s_spisd_addr_q)
  );

  // 0: init done
  // 1: wr sync done
  always_comb begin
    s_spisd_stat_d    = s_spisd_stat_q;
    s_spisd_stat_d[0] = init_done_i;
    if (wr_sync_done_i && ~s_spisd_stat_q[1]) begin
      s_spisd_stat_d[1] = 1'b1;
    end else if (s_spisd_stat_q[1] && s_apb4_rd_hdshk &&
                 (apb4.paddr[7:0] == `APB4_SPISD_STATUS)) begin
      s_spisd_stat_d[1] = 1'b0;
    end
  end
  dffr #(
      .DATA_WIDTH(2)
  ) u_spisd_status_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_spisd_stat_d),
      .dat_o  (s_spisd_stat_q)
  );

  // software wr sync
  assign wr_sync_o      = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_SPISD_SYNC;


  assign s_apb4_ready_d = apb4.psel && apb4.penable && (~s_apb4_ready_q);
  dffr #(
      .DATA_WIDTH(1)
  ) u_apb4_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_ready_d),
      .dat_o  (s_apb4_ready_q)
  );

  assign s_apb4_rdata_en = s_apb4_rd_hdshk;
  always_comb begin
    s_apb4_rdata_d = s_apb4_rdata_q;
    unique case (apb4.paddr[7:0])
      `APB4_SPISD_MODE:   s_apb4_rdata_d = {31'd0, s_spisd_mode_q};
      `APB4_SPISD_CLKDIV: s_apb4_rdata_d = {30'd0, s_spisd_clkdiv_q};
      `APB4_SPISD_ADDR:   s_apb4_rdata_d = s_spisd_addr_q;
      `APB4_SPISD_STATUS: s_apb4_rdata_d = {30'd0, s_spisd_stat_q};
      default:            s_apb4_rdata_d = s_apb4_rdata_q;
    endcase
  end
  dffer #(
      .DATA_WIDTH(32)
  ) u_apb4_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_apb4_rdata_en),
      .dat_i  (s_apb4_rdata_d),
      .dat_o  (s_apb4_rdata_q)
  );

endmodule
