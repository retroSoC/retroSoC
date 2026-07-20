// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef NMI_SDRAM_DEF_SV
`define NMI_SDRAM_DEF_SV

// verilog_format: off
`define NMI_SDRAM_CLKDIV 8'h00
`define NMI_SDRAM_CFG    8'h04
// verilog_format: on

`endif

module sdram_reg (
    // verilog_format: off
    input  logic       clk_i,
    input  logic       rst_n_i,
    nmi_if.slave       nmi,
    output logic [1:0] clkdiv_o
    // verilog_format: on
);
  // nmi
  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;
  // register
  logic s_sdram_clkdiv_en;
  logic [1:0] s_sdram_clkdiv_d, s_sdram_clkdiv_q;

  // nmi
  assign s_nmi_wr_hdshk    = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk    = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready         = s_nmi_ready_q;
  assign nmi.rdata         = s_nmi_rdata_q;
  // reg
  assign clkdiv_o          = s_sdram_clkdiv_q;


  assign s_sdram_clkdiv_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_SDRAM_CLKDIV;
  assign s_sdram_clkdiv_d  = nmi.wdata[1:0];
  dffer #(2) u_sdram_clkdiv_dffer (
      clk_i,
      rst_n_i,
      s_sdram_clkdiv_en,
      s_sdram_clkdiv_d,
      s_sdram_clkdiv_q
  );


  // nmi resp
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
      `NMI_SDRAM_CLKDIV: s_nmi_rdata_d = {30'd0, s_sdram_clkdiv_q};
      default:           s_nmi_rdata_d = s_nmi_rdata_q;
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
