// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// NPU-P3 production AXI4 data-plane engine (docs/ip/npu.md "AXI4 data plane").
// 32-bit addresses, 64-bit data, ID width 3 fixed to zero, USER fixed to
// zero, INCR bursts of 1..16 beats, at most one outstanding read and one
// outstanding write, which may overlap. AxCACHE/AxLOCK/AxPROT/AxQOS/AxREGION
// are always zero.
//
// Burst planning: bulk uses full 64-bit beats; leading/trailing read edges
// use the largest naturally aligned narrow size (1/2/4 bytes) so reads never
// overfetch; write edges are full-width aligned beats whose scheduler-built
// WSTRB covers only addressed lanes; no burst crosses a 4 KiB page.
//
// Reservation: ARVALID is presented only when the 16-entry receive FIFO is
// empty, so an accepted read burst always completes regardless of stream
// backpressure. A write burst gathers its complete payload into the 16-entry
// write FIFO before AWVALID; W beats are driven only after the AW handshake.
//
// Command rejection: a zero byte count or an addr+bytes wrap is refused
// combinationally (ready low, cmd_err high while presented) and is never
// accepted; only bus-visible events raise fault_o with codes 4 (AXI_READ),
// 5 (AXI_WRITE) or 6 (AXI_PROTOCOL), with same-cycle priority
// AXI_PROTOCOL > AXI_READ > AXI_WRITE. fault_o is sticky until clear_i. After
// a fault no new burst is presented and accepted obligations drain; a
// malformed R/B response is quarantined (its receiver stops) until clear_i.
// A write payload beat whose write_last_i does not match the planned segment
// end pulses write_cmd_err_o and aborts the segment locally without any AXI
// fault.
//
// Pause: block_new_i stops command acceptance, new burst presentation and
// payload gathering at register-safe boundaries. Presented-but-unaccepted
// ARVALID/AWVALID stay asserted with stable payload and accepted transfers
// drain. pause_ack_o asserts while block_new_i is held once no AR-accepted
// read and no AW-accepted write (W/B) obligation remains; it does not require
// empty command slots or busy_o low, and unblocking resumes identical work.
//
// Counters are 64-bit saturating and clear on reset and clear_i.
// read_bytes_o counts the addressed lanes of every accepted R beat, including
// beats of error-response bursts. write_bytes_o counts the accepted WSTRB
// bytes of every W beat, including bursts whose B response errors (erroneous
// traffic stays visible). stall_cycles_o counts cycles with a ready work item
// blocked on an AXI handshake (AR/AW/W backpressure or a pending R/B
// response). fault_addr_o records the failing beat address (for a write
// response, the final W beat of the failed burst) and fault_resp_o the AXI
// response bits.
module npu_dma (
    input  logic                 clk_hp_i,
    input  logic                 rst_hp_n_i,
    input  logic                 clear_i,
    input  logic                 block_new_i,
    output logic                 pause_ack_o,
    // read segment command
    input  logic                 read_req_valid_i,
    output logic                 read_req_ready_o,
    input  logic          [31:0] read_addr_i,
    input  logic          [31:0] read_bytes_i,
    // read data stream
    output logic                 read_data_valid_o,
    input  logic                 read_data_ready_i,
    output logic          [63:0] read_data_o,
    output logic          [ 7:0] read_keep_o,
    output logic                 read_last_o,
    // write segment command
    input  logic                 write_req_valid_i,
    output logic                 write_req_ready_o,
    input  logic          [31:0] write_addr_i,
    input  logic          [31:0] write_bytes_i,
    // write payload stream
    input  logic                 write_data_valid_i,
    output logic                 write_data_ready_o,
    input  logic          [63:0] write_data_i,
    input  logic          [ 7:0] write_keep_i,
    input  logic                 write_last_i,
    output logic                 write_done_o,
    // status
    output logic                 busy_o,
    output logic                 read_busy_o,
    output logic                 write_busy_o,
    output logic          [63:0] read_bytes_o,
    output logic          [63:0] write_bytes_o,
    output logic          [63:0] stall_cycles_o,
    output logic                 fault_o,
    output logic          [ 3:0] fault_code_o,
    output logic          [31:0] fault_addr_o,
    output logic          [ 1:0] fault_resp_o,
    output logic                 read_cmd_err_o,
    output logic                 write_cmd_err_o,
           axi4_if.master        axi4
);
  localparam int unsigned FifoDepth = 16;
  localparam logic [3:0] FaultAxiRead = 4'd4;
  localparam logic [3:0] FaultAxiWrite = 4'd5;
  localparam logic [3:0] FaultAxiProtocol = 4'd6;

  typedef enum logic [1:0] {
    ReadIdle,
    ReadPlan,
    ReadAddress,
    ReadData
  } read_state_e;
  typedef enum logic [2:0] {
    WriteIdle,
    WritePlan,
    WriteGather,
    WriteStaged,
    WriteAddress,
    WriteData,
    WriteResponse
  } write_state_e;

  read_state_e         s_read_state_q;
  write_state_e        s_write_state_q;

  logic                s_read_cmd_illegal;
  logic                s_read_cmd_accept;
  logic         [31:0] s_read_addr_q;
  logic         [31:0] s_read_bytes_left_q;
  logic         [31:0] s_read_burst_addr_q;
  logic         [ 4:0] s_read_burst_beats_q;
  logic         [ 2:0] s_read_burst_size_q;
  logic         [ 7:0] s_read_burst_bytes_q;
  logic                s_read_burst_last_q;
  logic         [ 4:0] s_read_beats_left_q;
  logic         [31:0] s_read_beat_addr_q;
  logic                s_read_proto_fault_q;
  logic         [ 4:0] s_read_plan_beats;
  logic         [ 2:0] s_read_plan_size;
  logic         [ 7:0] s_read_plan_bytes;
  logic         [ 3:0] s_read_beat_bytes;
  logic         [ 7:0] s_read_beat_keep;
  logic                s_read_last_expected;
  logic                s_read_proto_error;
  logic                s_read_rsp_accept;
  logic                s_rfifo_push;
  logic                s_rfifo_pop;

  logic                s_write_cmd_illegal;
  logic                s_write_cmd_accept;
  logic         [31:0] s_write_addr_q;
  logic         [31:0] s_write_bytes_left_q;
  logic         [31:0] s_write_burst_addr_q;
  logic         [ 4:0] s_write_burst_beats_q;
  logic         [ 7:0] s_write_burst_bytes_q;
  logic                s_write_burst_last_q;
  logic         [ 4:0] s_write_beats_left_q;
  logic         [31:0] s_write_beat_addr_q;
  logic         [ 4:0] s_write_gather_left_q;
  logic                s_write_proto_fault_q;
  logic         [31:0] s_write_plan_addr;
  logic         [ 4:0] s_write_plan_beats;
  logic         [ 7:0] s_write_plan_bytes;
  logic                s_write_plan_last;
  logic                s_write_gather_accept;
  logic                s_write_gather_last;
  logic                s_write_stream_err;
  logic                s_write_w_accept;
  logic                s_write_rsp_accept;
  logic                s_wfifo_push;
  logic                s_wfifo_pop;

  logic         [63:0] s_rfifo_data_q        [FifoDepth];
  logic         [ 7:0] s_rfifo_keep_q        [FifoDepth];
  logic                s_rfifo_last_q        [FifoDepth];
  logic         [ 3:0] s_rfifo_rptr_q;
  logic         [ 3:0] s_rfifo_wptr_q;
  logic         [ 4:0] s_rfifo_count_q;
  logic         [63:0] s_wfifo_data_q        [FifoDepth];
  logic         [ 7:0] s_wfifo_keep_q        [FifoDepth];
  logic         [ 3:0] s_wfifo_rptr_q;
  logic         [ 3:0] s_wfifo_wptr_q;
  logic         [ 4:0] s_wfifo_count_q;

  logic                s_fault_q;
  logic         [ 3:0] s_fault_code_q;
  logic         [31:0] s_fault_addr_q;
  logic         [ 1:0] s_fault_resp_q;
  logic                s_evt_proto_read;
  logic                s_evt_axi_read;
  logic                s_evt_proto_write;
  logic                s_evt_axi_write;

  logic         [63:0] s_read_bytes_q;
  logic         [63:0] s_write_bytes_q;
  logic         [63:0] s_stall_cycles_q;
  logic                s_stall_event;

  function automatic logic [3:0] count_ones(input logic [7:0] value_i);
    logic [3:0] count;
    begin
      count = 4'd0;
      for (int unsigned lane = 0; lane < 8; lane++) begin
        count = count + {3'd0, value_i[lane]};
      end
      return count;
    end
  endfunction

  function automatic logic [63:0] saturating_add(input logic [63:0] value_i,
                                                 input logic [3:0] increment_i);
    logic [64:0] widened;
    begin
      widened = {1'b0, value_i} + {61'd0, increment_i};
      if (widened[64]) begin
        return 64'hffff_ffff_ffff_ffff;
      end
      return widened[63:0];
    end
  endfunction

  assign s_read_cmd_illegal = (read_bytes_i == 32'd0) ||
                              ({1'b0, read_addr_i} + {1'b0, read_bytes_i} > 33'h1_0000_0000);
  assign read_req_ready_o = (s_read_state_q == ReadIdle) && !s_read_cmd_illegal && !s_fault_q &&
                            !block_new_i && !clear_i;
  assign read_cmd_err_o = read_req_valid_i && s_read_cmd_illegal && !clear_i;
  assign s_read_cmd_accept = read_req_valid_i && read_req_ready_o;

  // Read burst plan: full 64-bit beats in the bulk, the largest naturally
  // aligned narrow transfer at the leading/trailing edges, never crossing a
  // 4 KiB page, never fetching bytes outside the segment.
  always_comb begin
    logic [12:0] s_bytes_to_4k;
    logic [12:0] s_beats_to_4k;
    logic [31:0] s_full_beats;
    logic [ 3:0] s_to_alignment;
    s_bytes_to_4k     = 13'd4096 - {1'b0, s_read_addr_q[11:0]};
    s_beats_to_4k     = s_bytes_to_4k >> 3;
    s_full_beats      = s_read_bytes_left_q >> 3;
    s_to_alignment    = 4'd8 - {1'b0, s_read_addr_q[2:0]};
    s_read_plan_beats = 5'd1;
    s_read_plan_size  = 3'd0;
    s_read_plan_bytes = 8'd1;
    if ((s_read_addr_q[2:0] == 3'd0) && (s_read_bytes_left_q >= 32'd8)) begin
      s_read_plan_beats = (s_full_beats > 32'd16) ? 5'd16 : s_full_beats[4:0];
      if (s_beats_to_4k < {8'd0, s_read_plan_beats}) begin
        s_read_plan_beats = s_beats_to_4k[4:0];
      end
      s_read_plan_size  = 3'd3;
      s_read_plan_bytes = {s_read_plan_beats, 3'b000};
    end else if ((s_read_addr_q[1:0] == 2'd0) && (s_to_alignment >= 4'd4) &&
                 (s_read_bytes_left_q >= 32'd4)) begin
      s_read_plan_size  = 3'd2;
      s_read_plan_bytes = 8'd4;
    end else if ((s_read_addr_q[0] == 1'b0) && (s_to_alignment >= 4'd2) &&
                 (s_read_bytes_left_q >= 32'd2)) begin
      s_read_plan_size  = 3'd1;
      s_read_plan_bytes = 8'd2;
    end
  end

  assign s_read_beat_bytes = 4'd1 << s_read_burst_size_q;
  assign s_read_beat_keep = (8'hff >> (4'd8 - s_read_beat_bytes)) << s_read_beat_addr_q[2:0];
  assign s_read_last_expected = s_read_beats_left_q == 5'd1;
  assign s_read_proto_error = (axi4.rid != '0) || (axi4.rlast != s_read_last_expected);
  assign s_read_rsp_accept = axi4.rvalid && axi4.rready;

  assign axi4.arid = '0;
  assign axi4.araddr = s_read_burst_addr_q;
  assign axi4.arlen = {3'd0, s_read_burst_beats_q} - 8'd1;
  assign axi4.arsize = s_read_burst_size_q;
  assign axi4.arburst = 2'b01;
  assign axi4.arlock = 1'b0;
  assign axi4.arcache = 4'd0;
  assign axi4.arprot = 3'd0;
  assign axi4.arqos = 4'd0;
  assign axi4.arregion = 4'd0;
  assign axi4.aruser = '0;
  assign axi4.arvalid = (s_read_state_q == ReadAddress) && !clear_i;
  assign axi4.rready = (s_read_state_q == ReadData) && !s_read_proto_fault_q && !clear_i;

  assign s_rfifo_push = s_read_rsp_accept && !s_read_proto_error;
  assign s_rfifo_pop = read_data_valid_o && read_data_ready_i;
  assign read_data_valid_o = (s_rfifo_count_q != 5'd0) && !clear_i;
  assign read_data_o = s_rfifo_data_q[s_rfifo_rptr_q];
  assign read_keep_o = s_rfifo_keep_q[s_rfifo_rptr_q];
  assign read_last_o = s_rfifo_last_q[s_rfifo_rptr_q];

  assign s_write_cmd_illegal = (write_bytes_i == 32'd0) ||
                               ({1'b0, write_addr_i} + {1'b0, write_bytes_i} > 33'h1_0000_0000);
  assign write_req_ready_o = (s_write_state_q == WriteIdle) && !s_write_cmd_illegal &&
                             !s_fault_q && !block_new_i && !clear_i;
  assign write_cmd_err_o = (write_req_valid_i && s_write_cmd_illegal && !clear_i) ||
                           s_write_stream_err;
  assign s_write_cmd_accept = write_req_valid_i && write_req_ready_o;

  // Write burst plan: the address-aligned beat span of the remaining segment,
  // at most 16 beats, never crossing a 4 KiB page. Byte lanes outside the
  // segment are left to the scheduler-built WSTRB.
  always_comb begin
    logic [12:0] s_bytes_to_4k;
    logic [12:0] s_beats_to_4k;
    logic [31:0] s_span_beats;
    logic [31:0] s_burst_room;
    s_write_plan_addr  = {s_write_addr_q[31:3], 3'b000};
    s_bytes_to_4k      = 13'd4096 - {1'b0, s_write_plan_addr[11:0]};
    s_beats_to_4k      = s_bytes_to_4k >> 3;
    s_span_beats       = ({29'd0, s_write_addr_q[2:0]} + s_write_bytes_left_q + 32'd7) >> 3;
    s_write_plan_beats = (s_span_beats > 32'd16) ? 5'd16 : s_span_beats[4:0];
    if (s_beats_to_4k < {8'd0, s_write_plan_beats}) begin
      s_write_plan_beats = s_beats_to_4k[4:0];
    end
    s_burst_room       = ({24'd0, s_write_plan_beats, 3'b000} - {29'd0, s_write_addr_q[2:0]});
    s_write_plan_last  = s_write_bytes_left_q <= s_burst_room;
    s_write_plan_bytes = s_write_plan_last ? s_write_bytes_left_q[7:0] : s_burst_room[7:0];
  end

  assign axi4.awid = '0;
  assign axi4.awaddr = s_write_burst_addr_q;
  assign axi4.awlen = {3'd0, s_write_burst_beats_q} - 8'd1;
  assign axi4.awsize = 3'd3;
  assign axi4.awburst = 2'b01;
  assign axi4.awlock = 1'b0;
  assign axi4.awcache = 4'd0;
  assign axi4.awprot = 3'd0;
  assign axi4.awqos = 4'd0;
  assign axi4.awregion = 4'd0;
  assign axi4.awuser = '0;
  assign axi4.awvalid = (s_write_state_q == WriteAddress) && !clear_i;
  assign axi4.wdata = s_wfifo_data_q[s_wfifo_rptr_q];
  assign axi4.wstrb = s_wfifo_keep_q[s_wfifo_rptr_q];
  assign axi4.wlast = s_write_beats_left_q == 5'd1;
  assign axi4.wuser = '0;
  assign axi4.wvalid = (s_write_state_q == WriteData) && (s_wfifo_count_q != 5'd0) && !clear_i;
  assign axi4.bready = (s_write_state_q == WriteResponse) && !s_write_proto_fault_q && !clear_i;
  assign s_write_w_accept = axi4.wvalid && axi4.wready;
  assign s_write_rsp_accept = axi4.bvalid && axi4.bready;

  assign write_data_ready_o = (s_write_state_q == WriteGather) && !block_new_i && !s_fault_q &&
                              !clear_i;
  assign s_write_gather_accept = write_data_valid_i && write_data_ready_o;
  assign s_write_gather_last = (s_write_gather_left_q == 5'd1) && s_write_burst_last_q;
  assign s_write_stream_err = s_write_gather_accept && (write_last_i != s_write_gather_last);
  assign s_wfifo_push = s_write_gather_accept && !s_write_stream_err;
  assign s_wfifo_pop = s_write_w_accept;
  assign write_done_o = s_write_rsp_accept && (axi4.bid == '0) && (axi4.bresp == 2'b00) &&
                        s_write_burst_last_q;

  assign s_evt_proto_read = axi4.rvalid && !clear_i && !s_read_proto_fault_q &&
                            ((s_read_state_q != ReadData) || s_read_proto_error);
  assign s_evt_axi_read = s_read_rsp_accept && (axi4.rresp != 2'b00);
  assign s_evt_proto_write = axi4.bvalid && !clear_i && !s_write_proto_fault_q &&
                             ((s_write_state_q != WriteResponse) || (axi4.bid != '0));
  assign s_evt_axi_write = s_write_rsp_accept && (axi4.bresp != 2'b00);

  assign s_stall_event = (axi4.arvalid && !axi4.arready) || (axi4.awvalid && !axi4.awready) ||
                         (axi4.wvalid && !axi4.wready) ||
                         ((s_read_state_q == ReadData) && !axi4.rvalid && !s_read_proto_fault_q) ||
                         ((s_write_state_q == WriteResponse) && !axi4.bvalid &&
                          !s_write_proto_fault_q);

  assign read_busy_o = s_read_state_q != ReadIdle;
  assign write_busy_o = s_write_state_q != WriteIdle;
  assign busy_o = read_busy_o || write_busy_o;
  // Zero accepted obligations: a presented-but-unaccepted AR/AW does not
  // block the acknowledge, an AR-accepted read or AW-accepted write does.
  assign pause_ack_o = block_new_i && (s_read_state_q != ReadData) &&
                       (s_write_state_q != WriteData) && (s_write_state_q != WriteResponse);

  assign read_bytes_o = s_read_bytes_q;
  assign write_bytes_o = s_write_bytes_q;
  assign stall_cycles_o = s_stall_cycles_q;
  assign fault_o = s_fault_q;
  assign fault_code_o = s_fault_code_q;
  assign fault_addr_o = s_fault_addr_q;
  assign fault_resp_o = s_fault_resp_q;

  always_ff @(posedge clk_hp_i or negedge rst_hp_n_i) begin
    if (!rst_hp_n_i) begin
      s_read_state_q        <= ReadIdle;
      s_read_addr_q         <= '0;
      s_read_bytes_left_q   <= '0;
      s_read_burst_addr_q   <= '0;
      s_read_burst_beats_q  <= '0;
      s_read_burst_size_q   <= '0;
      s_read_burst_bytes_q  <= '0;
      s_read_burst_last_q   <= 1'b0;
      s_read_beats_left_q   <= '0;
      s_read_beat_addr_q    <= '0;
      s_read_proto_fault_q  <= 1'b0;
      s_write_state_q       <= WriteIdle;
      s_write_addr_q        <= '0;
      s_write_bytes_left_q  <= '0;
      s_write_burst_addr_q  <= '0;
      s_write_burst_beats_q <= '0;
      s_write_burst_bytes_q <= '0;
      s_write_burst_last_q  <= 1'b0;
      s_write_beats_left_q  <= '0;
      s_write_beat_addr_q   <= '0;
      s_write_gather_left_q <= '0;
      s_write_proto_fault_q <= 1'b0;
      s_rfifo_rptr_q        <= '0;
      s_rfifo_wptr_q        <= '0;
      s_rfifo_count_q       <= '0;
      s_wfifo_rptr_q        <= '0;
      s_wfifo_wptr_q        <= '0;
      s_wfifo_count_q       <= '0;
      s_fault_q             <= 1'b0;
      s_fault_code_q        <= '0;
      s_fault_addr_q        <= '0;
      s_fault_resp_q        <= '0;
      s_read_bytes_q        <= '0;
      s_write_bytes_q       <= '0;
      s_stall_cycles_q      <= '0;
    end else if (clear_i) begin
      // Coordinated fabric flush: in-flight state cancels together with the
      // fabric; afterwards the engine is clean, idle and fault-free.
      s_read_state_q        <= ReadIdle;
      s_read_proto_fault_q  <= 1'b0;
      s_write_state_q       <= WriteIdle;
      s_write_proto_fault_q <= 1'b0;
      s_rfifo_rptr_q        <= '0;
      s_rfifo_wptr_q        <= '0;
      s_rfifo_count_q       <= '0;
      s_wfifo_rptr_q        <= '0;
      s_wfifo_wptr_q        <= '0;
      s_wfifo_count_q       <= '0;
      s_fault_q             <= 1'b0;
      s_fault_code_q        <= '0;
      s_fault_addr_q        <= '0;
      s_fault_resp_q        <= '0;
      s_read_bytes_q        <= '0;
      s_write_bytes_q       <= '0;
      s_stall_cycles_q      <= '0;
    end else begin
      unique case (s_read_state_q)
        ReadIdle: begin
          if (s_read_cmd_accept) begin
            s_read_addr_q       <= read_addr_i;
            s_read_bytes_left_q <= read_bytes_i;
            s_read_state_q      <= ReadPlan;
          end
        end
        ReadPlan: begin
          // Reserve receive storage for the whole burst before presenting AR.
          if (!block_new_i && !s_fault_q && (s_rfifo_count_q == 5'd0)) begin
            s_read_burst_addr_q  <= s_read_addr_q;
            s_read_burst_beats_q <= s_read_plan_beats;
            s_read_burst_size_q  <= s_read_plan_size;
            s_read_burst_bytes_q <= s_read_plan_bytes;
            s_read_burst_last_q  <= {24'd0, s_read_plan_bytes} == s_read_bytes_left_q;
            s_read_beats_left_q  <= s_read_plan_beats;
            s_read_beat_addr_q   <= s_read_addr_q;
            s_read_proto_fault_q <= 1'b0;
            s_read_state_q       <= ReadAddress;
          end
        end
        ReadAddress: begin
          if (axi4.arvalid && axi4.arready) begin
            s_read_state_q <= ReadData;
          end
        end
        ReadData: begin
          if (s_read_rsp_accept) begin
            if (s_read_proto_error) begin
              // Malformed responses are quarantined until the flush.
              s_read_proto_fault_q <= 1'b1;
            end else if (s_read_beats_left_q == 5'd1) begin
              s_read_bytes_left_q <= s_read_bytes_left_q - {24'd0, s_read_burst_bytes_q};
              s_read_addr_q       <= s_read_burst_addr_q + {24'd0, s_read_burst_bytes_q};
              if (s_fault_q || s_evt_axi_read || s_read_burst_last_q) begin
                s_read_state_q <= ReadIdle;
              end else begin
                s_read_state_q <= ReadPlan;
              end
            end else begin
              s_read_beats_left_q <= s_read_beats_left_q - 1'b1;
              s_read_beat_addr_q  <= s_read_beat_addr_q + {28'd0, s_read_beat_bytes};
            end
          end
        end
        default: s_read_state_q <= ReadIdle;
      endcase

      unique case (s_write_state_q)
        WriteIdle: begin
          if (s_write_cmd_accept) begin
            s_write_addr_q       <= write_addr_i;
            s_write_bytes_left_q <= write_bytes_i;
            s_write_state_q      <= WritePlan;
          end
        end
        WritePlan: begin
          s_write_burst_addr_q  <= s_write_plan_addr;
          s_write_burst_beats_q <= s_write_plan_beats;
          s_write_burst_bytes_q <= s_write_plan_bytes;
          s_write_burst_last_q  <= s_write_plan_last;
          s_write_beats_left_q  <= s_write_plan_beats;
          s_write_gather_left_q <= s_write_plan_beats;
          s_write_beat_addr_q   <= s_write_plan_addr;
          s_write_proto_fault_q <= 1'b0;
          s_write_state_q       <= WriteGather;
        end
        WriteGather: begin
          // Reserve the complete write payload before presenting AW.
          if (s_write_stream_err) begin
            // Locally rejected segment: drop the partial payload.
            s_write_state_q <= WriteIdle;
            s_wfifo_rptr_q  <= '0;
            s_wfifo_wptr_q  <= '0;
            s_wfifo_count_q <= '0;
          end else if (s_write_gather_accept) begin
            if (s_write_gather_left_q == 5'd1) begin
              s_write_state_q <= WriteStaged;
            end else begin
              s_write_gather_left_q <= s_write_gather_left_q - 1'b1;
            end
          end
        end
        WriteStaged: begin
          if (!block_new_i && !s_fault_q) begin
            s_write_state_q <= WriteAddress;
          end
        end
        WriteAddress: begin
          if (axi4.awvalid && axi4.awready) begin
            s_write_state_q <= WriteData;
          end
        end
        WriteData: begin
          if (s_write_w_accept) begin
            if (s_write_beats_left_q == 5'd1) begin
              s_write_state_q <= WriteResponse;
            end else begin
              s_write_beats_left_q <= s_write_beats_left_q - 1'b1;
              s_write_beat_addr_q  <= s_write_beat_addr_q + 32'd8;
            end
          end
        end
        WriteResponse: begin
          if (s_write_rsp_accept) begin
            if (axi4.bid != '0) begin
              // Malformed responses are quarantined until the flush.
              s_write_proto_fault_q <= 1'b1;
            end else begin
              s_write_bytes_left_q <= s_write_bytes_left_q - {24'd0, s_write_burst_bytes_q};
              s_write_addr_q       <= s_write_burst_addr_q + {24'd0, s_write_burst_beats_q, 3'b000};
              if (s_fault_q || s_evt_axi_write || s_write_burst_last_q) begin
                s_write_state_q <= WriteIdle;
              end else begin
                s_write_state_q <= WritePlan;
              end
            end
          end
        end
        default: s_write_state_q <= WriteIdle;
      endcase

      if (s_rfifo_push) begin
        s_rfifo_data_q[s_rfifo_wptr_q] <= axi4.rdata;
        s_rfifo_keep_q[s_rfifo_wptr_q] <= s_read_beat_keep;
        s_rfifo_last_q[s_rfifo_wptr_q] <= (s_read_beats_left_q == 5'd1) && s_read_burst_last_q;
        s_rfifo_wptr_q                 <= s_rfifo_wptr_q + 1'b1;
      end
      if (s_rfifo_pop) begin
        s_rfifo_rptr_q <= s_rfifo_rptr_q + 1'b1;
      end
      unique case ({
        s_rfifo_push, s_rfifo_pop
      })
        2'b10: s_rfifo_count_q <= s_rfifo_count_q + 1'b1;
        2'b01: s_rfifo_count_q <= s_rfifo_count_q - 1'b1;
        default: begin
        end
      endcase

      if (s_wfifo_push) begin
        s_wfifo_data_q[s_wfifo_wptr_q] <= write_data_i;
        s_wfifo_keep_q[s_wfifo_wptr_q] <= write_keep_i;
        s_wfifo_wptr_q                 <= s_wfifo_wptr_q + 1'b1;
      end
      if (s_wfifo_pop) begin
        s_wfifo_rptr_q <= s_wfifo_rptr_q + 1'b1;
      end
      unique case ({
        s_wfifo_push, s_wfifo_pop
      })
        2'b10: s_wfifo_count_q <= s_wfifo_count_q + 1'b1;
        2'b01: s_wfifo_count_q <= s_wfifo_count_q - 1'b1;
        default: begin
        end
      endcase

      if (!s_fault_q) begin
        // Deterministic first-fault priority: AXI_PROTOCOL, AXI_READ, AXI_WRITE.
        if (s_evt_proto_read || s_evt_proto_write) begin
          s_fault_q      <= 1'b1;
          s_fault_code_q <= FaultAxiProtocol;
          s_fault_addr_q <= s_evt_proto_read ? s_read_beat_addr_q : s_write_beat_addr_q;
          s_fault_resp_q <= s_evt_proto_read ? axi4.rresp : axi4.bresp;
        end else if (s_evt_axi_read) begin
          s_fault_q      <= 1'b1;
          s_fault_code_q <= FaultAxiRead;
          s_fault_addr_q <= s_read_beat_addr_q;
          s_fault_resp_q <= axi4.rresp;
        end else if (s_evt_axi_write) begin
          s_fault_q      <= 1'b1;
          s_fault_code_q <= FaultAxiWrite;
          s_fault_addr_q <= s_write_beat_addr_q;
          s_fault_resp_q <= axi4.bresp;
        end
      end

      if (s_read_rsp_accept) begin
        s_read_bytes_q <= saturating_add(s_read_bytes_q, count_ones(s_read_beat_keep));
      end
      if (s_write_w_accept) begin
        s_write_bytes_q <= saturating_add(s_write_bytes_q, count_ones(axi4.wstrb));
      end
      if (s_stall_event && (s_stall_cycles_q != 64'hffff_ffff_ffff_ffff)) begin
        s_stall_cycles_q <= s_stall_cycles_q + 1'b1;
      end
    end
  end

`ifndef SV_ASSRT_DISABLE
  logic s_aw_wait_q;
  logic s_ar_wait_q;
  logic s_w_wait_q;
  logic s_r_wait_q;
  logic s_b_wait_q;
  logic s_read_outstanding_q;
  logic s_write_outstanding_q;
  logic s_write_aw_accepted_q;
  logic s_pause_ack_q;
  logic s_arvalid_q;
  logic s_awvalid_q;
  logic s_reset_seen_q;

  always_ff @(posedge clk_hp_i or negedge rst_hp_n_i) begin
    if (!rst_hp_n_i) begin
      s_aw_wait_q           <= 1'b0;
      s_ar_wait_q           <= 1'b0;
      s_w_wait_q            <= 1'b0;
      s_r_wait_q            <= 1'b0;
      s_b_wait_q            <= 1'b0;
      s_read_outstanding_q  <= 1'b0;
      s_write_outstanding_q <= 1'b0;
      s_write_aw_accepted_q <= 1'b0;
      s_pause_ack_q         <= 1'b0;
      s_arvalid_q           <= 1'b0;
      s_awvalid_q           <= 1'b0;
      s_reset_seen_q        <= 1'b1;
    end else begin
      s_reset_seen_q <= 1'b0;
      s_pause_ack_q  <= pause_ack_o;
      s_arvalid_q    <= axi4.arvalid;
      s_awvalid_q    <= axi4.awvalid;
      if (clear_i) begin
        s_aw_wait_q           <= 1'b0;
        s_ar_wait_q           <= 1'b0;
        s_w_wait_q            <= 1'b0;
        s_r_wait_q            <= 1'b0;
        s_b_wait_q            <= 1'b0;
        s_read_outstanding_q  <= 1'b0;
        s_write_outstanding_q <= 1'b0;
        s_write_aw_accepted_q <= 1'b0;
      end else begin
        s_aw_wait_q <= axi4.awvalid && !axi4.awready;
        s_ar_wait_q <= axi4.arvalid && !axi4.arready;
        s_w_wait_q  <= axi4.wvalid && !axi4.wready;
        s_r_wait_q  <= axi4.rvalid && !axi4.rready;
        s_b_wait_q  <= axi4.bvalid && !axi4.bready;
        if (axi4.arvalid && axi4.arready) begin
          s_read_outstanding_q <= 1'b1;
        end else if (s_read_rsp_accept && (s_read_beats_left_q == 5'd1)) begin
          s_read_outstanding_q <= 1'b0;
        end
        if (axi4.awvalid && axi4.awready) begin
          s_write_outstanding_q <= 1'b1;
          s_write_aw_accepted_q <= 1'b1;
        end
        if (s_write_rsp_accept) begin
          s_write_outstanding_q <= 1'b0;
        end
        if (s_write_w_accept && (s_write_beats_left_q == 5'd1)) begin
          s_write_aw_accepted_q <= 1'b0;
        end
      end
      // VALID payloads stay stable through any stall; only the coordinated
      // fabric flush may invalidate a presented transaction.
      if (s_aw_wait_q) begin
        assert ((axi4.awvalid && $stable({axi4.awaddr, axi4.awlen, axi4.awsize})) || clear_i);
      end
      if (s_ar_wait_q) begin
        assert ((axi4.arvalid && $stable({axi4.araddr, axi4.arlen, axi4.arsize})) || clear_i);
      end
      if (s_w_wait_q) begin
        assert ((axi4.wvalid && $stable({axi4.wdata, axi4.wstrb, axi4.wlast})) || clear_i);
      end
      if (s_r_wait_q) begin
        assert ((axi4.rvalid && $stable({axi4.rid, axi4.rdata, axi4.rresp, axi4.rlast})) ||
                clear_i);
      end
      if (s_b_wait_q) begin
        assert ((axi4.bvalid && $stable({axi4.bid, axi4.bresp})) || clear_i);
      end
      // W is only ever driven after its AW handshake.
      if (axi4.wvalid) begin
        assert (s_write_aw_accepted_q);
      end
      // At most one outstanding transaction per direction.
      if (axi4.arvalid && axi4.arready) begin
        assert (!s_read_outstanding_q);
      end
      if (axi4.awvalid && axi4.awready) begin
        assert (!s_write_outstanding_q);
      end
      // No new AR/AW presentation begins while the pause is acknowledged.
      if (s_pause_ack_q && !s_arvalid_q) begin
        assert (!axi4.arvalid);
      end
      if (s_pause_ack_q && !s_awvalid_q) begin
        assert (!axi4.awvalid);
      end
      // Address valids stay low out of reset.
      if (s_reset_seen_q) begin
        assert (!axi4.arvalid && !axi4.awvalid && !axi4.wvalid);
      end
      // Reserved storage can never overflow.
      if (s_rfifo_push) begin
        assert (s_rfifo_count_q < 5'd16);
      end
      if (s_wfifo_push) begin
        assert (s_wfifo_count_q < 5'd16);
      end
    end
  end
`endif
endmodule
