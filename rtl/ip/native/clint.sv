// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef CLINT_DEF_SV
`define CLINT_DEF_SV

// verilog_format: off
`define NATV_CLINT_CLKDIV    8'h00
`define NATV_CLINT_MTIMEL    8'h04
`define NATV_CLINT_MTIMEH    8'h08
`define NATV_CLINT_MTIMECMPL 8'h0C
`define NATV_CLINT_MTIMECMPH 8'h10
`define NATV_CLINT_MSIP      8'h14
// verilog_format: on

`endif

interface simp_clint_if ();
  logic tmr_irq_o;
  logic sfr_irq_o;

  modport dut(output tmr_irq_o, output sfr_irq_o);
endinterface

module nmi_clint (
    // verilog_format: off
    input logic       clk_i,
    input logic       rst_n_i,
    nmi_if.slave      nmi,
    simp_clint_if.dut clint
    // verilog_format: on
);

  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;

  logic s_clint_clkdiv_en;
  logic [7:0] s_clint_clkdiv_d, s_clint_clkdiv_q;
  logic s_clint_mtime_en;
  logic [63:0] s_clint_mtime_d, s_clint_mtime_q;
  logic s_clint_mtimecmp_en;
  logic [63:0] s_clint_mtimecmp_d, s_clint_mtimecmp_q;
  logic s_clint_msip_en;
  logic s_clint_msip_d, s_clint_msip_q;
  // utils
  logic [7:0] s_clk_cnt_d, s_clk_cnt_q;

  assign s_nmi_wr_hdshk    = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk    = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready         = s_nmi_ready_q;
  assign nmi.rdata         = s_nmi_rdata_q;

  assign clint.tmr_irq_o   = s_clint_mtime_q >= s_clint_mtimecmp_q;
  assign clint.sfr_irq_o   = s_clint_msip_q;


  assign s_clint_clkdiv_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_CLINT_CLKDIV;
  assign s_clint_clkdiv_d  = nmi.wdata[7:0];
  dffer #(8) u_clint_clkdiv_dffer (
      clk_i,
      rst_n_i,
      s_clint_clkdiv_en,
      s_clint_clkdiv_d,
      s_clint_clkdiv_q
  );

  always_comb begin
    s_clk_cnt_d = s_clk_cnt_q;
    if (s_clk_cnt_q == s_clint_clkdiv_q) begin
      s_clk_cnt_d = '0;
    end else begin
      s_clk_cnt_d = s_clk_cnt_q + 1'b1;
    end
  end
  dffr #(8) u_clk_cnt_dffr (
      clk_i,
      rst_n_i,
      s_clk_cnt_d,
      s_clk_cnt_q
  );


  assign s_clint_mtime_en = s_clk_cnt_q == s_clint_clkdiv_q;
  assign s_clint_mtime_d  = s_clint_mtime_q + 1'b1;
  dffer #(64) u_clint_mtime_dffer (
      clk_i,
      rst_n_i,
      s_clint_mtime_en,
      s_clint_mtime_d,
      s_clint_mtime_q
  );


  assign s_clint_mtimecmp_en = s_nmi_wr_hdshk && (nmi.addr[7:0] == `NATV_CLINT_MTIMECMPL || nmi.addr[7:0] == `NATV_CLINT_MTIMECMPH);
  always_comb begin
    s_clint_mtimecmp_d = s_clint_mtimecmp_q;
    if (nmi.addr[7:0] == `NATV_CLINT_MTIMECMPL) begin
      if (nmi.wstrb[0]) s_clint_mtimecmp_d[7:0] = nmi.wdata[7:0];
      if (nmi.wstrb[1]) s_clint_mtimecmp_d[15:8] = nmi.wdata[15:8];
      if (nmi.wstrb[2]) s_clint_mtimecmp_d[23:16] = nmi.wdata[23:16];
      if (nmi.wstrb[3]) s_clint_mtimecmp_d[31:24] = nmi.wdata[31:24];
    end else if (nmi.addr[7:0] == `NATV_CLINT_MTIMECMPH) begin
      if (nmi.wstrb[0]) s_clint_mtimecmp_d[39:32] = nmi.wdata[7:0];
      if (nmi.wstrb[1]) s_clint_mtimecmp_d[47:40] = nmi.wdata[15:8];
      if (nmi.wstrb[2]) s_clint_mtimecmp_d[55:48] = nmi.wdata[23:16];
      if (nmi.wstrb[3]) s_clint_mtimecmp_d[63:56] = nmi.wdata[31:24];
    end
  end
  dfferh #(64) u_clint_mtimecmp_dfferh (
      clk_i,
      rst_n_i,
      s_clint_mtimecmp_en,
      s_clint_mtimecmp_d,
      s_clint_mtimecmp_q
  );


  assign s_clint_msip_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_CLINT_MSIP;
  assign s_clint_msip_d  = nmi.wdata[0];
  dffer #(1) u_clint_msip_dffer(
    clk_i,
    rst_n_i,
    s_clint_msip_en,
    s_clint_msip_d,
    s_clint_msip_q
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
      `NATV_CLINT_CLKDIV:    s_nmi_rdata_d = {24'd0, s_clint_clkdiv_q};
      `NATV_CLINT_MTIMEL:    s_nmi_rdata_d = s_clint_mtime_q[31:0];
      `NATV_CLINT_MTIMEH:    s_nmi_rdata_d = s_clint_mtime_q[63:32];
      `NATV_CLINT_MTIMECMPL: s_nmi_rdata_d = s_clint_mtimecmp_q[31:0];
      `NATV_CLINT_MTIMECMPH: s_nmi_rdata_d = s_clint_mtimecmp_q[63:32];
      `NATV_CLINT_MSIP:      s_nmi_rdata_d = {31'd0, s_clint_msip_q};
      default:               s_nmi_rdata_d = s_nmi_rdata_q;
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
