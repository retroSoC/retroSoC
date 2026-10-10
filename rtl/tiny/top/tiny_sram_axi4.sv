// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

// One external transaction per group. Address ownership lasts through the
// terminal response, but the macro is arbitrated separately for every beat.
// W may precede AW on the bus; it is backpressured until its AW is accepted.
module tiny_sram_axi4 #(
    parameter logic [31:0] GroupBase = 32'h3000_0000
) (
    input logic                    clk_i,
    input logic                    rst_n_i,
          axi4_if.slave            axi4,
          tiny_sram_port_if.master memory
);
  typedef enum logic [2:0] {
    Idle,
    ReadStream,
    ReadError,
    WriteStream,
    WriteResponse,
    WriteDrain
  } state_e;
  typedef struct packed {
    state_e      state;
    logic        prefer_write;
    logic        id;
    logic [31:0] addr;
    logic [7:0]  len,          beat;
    logic [2:0]  size;
    logic [1:0]  burst,        resp;
    logic [8:0]  issued,       completed;
    logic        last;
  } transaction_t;
  typedef struct packed {
    logic [31:0] addr, data;
    logic [3:0]  strb;
  } write_t;
  transaction_t s_transaction_d, s_transaction_q;
  write_t s_write_input, s_write_output;
  logic [31:0] s_next_addr;
  logic [1:0] s_ar_resp, s_aw_resp;
  logic [3:0] s_lane_mask;
  logic s_expected_last, s_write_legal;
  logic s_write_full, s_write_empty, s_write_push, s_write_pop;
  logic s_req_accept, s_resp_accept, s_write_accept;

  function automatic logic [1:0] address_response(input logic [31:0] addr_i,
                                                  input logic [7:0] len_i, input logic [2:0] size_i,
                                                  input logic [1:0] burst_i, input logic lock_i);
    logic [32:0] bytes_count, last_addr;
    logic wrap_legal;
    bytes_count = ({25'd0, len_i} + 33'd1) << size_i;
    wrap_legal  = (len_i == 8'd1) || (len_i == 8'd3) || (len_i == 8'd7) || (len_i == 8'd15);
    last_addr   = {1'b0, addr_i} + bytes_count - 33'd1;
    if (burst_i == 2'b00) last_addr = {1'b0, addr_i} + (33'd1 << size_i) - 33'd1;
    if (burst_i == 2'b10)
      last_addr = ({1'b0, addr_i} & ~(bytes_count - 33'd1)) + bytes_count - 33'd1;
    if (lock_i || (len_i > 8'd15) || (size_i > 3'd2) ||
        (burst_i == 2'b11) || ((burst_i == 2'b10) && !wrap_legal) ||
        ((addr_i & ((32'd1 << size_i) - 32'd1)) != 32'd0) || last_addr[32] ||
        (addr_i[31:12] != last_addr[31:12]))
      return 2'b10;
    if ((addr_i < GroupBase) || (last_addr[31:0] > (GroupBase + 32'h7fff))) return 2'b11;
    return 2'b00;
  endfunction

  assign s_ar_resp = address_response(
      axi4.araddr, axi4.arlen, axi4.arsize, axi4.arburst, axi4.arlock
  );
  assign s_aw_resp = address_response(
      axi4.awaddr, axi4.awlen, axi4.awsize, axi4.awburst, axi4.awlock
  );
  assign axi4.arready = (s_transaction_q.state == Idle) &&
      !(s_transaction_q.prefer_write && axi4.awvalid);
  assign axi4.awready = (s_transaction_q.state == Idle) &&
      (s_transaction_q.prefer_write || !axi4.arvalid);
  assign axi4.wready = ((s_transaction_q.state == WriteStream) && !s_transaction_q.last &&
      (!s_write_full || s_write_pop)) || (s_transaction_q.state == WriteDrain);
  assign axi4.rvalid = (s_transaction_q.state == ReadError) ||
      ((s_transaction_q.state == ReadStream) && memory.rsp_valid);
  assign axi4.rid = s_transaction_q.id;
  assign axi4.rdata = (s_transaction_q.state == ReadStream) ? memory.rdata : 32'd0;
  assign axi4.rresp = s_transaction_q.resp;
  assign axi4.rlast = s_transaction_q.beat == s_transaction_q.len;
  assign axi4.ruser = '0;
  assign axi4.bvalid = s_transaction_q.state == WriteResponse;
  assign axi4.bid = s_transaction_q.id;
  assign axi4.bresp = s_transaction_q.resp;
  assign axi4.buser = '0;

  // Read responses stay in the group's reserved queue until R handshakes.
  // Issuance and retirement have independent positions within the same burst.
  assign memory.req_valid = ((s_transaction_q.state == ReadStream) &&
      (s_transaction_q.issued <= {1'b0, s_transaction_q.len})) ||
      ((s_transaction_q.state == WriteStream) && !s_write_empty);
  assign memory.addr = memory.write ? s_write_output.addr : s_transaction_q.addr;
  assign memory.write = s_transaction_q.state == WriteStream;
  assign memory.wdata = s_write_output.data;
  assign memory.wstrb = s_write_output.strb;
  assign memory.rsp_ready = ((s_transaction_q.state == ReadStream) && axi4.rready) ||
      (s_transaction_q.state == WriteStream);
  assign s_req_accept = memory.req_valid && memory.req_ready;
  assign s_resp_accept = memory.rsp_valid && memory.rsp_ready;
  assign s_write_accept = axi4.wvalid && axi4.wready;
  assign s_write_push = (s_transaction_q.state == WriteStream) && s_write_accept && s_write_legal;
  assign s_write_pop = (s_transaction_q.state == WriteStream) && s_req_accept;
  assign s_write_input = {s_transaction_q.addr, axi4.wdata, axi4.wstrb};
  // Capture W before it becomes eligible at the macro. A full queue can
  // replace its head on the same edge that the arbiter commits that word.
  fifo #(
      .DATA_WIDTH  ($bits(write_t)),
      .BUFFER_DEPTH(2)
  ) u_write_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(1'b0),
      .push_i (s_write_push),
      .full_o (s_write_full),
      .dat_i  (s_write_input),
      .pop_i  (s_write_pop),
      .empty_o(s_write_empty),
      .dat_o  (s_write_output),
      .cnt_o  ()                 // Full/empty and accepted/completed counts cover ownership.
  );
  assign s_lane_mask = 4'(((32'd1 << (32'd1 << s_transaction_q.size)) - 32'd1)
                         << s_transaction_q.addr[1:0]);
  assign s_expected_last = s_transaction_q.beat == s_transaction_q.len;
  assign s_write_legal = ((axi4.wstrb & ~s_lane_mask) == 4'd0) && (axi4.wlast == s_expected_last);
  axi4_addr_gen #(
      .ADDR_WIDTH(32)
  ) u_address (
      .alen_i  (s_transaction_q.len),
      .asize_i (s_transaction_q.size),
      .aburst_i(s_transaction_q.burst),
      .addr_i  (s_transaction_q.addr),
      .addr_o  (s_next_addr)
  );

  always_comb begin
    s_transaction_d = s_transaction_q;
    unique case (s_transaction_q.state)
      Idle: begin
        s_transaction_d.beat      = '0;
        s_transaction_d.issued    = '0;
        s_transaction_d.completed = '0;
        s_transaction_d.last      = 1'b0;
        if (axi4.arvalid && axi4.arready) begin
          s_transaction_d.prefer_write = 1'b1;
          s_transaction_d.id           = axi4.arid;
          s_transaction_d.addr         = axi4.araddr;
          // Match the shared target's malformed-address error response length.
          s_transaction_d.len          = (s_ar_resp == 2'b10) ? 8'd0 : axi4.arlen;
          s_transaction_d.size         = axi4.arsize;
          s_transaction_d.burst        = axi4.arburst;
          s_transaction_d.resp         = s_ar_resp;
          s_transaction_d.state        = (s_ar_resp == 2'b00) ? ReadStream : ReadError;
        end else if (axi4.awvalid && axi4.awready) begin
          s_transaction_d.prefer_write = 1'b0;
          s_transaction_d.id           = axi4.awid;
          s_transaction_d.addr         = axi4.awaddr;
          s_transaction_d.len          = (s_aw_resp == 2'b10) ? 8'd0 : axi4.awlen;
          s_transaction_d.size         = axi4.awsize;
          s_transaction_d.burst        = axi4.awburst;
          s_transaction_d.resp         = s_aw_resp;
          s_transaction_d.state        = (s_aw_resp == 2'b00) ? WriteStream : WriteDrain;
        end
      end
      ReadStream: begin
        if (s_req_accept) begin
          s_transaction_d.issued = s_transaction_q.issued + 9'd1;
          s_transaction_d.addr   = s_next_addr;
        end
        if (s_resp_accept) begin
          s_transaction_d.completed = s_transaction_q.completed + 9'd1;
          if (axi4.rlast) s_transaction_d.state = Idle;
          else s_transaction_d.beat = s_transaction_q.beat + 8'd1;
        end
      end
      ReadError:
      if (axi4.rready) begin
        if (axi4.rlast) s_transaction_d.state = Idle;
        else s_transaction_d.beat = s_transaction_q.beat + 8'd1;
      end
      WriteStream: begin
        if (s_write_accept) begin
          s_transaction_d.last = s_expected_last || axi4.wlast;
          s_transaction_d.beat = s_transaction_q.beat + 8'd1;
          s_transaction_d.addr = s_next_addr;
          if (!s_write_legal) s_transaction_d.resp = 2'b10;
        end
        if (s_req_accept) s_transaction_d.issued = s_transaction_q.issued + 9'd1;
        if (s_resp_accept) s_transaction_d.completed = s_transaction_q.completed + 9'd1;
        // Errors do not discard older queued writes. B acknowledges all
        // accepted legal beats only after their macro-commit responses drain.
        if (s_transaction_q.last && s_write_empty &&
            (s_transaction_q.issued == s_transaction_q.completed))
          s_transaction_d.state = WriteResponse;
      end
      WriteDrain:
      if (axi4.wvalid) begin
        if (s_expected_last || axi4.wlast) s_transaction_d.state = WriteResponse;
        else s_transaction_d.beat = s_transaction_q.beat + 8'd1;
      end
      WriteResponse: if (axi4.bready) s_transaction_d.state = Idle;
      default:       s_transaction_d.state = Idle;
    endcase
  end
  dffr #(
      .DATA_WIDTH($bits(transaction_t))
  ) u_transaction (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_transaction_d),
      .dat_o  (s_transaction_q)
  );
`ifdef HAVE_SVA
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      s_transaction_q.completed <= s_transaction_q.issued);
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      axi4.bvalid |-> s_write_empty &&
      (s_transaction_q.completed == s_transaction_q.issued));
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      axi4.rvalid && !axi4.rready |=> axi4.rvalid &&
      $stable(
      {axi4.rdata, axi4.rid, axi4.rresp, axi4.rlast}
  ));
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      axi4.bvalid && !axi4.bready |=> axi4.bvalid && $stable(
      {axi4.bid, axi4.bresp}
  ));
`endif
endmodule
