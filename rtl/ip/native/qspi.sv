// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "qspi_define.svh"

module nmi_qspi (
    // verilog_format: off
    input  logic clk_i,
    input  logic rst_n_i,
    output logic dma_tx_stall_o,
    output logic dma_rx_stall_o,
    nmi_if.slave nmi,
    qspi_if.dut  qspi
    // verilog_format: on
);

  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;
  // reg
  logic s_qspi_mode_en;
  logic s_qspi_mode_d, s_qspi_mode_q;
  logic s_qspi_nss_en;
  logic [3:0] s_qspi_nss_d, s_qspi_nss_q;
  logic s_qspi_clkdiv_en;
  logic [7:0] s_qspi_clkdiv_d, s_qspi_clkdiv_q;
  logic s_qspi_rdwr_en;
  logic s_qspi_rdwr_d, s_qspi_rdwr_q;
  logic s_qspi_revdat_en;
  logic s_qspi_revdat_d, s_qspi_revdat_q;
  logic s_qspi_txupbound_en;
  logic [7:0] s_qspi_txupbound_d, s_qspi_txupbound_q;
  logic s_qspi_txlowbound_en;
  logic [7:0] s_qspi_txlowbound_d, s_qspi_txlowbound_q;
  logic s_qspi_rxupbound_en;
  logic [5:0] s_qspi_rxupbound_d, s_qspi_rxupbound_q;
  logic s_qspi_rxlowbound_en;
  logic [5:0] s_qspi_rxlowbound_d, s_qspi_rxlowbound_q;
  logic s_qspi_flush, s_qspi_flush_val;
  logic s_tx_flush, s_rx_flush;
  // cmd
  logic s_qspi_cmdtyp_en;
  logic [1:0] s_qspi_cmdtyp_d, s_qspi_cmdtyp_q;
  logic s_qspi_cmdlen_en;
  logic [2:0] s_qspi_cmdlen_d, s_qspi_cmdlen_q;
  logic s_qspi_cmddat_en;
  logic [31:0] s_qspi_cmddat_d, s_qspi_cmddat_q;
  // adr
  logic s_qspi_adrtyp_en;
  logic [1:0] s_qspi_adrtyp_d, s_qspi_adrtyp_q;
  logic s_qspi_adrlen_en;
  logic [2:0] s_qspi_adrlen_d, s_qspi_adrlen_q;
  logic s_qspi_adrdat_en;
  logic [31:0] s_qspi_adrdat_d, s_qspi_adrdat_q;
  // dum
  logic s_qspi_dumlen_en;
  logic [7:0] s_qspi_dumlen_d, s_qspi_dumlen_q;
  // dat
  logic s_qspi_dattyp_en;
  logic [1:0] s_qspi_dattyp_d, s_qspi_dattyp_q;
  logic s_qspi_datlen_en;
  logic [7:0] s_qspi_datlen_d, s_qspi_datlen_q;
  logic s_qspi_datbit_en;
  logic [2:0] s_qspi_datbit_d, s_qspi_datbit_q;
  // ctrl
  logic s_qspi_hlvlen_en;
  logic [7:0] s_qspi_hlvlen_d, s_qspi_hlvlen_q;
  logic s_qspi_start_en;
  logic s_qspi_start_d, s_qspi_start_q;
  logic s_qspi_status_en;
  logic [4:0] s_qspi_status_d, s_qspi_status_q;
  // common
  logic s_xfer_start, s_xfer_done;
  logic s_tx_fifo_stall_d, s_tx_fifo_stall_q;
  logic s_rx_fifo_stall_d, s_rx_fifo_stall_q;
  // tx fifo
  logic s_tx_push_valid;  // NOTE: push ready?
  logic s_tx_pop_valid, s_tx_pop_ready;
  logic s_tx_empty, s_tx_full;
  logic [31:0] s_tx_push_data, s_tx_pop_data;
  logic [8:0] s_tx_elem_num;
  // rx fifo
  logic s_rx_push_valid, s_rx_push_ready;
  logic s_rx_pop_valid, s_rx_pop_ready;
  logic s_rx_empty, s_rx_full;
  logic [31:0] s_rx_push_data, s_rx_pop_data;
  logic [6:0] s_rx_elem_num;


  assign s_nmi_wr_hdshk = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready      = s_nmi_ready_q;
  assign nmi.rdata      = s_nmi_rdata_q;
  // dma
  assign dma_tx_stall_o = s_tx_fifo_stall_q;
  assign dma_rx_stall_o = s_rx_fifo_stall_q;
  // fifo
  assign s_tx_flush     = s_qspi_flush & s_qspi_flush_val;
  assign s_rx_flush     = s_qspi_flush & (~s_qspi_flush_val);


  assign s_qspi_mode_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_MODE;
  assign s_qspi_mode_d  = nmi.wdata[0];
  dffer #(1) u_qspi_mode_dffer (
      clk_i,
      rst_n_i,
      s_qspi_mode_en,
      s_qspi_mode_d,
      s_qspi_mode_q
  );


  assign s_qspi_nss_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_NSS;
  assign s_qspi_nss_d  = nmi.wdata[3:0];
  dffer #(4) u_qspi_nss_dffer (
      clk_i,
      rst_n_i,
      s_qspi_nss_en,
      s_qspi_nss_d,
      s_qspi_nss_q
  );


  assign s_qspi_clkdiv_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_CLKDIV;
  assign s_qspi_clkdiv_d  = nmi.wdata[7:0];
  dffer #(8) u_qspi_clkdiv_dffer (
      clk_i,
      rst_n_i,
      s_qspi_clkdiv_en,
      s_qspi_clkdiv_d,
      s_qspi_clkdiv_q
  );


  assign s_qspi_revdat_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_REVDAT;
  assign s_qspi_revdat_d  = nmi.wdata[0];
  dffer #(1) u_qspi_revdat_dffer (
      clk_i,
      rst_n_i,
      s_qspi_revdat_en,
      s_qspi_revdat_d,
      s_qspi_revdat_q
  );


  assign s_qspi_rdwr_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_RDWR;
  assign s_qspi_rdwr_d  = nmi.wdata[0];
  dffer #(1) u_qspi_rdwr_dffer (
      clk_i,
      rst_n_i,
      s_qspi_rdwr_en,
      s_qspi_rdwr_d,
      s_qspi_rdwr_q
  );


  assign s_qspi_txupbound_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_TXUPBOUND;
  assign s_qspi_txupbound_d  = nmi.wdata[7:0];
  dffer #(8) u_qspi_txupbound_dffer (
      clk_i,
      rst_n_i,
      s_qspi_txupbound_en,
      s_qspi_txupbound_d,
      s_qspi_txupbound_q
  );


  assign s_qspi_txlowbound_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_TXLOWBOUND;
  assign s_qspi_txlowbound_d  = nmi.wdata[7:0];
  dffer #(8) u_qspi_txlowbound_dffer (
      clk_i,
      rst_n_i,
      s_qspi_txlowbound_en,
      s_qspi_txlowbound_d,
      s_qspi_txlowbound_q
  );


  assign s_qspi_rxupbound_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_RXUPBOUND;
  assign s_qspi_rxupbound_d  = nmi.wdata[5:0];
  dffer #(6) u_qspi_rxupbound_dffer (
      clk_i,
      rst_n_i,
      s_qspi_rxupbound_en,
      s_qspi_rxupbound_d,
      s_qspi_rxupbound_q
  );


  assign s_qspi_rxlowbound_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_RXLOWBOUND;
  assign s_qspi_rxlowbound_d  = nmi.wdata[5:0];
  dffer #(6) u_qspi_rxlowbound_dffer (
      clk_i,
      rst_n_i,
      s_qspi_rxlowbound_en,
      s_qspi_rxlowbound_d,
      s_qspi_rxlowbound_q
  );


  assign s_qspi_flush     = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_FLUSH;
  assign s_qspi_flush_val = nmi.wdata[0];


  assign s_qspi_cmdtyp_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_CMDTYP;
  assign s_qspi_cmdtyp_d  = nmi.wdata[1:0];
  dffer #(2) u_qspi_cmdtyp_dffer (
      clk_i,
      rst_n_i,
      s_qspi_cmdtyp_en,
      s_qspi_cmdtyp_d,
      s_qspi_cmdtyp_q
  );


  assign s_qspi_cmdlen_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_CMDLEN;
  assign s_qspi_cmdlen_d  = nmi.wdata[2:0];
  dffer #(3) u_qspi_cmdlen_dffer (
      clk_i,
      rst_n_i,
      s_qspi_cmdlen_en,
      s_qspi_cmdlen_d,
      s_qspi_cmdlen_q
  );


  assign s_qspi_cmddat_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_CMDDAT;
  always_comb begin
    s_qspi_cmddat_d = s_qspi_cmddat_q;
    if (nmi.wstrb[0]) s_qspi_cmddat_d[7:0] = nmi.wdata[7:0];
    if (nmi.wstrb[1]) s_qspi_cmddat_d[15:8] = nmi.wdata[15:8];
    if (nmi.wstrb[2]) s_qspi_cmddat_d[23:16] = nmi.wdata[23:16];
    if (nmi.wstrb[3]) s_qspi_cmddat_d[31:24] = nmi.wdata[31:24];
  end
  dffer #(32) u_qspi_cmddat_dffer (
      clk_i,
      rst_n_i,
      s_qspi_cmddat_en,
      s_qspi_cmddat_d,
      s_qspi_cmddat_q
  );


  assign s_qspi_adrtyp_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_ADRTYP;
  assign s_qspi_adrtyp_d  = nmi.wdata[1:0];
  dffer #(2) u_qspi_adrtyp_dffer (
      clk_i,
      rst_n_i,
      s_qspi_adrtyp_en,
      s_qspi_adrtyp_d,
      s_qspi_adrtyp_q
  );


  assign s_qspi_adrlen_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_ADRLEN;
  assign s_qspi_adrlen_d  = nmi.wdata[2:0];
  dffer #(3) u_qspi_adrlen_dffer (
      clk_i,
      rst_n_i,
      s_qspi_adrlen_en,
      s_qspi_adrlen_d,
      s_qspi_adrlen_q
  );


  assign s_qspi_adrdat_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_ADRDAT;
  always_comb begin
    s_qspi_adrdat_d = s_qspi_adrdat_q;
    if (nmi.wstrb[0]) s_qspi_adrdat_d[7:0] = nmi.wdata[7:0];
    if (nmi.wstrb[1]) s_qspi_adrdat_d[15:8] = nmi.wdata[15:8];
    if (nmi.wstrb[2]) s_qspi_adrdat_d[23:16] = nmi.wdata[23:16];
    if (nmi.wstrb[3]) s_qspi_adrdat_d[31:24] = nmi.wdata[31:24];
  end
  dffer #(32) u_qspi_adrdat_dffer (
      clk_i,
      rst_n_i,
      s_qspi_adrdat_en,
      s_qspi_adrdat_d,
      s_qspi_adrdat_q
  );


  assign s_qspi_dumlen_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_DUMLEN;
  assign s_qspi_dumlen_d  = nmi.wdata[7:0];
  dffer #(8) u_qspi_dumlen_dffer (
      clk_i,
      rst_n_i,
      s_qspi_dumlen_en,
      s_qspi_dumlen_d,
      s_qspi_dumlen_q
  );


  assign s_qspi_dattyp_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_DATTYP;
  assign s_qspi_dattyp_d  = nmi.wdata[1:0];
  dffer #(2) u_qspi_dattyp_dffer (
      clk_i,
      rst_n_i,
      s_qspi_dattyp_en,
      s_qspi_dattyp_d,
      s_qspi_dattyp_q
  );


  assign s_qspi_datlen_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_DATLEN;
  assign s_qspi_datlen_d  = nmi.wdata[7:0];
  dffer #(8) u_qspi_datlen_dffer (
      clk_i,
      rst_n_i,
      s_qspi_datlen_en,
      s_qspi_datlen_d,
      s_qspi_datlen_q
  );

  assign s_qspi_datbit_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_DATBIT;
  assign s_qspi_datbit_d  = nmi.wdata[2:0];
  dffer #(3) u_qspi_datbit_dffer (
      clk_i,
      rst_n_i,
      s_qspi_datbit_en,
      s_qspi_datbit_d,
      s_qspi_datbit_q
  );

  assign s_qspi_hlvlen_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_HLVLEN;
  assign s_qspi_hlvlen_d  = nmi.wdata[7:0];
  dffer #(8) u_qspi_hlvlen_dffer (
      clk_i,
      rst_n_i,
      s_qspi_hlvlen_en,
      s_qspi_hlvlen_d,
      s_qspi_hlvlen_q
  );


  assign s_xfer_start = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_START;


  // tx fifo
  always_comb begin
    s_tx_push_valid = 1'b0;
    s_tx_push_data  = '0;
    if (s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_TXDATA) begin
      s_tx_push_valid = 1'b1;
      if (nmi.wstrb[0]) s_tx_push_data[7:0] = nmi.wdata[7:0];
      if (nmi.wstrb[1]) s_tx_push_data[15:8] = nmi.wdata[15:8];
      if (nmi.wstrb[2]) s_tx_push_data[23:16] = nmi.wdata[23:16];
      if (nmi.wstrb[3]) s_tx_push_data[31:24] = nmi.wdata[31:24];
    end
  end

  assign s_tx_pop_ready = ~s_tx_empty;
  fifo #(
      .DATA_WIDTH  (32),
      .BUFFER_DEPTH(256)
  ) u_tx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_tx_flush),
      .push_i (s_tx_push_valid),
      .full_o (s_tx_full),
      .dat_i  (s_tx_push_data),
      .pop_i  (s_tx_pop_valid),
      .empty_o(s_tx_empty),
      .dat_o  (s_tx_pop_data),
      .cnt_o  (s_tx_elem_num)
  );

  // rx fifo
  assign s_rx_push_ready = ~s_rx_full;
  assign s_rx_pop_ready  = ~s_rx_empty;
  fifo #(
      .DATA_WIDTH  (32),
      .BUFFER_DEPTH(64)
  ) u_rx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_rx_flush),
      .push_i (s_rx_push_valid),
      .full_o (s_rx_full),
      .dat_i  (s_rx_push_data),
      .pop_i  (s_rx_pop_valid),
      .empty_o(s_rx_empty),
      .dat_o  (s_rx_pop_data),
      .cnt_o  (s_rx_elem_num)
  );


  // [4] rx fifo empty
  // [3] rx fifo full
  // [2] tx fifo empty
  // [1] tx fifo full
  // [0] xfer done
  always_comb begin
    s_qspi_status_d    = s_qspi_status_q;
    s_qspi_status_d[1] = s_tx_full;
    s_qspi_status_d[2] = s_tx_empty;
    s_qspi_status_d[3] = s_rx_full;
    s_qspi_status_d[4] = s_rx_empty;
    if (s_xfer_done) begin
      s_qspi_status_d[0] = 1'b1;
    end else if (s_nmi_rd_hdshk && nmi.addr[7:0] == `NATV_QSPI_STATUS) begin
      s_qspi_status_d[0] = 1'b0;
    end
  end
  dffr #(5) u_qspi_status_dffr (
      clk_i,
      rst_n_i,
      s_qspi_status_d,
      s_qspi_status_q
  );


  always_comb begin
    s_tx_fifo_stall_d = s_tx_fifo_stall_q;
    if (~s_tx_fifo_stall_q && s_tx_elem_num[7:0] > s_qspi_txupbound_q) begin
      s_tx_fifo_stall_d = 1'b1;
    end else if (s_tx_fifo_stall_q && s_tx_elem_num[7:0] < s_qspi_txlowbound_q) begin
      s_tx_fifo_stall_d = 1'b0;
    end
  end
  dffr #(1) u_tx_fifo_stall_dffr (
      clk_i,
      rst_n_i,
      s_tx_fifo_stall_d,
      s_tx_fifo_stall_q
  );


  always_comb begin
    s_rx_fifo_stall_d = s_rx_fifo_stall_q;
    if (~s_rx_fifo_stall_q && s_rx_elem_num[5:0] < s_qspi_rxlowbound_q) begin
      s_rx_fifo_stall_d = 1'b1;
    end else if (s_rx_fifo_stall_q && s_rx_elem_num[5:0] > s_qspi_rxupbound_q) begin
      s_rx_fifo_stall_d = 1'b0;
    end
  end
  dffr #(1) u_rx_fifo_stall_dffr (
      clk_i,
      rst_n_i,
      s_rx_fifo_stall_d,
      s_rx_fifo_stall_q
  );


  // rd
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
      `NATV_QSPI_MODE:       s_nmi_rdata_d = {31'd0, s_qspi_mode_q};
      `NATV_QSPI_NSS:        s_nmi_rdata_d = {28'd0, s_qspi_nss_q};
      `NATV_QSPI_CLKDIV:     s_nmi_rdata_d = {24'd0, s_qspi_clkdiv_q};
      `NATV_QSPI_RDWR:       s_nmi_rdata_d = {31'd0, s_qspi_rdwr_q};
      `NATV_QSPI_REVDAT:     s_nmi_rdata_d = {31'd0, s_qspi_revdat_q};
      `NATV_QSPI_TXUPBOUND:  s_nmi_rdata_d = {24'd0, s_qspi_txupbound_q};
      `NATV_QSPI_TXLOWBOUND: s_nmi_rdata_d = {24'd0, s_qspi_txlowbound_q};
      `NATV_QSPI_RXUPBOUND:  s_nmi_rdata_d = {26'd0, s_qspi_rxupbound_q};
      `NATV_QSPI_RXLOWBOUND: s_nmi_rdata_d = {26'd0, s_qspi_rxlowbound_q};
      `NATV_QSPI_CMDTYP:     s_nmi_rdata_d = {30'd0, s_qspi_cmdtyp_q};
      `NATV_QSPI_CMDLEN:     s_nmi_rdata_d = {29'd0, s_qspi_cmdlen_q};
      `NATV_QSPI_CMDDAT:     s_nmi_rdata_d = s_qspi_cmddat_q;
      `NATV_QSPI_ADRTYP:     s_nmi_rdata_d = {30'd0, s_qspi_adrtyp_q};
      `NATV_QSPI_ADRLEN:     s_nmi_rdata_d = {29'd0, s_qspi_adrlen_q};
      `NATV_QSPI_ADRDAT:     s_nmi_rdata_d = s_qspi_adrdat_q;
      `NATV_QSPI_DUMLEN:     s_nmi_rdata_d = {24'd0, s_qspi_dumlen_q};
      `NATV_QSPI_DATTYP:     s_nmi_rdata_d = {30'd0, s_qspi_dattyp_q};
      `NATV_QSPI_DATLEN:     s_nmi_rdata_d = {24'd0, s_qspi_datlen_q};
      `NATV_QSPI_DATBIT:     s_nmi_rdata_d = {29'd0, s_qspi_datbit_q};
      `NATV_QSPI_RXDATA: begin
        if (s_rx_pop_ready) begin
          s_rx_pop_valid = 1'b1;
          s_nmi_rdata_d  = s_rx_pop_data;
        end else s_nmi_rdata_d = '0;
      end
      `NATV_QSPI_STATUS:     s_nmi_rdata_d = {27'd0, s_qspi_status_q};
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


  qspi_core u_qspi_core (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .mode_i       (s_qspi_mode_q),
      .nss_i        (s_qspi_nss_q),
      .clkdiv_i     (s_qspi_clkdiv_q),
      .rdwr_i       (s_qspi_rdwr_q),
      .revdat_i     (s_qspi_revdat_q),
      .cmdtyp_i     (s_qspi_cmdtyp_q),
      .cmdlen_i     (s_qspi_cmdlen_q),
      .cmddat_i     (s_qspi_cmddat_q),
      .adrtyp_i     (s_qspi_adrtyp_q),
      .adrlen_i     (s_qspi_adrlen_q),
      .adrdat_i     (s_qspi_adrdat_q),
      .dumlen_i     (s_qspi_dumlen_q),
      .dattyp_i     (s_qspi_dattyp_q),
      .datlen_i     (s_qspi_datlen_q),
      .datbit_i     (s_qspi_datbit_q),
      .hlvlen_i     (s_qspi_hlvlen_q),
      .tx_data_req_o(s_tx_pop_valid),
      .tx_data_rdy_i(s_tx_pop_ready),
      .tx_data_i    (s_tx_pop_data),
      .rx_data_req_o(s_rx_push_valid),
      .rx_data_rdy_i(s_rx_push_ready),
      .rx_data_o    (s_rx_push_data),
      .start_i      (s_xfer_start),
      .done_o       (s_xfer_done),
      .tx_elem_num_i(s_tx_elem_num[7:0]),
      .qspi         (qspi)
  );

endmodule
