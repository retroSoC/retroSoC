// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RIB_DMA_DEF_SV
`define RIB_DMA_DEF_SV

// verilog_format: off
`define RIB_DMA_MODE         8'h00
`define RIB_DMA_SRCADDR      8'h04
`define RIB_DMA_SRCINCR      8'h08
`define RIB_DMA_DSTADDR      8'h0C
`define RIB_DMA_DSTINCR      8'h10
`define RIB_DMA_XFERLEN      8'h14
`define RIB_DMA_START        8'h18
`define RIB_DMA_STOP         8'h1C
`define RIB_DMA_RESET        8'h20
`define RIB_DMA_STATUS       8'h24
`define RIB_DMA_FSM          8'h28
`define RIB_DMA_ERROR_STATUS 8'h2C
`define RIB_DMA_ERROR_ADDR   8'h30
// verilog_format: on

interface dma_hw_trg_if ();
  logic i2s_tx_proc;
  logic i2s_rx_proc;
  logic qspi_tx_proc;
  logic qspi_rx_proc;

  modport dut(input i2s_tx_proc, input i2s_rx_proc, input qspi_tx_proc, input qspi_rx_proc);
endinterface

`endif

module rib_dma (
    // verilog_format: off
    input  logic      clk_i,
    input  logic      rst_n_i,
    output logic      dma_xfer_done_o,
    dma_hw_trg_if.dut hw_trg,
    rib_if.slave      rib,
    soc_rib_if.master rib_dma
    // verilog_format: on
);

  logic s_rib_wr_hdshk, s_rib_rd_hdshk;
  logic s_rib_ready_d, s_rib_ready_q;
  logic s_rib_rdata_en;
  logic [31:0] s_rib_rdata_d, s_rib_rdata_q;

  logic s_dma_mode_en;
  logic [2:0] s_dma_mode_d, s_dma_mode_q;
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
  logic s_dma_error_status_d, s_dma_error_status_q;
  logic [2:0] s_dma_error_code_d, s_dma_error_code_q;
  logic [31:0] s_dma_error_addr_d, s_dma_error_addr_q;
  // common
  logic s_xfer_start, s_xfer_stop, s_xfer_reset, s_xfer_done;
  logic [ 1:0] s_xfer_fsm;
  logic        s_xfer_error;
  logic [ 2:0] s_xfer_error_code;
  logic [31:0] s_xfer_error_addr;


  assign s_rib_wr_hdshk  = rib.valid && (~s_rib_ready_q) && (|rib.wstrb);
  assign s_rib_rd_hdshk  = rib.valid && (~s_rib_ready_q) && (~(|rib.wstrb));
  assign rib.ready       = s_rib_ready_q;
  assign rib.rdata       = s_rib_rdata_q;

  assign dma_xfer_done_o = s_dma_status_q;


  assign s_dma_mode_en   = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_DMA_MODE;
  assign s_dma_mode_d    = rib.wdata[2:0];
  dffer #(3) u_dma_mode_dffer (
      clk_i,
      rst_n_i,
      s_dma_mode_en,
      s_dma_mode_d,
      s_dma_mode_q
  );


  assign s_dma_srcaddr_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_DMA_SRCADDR;
  always_comb begin
    s_dma_srcaddr_d = s_dma_srcaddr_q;
    if (rib.wstrb[0]) s_dma_srcaddr_d[7:0] = rib.wdata[7:0];
    if (rib.wstrb[1]) s_dma_srcaddr_d[15:8] = rib.wdata[15:8];
    if (rib.wstrb[2]) s_dma_srcaddr_d[23:16] = rib.wdata[23:16];
    if (rib.wstrb[3]) s_dma_srcaddr_d[31:24] = rib.wdata[31:24];
  end
  dffer #(32) u_dma_srcaddr_dffer (
      clk_i,
      rst_n_i,
      s_dma_srcaddr_en,
      s_dma_srcaddr_d,
      s_dma_srcaddr_q
  );


  assign s_dma_srcincr_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_DMA_SRCINCR;
  assign s_dma_srcincr_d  = rib.wdata[0];
  dffer #(1) u_dma_srcincr_dffer (
      clk_i,
      rst_n_i,
      s_dma_srcincr_en,
      s_dma_srcincr_d,
      s_dma_srcincr_q
  );


  assign s_dma_dstaddr_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_DMA_DSTADDR;
  always_comb begin
    s_dma_dstaddr_d = s_dma_dstaddr_q;
    if (rib.wstrb[0]) s_dma_dstaddr_d[7:0] = rib.wdata[7:0];
    if (rib.wstrb[1]) s_dma_dstaddr_d[15:8] = rib.wdata[15:8];
    if (rib.wstrb[2]) s_dma_dstaddr_d[23:16] = rib.wdata[23:16];
    if (rib.wstrb[3]) s_dma_dstaddr_d[31:24] = rib.wdata[31:24];
  end
  dffer #(32) u_dma_dstaddr_dffer (
      clk_i,
      rst_n_i,
      s_dma_dstaddr_en,
      s_dma_dstaddr_d,
      s_dma_dstaddr_q
  );

  assign s_dma_dstincr_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_DMA_DSTINCR;
  assign s_dma_dstincr_d  = rib.wdata[0];
  dffer #(1) u_dma_dstincr_dffer (
      clk_i,
      rst_n_i,
      s_dma_dstincr_en,
      s_dma_dstincr_d,
      s_dma_dstincr_q
  );

  assign s_dma_xferlen_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_DMA_XFERLEN;
  always_comb begin
    s_dma_xferlen_d = s_dma_xferlen_q;
    if (rib.wstrb[0]) s_dma_xferlen_d[7:0] = rib.wdata[7:0];
    if (rib.wstrb[1]) s_dma_xferlen_d[15:8] = rib.wdata[15:8];
    if (rib.wstrb[2]) s_dma_xferlen_d[23:16] = rib.wdata[23:16];
    if (rib.wstrb[3]) s_dma_xferlen_d[31:24] = rib.wdata[31:24];
  end
  dffer #(32) u_dma_xferlen_dffer (
      clk_i,
      rst_n_i,
      s_dma_xferlen_en,
      s_dma_xferlen_d,
      s_dma_xferlen_q
  );


  assign s_xfer_start = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_DMA_START;
  assign s_xfer_stop  = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_DMA_STOP;
  assign s_xfer_reset = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_DMA_RESET;


  always_comb begin
    s_dma_status_d = s_dma_status_q;
    if (s_rib_rd_hdshk && rib.addr[7:0] == `RIB_DMA_STATUS) begin
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

  always_comb begin
    s_dma_error_status_d = s_dma_error_status_q;
    if (s_rib_wr_hdshk && rib.addr[7:0] == `RIB_DMA_ERROR_STATUS && rib.wstrb[0] &&
        rib.wdata[0]) begin
      s_dma_error_status_d = 1'b0;
    end else if (s_xfer_error) begin
      s_dma_error_status_d = 1'b1;
    end
  end
  dffr #(1) u_dma_error_status_dffr (
      clk_i,
      rst_n_i,
      s_dma_error_status_d,
      s_dma_error_status_q
  );
  assign s_dma_error_code_d = s_xfer_error_code;
  dffer #(3) u_dma_error_code_dffer (
      clk_i,
      rst_n_i,
      s_xfer_error,
      s_dma_error_code_d,
      s_dma_error_code_q
  );
  assign s_dma_error_addr_d = s_xfer_error_addr;
  dffer #(32) u_dma_error_addr_dffer (
      clk_i,
      rst_n_i,
      s_xfer_error,
      s_dma_error_addr_d,
      s_dma_error_addr_q
  );


  assign s_rib_ready_d = rib.valid && (~s_rib_ready_q);
  dffr #(1) u_rib_ready_dffr (
      clk_i,
      rst_n_i,
      s_rib_ready_d,
      s_rib_ready_q
  );

  assign s_rib_rdata_en = s_rib_rd_hdshk;
  always_comb begin
    s_rib_rdata_d = s_rib_rdata_q;
    unique case (rib.addr[7:0])
      `RIB_DMA_MODE:         s_rib_rdata_d = {29'd0, s_dma_mode_q};
      `RIB_DMA_SRCADDR:      s_rib_rdata_d = s_dma_srcaddr_q;
      `RIB_DMA_SRCINCR:      s_rib_rdata_d = {31'd0, s_dma_srcincr_q};
      `RIB_DMA_DSTADDR:      s_rib_rdata_d = s_dma_dstaddr_q;
      `RIB_DMA_DSTINCR:      s_rib_rdata_d = {31'd0, s_dma_dstincr_q};
      `RIB_DMA_XFERLEN:      s_rib_rdata_d = s_dma_xferlen_q;
      `RIB_DMA_STATUS:       s_rib_rdata_d = {31'd0, s_dma_status_q};
      `RIB_DMA_FSM:          s_rib_rdata_d = {30'd0, s_xfer_fsm};
      `RIB_DMA_ERROR_STATUS: s_rib_rdata_d = {28'd0, s_dma_error_code_q, s_dma_error_status_q};
      `RIB_DMA_ERROR_ADDR:   s_rib_rdata_d = s_dma_error_addr_q;
      default:               s_rib_rdata_d = s_rib_rdata_q;
    endcase
  end
  dffer #(32) u_rib_rdata_dffer (
      clk_i,
      rst_n_i,
      s_rib_rdata_en,
      s_rib_rdata_d,
      s_rib_rdata_q
  );


  dma_core u_dma_core (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .mode_i      (s_dma_mode_q),
      .srcaddr_i   (s_dma_srcaddr_q),
      .srcincr_i   (s_dma_srcincr_q),
      .dstaddr_i   (s_dma_dstaddr_q),
      .dstincr_i   (s_dma_dstincr_q),
      .xferlen_i   (s_dma_xferlen_q),
      .start_i     (s_xfer_start),
      .stop_i      (s_xfer_stop),
      .reset_i     (s_xfer_reset),
      .done_o      (s_xfer_done),
      .error_o     (s_xfer_error),
      .error_code_o(s_xfer_error_code),
      .error_addr_o(s_xfer_error_addr),
      .fsm_o       (s_xfer_fsm),
      .hw_trg      (hw_trg),
      .rib         (rib_dma)
  );

endmodule
