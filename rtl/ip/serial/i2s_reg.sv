// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "i2s_define.svh"

module i2s_reg (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic        clk_i,
    input  logic        rst_n_i,
    apb4_if.slave       apb4,
    output logic        mode_o,
    output logic [ 1:0] format_o,
    output logic        recven_o,
    output logic        stream_tx_enable_o,
    output logic        stream_rx_enable_o,
    output logic        tx_push_valid_o,
    output logic [31:0] tx_push_data_o,
    input  logic        tx_full_i,
    input  logic [ 7:0] tx_elem_num_i,
    output logic        rx_pop_valid_o,
    input  logic [31:0] rx_pop_data_i,
    input  logic        rx_empty_i,
    input  logic [ 7:0] rx_elem_num_i,
    output logic        dma_tx_stall_o,
    output logic        dma_rx_stall_o
    // verilog_format: on
);

  // apb4
  logic s_apb4_wr_hdshk, s_apb4_rd_hdshk;
  logic s_apb4_ready_d, s_apb4_ready_q;
  logic s_apb4_rdata_en;
  logic [31:0] s_apb4_rdata_d, s_apb4_rdata_q;
  // register
  logic s_i2s_mode_en;
  logic s_i2s_mode_d, s_i2s_mode_q;
  logic s_i2s_format_en;
  logic [1:0] s_i2s_format_d, s_i2s_format_q;
  logic s_i2s_upbound_en;
  logic [7:0] s_i2s_upbound_d, s_i2s_upbound_q;
  logic s_i2s_lowbound_en;
  logic [7:0] s_i2s_lowbound_d, s_i2s_lowbound_q;
  logic s_i2s_recven_en;
  logic s_i2s_recven_d, s_i2s_recven_q;
  logic [1:0] s_i2s_stat_d, s_i2s_stat_q;
  logic s_i2s_stream_en;
  logic [1:0] s_i2s_stream_d, s_i2s_stream_q;
  // common
  logic s_tx_fifo_stall_d, s_tx_fifo_stall_q;
  logic s_rx_fifo_stall_d, s_rx_fifo_stall_q;


  // apb4
  assign s_apb4_wr_hdshk    = apb4.psel && apb4.penable && (~s_apb4_ready_q) && apb4.pwrite;
  assign s_apb4_rd_hdshk    = apb4.psel && apb4.penable && (~s_apb4_ready_q) && (~apb4.pwrite);
  assign apb4.pready        = s_apb4_ready_q;
  assign apb4.pslverr       = 1'b0;
  assign apb4.prdata        = s_apb4_rdata_q;
  // reg
  assign mode_o             = s_i2s_mode_q;
  assign format_o           = s_i2s_format_q;
  assign recven_o           = s_i2s_recven_q;
  assign stream_tx_enable_o = s_i2s_stream_q[0];
  assign stream_rx_enable_o = s_i2s_stream_q[1];
  // dma
  assign dma_tx_stall_o     = s_tx_fifo_stall_q;
  assign dma_rx_stall_o     = s_rx_fifo_stall_q;


  assign s_i2s_mode_en      = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_I2S_MODE;
  assign s_i2s_mode_d       = apb4.pwdata[0];
  dffer #(
      .DATA_WIDTH(1)
  ) u_i2s_mode_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_i2s_mode_en),
      .dat_i  (s_i2s_mode_d),
      .dat_o  (s_i2s_mode_q)
  );


  assign s_i2s_format_en = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_I2S_FORMAT;
  assign s_i2s_format_d  = apb4.pwdata[1:0];
  dffer #(
      .DATA_WIDTH(2)
  ) u_i2s_format_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_i2s_format_en),
      .dat_i  (s_i2s_format_d),
      .dat_o  (s_i2s_format_q)
  );


  assign s_i2s_upbound_en = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_I2S_UPBOUND;
  assign s_i2s_upbound_d  = apb4.pwdata[7:0];
  dfferh #(
      .DATA_WIDTH(8)
  ) u_i2s_upbound_dfferh (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_i2s_upbound_en),
      .dat_i  (s_i2s_upbound_d),
      .dat_o  (s_i2s_upbound_q)
  );


  assign s_i2s_lowbound_en = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_I2S_LOWBOUND;
  assign s_i2s_lowbound_d  = apb4.pwdata[7:0];
  dffer #(
      .DATA_WIDTH(8)
  ) u_i2s_lowbound_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_i2s_lowbound_en),
      .dat_i  (s_i2s_lowbound_d),
      .dat_o  (s_i2s_lowbound_q)
  );


  assign s_i2s_recven_en = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_I2S_RECVEN;
  assign s_i2s_recven_d  = apb4.pwdata[0];
  dffer #(
      .DATA_WIDTH(1)
  ) u_i2s_recven_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_i2s_recven_en),
      .dat_i  (s_i2s_recven_d),
      .dat_o  (s_i2s_recven_q)
  );

  assign s_i2s_stream_en = s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_I2S_STREAM_CTRL;
  assign s_i2s_stream_d  = apb4.pwdata[1:0];
  dffer #(
      .DATA_WIDTH(2)
  ) u_i2s_stream_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_i2s_stream_en),
      .dat_i  (s_i2s_stream_d),
      .dat_o  (s_i2s_stream_q)
  );


  always_comb begin
    s_tx_fifo_stall_d = s_tx_fifo_stall_q;
    if (~s_tx_fifo_stall_q && tx_elem_num_i > s_i2s_upbound_q) begin
      s_tx_fifo_stall_d = 1'b1;
    end else if (s_tx_fifo_stall_q && tx_elem_num_i < s_i2s_lowbound_q) begin
      s_tx_fifo_stall_d = 1'b0;
    end
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_tx_fifo_stall_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_fifo_stall_d),
      .dat_o  (s_tx_fifo_stall_q)
  );


  always_comb begin
    s_rx_fifo_stall_d = s_rx_fifo_stall_q;
    if (~s_rx_fifo_stall_q && rx_elem_num_i < s_i2s_lowbound_q) begin
      s_rx_fifo_stall_d = 1'b1;
    end else if (s_rx_fifo_stall_q && rx_elem_num_i > s_i2s_upbound_q) begin
      s_rx_fifo_stall_d = 1'b0;
    end
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_rx_fifo_stall_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_fifo_stall_d),
      .dat_o  (s_rx_fifo_stall_q)
  );


  // TODO: need to handle when tx fifo is full(DMA is fine)
  always_comb begin
    tx_push_valid_o = 1'b0;
    tx_push_data_o  = '0;
    if (s_apb4_wr_hdshk && apb4.paddr[7:0] == `APB4_I2S_TXDATA) begin
      tx_push_valid_o = 1'b1;
      if (apb4.pstrb[0]) tx_push_data_o[7:0] = apb4.pwdata[7:0];
      if (apb4.pstrb[1]) tx_push_data_o[15:8] = apb4.pwdata[15:8];
      if (apb4.pstrb[2]) tx_push_data_o[23:16] = apb4.pwdata[23:16];
      if (apb4.pstrb[3]) tx_push_data_o[31:24] = apb4.pwdata[31:24];
    end
  end


  always_comb begin
    s_i2s_stat_d[0] = tx_full_i;
    s_i2s_stat_d[1] = rx_empty_i;
  end
  dffr #(
      .DATA_WIDTH(2)
  ) u_i2s_status_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_i2s_stat_d),
      .dat_o  (s_i2s_stat_q)
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
    rx_pop_valid_o = 1'b0;
    s_apb4_rdata_d = s_apb4_rdata_q;
    unique case (apb4.paddr[7:0])
      `APB4_I2S_MODE:        s_apb4_rdata_d = {31'd0, s_i2s_mode_q};
      `APB4_I2S_FORMAT:      s_apb4_rdata_d = {30'd0, s_i2s_format_q};
      `APB4_I2S_RXDATA: begin
        if (s_apb4_rd_hdshk) begin
          rx_pop_valid_o = 1'b1;
          if (!rx_empty_i) s_apb4_rdata_d = rx_pop_data_i;
          else s_apb4_rdata_d = '0;
        end
      end
      `APB4_I2S_STATUS:      s_apb4_rdata_d = {30'd0, s_i2s_stat_q};
      `APB4_I2S_STREAM_CTRL: s_apb4_rdata_d = {30'd0, s_i2s_stream_q};
      default:               s_apb4_rdata_d = s_apb4_rdata_q;
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

endmodule
