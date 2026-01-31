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

interface nv_i2s_if ();
  logic mclk_o;
  logic sclk_o;
  logic lrck_o;
  logic dacdat_o;
  logic adcdat_i;
  logic irq_o;

  modport dut(
      output mclk_o,
      output sclk_o,
      output lrck_o,
      output dacdat_o,
      input adcdat_i,
      output irq_o
  );
endinterface


module nmi_i2s (
    // verilog_format: off
    input logic   clk_i,
    input logic   rst_n_i,
    input logic   clk_aud_i,
    input logic   rst_aud_n_i,
    output logic  dma_tx_stall_o,
    output logic  dma_rx_stall_o,
    nmi_if.slave  nmi,
    nv_i2s_if.dut i2s
    // verilog_format: on
);

  logic       s_i2s_mode;
  logic [1:0] s_i2s_format;
  logic       s_i2s_recven;
  // tx fifo
  logic s_tx_push_valid, s_tx_full, s_tx_empty;
  logic s_tx_pop_valid, s_tx_pop_ready;
  logic [31:0] s_tx_push_data, s_tx_pop_data;
  logic [7:0] s_tx_elem_num;
  // rx fifo
  logic s_rx_push_valid, s_rx_full, s_rx_empty;
  logic s_rx_pop_valid, s_rx_pop_ready;
  logic [31:0] s_rx_push_data, s_rx_pop_data;
  logic [7:0] s_rx_elem_num;


  i2s_reg u_i2s_reg (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .nmi            (nmi),
      .mode_o         (s_i2s_mode),
      .format_o       (s_i2s_format),
      .recven_o       (s_i2s_recven),
      .tx_push_valid_o(s_tx_push_valid),
      .tx_push_data_o (s_tx_push_data),
      .tx_full_i      (s_tx_full),
      .tx_elem_num_i  (s_tx_elem_num),
      .rx_pop_valid_o (s_rx_pop_valid),
      .rx_pop_data_i  (s_rx_pop_data),
      .rx_empty_i     (s_rx_empty),
      .rx_elem_num_i  (s_rx_elem_num),
      .dma_tx_stall_o (dma_tx_stall_o),
      .dma_rx_stall_o (dma_rx_stall_o)
  );


  async_fifo #(
      .DATA_WIDTH (32),
      .DEPTH_POWER(7)
  ) u_tx_async_fifo (
      .wr_clk_i  (clk_i),
      .wr_rst_n_i(rst_n_i),
      .wr_en_i   (s_tx_push_valid),
      .wr_data_i (s_tx_push_data),
      .wr_full_o (s_tx_full),
      .rd_clk_i  (clk_aud_i),
      .rd_rst_n_i(rst_aud_n_i),
      .rd_en_i   (s_tx_pop_valid),
      .rd_data_o (s_tx_pop_data),
      .rd_empty_o(s_tx_empty),
      .elem_num_o(s_tx_elem_num)
  );


  async_fifo #(
      .DATA_WIDTH (32),
      .DEPTH_POWER(7)
  ) u_rx_async_fifo (
      .wr_clk_i  (clk_aud_i),
      .wr_rst_n_i(rst_aud_n_i),
      .wr_en_i   (s_rx_push_valid & s_i2s_recven),
      .wr_data_i (s_rx_push_data),
      .wr_full_o (s_rx_full),
      .rd_clk_i  (clk_i),
      .rd_rst_n_i(rst_n_i),
      .rd_en_i   (s_rx_pop_valid),
      .rd_data_o (s_rx_pop_data),
      .rd_empty_o(s_rx_empty),
      .elem_num_o(s_rx_elem_num)
  );


  i2s_core u_i2s_core (
      .clk_i     (clk_aud_i),
      .rst_n_i   (rst_aud_n_i),
      .mode_i    (s_i2s_mode),
      .format_i  (s_i2s_format),
      .tx_valid_o(s_tx_pop_valid),
      .tx_data_i (s_tx_pop_data),
      .tx_empty_i(s_tx_empty),
      .rx_valid_o(s_rx_push_valid),
      .rx_data_o (s_rx_push_data),
      .rx_full_i (s_rx_full),
      .i2s       (i2s)
  );
endmodule
