// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

// A single target owns one transaction through the upstream terminal handshake.
// Address capture reserves ownership even while the downstream target is stalled.
// Per-owner direction preference and owner round robin advance on admission.
module tiny_axi4_target (
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 enable_i,
           axi4_if.slave         masters            [3],
           axi4_if.master        target,
    output logic                 idle_o,
    output logic                 fault_valid_o,
    output logic          [31:0] fault_addr_o,
    output logic          [ 1:0] fault_master_o,
    output logic                 fault_write_o,
    output logic                 fault_instruction_o,
    output logic          [ 1:0] fault_resp_o
);
  typedef enum logic [2:0] {
    Idle,
    Address,
    Response,
    AbortWrite,
    AbortResponse
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
    logic [3:0]  user;
  } addr_t;
  typedef struct packed {
    state_e      state;
    logic [1:0]  owner;
    logic        write;
    addr_t       addr;
    logic [7:0]  write_beat;
    logic        write_done;
    logic [8:0]  read_count;
    logic        b_captured;
    logic [31:0] read_addr,  error_addr;
    logic [1:0]  error_resp;
    logic        error_seen;
  } request_t;
  request_t s_req_d, s_req_q;
  addr_t s_saved_addr, s_selected_addr;
  logic [31:0] s_req_addr;
  logic        s_req_id;
  addr_t s_read_addr[3], s_write_addr[3];
  logic [2:0] s_arvalid, s_awvalid, s_wvalid, s_wlast, s_bready, s_rready;
  logic [2:0][ 3:0] s_wuser;
  logic [2:0][31:0] s_wdata;
  logic [2:0][ 3:0] s_wstrb;
  logic [2:0] s_owner_req, s_grant, s_prefer_write_d, s_prefer_write_q;
  logic [1:0] s_selected;
  logic s_valid, s_selected_write, s_accept, s_terminal;
  logic s_r_valid, s_r_ready, s_b_valid, s_b_ready;
  logic [39:0] s_r_data;
  logic [ 6:0] s_b_data;
  logic s_read_capture, s_write_capture;
  logic s_abort_read_valid, s_abort_write_valid;
  logic s_resp_active, s_rin_valid, s_bin_valid;
  logic [39:0] s_rin_data;
  logic [ 6:0] s_bin_data;

  assign s_saved_addr = s_req_q.addr;
  assign s_req_addr = s_saved_addr.addr;
  assign s_req_id = s_saved_addr.id;

  assign s_selected_write = s_awvalid[s_selected] &&
      (s_prefer_write_q[s_selected] || !s_arvalid[s_selected]);
  assign s_selected_addr = s_selected_write ? s_write_addr[s_selected] : s_read_addr[s_selected];
  assign s_accept = (s_req_q.state == Idle) && enable_i && s_valid;
  assign idle_o = (s_req_q.state == Idle) && !s_r_valid && !s_b_valid;
  // Target reset cancels downstream work, never an already captured upstream
  // response. Append missing error beats through the same spill registers.
  assign s_resp_active = (s_req_q.state == Response) || (s_req_q.state == AbortResponse);
  assign s_abort_read_valid = (s_req_q.state == AbortResponse) && !s_req_q.write &&
      (s_req_q.read_count <= {1'b0, s_saved_addr.len});
  assign s_abort_write_valid = (s_req_q.state == AbortResponse) && s_req_q.write &&
      s_req_q.write_done && !s_req_q.b_captured;
  assign s_terminal = s_resp_active &&
      (s_req_q.write ? (s_b_valid && s_bready[s_req_q.owner]) :
       (s_r_valid && s_rready[s_req_q.owner] && s_r_data[4]));
  assign fault_valid_o = s_terminal && s_req_q.error_seen;
  assign fault_addr_o = s_req_q.error_addr;
  assign fault_master_o = s_req_q.owner;
  assign fault_write_o = s_req_q.write;
  assign fault_instruction_o = !s_req_q.write && s_saved_addr.prot[2];
  assign fault_resp_o = s_req_q.error_resp;
  assign s_rin_valid = ((s_req_q.state == Response) && enable_i &&
      !s_req_q.write && target.rvalid) || s_abort_read_valid;
  assign s_rin_data = s_abort_read_valid ?
      {s_req_id, 32'd0, 2'b11,
       (s_req_q.read_count == {1'b0, s_saved_addr.len}), 4'd0} :
      {target.rid, target.rdata, target.rresp, target.rlast, target.ruser};
  assign s_bin_valid = ((s_req_q.state == Response) && enable_i &&
      s_req_q.write && target.bvalid) || s_abort_write_valid;
  assign s_bin_data = s_abort_write_valid ? {s_req_id, 2'b11, 4'd0} :
      {target.bid, target.bresp, target.buser};
  assign s_read_capture = s_rin_valid && s_r_ready;
  assign s_write_capture = s_bin_valid && s_b_ready;

  round_robin_arbiter #(
      .CLIENTS(3)
  ) u_owner_arbiter (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .advance_i (s_accept),
      .request_i (s_owner_req),
      .grant_o   (s_grant),
      .selected_o(s_selected),
      .valid_o   (s_valid)
  );
  always_comb begin
    s_prefer_write_d = s_prefer_write_q;
    if (s_accept) s_prefer_write_d[s_selected] = !s_selected_write;
  end
  dffr #(
      .DATA_WIDTH(3)
  ) u_direction_preference (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_prefer_write_d),
      .dat_o  (s_prefer_write_q)
  );

  for (genvar owner = 0; owner < 3; owner++) begin : gen_owner
    assign s_owner_req[owner] = s_arvalid[owner] || s_awvalid[owner];
    assign s_arvalid[owner] = masters[owner].arvalid;
    assign s_awvalid[owner] = masters[owner].awvalid;
    assign s_read_addr[owner] = {
      masters[owner].araddr,
      masters[owner].arlen,
      masters[owner].arsize,
      masters[owner].arburst,
      masters[owner].arlock,
      masters[owner].arcache,
      masters[owner].arprot,
      masters[owner].arqos,
      masters[owner].arregion,
      masters[owner].arid,
      masters[owner].aruser
    };
    assign s_write_addr[owner] = {
      masters[owner].awaddr,
      masters[owner].awlen,
      masters[owner].awsize,
      masters[owner].awburst,
      masters[owner].awlock,
      masters[owner].awcache,
      masters[owner].awprot,
      masters[owner].awqos,
      masters[owner].awregion,
      masters[owner].awid,
      masters[owner].awuser
    };
    assign s_wvalid[owner] = masters[owner].wvalid;
    assign s_wdata[owner] = masters[owner].wdata;
    assign s_wstrb[owner] = masters[owner].wstrb;
    assign s_wlast[owner] = masters[owner].wlast;
    assign s_wuser[owner] = masters[owner].wuser;
    assign s_rready[owner] = masters[owner].rready;
    assign s_bready[owner] = masters[owner].bready;
    assign masters[owner].arready = s_accept && s_grant[owner] && !s_selected_write;
    assign masters[owner].awready = s_accept && s_grant[owner] && s_selected_write;
    assign masters[owner].wready = ((s_req_q.state == Response) && enable_i && s_req_q.write &&
        !s_req_q.write_done && (s_req_q.owner == 2'(owner)) && target.wready) ||
        ((s_req_q.state == AbortWrite) && !s_req_q.write_done &&
         (s_req_q.owner == 2'(owner)));
    assign masters[owner].rvalid = s_resp_active && !s_req_q.write &&
        (s_req_q.owner == 2'(owner)) && s_r_valid;
    assign {masters[owner].rid, masters[owner].rdata, masters[owner].rresp,
            masters[owner].rlast, masters[owner].ruser} = s_r_data;
    assign masters[owner].bvalid = s_resp_active && s_req_q.write &&
        (s_req_q.owner == 2'(owner)) && s_b_valid;
    assign {masters[owner].bid, masters[owner].bresp, masters[owner].buser} = s_b_data;
  end

  assign target.awaddr = s_saved_addr.addr;
  assign target.awlen = s_saved_addr.len;
  assign target.awsize = s_saved_addr.size;
  assign target.awburst = s_saved_addr.burst;
  assign target.awlock = s_saved_addr.lock;
  assign target.awcache = s_saved_addr.cache;
  assign target.awprot = s_saved_addr.prot;
  assign target.awqos = s_saved_addr.qos;
  assign target.awregion = s_saved_addr.region;
  assign target.awid = s_saved_addr.id;
  assign target.awuser = s_saved_addr.user;
  assign target.araddr = s_saved_addr.addr;
  assign target.arlen = s_saved_addr.len;
  assign target.arsize = s_saved_addr.size;
  assign target.arburst = s_saved_addr.burst;
  assign target.arlock = s_saved_addr.lock;
  assign target.arcache = s_saved_addr.cache;
  assign target.arprot = s_saved_addr.prot;
  assign target.arqos = s_saved_addr.qos;
  assign target.arregion = s_saved_addr.region;
  assign target.arid = s_saved_addr.id;
  assign target.aruser = s_saved_addr.user;
  assign target.awvalid = (s_req_q.state == Address) && enable_i && s_req_q.write;
  assign target.arvalid = (s_req_q.state == Address) && enable_i && !s_req_q.write;
  assign target.wvalid = (s_req_q.state == Response) && enable_i && s_req_q.write &&
      !s_req_q.write_done && s_wvalid[s_req_q.owner];
  assign target.wdata = s_wdata[s_req_q.owner];
  assign target.wstrb = s_wstrb[s_req_q.owner];
  assign target.wlast = s_wlast[s_req_q.owner];
  assign target.wuser = s_wuser[s_req_q.owner];
  assign target.rready = (s_req_q.state == Response) && enable_i && !s_req_q.write && s_r_ready;
  assign target.bready = (s_req_q.state == Response) && enable_i && s_req_q.write && s_b_ready;
  spill_register #(
      .DATA_WIDTH(40)
  ) u_read_response (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(1'b0),
      .valid_i(s_rin_valid),
      .ready_o(s_r_ready),
      .data_i (s_rin_data),
      .valid_o(s_r_valid),
      .ready_i(s_resp_active && !s_req_q.write && s_rready[s_req_q.owner]),
      .data_o (s_r_data)
  );
  spill_register #(
      .DATA_WIDTH(7)
  ) u_write_response (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(1'b0),
      .valid_i(s_bin_valid),
      .ready_o(s_b_ready),
      .data_i (s_bin_data),
      .valid_o(s_b_valid),
      .ready_i(s_resp_active && s_req_q.write && s_bready[s_req_q.owner]),
      .data_o (s_b_data)
  );
  always_comb begin
    s_req_d = s_req_q;
    unique case (s_req_q.state)
      Idle:
      if (s_accept) begin
        s_req_d = '0;
        s_req_d.state = Address;
        s_req_d.owner = s_selected;
        s_req_d.write = s_selected_write;
        s_req_d.addr = {
          s_selected_addr.addr,
          s_selected_addr.len,
          s_selected_addr.size,
          s_selected_addr.burst,
          s_selected_addr.lock,
          s_selected_addr.cache,
          s_selected_addr.prot,
          s_selected_addr.qos,
          s_selected_addr.region,
          s_selected_addr.id,
          (s_selected == 2'd1) ? {1'b1, s_selected_addr.user[2:0]} :
            (s_selected == 2'd2) ? 4'b0100 : 4'b0000
        };
        s_req_d.read_addr = s_selected_addr.addr;
      end
      Address: begin
        if (!enable_i) begin
          s_req_d.state = s_req_q.write ? AbortWrite : AbortResponse;
        end else if (s_req_q.write ? target.awready : target.arready) s_req_d.state = Response;
      end
      Response: begin
        if (!enable_i) begin
          s_req_d.state = (s_req_q.write && !s_req_q.write_done) ? AbortWrite : AbortResponse;
        end
        if (target.wvalid && target.wready) begin
          s_req_d.write_beat = s_req_q.write_beat + 8'd1;
          if (target.wlast || (s_req_q.write_beat == s_saved_addr.len)) s_req_d.write_done = 1'b1;
        end
        if (s_terminal) s_req_d.state = Idle;
      end
      AbortWrite: begin
        if (s_wvalid[s_req_q.owner] && !s_req_q.write_done) begin
          s_req_d.write_beat = s_req_q.write_beat + 8'd1;
          if (s_wlast[s_req_q.owner] || (s_req_q.write_beat == s_saved_addr.len)) begin
            s_req_d.write_done = 1'b1;
            s_req_d.state      = AbortResponse;
          end
        end
      end
      AbortResponse: if (s_terminal) s_req_d.state = Idle;
      default:       s_req_d.state = Idle;
    endcase
    if (s_read_capture) begin
      s_req_d.read_count = s_req_q.read_count + 9'd1;
      if (s_saved_addr.burst == 2'b01)
        s_req_d.read_addr = s_req_q.read_addr + (32'd1 << s_saved_addr.size);
      if (!s_req_q.error_seen && (s_rin_data[6:5] != 2'b00)) begin
        s_req_d.error_seen = 1'b1;
        s_req_d.error_addr = s_req_q.read_addr;
        s_req_d.error_resp = s_rin_data[6:5];
      end
    end
    if (s_write_capture) begin
      s_req_d.b_captured = 1'b1;
      if (!s_req_q.error_seen && (s_bin_data[5:4] != 2'b00)) begin
        s_req_d.error_seen = 1'b1;
        s_req_d.error_addr = s_req_addr;
        s_req_d.error_resp = s_bin_data[5:4];
      end
    end
  end
  dffr #(
      .DATA_WIDTH($bits(request_t))
  ) u_request (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_req_d),
      .dat_o  (s_req_q)
  );

`ifdef FORMAL
  logic s_past_valid_q = 1'b0;
  always_ff @(posedge clk_i) begin
    s_past_valid_q <= 1'b1;
    if (rst_n_i) begin
      assert ($onehot0(s_grant));
      assert (!s_accept || idle_o);
      assert (!fault_valid_o || s_terminal);
      if (s_req_q.state != Idle) assert (s_req_q.owner < 2'd3);
    end
    if (s_past_valid_q && rst_n_i && $past(rst_n_i && !s_terminal && (s_req_q.state != Idle))) begin
      assert (s_req_q.owner == $past(s_req_q.owner));
      assert (s_req_q.write == $past(s_req_q.write));
      assert (s_req_q.addr == $past(s_req_q.addr));
    end
  end
  for (genvar owner = 0; owner < 3; owner++) begin : gen_fairness
    logic [1:0] s_bypass_q;
    always_ff @(posedge clk_i) begin
      if (!rst_n_i || !s_owner_req[owner] || (s_accept && s_grant[owner])) s_bypass_q <= '0;
      else if (s_accept) s_bypass_q <= s_bypass_q + 2'd1;
      if (rst_n_i) begin
        assert (s_bypass_q <= 2'd2);
        assert (!(s_bypass_q == 2'd2 && s_owner_req[owner] && s_accept && !s_grant[owner]));
      end
      if (s_past_valid_q && rst_n_i && $past(rst_n_i)) begin
        if ($past(masters[owner].rvalid && !masters[owner].rready)) begin
          assert (masters[owner].rvalid);
          assert ({masters[owner].rid, masters[owner].rdata, masters[owner].rresp,
                   masters[owner].rlast} == $past(
              {masters[owner].rid, masters[owner].rdata, masters[owner].rresp, masters[owner].rlast}
          ));
        end
        if ($past(masters[owner].bvalid && !masters[owner].bready)) begin
          assert (masters[owner].bvalid);
          assert ({masters[owner].bid, masters[owner].bresp} == $past(
              {masters[owner].bid, masters[owner].bresp}
          ));
        end
      end
    end
  end
`endif
`ifdef HAVE_SVA
  assert property (@(posedge clk_i) disable iff (!rst_n_i || !enable_i)
      target.wvalid && !target.wready |=> target.wvalid &&
      $stable(
      {target.wdata, target.wstrb, target.wlast, target.wuser}
  ));
  assert property (@(posedge clk_i) disable iff (!rst_n_i || !enable_i)
      target.arvalid && !target.arready |=> target.arvalid &&
      $stable(
      {target.araddr, target.arlen, target.arid, target.arsize, target.arburst}
  ));
  assert property (@(posedge clk_i) disable iff (!rst_n_i || !enable_i)
      target.awvalid && !target.awready |=> target.awvalid &&
      $stable(
      {target.awaddr, target.awlen, target.awid, target.awsize, target.awburst}
  ));
  for (genvar owner = 0; owner < 3; owner++) begin : gen_response_assert
    assert property (@(posedge clk_i) disable iff (!rst_n_i)
        masters[owner].rvalid && !masters[owner].rready |=> masters[owner].rvalid &&
        $stable(
        {masters[owner].rid, masters[owner].rdata, masters[owner].rresp, masters[owner].rlast}
    ));
    assert property (@(posedge clk_i) disable iff (!rst_n_i)
        masters[owner].bvalid && !masters[owner].bready |=> masters[owner].bvalid &&
        $stable(
        {masters[owner].bid, masters[owner].bresp}
    ));
  end
`endif
endmodule
