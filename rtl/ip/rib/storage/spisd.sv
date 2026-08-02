// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
//
// memory-map rd/wr for first 256MB range of TF card
// cache size: 512(width 9) [8:0]
// tag width: 23(mem access) 32(reg access)

`include "mmap_define.svh"

module rib_spisd (
    // verilog_format: off
    input  logic clk_i,
    input  logic rst_n_i,
    rib_if.slave rib,
    spi_if.dut   spi
    // verilog_format: on
);

  logic        s_cfg_reg_sel;
  logic        s_init_done;
  logic        s_wr_sync;
  logic        s_wr_sync_done;
  logic        s_mode;
  logic [ 1:0] s_clkdiv;
  logic        s_fir_clk_edge;
  logic [31:0] s_sd_addr;
  logic        s_sd_rd_req;
  logic        s_sd_rd_vld;
  logic [ 7:0] s_sd_rd_data;
  logic        s_sd_rd_busy;
  logic        s_sd_wr_req;
  logic        s_sd_wr_data_req;
  logic [ 7:0] s_sd_wr_data;
  logic        s_sd_wr_busy;

  rib_if u_cfg_rib_if ();
  rib_if u_cache_rib_if ();
  rib_if u_cache_mem_rib_if ();
  rib_if u_cache_byp_rib_if ();

  // verilog_format: off
  assign s_cfg_reg_sel            = `SOC_ADDR_IS_RIB_SPISD(rib.addr);
  assign u_cfg_rib_if.valid       = rib.valid && s_cfg_reg_sel;
  assign u_cfg_rib_if.addr        = rib.addr;
  assign u_cfg_rib_if.wdata       = rib.wdata;
  assign u_cfg_rib_if.wstrb       = rib.wstrb;

  assign u_cache_mem_rib_if.valid = rib.valid && (~s_cfg_reg_sel);
  assign u_cache_mem_rib_if.addr  = rib.addr;
  assign u_cache_mem_rib_if.wdata = rib.wdata;
  assign u_cache_mem_rib_if.wstrb = rib.wstrb;

  assign rib.ready                = s_cfg_reg_sel ? u_cfg_rib_if.ready : u_cache_mem_rib_if.ready;
  assign rib.rdata                = s_cfg_reg_sel ? u_cfg_rib_if.rdata : u_cache_mem_rib_if.rdata;
 // verilog_format: on

  spisd_reg u_spisd_reg (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .init_done_i   (s_init_done),
      .wr_sync_o     (s_wr_sync),
      .wr_sync_done_i(s_wr_sync_done),
      .mode_o        (s_mode),
      .clkdiv_o      (s_clkdiv),
      .rib           (u_cfg_rib_if),
      .byp_rib       (u_cache_byp_rib_if)
  );


  assign u_cache_rib_if.valid     = s_mode ? u_cache_byp_rib_if.valid : u_cache_mem_rib_if.valid;
  assign u_cache_rib_if.addr      = s_mode ? u_cache_byp_rib_if.addr : u_cache_mem_rib_if.addr;
  assign u_cache_rib_if.wdata     = s_mode ? u_cache_byp_rib_if.wdata : u_cache_mem_rib_if.wdata;
  assign u_cache_rib_if.wstrb     = s_mode ? u_cache_byp_rib_if.wstrb : u_cache_mem_rib_if.wstrb;

  assign u_cache_byp_rib_if.ready = s_mode ? u_cache_rib_if.ready : '0;
  assign u_cache_byp_rib_if.rdata = s_mode ? u_cache_rib_if.rdata : '0;
  assign u_cache_mem_rib_if.ready = ~s_mode ? u_cache_rib_if.ready : '0;
  assign u_cache_mem_rib_if.rdata = ~s_mode ? u_cache_rib_if.rdata : '0;
  spisd_cache u_spisd_cache (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .mode_i          (s_mode),
      .init_done_i     (s_init_done),
      .wr_sync_i       (s_wr_sync),
      .wr_sync_done_o  (s_wr_sync_done),
      .fir_clk_edge_i  (s_fir_clk_edge),
      .sd_addr_o       (s_sd_addr),
      .sd_rd_req_o     (s_sd_rd_req),
      .sd_rd_vld_i     (s_sd_rd_vld),
      .sd_rd_data_i    (s_sd_rd_data),
      .sd_rd_busy_i    (s_sd_rd_busy),
      .sd_wr_req_o     (s_sd_wr_req),
      .sd_wr_data_req_i(s_sd_wr_data_req),
      .sd_wr_data_o    (s_sd_wr_data),
      .sd_wr_busy_i    (s_sd_wr_busy),
      .rib             (u_cache_rib_if)
  );

  assign spi.irq_o = 1'b0;  // TODO:
  spisd_core u_spisd_core (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .cfg_clkdiv_i  (s_clkdiv),
      .fir_clk_edge_o(s_fir_clk_edge),
      .init_done_o   (s_init_done),
      .sec_addr_i    (s_sd_addr),
      .rd_req_i      (s_sd_rd_req),
      .rd_data_vld_o (s_sd_rd_vld),
      .rd_data_o     (s_sd_rd_data),
      .rd_busy_o     (s_sd_rd_busy),
      .wr_req_i      (s_sd_wr_req),
      .wr_data_req_o (s_sd_wr_data_req),
      .wr_data_i     (s_sd_wr_data),
      .wr_busy_o     (s_sd_wr_busy),
      .spisd_clk_o   (spi.sck_o),
      .spisd_cs_o    (spi.nss_o),
      .spisd_mosi_o  (spi.mosi_o),
      .spisd_miso_i  (spi.miso_i)
  );

endmodule
