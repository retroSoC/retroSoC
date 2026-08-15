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
    ribp_if.slave cfg_ribp,
    sdram_if.dut  sdram
    // verilog_format: on
);

  // clk_i/rst_n_i drive all logic. Configuration and AXI traffic arbitrate onto
  // one RIBP path; ready/resp_err return only from the selected target.
  logic       s_sdram_reg_sel;
  logic [1:0] s_sdram_clkdiv;
  logic       s_sdram_clk;
  logic       s_fir_edge;
  logic       s_sec_edge;

  // interface
  ribp_if u_data_ribp_if ();
  ribp_if u_merged_ribp_if ();
  ribp_if u_reg_ribp_if ();
  ribp_if u_mem_ribp_if ();

  axi42ribp_burst u_axi42ribp_burst (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (axi4),
      .ribp   (u_data_ribp_if)
  );

  ribp_arbiter2 u_ribp_arbiter (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .cfg    (cfg_ribp),
      .data   (u_data_ribp_if),
      .target (u_merged_ribp_if)
  );

  // ribp mux
  assign s_sdram_reg_sel     = `SOC_ADDR_IS_RIBP_SDRAM(u_merged_ribp_if.addr);
  assign u_reg_ribp_if.valid = u_merged_ribp_if.valid && s_sdram_reg_sel;
  assign u_reg_ribp_if.addr  = u_merged_ribp_if.addr;
  assign u_reg_ribp_if.wdata = u_merged_ribp_if.wdata;
  assign u_reg_ribp_if.wstrb = u_merged_ribp_if.wstrb;

  assign u_mem_ribp_if.valid = u_merged_ribp_if.valid && !s_sdram_reg_sel;
  assign u_mem_ribp_if.addr  = u_merged_ribp_if.addr;
  assign u_mem_ribp_if.wdata = u_merged_ribp_if.wdata;
  assign u_mem_ribp_if.wstrb = u_merged_ribp_if.wstrb;

  // verilog_format: off -- preserve reviewed column alignment
  assign u_merged_ribp_if.ready = (u_reg_ribp_if.valid & u_reg_ribp_if.ready) |
                                  (u_mem_ribp_if.valid & u_mem_ribp_if.ready);
  assign u_merged_ribp_if.resp_err =
      (u_reg_ribp_if.valid & u_reg_ribp_if.ready & u_reg_ribp_if.resp_err) |
      (u_mem_ribp_if.valid & u_mem_ribp_if.ready & u_mem_ribp_if.resp_err);

  assign u_merged_ribp_if.rdata =
      ({32{(u_reg_ribp_if.valid & u_reg_ribp_if.ready)}} & u_reg_ribp_if.rdata) |
      ({32{(u_mem_ribp_if.valid & u_mem_ribp_if.ready)}} & u_mem_ribp_if.rdata);
  // verilog_format: on


  sdram_reg u_sdram_reg (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .ribp    (u_reg_ribp_if),
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
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .fir_edge_i (s_fir_edge),
      .sec_edge_i (s_sec_edge),
      .sdram_clk_i(s_sdram_clk),
      .ribp       (u_mem_ribp_if),
      .sdram      (sdram)
  );


endmodule
