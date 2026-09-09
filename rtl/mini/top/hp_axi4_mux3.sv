// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// Serializes the three HP compatibility ports onto one legacy AXI4 master.
module hp_axi4_mux3 #(
    parameter bit RoundRobin        = 1'b0,
    parameter bit Client0EpochAware = 1'b0
) (
    input logic                clk_i,
    input logic                rst_n_i,
    input logic          [7:0] epoch_i,
          axi4_if.slave        icache,
          axi4_if.slave        dcache,
          axi4_if.slave        mmio,
          axi4_if.master       axi4
);
  typedef enum logic [2:0] {
    Idle,
    Address,
    Active,
    RecoverRead,
    RecoverWriteData,
    RecoverWriteResponse
  } state_e;

  state_e s_state_d, s_state_q;
  logic [2:0] s_state_bits_q;
  logic [1:0] s_owner_d, s_owner_q;
  logic s_write_d, s_write_q;
  logic [1:0] s_selected;
  logic [1:0] s_route_owner;
  logic [1:0] s_rr_selected;
  logic [2:0] s_rr_grant;
  logic [2:0] s_rr_request;
  logic       s_rr_valid;
  logic       s_selected_write;
  logic       s_route_write;
  logic       s_addr_state;
  logic       s_addr_valid;
  logic       s_addr_accept;
  logic       s_terminal;
  logic       s_recovery_terminal;
  logic       s_recovery_write_last;
  logic       s_write_data_accept_last;
  logic       s_recover;
  logic s_write_data_done_d, s_write_data_done_q;
  logic [7:0] s_epoch_q;

  assign s_state_q = state_e'(s_state_bits_q);

  assign s_rr_request = {
    mmio.arvalid || mmio.awvalid, dcache.arvalid || dcache.awvalid, icache.arvalid || icache.awvalid
  };
  assign s_route_owner = (s_state_q == Idle) ? s_selected : s_owner_q;
  assign s_route_write = (s_state_q == Idle) ? s_selected_write : s_write_q;
  assign s_addr_state = (s_state_q == Idle) || (s_state_q == Address);
  assign s_addr_valid = s_route_write ?
      ((s_route_owner == 2'd2) ? mmio.awvalid :
       (s_route_owner == 2'd1) ? dcache.awvalid : icache.awvalid) :
      ((s_route_owner == 2'd2) ? mmio.arvalid :
       (s_route_owner == 2'd1) ? dcache.arvalid : icache.arvalid);
  assign s_recover = epoch_i != s_epoch_q;

  round_robin_arbiter #(
      .CLIENTS    (3),
      .INDEX_WIDTH(2)
  ) u_round_robin (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .advance_i (s_addr_accept && RoundRobin),
      .request_i (s_rr_request),
      .grant_o   (s_rr_grant),
      .selected_o(s_rr_selected),
      .valid_o   (s_rr_valid)
  );

  always_comb begin
    s_selected       = 2'd0;
    s_selected_write = 1'b0;
    if (RoundRobin && s_rr_valid) begin
      s_selected = s_rr_selected;
      case (s_rr_selected)
        2'd2:    s_selected_write = mmio.awvalid && !mmio.arvalid;
        2'd1:    s_selected_write = dcache.awvalid && !dcache.arvalid;
        default: s_selected_write = icache.awvalid && !icache.arvalid;
      endcase
    end else if (mmio.arvalid || mmio.awvalid) begin
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

  assign axi4.awid = (s_route_owner == 2'd2) ? mmio.awid :
                     (s_route_owner == 2'd1) ? dcache.awid : icache.awid;
  assign axi4.awaddr = (s_route_owner == 2'd2) ? mmio.awaddr :
                       (s_route_owner == 2'd1) ? dcache.awaddr : icache.awaddr;
  assign axi4.awlen = (s_route_owner == 2'd2) ? mmio.awlen :
                      (s_route_owner == 2'd1) ? dcache.awlen : icache.awlen;
  assign axi4.awsize = (s_route_owner == 2'd2) ? mmio.awsize :
                       (s_route_owner == 2'd1) ? dcache.awsize : icache.awsize;
  assign axi4.awburst = (s_route_owner == 2'd2) ? mmio.awburst :
                        (s_route_owner == 2'd1) ? dcache.awburst : icache.awburst;
  assign axi4.awlock = (s_route_owner == 2'd2) ? mmio.awlock :
                       (s_route_owner == 2'd1) ? dcache.awlock : icache.awlock;
  assign axi4.awcache = (s_route_owner == 2'd2) ? mmio.awcache :
                        (s_route_owner == 2'd1) ? dcache.awcache : icache.awcache;
  assign axi4.awprot = (s_route_owner == 2'd2) ? mmio.awprot :
                       (s_route_owner == 2'd1) ? dcache.awprot : icache.awprot;
  assign axi4.awqos = (s_route_owner == 2'd2) ? mmio.awqos :
                      (s_route_owner == 2'd1) ? dcache.awqos : icache.awqos;
  assign axi4.awregion = (s_route_owner == 2'd2) ? mmio.awregion :
                         (s_route_owner == 2'd1) ? dcache.awregion : icache.awregion;
  assign axi4.awuser = '0;
  assign axi4.awvalid = s_addr_state && !s_recover && s_route_write &&
                        ((s_route_owner == 2'd2) ? mmio.awvalid :
                         (s_route_owner == 2'd1) ? dcache.awvalid : icache.awvalid);

  assign mmio.awready = s_addr_state && !s_recover && (s_route_owner == 2'd2) &&
                        s_route_write && axi4.awready;
  assign dcache.awready = s_addr_state && !s_recover && (s_route_owner == 2'd1) &&
                          s_route_write && axi4.awready;
  assign icache.awready = s_addr_state && !s_recover && (s_route_owner == 2'd0) &&
                          s_route_write && axi4.awready;

  assign axi4.arid = (s_route_owner == 2'd2) ? mmio.arid :
                     (s_route_owner == 2'd1) ? dcache.arid : icache.arid;
  assign axi4.araddr = (s_route_owner == 2'd2) ? mmio.araddr :
                       (s_route_owner == 2'd1) ? dcache.araddr : icache.araddr;
  assign axi4.arlen = (s_route_owner == 2'd2) ? mmio.arlen :
                      (s_route_owner == 2'd1) ? dcache.arlen : icache.arlen;
  assign axi4.arsize = (s_route_owner == 2'd2) ? mmio.arsize :
                       (s_route_owner == 2'd1) ? dcache.arsize : icache.arsize;
  assign axi4.arburst = (s_route_owner == 2'd2) ? mmio.arburst :
                        (s_route_owner == 2'd1) ? dcache.arburst : icache.arburst;
  assign axi4.arlock = (s_route_owner == 2'd2) ? mmio.arlock :
                       (s_route_owner == 2'd1) ? dcache.arlock : icache.arlock;
  assign axi4.arcache = (s_route_owner == 2'd2) ? mmio.arcache :
                        (s_route_owner == 2'd1) ? dcache.arcache : icache.arcache;
  assign axi4.arprot = (s_route_owner == 2'd2) ? mmio.arprot :
                       (s_route_owner == 2'd1) ? dcache.arprot : icache.arprot;
  assign axi4.arqos = (s_route_owner == 2'd2) ? mmio.arqos :
                      (s_route_owner == 2'd1) ? dcache.arqos : icache.arqos;
  assign axi4.arregion = (s_route_owner == 2'd2) ? mmio.arregion :
                         (s_route_owner == 2'd1) ? dcache.arregion : icache.arregion;
  assign axi4.aruser = '0;
  assign axi4.arvalid = s_addr_state && !s_recover && !s_route_write &&
                        ((s_route_owner == 2'd2) ? mmio.arvalid :
                         (s_route_owner == 2'd1) ? dcache.arvalid : icache.arvalid);

  assign mmio.arready = s_addr_state && !s_recover && (s_route_owner == 2'd2) &&
                        !s_route_write && axi4.arready;
  assign dcache.arready = s_addr_state && !s_recover && (s_route_owner == 2'd1) &&
                          !s_route_write && axi4.arready;
  assign icache.arready = s_addr_state && !s_recover && (s_route_owner == 2'd0) &&
                          !s_route_write && axi4.arready;

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
  assign mmio.wready = s_write_q && (s_owner_q == 2'd2) &&
      (((s_state_q == Active) && axi4.wready) || (s_state_q == RecoverWriteData));
  assign dcache.wready = s_write_q && (s_owner_q == 2'd1) &&
      (((s_state_q == Active) && axi4.wready) || (s_state_q == RecoverWriteData));
  assign icache.wready = s_write_q && (s_owner_q == 2'd0) &&
      (((s_state_q == Active) && axi4.wready) || (s_state_q == RecoverWriteData));

  assign mmio.bid = (s_state_q == RecoverWriteResponse) ? 1'b0 : axi4.bid;
  assign dcache.bid = (s_state_q == RecoverWriteResponse) ? 1'b0 : axi4.bid;
  assign icache.bid = (s_state_q == RecoverWriteResponse) ? 1'b0 : axi4.bid;
  assign mmio.bresp = (s_state_q == RecoverWriteResponse) ? 2'b11 : axi4.bresp;
  assign dcache.bresp = (s_state_q == RecoverWriteResponse) ? 2'b11 : axi4.bresp;
  assign icache.bresp = (s_state_q == RecoverWriteResponse) ? 2'b11 : axi4.bresp;
  assign mmio.buser = '0;
  assign dcache.buser = '0;
  assign icache.buser = '0;
  assign mmio.bvalid = s_write_q && (s_owner_q == 2'd2) &&
      (((s_state_q == Active) && !s_recover && axi4.bvalid) ||
       (s_state_q == RecoverWriteResponse));
  assign dcache.bvalid = s_write_q && (s_owner_q == 2'd1) &&
      (((s_state_q == Active) && !s_recover && axi4.bvalid) ||
       (s_state_q == RecoverWriteResponse));
  assign icache.bvalid = s_write_q && (s_owner_q == 2'd0) &&
      (((s_state_q == Active) && !s_recover && axi4.bvalid) ||
       (s_state_q == RecoverWriteResponse));
  assign axi4.bready = ((s_state_q == Active) && s_write_q) ?
                       ((s_owner_q == 2'd2) ? mmio.bready :
                        (s_owner_q == 2'd1) ? dcache.bready : icache.bready) : 1'b0;

  assign mmio.rid = (s_state_q == RecoverRead) ? 1'b0 : axi4.rid;
  assign dcache.rid = (s_state_q == RecoverRead) ? 1'b0 : axi4.rid;
  assign icache.rid = (s_state_q == RecoverRead) ? 1'b0 : axi4.rid;
  assign mmio.rdata = (s_state_q == RecoverRead) ? 32'd0 : axi4.rdata;
  assign dcache.rdata = (s_state_q == RecoverRead) ? 32'd0 : axi4.rdata;
  assign icache.rdata = (s_state_q == RecoverRead) ? 32'd0 : axi4.rdata;
  assign mmio.rresp = (s_state_q == RecoverRead) ? 2'b11 : axi4.rresp;
  assign dcache.rresp = (s_state_q == RecoverRead) ? 2'b11 : axi4.rresp;
  assign icache.rresp = (s_state_q == RecoverRead) ? 2'b11 : axi4.rresp;
  assign mmio.rlast = (s_state_q == RecoverRead) ? 1'b1 : axi4.rlast;
  assign dcache.rlast = (s_state_q == RecoverRead) ? 1'b1 : axi4.rlast;
  assign icache.rlast = (s_state_q == RecoverRead) ? 1'b1 : axi4.rlast;
  assign mmio.ruser = '0;
  assign dcache.ruser = '0;
  assign icache.ruser = '0;
  assign mmio.rvalid = !s_write_q && (s_owner_q == 2'd2) &&
      (((s_state_q == Active) && !s_recover && axi4.rvalid) || (s_state_q == RecoverRead));
  assign dcache.rvalid = !s_write_q && (s_owner_q == 2'd1) &&
      (((s_state_q == Active) && !s_recover && axi4.rvalid) || (s_state_q == RecoverRead));
  assign icache.rvalid = !s_write_q && (s_owner_q == 2'd0) &&
      (((s_state_q == Active) && !s_recover && axi4.rvalid) || (s_state_q == RecoverRead));
  assign axi4.rready = ((s_state_q == Active) && !s_write_q) ?
                       ((s_owner_q == 2'd2) ? mmio.rready :
                        (s_owner_q == 2'd1) ? dcache.rready : icache.rready) : 1'b0;

  assign s_addr_accept = (axi4.awvalid && axi4.awready) || (axi4.arvalid && axi4.arready);
  assign s_terminal = (s_write_q && axi4.bvalid && axi4.bready) ||
                      (!s_write_q && axi4.rvalid && axi4.rready && axi4.rlast);
  assign s_recovery_terminal = ((s_state_q == RecoverWriteResponse) &&
      ((s_owner_q == 2'd2) ? mmio.bready :
       (s_owner_q == 2'd1) ? dcache.bready : icache.bready)) ||
      ((s_state_q == RecoverRead) &&
       ((s_owner_q == 2'd2) ? mmio.rready :
        (s_owner_q == 2'd1) ? dcache.rready : icache.rready));
  assign s_recovery_write_last = (s_state_q == RecoverWriteData) &&
      ((s_owner_q == 2'd2) ? (mmio.wvalid && mmio.wready && mmio.wlast) :
       (s_owner_q == 2'd1) ? (dcache.wvalid && dcache.wready && dcache.wlast) :
                             (icache.wvalid && icache.wready && icache.wlast));
  assign s_write_data_accept_last = (s_state_q == Active) && s_write_q &&
      axi4.wvalid && axi4.wready && axi4.wlast;

  always_comb begin
    s_state_d           = s_state_q;
    s_owner_d           = s_owner_q;
    s_write_d           = s_write_q;
    s_write_data_done_d = s_write_data_done_q;
    if (s_recover) begin
      unique case (s_state_q)
        Active: begin
          if (Client0EpochAware && (s_owner_q == 2'd0)) begin
            s_state_d = Idle;
          end else if (s_write_q) begin
            s_state_d = (s_write_data_done_q || s_write_data_accept_last) ?
                RecoverWriteResponse : RecoverWriteData;
          end else begin
            s_state_d = RecoverRead;
          end
        end
        RecoverRead, RecoverWriteData, RecoverWriteResponse: s_state_d = s_state_q;
        default:                                             s_state_d = Idle;
      endcase
    end else begin
      unique case (s_state_q)
        Idle: begin
          if (s_addr_valid) begin
            s_owner_d           = s_selected;
            s_write_d           = s_selected_write;
            s_write_data_done_d = 1'b0;
            s_state_d           = s_addr_accept ? Active : Address;
          end
        end
        Address:              if (s_addr_accept) s_state_d = Active;
        Active: begin
          if (s_write_data_accept_last) begin
            s_write_data_done_d = 1'b1;
          end
          if (s_terminal) s_state_d = Idle;
        end
        RecoverRead:          if (s_recovery_terminal) s_state_d = Idle;
        RecoverWriteData: begin
          if (s_recovery_write_last) s_state_d = RecoverWriteResponse;
        end
        RecoverWriteResponse: if (s_recovery_terminal) s_state_d = Idle;
        default:              s_state_d = Idle;
      endcase
    end
  end

  dffr #(
      .DATA_WIDTH(3)
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
  dffr #(
      .DATA_WIDTH(1)
  ) u_write_data_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_data_done_d),
      .dat_o  (s_write_data_done_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_epoch_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (epoch_i),
      .dat_o  (s_epoch_q)
  );

  logic [2:0] s_unused_rr_grant;
  assign s_unused_rr_grant = RoundRobin ? 3'd0 : s_rr_grant;
endmodule
