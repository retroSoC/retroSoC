// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module axi4_address_gate (
    input  logic          clk_i,
    input  logic          rst_n_i,
    input  logic          block_new_i,
           axi4_if.slave  source,
           axi4_if.master sink,
    output logic          idle_o
);
  logic s_write_pending_d;
  logic s_write_pending_q;
  logic s_read_pending_d;
  logic s_read_pending_q;
  logic s_aw_accept;
  logic s_b_accept;
  logic s_ar_accept;
  logic s_r_accept;

  assign sink.awid = source.awid;
  assign sink.awaddr = source.awaddr;
  assign sink.awlen = source.awlen;
  assign sink.awsize = source.awsize;
  assign sink.awburst = source.awburst;
  assign sink.awlock = source.awlock;
  assign sink.awcache = source.awcache;
  assign sink.awprot = source.awprot;
  assign sink.awqos = source.awqos;
  assign sink.awregion = source.awregion;
  assign sink.awuser = source.awuser;
  assign sink.awvalid = source.awvalid && !block_new_i && !s_write_pending_q;
  assign source.awready = sink.awready && !block_new_i && !s_write_pending_q;

  assign sink.wdata = source.wdata;
  assign sink.wstrb = source.wstrb;
  assign sink.wlast = source.wlast;
  assign sink.wuser = source.wuser;
  assign sink.wvalid = source.wvalid && (s_write_pending_q || s_aw_accept);
  assign source.wready = sink.wready && (s_write_pending_q || s_aw_accept);

  assign source.bid = sink.bid;
  assign source.bresp = sink.bresp;
  assign source.buser = sink.buser;
  assign source.bvalid = sink.bvalid;
  assign sink.bready = source.bready;

  assign sink.arid = source.arid;
  assign sink.araddr = source.araddr;
  assign sink.arlen = source.arlen;
  assign sink.arsize = source.arsize;
  assign sink.arburst = source.arburst;
  assign sink.arlock = source.arlock;
  assign sink.arcache = source.arcache;
  assign sink.arprot = source.arprot;
  assign sink.arqos = source.arqos;
  assign sink.arregion = source.arregion;
  assign sink.aruser = source.aruser;
  assign sink.arvalid = source.arvalid && !block_new_i && !s_read_pending_q;
  assign source.arready = sink.arready && !block_new_i && !s_read_pending_q;

  assign source.rid = sink.rid;
  assign source.rdata = sink.rdata;
  assign source.rresp = sink.rresp;
  assign source.rlast = sink.rlast;
  assign source.ruser = sink.ruser;
  assign source.rvalid = sink.rvalid;
  assign sink.rready = source.rready;

  assign s_aw_accept = source.awvalid && source.awready;
  assign s_b_accept = source.bvalid && source.bready;
  assign s_ar_accept = source.arvalid && source.arready;
  assign s_r_accept = source.rvalid && source.rready && source.rlast;
  assign idle_o = !s_write_pending_q && !s_read_pending_q && !source.awvalid && !source.arvalid;

  always_comb begin
    s_write_pending_d = s_write_pending_q;
    s_read_pending_d  = s_read_pending_q;
    if (s_b_accept) s_write_pending_d = 1'b0;
    if (s_aw_accept) s_write_pending_d = 1'b1;
    if (s_r_accept) s_read_pending_d = 1'b0;
    if (s_ar_accept) s_read_pending_d = 1'b1;
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_write_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_pending_d),
      .dat_o  (s_write_pending_q)
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
