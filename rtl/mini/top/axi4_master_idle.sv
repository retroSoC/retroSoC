// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module axi4_master_idle (
    axi4_if.master axi4
);
  assign axi4.awid     = '0;
  assign axi4.awaddr   = '0;
  assign axi4.awlen    = '0;
  assign axi4.awsize   = '0;
  assign axi4.awburst  = '0;
  assign axi4.awlock   = 1'b0;
  assign axi4.awcache  = '0;
  assign axi4.awprot   = '0;
  assign axi4.awqos    = '0;
  assign axi4.awregion = '0;
  assign axi4.awuser   = '0;
  assign axi4.awvalid  = 1'b0;
  assign axi4.wdata    = '0;
  assign axi4.wstrb    = '0;
  assign axi4.wlast    = 1'b0;
  assign axi4.wuser    = '0;
  assign axi4.wvalid   = 1'b0;
  assign axi4.bready   = 1'b1;
  assign axi4.arid     = '0;
  assign axi4.araddr   = '0;
  assign axi4.arlen    = '0;
  assign axi4.arsize   = '0;
  assign axi4.arburst  = '0;
  assign axi4.arlock   = 1'b0;
  assign axi4.arcache  = '0;
  assign axi4.arprot   = '0;
  assign axi4.arqos    = '0;
  assign axi4.arregion = '0;
  assign axi4.aruser   = '0;
  assign axi4.arvalid  = 1'b0;
  assign axi4.rready   = 1'b1;
endmodule
