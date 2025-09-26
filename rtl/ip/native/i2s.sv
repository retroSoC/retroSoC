// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef NATV_I2S_DEF_SV
`define NATV_I2S_DEF_SV

// verilog_format: off
`define NATV_I2S_MODE   8'h00
`define NATV_I2S_TXDATA 8'h04
`define NATV_I2S_RXDATA 8'h08
`define NATV_I2S_STATUS 8'h0C
// verilog_format: on

interface nv_i2s_if ();
  logic mclk_o;
  logic sclk_o;
  logic lrck_o;
  logic dacdat_o;
  logic adcdat_i;

  modport dut(output mclk_o, output sclk_o, output lrck_o, output dacdat_o, input adcdat_i);

endinterface

`endif

module nmi_i2s (
    // verilog_format: off
    input logic   clk_i,
    input logic   rst_n_i,
    input logic   clk_aud_i  ,
    input logic   rst_aud_n_i,
    nmi_if.slave  nmi,
    nv_i2s_if.dut i2s
    // verilog_format: on
);

  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;

  logic s_i2s_mode_en;
  logic s_i2s_mode_d, s_i2s_mode_q;
  logic [1:0] s_i2s_status_d, s_i2s_status_q;
  // tx fifo
  logic s_tx_push_valid, s_tx_full, s_tx_empty;
  logic s_tx_pop_valid, s_tx_pop_ready;
  logic [15:0] s_tx_push_data, s_tx_pop_data;
  // rx fifo
  logic s_rx_push_valid, s_rx_full, s_rx_empty;
  logic s_rx_pop_valid, s_rx_pop_ready;
  logic [15:0] s_rx_push_data, s_rx_pop_data;

  assign s_nmi_wr_hdshk = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready      = s_nmi_ready_q;
  assign nmi.rdata      = s_nmi_rdata_q;


  assign s_i2s_mode_en  = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_I2S_MODE;
  assign s_i2s_mode_d   = nmi.wdata[0];
  dffer #(1) u_i2s_mode_dffer (
      clk_i,
      rst_n_i,
      s_i2s_mode_en,
      s_i2s_mode_d,
      s_i2s_mode_q
  );

  always_comb begin
    s_tx_push_valid = 1'b0;
    s_tx_push_data  = '0;
    if (s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_I2S_TXDATA) begin
      s_tx_push_valid = 1'b1;
      if (nmi.wstrb[0]) s_tx_push_data[7:0] = nmi.wdata[7:0];
      if (nmi.wstrb[1]) s_tx_push_data[15:8] = nmi.wdata[15:8];
    end
  end

  // [0] wr fifo full, [1] rd fifo empty
  always_comb begin
    s_i2s_status_d[0] = s_tx_full;
    s_i2s_status_d[1] = s_rx_empty;
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
    s_rx_pop_valid = 1'b0;
    s_nmi_rdata_d  = s_nmi_rdata_q;
    unique case (nmi.addr[7:0])
      `NATV_I2S_MODE:   s_nmi_rdata_d = {31'd0, s_i2s_mode_q};
      `NATV_I2S_RXDATA: begin
        s_rx_pop_valid = 1'b1;
        if (!s_rx_empty) s_nmi_rdata_d = {16'd0, s_rx_pop_data};
        else s_nmi_rdata_d = '0;
      end
      `NATV_I2S_STATUS: s_nmi_rdata_d = {30'd0, s_i2s_status_q};
      default:          s_nmi_rdata_d = s_nmi_rdata_q;
    endcase
  end
  dffer #(32) u_nmi_rdata_dffer (
      clk_i,
      rst_n_i,
      s_nmi_rdata_en,
      s_nmi_rdata_d,
      s_nmi_rdata_q
  );


  async_fifo #(
      .DATA_WIDTH (16),
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
      .rd_empty_o(s_tx_empty)
  );


  async_fifo #(
      .DATA_WIDTH (16),
      .DEPTH_POWER(7)
  ) u_rx_async_fifo (
      .wr_clk_i  (clk_aud_i),
      .wr_rst_n_i(rst_aud_n_i),
      .wr_en_i   (s_rx_push_valid),
      .wr_data_i (s_rx_push_data),
      .wr_full_o (s_rx_full),
      .rd_clk_i  (clk_i),
      .rd_rst_n_i(rst_n_i),
      .rd_en_i   (s_rx_pop_valid),
      .rd_data_o (s_rx_pop_data),
      .rd_empty_o(s_rx_empty)
  );

  i2s_core u_i2s_core (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .mode_i    (s_i2s_mode_q),
      .tx_valid_o(s_tx_pop_valid),
      .tx_data_i (s_tx_pop_data),
      .tx_empty_i(s_tx_empty),
      .rx_valid_o(s_rx_push_valid),
      .rx_data_o (s_rx_push_data),
      .rx_full_i (s_rx_full),
      .i2s       (i2s)
  );
endmodule
