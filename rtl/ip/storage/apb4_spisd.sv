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

module apb4_spisd (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic  clk_i,
    input  logic  rst_n_i,
    apb4_if.slave apb4,
    axi4_if.slave mem_axi4,
    spi_if.dut    spi
    // verilog_format: on
);

  // clk_i/rst_n_i control configuration and media traffic. Requests route to
  // either configuration or cache mode; each selected child supplies ready,
  // data, and resp_err, with one cache operation outstanding at a time.
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

  logic        s_mem_req_valid;
  logic        s_mem_req_ready;
  logic [31:0] s_mem_req_addr;
  logic [31:0] s_mem_req_wdata;
  logic [ 3:0] s_mem_req_wstrb;
  logic [31:0] s_mem_req_rdata;
  logic        s_mem_req_resp_err;
  logic        s_byp_valid;
  logic        s_byp_ready;
  logic [31:0] s_byp_addr;
  logic [31:0] s_byp_wdata;
  logic [ 3:0] s_byp_wstrb;
  logic [31:0] s_byp_rdata;
  logic        s_byp_resp_err;
  logic        s_cache_valid;
  logic        s_cache_ready;
  logic [31:0] s_cache_addr;
  logic [31:0] s_cache_wdata;
  logic [ 3:0] s_cache_wstrb;
  logic [31:0] s_cache_rdata;
  logic        s_cache_resp_err;

  axi4_word_bridge u_mem_bridge (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .axi4          (mem_axi4),
      .req_valid_o   (s_mem_req_valid),
      .req_ready_i   (s_mem_req_ready),
      .req_addr_o    (s_mem_req_addr),
      .req_wdata_o   (s_mem_req_wdata),
      .req_wstrb_o   (s_mem_req_wstrb),
      .req_rdata_i   (s_mem_req_rdata),
      .req_resp_err_i(s_mem_req_resp_err)
  );

  spisd_reg u_spisd_reg (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .init_done_i   (s_init_done),
      .wr_sync_o     (s_wr_sync),
      .wr_sync_done_i(s_wr_sync_done),
      .mode_o        (s_mode),
      .clkdiv_o      (s_clkdiv),
      .apb4          (apb4),
      .byp_valid_o   (s_byp_valid),
      .byp_ready_i   (s_byp_ready),
      .byp_addr_o    (s_byp_addr),
      .byp_wdata_o   (s_byp_wdata),
      .byp_wstrb_o   (s_byp_wstrb),
      .byp_rdata_i   (s_byp_rdata),
      .byp_resp_err_i(s_byp_resp_err)
  );

  assign s_cache_valid      = s_mode ? s_byp_valid : s_mem_req_valid;
  assign s_cache_addr       = s_mode ? s_byp_addr : s_mem_req_addr;
  assign s_cache_wdata      = s_mode ? s_byp_wdata : s_mem_req_wdata;
  assign s_cache_wstrb      = s_mode ? s_byp_wstrb : s_mem_req_wstrb;
  assign s_byp_ready        = s_mode ? s_cache_ready : 1'b0;
  assign s_byp_rdata        = s_mode ? s_cache_rdata : '0;
  assign s_byp_resp_err     = s_mode ? s_cache_resp_err : 1'b0;
  assign s_mem_req_ready    = ~s_mode ? s_cache_ready : 1'b0;
  assign s_mem_req_rdata    = ~s_mode ? s_cache_rdata : '0;
  assign s_mem_req_resp_err = ~s_mode ? s_cache_resp_err : 1'b0;

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
      .req_valid_i     (s_cache_valid),
      .req_ready_o     (s_cache_ready),
      .req_addr_i      (s_cache_addr),
      .req_wdata_i     (s_cache_wdata),
      .req_wstrb_i     (s_cache_wstrb),
      .req_rdata_o     (s_cache_rdata),
      .req_resp_err_o  (s_cache_resp_err)
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
