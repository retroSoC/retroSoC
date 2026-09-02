// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// Serializes the three HP compatibility ports onto one legacy AXI4 master.
module hp_axi4_mux3 (
    input logic          clk_i,
    input logic          rst_n_i,
          axi4_if.slave  icache,
          axi4_if.slave  dcache,
          axi4_if.slave  mmio,
          axi4_if.master axi4
);
  typedef enum logic {
    Idle,
    Active
  } state_e;

  state_e s_state_d, s_state_q;
  logic s_state_bits_q;
  logic [1:0] s_owner_d, s_owner_q;
  logic s_write_d, s_write_q;
  logic [1:0] s_selected;
  logic       s_selected_write;
  logic       s_addr_accept;
  logic       s_terminal;

  assign s_state_q = state_e'(s_state_bits_q);

  always_comb begin
    s_selected       = 2'd0;
    s_selected_write = 1'b0;
    if (mmio.arvalid || mmio.awvalid) begin
      s_selected       = 2'd2;
      s_selected_write = mmio.awvalid && !mmio.arvalid;
    end else if (dcache.arvalid || dcache.awvalid) begin
      s_selected       = 2'd1;
      s_selected_write = dcache.awvalid && !dcache.arvalid;
    end else begin
      s_selected       = 2'd0;
      s_selected_write = icache.awvalid && !icache.arvalid;
    end
  end

  assign axi4.awid = (s_state_q == Idle) ?
                      ((s_selected == 2'd2) ? mmio.awid :
                       (s_selected == 2'd1) ? dcache.awid : icache.awid) : '0;
  assign axi4.awaddr = (s_selected == 2'd2) ? mmio.awaddr :
                       (s_selected == 2'd1) ? dcache.awaddr : icache.awaddr;
  assign axi4.awlen = (s_selected == 2'd2) ? mmio.awlen :
                      (s_selected == 2'd1) ? dcache.awlen : icache.awlen;
  assign axi4.awsize = (s_selected == 2'd2) ? mmio.awsize :
                       (s_selected == 2'd1) ? dcache.awsize : icache.awsize;
  assign axi4.awburst = (s_selected == 2'd2) ? mmio.awburst :
                        (s_selected == 2'd1) ? dcache.awburst : icache.awburst;
  assign axi4.awlock = (s_selected == 2'd2) ? mmio.awlock :
                       (s_selected == 2'd1) ? dcache.awlock : icache.awlock;
  assign axi4.awcache = (s_selected == 2'd2) ? mmio.awcache :
                        (s_selected == 2'd1) ? dcache.awcache : icache.awcache;
  assign axi4.awprot = (s_selected == 2'd2) ? mmio.awprot :
                       (s_selected == 2'd1) ? dcache.awprot : icache.awprot;
  assign axi4.awqos = (s_selected == 2'd2) ? mmio.awqos :
                      (s_selected == 2'd1) ? dcache.awqos : icache.awqos;
  assign axi4.awregion = (s_selected == 2'd2) ? mmio.awregion :
                         (s_selected == 2'd1) ? dcache.awregion : icache.awregion;
  assign axi4.awuser = '0;
  assign axi4.awvalid = (s_state_q == Idle) && s_selected_write &&
                        ((s_selected == 2'd2) ? mmio.awvalid :
                         (s_selected == 2'd1) ? dcache.awvalid : icache.awvalid);

  assign mmio.awready = (s_state_q == Idle) && (s_selected == 2'd2) &&
                        s_selected_write && axi4.awready;
  assign dcache.awready = (s_state_q == Idle) && (s_selected == 2'd1) &&
                          s_selected_write && axi4.awready;
  assign icache.awready = (s_state_q == Idle) && (s_selected == 2'd0) &&
                          s_selected_write && axi4.awready;

  assign axi4.arid = (s_selected == 2'd2) ? mmio.arid :
                      (s_selected == 2'd1) ? dcache.arid : icache.arid;
  assign axi4.araddr = (s_selected == 2'd2) ? mmio.araddr :
                       (s_selected == 2'd1) ? dcache.araddr : icache.araddr;
  assign axi4.arlen = (s_selected == 2'd2) ? mmio.arlen :
                      (s_selected == 2'd1) ? dcache.arlen : icache.arlen;
  assign axi4.arsize = (s_selected == 2'd2) ? mmio.arsize :
                       (s_selected == 2'd1) ? dcache.arsize : icache.arsize;
  assign axi4.arburst = (s_selected == 2'd2) ? mmio.arburst :
                        (s_selected == 2'd1) ? dcache.arburst : icache.arburst;
  assign axi4.arlock = (s_selected == 2'd2) ? mmio.arlock :
                       (s_selected == 2'd1) ? dcache.arlock : icache.arlock;
  assign axi4.arcache = (s_selected == 2'd2) ? mmio.arcache :
                        (s_selected == 2'd1) ? dcache.arcache : icache.arcache;
  assign axi4.arprot = (s_selected == 2'd2) ? mmio.arprot :
                       (s_selected == 2'd1) ? dcache.arprot : icache.arprot;
  assign axi4.arqos = (s_selected == 2'd2) ? mmio.arqos :
                      (s_selected == 2'd1) ? dcache.arqos : icache.arqos;
  assign axi4.arregion = (s_selected == 2'd2) ? mmio.arregion :
                         (s_selected == 2'd1) ? dcache.arregion : icache.arregion;
  assign axi4.aruser = '0;
  assign axi4.arvalid = (s_state_q == Idle) && !s_selected_write &&
                        ((s_selected == 2'd2) ? mmio.arvalid :
                         (s_selected == 2'd1) ? dcache.arvalid : icache.arvalid);

  assign mmio.arready = (s_state_q == Idle) && (s_selected == 2'd2) &&
                        !s_selected_write && axi4.arready;
  assign dcache.arready = (s_state_q == Idle) && (s_selected == 2'd1) &&
                          !s_selected_write && axi4.arready;
  assign icache.arready = (s_state_q == Idle) && (s_selected == 2'd0) &&
                          !s_selected_write && axi4.arready;

  assign axi4.wdata = (s_owner_q == 2'd2) ? mmio.wdata :
                      (s_owner_q == 2'd1) ? dcache.wdata : icache.wdata;
  assign axi4.wstrb = (s_owner_q == 2'd2) ? mmio.wstrb :
                      (s_owner_q == 2'd1) ? dcache.wstrb : icache.wstrb;
  assign axi4.wlast = (s_owner_q == 2'd2) ? mmio.wlast :
                      (s_owner_q == 2'd1) ? dcache.wlast : icache.wlast;
  assign axi4.wuser = '0;
  assign axi4.wvalid = (s_state_q == Active) && s_write_q &&
                       ((s_owner_q == 2'd2) ? mmio.wvalid :
                        (s_owner_q == 2'd1) ? dcache.wvalid : icache.wvalid);
  assign mmio.wready = (s_state_q == Active) && s_write_q && (s_owner_q == 2'd2) && axi4.wready;
  assign dcache.wready = (s_state_q == Active) && s_write_q && (s_owner_q == 2'd1) && axi4.wready;
  assign icache.wready = (s_state_q == Active) && s_write_q && (s_owner_q == 2'd0) && axi4.wready;

  assign mmio.bid = axi4.bid;
  assign dcache.bid = axi4.bid;
  assign icache.bid = axi4.bid;
  assign mmio.bresp = axi4.bresp;
  assign dcache.bresp = axi4.bresp;
  assign icache.bresp = axi4.bresp;
  assign mmio.buser = '0;
  assign dcache.buser = '0;
  assign icache.buser = '0;
  assign mmio.bvalid = (s_state_q == Active) && s_write_q && (s_owner_q == 2'd2) && axi4.bvalid;
  assign dcache.bvalid = (s_state_q == Active) && s_write_q && (s_owner_q == 2'd1) && axi4.bvalid;
  assign icache.bvalid = (s_state_q == Active) && s_write_q && (s_owner_q == 2'd0) && axi4.bvalid;
  assign axi4.bready = ((s_state_q == Active) && s_write_q) ?
                       ((s_owner_q == 2'd2) ? mmio.bready :
                        (s_owner_q == 2'd1) ? dcache.bready : icache.bready) : 1'b0;

  assign mmio.rid = axi4.rid;
  assign dcache.rid = axi4.rid;
  assign icache.rid = axi4.rid;
  assign mmio.rdata = axi4.rdata;
  assign dcache.rdata = axi4.rdata;
  assign icache.rdata = axi4.rdata;
  assign mmio.rresp = axi4.rresp;
  assign dcache.rresp = axi4.rresp;
  assign icache.rresp = axi4.rresp;
  assign mmio.rlast = axi4.rlast;
  assign dcache.rlast = axi4.rlast;
  assign icache.rlast = axi4.rlast;
  assign mmio.ruser = '0;
  assign dcache.ruser = '0;
  assign icache.ruser = '0;
  assign mmio.rvalid = (s_state_q == Active) && !s_write_q && (s_owner_q == 2'd2) && axi4.rvalid;
  assign dcache.rvalid = (s_state_q == Active) && !s_write_q && (s_owner_q == 2'd1) && axi4.rvalid;
  assign icache.rvalid = (s_state_q == Active) && !s_write_q && (s_owner_q == 2'd0) && axi4.rvalid;
  assign axi4.rready = ((s_state_q == Active) && !s_write_q) ?
                       ((s_owner_q == 2'd2) ? mmio.rready :
                        (s_owner_q == 2'd1) ? dcache.rready : icache.rready) : 1'b0;

  assign s_addr_accept = (axi4.awvalid && axi4.awready) || (axi4.arvalid && axi4.arready);
  assign s_terminal = (s_write_q && axi4.bvalid && axi4.bready) ||
                      (!s_write_q && axi4.rvalid && axi4.rready && axi4.rlast);

  always_comb begin
    s_state_d = s_state_q;
    s_owner_d = s_owner_q;
    s_write_d = s_write_q;
    if ((s_state_q == Idle) && s_addr_accept) begin
      s_state_d = Active;
      s_owner_d = s_selected;
      s_write_d = axi4.awvalid && axi4.awready;
    end
    if ((s_state_q == Active) && s_terminal) s_state_d = Idle;
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_owner_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_owner_d),
      .dat_o  (s_owner_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_write_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_d),
      .dat_o  (s_write_q)
  );
endmodule
