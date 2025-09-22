// Copyright (c) 2023-2025 Miao Yuchi <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module nmi2nmi (
    // mstr
    input  logic        mstr_clk_i,
    input  logic        mstr_rst_n_i,
    input  logic        mstr_valid_i,
    input  logic [31:0] mstr_addr_i,
    input  logic [31:0] mstr_wdata_i,
    input  logic [ 3:0] mstr_wstrb_i,
    output logic [31:0] mstr_rdata_o,
    output logic        mstr_ready_o,
    // slvr
    input  logic        slvr_clk_i,
    input  logic        slvr_rst_n_i,
    output logic        slvr_valid_o,
    output logic [31:0] slvr_addr_o,
    output logic [31:0] slvr_wdata_o,
    output logic [ 3:0] slvr_wstrb_o,
    input  logic [31:0] slvr_rdata_i,
    input  logic        slvr_ready_i
);

  logic s_mstr_valid_re;
  logic s_req_empty;
  logic s_req_empty_d, s_req_empty_q;
  logic [68:0] s_req_rdata;
  logic [68:0] s_req_rdata_d, s_req_rdata_q;

  logic s_resp_empty;
  logic s_resp_empty_d, s_resp_empty_q;
  logic [32:0] s_resp_rdata;


  assign mstr_ready_o = ~s_resp_empty_q ? s_resp_rdata[32] : '0;
  assign mstr_rdata_o = ~s_resp_empty_q ? s_resp_rdata[31:0] : '0;
  assign slvr_valid_o = ~s_req_empty_q ? s_req_rdata_q[68] : '0;
  assign slvr_addr_o  = ~s_req_empty_q ? s_req_rdata_q[67:36] : '0;
  assign slvr_wdata_o = ~s_req_empty_q ? s_req_rdata_q[35:4] : '0;
  assign slvr_wstrb_o = ~s_req_empty_q ? s_req_rdata_q[3:0] : '0;

  edge_det_sync_re #(1) u_mstr_valid_det_sync_re (
      mstr_clk_i,
      mstr_rst_n_i,
      mstr_valid_i,
      s_mstr_valid_re
  );

  assign s_req_rdata_d = s_req_rdata;
  dffr #(69) u_req_rdata_dffr (
      slvr_clk_i,
      slvr_rst_n_i,
      s_req_rdata_d,
      s_req_rdata_q
  );

  assign s_req_empty_d = s_req_empty;
  dffr #(1) u_req_empty_dffr (
      slvr_clk_i,
      slvr_rst_n_i,
      s_req_empty_d,
      s_req_empty_q
  );

  assign s_resp_empty_d = s_resp_empty;
  dffr #(1) u_resp_empty_dffr (
      mstr_clk_i,
      mstr_rst_n_i,
      s_resp_empty_d,
      s_resp_empty_q
  );

  // req frame: valid[1] addr[32], wdata[32], wstrb[4]
  async_fifo #(
      .DATA_WIDTH (1 + 32 + 32 + 4),
      .DEPTH_POWER(4)
  ) u_req_async_fifo (
      .wr_clk_i  (mstr_clk_i),
      .wr_rst_n_i(mstr_rst_n_i),
      .wr_en_i   (s_mstr_valid_re),
      .wr_data_i ({mstr_valid_i, mstr_addr_i, mstr_wdata_i, mstr_wstrb_i}),
      .full_o    (),
      .rd_clk_i  (slvr_clk_i),
      .rd_rst_n_i(slvr_rst_n_i),
      .rd_en_i   (1'b1),
      .rd_data_o (s_req_rdata),
      .empty_o   (s_req_empty)
  );

  // resp frame: ready[1] data[32]
  async_fifo #(
      .DATA_WIDTH (33),
      .DEPTH_POWER(4)
  ) u_resp_async_fifo (
      .wr_clk_i  (slvr_clk_i),
      .wr_rst_n_i(slvr_rst_n_i),
      .wr_en_i   (slvr_ready_i),
      .wr_data_i ({slvr_ready_i, slvr_rdata_i}),
      .full_o    (),
      .rd_clk_i  (mstr_clk_i),
      .rd_rst_n_i(mstr_rst_n_i),
      .rd_en_i   (1'b1),
      .rd_data_o (s_resp_rdata),
      .empty_o   (s_resp_empty)
  );

endmodule
