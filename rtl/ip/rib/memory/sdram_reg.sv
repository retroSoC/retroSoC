// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RIB_SDRAM_DEF_SV
`define RIB_SDRAM_DEF_SV

// verilog_format: off
`define RIB_SDRAM_CLKDIV 8'h00
`define RIB_SDRAM_CFG    8'h04
// verilog_format: on

`endif

module sdram_reg (
    // verilog_format: off
    input  logic       clk_i,
    input  logic       rst_n_i,
    rib_if.slave       rib,
    output logic [1:0] clkdiv_o
    // verilog_format: on
);
  // rib
  logic s_rib_wr_hdshk, s_rib_rd_hdshk;
  logic s_rib_ready_d, s_rib_ready_q;
  logic s_rib_rdata_en;
  logic [31:0] s_rib_rdata_d, s_rib_rdata_q;
  // register
  logic s_sdram_clkdiv_en;
  logic [1:0] s_sdram_clkdiv_d, s_sdram_clkdiv_q;

  // rib
  assign s_rib_wr_hdshk    = rib.valid && (~s_rib_ready_q) && (|rib.wstrb);
  assign s_rib_rd_hdshk    = rib.valid && (~s_rib_ready_q) && (~(|rib.wstrb));
  assign rib.ready         = s_rib_ready_q;
  assign rib.rdata         = s_rib_rdata_q;
  // reg
  assign clkdiv_o          = s_sdram_clkdiv_q;


  assign s_sdram_clkdiv_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_SDRAM_CLKDIV;
  assign s_sdram_clkdiv_d  = rib.wdata[1:0];
  dffer #(2) u_sdram_clkdiv_dffer (
      clk_i,
      rst_n_i,
      s_sdram_clkdiv_en,
      s_sdram_clkdiv_d,
      s_sdram_clkdiv_q
  );


  // rib resp
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
      `RIB_SDRAM_CLKDIV: s_rib_rdata_d = {30'd0, s_sdram_clkdiv_q};
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
