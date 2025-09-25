// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef NATV_I2S_DEF_SV
`define NATV_I2S_DEF_SV

// verilog_format: off
`define NATV_I2S_MODE   8'h00
`define NATV_I2S_TXDATA 8'h04
`define NATV_I2S_RXDATA 8'h08
// verilog_format: on

interface nv_i2s_if ();
  logic mclk_o;
  logic sclk_o;
  logic lrck_o;
  logic dacdat_o;
  logic adcdat_i;

  modport dut(output mclk_o, output sclk_o, output lrck_o, output dacdat_o, input adcdat_i);

endinterface

`endif

module nmi_i2s (
    // verilog_format: off
    input logic   clk_i,
    input logic   rst_n_i,
    input logic   clk_aud_i  ,
    input logic   rst_aud_n_i,
    nmi_if.slave  nmi,
    nv_i2s_if.dut i2s
    // verilog_format: on
);


  // nmi2nmi u_nmi2nmi (
  //     .mstr_clk_i  (clk_i),
  //     .mstr_rst_n_i(rst_n_i),
  //     .mstr_valid_i(s_i2s_valid),
  //     .mstr_addr_i (s_i2s_addr),
  //     .mstr_wdata_i(s_i2s_wdata),
  //     .mstr_wstrb_i(s_i2s_wstrb),
  //     .mstr_rdata_o(s_i2s_rdata),
  //     .mstr_ready_o(s_i2s_ready),
  //     .slvr_clk_i  (clk_aud_i),
  //     .slvr_rst_n_i(rst_aud_n_i),
  //     .slvr_valid_o(s_i2s_aud_valid),
  //     .slvr_addr_o (s_i2s_aud_addr),
  //     .slvr_wdata_o(s_i2s_aud_wdata),
  //     .slvr_wstrb_o(s_i2s_aud_wstrb),
  //     .slvr_rdata_i(s_i2s_aud_rdata),
  //     .slvr_ready_i(s_i2s_aud_ready)
  // );

  i2s_core u_i2s_core (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .i2s    (i2s)
  );
endmodule
