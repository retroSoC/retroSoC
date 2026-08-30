// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module axi4_id_prefix #(
    parameter logic [2:0] MasterIndex = 3'd0
) (
    axi4_if.slave  source,
    axi4_if.master sink
);
  assign sink.awid      = {MasterIndex, source.awid};
  assign sink.awaddr    = source.awaddr;
  assign sink.awlen     = source.awlen;
  assign sink.awsize    = source.awsize;
  assign sink.awburst   = source.awburst;
  assign sink.awlock    = source.awlock;
  assign sink.awcache   = source.awcache;
  assign sink.awprot    = source.awprot;
  assign sink.awqos     = source.awqos;
  assign sink.awregion  = source.awregion;
  assign sink.awuser    = source.awuser;
  assign sink.awvalid   = source.awvalid;
  assign source.awready = sink.awready;
  assign sink.wdata     = source.wdata;
  assign sink.wstrb     = source.wstrb;
  assign sink.wlast     = source.wlast;
  assign sink.wuser     = source.wuser;
  assign sink.wvalid    = source.wvalid;
  assign source.wready  = sink.wready;
  assign source.bid     = sink.bid[2:0];
  assign source.bresp   = sink.bresp;
  assign source.buser   = sink.buser;
  assign source.bvalid  = sink.bvalid;
  assign sink.bready    = source.bready;
  assign sink.arid      = {MasterIndex, source.arid};
  assign sink.araddr    = source.araddr;
  assign sink.arlen     = source.arlen;
  assign sink.arsize    = source.arsize;
  assign sink.arburst   = source.arburst;
  assign sink.arlock    = source.arlock;
  assign sink.arcache   = source.arcache;
  assign sink.arprot    = source.arprot;
  assign sink.arqos     = source.arqos;
  assign sink.arregion  = source.arregion;
  assign sink.aruser    = source.aruser;
  assign sink.arvalid   = source.arvalid;
  assign source.arready = sink.arready;
  assign source.rid     = sink.rid[2:0];
  assign source.rdata   = sink.rdata;
  assign source.rresp   = sink.rresp;
  assign source.rlast   = sink.rlast;
  assign source.ruser   = sink.ruser;
  assign source.rvalid  = sink.rvalid;
  assign sink.rready    = source.rready;
endmodule
