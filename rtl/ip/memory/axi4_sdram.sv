// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"
`include "sdram_define.svh"

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

// Fixed-geometry 16-bit / 64 MiB SDR controller. sdram_reg owns the handwritten
// APB ABI, sdram_clkgen produces the divided SDR clock plus fir_edge/sec_edge,
// sdram_axi4 queues one outstanding AXI read and one outstanding AXI write into
// native multi-beat fragments, and sdram_core owns JEDEC init, four open rows,
// refresh credit, and the phase-separated command/data engine. Commands and
// write data launch on sec_edge; read data is sampled on fir_edge. There is no
// AXI word-bridge and no register generator.
module axi4_sdram (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic  clk_i,
    input  logic  rst_n_i,
    axi4_if.slave axi4,
    apb4_if.slave cfg_apb4,
    sdram_if.dut  sdram
    // verilog_format: on
);

  import sdram_pkg::*;

  logic         [ 1:0] s_clkdiv;
  logic                s_sdram_clk;
  logic                s_fir_edge;
  logic                s_sec_edge;
  logic                s_init_busy;
  logic                s_axi_busy;
  logic                s_phy_busy;
  logic                s_ready;
  logic                s_auto_init;
  logic                s_open_page;
  logic                s_ctrl_enable;
  logic                s_mem_enable;
  logic         [ 1:0] s_cas;
  logic         [ 1:0] s_burst_len;
  logic                s_write_burst;
  logic         [ 7:0] s_trp;
  logic         [ 7:0] s_trcd;
  logic         [ 7:0] s_tras;
  logic         [ 7:0] s_trc;
  logic         [ 7:0] s_twr;
  logic         [ 7:0] s_trfc;
  logic         [ 7:0] s_trrd;
  logic         [ 7:0] s_twtr;
  logic         [ 7:0] s_trtp;
  logic         [ 7:0] s_tmrd;
  logic         [ 7:0] s_txsr;
  logic         [15:0] s_trefi;
  logic         [ 3:0] s_credit_max;
  logic         [15:0] s_powerup;
  logic                s_init_start;
  logic                s_reinit_start;
  logic                s_precharge_all;
  logic                s_refresh_start;
  logic                s_init_done_event;
  logic                s_axi_err_event;
  sdram_error_e        s_axi_err_code;
  logic         [31:0] s_axi_err_addr;
  logic                s_accept_enable;
  logic                s_core_ready;
  logic                s_perf_row_hit;
  logic                s_perf_row_miss;
  logic                s_perf_refresh_stall;
  logic                s_perf_bank_conflict;
  logic         [ 2:0] s_perf_read_bytes;
  logic         [ 2:0] s_perf_write_bytes;

  logic                s_rd_cmd_valid;
  logic                s_rd_cmd_ready;
  logic         [ 1:0] s_rd_cmd_bank;
  logic         [12:0] s_rd_cmd_row;
  logic         [ 9:0] s_rd_cmd_col;
  logic         [ 3:0] s_rd_cmd_len;
  logic                s_rd_data_valid;
  logic                s_rd_data_ready;
  logic         [31:0] s_rd_data_rdata;
  logic                s_rd_data_error;
  logic                s_wr_cmd_valid;
  logic                s_wr_cmd_ready;
  logic         [ 1:0] s_wr_cmd_bank;
  logic         [12:0] s_wr_cmd_row;
  logic         [ 9:0] s_wr_cmd_col;
  logic         [ 3:0] s_wr_cmd_len;
  logic                s_wr_data_valid;
  logic                s_wr_data_ready;
  logic         [31:0] s_wr_data_wdata;
  logic         [ 3:0] s_wr_data_wstrb;
  logic                s_wr_done_valid;
  logic                s_wr_done_ready;
  logic                s_wr_done_error;

  assign s_accept_enable = s_ctrl_enable && s_mem_enable;
  assign s_core_ready    = s_ready && !s_init_busy;

  sdram_reg u_sdram_reg (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .apb4(cfg_apb4),
      .init_busy_i(s_init_busy),
      .axi_busy_i(s_axi_busy),
      .phy_busy_i(s_phy_busy),
      .ready_i(s_ready),
      .last_error_i(s_axi_err_code),
      .last_error_addr_i(s_axi_err_addr),
      .init_done_event_i(s_init_done_event),
      .error_event_i(s_axi_err_event),
      .perf_read_byte_event_i(s_perf_read_bytes),
      .perf_write_byte_event_i(s_perf_write_bytes),
      .perf_row_hit_event_i(s_perf_row_hit),
      .perf_row_miss_event_i(s_perf_row_miss),
      .perf_refresh_stall_event_i(s_perf_refresh_stall),
      .perf_bank_conflict_event_i(s_perf_bank_conflict),
      .clkdiv_o(s_clkdiv),
      .controller_enable_o(s_ctrl_enable),
      .memory_enable_o(s_mem_enable),
      .auto_init_o(s_auto_init),
      .open_page_o(s_open_page),
      .cas_o(s_cas),
      .burst_len_o(s_burst_len),
      .write_burst_o(s_write_burst),
      .burst_type_o(),  // sequential-only MRS; burst type is not a runtime input
      .trp_o(s_trp),
      .trcd_o(s_trcd),
      .tras_o(s_tras),
      .trc_o(s_trc),
      .twr_o(s_twr),
      .trfc_o(s_trfc),
      .trrd_o(s_trrd),
      .twtr_o(s_twtr),
      .trtp_o(s_trtp),
      .tmrd_o(s_tmrd),
      .txsr_o(s_txsr),
      .trefi_o(s_trefi),
      .credit_max_o(s_credit_max),
      .powerup_cycles_o(s_powerup),
      .init_start_o(s_init_start),
      .reinit_start_o(s_reinit_start),
      .precharge_all_o(s_precharge_all),
      .refresh_start_o(s_refresh_start)
  );

  sdram_clkgen u_sdram_clkgen (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .div_i     (s_clkdiv),
      .clk_o     (s_sdram_clk),
      .fir_edge_o(s_fir_edge),
      .sec_edge_o(s_sec_edge)
  );

  sdram_axi4 u_sdram_axi4 (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .accept_enable_i(s_accept_enable),
      .core_ready_i   (s_core_ready),
      .busy_o         (s_axi_busy),
      .stall_event_o  (),                 // reserved for a later datapath-stall counter
      .axi4           (axi4),
      .rd_cmd_valid_o (s_rd_cmd_valid),
      .rd_cmd_ready_i (s_rd_cmd_ready),
      .rd_cmd_bank_o  (s_rd_cmd_bank),
      .rd_cmd_row_o   (s_rd_cmd_row),
      .rd_cmd_col_o   (s_rd_cmd_col),
      .rd_cmd_len_o   (s_rd_cmd_len),
      .rd_data_valid_i(s_rd_data_valid),
      .rd_data_ready_o(s_rd_data_ready),
      .rd_data_rdata_i(s_rd_data_rdata),
      .rd_data_error_i(s_rd_data_error),
      .wr_cmd_valid_o (s_wr_cmd_valid),
      .wr_cmd_ready_i (s_wr_cmd_ready),
      .wr_cmd_bank_o  (s_wr_cmd_bank),
      .wr_cmd_row_o   (s_wr_cmd_row),
      .wr_cmd_col_o   (s_wr_cmd_col),
      .wr_cmd_len_o   (s_wr_cmd_len),
      .wr_data_valid_o(s_wr_data_valid),
      .wr_data_ready_i(s_wr_data_ready),
      .wr_data_wdata_o(s_wr_data_wdata),
      .wr_data_wstrb_o(s_wr_data_wstrb),
      .wr_done_valid_i(s_wr_done_valid),
      .wr_done_ready_o(s_wr_done_ready),
      .wr_done_error_i(s_wr_done_error),
      .error_event_o  (s_axi_err_event),
      .error_code_o   (s_axi_err_code),
      .error_addr_o   (s_axi_err_addr)
  );

  sdram_core u_sdram_core (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .fir_edge_i          (s_fir_edge),
      .sec_edge_i          (s_sec_edge),
      .sdram_clk_i         (s_sdram_clk),
      .auto_init_i         (s_auto_init),
      .open_page_i         (s_open_page),
      .cas_i               (s_cas),
      .burst_len_i         (s_burst_len),
      .write_burst_i       (s_write_burst),
      .trp_i               (s_trp),
      .trcd_i              (s_trcd),
      .tras_i              (s_tras),
      .trc_i               (s_trc),
      .twr_i               (s_twr),
      .trfc_i              (s_trfc),
      .trrd_i              (s_trrd),
      .twtr_i              (s_twtr),
      .trtp_i              (s_trtp),
      .tmrd_i              (s_tmrd),
      .txsr_i              (s_txsr),
      .trefi_i             (s_trefi),
      .credit_max_i        (s_credit_max),
      .powerup_cycles_i    (s_powerup),
      .init_start_i        (s_init_start),
      .reinit_start_i      (s_reinit_start),
      .precharge_all_i     (s_precharge_all),
      .refresh_start_i     (s_refresh_start),
      .init_busy_o         (s_init_busy),
      .phy_busy_o          (s_phy_busy),
      .ready_o             (s_ready),
      .init_done_event_o   (s_init_done_event),
      .perf_row_hit_o      (s_perf_row_hit),
      .perf_row_miss_o     (s_perf_row_miss),
      .perf_refresh_stall_o(s_perf_refresh_stall),
      .perf_bank_conflict_o(s_perf_bank_conflict),
      .perf_read_bytes_o   (s_perf_read_bytes),
      .perf_write_bytes_o  (s_perf_write_bytes),
      .rd_cmd_valid_i      (s_rd_cmd_valid),
      .rd_cmd_ready_o      (s_rd_cmd_ready),
      .rd_cmd_bank_i       (s_rd_cmd_bank),
      .rd_cmd_row_i        (s_rd_cmd_row),
      .rd_cmd_col_i        (s_rd_cmd_col),
      .rd_cmd_len_i        (s_rd_cmd_len),
      .rd_data_valid_o     (s_rd_data_valid),
      .rd_data_ready_i     (s_rd_data_ready),
      .rd_data_rdata_o     (s_rd_data_rdata),
      .rd_data_error_o     (s_rd_data_error),
      .wr_cmd_valid_i      (s_wr_cmd_valid),
      .wr_cmd_ready_o      (s_wr_cmd_ready),
      .wr_cmd_bank_i       (s_wr_cmd_bank),
      .wr_cmd_row_i        (s_wr_cmd_row),
      .wr_cmd_col_i        (s_wr_cmd_col),
      .wr_cmd_len_i        (s_wr_cmd_len),
      .wr_data_valid_i     (s_wr_data_valid),
      .wr_data_ready_o     (s_wr_data_ready),
      .wr_data_wdata_i     (s_wr_data_wdata),
      .wr_data_wstrb_i     (s_wr_data_wstrb),
      .wr_done_valid_o     (s_wr_done_valid),
      .wr_done_ready_i     (s_wr_done_ready),
      .wr_done_error_o     (s_wr_done_error),
      .sdram               (sdram)
  );

endmodule
