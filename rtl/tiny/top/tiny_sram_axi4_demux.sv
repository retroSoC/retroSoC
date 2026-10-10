// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

// Compatibility attachment to the pre-P5 fabric. Independent direction tags
// route responses; this module does not arbitrate or lock the SRAM macros.
module tiny_sram_axi4_demux (
    input logic          clk_i,
    input logic          rst_n_i,
          axi4_if.slave  upstream,
          axi4_if.master groups  [4]
);
  logic s_read_busy_d, s_read_busy_q;
  logic s_write_busy_d, s_write_busy_q;
  logic s_read_terminal, s_write_terminal;
  logic [1:0] s_read_group_d, s_read_group_q;
  logic [1:0] s_write_group_d, s_write_group_q;
  logic [3:0] s_arready, s_awready, s_wready, s_rvalid, s_bvalid, s_rlast;
  logic [3:0] s_rid, s_bid, s_ruser, s_buser;
  logic [1:0] s_rresp[4], s_bresp[4];
  logic [31:0] s_rdata[4];

  assign upstream.arready = !s_read_busy_q && s_arready[upstream.araddr[16:15]];
  assign upstream.awready = !s_write_busy_q && s_awready[upstream.awaddr[16:15]];
  assign upstream.wready = s_write_busy_q && s_wready[s_write_group_q];
  assign upstream.rvalid = s_read_busy_q && s_rvalid[s_read_group_q];
  assign upstream.rdata = s_rdata[s_read_group_q];
  assign upstream.rresp = s_rresp[s_read_group_q];
  assign upstream.rlast = s_rlast[s_read_group_q];
  assign upstream.rid = s_rid[s_read_group_q];
  assign upstream.ruser = s_ruser[s_read_group_q];
  assign upstream.bvalid = s_write_busy_q && s_bvalid[s_write_group_q];
  assign upstream.bresp = s_bresp[s_write_group_q];
  assign upstream.bid = s_bid[s_write_group_q];
  assign upstream.buser = s_buser[s_write_group_q];
  assign s_read_terminal = upstream.rvalid && upstream.rready && upstream.rlast;
  assign s_write_terminal = upstream.bvalid && upstream.bready;
  assign s_read_busy_d = (s_read_busy_q && !s_read_terminal) ||
      (upstream.arvalid && upstream.arready);
  assign s_write_busy_d = (s_write_busy_q && !s_write_terminal) ||
      (upstream.awvalid && upstream.awready);
  assign s_read_group_d = upstream.araddr[16:15];
  assign s_write_group_d = upstream.awaddr[16:15];

  dffr #(
      .DATA_WIDTH(1)
  ) u_read_busy (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_busy_d),
      .dat_o  (s_read_busy_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_write_busy (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_busy_d),
      .dat_o  (s_write_busy_q)
  );
  dffer #(
      .DATA_WIDTH(2)
  ) u_read_group (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (upstream.arvalid && upstream.arready),
      .dat_i  (s_read_group_d),
      .dat_o  (s_read_group_q)
  );
  dffer #(
      .DATA_WIDTH(2)
  ) u_write_group (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (upstream.awvalid && upstream.awready),
      .dat_i  (s_write_group_d),
      .dat_o  (s_write_group_q)
  );

  for (genvar group = 0; group < 4; group++) begin : gen_group
    assign groups[group].arid = upstream.arid;
    assign groups[group].araddr = upstream.araddr;
    assign groups[group].arlen = upstream.arlen;
    assign groups[group].arsize = upstream.arsize;
    assign groups[group].arburst = upstream.arburst;
    assign groups[group].arlock = upstream.arlock;
    assign groups[group].arcache = upstream.arcache;
    assign groups[group].arprot = upstream.arprot;
    assign groups[group].arqos = upstream.arqos;
    assign groups[group].arregion = upstream.arregion;
    assign groups[group].aruser = upstream.aruser;
    assign groups[group].awid = upstream.awid;
    assign groups[group].awaddr = upstream.awaddr;
    assign groups[group].awlen = upstream.awlen;
    assign groups[group].awsize = upstream.awsize;
    assign groups[group].awburst = upstream.awburst;
    assign groups[group].awlock = upstream.awlock;
    assign groups[group].awcache = upstream.awcache;
    assign groups[group].awprot = upstream.awprot;
    assign groups[group].awqos = upstream.awqos;
    assign groups[group].awregion = upstream.awregion;
    assign groups[group].awuser = upstream.awuser;
    assign groups[group].wdata = upstream.wdata;
    assign groups[group].wstrb = upstream.wstrb;
    assign groups[group].wlast = upstream.wlast;
    assign groups[group].wuser = upstream.wuser;

    assign groups[group].arvalid = upstream.arvalid && !s_read_busy_q &&
        (upstream.araddr[16:15] == 2'(group));
    assign groups[group].awvalid = upstream.awvalid && !s_write_busy_q &&
        (upstream.awaddr[16:15] == 2'(group));
    assign groups[group].wvalid = upstream.wvalid && s_write_busy_q &&
        (s_write_group_q == 2'(group));
    assign groups[group].rready = upstream.rready && s_read_busy_q && (s_read_group_q == 2'(group));
    assign groups[group].bready = upstream.bready && s_write_busy_q &&
        (s_write_group_q == 2'(group));
    assign s_arready[group] = groups[group].arready;
    assign s_awready[group] = groups[group].awready;
    assign s_wready[group] = groups[group].wready;
    assign s_rvalid[group] = groups[group].rvalid;
    assign s_bvalid[group] = groups[group].bvalid;
    assign s_rlast[group] = groups[group].rlast;
    assign s_rid[group] = groups[group].rid;
    assign s_bid[group] = groups[group].bid;
    assign s_ruser[group] = groups[group].ruser;
    assign s_buser[group] = groups[group].buser;
    assign s_rresp[group] = groups[group].rresp;
    assign s_bresp[group] = groups[group].bresp;
    assign s_rdata[group] = groups[group].rdata;
  end
endmodule
