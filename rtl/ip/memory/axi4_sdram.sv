// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"

interface sdram_if ();
  logic        clk_o;
  logic        cke_o;
  logic        cs_n_o;
  logic        ras_n_o;
  logic        cas_n_o;
  logic        we_n_o;
  logic [ 1:0] ba_o;
  logic [12:0] addr_o;
  logic [ 1:0] dqm_o;
  logic        oe_o;
  logic [15:0] dq_i;
  logic [15:0] dq_o;

  modport dut(
      output clk_o,
      output cke_o,
      output cs_n_o,
      output ras_n_o,
      output cas_n_o,
      output we_n_o,
      output ba_o,
      output addr_o,
      output dqm_o,
      output oe_o,
      input dq_i,
      output dq_o
  );
endinterface


module axi4_sdram (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic  clk_i,
    input  logic  rst_n_i,
    axi4_if.slave axi4,
    apb4_if.slave cfg_apb4,
    sdram_if.dut  sdram
    // verilog_format: on
);

  // clk_i/rst_n_i drive all logic. Configuration is APB4; memory traffic stays
  // on the AXI4 window and is serialized into one native word request.
  logic [ 1:0] s_sdram_clkdiv;
  logic        s_sdram_clk;
  logic        s_fir_edge;
  logic        s_sec_edge;
  logic        s_req_valid;
  logic        s_req_ready;
  logic [31:0] s_req_addr;
  logic [31:0] s_req_wdata;
  logic [ 3:0] s_req_wstrb;
  logic [31:0] s_req_rdata;
  logic        s_req_resp_err;

  axi4_word_bridge u_axi4_word_bridge (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .axi4          (axi4),
      .req_valid_o   (s_req_valid),
      .req_ready_i   (s_req_ready),
      .req_addr_o    (s_req_addr),
      .req_wdata_o   (s_req_wdata),
      .req_wstrb_o   (s_req_wstrb),
      .req_rdata_i   (s_req_rdata),
      .req_resp_err_i(s_req_resp_err)
  );

  sdram_reg u_sdram_reg (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .apb4    (cfg_apb4),
      .clkdiv_o(s_sdram_clkdiv)
  );

  sdram_clkgen u_sdram_clkgen (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .div_i     (s_sdram_clkdiv),
      .clk_o     (s_sdram_clk),
      .fir_edge_o(s_fir_edge),
      .sec_edge_o(s_sec_edge)
  );

  sdram_core u_sdram_core (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .fir_edge_i    (s_fir_edge),
      .sec_edge_i    (s_sec_edge),
      .sdram_clk_i   (s_sdram_clk),
      .req_valid_i   (s_req_valid),
      .req_ready_o   (s_req_ready),
      .req_addr_i    (s_req_addr),
      .req_wdata_i   (s_req_wdata),
      .req_wstrb_i   (s_req_wstrb),
      .req_rdata_o   (s_req_rdata),
      .req_resp_err_o(s_req_resp_err),
      .sdram         (sdram)
  );

endmodule
