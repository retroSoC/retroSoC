// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "qspi_define.svh"

module qspi_reg (
    // verilog_format: off
    input  logic                     clk_i,
    input  logic                     rst_n_i,
    // reg
    output logic                     qspi_accmd_o   [0:`QSPI_NSS_NUM-1],
    output logic [             31:0] qspi_mmstad_o  [0:`QSPI_NSS_NUM-1],
    output logic [             31:0] qspi_mmoffst_o [0:`QSPI_NSS_NUM-1],
    output logic                     qspi_mode_o    [0:`QSPI_NSS_NUM-1],
    output logic [`QSPI_LNS_NUM-1:0] qspi_regnss_o,
    output logic [              7:0] qspi_clkdiv_o  [0:`QSPI_NSS_NUM-1],
    output logic                     qspi_rdwr_o    [0:`QSPI_NSS_NUM-1],
    output logic                     qspi_revdat_o  [0:`QSPI_NSS_NUM-1],
    output logic                     qspi_tx_flush_o,
    output logic                     qspi_rx_flush_o,
    output logic [              1:0] qspi_cmdtyp_o  [0:`QSPI_NSS_NUM-1],
    output logic [              2:0] qspi_cmdlen_o  [0:`QSPI_NSS_NUM-1],
    output logic [             31:0] qspi_cmddat_o  [0:`QSPI_NSS_NUM-1],
    output logic [              1:0] qspi_adrtyp_o  [0:`QSPI_NSS_NUM-1],
    output logic [              2:0] qspi_adrlen_o  [0:`QSPI_NSS_NUM-1],
    output logic [             31:0] qspi_adrdat_o  [0:`QSPI_NSS_NUM-1],
    output logic [              1:0] qspi_alttyp_o  [0:`QSPI_NSS_NUM-1],
    output logic [              2:0] qspi_altlen_o  [0:`QSPI_NSS_NUM-1],
    output logic [             31:0] qspi_altdat_o  [0:`QSPI_NSS_NUM-1],
    output logic [              7:0] qspi_tdulen_o  [0:`QSPI_NSS_NUM-1],
    output logic [              7:0] qspi_rdulen_o  [0:`QSPI_NSS_NUM-1],
    output logic [              1:0] qspi_dattyp_o  [0:`QSPI_NSS_NUM-1],
    output logic [              7:0] qspi_datlen_o  [0:`QSPI_NSS_NUM-1],
    output logic [              2:0] qspi_datbit_o  [0:`QSPI_NSS_NUM-1],
    output logic [              7:0] qspi_hlvlen_o  [0:`QSPI_NSS_NUM-1],
    // tx fifo
    output logic                     tx_push_valid_o,
    output logic [             31:0] tx_push_data_o,
    input  logic                     tx_full_i,
    input  logic                     tx_empty_i,
    input  logic [              8:0] tx_elem_num_i,
    // rx fifo
    output logic                     rx_pop_valid_o,
    input  logic [             31:0] rx_pop_data_i,
    input  logic                     rx_full_i,
    input  logic                     rx_empty_i,
    input  logic [              6:0] rx_elem_num_i,
    // ctrl
    output logic                     xfer_start_o,
    input  logic                     xfer_done_i,
    // dma
    output logic                     dma_tx_stall_o,
    output logic                     dma_rx_stall_o,
    nmi_if.slave                     nmi
    // verilog_format: on
);

  // nmi
  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;
  // cfgidx
  logic                     s_qspi_cfgidx_en;
  logic [`QSPI_LNS_NUM-1:0] s_qspi_cfgidx_d;
  logic [`QSPI_LNS_NUM-1:0] s_qspi_cfgidx_q;
  // accmd
  logic [`QSPI_NSS_NUM-1:0] s_qspi_accmd_en;
  logic                     s_qspi_accmd_d    [0:`QSPI_NSS_NUM-1];
  logic                     s_qspi_accmd_q    [0:`QSPI_NSS_NUM-1];
  // mmstad
  logic [`QSPI_NSS_NUM-1:0] s_qspi_mmstad_en;
  logic [             31:0] s_qspi_mmstad_d   [0:`QSPI_NSS_NUM-1];
  logic [             31:0] s_qspi_mmstad_q   [0:`QSPI_NSS_NUM-1];
  // mmoffst
  logic [`QSPI_NSS_NUM-1:0] s_qspi_mmoffst_en;
  logic [             31:0] s_qspi_mmoffst_d  [0:`QSPI_NSS_NUM-1];
  logic [             31:0] s_qspi_mmoffst_q  [0:`QSPI_NSS_NUM-1];
  // mode
  logic [`QSPI_NSS_NUM-1:0] s_qspi_mode_en;
  logic                     s_qspi_mode_d     [0:`QSPI_NSS_NUM-1];
  logic                     s_qspi_mode_q     [0:`QSPI_NSS_NUM-1];
  // nss
  logic                     s_qspi_nss_en;
  logic [`QSPI_LNS_NUM-1:0] s_qspi_nss_d;
  logic [`QSPI_LNS_NUM-1:0] s_qspi_nss_q;
  // clkdiv
  logic [`QSPI_NSS_NUM-1:0] s_qspi_clkdiv_en;
  logic [              7:0] s_qspi_clkdiv_d   [0:`QSPI_NSS_NUM-1];
  logic [              7:0] s_qspi_clkdiv_q   [0:`QSPI_NSS_NUM-1];
  // rdwr
  logic [`QSPI_NSS_NUM-1:0] s_qspi_rdwr_en;
  logic                     s_qspi_rdwr_d     [0:`QSPI_NSS_NUM-1];
  logic                     s_qspi_rdwr_q     [0:`QSPI_NSS_NUM-1];
  // revdat
  logic [`QSPI_NSS_NUM-1:0] s_qspi_revdat_en;
  logic                     s_qspi_revdat_d   [0:`QSPI_NSS_NUM-1];
  logic                     s_qspi_revdat_q   [0:`QSPI_NSS_NUM-1];
  // txupb
  logic [`QSPI_NSS_NUM-1:0] s_qspi_txupb_en;
  logic [              7:0] s_qspi_txupb_d    [0:`QSPI_NSS_NUM-1];
  logic [              7:0] s_qspi_txupb_q    [0:`QSPI_NSS_NUM-1];
  // txlowb
  logic [`QSPI_NSS_NUM-1:0] s_qspi_txlowb_en;
  logic [              7:0] s_qspi_txlowb_d   [0:`QSPI_NSS_NUM-1];
  logic [              7:0] s_qspi_txlowb_q   [0:`QSPI_NSS_NUM-1];
  // rxupb
  logic [`QSPI_NSS_NUM-1:0] s_qspi_rxupb_en;
  logic [              5:0] s_qspi_rxupb_d    [0:`QSPI_NSS_NUM-1];
  logic [              5:0] s_qspi_rxupb_q    [0:`QSPI_NSS_NUM-1];
  // rxlowb
  logic [`QSPI_NSS_NUM-1:0] s_qspi_rxlowb_en;
  logic [              5:0] s_qspi_rxlowb_d   [0:`QSPI_NSS_NUM-1];
  logic [              5:0] s_qspi_rxlowb_q   [0:`QSPI_NSS_NUM-1];
  // flush
  logic s_qspi_flush, s_qspi_flush_val;
  // cmdtyp
  logic [`QSPI_NSS_NUM-1:0] s_qspi_cmdtyp_en;
  logic [              1:0] s_qspi_cmdtyp_d  [0:`QSPI_NSS_NUM-1];
  logic [              1:0] s_qspi_cmdtyp_q  [0:`QSPI_NSS_NUM-1];
  // cmdlen
  logic [`QSPI_NSS_NUM-1:0] s_qspi_cmdlen_en;
  logic [              2:0] s_qspi_cmdlen_d  [0:`QSPI_NSS_NUM-1];
  logic [              2:0] s_qspi_cmdlen_q  [0:`QSPI_NSS_NUM-1];
  // cmddat
  logic [`QSPI_NSS_NUM-1:0] s_qspi_cmddat_en;
  logic [             31:0] s_qspi_cmddat_d  [0:`QSPI_NSS_NUM-1];
  logic [             31:0] s_qspi_cmddat_q  [0:`QSPI_NSS_NUM-1];
  // adrtyp
  logic [`QSPI_NSS_NUM-1:0] s_qspi_adrtyp_en;
  logic [              1:0] s_qspi_adrtyp_d  [0:`QSPI_NSS_NUM-1];
  logic [              1:0] s_qspi_adrtyp_q  [0:`QSPI_NSS_NUM-1];
  // adrlen
  logic [`QSPI_NSS_NUM-1:0] s_qspi_adrlen_en;
  logic [              2:0] s_qspi_adrlen_d  [0:`QSPI_NSS_NUM-1];
  logic [              2:0] s_qspi_adrlen_q  [0:`QSPI_NSS_NUM-1];
  // adrdat
  logic [`QSPI_NSS_NUM-1:0] s_qspi_adrdat_en;
  logic [             31:0] s_qspi_adrdat_d  [0:`QSPI_NSS_NUM-1];
  logic [             31:0] s_qspi_adrdat_q  [0:`QSPI_NSS_NUM-1];
  // alttyp
  logic [`QSPI_NSS_NUM-1:0] s_qspi_alttyp_en;
  logic [              1:0] s_qspi_alttyp_d  [0:`QSPI_NSS_NUM-1];
  logic [              1:0] s_qspi_alttyp_q  [0:`QSPI_NSS_NUM-1];
  // altlen
  logic [`QSPI_NSS_NUM-1:0] s_qspi_altlen_en;
  logic [              2:0] s_qspi_altlen_d  [0:`QSPI_NSS_NUM-1];
  logic [              2:0] s_qspi_altlen_q  [0:`QSPI_NSS_NUM-1];
  // altdat
  logic [`QSPI_NSS_NUM-1:0] s_qspi_altdat_en;
  logic [             31:0] s_qspi_altdat_d  [0:`QSPI_NSS_NUM-1];
  logic [             31:0] s_qspi_altdat_q  [0:`QSPI_NSS_NUM-1];
  // tdulen
  logic [`QSPI_NSS_NUM-1:0] s_qspi_tdulen_en;
  logic [              7:0] s_qspi_tdulen_d  [0:`QSPI_NSS_NUM-1];
  logic [              7:0] s_qspi_tdulen_q  [0:`QSPI_NSS_NUM-1];
  // rdulen
  logic [`QSPI_NSS_NUM-1:0] s_qspi_rdulen_en;
  logic [              7:0] s_qspi_rdulen_d  [0:`QSPI_NSS_NUM-1];
  logic [              7:0] s_qspi_rdulen_q  [0:`QSPI_NSS_NUM-1];
  // dattyp
  logic [`QSPI_NSS_NUM-1:0] s_qspi_dattyp_en;
  logic [              1:0] s_qspi_dattyp_d  [0:`QSPI_NSS_NUM-1];
  logic [              1:0] s_qspi_dattyp_q  [0:`QSPI_NSS_NUM-1];
  // datlen
  logic [`QSPI_NSS_NUM-1:0] s_qspi_datlen_en;
  logic [              7:0] s_qspi_datlen_d  [0:`QSPI_NSS_NUM-1];
  logic [              7:0] s_qspi_datlen_q  [0:`QSPI_NSS_NUM-1];
  // datbit
  logic [`QSPI_NSS_NUM-1:0] s_qspi_datbit_en;
  logic [              2:0] s_qspi_datbit_d  [0:`QSPI_NSS_NUM-1];
  logic [              2:0] s_qspi_datbit_q  [0:`QSPI_NSS_NUM-1];
  // hlvlen
  logic [`QSPI_NSS_NUM-1:0] s_qspi_hlvlen_en;
  logic [              7:0] s_qspi_hlvlen_d  [0:`QSPI_NSS_NUM-1];
  logic [              7:0] s_qspi_hlvlen_q  [0:`QSPI_NSS_NUM-1];
  // status
  logic                     s_qspi_status_en;
  logic [             20:0] s_qspi_status_d;
  logic [             20:0] s_qspi_status_q;
  // flow ctrl
  logic s_tx_fifo_stall_d, s_tx_fifo_stall_q;
  logic s_rx_fifo_stall_d, s_rx_fifo_stall_q;

  // nmi
  assign s_nmi_wr_hdshk   = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk   = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready        = s_nmi_ready_q;
  assign nmi.rdata        = s_nmi_rdata_q;
  // reg
  assign qspi_accmd_o     = s_qspi_accmd_q;
  assign qspi_mmstad_o    = s_qspi_mmstad_q;
  assign qspi_mmoffst_o   = s_qspi_mmoffst_q;
  assign qspi_mode_o      = s_qspi_mode_q;
  assign qspi_regnss_o    = s_qspi_nss_q;
  assign qspi_clkdiv_o    = s_qspi_clkdiv_q;
  assign qspi_rdwr_o      = s_qspi_rdwr_q;
  assign qspi_revdat_o    = s_qspi_revdat_q;
  assign qspi_tx_flush_o  = s_qspi_flush & s_qspi_flush_val;
  assign qspi_rx_flush_o  = s_qspi_flush & (~s_qspi_flush_val);
  assign qspi_cmdtyp_o    = s_qspi_cmdtyp_q;
  assign qspi_cmdlen_o    = s_qspi_cmdlen_q;
  assign qspi_cmddat_o    = s_qspi_cmddat_q;
  assign qspi_adrtyp_o    = s_qspi_adrtyp_q;
  assign qspi_adrlen_o    = s_qspi_adrlen_q;
  assign qspi_adrdat_o    = s_qspi_adrdat_q;
  assign qspi_alttyp_o    = s_qspi_alttyp_q;
  assign qspi_altlen_o    = s_qspi_altlen_q;
  assign qspi_altdat_o    = s_qspi_altdat_q;
  assign qspi_tdulen_o    = s_qspi_tdulen_q;
  assign qspi_rdulen_o    = s_qspi_rdulen_q;
  assign qspi_dattyp_o    = s_qspi_dattyp_q;
  assign qspi_datlen_o    = s_qspi_datlen_q;
  assign qspi_datbit_o    = s_qspi_datbit_q;
  assign qspi_hlvlen_o    = s_qspi_hlvlen_q;
  // dma
  assign dma_tx_stall_o   = s_tx_fifo_stall_q;
  assign dma_rx_stall_o   = s_rx_fifo_stall_q;


  assign s_qspi_cfgidx_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_CFGIDX;
  assign s_qspi_cfgidx_d  = nmi.wdata[`QSPI_LNS_NUM-1:0];
  dffer #(`QSPI_LNS_NUM) u_qspi_cfgidx_dffer (
      clk_i,
      rst_n_i,
      s_qspi_cfgidx_en,
      s_qspi_cfgidx_d,
      s_qspi_cfgidx_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_ACCMD_BLOCK
    assign s_qspi_accmd_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_ACCMD && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_accmd_d[i] = nmi.wdata[0];
  end
  dfferm #(`QSPI_NSS_NUM, 1, 1'b1) u_qspi_accmd_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_accmd_en,
      s_qspi_accmd_d,
      s_qspi_accmd_q
  );


  // 5000_0000 - 5FFF_FFFF
  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_MMSTAD_BLOCK
    assign s_qspi_mmstad_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_MMSTAD && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    always_comb begin
      s_qspi_mmstad_d[i] = s_qspi_mmstad_q[i];
      if (nmi.wstrb[0]) s_qspi_mmstad_d[i][7:0] = nmi.wdata[7:0];
      if (nmi.wstrb[1]) s_qspi_mmstad_d[i][15:8] = nmi.wdata[15:8];
      if (nmi.wstrb[2]) s_qspi_mmstad_d[i][23:16] = nmi.wdata[23:16];
      if (nmi.wstrb[3]) s_qspi_mmstad_d[i][31:24] = nmi.wdata[31:24];
    end
  end
  dfferm #(`QSPI_NSS_NUM, 32, 32'd0) u_qspi_mmdstad_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_mmstad_en,
      s_qspi_mmstad_d,
      s_qspi_mmstad_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_MMOFFST_BLOCK
    assign s_qspi_mmoffst_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_MMOFFST && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    always_comb begin
      s_qspi_mmoffst_d[i] = s_qspi_mmoffst_q[i];
      if (nmi.wstrb[0]) s_qspi_mmoffst_d[i][7:0] = nmi.wdata[7:0];
      if (nmi.wstrb[1]) s_qspi_mmoffst_d[i][15:8] = nmi.wdata[15:8];
      if (nmi.wstrb[2]) s_qspi_mmoffst_d[i][23:16] = nmi.wdata[23:16];
      if (nmi.wstrb[3]) s_qspi_mmoffst_d[i][31:24] = nmi.wdata[31:24];
    end
  end
  dfferm #(`QSPI_NSS_NUM, 32, 32'h0200_0000) u_qspi_mmoffst_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_mmoffst_en,
      s_qspi_mmoffst_d,
      s_qspi_mmoffst_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_MODE_BLOCK
    assign s_qspi_mode_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_MODE && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_mode_d[i] = nmi.wdata[0];
  end
  dfferm #(`QSPI_NSS_NUM, 1, 1'b0) u_qspi_mode_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_mode_en,
      s_qspi_mode_d,
      s_qspi_mode_q
  );


  assign s_qspi_nss_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_NSS;
  assign s_qspi_nss_d  = nmi.wdata[`QSPI_LNS_NUM-1:0];
  dffer #(`QSPI_LNS_NUM) u_qspi_nss_dffer (
      clk_i,
      rst_n_i,
      s_qspi_nss_en,
      s_qspi_nss_d,
      s_qspi_nss_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_CLKDIV_BLOCK
    assign s_qspi_clkdiv_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_CLKDIV && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_clkdiv_d[i] = nmi.wdata[7:0];
  end
  dfferm #(`QSPI_NSS_NUM, 8, 8'd0) u_qspi_clkdiv_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_clkdiv_en,
      s_qspi_clkdiv_d,
      s_qspi_clkdiv_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_RDWR_BLOCK
    assign s_qspi_rdwr_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_RDWR && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_rdwr_d[i] = nmi.wdata[0];
  end
  dfferm #(`QSPI_NSS_NUM, 1, 1'b1) u_qspi_rdwr_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_rdwr_en,
      s_qspi_rdwr_d,
      s_qspi_rdwr_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_REVDAT_BLOCK
    assign s_qspi_revdat_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_REVDAT && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_revdat_d[i] = nmi.wdata[0];
  end
  dfferm #(`QSPI_NSS_NUM, 1, 1'b0) u_qspi_revdat_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_revdat_en,
      s_qspi_revdat_d,
      s_qspi_revdat_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_TXUPB_BLOCK
    assign s_qspi_txupb_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_TXUPB && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_txupb_d[i] = nmi.wdata[7:0];
  end
  dfferm #(`QSPI_NSS_NUM, 8, 8'd0) u_qspi_txupb_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_txupb_en,
      s_qspi_txupb_d,
      s_qspi_txupb_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_TXLOWB_BLOCK
    assign s_qspi_txlowb_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_TXLOWB && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_txlowb_d[i] = nmi.wdata[7:0];
  end
  dfferm #(`QSPI_NSS_NUM, 8, 8'd0) u_qspi_txlowb_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_txlowb_en,
      s_qspi_txlowb_d,
      s_qspi_txlowb_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_RXUPB_BLOCK
    assign s_qspi_rxupb_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_RXUPB && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_rxupb_d[i] = nmi.wdata[5:0];
  end
  dfferm #(`QSPI_NSS_NUM, 6, 6'd0) u_qspi_rxupb_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_rxupb_en,
      s_qspi_rxupb_d,
      s_qspi_rxupb_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_RXLOWB_BLOCK
    assign s_qspi_rxlowb_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_RXLOWB && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_rxlowb_d[i] = nmi.wdata[5:0];
  end
  dfferm #(`QSPI_NSS_NUM, 6, 6'd0) u_qspi_rxlowb_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_rxlowb_en,
      s_qspi_rxlowb_d,
      s_qspi_rxlowb_q
  );


  assign s_qspi_flush     = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_FLUSH;
  assign s_qspi_flush_val = nmi.wdata[0];


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_CMDTYP_BLOCK
    assign s_qspi_cmdtyp_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_CMDTYP && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_cmdtyp_d[i] = nmi.wdata[1:0];
  end
  dfferm #(`QSPI_NSS_NUM, 2, 2'd1) u_qspi_cmdtyp_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_cmdtyp_en,
      s_qspi_cmdtyp_d,
      s_qspi_cmdtyp_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_CMDLEN_BLOCK
    assign s_qspi_cmdlen_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_CMDLEN && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_cmdlen_d[i] = nmi.wdata[2:0];
  end
  dfferm #(`QSPI_NSS_NUM, 3, 3'd1) u_qspi_cmdlen_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_cmdlen_en,
      s_qspi_cmdlen_d,
      s_qspi_cmdlen_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_CMDDAT_BLOCK
    assign s_qspi_cmddat_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_CMDDAT && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    always_comb begin
      s_qspi_cmddat_d[i] = s_qspi_cmddat_q[i];
      if (nmi.wstrb[0]) s_qspi_cmddat_d[i][7:0] = nmi.wdata[7:0];
      if (nmi.wstrb[1]) s_qspi_cmddat_d[i][15:8] = nmi.wdata[15:8];
      if (nmi.wstrb[2]) s_qspi_cmddat_d[i][23:16] = nmi.wdata[23:16];
      if (nmi.wstrb[3]) s_qspi_cmddat_d[i][31:24] = nmi.wdata[31:24];
    end
  end
  dfferm #(`QSPI_NSS_NUM, 32, 32'hEB00_0000) u_qspi_cmddat_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_cmddat_en,
      s_qspi_cmddat_d,
      s_qspi_cmddat_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_ADRTYP_BLOCK
    assign s_qspi_adrtyp_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_ADRTYP && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_adrtyp_d[i] = nmi.wdata[1:0];
  end
  dfferm #(`QSPI_NSS_NUM, 2, 2'd3) u_qspi_adrtyp_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_adrtyp_en,
      s_qspi_adrtyp_d,
      s_qspi_adrtyp_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_ADRLEN_BLOCK
    assign s_qspi_adrlen_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_ADRLEN && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_adrlen_d[i] = nmi.wdata[2:0];
  end
  dfferm #(`QSPI_NSS_NUM, 3, 3'd4) u_qspi_adrlen_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_adrlen_en,
      s_qspi_adrlen_d,
      s_qspi_adrlen_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_ADRDAT_BLOCK
    assign s_qspi_adrdat_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_ADRDAT && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    always_comb begin
      s_qspi_adrdat_d[i] = s_qspi_adrdat_q[i];
      if (nmi.wstrb[0]) s_qspi_adrdat_d[i][7:0] = nmi.wdata[7:0];
      if (nmi.wstrb[1]) s_qspi_adrdat_d[i][15:8] = nmi.wdata[15:8];
      if (nmi.wstrb[2]) s_qspi_adrdat_d[i][23:16] = nmi.wdata[23:16];
      if (nmi.wstrb[3]) s_qspi_adrdat_d[i][31:24] = nmi.wdata[31:24];
    end
  end
  dfferm #(`QSPI_NSS_NUM, 32, 32'd0) u_qspi_adrdat_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_adrdat_en,
      s_qspi_adrdat_d,
      s_qspi_adrdat_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_ALTTYP_BLOCK
    assign s_qspi_alttyp_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_ALTTYP && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_alttyp_d[i] = nmi.wdata[1:0];
  end
  dfferm #(`QSPI_NSS_NUM, 2, 2'd0) u_qspi_alttyp_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_alttyp_en,
      s_qspi_alttyp_d,
      s_qspi_alttyp_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_ALTLEN_BLOCK
    assign s_qspi_altlen_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_ALTLEN && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_altlen_d[i] = nmi.wdata[2:0];
  end
  dfferm #(`QSPI_NSS_NUM, 3, 3'd0) u_qspi_altlen_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_altlen_en,
      s_qspi_altlen_d,
      s_qspi_altlen_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_ALTDAT_BLOCK
    assign s_qspi_altdat_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_ALTDAT && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    always_comb begin
      s_qspi_altdat_d[i] = s_qspi_altdat_q[i];
      if (nmi.wstrb[0]) s_qspi_altdat_d[i][7:0] = nmi.wdata[7:0];
      if (nmi.wstrb[1]) s_qspi_altdat_d[i][15:8] = nmi.wdata[15:8];
      if (nmi.wstrb[2]) s_qspi_altdat_d[i][23:16] = nmi.wdata[23:16];
      if (nmi.wstrb[3]) s_qspi_altdat_d[i][31:24] = nmi.wdata[31:24];
    end
  end
  dfferm #(`QSPI_NSS_NUM, 32, 32'd0) u_qspi_altdat_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_altdat_en,
      s_qspi_altdat_d,
      s_qspi_altdat_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_TDULEN_BLOCK
    assign s_qspi_tdulen_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_TDULEN && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_tdulen_d[i] = nmi.wdata[7:0];
  end
  dfferm #(`QSPI_NSS_NUM, 8, 8'd4) u_qspi_tdulen_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_tdulen_en,
      s_qspi_tdulen_d,
      s_qspi_tdulen_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_RDULEN_BLOCK
    assign s_qspi_rdulen_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_RDULEN && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_rdulen_d[i] = nmi.wdata[7:0];
  end
  dfferm #(`QSPI_NSS_NUM, 8, 8'd4) u_qspi_rdulen_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_rdulen_en,
      s_qspi_rdulen_d,
      s_qspi_rdulen_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_DATTYP_BLOCK
    assign s_qspi_dattyp_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_DATTYP && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_dattyp_d[i] = nmi.wdata[1:0];
  end
  dfferm #(`QSPI_NSS_NUM, 2, 2'd3) u_qspi_dattyp_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_dattyp_en,
      s_qspi_dattyp_d,
      s_qspi_dattyp_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_DATLEN_BLOCK
    assign s_qspi_datlen_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_DATLEN && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_datlen_d[i] = nmi.wdata[7:0];
  end
  dfferm #(`QSPI_NSS_NUM, 8, 8'd1) u_qspi_datlen_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_datlen_en,
      s_qspi_datlen_d,
      s_qspi_datlen_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_DATBIT_BLOCK
    assign s_qspi_datbit_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_DATBIT && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_datbit_d[i] = nmi.wdata[2:0];
  end
  dfferm #(`QSPI_NSS_NUM, 3, 3'd4) u_qspi_datbit_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_datbit_en,
      s_qspi_datbit_d,
      s_qspi_datbit_q
  );


  for (genvar i = 0; i < `QSPI_NSS_NUM; i++) begin : QSPI_HLVLEN_BLOCK
    assign s_qspi_hlvlen_en[i] = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_HLVLEN && `QSPI_LNS_NUM'(i) == s_qspi_cfgidx_q;
    assign s_qspi_hlvlen_d[i] = nmi.wdata[7:0];
  end
  dfferm #(`QSPI_NSS_NUM, 8, 8'd2) u_qspi_hlvlen_dfferm (
      clk_i,
      rst_n_i,
      s_qspi_hlvlen_en,
      s_qspi_hlvlen_d,
      s_qspi_hlvlen_q
  );


  // tx fifo
  always_comb begin
    tx_push_valid_o = 1'b0;
    tx_push_data_o  = '0;
    if (s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_TXDATA) begin
      tx_push_valid_o = 1'b1;
      if (nmi.wstrb[0]) tx_push_data_o[7:0] = nmi.wdata[7:0];
      if (nmi.wstrb[1]) tx_push_data_o[15:8] = nmi.wdata[15:8];
      if (nmi.wstrb[2]) tx_push_data_o[23:16] = nmi.wdata[23:16];
      if (nmi.wstrb[3]) tx_push_data_o[31:24] = nmi.wdata[31:24];
    end
  end

  // start
  assign xfer_start_o = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_START;

  // status
  // [20:14] rx elem num
  // [13:5]  tx elem num
  // [4]     rx fifo empty
  // [3]     rx fifo full
  // [2]     tx fifo empty
  // [1]     tx fifo full
  // [0]     xfer done
  always_comb begin
    s_qspi_status_d        = s_qspi_status_q;
    s_qspi_status_d[1]     = tx_full_i;
    s_qspi_status_d[2]     = tx_empty_i;
    s_qspi_status_d[3]     = rx_full_i;
    s_qspi_status_d[4]     = rx_empty_i;
    s_qspi_status_d[13:5]  = tx_elem_num_i;
    s_qspi_status_d[20:14] = rx_elem_num_i;
    if (xfer_done_i) begin
      s_qspi_status_d[0] = 1'b1;
    end else if (s_nmi_rd_hdshk && nmi.addr[7:0] == `NATV_QSPI_STATUS) begin
      s_qspi_status_d[0] = 1'b0;
    end
  end
  dffr #(21) u_qspi_status_dffr (
      clk_i,
      rst_n_i,
      s_qspi_status_d,
      s_qspi_status_q
  );


  // dma tx flow ctrl
  always_comb begin
    s_tx_fifo_stall_d = s_tx_fifo_stall_q;
    if (~s_tx_fifo_stall_q && tx_elem_num_i[7:0] > s_qspi_txupb_q[s_qspi_nss_q]) begin
      s_tx_fifo_stall_d = 1'b1;
    end else if (s_tx_fifo_stall_q && tx_elem_num_i[7:0] < s_qspi_txlowb_q[s_qspi_nss_q]) begin
      s_tx_fifo_stall_d = 1'b0;
    end
  end
  dffr #(1) u_tx_fifo_stall_dffr (
      clk_i,
      rst_n_i,
      s_tx_fifo_stall_d,
      s_tx_fifo_stall_q
  );

  // dma rx flow ctrl
  always_comb begin
    s_rx_fifo_stall_d = s_rx_fifo_stall_q;
    if (~s_rx_fifo_stall_q && rx_elem_num_i[5:0] < s_qspi_rxlowb_q[s_qspi_nss_q]) begin
      s_rx_fifo_stall_d = 1'b1;
    end else if (s_rx_fifo_stall_q && rx_elem_num_i[5:0] > s_qspi_rxupb_q[s_qspi_nss_q]) begin
      s_rx_fifo_stall_d = 1'b0;
    end
  end
  dffr #(1) u_rx_fifo_stall_dffr (
      clk_i,
      rst_n_i,
      s_rx_fifo_stall_d,
      s_rx_fifo_stall_q
  );


  // nmi rd
  assign s_nmi_ready_d = nmi.valid && (~s_nmi_ready_q);
  dffr #(1) u_nmi_ready_dffr (
      clk_i,
      rst_n_i,
      s_nmi_ready_d,
      s_nmi_ready_q
  );

  // verilog_format: off
  assign s_nmi_rdata_en = s_nmi_rd_hdshk;
  always_comb begin
    rx_pop_valid_o = '0;
    s_nmi_rdata_d  = s_nmi_rdata_q;
    unique case (nmi.addr[7:0])
      `NATV_QSPI_CFGIDX:  s_nmi_rdata_d = {{(32 - `QSPI_LNS_NUM) {1'b0}}, s_qspi_cfgidx_q};
      `NATV_QSPI_ACCMD:   s_nmi_rdata_d = {31'd0, s_qspi_accmd_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_MMSTAD:  s_nmi_rdata_d = s_qspi_mmstad_q[s_qspi_cfgidx_q];
      `NATV_QSPI_MMOFFST: s_nmi_rdata_d = s_qspi_mmoffst_q[s_qspi_cfgidx_q];
      `NATV_QSPI_MODE:    s_nmi_rdata_d = {31'd0, s_qspi_mode_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_NSS:     s_nmi_rdata_d = {{(32 - `QSPI_LNS_NUM) {1'b0}}, s_qspi_nss_q};
      `NATV_QSPI_CLKDIV:  s_nmi_rdata_d = {24'd0, s_qspi_clkdiv_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_RDWR:    s_nmi_rdata_d = {31'd0, s_qspi_rdwr_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_REVDAT:  s_nmi_rdata_d = {31'd0, s_qspi_revdat_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_TXUPB:   s_nmi_rdata_d = {24'd0, s_qspi_txupb_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_TXLOWB:  s_nmi_rdata_d = {24'd0, s_qspi_txlowb_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_RXUPB:   s_nmi_rdata_d = {26'd0, s_qspi_rxupb_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_RXLOWB:  s_nmi_rdata_d = {26'd0, s_qspi_rxlowb_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_CMDTYP:  s_nmi_rdata_d = {30'd0, s_qspi_cmdtyp_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_CMDLEN:  s_nmi_rdata_d = {29'd0, s_qspi_cmdlen_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_CMDDAT:  s_nmi_rdata_d = s_qspi_cmddat_q[s_qspi_cfgidx_q];
      `NATV_QSPI_ADRTYP:  s_nmi_rdata_d = {30'd0, s_qspi_adrtyp_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_ADRLEN:  s_nmi_rdata_d = {29'd0, s_qspi_adrlen_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_ADRDAT:  s_nmi_rdata_d = s_qspi_adrdat_q[s_qspi_cfgidx_q];
      `NATV_QSPI_ALTTYP:  s_nmi_rdata_d = {30'd0, s_qspi_alttyp_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_ALTLEN:  s_nmi_rdata_d = {29'd0, s_qspi_altlen_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_ALTDAT:  s_nmi_rdata_d = s_qspi_altdat_q[s_qspi_cfgidx_q];
      `NATV_QSPI_TDULEN:  s_nmi_rdata_d = {24'd0, s_qspi_tdulen_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_RDULEN:  s_nmi_rdata_d = {24'd0, s_qspi_rdulen_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_DATTYP:  s_nmi_rdata_d = {30'd0, s_qspi_dattyp_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_DATLEN:  s_nmi_rdata_d = {24'd0, s_qspi_datlen_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_DATBIT:  s_nmi_rdata_d = {29'd0, s_qspi_datbit_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_HLVLEN:  s_nmi_rdata_d = {24'd0, s_qspi_hlvlen_q[s_qspi_cfgidx_q]};
      `NATV_QSPI_RXDATA: begin
        if (s_nmi_rd_hdshk) begin
          rx_pop_valid_o = 1'b1;
          if (~rx_empty_i) s_nmi_rdata_d = rx_pop_data_i;
          else s_nmi_rdata_d = '0;
        end
      end
      `NATV_QSPI_STATUS:  s_nmi_rdata_d = {11'd0, s_qspi_status_q};
      default:            s_nmi_rdata_d = s_nmi_rdata_q;
    endcase
  end
  // verilog_format: on
  dffer #(32) u_nmi_rdata_dffer (
      clk_i,
      rst_n_i,
      s_nmi_rdata_en,
      s_nmi_rdata_d,
      s_nmi_rdata_q
  );

endmodule
