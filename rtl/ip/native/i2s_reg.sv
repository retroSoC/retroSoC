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
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    nmi_if.slave        nmi,
    output logic        mode_o,
    output logic [ 1:0] format_o,
    output logic        recven_o,
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

  // nmi
  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;
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
  logic [1:0] s_i2s_status_d, s_i2s_status_q;
  // common
  logic s_tx_fifo_stall_d, s_tx_fifo_stall_q;
  logic s_rx_fifo_stall_d, s_rx_fifo_stall_q;


  // nmi
  assign s_nmi_wr_hdshk = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready      = s_nmi_ready_q;
  assign nmi.rdata      = s_nmi_rdata_q;
  // reg
  assign mode_o         = s_i2s_mode_q;
  assign format_o       = s_i2s_format_q;
  assign recven_o       = s_i2s_recven_q;
  // dma
  assign dma_tx_stall_o = s_tx_fifo_stall_q;
  assign dma_rx_stall_o = s_rx_fifo_stall_q;


  assign s_i2s_mode_en  = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_I2S_MODE;
  assign s_i2s_mode_d   = nmi.wdata[0];
  dffer #(1) u_i2s_mode_dffer (
      clk_i,
      rst_n_i,
      s_i2s_mode_en,
      s_i2s_mode_d,
      s_i2s_mode_q
  );


  assign s_i2s_format_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_I2S_FORMAT;
  assign s_i2s_format_d  = nmi.wdata[1:0];
  dffer #(2) u_i2s_format_dffer (
      clk_i,
      rst_n_i,
      s_i2s_format_en,
      s_i2s_format_d,
      s_i2s_format_q
  );


  assign s_i2s_upbound_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_I2S_UPBOUND;
  assign s_i2s_upbound_d  = nmi.wdata[7:0];
  dfferh #(8) u_i2s_upbound_dfferh (
      clk_i,
      rst_n_i,
      s_i2s_upbound_en,
      s_i2s_upbound_d,
      s_i2s_upbound_q
  );


  assign s_i2s_lowbound_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_I2S_LOWBOUND;
  assign s_i2s_lowbound_d  = nmi.wdata[7:0];
  dffer #(8) u_i2s_lowbound_dffer (
      clk_i,
      rst_n_i,
      s_i2s_lowbound_en,
      s_i2s_lowbound_d,
      s_i2s_lowbound_q
  );


  assign s_i2s_recven_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_I2S_RECVEN;
  assign s_i2s_recven_d  = nmi.wdata[0];
  dffer #(1) u_i2s_recven_dffer (
      clk_i,
      rst_n_i,
      s_i2s_recven_en,
      s_i2s_recven_d,
      s_i2s_recven_q
  );


  always_comb begin
    s_tx_fifo_stall_d = s_tx_fifo_stall_q;
    if (~s_tx_fifo_stall_q && tx_elem_num_i > s_i2s_upbound_q) begin
      s_tx_fifo_stall_d = 1'b1;
    end else if (s_tx_fifo_stall_q && tx_elem_num_i < s_i2s_lowbound_q) begin
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
    if (~s_rx_fifo_stall_q && rx_elem_num_i < s_i2s_lowbound_q) begin
      s_rx_fifo_stall_d = 1'b1;
    end else if (s_rx_fifo_stall_q && rx_elem_num_i > s_i2s_upbound_q) begin
      s_rx_fifo_stall_d = 1'b0;
    end
  end
  dffr #(1) u_rx_fifo_stall_dffr (
      clk_i,
      rst_n_i,
      s_rx_fifo_stall_d,
      s_rx_fifo_stall_q
  );


  // TODO: need to handle when tx fifo is full(DMA is fine)
  always_comb begin
    tx_push_valid_o = 1'b0;
    tx_push_data_o  = '0;
    if (s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_I2S_TXDATA) begin
      tx_push_valid_o = 1'b1;
      if (nmi.wstrb[0]) tx_push_data_o[7:0] = nmi.wdata[7:0];
      if (nmi.wstrb[1]) tx_push_data_o[15:8] = nmi.wdata[15:8];
      if (nmi.wstrb[2]) tx_push_data_o[23:16] = nmi.wdata[23:16];
      if (nmi.wstrb[3]) tx_push_data_o[31:24] = nmi.wdata[31:24];
    end
  end


  always_comb begin
    s_i2s_status_d[0] = tx_full_i;
    s_i2s_status_d[1] = rx_empty_i;
  end
  dffr #(2) u_i2s_status_dffr (
      clk_i,
      rst_n_i,
      s_i2s_status_d,
      s_i2s_status_q
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
    rx_pop_valid_o = 1'b0;
    s_nmi_rdata_d  = s_nmi_rdata_q;
    unique case (nmi.addr[7:0])
      `NMI_I2S_MODE:   s_nmi_rdata_d = {31'd0, s_i2s_mode_q};
      `NMI_I2S_FORMAT: s_nmi_rdata_d = {30'd0, s_i2s_format_q};
      `NMI_I2S_RXDATA: begin
        if (s_nmi_rd_hdshk) begin
          rx_pop_valid_o = 1'b1;
          if (!rx_empty_i) s_nmi_rdata_d = rx_pop_data_i;
          else s_nmi_rdata_d = '0;
        end
      end
      `NMI_I2S_STATUS: s_nmi_rdata_d = {30'd0, s_i2s_status_q};
      default:         s_nmi_rdata_d = s_nmi_rdata_q;
    endcase
  end
  dffer #(32) u_nmi_rdata_dffer (
      clk_i,
      rst_n_i,
      s_nmi_rdata_en,
      s_nmi_rdata_d,
      s_nmi_rdata_q
  );

endmodule
