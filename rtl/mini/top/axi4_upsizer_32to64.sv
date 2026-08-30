// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module axi4_upsizer_32to64 #(
    parameter logic [2:0] MasterIndex = 3'd0
) (
    input logic          clk_i,
    input logic          rst_n_i,
          axi4_if.slave  narrow,
          axi4_if.master wide
);
  logic [31:0] s_write_addr_d;
  logic [31:0] s_write_addr_q;
  logic [31:0] s_read_addr_d;
  logic [31:0] s_read_addr_q;
  logic        s_write_pending_d;
  logic        s_write_pending_q;
  logic        s_read_pending_d;
  logic        s_read_pending_q;
  logic [31:0] s_write_next_addr;
  logic [31:0] s_read_next_addr;
  logic        s_aw_accept;
  logic        s_w_accept;
  logic        s_b_accept;
  logic        s_ar_accept;
  logic        s_r_accept;

  axi4_addr_gen #(
      .ADDR_WIDTH(32)
  ) u_write_addr_gen (
      .alen_i  (narrow.awlen),
      .asize_i (narrow.awsize),
      .aburst_i(narrow.awburst),
      .addr_i  (s_write_addr_q),
      .addr_o  (s_write_next_addr)
  );
  axi4_addr_gen #(
      .ADDR_WIDTH(32)
  ) u_read_addr_gen (
      .alen_i  (narrow.arlen),
      .asize_i (narrow.arsize),
      .aburst_i(narrow.arburst),
      .addr_i  (s_read_addr_q),
      .addr_o  (s_read_next_addr)
  );

  assign wide.awid      = {MasterIndex, 2'd0, narrow.awid};
  assign wide.awaddr    = narrow.awaddr;
  assign wide.awlen     = narrow.awlen;
  assign wide.awsize    = narrow.awsize;
  assign wide.awburst   = narrow.awburst;
  assign wide.awlock    = narrow.awlock;
  assign wide.awcache   = narrow.awcache;
  assign wide.awprot    = narrow.awprot;
  assign wide.awqos     = narrow.awqos;
  assign wide.awregion  = narrow.awregion;
  assign wide.awuser    = narrow.awuser;
  assign wide.awvalid   = narrow.awvalid && !s_write_pending_q;
  assign narrow.awready = wide.awready && !s_write_pending_q;

  assign wide.wdata     = s_write_addr_q[2] ? {narrow.wdata, 32'd0} : {32'd0, narrow.wdata};
  assign wide.wstrb     = s_write_addr_q[2] ? {narrow.wstrb, 4'd0} : {4'd0, narrow.wstrb};
  assign wide.wlast     = narrow.wlast;
  assign wide.wuser     = narrow.wuser;
  assign wide.wvalid    = narrow.wvalid && s_write_pending_q;
  assign narrow.wready  = wide.wready && s_write_pending_q;
  assign narrow.bid     = wide.bid[0];
  assign narrow.bresp   = wide.bresp;
  assign narrow.buser   = wide.buser;
  assign narrow.bvalid  = wide.bvalid;
  assign wide.bready    = narrow.bready;

  assign wide.arid      = {MasterIndex, 2'd0, narrow.arid};
  assign wide.araddr    = narrow.araddr;
  assign wide.arlen     = narrow.arlen;
  assign wide.arsize    = narrow.arsize;
  assign wide.arburst   = narrow.arburst;
  assign wide.arlock    = narrow.arlock;
  assign wide.arcache   = narrow.arcache;
  assign wide.arprot    = narrow.arprot;
  assign wide.arqos     = narrow.arqos;
  assign wide.arregion  = narrow.arregion;
  assign wide.aruser    = narrow.aruser;
  assign wide.arvalid   = narrow.arvalid && !s_read_pending_q;
  assign narrow.arready = wide.arready && !s_read_pending_q;
  assign narrow.rid     = wide.rid[0];
  assign narrow.rdata   = s_read_addr_q[2] ? wide.rdata[63:32] : wide.rdata[31:0];
  assign narrow.rresp   = wide.rresp;
  assign narrow.rlast   = wide.rlast;
  assign narrow.ruser   = wide.ruser;
  assign narrow.rvalid  = wide.rvalid;
  assign wide.rready    = narrow.rready;

  assign s_aw_accept    = narrow.awvalid && narrow.awready;
  assign s_w_accept     = narrow.wvalid && narrow.wready;
  assign s_b_accept     = narrow.bvalid && narrow.bready;
  assign s_ar_accept    = narrow.arvalid && narrow.arready;
  assign s_r_accept     = narrow.rvalid && narrow.rready;

  always_comb begin
    s_write_addr_d    = s_write_addr_q;
    s_write_pending_d = s_write_pending_q;
    if (s_aw_accept) begin
      s_write_addr_d    = narrow.awaddr;
      s_write_pending_d = 1'b1;
    end else if (s_w_accept && !narrow.wlast) begin
      s_write_addr_d = s_write_next_addr;
    end
    if (s_b_accept) s_write_pending_d = 1'b0;
  end

  always_comb begin
    s_read_addr_d    = s_read_addr_q;
    s_read_pending_d = s_read_pending_q;
    if (s_ar_accept) begin
      s_read_addr_d    = narrow.araddr;
      s_read_pending_d = 1'b1;
    end else if (s_r_accept && !narrow.rlast) begin
      s_read_addr_d = s_read_next_addr;
    end
    if (s_r_accept && narrow.rlast) s_read_pending_d = 1'b0;
  end

  dffr #(
      .DATA_WIDTH(32)
  ) u_write_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_addr_d),
      .dat_o  (s_write_addr_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_write_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_pending_d),
      .dat_o  (s_write_pending_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_read_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_addr_d),
      .dat_o  (s_read_addr_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_read_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_pending_d),
      .dat_o  (s_read_pending_q)
  );
endmodule
