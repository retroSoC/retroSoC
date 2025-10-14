// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef NATV_DMA_DEF_SV
`define NATV_DMA_DEF_SV

// verilog_format: off
`define NATV_DMA_MODE    8'h00
`define NATV_DMA_SRCADDR 8'h04
`define NATV_DMA_SRCINCR 8'h08
`define NATV_DMA_DSTADDR 8'h0C
`define NATV_DMA_DSTINCR 8'h10
`define NATV_DMA_XFERLEN 8'h14
`define NATV_DMA_START   8'h18
`define NATV_DMA_STOP    8'h1C
`define NATV_DMA_RESET   8'h20
`define NATV_DMA_STATUS  8'h24
// verilog_format: on

interface dma_hw_trg_if ();
  logic i2s_tx_proc;
  logic i2s_rx_proc;

  modport dut(input i2s_tx_proc, input i2s_rx_proc);
endinterface

`endif

module nmi_dma (
    // verilog_format: off
    input  logic      clk_i,
    input  logic      rst_n_i,
    dma_hw_trg_if.dut hw_trg,
    nmi_if.slave      nmi,
    nmi_if.master     nmi_dma
    // verilog_format: on
);

  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;

  logic s_dma_mode_en;
  logic [1:0] s_dma_mode_d, s_dma_mode_q;
  logic s_dma_srcaddr_en;
  logic [31:0] s_dma_srcaddr_d, s_dma_srcaddr_q;
  logic s_dma_srcincr_en;
  logic s_dma_srcincr_d, s_dma_srcincr_q;
  logic s_dma_dstaddr_en;
  logic [31:0] s_dma_dstaddr_d, s_dma_dstaddr_q;
  logic s_dma_dstincr_en;
  logic s_dma_dstincr_d, s_dma_dstincr_q;
  logic s_dma_xferlen_en;
  logic [31:0] s_dma_xferlen_d, s_dma_xferlen_q;
  logic s_dma_status_d, s_dma_status_q;
  // common
  logic s_xfer_start, s_xfer_stop, s_xfer_reset, s_xfer_done;


  assign s_nmi_wr_hdshk = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready      = s_nmi_ready_q;
  assign nmi.rdata      = s_nmi_rdata_q;


  // [3]: spi tx fifo trg [2]: i2s rx fifo trg [1]: i2s tx fifo trg [0]: sft trg
  assign s_dma_mode_en  = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_DMA_MODE;
  assign s_dma_mode_d   = nmi.wdata[1:0];
  dffer #(2) u_dma_mode_dffer (
      clk_i,
      rst_n_i,
      s_dma_mode_en,
      s_dma_mode_d,
      s_dma_mode_q
  );


  assign s_dma_srcaddr_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_DMA_SRCADDR;
  always_comb begin
    s_dma_srcaddr_d = s_dma_srcaddr_q;
    if (nmi.wstrb[0]) s_dma_srcaddr_d[7:0] = nmi.wdata[7:0];
    if (nmi.wstrb[1]) s_dma_srcaddr_d[15:8] = nmi.wdata[15:8];
    if (nmi.wstrb[2]) s_dma_srcaddr_d[23:16] = nmi.wdata[23:16];
    if (nmi.wstrb[3]) s_dma_srcaddr_d[31:24] = nmi.wdata[31:24];
  end
  dffer #(32) u_dma_srcaddr_dffer (
      clk_i,
      rst_n_i,
      s_dma_srcaddr_en,
      s_dma_srcaddr_d,
      s_dma_srcaddr_q
  );


  assign s_dma_srcincr_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_DMA_SRCINCR;
  assign s_dma_srcincr_d  = nmi.wdata[0];
  dffer #(1) u_dma_srcincr_dffer (
      clk_i,
      rst_n_i,
      s_dma_srcincr_en,
      s_dma_srcincr_d,
      s_dma_srcincr_q
  );


  assign s_dma_dstaddr_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_DMA_DSTADDR;
  always_comb begin
    s_dma_dstaddr_d = s_dma_dstaddr_q;
    if (nmi.wstrb[0]) s_dma_dstaddr_d[7:0] = nmi.wdata[7:0];
    if (nmi.wstrb[1]) s_dma_dstaddr_d[15:8] = nmi.wdata[15:8];
    if (nmi.wstrb[2]) s_dma_dstaddr_d[23:16] = nmi.wdata[23:16];
    if (nmi.wstrb[3]) s_dma_dstaddr_d[31:24] = nmi.wdata[31:24];
  end
  dffer #(32) u_dma_dstaddr_dffer (
      clk_i,
      rst_n_i,
      s_dma_dstaddr_en,
      s_dma_dstaddr_d,
      s_dma_dstaddr_q
  );

  assign s_dma_dstincr_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_DMA_DSTINCR;
  assign s_dma_dstincr_d  = nmi.wdata[0];
  dffer #(1) u_dma_dstincr_dffer (
      clk_i,
      rst_n_i,
      s_dma_dstincr_en,
      s_dma_dstincr_d,
      s_dma_dstincr_q
  );

  assign s_dma_xferlen_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_DMA_XFERLEN;
  always_comb begin
    s_dma_xferlen_d = s_dma_xferlen_q;
    if (nmi.wstrb[0]) s_dma_xferlen_d[7:0] = nmi.wdata[7:0];
    if (nmi.wstrb[1]) s_dma_xferlen_d[15:8] = nmi.wdata[15:8];
    if (nmi.wstrb[2]) s_dma_xferlen_d[23:16] = nmi.wdata[23:16];
    if (nmi.wstrb[3]) s_dma_xferlen_d[31:24] = nmi.wdata[31:24];
  end
  dffer #(32) u_dma_xferlen_dffer (
      clk_i,
      rst_n_i,
      s_dma_xferlen_en,
      s_dma_xferlen_d,
      s_dma_xferlen_q
  );


  assign s_xfer_start = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_DMA_START;
  assign s_xfer_stop  = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_DMA_STOP;
  assign s_xfer_reset = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_DMA_RESET;


  always_comb begin
    s_dma_status_d = s_dma_status_q;
    if (s_nmi_rd_hdshk && nmi.addr[7:0] == `NATV_DMA_STATUS) begin
      s_dma_status_d = '0;
    end else if (s_xfer_done) begin
      s_dma_status_d = 1'b1;
    end
  end
  dffr #(1) u_dma_status_dffr (
      clk_i,
      rst_n_i,
      s_dma_status_d,
      s_dma_status_q
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
      `NATV_DMA_MODE:    s_nmi_rdata_d = {30'd0, s_dma_mode_q};
      `NATV_DMA_SRCADDR: s_nmi_rdata_d = s_dma_srcaddr_q;
      `NATV_DMA_SRCINCR: s_nmi_rdata_d = {31'd0, s_dma_srcincr_q};
      `NATV_DMA_DSTADDR: s_nmi_rdata_d = s_dma_dstaddr_q;
      `NATV_DMA_DSTINCR: s_nmi_rdata_d = {31'd0, s_dma_dstincr_q};
      `NATV_DMA_XFERLEN: s_nmi_rdata_d = s_dma_xferlen_q;
      `NATV_DMA_STATUS:  s_nmi_rdata_d = {31'd0, s_dma_status_q};
      default:           s_nmi_rdata_d = s_nmi_rdata_q;
    endcase
  end
  dffer #(32) u_nmi_rdata_dffer (
      clk_i,
      rst_n_i,
      s_nmi_rdata_en,
      s_nmi_rdata_d,
      s_nmi_rdata_q
  );


  dma_core u_dma_core (
      .clk_i    (clk_i),
      .rst_n_i  (rst_n_i),
      .mode_i   (s_dma_mode_q),
      .srcaddr_i(s_dma_srcaddr_q),
      .srcincr_i(s_dma_srcincr_q),
      .dstaddr_i(s_dma_dstaddr_q),
      .dstincr_i(s_dma_dstincr_q),
      .xferlen_i(s_dma_xferlen_q),
      .start_i  (s_xfer_start),
      .stop_i   (s_xfer_stop),
      .reset_i  (s_xfer_reset),
      .done_o   (s_xfer_done),
      .hw_trg   (hw_trg),
      .nmi      (nmi_dma)
  );

endmodule
