// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef APB4_DMA_DEF_SV
`define APB4_DMA_DEF_SV

// verilog_format: off -- preserve reviewed column alignment
`define APB4_DMA_MODE         8'h00
`define APB4_DMA_SRCADDR      8'h04
`define APB4_DMA_SRCINCR      8'h08
`define APB4_DMA_DSTADDR      8'h0C
`define APB4_DMA_DSTINCR      8'h10
`define APB4_DMA_XFERLEN      8'h14
`define APB4_DMA_START        8'h18
`define APB4_DMA_STOP         8'h1C
`define APB4_DMA_RESET        8'h20
`define APB4_DMA_STATUS       8'h24
`define APB4_DMA_FSM          8'h28
`define APB4_DMA_ERROR_STATUS 8'h2C
`define APB4_DMA_ERROR_ADDR   8'h30
// verilog_format: on

interface dma_hw_trg_if ();
  logic i2s_tx_proc;
  logic i2s_rx_proc;
  logic qspi_tx_proc;
  logic qspi_rx_proc;
  logic uart_tx_proc;
  logic uart_rx_proc;
  logic i2c0_tx_proc;
  logic i2c0_rx_proc;
  logic i2c1_tx_proc;
  logic i2c1_rx_proc;

  modport dut(
      input i2s_tx_proc,
      input i2s_rx_proc,
      input qspi_tx_proc,
      input qspi_rx_proc,
      input uart_tx_proc,
      input uart_rx_proc,
      input i2c0_tx_proc,
      input i2c0_rx_proc,
      input i2c1_tx_proc,
      input i2c1_rx_proc
  );
endinterface

