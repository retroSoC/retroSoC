// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

// One retained address and terminal response per direction. Blocking affects
// only upstream acceptance; already accepted addresses remain VALID downstream
// and write data/responses drain. Unaccepted requests never enter idle accounting.
module tiny_axi4_admission (
    input  logic          clk_i,
    input  logic          rst_n_i,
    input  logic          block_i,
    output logic          idle_o,
           axi4_if.slave  source,
           axi4_if.master sink
);
  typedef struct packed {
    logic [0:0]  id;
    logic [31:0] addr;
    logic [7:0]  len;
    logic [2:0]  size;
    logic [1:0]  burst;
    logic [0:0]  lock;
    logic [3:0]  cache;
    logic [2:0]  prot;
    logic [3:0]  qos;
    logic [3:0]  region;
    logic [0:0]  user;
  } address_t;
  address_t s_aw_d, s_aw_q, s_ar_d, s_ar_q;
  logic [1:0] s_pending_d, s_pending_q, s_sent_d, s_sent_q;
  assign source.awready = rst_n_i && !block_i && !s_pending_q[0];
  assign source.arready = rst_n_i && !block_i && !s_pending_q[1];
  assign sink.awvalid = s_pending_q[0] && !s_sent_q[0];
  assign sink.arvalid = s_pending_q[1] && !s_sent_q[1];
  assign sink.awid = s_aw_q.id;
  assign sink.awaddr = s_aw_q.addr;
  assign sink.awlen = s_aw_q.len;
  assign sink.awsize = s_aw_q.size;
  assign sink.awburst = s_aw_q.burst;
  assign sink.awlock = s_aw_q.lock;
  assign sink.awcache = s_aw_q.cache;
  assign sink.awprot = s_aw_q.prot;
  assign sink.awqos = s_aw_q.qos;
  assign sink.awregion = s_aw_q.region;
  assign sink.awuser = s_aw_q.user;
  assign sink.arid = s_ar_q.id;
  assign sink.araddr = s_ar_q.addr;
  assign sink.arlen = s_ar_q.len;
  assign sink.arsize = s_ar_q.size;
  assign sink.arburst = s_ar_q.burst;
  assign sink.arlock = s_ar_q.lock;
  assign sink.arcache = s_ar_q.cache;
  assign sink.arprot = s_ar_q.prot;
  assign sink.arqos = s_ar_q.qos;
  assign sink.arregion = s_ar_q.region;
  assign sink.aruser = s_ar_q.user;
  assign sink.wvalid = source.wvalid && s_pending_q[0] &&
      (s_sent_q[0] || (sink.awvalid && sink.awready));
  assign source.wready = sink.wready && s_pending_q[0] &&
      (s_sent_q[0] || (sink.awvalid && sink.awready));
  assign sink.wdata = source.wdata;
  assign sink.wstrb = source.wstrb;
  assign sink.wlast = source.wlast;
  assign sink.wuser = source.wuser;
  assign sink.bready = source.bready;
  assign sink.rready = source.rready;
  assign source.bid = sink.bid;
  assign source.bresp = sink.bresp;
  assign source.buser = sink.buser;
  assign source.bvalid = sink.bvalid;
  assign source.rid = sink.rid;
  assign source.rdata = sink.rdata;
  assign source.rresp = sink.rresp;
  assign source.rlast = sink.rlast;
  assign source.ruser = sink.ruser;
  assign source.rvalid = sink.rvalid;
  assign idle_o = s_pending_q == 0;
  always_comb begin
    s_aw_d      = s_aw_q;
    s_ar_d      = s_ar_q;
    s_pending_d = s_pending_q;
    s_sent_d    = s_sent_q;
    if (source.bvalid && source.bready) begin
      s_pending_d[0] = 1'b0;
      s_sent_d[0]    = 1'b0;
    end
    if (source.rvalid && source.rready && source.rlast) begin
      s_pending_d[1] = 1'b0;
      s_sent_d[1]    = 1'b0;
    end
    if (sink.awvalid && sink.awready) s_sent_d[0] = 1'b1;
    if (sink.arvalid && sink.arready) s_sent_d[1] = 1'b1;
    if (source.awvalid && source.awready) begin
      s_pending_d[0] = 1'b1;
      s_aw_d.id      = source.awid;
      s_aw_d.addr    = source.awaddr;
      s_aw_d.len     = source.awlen;
      s_aw_d.size    = source.awsize;
      s_aw_d.burst   = source.awburst;
      s_aw_d.lock    = source.awlock;
      s_aw_d.cache   = source.awcache;
      s_aw_d.prot    = source.awprot;
      s_aw_d.qos     = source.awqos;
      s_aw_d.region  = source.awregion;
      s_aw_d.user    = source.awuser;
    end
    if (source.arvalid && source.arready) begin
      s_pending_d[1] = 1'b1;
      s_ar_d.id      = source.arid;
      s_ar_d.addr    = source.araddr;
      s_ar_d.len     = source.arlen;
      s_ar_d.size    = source.arsize;
      s_ar_d.burst   = source.arburst;
      s_ar_d.lock    = source.arlock;
      s_ar_d.cache   = source.arcache;
      s_ar_d.prot    = source.arprot;
      s_ar_d.qos     = source.arqos;
      s_ar_d.region  = source.arregion;
      s_ar_d.user    = source.aruser;
    end
  end
  dffr #(
      .DATA_WIDTH($bits(address_t))
  ) u_aw (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_aw_d),
      .dat_o  (s_aw_q)
  );
  dffr #(
      .DATA_WIDTH($bits(address_t))
  ) u_ar (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ar_d),
      .dat_o  (s_ar_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_pending (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pending_d),
      .dat_o  (s_pending_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_sent (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sent_d),
      .dat_o  (s_sent_q)
  );
endmodule
