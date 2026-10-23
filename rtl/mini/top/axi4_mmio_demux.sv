// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "axi4_define.svh"

// Routes the single OpenC906 64-bit data stream between the HP data fabric
// and the MMIO chain by address window. The upstream master is the
// serializing axi4_downsizer_128to64, so at most one read and one write are
// outstanding at any time; the routing decision is registered at the address
// handshake and held until the response completes.
module axi4_mmio_demux #(
    parameter logic [31:0] MmioBase  = 32'h0200_0000,
    parameter logic [31:0] MmioLimit = 32'h3000_0000
) (
    input logic          clk_i,
    input logic          rst_n_i,
    input logic          clear_i,
          axi4_if.slave  source,
          axi4_if.master mem,
          axi4_if.master mmio
);
  typedef enum logic {
    Idle,
    Active
  } channel_state_e;

  channel_state_e s_read_state_d, s_read_state_q;
  channel_state_e s_write_state_d, s_write_state_q;
  logic s_read_state_bits_q;
  logic s_write_state_bits_q;
  logic s_read_sel_d, s_read_sel_q;
  logic s_write_sel_d, s_write_sel_q;
  logic s_read_route_mmio;
  logic s_write_route_mmio;
  logic s_read_accept;
  logic s_write_accept;
  logic s_read_done;
  logic s_write_done;

  assign s_read_state_q = channel_state_e'(s_read_state_bits_q);
  assign s_write_state_q = channel_state_e'(s_write_state_bits_q);

  assign s_read_route_mmio = (source.araddr >= MmioBase) && (source.araddr < MmioLimit);
  assign s_write_route_mmio = (source.awaddr >= MmioBase) && (source.awaddr < MmioLimit);

  assign source.arready = (s_read_state_q == Idle) &&
                          (s_read_route_mmio ? mmio.arready : mem.arready);
  assign mem.arvalid = (s_read_state_q == Idle) && !s_read_route_mmio && source.arvalid;
  assign mmio.arvalid = (s_read_state_q == Idle) && s_read_route_mmio && source.arvalid;
  assign mem.arid = source.arid;
  assign mmio.arid = source.arid;
  assign mem.araddr = source.araddr;
  assign mmio.araddr = source.araddr;
  assign mem.arlen = source.arlen;
  assign mmio.arlen = source.arlen;
  assign mem.arsize = source.arsize;
  assign mmio.arsize = source.arsize;
  assign mem.arburst = source.arburst;
  assign mmio.arburst = source.arburst;
  assign mem.arlock = source.arlock;
  assign mmio.arlock = source.arlock;
  assign mem.arcache = source.arcache;
  assign mmio.arcache = source.arcache;
  assign mem.arprot = source.arprot;
  assign mmio.arprot = source.arprot;
  assign mem.arqos = source.arqos;
  assign mmio.arqos = source.arqos;
  assign mem.arregion = source.arregion;
  assign mmio.arregion = source.arregion;
  assign mem.aruser = source.aruser;
  assign mmio.aruser = source.aruser;
  assign s_read_accept = source.arvalid && source.arready;

  assign source.rid = s_read_sel_q ? mmio.rid : mem.rid;
  assign source.rdata = s_read_sel_q ? mmio.rdata : mem.rdata;
  assign source.rresp = s_read_sel_q ? mmio.rresp : mem.rresp;
  assign source.rlast = s_read_sel_q ? mmio.rlast : mem.rlast;
  assign source.ruser = s_read_sel_q ? mmio.ruser : mem.ruser;
  assign source.rvalid = (s_read_state_q == Active) && (s_read_sel_q ? mmio.rvalid : mem.rvalid);
  assign mem.rready = (s_read_state_q == Active) && !s_read_sel_q && source.rready;
  assign mmio.rready = (s_read_state_q == Active) && s_read_sel_q && source.rready;
  assign s_read_done = source.rvalid && source.rready && source.rlast;

  assign source.awready = (s_write_state_q == Idle) &&
                          (s_write_route_mmio ? mmio.awready : mem.awready);
  assign mem.awvalid = (s_write_state_q == Idle) && !s_write_route_mmio && source.awvalid;
  assign mmio.awvalid = (s_write_state_q == Idle) && s_write_route_mmio && source.awvalid;
  assign mem.awid = source.awid;
  assign mmio.awid = source.awid;
  assign mem.awaddr = source.awaddr;
  assign mmio.awaddr = source.awaddr;
  assign mem.awlen = source.awlen;
  assign mmio.awlen = source.awlen;
  assign mem.awsize = source.awsize;
  assign mmio.awsize = source.awsize;
  assign mem.awburst = source.awburst;
  assign mmio.awburst = source.awburst;
  assign mem.awlock = source.awlock;
  assign mmio.awlock = source.awlock;
  assign mem.awcache = source.awcache;
  assign mmio.awcache = source.awcache;
  assign mem.awprot = source.awprot;
  assign mmio.awprot = source.awprot;
  assign mem.awqos = source.awqos;
  assign mmio.awqos = source.awqos;
  assign mem.awregion = source.awregion;
  assign mmio.awregion = source.awregion;
  assign mem.awuser = source.awuser;
  assign mmio.awuser = source.awuser;
  assign s_write_accept = source.awvalid && source.awready;

  // AXI4 has no WID; with a single outstanding write the W channel follows
  // the registered address routing until WLAST.
  assign mem.wdata = source.wdata;
  assign mmio.wdata = source.wdata;
  assign mem.wstrb = source.wstrb;
  assign mmio.wstrb = source.wstrb;
  assign mem.wlast = source.wlast;
  assign mmio.wlast = source.wlast;
  assign mem.wuser = source.wuser;
  assign mmio.wuser = source.wuser;
  assign mem.wvalid = (s_write_state_q == Active) && !s_write_sel_q && source.wvalid;
  assign mmio.wvalid = (s_write_state_q == Active) && s_write_sel_q && source.wvalid;
  assign source.wready = (s_write_state_q == Active) && (s_write_sel_q ? mmio.wready : mem.wready);

  assign source.bid = s_write_sel_q ? mmio.bid : mem.bid;
  assign source.bresp = s_write_sel_q ? mmio.bresp : mem.bresp;
  assign source.buser = s_write_sel_q ? mmio.buser : mem.buser;
  assign source.bvalid = (s_write_state_q == Active) && (s_write_sel_q ? mmio.bvalid : mem.bvalid);
  assign mem.bready = (s_write_state_q == Active) && !s_write_sel_q && source.bready;
  assign mmio.bready = (s_write_state_q == Active) && s_write_sel_q && source.bready;
  assign s_write_done = source.bvalid && source.bready;

  always_comb begin
    s_read_state_d = s_read_state_q;
    s_read_sel_d   = s_read_sel_q;
    if (s_read_accept) begin
      s_read_state_d = Active;
      s_read_sel_d   = s_read_route_mmio;
    end
    if (s_read_done) s_read_state_d = Idle;
    if (clear_i) s_read_state_d = Idle;
  end

  always_comb begin
    s_write_state_d = s_write_state_q;
    s_write_sel_d   = s_write_sel_q;
    if (s_write_accept) begin
      s_write_state_d = Active;
      s_write_sel_d   = s_write_route_mmio;
    end
    if (s_write_done) s_write_state_d = Idle;
    if (clear_i) s_write_state_d = Idle;
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_read_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_state_d),
      .dat_o  (s_read_state_bits_q)
  );

  dffr #(
      .DATA_WIDTH(1)
  ) u_write_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_state_d),
      .dat_o  (s_write_state_bits_q)
  );

  dffr #(
      .DATA_WIDTH(1)
  ) u_read_sel_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_sel_d),
      .dat_o  (s_read_sel_q)
  );

  dffr #(
      .DATA_WIDTH(1)
  ) u_write_sel_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_sel_d),
      .dat_o  (s_write_sel_q)
  );

`ifndef SYNTHESIS
  property p_single_outstanding_read;
    @(posedge clk_i) disable iff (!rst_n_i) source.arvalid |-> (s_read_state_q == Idle);
  endproperty
  assert property (p_single_outstanding_read);

  property p_single_outstanding_write;
    @(posedge clk_i) disable iff (!rst_n_i) source.awvalid |-> (s_write_state_q == Idle);
  endproperty
  assert property (p_single_outstanding_write);
`endif
endmodule