`endif

module apb4_dma (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic          clk_i,
    input  logic          rst_n_i,
    output logic          dma_xfer_done_o,
    dma_hw_trg_if.dut     hw_trg,
    apb4_if.slave         apb4,
    rib_if.master         rib,
    axi4_stream_if.source i2s_tx_axis,
    axi4_stream_if.sink   i2s_rx_axis,
    axi4_stream_if.sink   dvp_rx_axis
    // verilog_format: on
);

  logic s_apb4_wr_hdshk, s_apb4_rd_hdshk;
  logic s_apb4_ready_d, s_apb4_ready_q;
  logic s_apb4_rdata_en;
  logic [31:0] s_apb4_rdata_d, s_apb4_rdata_q;

  logic s_dma_mode_en;
  logic [3:0] s_dma_mode_d, s_dma_mode_q;
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
  logic s_dma_stat_d, s_dma_stat_q;
  logic s_dma_err_stat_d, s_dma_err_stat_q;
  logic [2:0] s_dma_err_code_d, s_dma_err_code_q;
  logic [31:0] s_dma_err_addr_d, s_dma_err_addr_q;
  // common
  logic s_xfer_start, s_xfer_stop, s_xfer_reset, s_xfer_done;
  logic [ 1:0] s_xfer_fsm;
  logic        s_xfer_err;
  logic [ 2:0] s_xfer_err_code;
  logic [31:0] s_xfer_err_addr;


  assign s_apb4_wr_hdshk = apb4.psel && apb4.penable && (~s_apb4_ready_q) && apb4.pwrite;
  assign s_apb4_rd_hdshk = apb4.psel && apb4.penable && (~s_apb4_ready_q) && (~apb4.pwrite);
  assign apb4.pready     = s_apb4_ready_q;
  assign apb4.pslverr    = 1'b0;
  assign apb4.prdata     = s_apb4_rdata_q;

  assign dma_xfer_done_o = s_dma_stat_q;


  assign s_dma_mode_en   = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_DMA_MODE;
  assign s_dma_mode_d    = apb4.pwdata[3:0];
  dffer #(
      .DATA_WIDTH(4)
  ) u_dma_mode_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_dma_mode_en),
      .dat_i  (s_dma_mode_d),
      .dat_o  (s_dma_mode_q)
  );


  assign s_dma_srcaddr_en = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_DMA_SRCADDR;
  always_comb begin
    s_dma_srcaddr_d = s_dma_srcaddr_q;
    if (apb4.pstrb[0]) s_dma_srcaddr_d[7:0] = apb4.pwdata[7:0];
    if (apb4.pstrb[1]) s_dma_srcaddr_d[15:8] = apb4.pwdata[15:8];
    if (apb4.pstrb[2]) s_dma_srcaddr_d[23:16] = apb4.pwdata[23:16];
    if (apb4.pstrb[3]) s_dma_srcaddr_d[31:24] = apb4.pwdata[31:24];
  end
  dffer #(
      .DATA_WIDTH(32)
  ) u_dma_srcaddr_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_dma_srcaddr_en),
      .dat_i  (s_dma_srcaddr_d),
      .dat_o  (s_dma_srcaddr_q)
  );


  assign s_dma_srcincr_en = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_DMA_SRCINCR;
  assign s_dma_srcincr_d  = apb4.pwdata[0];
  dffer #(
      .DATA_WIDTH(1)
  ) u_dma_srcincr_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_dma_srcincr_en),
      .dat_i  (s_dma_srcincr_d),
      .dat_o  (s_dma_srcincr_q)
  );


  assign s_dma_dstaddr_en = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_DMA_DSTADDR;
  always_comb begin
    s_dma_dstaddr_d = s_dma_dstaddr_q;
    if (apb4.pstrb[0]) s_dma_dstaddr_d[7:0] = apb4.pwdata[7:0];
    if (apb4.pstrb[1]) s_dma_dstaddr_d[15:8] = apb4.pwdata[15:8];
    if (apb4.pstrb[2]) s_dma_dstaddr_d[23:16] = apb4.pwdata[23:16];
    if (apb4.pstrb[3]) s_dma_dstaddr_d[31:24] = apb4.pwdata[31:24];
  end
  dffer #(
      .DATA_WIDTH(32)
  ) u_dma_dstaddr_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_dma_dstaddr_en),
      .dat_i  (s_dma_dstaddr_d),
      .dat_o  (s_dma_dstaddr_q)
  );

  assign s_dma_dstincr_en = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_DMA_DSTINCR;
  assign s_dma_dstincr_d  = apb4.pwdata[0];
  dffer #(
      .DATA_WIDTH(1)
  ) u_dma_dstincr_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_dma_dstincr_en),
      .dat_i  (s_dma_dstincr_d),
      .dat_o  (s_dma_dstincr_q)
  );

  assign s_dma_xferlen_en = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_DMA_XFERLEN;
  always_comb begin
    s_dma_xferlen_d = s_dma_xferlen_q;
    if (apb4.pstrb[0]) s_dma_xferlen_d[7:0] = apb4.pwdata[7:0];
    if (apb4.pstrb[1]) s_dma_xferlen_d[15:8] = apb4.pwdata[15:8];
    if (apb4.pstrb[2]) s_dma_xferlen_d[23:16] = apb4.pwdata[23:16];
    if (apb4.pstrb[3]) s_dma_xferlen_d[31:24] = apb4.pwdata[31:24];
  end
  dffer #(
      .DATA_WIDTH(32)
  ) u_dma_xferlen_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_dma_xferlen_en),
      .dat_i  (s_dma_xferlen_d),
      .dat_o  (s_dma_xferlen_q)
  );


  assign s_xfer_start = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_DMA_START;
  assign s_xfer_stop  = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_DMA_STOP;
  assign s_xfer_reset = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_DMA_RESET;


  always_comb begin
    s_dma_stat_d = s_dma_stat_q;
    if (s_apb4_rd_hdshk && apb4.paddr[7:0] == `APB4_DMA_STATUS) begin
      s_dma_stat_d = '0;
    end else if (s_xfer_done) begin
      s_dma_stat_d = 1'b1;
    end
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_dma_status_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dma_stat_d),
      .dat_o  (s_dma_stat_q)
  );

  always_comb begin
    s_dma_err_stat_d = s_dma_err_stat_q;
    if (s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_DMA_ERROR_STATUS && apb4.pstrb[0] &&
        apb4.pwdata[0]) begin
      s_dma_err_stat_d = 1'b0;
    end else if (s_xfer_err) begin
      s_dma_err_stat_d = 1'b1;
    end
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_dma_error_status_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dma_err_stat_d),
      .dat_o  (s_dma_err_stat_q)
  );
  assign s_dma_err_code_d = s_xfer_err_code;
  dffer #(
      .DATA_WIDTH(3)
  ) u_dma_error_code_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_xfer_err),
      .dat_i  (s_dma_err_code_d),
      .dat_o  (s_dma_err_code_q)
  );
  assign s_dma_err_addr_d = s_xfer_err_addr;
  dffer #(
      .DATA_WIDTH(32)
  ) u_dma_error_addr_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_xfer_err),
      .dat_i  (s_dma_err_addr_d),
      .dat_o  (s_dma_err_addr_q)
  );


  assign s_apb4_ready_d = apb4.psel && apb4.penable && (~s_apb4_ready_q);
  dffr #(
      .DATA_WIDTH(1)
  ) u_apb4_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_ready_d),
      .dat_o  (s_apb4_ready_q)
  );

  assign s_apb4_rdata_en = s_apb4_rd_hdshk;
  always_comb begin
    s_apb4_rdata_d = s_apb4_rdata_q;
    unique case (apb4.paddr[7:0])
      `APB4_DMA_MODE:         s_apb4_rdata_d = {28'd0, s_dma_mode_q};
      `APB4_DMA_SRCADDR:      s_apb4_rdata_d = s_dma_srcaddr_q;
      `APB4_DMA_SRCINCR:      s_apb4_rdata_d = {31'd0, s_dma_srcincr_q};
      `APB4_DMA_DSTADDR:      s_apb4_rdata_d = s_dma_dstaddr_q;
      `APB4_DMA_DSTINCR:      s_apb4_rdata_d = {31'd0, s_dma_dstincr_q};
      `APB4_DMA_XFERLEN:      s_apb4_rdata_d = s_dma_xferlen_q;
      `APB4_DMA_STATUS:       s_apb4_rdata_d = {31'd0, s_dma_stat_q};
      `APB4_DMA_FSM:          s_apb4_rdata_d = {30'd0, s_xfer_fsm};
      `APB4_DMA_ERROR_STATUS: s_apb4_rdata_d = {28'd0, s_dma_err_code_q, s_dma_err_stat_q};
      `APB4_DMA_ERROR_ADDR:   s_apb4_rdata_d = s_dma_err_addr_q;
      default:                s_apb4_rdata_d = s_apb4_rdata_q;
    endcase
  end
  dffer #(
      .DATA_WIDTH(32)
  ) u_apb4_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_apb4_rdata_en),
      .dat_i  (s_apb4_rdata_d),
      .dat_o  (s_apb4_rdata_q)
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
      .error_o     (s_xfer_err),
      .error_code_o(s_xfer_err_code),
      .error_addr_o(s_xfer_err_addr),
      .fsm_o       (s_xfer_fsm),
      .hw_trg      (hw_trg),
      .rib         (rib),
      .i2s_tx_axis (i2s_tx_axis),
      .i2s_rx_axis (i2s_rx_axis),
      .dvp_rx_axis (dvp_rx_axis)
  );

endmodule
