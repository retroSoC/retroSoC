// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef NMI_DVP_DEF_SV
`define NMI_DVP_DEF_SV

`define NMI_DVP_RECVEN 8'h00
`define NMI_DVP_RXDATA 8'h04
`define NMI_DVP_STATUS 8'h08

`endif

interface dvp_if ();
  logic       pclk_i;
  logic       href_i;
  logic       vsync_i;
  logic [7:0] dat_i;

  modport dut(input pclk_i, input href_i, input vsync_i, input dat_i);
endinterface

module nmi_dvp (
    // verilog_format: off
    input logic  clk_i,
    input logic  rst_n_i,
    nmi_if.slave nmi,
    dvp_if.dut   dvp
    // verilog_format: on
);
  // nmi
  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;
  // register
  logic s_dvp_recven_en;
  logic s_dvp_recven_d, s_dvp_recven_q;
  logic s_dvp_status_d, s_dvp_status_q;
  // dvp clk
  logic s_dvp_pclk_buf;
  logic s_dvp_pclk_rst_n_sync;
  // rx fifo
  logic s_rx_push_valid, s_rx_full, s_rx_empty;
  logic s_rx_pop_valid, s_rx_pop_ready;
  logic [31:0] s_rx_push_data, s_rx_pop_data;
  logic [7:0] s_rx_elem_num;

  // nmi
  assign s_nmi_wr_hdshk  = nmi.valid && (~s_nmi_ready_q) && nmi.wstrb[0];
  assign s_nmi_rd_hdshk  = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready       = s_nmi_ready_q;
  assign nmi.rdata       = s_nmi_rdata_q;


  assign s_dvp_recven_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_DVP_RECVEN;
  assign s_dvp_recven_d  = nmi.wdata[0];
  dffer #(1) u_dvp_recven_dffer (
      clk_i,
      rst_n_i,
      s_dvp_recven_en,
      s_dvp_recven_d,
      s_dvp_recven_q
  );

  assign s_dvp_status_d = s_rx_empty;
  dffr #(1) u_dvp_status_dffr (
      clk_i,
      rst_n_i,
      s_dvp_status_d,
      s_dvp_status_q
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
      `NMI_DVP_RECVEN: s_nmi_rdata_d = {31'd0, s_dvp_recven_q};
      `NMI_DVP_RXDATA: begin
        if (s_nmi_rd_hdshk) begin
          s_rx_pop_valid = 1'b1;
          if (!s_rx_empty) s_nmi_rdata_d = s_rx_pop_data;
          else s_nmi_rdata_d = '0;
        end
      end
      `NMI_DVP_STATUS: s_nmi_rdata_d = {31'd0, s_dvp_status_q};
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


  // clk buffer
  tc_clk_buf u_dvp_pclk_clk_buf (
      .clk_i(dvp.pclk_i),
      .clk_o(s_dvp_pclk_buf)
  );

  rst_sync #(
      .STAGE(5)
  ) u_dvp_pclk_rst_sync (
      .clk_i  (s_dvp_pclk_buf),
      .rst_n_i(rst_n_i),
      .rst_n_o(s_dvp_pclk_rst_n_sync)
  );


  async_fifo #(
      .DATA_WIDTH (32),
      .DEPTH_POWER(7)
  ) u_rx_async_fifo (
      .wr_clk_i  (s_dvp_pclk_buf),
      .wr_rst_n_i(s_dvp_pclk_rst_n_sync),
      .wr_en_i   (s_rx_push_valid & s_dvp_recven_q),
      .wr_data_i (s_rx_push_data),
      .wr_full_o (s_rx_full),
      .rd_clk_i  (clk_i),
      .rd_rst_n_i(rst_n_i),
      .rd_en_i   (s_rx_pop_valid),
      .rd_data_o (s_rx_pop_data),
      .rd_empty_o(s_rx_empty),
      .elem_num_o(s_rx_elem_num)
  );


  dvp_core u_dvp_core (
      .clk_i      (s_dvp_pclk_buf),
      .rst_n_i    (s_dvp_pclk_rst_n_sync),
      .dvp_href_i (dvp.href_i),
      .dvp_vsync_i(dvp.vsync_i),
      .dvp_dat_i  (dvp.dat_i),
      .wr_en_o    (s_rx_push_valid),
      .rgb_dat_o  (s_rx_push_data)
  );
endmodule
