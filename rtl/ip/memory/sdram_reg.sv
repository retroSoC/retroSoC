// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RIBP_SDRAM_DEF_SV
`define RIBP_SDRAM_DEF_SV

// verilog_format: off
`define RIBP_SDRAM_CLKDIV 8'h00
`define RIBP_SDRAM_CFG    8'h04
// verilog_format: on

`endif

module sdram_reg (
    // verilog_format: off
    input  logic       clk_i,
    input  logic       rst_n_i,
    ribp_if.slave       ribp,
    output logic [1:0] clkdiv_o
    // verilog_format: on
);
  // ribp
  logic s_ribp_wr_hdshk, s_ribp_rd_hdshk;
  logic s_ribp_ready_d, s_ribp_ready_q;
  logic s_ribp_rdata_en;
  logic [31:0] s_ribp_rdata_d, s_ribp_rdata_q;
  // register
  logic s_sdram_clkdiv_en;
  logic [1:0] s_sdram_clkdiv_d, s_sdram_clkdiv_q;

  // ribp
  assign s_ribp_wr_hdshk   = ribp.valid && (~s_ribp_ready_q) && (|ribp.wstrb);
  assign s_ribp_rd_hdshk   = ribp.valid && (~s_ribp_ready_q) && (~(|ribp.wstrb));
  assign ribp.ready        = s_ribp_ready_q;
  assign ribp.resp_err     = 1'b0;
  assign ribp.rdata        = s_ribp_rdata_q;
  // reg
  assign clkdiv_o          = s_sdram_clkdiv_q;


  assign s_sdram_clkdiv_en = s_ribp_wr_hdshk && ribp.addr[7:0] == `RIBP_SDRAM_CLKDIV;
  assign s_sdram_clkdiv_d  = ribp.wdata[1:0];
  dffer #(
      .DATA_WIDTH(2)
  ) u_sdram_clkdiv_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_sdram_clkdiv_en),
      .dat_i  (s_sdram_clkdiv_d),
      .dat_o  (s_sdram_clkdiv_q)
  );


  // ribp resp
  assign s_ribp_ready_d = ribp.valid && (~s_ribp_ready_q);
  dffr #(
      .DATA_WIDTH(1)
  ) u_ribp_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ribp_ready_d),
      .dat_o  (s_ribp_ready_q)
  );


  assign s_ribp_rdata_en = s_ribp_rd_hdshk;
  always_comb begin
    s_ribp_rdata_d = s_ribp_rdata_q;
    unique case (ribp.addr[7:0])
      `RIBP_SDRAM_CLKDIV: s_ribp_rdata_d = {30'd0, s_sdram_clkdiv_q};
      default:            s_ribp_rdata_d = s_ribp_rdata_q;
    endcase
  end
  dffer #(
      .DATA_WIDTH(32)
  ) u_ribp_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_ribp_rdata_en),
      .dat_i  (s_ribp_rdata_d),
      .dat_o  (s_ribp_rdata_q)
  );

endmodule
