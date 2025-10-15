// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef SYSCTEL_DEF_SV
`define SYSCTEL_DEF_SV

// verilog_format: off
`define NATV_SYSCTRL_CORESEL 8'h00 // RO
`define NATV_SYSCTRL_IPSEL   8'h04 // WR/RD
`define NATV_SYSCTRL_I2CSEL  8'h08 // WR/RD
`define NATV_SYSCTRL_QSPISEL 8'h0C // WR/RD
// verilog_format: on

`endif

`include "mdd_config.svh"

interface sysctrl_if ();
  logic [`USER_CORESEL_WIDTH-1:0] core_sel_i;
  logic [  `USER_IPSEL_WIDTH-1:0] ip_sel_o;
  logic                           i2c_sel_o;
  logic                           qspi_sel_o;

  modport dut(input core_sel_i, output ip_sel_o, output i2c_sel_o, output qspi_sel_o);
endinterface

module nmi_sysctrl (
    // verilog_format: off
    input logic    clk_i,
    input logic    rst_n_i,
    nmi_if.slave   nmi,
    sysctrl_if.dut sysctrl
    // verilog_format: on
);

  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;

  logic [`USER_CORESEL_WIDTH-1:0] s_sysctrl_coresel_d, s_sysctrl_coresel_q;
  logic s_sysctrl_ipsel_en;
  logic [`USER_IPSEL_WIDTH-1:0] s_sysctrl_ipsel_d, s_sysctrl_ipsel_q;
  logic s_sysctrl_i2csel_en;
  logic s_sysctrl_i2csel_d, s_sysctrl_i2csel_q;
  logic s_sysctrl_qspisel_en;
  logic s_sysctrl_qspisel_d, s_sysctrl_qspisel_q;

  assign s_nmi_wr_hdshk      = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk      = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready           = s_nmi_ready_q;
  assign nmi.rdata           = s_nmi_rdata_q;

  assign sysctrl.ip_sel_o    = s_sysctrl_ipsel_q;
  assign sysctrl.i2c_sel_o   = s_sysctrl_i2csel_q;

  assign s_sysctrl_coresel_d = sysctrl.core_sel_i;
  dffr #(`USER_CORESEL_WIDTH) u_sysctrl_coresel_dffr (
      clk_i,
      rst_n_i,
      s_sysctrl_coresel_d,
      s_sysctrl_coresel_q
  );

  assign s_sysctrl_ipsel_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_SYSCTRL_IPSEL;
  assign s_sysctrl_ipsel_d  = nmi.wdata[`USER_IPSEL_WIDTH-1:0];
  dffer #(`USER_IPSEL_WIDTH) u_sysctrl_ipsel_dffer (
      clk_i,
      rst_n_i,
      s_sysctrl_ipsel_en,
      s_sysctrl_ipsel_d,
      s_sysctrl_ipsel_q
  );

  assign s_sysctrl_i2csel_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_SYSCTRL_I2CSEL;
  assign s_sysctrl_i2csel_d  = nmi.wdata[0];
  dffer #(1) u_sysctrl_i2csel_dffer (
      clk_i,
      rst_n_i,
      s_sysctrl_i2csel_en,
      s_sysctrl_i2csel_d,
      s_sysctrl_i2csel_q
  );

  assign s_sysctrl_qspisel_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_SYSCTRL_QSPISEL;
  assign s_sysctrl_qspisel_d  = nmi.wdata[0];
  dffer #(1) u_sysctrl_qspisel_dffer (
      clk_i,
      rst_n_i,
      s_sysctrl_qspisel_en,
      s_sysctrl_qspisel_d,
      s_sysctrl_qspisel_q
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
      // verilog_format: off
      `NATV_SYSCTRL_CORESEL: s_nmi_rdata_d = {{(32 - `USER_CORESEL_WIDTH) {1'b0}}, s_sysctrl_coresel_q};
      `NATV_SYSCTRL_IPSEL:   s_nmi_rdata_d = {{(32 - `USER_IPSEL_WIDTH) {1'b0}}, s_sysctrl_ipsel_q};
      `NATV_SYSCTRL_I2CSEL:  s_nmi_rdata_d = {31'd0, s_sysctrl_i2csel_q};
      `NATV_SYSCTRL_QSPISEL: s_nmi_rdata_d = {31'd0, s_sysctrl_qspisel_q};
      default: s_nmi_rdata_d = s_nmi_rdata_q;
    endcase
      // verilog_format: on
  end
  dffer #(32) u_nmi_rdata_dffer (
      clk_i,
      rst_n_i,
      s_nmi_rdata_en,
      s_nmi_rdata_d,
      s_nmi_rdata_q
  );

endmodule
