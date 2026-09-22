// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// Property set for the NPU-P3 AXI4 data-plane engine (npu_dma). A shadow
// scoreboard tracks every accepted command, burst and beat from the bus so
// the contract checks below are purely bus-derived.
//
// Assumption list (all explicit; nothing else is assumed):
//  (A1) command legality: non-zero byte counts bounded to 128 bytes and no
//       32-bit address wrap, so bounded runs reach the deepest burst plans
//       and the combinational command rejection never fires;
//  (A2) the write payload stream obeys valid/ready: the last flag is stable
//       while a beat is stalled (valid itself and data/keep are constant).
// Commands are held by the harness until acceptance, so no command-channel
// assumption is needed.
// The AXI4 responder is RTL inside npu_dma_formal.sv (not assumed), so R/B
// stability and response placement are checked there as model self-checks.
// No fairness assumptions are needed: every assertion is a safety property.
// Responder stalls are bounded (0..3 cycles per handshake beat, anyconst per
// run — the engine holds its registers during a stall, so longer stalls add
// no new engine states), and the covers below stand in as bounded-liveness
// spot checks.

module npu_dma_formal;
  // verilog_format: off -- formal observations mirror npu_dma_formal_design ports.
  (* anyseq *) (* gclk *) reg clk_i;
  wire        rst_n_i;
  wire        f_past_valid;
  wire        clear;
  wire        block_new;
  wire        pause_ack;
  wire        read_req_valid;
  wire        read_req_ready;
  wire [31:0] read_addr;
  wire [31:0] read_bytes;
  wire        read_data_valid;
  wire        read_data_ready;
  wire [63:0] read_data;
  wire [ 7:0] read_keep;
  wire        read_last;
  wire        write_req_valid;
  wire        write_req_ready;
  wire [31:0] write_addr;
  wire [31:0] write_bytes;
  wire        write_data_valid;
  wire        write_data_ready;
  wire [63:0] write_data;
  wire [ 7:0] write_keep;
  wire        write_last;
  wire        write_done;
  wire        busy;
  wire        read_busy;
  wire        write_busy;
  wire [63:0] read_bytes_done;
  wire [63:0] write_bytes_done;
  wire [63:0] stall_cycles;
  wire        fault;
  wire [ 3:0] fault_code;
  wire [31:0] fault_addr;
  wire [ 1:0] fault_resp;
  wire        read_cmd_err;
  wire        write_cmd_err;
  wire [ 4:0] rfifo_count;
  wire [ 4:0] wfifo_count;
  wire [ 1:0] read_fault;
  wire [63:0] read_data_const;
  wire [63:0] write_data_const;
  wire [ 7:0] write_keep_const;
  wire        awvalid;
  wire        awready;
  wire [ 2:0] awid;
  wire [31:0] awaddr;
  wire [ 7:0] awlen;
  wire [ 2:0] awsize;
  wire [ 1:0] awburst;
  wire        awlock;
  wire [ 3:0] awcache;
  wire [ 2:0] awprot;
  wire [ 3:0] awqos;
  wire [ 3:0] awregion;
  wire        awuser;
  wire        wvalid;
  wire        wready;
  wire [63:0] wdata;
  wire [ 7:0] wstrb;
  wire        wlast;
  wire        wuser;
  wire        bvalid;
  wire        bready;
  wire [ 2:0] bid;
  wire [ 1:0] bresp;
  wire        buser;
  wire        arvalid;
  wire        arready;
  wire [ 2:0] arid;
  wire [31:0] araddr;
  wire [ 7:0] arlen;
  wire [ 2:0] arsize;
  wire [ 1:0] arburst;
  wire        arlock;
  wire [ 3:0] arcache;
  wire [ 2:0] arprot;
  wire [ 3:0] arqos;
  wire [ 3:0] arregion;
  wire        aruser;
  wire        rvalid;
  wire        rready;
  wire [ 2:0] rid;
  wire [63:0] rdata;
  wire [ 1:0] rresp;
  wire        rlast;
  wire        ruser;
  // verilog_format: on

  logic        f_rd_outstanding_q;
  logic [ 8:0] f_rd_beats_left_q;
  logic [ 2:0] f_rd_size_q;
  logic [31:0] f_rd_beat_addr_q;
  logic [31:0] f_rd_seg_addr_q;
  logic [32:0] f_rd_seg_end_q;
  logic [31:0] f_rd_next_burst_q;
  logic        f_rd_done_q;
  logic        f_wr_aw_q;
  logic [ 8:0] f_wr_beats_left_q;
  logic        f_wr_b_q;
  logic [31:0] f_wr_beat_addr_q;
  logic [31:0] f_wr_next_burst_q;

  wire        f_rd_cmd_accept;
  wire        f_wr_cmd_accept;
  wire        f_ar_accept;
  wire        f_r_accept;
  wire        f_r_last_due;
  wire        f_r_proto_now;
  wire        f_aw_accept;
  wire        f_w_accept;
  wire        f_b_accept;
  wire [ 3:0] f_wstrb_ones;
  wire        f_evt_proto_rd;
  wire        f_evt_axi_rd;
  wire        f_evt_proto_wr;
  wire        f_evt_axi_wr;

  assign f_rd_cmd_accept = read_req_valid && read_req_ready;
  assign f_wr_cmd_accept = write_req_valid && write_req_ready;
  assign f_ar_accept = arvalid && arready;
  assign f_r_accept = rvalid && rready;
  assign f_r_last_due = f_rd_beats_left_q == 9'd1;
  assign f_r_proto_now = rvalid && f_rd_outstanding_q && ((rid != 3'd0) || (rlast != f_r_last_due));
  assign f_aw_accept = awvalid && awready;
  assign f_w_accept = wvalid && wready;
  assign f_b_accept = bvalid && bready;
  assign f_wstrb_ones    = {3'd0, wstrb[0]} + {3'd0, wstrb[1]} + {3'd0, wstrb[2]} +
                           {3'd0, wstrb[3]} + {3'd0, wstrb[4]} + {3'd0, wstrb[5]} +
                           {3'd0, wstrb[6]} + {3'd0, wstrb[7]};
  // Bus-visible fault events, mirroring the engine's fault sources: a
  // malformed R beat faults on presentation, a malformed BID faults on
  // presentation, and error responses fault on acceptance.
  assign f_evt_proto_rd = f_r_proto_now && !clear;
  assign f_evt_axi_rd = f_r_accept && (rresp != 2'b00);
  assign f_evt_proto_wr = bvalid && f_wr_b_q && (bid != 3'd0) && !clear;
  assign f_evt_axi_wr = f_b_accept && (bresp != 2'b00);

  npu_dma_formal_design u_design (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .f_past_valid    (f_past_valid),
      .clear           (clear),
      .block_new       (block_new),
      .pause_ack       (pause_ack),
      .read_req_valid  (read_req_valid),
      .read_req_ready  (read_req_ready),
      .read_addr       (read_addr),
      .read_bytes      (read_bytes),
      .read_data_valid (read_data_valid),
      .read_data_ready (read_data_ready),
      .read_data       (read_data),
      .read_keep       (read_keep),
      .read_last       (read_last),
      .write_req_valid (write_req_valid),
      .write_req_ready (write_req_ready),
      .write_addr      (write_addr),
      .write_bytes     (write_bytes),
      .write_data_valid(write_data_valid),
      .write_data_ready(write_data_ready),
      .write_data      (write_data),
      .write_keep      (write_keep),
      .write_last      (write_last),
      .write_done      (write_done),
      .busy            (busy),
      .read_busy       (read_busy),
      .write_busy      (write_busy),
      .read_bytes_done (read_bytes_done),
      .write_bytes_done(write_bytes_done),
      .stall_cycles    (stall_cycles),
      .fault           (fault),
      .fault_code      (fault_code),
      .fault_addr      (fault_addr),
      .fault_resp      (fault_resp),
      .read_cmd_err    (read_cmd_err),
      .write_cmd_err   (write_cmd_err),
      .rfifo_count     (rfifo_count),
      .wfifo_count     (wfifo_count),
      .read_fault      (read_fault),
      .read_data_const (read_data_const),
      .write_data_const(write_data_const),
      .write_keep_const(write_keep_const),
      .awvalid         (awvalid),
      .awready         (awready),
      .awid            (awid),
      .awaddr          (awaddr),
      .awlen           (awlen),
      .awsize          (awsize),
      .awburst         (awburst),
      .awlock          (awlock),
      .awcache         (awcache),
      .awprot          (awprot),
      .awqos           (awqos),
      .awregion        (awregion),
      .awuser          (awuser),
      .wvalid          (wvalid),
      .wready          (wready),
      .wdata           (wdata),
      .wstrb           (wstrb),
      .wlast           (wlast),
      .wuser           (wuser),
      .bvalid          (bvalid),
      .bready          (bready),
      .bid             (bid),
      .bresp           (bresp),
      .buser           (buser),
      .arvalid         (arvalid),
      .arready         (arready),
      .arid            (arid),
      .araddr          (araddr),
      .arlen           (arlen),
      .arsize          (arsize),
      .arburst         (arburst),
      .arlock          (arlock),
      .arcache         (arcache),
      .arprot          (arprot),
      .arqos           (arqos),
      .arregion        (arregion),
      .aruser          (aruser),
      .rvalid          (rvalid),
      .rready          (rready),
      .rid             (rid),
      .rdata           (rdata),
      .rresp           (rresp),
      .rlast           (rlast),
      .ruser           (ruser)
  );

  // Shadow scoreboard. A malformed accepted R/B beat quarantines the
  // receiver in the engine, so the shadow retains the burst obligation until
  // the flush; address/beat tracking otherwise follows the accepted traffic.
  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      f_rd_outstanding_q <= 1'b0;
      f_rd_beats_left_q  <= 9'd0;
      f_rd_size_q        <= 3'd0;
      f_rd_beat_addr_q   <= 32'd0;
      f_rd_seg_addr_q    <= 32'd0;
      f_rd_seg_end_q     <= 33'd0;
      f_rd_next_burst_q  <= 32'd0;
      f_rd_done_q        <= 1'b0;
      f_wr_aw_q          <= 1'b0;
      f_wr_beats_left_q  <= 9'd0;
      f_wr_b_q           <= 1'b0;
      f_wr_beat_addr_q   <= 32'd0;
      f_wr_next_burst_q  <= 32'd0;
    end else if (clear) begin
      f_rd_outstanding_q <= 1'b0;
      f_rd_beats_left_q  <= 9'd0;
      f_rd_size_q        <= 3'd0;
      f_rd_beat_addr_q   <= 32'd0;
      f_rd_seg_addr_q    <= 32'd0;
      f_rd_seg_end_q     <= 33'd0;
      f_rd_next_burst_q  <= 32'd0;
      f_rd_done_q        <= 1'b0;
      f_wr_aw_q          <= 1'b0;
      f_wr_beats_left_q  <= 9'd0;
      f_wr_b_q           <= 1'b0;
      f_wr_beat_addr_q   <= 32'd0;
      f_wr_next_burst_q  <= 32'd0;
    end else begin
      if (f_rd_cmd_accept) begin
        f_rd_seg_addr_q   <= read_addr;
        f_rd_seg_end_q    <= {1'b0, read_addr} + {1'b0, read_bytes};
        f_rd_next_burst_q <= read_addr;
        f_rd_done_q       <= 1'b0;
      end
      if (f_wr_cmd_accept) begin
        f_wr_next_burst_q <= {write_addr[31:3], 3'b000};
      end
      if (f_r_accept) begin
        if ((rid != 3'd0) || (rlast != f_r_last_due)) begin
          f_rd_outstanding_q <= 1'b1;
        end else if (f_r_last_due) begin
          f_rd_outstanding_q <= 1'b0;
          if ((f_rd_next_burst_q == f_rd_seg_end_q[31:0]) && (rresp == 2'b00)) begin
            f_rd_done_q <= 1'b1;
          end
        end else begin
          f_rd_beats_left_q <= f_rd_beats_left_q - 9'd1;
          f_rd_beat_addr_q  <= f_rd_beat_addr_q + (32'd1 << f_rd_size_q);
        end
      end
      if (f_w_accept) begin
        if (f_wr_beats_left_q == 9'd1) begin
          f_wr_aw_q <= 1'b0;
          f_wr_b_q  <= 1'b1;
        end else begin
          f_wr_beats_left_q <= f_wr_beats_left_q - 9'd1;
          f_wr_beat_addr_q  <= f_wr_beat_addr_q + 32'd8;
        end
      end
      if (f_b_accept && (bid == 3'd0)) begin
        f_wr_b_q <= 1'b0;
      end
      if (f_ar_accept) begin
        f_rd_outstanding_q <= 1'b1;
        f_rd_beats_left_q  <= {1'b0, arlen} + 9'd1;
        f_rd_size_q        <= arsize;
        f_rd_beat_addr_q   <= araddr;
        f_rd_next_burst_q  <= araddr + (({24'd0, arlen} + 32'd1) << arsize);
      end
      if (f_aw_accept) begin
        f_wr_aw_q         <= 1'b1;
        f_wr_beats_left_q <= {1'b0, awlen} + 9'd1;
        f_wr_beat_addr_q  <= awaddr;
        f_wr_next_burst_q <= awaddr + (({24'd0, awlen} + 32'd1) << 3);
      end
    end
  end

  // Assumptions A1 (command legality) and A2 (write stream last-flag
  // stability). Commands are held by the harness until accepted, so no
  // command-channel assumption is needed.
  always @(posedge clk_i) begin
    if (rst_n_i) begin
      assume (read_bytes != 32'd0);
      assume (read_bytes <= 32'd128);
      assume ({1'b0, read_addr} + {1'b0, read_bytes} <= 33'h1_0000_0000);
      assume (write_bytes != 32'd0);
      assume (write_bytes <= 32'd128);
      assume ({1'b0, write_addr} + {1'b0, write_bytes} <= 33'h1_0000_0000);
    end
    if (f_past_valid && $past(rst_n_i)) begin
      if ($past(write_data_valid && !write_data_ready)) begin
        assume (write_last == $past(write_last));
      end
    end
  end

  // Responder model self-checks: a failure here is a harness bug, not an
  // engine bug. Responses arrive only inside an outstanding burst, payload
  // is stable through any stall (the flush invalidates in-flight beats), and
  // RLAST is well placed unless a protocol fault is being injected.
  always @(posedge clk_i) begin
    if (rst_n_i) begin
      if (rvalid) begin
        assert (f_rd_outstanding_q);
      end
      if (bvalid) begin
        assert (f_wr_b_q);
      end
      if (rvalid && (read_fault != 2'd3)) begin
        assert (rlast == f_r_last_due);
      end
    end
    if (f_past_valid && $past(rst_n_i) && !$past(clear) && !clear) begin
      if ($past(rvalid && !rready)) begin
        assert (rvalid);
        assert (rid == $past(rid));
        assert (rdata == $past(rdata));
        assert (rresp == $past(rresp));
        assert (rlast == $past(rlast));
        assert (ruser == $past(ruser));
      end
      if ($past(bvalid && !bready)) begin
        assert (bvalid);
        assert (bid == $past(bid));
        assert (bresp == $past(bresp));
        assert (buser == $past(buser));
      end
    end
  end

  // Engine contract, current-cycle checks.
  always @(posedge clk_i) begin
    if (rst_n_i) begin
      // Emitted read-address attributes: ID zero, INCR, at most 16 beats,
      // sizes 1/2/4/8 with narrow transfers only as single-beat edges,
      // naturally aligned, never crossing a 4 KiB page, never fetching
      // outside the accepted segment, and only with an empty receive FIFO.
      if (arvalid) begin
        assert (arid == 3'd0);
        assert (arburst == 2'b01);
        assert (arlen <= 8'd15);
        assert (arsize <= 3'd3);
        assert ((arsize == 3'd3) || (arlen == 8'd0));
        assert ((araddr & ((32'd1 << arsize) - 32'd1)) == 32'd0);
        assert ({1'b0, araddr[11:0]} + (({5'd0, arlen} + 13'd1) << arsize) <= 13'd4096);
        assert (arlock == 1'b0);
        assert (arcache == 4'd0);
        assert (arprot == 3'd0);
        assert (arqos == 4'd0);
        assert (arregion == 4'd0);
        assert (aruser == 1'b0);
        assert (rfifo_count == 5'd0);
        assert (araddr == f_rd_next_burst_q);
        assert ({1'b0, araddr} >= {1'b0, f_rd_seg_addr_q});
        assert ({1'b0, araddr} + (({25'd0, arlen} + 33'd1) << arsize) <= f_rd_seg_end_q);
      end
      // Emitted write-address attributes: ID zero, INCR, full-width aligned
      // beats only, at most 16 beats, never crossing a 4 KiB page, with the
      // complete payload already staged in the write FIFO.
      if (awvalid) begin
        assert (awid == 3'd0);
        assert (awburst == 2'b01);
        assert (awlen <= 8'd15);
        assert (awsize == 3'd3);
        assert (awaddr[2:0] == 3'd0);
        assert ({1'b0, awaddr[11:0]} + (({5'd0, awlen} + 13'd1) << 3) <= 13'd4096);
        assert (awlock == 1'b0);
        assert (awcache == 4'd0);
        assert (awprot == 3'd0);
        assert (awqos == 4'd0);
        assert (awregion == 4'd0);
        assert (awuser == 1'b0);
        assert ({4'd0, wfifo_count} == ({1'b0, awlen} + 9'd1));
        assert (awaddr == f_wr_next_burst_q);
      end
      if (wvalid) begin
        assert (wuser == 1'b0);
        // W is only ever driven after its AW handshake.
        assert (f_wr_aw_q);
        // The write FIFO passes the staged payload through unmodified.
        assert (wdata == write_data_const);
        assert (wstrb == write_keep_const);
      end
      if (read_data_valid) begin
        // The receive FIFO passes the response data through unmodified.
        assert (read_data == read_data_const);
      end
      // At most one outstanding transaction per direction.
      if (f_ar_accept) begin
        assert (!f_rd_outstanding_q);
      end
      if (f_aw_accept) begin
        assert (!f_wr_aw_q);
        assert (!f_wr_b_q);
      end
      // Accepted-transfer conservation: the engine never consumes more beats
      // than the burst carries, WLAST marks exactly the final W beat, and the
      // receivers close after the final beat of a burst.
      if (f_r_accept) begin
        assert (f_rd_beats_left_q != 9'd0);
      end
      if (f_w_accept) begin
        assert (f_wr_beats_left_q != 9'd0);
        assert (wlast == (f_wr_beats_left_q == 9'd1));
      end
      if (write_done) begin
        assert (f_b_accept);
        assert (bid == 3'd0);
        assert (bresp == 2'b00);
      end
      // Legal commands never raise the combinational rejection.
      assert (!read_cmd_err);
      // Pause acknowledge is exactly "block_new held with no AR-accepted
      // read and no AW-accepted write obligation".
      if (block_new && !f_rd_outstanding_q && !f_wr_aw_q && !f_wr_b_q) begin
        assert (pause_ack);
      end
      if (pause_ack) begin
        assert (block_new);
        assert (!f_rd_outstanding_q);
        assert (!f_wr_aw_q);
        assert (!f_wr_b_q);
      end
    end
  end

  // Engine contract, registered checks.
  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i)) begin
      // VALID payloads stay stable through any stall on the engine-driven
      // channels and the read-data stream; only the coordinated fabric flush
      // may retract a presented transfer.
      if ($past(arvalid && !arready) && !clear) begin
        assert (arvalid);
        assert (arid == $past(arid));
        assert (araddr == $past(araddr));
        assert (arlen == $past(arlen));
        assert (arsize == $past(arsize));
        assert (arburst == $past(arburst));
        assert (arlock == $past(arlock));
        assert (arcache == $past(arcache));
        assert (arprot == $past(arprot));
        assert (arqos == $past(arqos));
        assert (arregion == $past(arregion));
        assert (aruser == $past(aruser));
      end
      if ($past(awvalid && !awready) && !clear) begin
        assert (awvalid);
        assert (awid == $past(awid));
        assert (awaddr == $past(awaddr));
        assert (awlen == $past(awlen));
        assert (awsize == $past(awsize));
        assert (awburst == $past(awburst));
        assert (awlock == $past(awlock));
        assert (awcache == $past(awcache));
        assert (awprot == $past(awprot));
        assert (awqos == $past(awqos));
        assert (awregion == $past(awregion));
        assert (awuser == $past(awuser));
      end
      if ($past(wvalid && !wready) && !clear) begin
        assert (wvalid);
        assert (wdata == $past(wdata));
        assert (wstrb == $past(wstrb));
        assert (wlast == $past(wlast));
        assert (wuser == $past(wuser));
      end
      if ($past(read_data_valid && !read_data_ready) && !clear) begin
        assert (read_data_valid);
        assert (read_data == $past(read_data));
        assert (read_keep == $past(read_keep));
        assert (read_last == $past(read_last));
      end
      // No new AR/AW presentation begins while the pause is acknowledged.
      if ($past(pause_ack && !arvalid) && !$past(clear)) begin
        assert (!arvalid);
      end
      if ($past(pause_ack && !awvalid) && !$past(clear)) begin
        assert (!awvalid);
      end
      // Receivers close after the final accepted beat of a burst.
      if ($past(f_r_accept && f_r_last_due)) begin
        assert (!rready);
      end
      if ($past(f_w_accept && (f_wr_beats_left_q == 9'd1))) begin
        assert (!wvalid);
      end
      // Sticky first fault with deterministic priority
      // AXI_PROTOCOL (6) > AXI_READ (4) > AXI_WRITE (5).
      if (!$past(fault)) begin
        if ($past(f_evt_proto_rd)) begin
          assert (fault);
          assert (fault_code == 4'd6);
          assert (fault_resp == $past(rresp));
          assert (fault_addr == $past(f_rd_beat_addr_q));
        end else if ($past(f_evt_proto_wr)) begin
          assert (fault);
          assert (fault_code == 4'd6);
          assert (fault_resp == $past(bresp));
          assert (fault_addr == $past(f_wr_beat_addr_q));
        end else if ($past(f_evt_axi_rd)) begin
          assert (fault);
          assert (fault_code == 4'd4);
          assert (fault_resp == $past(rresp));
          assert (fault_addr == $past(f_rd_beat_addr_q));
        end else if ($past(f_evt_axi_wr)) begin
          assert (fault);
          assert (fault_code == 4'd5);
          assert (fault_resp == $past(bresp));
          assert (fault_addr == $past(f_wr_beat_addr_q));
        end
      end
      // The fault is sticky with stable fields until clear_i.
      if ($past(fault) && !$past(clear) && !clear) begin
        assert (fault);
        assert (fault_code == $past(fault_code));
        assert (fault_addr == $past(fault_addr));
        assert (fault_resp == $past(fault_resp));
      end
      if (fault) begin
        assert ((fault_code == 4'd4) || (fault_code == 4'd5) || (fault_code == 4'd6));
      end
      // Counters are monotone without clear_i and count exactly the accepted
      // traffic (addressed read lanes, accepted WSTRB bytes).
      if (!$past(clear) && !clear) begin
        assert (read_bytes_done >= $past(read_bytes_done));
        assert (write_bytes_done >= $past(write_bytes_done));
        assert (stall_cycles >= $past(stall_cycles));
      end
      if ($past(f_r_accept)) begin
        assert (read_bytes_done == ($past(read_bytes_done) + (64'd1 << $past(f_rd_size_q))));
      end
      if ($past(f_w_accept)) begin
        assert (write_bytes_done == ($past(write_bytes_done) + {60'd0, $past(f_wstrb_ones)}));
      end
    end
    // Valids stay low out of reset. pause_ack is exempt: it combinationally
    // follows block_new on an idle engine, which is legal at any time.
    if (f_past_valid && rst_n_i && !$past(rst_n_i)) begin
      assert (!arvalid && !awvalid && !wvalid && !rready && !bready);
      assert (!read_data_valid && !write_data_ready && !write_done);
      assert (!busy && !fault);
    end
    if (!rst_n_i) begin
      assert (!arvalid && !awvalid && !wvalid && !rready && !bready);
      assert (!read_data_valid && !write_data_ready && !write_done);
      assert (!busy && !fault && !pause_ack);
    end
  end

  // Reachability covers: successful read and write bursts, the fault cases,
  // pause with a retained unaccepted VALID, and a mid-flight flush.
  always @(posedge clk_i) begin
    if (rst_n_i) begin
      cover (f_ar_accept && (arlen == 8'd15));
      cover (f_ar_accept && (arsize != 3'd3));
      cover (f_ar_accept && (arlen >= 8'd3));
      cover (f_rd_done_q && !fault);
      cover (f_aw_accept && (awlen >= 8'd1));
      cover (write_done);
      cover (fault && (fault_code == 4'd4));
      cover (fault && (fault_code == 4'd5));
      cover (fault && (fault_code == 4'd6));
      cover (pause_ack && arvalid && !arready);
      cover (pause_ack && awvalid && !awready);
      cover (clear && f_rd_outstanding_q);
      cover (clear && (f_wr_aw_q || f_wr_b_q));
      cover (f_rd_outstanding_q && (f_wr_aw_q || f_wr_b_q));
      cover (write_cmd_err);
      cover (read_data_valid && read_data_ready && read_last);
    end
  end

endmodule
