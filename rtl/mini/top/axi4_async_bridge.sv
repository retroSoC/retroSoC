// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module axi4_async_bridge #(
    parameter int unsigned AddrWidth = 32,
    parameter int unsigned DataWidth = 32,
    parameter int unsigned IdWidth   = 1,
    parameter int unsigned UserWidth = 1,
    parameter int unsigned FifoDepth = 4
) (
    // verilog_format: off -- preserve the source/destination clock boundary columns
    input  logic       src_clk_i,
    input  logic       src_rst_n_i,
    input  logic       dst_clk_i,
    input  logic       dst_rst_n_i,
    axi4_if.slave      src_axi4,
    axi4_if.master     dst_axi4
    // verilog_format: on
);
  localparam int unsigned StrbWidth = DataWidth / 8;
  localparam int unsigned AwWidth = IdWidth + AddrWidth + 8 + 3 + 2 + 1 + 4 + 3 + 4 + 4 + UserWidth;
  localparam int unsigned WWidth = DataWidth + StrbWidth + 1 + UserWidth;
  localparam int unsigned BWidth = IdWidth + 2 + UserWidth;
  localparam int unsigned ArWidth = AwWidth;
  localparam int unsigned RWidth = IdWidth + DataWidth + 2 + 1 + UserWidth;

  logic [AwWidth-1:0] s_aw_src_data;
  logic [AwWidth-1:0] s_aw_dst_data;
  logic [ WWidth-1:0] s_w_src_data;
  logic [ WWidth-1:0] s_w_dst_data;
  logic [ BWidth-1:0] s_b_dst_data;
  logic [ BWidth-1:0] s_b_src_data;
  logic [ArWidth-1:0] s_ar_src_data;
  logic [ArWidth-1:0] s_ar_dst_data;
  logic [ RWidth-1:0] s_r_dst_data;
  logic [ RWidth-1:0] s_r_src_data;

  assign s_aw_src_data = {
    src_axi4.awid,
    src_axi4.awaddr,
    src_axi4.awlen,
    src_axi4.awsize,
    src_axi4.awburst,
    src_axi4.awlock,
    src_axi4.awcache,
    src_axi4.awprot,
    src_axi4.awqos,
    src_axi4.awregion,
    src_axi4.awuser
  };
  assign {
    dst_axi4.awid,
    dst_axi4.awaddr,
    dst_axi4.awlen,
    dst_axi4.awsize,
    dst_axi4.awburst,
    dst_axi4.awlock,
    dst_axi4.awcache,
    dst_axi4.awprot,
    dst_axi4.awqos,
    dst_axi4.awregion,
    dst_axi4.awuser
  } = s_aw_dst_data;

  cdc_fifo #(
      .DATA_WIDTH  (AwWidth),
      .BUFFER_DEPTH(FifoDepth)
  ) u_aw_fifo (
      .src_clk_i  (src_clk_i),
      .src_rst_n_i(src_rst_n_i),
      .src_data_i (s_aw_src_data),
      .src_valid_i(src_axi4.awvalid),
      .src_ready_o(src_axi4.awready),
      .dst_clk_i  (dst_clk_i),
      .dst_rst_n_i(dst_rst_n_i),
      .dst_data_o (s_aw_dst_data),
      .dst_valid_o(dst_axi4.awvalid),
      .dst_ready_i(dst_axi4.awready)
  );

  assign s_w_src_data = {src_axi4.wdata, src_axi4.wstrb, src_axi4.wlast, src_axi4.wuser};
  assign {dst_axi4.wdata, dst_axi4.wstrb, dst_axi4.wlast, dst_axi4.wuser} = s_w_dst_data;

  cdc_fifo #(
      .DATA_WIDTH  (WWidth),
      .BUFFER_DEPTH(FifoDepth)
  ) u_w_fifo (
      .src_clk_i  (src_clk_i),
      .src_rst_n_i(src_rst_n_i),
      .src_data_i (s_w_src_data),
      .src_valid_i(src_axi4.wvalid),
      .src_ready_o(src_axi4.wready),
      .dst_clk_i  (dst_clk_i),
      .dst_rst_n_i(dst_rst_n_i),
      .dst_data_o (s_w_dst_data),
      .dst_valid_o(dst_axi4.wvalid),
      .dst_ready_i(dst_axi4.wready)
  );

  assign s_b_dst_data = {dst_axi4.bid, dst_axi4.bresp, dst_axi4.buser};
  assign {src_axi4.bid, src_axi4.bresp, src_axi4.buser} = s_b_src_data;

  cdc_fifo #(
      .DATA_WIDTH  (BWidth),
      .BUFFER_DEPTH(FifoDepth)
  ) u_b_fifo (
      .src_clk_i  (dst_clk_i),
      .src_rst_n_i(dst_rst_n_i),
      .src_data_i (s_b_dst_data),
      .src_valid_i(dst_axi4.bvalid),
      .src_ready_o(dst_axi4.bready),
      .dst_clk_i  (src_clk_i),
      .dst_rst_n_i(src_rst_n_i),
      .dst_data_o (s_b_src_data),
      .dst_valid_o(src_axi4.bvalid),
      .dst_ready_i(src_axi4.bready)
  );

  assign s_ar_src_data = {
    src_axi4.arid,
    src_axi4.araddr,
    src_axi4.arlen,
    src_axi4.arsize,
    src_axi4.arburst,
    src_axi4.arlock,
    src_axi4.arcache,
    src_axi4.arprot,
    src_axi4.arqos,
    src_axi4.arregion,
    src_axi4.aruser
  };
  assign {
    dst_axi4.arid,
    dst_axi4.araddr,
    dst_axi4.arlen,
    dst_axi4.arsize,
    dst_axi4.arburst,
    dst_axi4.arlock,
    dst_axi4.arcache,
    dst_axi4.arprot,
    dst_axi4.arqos,
    dst_axi4.arregion,
    dst_axi4.aruser
  } = s_ar_dst_data;

  cdc_fifo #(
      .DATA_WIDTH  (ArWidth),
      .BUFFER_DEPTH(FifoDepth)
  ) u_ar_fifo (
      .src_clk_i  (src_clk_i),
      .src_rst_n_i(src_rst_n_i),
      .src_data_i (s_ar_src_data),
      .src_valid_i(src_axi4.arvalid),
      .src_ready_o(src_axi4.arready),
      .dst_clk_i  (dst_clk_i),
      .dst_rst_n_i(dst_rst_n_i),
      .dst_data_o (s_ar_dst_data),
      .dst_valid_o(dst_axi4.arvalid),
      .dst_ready_i(dst_axi4.arready)
  );

  assign s_r_dst_data = {
    dst_axi4.rid, dst_axi4.rdata, dst_axi4.rresp, dst_axi4.rlast, dst_axi4.ruser
  };
  assign {src_axi4.rid, src_axi4.rdata, src_axi4.rresp, src_axi4.rlast,
          src_axi4.ruser} = s_r_src_data;

  cdc_fifo #(
      .DATA_WIDTH  (RWidth),
      .BUFFER_DEPTH(FifoDepth)
  ) u_r_fifo (
      .src_clk_i  (dst_clk_i),
      .src_rst_n_i(dst_rst_n_i),
      .src_data_i (s_r_dst_data),
      .src_valid_i(dst_axi4.rvalid),
      .src_ready_o(dst_axi4.rready),
      .dst_clk_i  (src_clk_i),
      .dst_rst_n_i(src_rst_n_i),
      .dst_data_o (s_r_src_data),
      .dst_valid_o(src_axi4.rvalid),
      .dst_ready_i(src_axi4.rready)
  );

`ifndef SYNTHESIS
  initial begin
    if ((AddrWidth < 1) || (DataWidth < 8) || ((DataWidth % 8) != 0) ||
        (IdWidth < 1) || (UserWidth < 1) || (FifoDepth < 2) ||
        ((FifoDepth & (FifoDepth - 1)) != 0)) begin
      $fatal(1, "axi4_async_bridge: invalid interface or FIFO parameters");
    end
  end
`endif
endmodule
