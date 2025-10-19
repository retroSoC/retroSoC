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
  logic s_qspi_upbound_en;
  logic [7:0] s_qspi_upbound_d, s_qspi_upbound_q;
  logic s_qspi_lowbound_en;
  logic [7:0] s_qspi_lowbound_d, s_qspi_lowbound_q;
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
  logic s_qspi_dumtyp_en;
  logic [1:0] s_qspi_dumtyp_d, s_qspi_dumtyp_q;
  logic s_qspi_dumlen_en;
  logic [7:0] s_qspi_dumlen_d, s_qspi_dumlen_q;
  logic s_qspi_dumdat_en;
  logic [31:0] s_qspi_dumdat_d, s_qspi_dumdat_q;
  // dat
  logic s_qspi_dattyp_en;
  logic [1:0] s_qspi_dattyp_d, s_qspi_dattyp_q;
  logic s_qspi_datlen_en;
  logic [7:0] s_qspi_datlen_d, s_qspi_datlen_q;
  // ctrl
  logic s_qspi_hlvlen_en;
  logic [7:0] s_qspi_hlvlen_d, s_qspi_hlvlen_q;
  logic s_qspi_start_en;
  logic s_qspi_start_d, s_qspi_start_q;
  logic s_qspi_status_en;
  logic [2:0] s_qspi_status_d, s_qspi_status_q;
  // common
  logic s_xfer_start, s_xfer_done;
  // fifo
  logic s_tx_push_valid, s_tx_empty, s_tx_full;
  logic s_tx_pop_valid, s_tx_pop_ready;
  logic [31:0] s_tx_push_data, s_tx_pop_data;


  assign s_nmi_wr_hdshk = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready      = s_nmi_ready_q;
  assign nmi.rdata      = s_nmi_rdata_q;

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


  assign s_qspi_upbound_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_UPBOUND;
  assign s_qspi_upbound_d  = nmi.wdata[7:0];
  dffer #(8) u_qspi_upbound_dffer (
      clk_i,
      rst_n_i,
      s_qspi_upbound_en,
      s_qspi_upbound_d,
      s_qspi_upbound_q
  );


  assign s_qspi_lowbound_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_LOWBOUND;
  assign s_qspi_lowbound_d  = nmi.wdata[7:0];
  dffer #(8) u_qspi_lowbound_dffer (
      clk_i,
      rst_n_i,
      s_qspi_lowbound_en,
      s_qspi_lowbound_d,
      s_qspi_lowbound_q
  );


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


  assign s_qspi_dumtyp_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_DUMTYP;
  assign s_qspi_dumtyp_d  = nmi.wdata[1:0];
  dffer #(2) u_qspi_dumtyp_dffer (
      clk_i,
      rst_n_i,
      s_qspi_dumtyp_en,
      s_qspi_dumtyp_d,
      s_qspi_dumtyp_q
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


  assign s_qspi_dumdat_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_DUMDAT;
  always_comb begin
    s_qspi_dumdat_d = s_qspi_dumdat_q;
    if (nmi.wstrb[0]) s_qspi_dumdat_d[7:0] = nmi.wdata[7:0];
    if (nmi.wstrb[1]) s_qspi_dumdat_d[15:8] = nmi.wdata[15:8];
    if (nmi.wstrb[2]) s_qspi_dumdat_d[23:16] = nmi.wdata[23:16];
    if (nmi.wstrb[3]) s_qspi_dumdat_d[31:24] = nmi.wdata[31:24];
  end
  dffer #(32) u_qspi_dumdat_dffer (
      clk_i,
      rst_n_i,
      s_qspi_dumdat_en,
      s_qspi_dumdat_d,
      s_qspi_dumdat_q
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


  assign s_qspi_hlvlen_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_QSPI_HLVLEN;
  assign s_qspi_hlvlen_d  = nmi.wdata[7:0];
  dffer #(8) u_qspi_hlvlen_dffer (
      clk_i,
      rst_n_i,
      s_qspi_hlvlen_en,
      s_qspi_hlvlen_d,
      s_qspi_hlvlen_q
  );

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
      .flush_i(1'b0),
      .push_i (s_tx_push_valid),
      .full_o (s_tx_full),
      .dat_i  (s_tx_push_data),
      .pop_i  (s_tx_pop_valid),
      .empty_o(s_tx_empty),
      .dat_o  (s_tx_pop_data),
      .cnt_o  ()
  );


  // [0] xfer done [1] tx fifo full [2] tx fifo empty
  always_comb begin
    s_qspi_status_d    = s_qspi_status_q;
    s_qspi_status_d[1] = s_tx_full;
    s_qspi_status_d[2] = s_tx_empty;
    if (s_xfer_done) begin
      s_qspi_status_d[0] = 1'b1;
    end else if (s_nmi_rd_hdshk && nmi.addr[7:0] == `NATV_QSPI_STATUS) begin
      s_qspi_status_d[0] = 1'b0;
    end
  end
  dffr #(3) u_qspi_status_dffr (
      clk_i,
      rst_n_i,
      s_qspi_status_d,
      s_qspi_status_q
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
      `NATV_QSPI_MODE:     s_nmi_rdata_d = {31'd0, s_qspi_mode_q};
      `NATV_QSPI_NSS:      s_nmi_rdata_d = {28'd0, s_qspi_nss_q};
      `NATV_QSPI_CLKDIV:   s_nmi_rdata_d = {24'd0, s_qspi_clkdiv_q};
      `NATV_QSPI_UPBOUND:  s_nmi_rdata_d = {24'd0, s_qspi_upbound_q};
      `NATV_QSPI_LOWBOUND: s_nmi_rdata_d = {24'd0, s_qspi_lowbound_q};
      `NATV_QSPI_CMDTYP:   s_nmi_rdata_d = {30'd0, s_qspi_cmdtyp_q};
      `NATV_QSPI_CMDLEN:   s_nmi_rdata_d = {30'd0, s_qspi_cmdlen_q};
      `NATV_QSPI_CMDDAT:   s_nmi_rdata_d = s_qspi_cmddat_q;
      `NATV_QSPI_ADRTYP:   s_nmi_rdata_d = {30'd0, s_qspi_adrtyp_q};
      `NATV_QSPI_ADRLEN:   s_nmi_rdata_d = {30'd0, s_qspi_adrlen_q};
      `NATV_QSPI_ADRDAT:   s_nmi_rdata_d = s_qspi_adrdat_q;
      `NATV_QSPI_DUMTYP:   s_nmi_rdata_d = {30'd0, s_qspi_dumtyp_q};
      `NATV_QSPI_DUMLEN:   s_nmi_rdata_d = {24'd0, s_qspi_dumlen_q};
      `NATV_QSPI_DUMDAT:   s_nmi_rdata_d = s_qspi_dumdat_q;
      `NATV_QSPI_DATTYP:   s_nmi_rdata_d = {30'd0, s_qspi_dattyp_q};
      `NATV_QSPI_DATLEN:   s_nmi_rdata_d = {24'd0, s_qspi_datlen_q};
      `NATV_QSPI_STATUS:   s_nmi_rdata_d = {29'd0, s_qspi_status_q};
      default:             s_nmi_rdata_d = s_nmi_rdata_q;
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
      .cmdtyp_i     (s_qspi_cmdtyp_q),
      .cmdlen_i     (s_qspi_cmdlen_q),
      .cmddat_i     (s_qspi_cmddat_q),
      .adrtyp_i     (s_qspi_adrtyp_q),
      .adrlen_i     (s_qspi_adrlen_q),
      .adrdat_i     (s_qspi_adrdat_q),
      .dumtyp_i     (s_qspi_dumtyp_q),
      .dumlen_i     (s_qspi_dumlen_q),
      .dumdat_i     (s_qspi_dumdat_q),
      .dattyp_i     (s_qspi_dattyp_q),
      .datlen_i     (s_qspi_datlen_q),
      .hlvlen_i     (s_qspi_hlvlen_q),
      .tx_data_req_o(s_tx_pop_valid),
      .tx_data_rdy_i(s_tx_pop_ready),
      .tx_data_i    (s_tx_pop_data),
      .start_i      (s_xfer_start),
      .done_o       (s_xfer_done),
      .qspi         (qspi)
  );

endmodule
