// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

`include "mmap_define.svh"

// One accepted transaction globally. AW and W remain independent: W is
// backpressured until the saved AW has reached its target. The owner and all
// address attributes remain registered until the terminal response handshake.
module tiny_axi4_fabric (
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 perf_enable_i,
    input  logic                 perf_clear_i,
           axi4_if.slave         masters       [2],
           axi4_if.master        targets       [5],
    output logic                 fault_valid_o,
    output logic          [31:0] fault_addr_o,
    output logic                 fault_master_o,
    output logic                 fault_write_o,
    output logic          [ 1:0] fault_resp_o,
    output logic          [63:0] cpu_wait_o,
    output logic          [63:0] dma_wait_o
);
  typedef enum logic [1:0] {
    Idle,
    Addr,
    Response
  } state_e;
  typedef struct packed {
    logic [31:0] addr;
    logic [7:0]  len;
    logic [2:0]  size;
    logic [1:0]  burst;
    logic        lock;
    logic [3:0]  cache;
    logic [2:0]  prot;
    logic [3:0]  qos;
    logic [3:0]  region;
    logic        id;
    logic        user;
  } addr_t;
  state_e s_state_d, s_state_q;
  logic [1:0] s_state_bits_q;
  addr_t s_addr_d, s_addr_q;
  addr_t s_read_addr     [2];
  addr_t s_write_addr    [2];
  addr_t s_selected_addr;
  logic s_owner_d, s_owner_q;
  logic s_write_d, s_write_q;
  logic [2:0] s_tgt_d, s_tgt_q;
  logic [3:0] s_request, s_unused_grant;
  logic [ 1:0] s_selected;
  logic        s_selected_valid;
  logic        s_accept;
  logic        s_terminal;
  logic [32:0] s_last_addr;
  logic [ 2:0] s_decoded_target;
  logic        s_protocol_legal;
  logic [1:0] s_awvalid, s_arvalid, s_wvalid, s_wlast, s_bready, s_rready;
  logic [1:0][31:0] s_wdata;
  logic [1:0][ 3:0] s_wstrb;
  logic [1:0]       s_wuser;
  logic [4:0] s_target_awready, s_target_arready, s_target_wready;
  logic [4:0] s_target_bvalid, s_target_rvalid, s_target_rlast;
  logic [4:0] s_target_bid, s_target_rid, s_target_buser, s_target_ruser;
  logic [4:0][1:0] s_target_bresp, s_target_rresp;
  logic [4:0][31:0] s_target_rdata;
  logic [1:0][63:0] s_wait_d, s_wait_q;

  function automatic logic [2:0] decode_target(input logic [31:0] addr_i);
    if (`SOC_ADDR_IS_SRAM(addr_i)) return 3'd0;
    if (`SOC_ADDR_IS_FLASH(addr_i) || `SOC_ADDR_IS_XPI(addr_i)) return 3'd1;
    if (`SOC_ADDR_IS_APB4_PERIPH(addr_i) || `SOC_ADDR_IS_APB4_SYSTEM(addr_i)) return 3'd2;
    return 3'd3;
  endfunction

  assign s_state_q = state_e'(s_state_bits_q);
  assign s_request = {s_awvalid[1], s_arvalid[1], s_awvalid[0], s_arvalid[0]};
  assign s_selected_addr = s_selected[0] ? s_write_addr[s_selected[1]] : s_read_addr[s_selected[1]];
  assign s_decoded_target = decode_target(s_selected_addr.addr);
  assign s_last_addr = {1'b0, s_selected_addr.addr} +
      (({25'd0, s_selected_addr.len} + 33'd1) << s_selected_addr.size) - 33'd1;
  assign s_protocol_legal = !s_selected_addr.lock && (s_selected_addr.size <= 3'd2) &&
      ((s_selected_addr.addr & ((32'd1 << s_selected_addr.size) - 32'd1)) == 32'd0) &&
      ((s_selected_addr.burst == 2'b01) ||
       ((s_selected_addr.burst == 2'b00) && (s_selected_addr.len == 8'd0))) &&
      (s_selected_addr.len <= 8'd15) && !s_last_addr[32] &&
      (s_last_addr[31:12] == s_selected_addr.addr[31:12]) &&
      (decode_target(
      s_last_addr[31:0]
  ) == s_decoded_target) && ((s_decoded_target != 3'd2) || (s_selected_addr.len == 8'd0));
  assign s_accept = (s_state_q == Idle) && s_selected_valid;
  assign s_terminal = (s_state_q == Response) &&
      (s_write_q ? (s_target_bvalid[s_tgt_q] && s_bready[s_owner_q]) :
       (s_target_rvalid[s_tgt_q] && s_rready[s_owner_q] && s_target_rlast[s_tgt_q]));
  assign fault_resp_o = s_write_q ? s_target_bresp[s_tgt_q] : s_target_rresp[s_tgt_q];
  assign fault_valid_o = s_terminal && (fault_resp_o != 2'b00);
  assign fault_addr_o = s_addr_q.addr;
  assign fault_master_o = s_owner_q;
  assign fault_write_o = s_write_q;
  assign cpu_wait_o = s_wait_q[0];
  assign dma_wait_o = s_wait_q[1];

  // Advance on acceptance: the chosen owner is saved until completion, so the
  // next grant after completion starts after this source/direction.
  round_robin_arbiter #(
      .CLIENTS(4)
  ) u_arbiter (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .advance_i (s_accept),
      .request_i (s_request),
      .grant_o   (s_unused_grant),
      .selected_o(s_selected),
      .valid_o   (s_selected_valid)
  );

  always_comb begin
    s_state_d = s_state_q;
    s_owner_d = s_owner_q;
    s_write_d = s_write_q;
    s_addr_d  = s_addr_q;
    s_tgt_d   = s_tgt_q;
    unique case (s_state_q)
      Idle:
      if (s_accept) begin
        s_owner_d = s_selected[1];
        s_write_d = s_selected[0];
        s_addr_d  = s_selected_addr;
        s_tgt_d   = s_protocol_legal ? s_decoded_target : 3'd4;
        s_state_d = Addr;
      end
      Addr:
      if (s_write_q ? s_target_awready[s_tgt_q] : s_target_arready[s_tgt_q]) s_state_d = Response;
      Response: if (s_terminal) s_state_d = Idle;
      default: s_state_d = Idle;
    endcase
    s_wait_d = s_wait_q;
    for (int unsigned master = 0; master < 2; master++) begin
      if (perf_clear_i) s_wait_d[master] = '0;
      else if (perf_enable_i && (s_awvalid[master] || s_arvalid[master]) &&
               !(s_accept && (s_selected[1] == 1'(master))) &&
               (s_wait_q[master] != 64'hffff_ffff_ffff_ffff))
        s_wait_d[master] = s_wait_q[master] + 64'd1;
    end
  end
  for (genvar master = 0; master < 2; master++) begin : gen_master
    assign s_write_addr[master] = {
      masters[master].awaddr,
      masters[master].awlen,
      masters[master].awsize,
      masters[master].awburst,
      masters[master].awlock,
      masters[master].awcache,
      masters[master].awprot,
      masters[master].awqos,
      masters[master].awregion,
      masters[master].awid,
      masters[master].awuser
    };
    assign s_read_addr[master] = {
      masters[master].araddr,
      masters[master].arlen,
      masters[master].arsize,
      masters[master].arburst,
      masters[master].arlock,
      masters[master].arcache,
      masters[master].arprot,
      masters[master].arqos,
      masters[master].arregion,
      masters[master].arid,
      masters[master].aruser
    };
    assign s_awvalid[master] = masters[master].awvalid;
    assign s_arvalid[master] = masters[master].arvalid;
    assign s_wdata[master] = masters[master].wdata;
    assign s_wstrb[master] = masters[master].wstrb;
    assign s_wlast[master] = masters[master].wlast;
    assign s_wuser[master] = masters[master].wuser;
    assign s_wvalid[master] = masters[master].wvalid;
    assign s_bready[master] = masters[master].bready;
    assign s_rready[master] = masters[master].rready;
    assign masters[master].awready = s_accept && (s_selected == {1'(master), 1'b1});
    assign masters[master].arready = s_accept && (s_selected == {1'(master), 1'b0});
    assign masters[master].wready = (s_state_q == Response) && s_write_q &&
        (s_owner_q == 1'(master)) && s_target_wready[s_tgt_q];
    assign masters[master].bvalid = (s_state_q == Response) && s_write_q &&
        (s_owner_q == 1'(master)) && s_target_bvalid[s_tgt_q];
    assign masters[master].rvalid = (s_state_q == Response) && !s_write_q &&
        (s_owner_q == 1'(master)) && s_target_rvalid[s_tgt_q];
    assign masters[master].bid = s_target_bid[s_tgt_q];
    assign masters[master].bresp = s_target_bresp[s_tgt_q];
    assign masters[master].buser = s_target_buser[s_tgt_q];
    assign masters[master].rid = s_target_rid[s_tgt_q];
    assign masters[master].rdata = s_target_rdata[s_tgt_q];
    assign masters[master].rresp = s_target_rresp[s_tgt_q];
    assign masters[master].rlast = s_target_rlast[s_tgt_q];
    assign masters[master].ruser = s_target_ruser[s_tgt_q];
  end
  for (genvar target = 0; target < 5; target++) begin : gen_target
    assign targets[target].awaddr = s_addr_q.addr;
    assign targets[target].awlen = s_addr_q.len;
    assign targets[target].awsize = s_addr_q.size;
    assign targets[target].awburst = s_addr_q.burst;
    assign targets[target].awlock = s_addr_q.lock;
    assign targets[target].awcache = s_addr_q.cache;
    assign targets[target].awprot = s_addr_q.prot;
    assign targets[target].awqos = s_addr_q.qos;
    assign targets[target].awregion = s_addr_q.region;
    assign targets[target].awid = s_addr_q.id;
    assign targets[target].awuser = s_addr_q.user;
    assign targets[target].awvalid = (s_state_q == Addr) && s_write_q && (s_tgt_q == 3'(target));
    assign targets[target].araddr = s_addr_q.addr;
    assign targets[target].arlen = s_addr_q.len;
    assign targets[target].arsize = s_addr_q.size;
    assign targets[target].arburst = s_addr_q.burst;
    assign targets[target].arlock = s_addr_q.lock;
    assign targets[target].arcache = s_addr_q.cache;
    assign targets[target].arprot = s_addr_q.prot;
    assign targets[target].arqos = s_addr_q.qos;
    assign targets[target].arregion = s_addr_q.region;
    assign targets[target].arid = s_addr_q.id;
    assign targets[target].aruser = s_addr_q.user;
    assign targets[target].arvalid = (s_state_q == Addr) && !s_write_q && (s_tgt_q == 3'(target));
    assign targets[target].wdata = s_wdata[s_owner_q];
    assign targets[target].wstrb = s_wstrb[s_owner_q];
    assign targets[target].wlast = s_wlast[s_owner_q];
    assign targets[target].wuser = s_wuser[s_owner_q];
    assign targets[target].wvalid = (s_state_q == Response) && s_write_q &&
        (s_tgt_q == 3'(target)) && s_wvalid[s_owner_q];
    assign targets[target].bready = (s_state_q == Response) && s_write_q &&
        (s_tgt_q == 3'(target)) && s_bready[s_owner_q];
    assign targets[target].rready = (s_state_q == Response) && !s_write_q &&
        (s_tgt_q == 3'(target)) && s_rready[s_owner_q];
    assign s_target_awready[target] = targets[target].awready;
    assign s_target_arready[target] = targets[target].arready;
    assign s_target_wready[target] = targets[target].wready;
    assign s_target_bvalid[target] = targets[target].bvalid;
    assign s_target_bid[target] = targets[target].bid;
    assign s_target_bresp[target] = targets[target].bresp;
    assign s_target_buser[target] = targets[target].buser;
    assign s_target_rvalid[target] = targets[target].rvalid;
    assign s_target_rid[target] = targets[target].rid;
    assign s_target_rresp[target] = targets[target].rresp;
    assign s_target_rdata[target] = targets[target].rdata;
    assign s_target_rlast[target] = targets[target].rlast;
    assign s_target_ruser[target] = targets[target].ruser;
  end
  dffr #(
      .DATA_WIDTH(2)
  ) u_state_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_owner_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_owner_d),
      .dat_o  (s_owner_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_write_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_d),
      .dat_o  (s_write_q)
  );
  dffr #(
      .DATA_WIDTH(63)
  ) u_addr_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_addr_d),
      .dat_o  (s_addr_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_target_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tgt_d),
      .dat_o  (s_tgt_q)
  );
  dffr #(
      .DATA_WIDTH(128)
  ) u_wait_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_wait_d),
      .dat_o  (s_wait_q)
  );
endmodule
