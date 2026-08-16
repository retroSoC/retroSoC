// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef APB4_SDRAM_DEF_SV
`define APB4_SDRAM_DEF_SV

// verilog_format: off -- preserve reviewed column alignment
`define APB4_SDRAM_CLKDIV 8'h00
`define APB4_SDRAM_CFG    8'h04
// verilog_format: on

`endif

module sdram_reg (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic       clk_i,
    input  logic       rst_n_i,
    apb4_if.slave      apb4,
    output logic [1:0] clkdiv_o
    // verilog_format: on
);
  // apb4
  logic s_apb4_wr_hdshk, s_apb4_rd_hdshk;
  logic s_apb4_ready_d, s_apb4_ready_q;
  logic s_apb4_rdata_en;
  logic [31:0] s_apb4_rdata_d, s_apb4_rdata_q;
  // register
  logic s_sdram_clkdiv_en;
  logic [1:0] s_sdram_clkdiv_d, s_sdram_clkdiv_q;

  // apb4
  assign s_apb4_wr_hdshk   = apb4.psel && apb4.penable && (~s_apb4_ready_q) && apb4.pwrite;
  assign s_apb4_rd_hdshk   = apb4.psel && apb4.penable && (~s_apb4_ready_q) && (~apb4.pwrite);
  assign apb4.pready       = s_apb4_ready_q;
  assign apb4.pslverr      = 1'b0;
  assign apb4.prdata       = s_apb4_rdata_q;
  // reg
  assign clkdiv_o          = s_sdram_clkdiv_q;


  assign s_sdram_clkdiv_en = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_SDRAM_CLKDIV;
  assign s_sdram_clkdiv_d  = apb4.pwdata[1:0];
  dffer #(
      .DATA_WIDTH(2)
  ) u_sdram_clkdiv_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_sdram_clkdiv_en),
      .dat_i  (s_sdram_clkdiv_d),
      .dat_o  (s_sdram_clkdiv_q)
  );


  // apb4 resp
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
      `APB4_SDRAM_CLKDIV: s_apb4_rdata_d = {30'd0, s_sdram_clkdiv_q};
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
