// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// Bounded formal harness for the NPU-P3 AXI4 data-plane engine (npu_dma).
// One legal-but-adversarial command is offered per direction from the first
// active cycle until it is accepted (anyconst address/byte-count fields), so
// edge alignments, short segments and post-flush re-issue are all explored.
// The constrained AXI4 responder below keeps at most one outstanding burst
// per direction, runs independent per-channel stall state machines (0..3
// stall cycles per handshake beat, chosen once per run by anyconst
// personalities), and optionally injects SLVERR/DECERR or malformed
// RID/RLAST/BID responses selected by anyconst knobs. block_new_i and
// clear_i toggle inside anyconst-timed windows; clear_i models the
// coordinated fabric flush, so the responder cancels in-flight transfers
// together with the engine and never presents residual R/B beats to a
// flushed receiver (BMC-sound suppression). A burst quarantined by a
// malformed response is likewise retired silently because the engine stops
// its receiver until the flush. All legality assumptions on the command and
// stream sources live in npu_dma_formal_props.sv.

module npu_dma_formal_design (
    // verilog_format: off -- protocol observations are grouped by channel.
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        clear,
    output logic        block_new,
    output logic        pause_ack,
    output logic        read_req_valid,
    output logic        read_req_ready,
    output logic [31:0] read_addr,
    output logic [31:0] read_bytes,
    output logic        read_data_valid,
    output logic        read_data_ready,
    output logic [63:0] read_data,
    output logic [ 7:0] read_keep,
    output logic        read_last,
    output logic        write_req_valid,
    output logic        write_req_ready,
    output logic [31:0] write_addr,
    output logic [31:0] write_bytes,
    output logic        write_data_valid,
    output logic        write_data_ready,
    output logic [63:0] write_data,
    output logic [ 7:0] write_keep,
    output logic        write_last,
    output logic        write_done,
    output logic        busy,
    output logic        read_busy,
    output logic        write_busy,
    output logic [63:0] read_bytes_done,
    output logic [63:0] write_bytes_done,
    output logic [63:0] stall_cycles,
    output logic        fault,
    output logic [ 3:0] fault_code,
    output logic [31:0] fault_addr,
    output logic [ 1:0] fault_resp,
    output logic        read_cmd_err,
    output logic        write_cmd_err,
    output logic [ 4:0] rfifo_count,
    output logic [ 4:0] wfifo_count,
    output logic [ 1:0] read_fault,
    output logic [63:0] read_data_const,
    output logic [63:0] write_data_const,
    output logic [ 7:0] write_keep_const,
    output logic        awvalid,
    output logic        awready,
    output logic [ 2:0] awid,
    output logic [31:0] awaddr,
    output logic [ 7:0] awlen,
    output logic [ 2:0] awsize,
    output logic [ 1:0] awburst,
    output logic        awlock,
    output logic [ 3:0] awcache,
    output logic [ 2:0] awprot,
    output logic [ 3:0] awqos,
    output logic [ 3:0] awregion,
    output logic        awuser,
    output logic        wvalid,
    output logic        wready,
    output logic [63:0] wdata,
    output logic [ 7:0] wstrb,
    output logic        wlast,
    output logic        wuser,
    output logic        bvalid,
    output logic        bready,
    output logic [ 2:0] bid,
    output logic [ 1:0] bresp,
    output logic        buser,
    output logic        arvalid,
    output logic        arready,
    output logic [ 2:0] arid,
    output logic [31:0] araddr,
    output logic [ 7:0] arlen,
    output logic [ 2:0] arsize,
    output logic [ 1:0] arburst,
    output logic        arlock,
    output logic [ 3:0] arcache,
    output logic [ 2:0] arprot,
    output logic [ 3:0] arqos,
    output logic [ 3:0] arregion,
    output logic        aruser,
    output logic        rvalid,
    output logic        rready,
    output logic [ 2:0] rid,
    output logic [63:0] rdata,
    output logic [ 1:0] rresp,
    output logic        rlast,
    output logic        ruser
    // verilog_format: on
);
  localparam logic [1:0] AxiRespOkay = 2'b00;
  localparam logic [1:0] AxiRespSlverr = 2'b10;
  localparam logic [1:0] AxiRespDecerr = 2'b11;

  // Command fields, payload constants and fault-injection selectors are
  // constant per run. Payload data/keep values never influence the engine's
  // control path, so they are anyconst (this also keeps the solver cheap);
  // the properties file cross-checks the data path against these constants.
  (* anyconst *)logic [31:0] f_read_addr;
  (* anyconst *)logic [31:0] f_read_bytes;
  (* anyconst *)logic [31:0] f_write_addr;
  (* anyconst *)logic [31:0] f_write_bytes;
  (* anyconst *)logic [ 1:0] f_read_fault;
  (* anyconst *)logic        f_read_proto_rlast;
  (* anyconst *)logic [ 1:0] f_write_fault;
  (* anyconst *)logic [63:0] f_read_data;
  (* anyconst *)logic [63:0] f_write_data;
  (* anyconst *)logic [ 7:0] f_write_keep;
  // Per-channel stall personalities, constant per run: each address
  // handshake is stalled f_ar_stall/f_aw_stall cycles before the grant, each
  // R beat waits f_r_gap cycles before presentation, each W beat is stalled
  // f_w_stall cycles, and B waits f_b_gap cycles after the final W beat.
  // Bounding stalls to 0..3 keeps the bounded proof tractable; longer stalls
  // add no new engine states because the engine holds its registers while a
  // handshake is stalled (payload stability is checked on the first stalled
  // cycle already), and the control-event windows below still place
  // pause/clear/stream events at every possible stall cycle.
  (* anyconst *)logic [ 1:0] f_ar_stall;
  (* anyconst *)logic [ 1:0] f_r_gap;
  (* anyconst *)logic [ 1:0] f_aw_stall;
  (* anyconst *)logic [ 1:0] f_w_stall;
  (* anyconst *)logic [ 1:0] f_b_gap;
  // Control-event windows, constant per run. Both commands are presented
  // from the first active cycle until they are accepted (and are re-presented
  // after a flush): the engine has no timers, so an absolute issue phase
  // carries no contract meaning. block_new_i is held over the [start, stop)
  // window, clear_i pulses for one cycle, and the read stream is stalled over
  // its own window. Windows are bounded to the first 16 active cycles, where
  // every engine phase of a reachable burst occurs; this keeps every
  // adversarial event placement reachable while avoiding per-cycle free
  // inputs, which are what make deep bounded queries expensive.
  (* anyconst *)logic [ 3:0] f_block_start;
  (* anyconst *)logic [ 3:0] f_block_stop;
  (* anyconst *)logic        f_clear_en;
  (* anyconst *)logic [ 3:0] f_clear_at;
  (* anyconst *)logic [ 3:0] f_rdstall_start;
  (* anyconst *)logic [ 3:0] f_rdstall_stop;
  // Only the write stream last flag is free per cycle: the solver chooses a
  // correct segment end for success traces or a wrong one to exercise the
  // local write_cmd_err abort. Every check in the properties file is a
  // safety property and needs no fairness assumption.
  (* anyseq *)logic        f_write_last;

  logic [ 5:0] s_cycle_q;
  logic        s_read_done_q;
  logic        s_write_done_q;

  logic        s_r_active_q;
  logic [ 8:0] s_r_beats_q;
  logic        s_r_beat_valid_q;
  logic        s_r_first_q;
  logic [ 1:0] s_r_resp_q;
  logic        s_r_proto_rid_q;
  logic        s_r_proto_rlast_q;
  logic        s_w_active_q;
  logic [ 8:0] s_w_beats_q;
  logic        s_w_bvalid_q;
  logic        s_w_bpending_q;
  logic [ 1:0] s_w_bresp_q;
  logic        s_w_bid_bad_q;
  logic [ 1:0] s_ar_stall_q;
  logic [ 1:0] s_r_gap_q;
  logic [ 1:0] s_aw_stall_q;
  logic [ 1:0] s_w_stall_q;
  logic [ 1:0] s_b_gap_q;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  // Constrained responder: independent per-channel stall state machines
  // driven by the anyconst personalities; a burst carries one latched fault
  // personality.
  assign axi4.arready = !s_r_active_q && !s_r_beat_valid_q && (s_ar_stall_q >= f_ar_stall);
  assign axi4.rid = s_r_proto_rid_q ? 3'd1 : 3'd0;
  assign axi4.rdata = f_read_data;
  assign axi4.rresp = s_r_resp_q;
  assign axi4.rlast = (s_r_beats_q == 9'd1) || (s_r_proto_rlast_q && s_r_first_q);
  assign axi4.ruser = 1'b0;
  assign axi4.rvalid = s_r_beat_valid_q;

  assign axi4.awready     = !s_w_active_q && !s_w_bvalid_q && !s_w_bpending_q &&
                            (s_aw_stall_q >= f_aw_stall);
  assign axi4.wready = s_w_active_q && (s_w_stall_q >= f_w_stall);
  assign axi4.bid = s_w_bid_bad_q ? 3'd1 : 3'd0;
  assign axi4.bresp = s_w_bresp_q;
  assign axi4.buser = 1'b0;
  assign axi4.bvalid = s_w_bvalid_q;

  assign read_req_valid = rst_n_i && !s_read_done_q;
  assign read_addr = f_read_addr;
  assign read_bytes = f_read_bytes;
  assign read_data_ready = rst_n_i &&
                           !((s_cycle_q >= {2'd0, f_rdstall_start}) &&
                             (s_cycle_q < {2'd0, f_rdstall_stop}));
  assign write_req_valid = rst_n_i && !s_write_done_q;
  assign write_addr = f_write_addr;
  assign write_bytes = f_write_bytes;
  assign write_data_valid = rst_n_i;
  assign write_data = f_write_data;
  assign write_keep = f_write_keep;
  assign write_last = f_write_last;
  assign block_new = rst_n_i && (s_cycle_q >= {2'd0, f_block_start}) &&
                     (s_cycle_q < {2'd0, f_block_stop});
  assign clear = rst_n_i && f_clear_en && (s_cycle_q == {2'd0, f_clear_at});
  assign read_fault = f_read_fault;
  assign read_data_const = f_read_data;
  assign write_data_const = f_write_data;
  assign write_keep_const = f_write_keep;

  npu_dma u_dut (
      .clk_hp_i          (clk_i),
      .rst_hp_n_i        (rst_n_i),
      .clear_i           (clear),
      .block_new_i       (block_new),
      .pause_ack_o       (pause_ack),
      .read_req_valid_i  (read_req_valid),
      .read_req_ready_o  (read_req_ready),
      .read_addr_i       (read_addr),
      .read_bytes_i      (read_bytes),
      .read_data_valid_o (read_data_valid),
      .read_data_ready_i (read_data_ready),
      .read_data_o       (read_data),
      .read_keep_o       (read_keep),
      .read_last_o       (read_last),
      .write_req_valid_i (write_req_valid),
      .write_req_ready_o (write_req_ready),
      .write_addr_i      (write_addr),
      .write_bytes_i     (write_bytes),
      .write_data_valid_i(write_data_valid),
      .write_data_ready_o(write_data_ready),
      .write_data_i      (write_data),
      .write_keep_i      (write_keep),
      .write_last_i      (write_last),
      .write_done_o      (write_done),
      .busy_o            (busy),
      .read_busy_o       (read_busy),
      .write_busy_o      (write_busy),
      .read_bytes_o      (read_bytes_done),
      .write_bytes_o     (write_bytes_done),
      .stall_cycles_o    (stall_cycles),
      .fault_o           (fault),
      .fault_code_o      (fault_code),
      .fault_addr_o      (fault_addr),
      .fault_resp_o      (fault_resp),
      .read_cmd_err_o    (read_cmd_err),
      .write_cmd_err_o   (write_cmd_err),
      .axi4              (axi4)
  );

  assign awvalid     = axi4.awvalid;
  assign awready     = axi4.awready;
  assign awid        = axi4.awid;
  assign awaddr      = axi4.awaddr;
  assign awlen       = axi4.awlen;
  assign awsize      = axi4.awsize;
  assign awburst     = axi4.awburst;
  assign awlock      = axi4.awlock;
  assign awcache     = axi4.awcache;
  assign awprot      = axi4.awprot;
  assign awqos       = axi4.awqos;
  assign awregion    = axi4.awregion;
  assign awuser      = axi4.awuser;
  assign wvalid      = axi4.wvalid;
  assign wready      = axi4.wready;
  assign wdata       = axi4.wdata;
  assign wstrb       = axi4.wstrb;
  assign wlast       = axi4.wlast;
  assign wuser       = axi4.wuser;
  assign bvalid      = axi4.bvalid;
  assign bready      = axi4.bready;
  assign bid         = axi4.bid;
  assign bresp       = axi4.bresp;
  assign buser       = axi4.buser;
  assign arvalid     = axi4.arvalid;
  assign arready     = axi4.arready;
  assign arid        = axi4.arid;
  assign araddr      = axi4.araddr;
  assign arlen       = axi4.arlen;
  assign arsize      = axi4.arsize;
  assign arburst     = axi4.arburst;
  assign arlock      = axi4.arlock;
  assign arcache     = axi4.arcache;
  assign arprot      = axi4.arprot;
  assign arqos       = axi4.arqos;
  assign arregion    = axi4.arregion;
  assign aruser      = axi4.aruser;
  assign rvalid      = axi4.rvalid;
  assign rready      = axi4.rready;
  assign rid         = axi4.rid;
  assign rdata       = axi4.rdata;
  assign rresp       = axi4.rresp;
  assign rlast       = axi4.rlast;
  assign ruser       = axi4.ruser;
  assign rfifo_count = u_dut.s_rfifo_count_q;
  assign wfifo_count = u_dut.s_wfifo_count_q;

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
    if (!rst_n_i) begin
      s_cycle_q <= 6'd0;
    end else if (s_cycle_q != 6'h3f) begin
      s_cycle_q <= s_cycle_q + 6'd1;
    end
  end

  // Responder state. The clear_i branch is the coordinated fabric flush:
  // in-flight bursts cancel with the engine, so no residual R/B beat is ever
  // presented to a flushed receiver. A burst whose malformed beat has been
  // accepted (bad RID or early RLAST) is retired silently because the engine
  // quarantines its receiver until the flush.
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_r_active_q      <= 1'b0;
      s_r_beats_q       <= 9'd0;
      s_r_beat_valid_q  <= 1'b0;
      s_r_first_q       <= 1'b0;
      s_r_resp_q        <= AxiRespOkay;
      s_r_proto_rid_q   <= 1'b0;
      s_r_proto_rlast_q <= 1'b0;
      s_w_active_q      <= 1'b0;
      s_w_beats_q       <= 9'd0;
      s_w_bvalid_q      <= 1'b0;
      s_w_bpending_q    <= 1'b0;
      s_w_bresp_q       <= AxiRespOkay;
      s_w_bid_bad_q     <= 1'b0;
      s_ar_stall_q      <= 2'd0;
      s_r_gap_q         <= 2'd0;
      s_aw_stall_q      <= 2'd0;
      s_w_stall_q       <= 2'd0;
      s_b_gap_q         <= 2'd0;
      s_read_done_q     <= 1'b0;
      s_write_done_q    <= 1'b0;
    end else if (clear) begin
      s_r_active_q      <= 1'b0;
      s_r_beats_q       <= 9'd0;
      s_r_beat_valid_q  <= 1'b0;
      s_r_first_q       <= 1'b0;
      s_r_resp_q        <= AxiRespOkay;
      s_r_proto_rid_q   <= 1'b0;
      s_r_proto_rlast_q <= 1'b0;
      s_w_active_q      <= 1'b0;
      s_w_beats_q       <= 9'd0;
      s_w_bvalid_q      <= 1'b0;
      s_w_bpending_q    <= 1'b0;
      s_w_bresp_q       <= AxiRespOkay;
      s_w_bid_bad_q     <= 1'b0;
      s_ar_stall_q      <= 2'd0;
      s_r_gap_q         <= 2'd0;
      s_aw_stall_q      <= 2'd0;
      s_w_stall_q       <= 2'd0;
      s_b_gap_q         <= 2'd0;
      // A flushed command is offered again, so post-flush retry is covered.
      s_read_done_q     <= 1'b0;
      s_write_done_q    <= 1'b0;
    end else begin
      if (read_req_valid && read_req_ready) begin
        s_read_done_q <= 1'b1;
      end
      if (write_req_valid && write_req_ready) begin
        s_write_done_q <= 1'b1;
      end
      // Per-channel stall counters saturate above the anyconst personality.
      if (axi4.arvalid && axi4.arready) begin
        s_ar_stall_q <= 2'd0;
      end else if (axi4.arvalid && !axi4.arready && (s_ar_stall_q != 2'd3)) begin
        s_ar_stall_q <= s_ar_stall_q + 2'd1;
      end
      if (axi4.awvalid && axi4.awready) begin
        s_aw_stall_q <= 2'd0;
      end else if (axi4.awvalid && !axi4.awready && (s_aw_stall_q != 2'd3)) begin
        s_aw_stall_q <= s_aw_stall_q + 2'd1;
      end
      if (axi4.arvalid && axi4.arready) begin
        s_r_active_q <= 1'b1;
        s_r_beats_q  <= {1'b0, axi4.arlen} + 9'd1;
        s_r_first_q  <= 1'b1;
        s_r_gap_q    <= 2'd0;
        if (f_read_fault == 2'd1) begin
          s_r_resp_q <= AxiRespSlverr;
        end else if (f_read_fault == 2'd2) begin
          s_r_resp_q <= AxiRespDecerr;
        end else begin
          s_r_resp_q <= AxiRespOkay;
        end
        s_r_proto_rid_q   <= (f_read_fault == 2'd3) && !f_read_proto_rlast;
        s_r_proto_rlast_q <= (f_read_fault == 2'd3) && f_read_proto_rlast;
      end
      if (s_r_active_q && !s_r_beat_valid_q) begin
        if (s_r_gap_q >= f_r_gap) begin
          s_r_beat_valid_q <= 1'b1;
        end else begin
          s_r_gap_q <= s_r_gap_q + 2'd1;
        end
      end
      if (axi4.rvalid && axi4.rready) begin
        s_r_beat_valid_q <= 1'b0;
        s_r_first_q      <= 1'b0;
        s_r_gap_q        <= 2'd0;
        if ((s_r_beats_q == 9'd1) || axi4.rlast || s_r_proto_rid_q) begin
          s_r_active_q <= 1'b0;
          s_r_beats_q  <= 9'd0;
        end else begin
          s_r_beats_q <= s_r_beats_q - 9'd1;
        end
      end
      if (axi4.awvalid && axi4.awready) begin
        s_w_active_q <= 1'b1;
        s_w_beats_q  <= {1'b0, axi4.awlen} + 9'd1;
        s_w_stall_q  <= 2'd0;
        if (f_write_fault == 2'd1) begin
          s_w_bresp_q <= AxiRespSlverr;
        end else if (f_write_fault == 2'd2) begin
          s_w_bresp_q <= AxiRespDecerr;
        end else begin
          s_w_bresp_q <= AxiRespOkay;
        end
        s_w_bid_bad_q <= (f_write_fault == 2'd3);
      end
      if (axi4.wvalid && !axi4.wready && (s_w_stall_q != 2'd3)) begin
        s_w_stall_q <= s_w_stall_q + 2'd1;
      end
      if (axi4.wvalid && axi4.wready) begin
        s_w_stall_q <= 2'd0;
        if (s_w_beats_q == 9'd1) begin
          s_w_active_q   <= 1'b0;
          s_w_beats_q    <= 9'd0;
          s_w_bpending_q <= 1'b1;
          s_b_gap_q      <= 2'd0;
        end else begin
          s_w_beats_q <= s_w_beats_q - 9'd1;
        end
      end
      if (s_w_bpending_q) begin
        if (s_b_gap_q >= f_b_gap) begin
          s_w_bpending_q <= 1'b0;
          s_w_bvalid_q   <= 1'b1;
        end else begin
          s_b_gap_q <= s_b_gap_q + 2'd1;
        end
      end
      if (axi4.bvalid && axi4.bready) begin
        s_w_bvalid_q <= 1'b0;
      end
    end
  end

endmodule
