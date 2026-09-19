// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// NPU-P3 job scheduler: transport ownership for one validated descriptor at a
// time, the per-job PERF counters, the no-progress watchdog and the
// transport-level lifecycle discipline (docs/ip/npu.md "Job submission and
// ordering", "Abort, quiesce, reset and flush", counter and watchdog tables).
//
// Transport phases per descriptor: packed weights are streamed through the
// npu_dma read channel into the W banks (pack write port; the compiler
// pre-packs W, so the load is a direct bank fill in 8192-byte chunks
// alternating halves), parameters are streamed into the parameter region in
// bounded 128-byte group chunks, then for each output position the receptive
// field is gathered into a raw half as contiguous input-channel runs per
// kernel position (out-of-range padding is synthesized locally with the input
// zero point; segments are bounded by the channel run and the 1024-element
// pack chunk), packed through npu_patch_packer into the A banks, and stored.
//
// P3 transport-only content rule (reviewable scaffolding, removed at P4 when
// the compute wiring lands): since the MAC/vector/requantizer datapath is not
// wired at P3, the output staging half of a position is filled with a
// byte-exact echo of the gathered bytes: output byte (oy, ox, c) is the
// gather byte of position (oy, ox) at gather index g = c mod G, where G is
// the per-position gather length (kernel positions times input channels in
// the kh,kw,cin reduction order; H*W whole-input positions for
// GLOBAL_AVERAGE_POOL; one kernel position for ADD/CLAMP/FC). The position
// staging is drained to OUTPUT_BASE + oy*OUTPUT_ROW_BYTES + ox*Cout as Cout
// contiguous bytes. This exercises gather -> pack -> staging -> store
// end-to-end with byte-checkable content; it is NOT inference (the shell
// keeps EXECUTION_READY=0 and no numerical claim is made).
//
// K_SLICE is validated by the decoder but does not schedule P3 transport:
// gather/pack chunks are bounded by the packer row limit and the raw half
// capacity; the compute reduction schedule arrives with P4.
//
// Ordering: a descriptor retires only after the final write command of its
// last position reports a successful B response (write_done_i); the next
// descriptor is accepted only after retirement. stop_i (abort/quiesce/
// resource reset) finishes the current DMA segment (a read runs out through
// the stream; a write chunk of at most one 16-beat burst is completed and
// drained), starts no new segment, and reaches drained_o only with the DMA
// idle, the packer idle and no residue queued. A DMA fault escapes any stream
// wait immediately and quarantines the segment. Pause (block_new_i) starts no
// new bus/internal work, retains presented VALID, keeps draining accepted
// read data, and acknowledges with zero accepted obligations (pause_ok_o);
// pause cycles are excluded from the watchdog and from ACTIVE_CYCLES.
//
// P3 truthfulness: USEFUL_MACS, LOCAL_BANK_STALL_CYCLES and
// REQUANT_STALL_CYCLES read zero because compute is unwired; PACK_CYCLES is
// real (packer busy cycles); the DMA counters are live wires from npu_dma
// (cleared at the accepted launch); ACTIVE excludes pause. The terminal bank
// is latched separately on terminal_i and never overwrites the live bank.
`include "npu_define.svh"

module npu_scheduler (
    input  logic         clk_hp_i,
    input  logic         rst_hp_n_i,
    // coordinated fabric flush / recovery commit: FSM to idle (counters are
    // only cleared by launch_i, never by clear_i)
    input  logic         clear_i,
    // stop scheduling and drain (abort/quiesce/resource reset)
    input  logic         stop_i,
    input  logic         block_new_i,
    output logic         pause_ok_o,
    // accepted launch: reset the per-job counters and arm the watchdog
    input  logic         launch_i,
    input  logic [ 31:0] timeout_cycles_i,
    input  logic         job_active_i,
    input  logic         pause_active_i,
    // validated execute record from npu_job_decoder
    input  logic         rec_valid_i,
    output logic         rec_ready_o,
    input  logic [  3:0] rec_opcode_i,
    input  logic [ 12:0] rec_h_i,
    input  logic [ 12:0] rec_w_i,
    input  logic [ 12:0] rec_cin_i,
    input  logic [ 12:0] rec_cout_i,
    input  logic [ 12:0] rec_oh_i,
    input  logic [ 12:0] rec_ow_i,
    input  logic [ 31:0] rec_input0_base_i,
    input  logic [ 31:0] rec_output_base_i,
    input  logic [ 31:0] rec_weight_base_i,
    input  logic [ 31:0] rec_param_base_i,
    input  logic [ 31:0] rec_input0_row_bytes_i,
    input  logic [ 31:0] rec_output_row_bytes_i,
    input  logic [  7:0] rec_kh_i,
    input  logic [  7:0] rec_kw_i,
    input  logic [  7:0] rec_sh_i,
    input  logic [  7:0] rec_sw_i,
    input  logic [  7:0] rec_pad_top_i,
    input  logic [  7:0] rec_pad_left_i,
    input  logic [  7:0] rec_input0_zero_i,
    input  logic [ 31:0] rec_weight_bytes_i,
    input  logic [ 31:0] rec_param_bytes_i,
    input  logic [ 15:0] rec_desc_index_i,
    output logic         retired_o,
    output logic [ 31:0] completed_o,
    // npu_dma read command channel
    output logic         read_req_valid_o,
    input  logic         read_req_ready_i,
    output logic [ 31:0] read_addr_o,
    output logic [ 31:0] read_bytes_o,
    // npu_dma read stream
    input  logic         read_data_valid_i,
    output logic         read_data_ready_o,
    input  logic [ 63:0] read_data_i,
    input  logic [  7:0] read_keep_i,
    input  logic         read_last_i,
    // npu_dma write command channel
    output logic         write_req_valid_o,
    input  logic         write_req_ready_i,
    output logic [ 31:0] write_addr_o,
    output logic [ 31:0] write_bytes_o,
    // npu_dma write payload stream
    output logic         write_data_valid_o,
    input  logic         write_data_ready_i,
    output logic [ 63:0] write_data_o,
    output logic [  7:0] write_keep_o,
    output logic         write_last_o,
    input  logic         write_done_i,
    // npu_dma status
    input  logic         dma_read_busy_i,
    input  logic         dma_write_busy_i,
    input  logic         dma_pause_ack_i,
    input  logic         dma_fault_i,
    input  logic [  3:0] dma_fault_code_i,
    input  logic [ 31:0] dma_fault_addr_i,
    input  logic [  1:0] dma_fault_resp_i,
    input  logic [ 63:0] dma_read_bytes_i,
    input  logic [ 63:0] dma_write_bytes_i,
    input  logic [ 63:0] dma_stall_cycles_i,
    // watchdog progress of the decoder
    input  logic         progress_i,
    // terminal counters latch (pulse at terminal composition)
    input  logic         terminal_i,
    // live and retained-terminal counter banks, PERF offset order
    output logic [639:0] counters_o,
    output logic [639:0] term_counters_o,
    // terminal fault report (sticky until clear_i or the next launch)
    output logic         fault_req_o,
    output logic [  3:0] fault_code_o,
    output logic [ 31:0] fault_addr_o,
    output logic [ 31:0] fault_info_o,
    output logic [ 31:0] fault_desc_o,
    output logic         busy_o,
    output logic         drained_o
);
  localparam logic [31:0] FaultInfoInternal = {16'd0, 8'd255, 4'd0, 2'd0, 2'd0};

  typedef enum logic [4:0] {
    SchIdle,
    SchWCmd,
    SchWStream,
    SchPCmd,
    SchPStream,
    SchPosInit,
    SchGathSeg,
    SchGathAddr,
    SchGathCmd,
    SchGathStream,
    SchGathPad,
    SchPackStart,
    SchPackWait,
    SchEcho,
    SchStoreInit,
    SchStoreChunk,
    SchStoreCmd,
    SchStoreBeat,
    SchStoreWait,
    SchRetire,
    SchDrainWait,
    SchStopIdle,
    SchFaultWait
  } state_e;

  state_e s_state_d, s_state_q;
  // latched record
  logic [3:0] s_op_q;
  logic [12:0] s_h_q, s_w_q, s_cin_q, s_cout_q, s_oh_q, s_ow_q;
  logic [31:0] s_in0_base_q, s_out_base_q, s_w_base_q, s_p_base_q;
  logic [31:0] s_irow_q, s_orow_q;
  logic [7:0] s_kh_q, s_kw_q, s_sh_q, s_sw_q;
  logic [7:0] s_pad_t_q, s_pad_l_q, s_zp_q;
  logic [31:0] s_wbytes_q, s_pbytes_q;
  logic [15:0] s_desc_idx_q;
  // derived geometry
  logic [63:0] s_rec_kp_count;
  logic [63:0] s_kp_count_q;
  logic [63:0] s_kp_cin;
  logic [32:0] s_gather_len_q;
  logic [24:0] s_pos_count_q;
  // position and gather iterators
  logic [24:0] s_pos_q;
  logic [12:0] s_oy_q, s_ox_q;
  logic [32:0] s_g_q;
  logic [32:0] s_g0_q;
  logic [10:0] s_chunk_len_q;
  logic [12:0] s_ci_q;
  logic [12:0] s_kpos_h_q, s_kpos_w_q;
  logic        s_half_q;
  // current gather segment
  logic [31:0] s_seg_addr;
  logic [31:0] s_seg_addr_q;
  logic [31:0] s_iy_q;
  logic [31:0] s_ix_q;
  logic        s_in_range_q;
  logic [12:0] s_seg_run;
  logic [12:0] s_seg_left_q;
  logic [10:0] s_pad_head_q;
  logic [ 2:0] s_pad_room;
  logic [ 2:0] s_pad_n;
  // read distributor byte queue (gather beats -> raw half word writes)
  logic [ 7:0] s_q_bytes_q      [16];
  logic [ 4:0] s_q_cnt_q;
  logic [10:0] s_q_base_q;
  logic [ 3:0] s_keep_count;
  logic [ 3:0] s_keep_rank      [ 8];
  logic [ 2:0] s_pop_room;
  logic [ 2:0] s_pop_n;
  logic [ 4:0] s_q_cnt_pop;
  logic        s_q_accept;
  // weights/params fill
  logic [31:0] s_woff_q;
  logic [13:0] s_wchunk_q;
  logic [12:0] s_wfill_off_q;
  logic        s_whalf_q;
  logic [31:0] s_pdone_q;
  logic [31:0] s_prem_q;
  logic [ 7:0] s_pchunk_q;
  logic [12:0] s_poff_q;
  logic        s_phalf_q;
  logic [31:0] s_pend_data_q;
  logic [ 3:0] s_pend_keep_q;
  logic        s_pend_last_q;
  // packer wires
  logic        s_pack_start;
  logic        s_pack_ready;
  logic        s_pack_busy;
  logic        s_pack_done;
  logic        s_pack_raw_valid;
  logic [12:0] s_pack_raw_addr;
  logic        s_pack_wr_valid;
  logic [12:0] s_pack_wr_addr;
  logic [63:0] s_pack_wr_data;
  logic [ 7:0] s_pack_wr_strb;
  // echo engine
  logic [10:0] s_ech_j_q;
  logic [12:0] s_ech_c_q;
  logic [31:0] s_ech_word_q;
  logic        s_ech_rd_q;
  logic        s_ech_cap_q;
  // store engine
  logic [31:0] s_st_pos_addr_q;
  logic [31:0] s_st_cur_q;
  logic [12:0] s_st_rem_q;
  logic [12:0] s_st_cmd_bytes_q;
  logic [ 4:0] s_st_beats_q;
  logic [ 4:0] s_st_beat_idx_q;
  logic [ 2:0] s_st_phase_q;
  logic [31:0] s_st_w0_q, s_st_w1_q, s_st_w2_q;
  // watchdog and counters
  logic [31:0] s_timeout_q;
  logic [31:0] s_wdog_q;
  logic [63:0] s_cnt_active_q, s_cnt_pause_q, s_cnt_pack_q, s_cnt_retired_q;
  logic        [ 31:0] s_completed_q;
  logic        [639:0] s_term_q;
  // fault record
  logic                s_fault_seen_q;
  logic        [  3:0] s_fault_code_q;
  logic        [ 31:0] s_fault_addr_q;
  logic        [ 31:0] s_fault_info_q;

  logic                s_is_gap;
  logic        [ 12:0] s_kw_lim;
  logic        [ 31:0] s_iy_in;
  logic        [ 31:0] s_ix_in;
  logic                s_in_range;
  logic        [ 63:0] s_seg_addr_full;
  logic        [ 12:0] s_run_max;
  logic        [ 10:0] s_chunk_used;
  logic        [ 10:0] s_chunk_left;
  logic                s_read_accept;
  logic                s_stream_accept;
  logic                s_seg_stream_done;
  logic                s_iter_wrap;
  logic        [ 33:0] s_echo_c_next;
  logic                s_echo_c_valid;
  logic                s_echo_c_last;
  logic                s_echo_j_last;
  logic        [  7:0] s_ech_byte;
  // store beat planning (mirrors the npu_dma single-burst plan)
  logic        [ 31:0] s_st_aligned;
  logic        [ 13:0] s_st_span_beats;
  logic        [ 12:0] s_st_beats_4k;
  logic        [  4:0] s_st_plan_beats;
  logic        [ 12:0] s_st_plan_room;
  logic        [ 12:0] s_st_plan_bytes;
  logic        [ 31:0] s_st_beat_addr;
  logic        [  7:0] s_st_beat_keep;
  logic signed [ 13:0] s_st_beat_off;
  logic        [ 11:0] s_st_blo;
  logic        [ 11:0] s_st_bhi;
  logic        [ 11:0] s_st_wb;
  logic        [  2:0] s_st_nwords;
  logic        [ 63:0] s_st_beat_data;
  logic                s_write_accept;
  logic                s_cmd_w_accept;
  logic                s_progress;
  logic                s_wdog_fire;
  logic                s_drain_quiet;
  logic        [639:0] s_live_counters;
  logic                s_sram_err;
  logic                s_sram_clear;
  logic                s_iter_advance;

  // local SRAM and packer port wires
  logic                s_raw_write_valid;
  logic        [ 12:0] s_raw_write_addr;
  logic        [ 31:0] s_raw_write_data;
  logic        [  3:0] s_raw_write_strb;
  logic                s_raw_read_valid;
  logic        [ 12:0] s_raw_read_addr;
  logic        [ 31:0] s_raw_read_data;
  logic                s_pack_write_valid;
  logic                s_pack_write_sel_w;
  logic                s_pack_write_half;
  logic        [ 12:0] s_pack_write_addr;
  logic        [ 63:0] s_pack_write_data;
  logic        [  7:0] s_pack_write_strb;
  logic                s_out_valid;
  logic                s_out_write;
  logic        [ 11:0] s_out_addr;
  logic        [ 31:0] s_out_wdata;
  logic        [  3:0] s_out_wstrb;
  logic        [ 31:0] s_out_rdata;
  logic                s_param_write_valid;
  logic        [ 12:0] s_param_write_addr;
  logic        [ 31:0] s_param_write_data;
  logic        [  3:0] s_param_write_strb;

  // Record-input derived geometry (valid while the record is presented). Only
  // one multiply level crosses the accept edge; the per-channel reduction is
  // completed from registers in SchPosInit before the first gather segment.
  always_comb begin
    if (rec_opcode_i == `APB4_NPU__OP_GLOBAL_AVERAGE_POOL) begin
      s_rec_kp_count = {51'd0, rec_h_i} * {51'd0, rec_w_i};
    end else if (rec_opcode_i == `APB4_NPU__OP_DEPTHWISE3X3) begin
      s_rec_kp_count = 64'd9;
    end else if ((rec_opcode_i == `APB4_NPU__OP_CONV2D) ||
                 (rec_opcode_i == `APB4_NPU__OP_MAX_POOL) ||
                 (rec_opcode_i == `APB4_NPU__OP_AVERAGE_POOL)) begin
      s_rec_kp_count = {56'd0, rec_kh_i} * {56'd0, rec_kw_i};
    end else begin
      s_rec_kp_count = 64'd1;
    end
  end
  assign s_kp_cin = s_kp_count_q * {51'd0, s_cin_q};

  assign s_is_gap = (s_op_q == `APB4_NPU__OP_GLOBAL_AVERAGE_POOL);
  assign s_kw_lim = s_is_gap ? s_w_q : {5'd0, s_kw_q};

  // Iterator input position: for GAP the stride/padding words are zero, so
  // the same expression yields the whole-input raster position.
  assign s_iy_in = 32'($signed(
      {19'd0, s_oy_q}
  ) * $signed(
      {24'd0, s_sh_q}
  ) + $signed(
      {19'd0, s_kpos_h_q}
  ) - $signed(
      {24'd0, s_pad_t_q}
  ));
  assign s_ix_in = 32'($signed(
      {19'd0, s_ox_q}
  ) * $signed(
      {24'd0, s_sw_q}
  ) + $signed(
      {19'd0, s_kpos_w_q}
  ) - $signed(
      {24'd0, s_pad_l_q}
  ));
  assign s_in_range = (s_iy_in < {19'd0, s_h_q}) && (s_ix_in < {19'd0, s_w_q}) &&
      !s_iy_in[31] && !s_ix_in[31];
  // Segment address from the registered iterator position (SchGathAddr): one
  // multiply level per pipeline cycle keeps the 64-bit products off the
  // iterator-math cycle (SchGathSeg) and the command output path.
  assign s_seg_addr_full = {32'd0, s_in0_base_q} + {32'd0, s_iy_q} * {32'd0, s_irow_q} +
      ({32'd0, s_ix_q} * {51'd0, s_cin_q}) + {51'd0, s_ci_q};
  assign s_seg_addr = s_seg_addr_full[31:0];
  assign s_run_max = s_cin_q - s_ci_q;
  assign s_chunk_used = 11'(s_g_q - s_g0_q);
  assign s_chunk_left = s_chunk_len_q - s_chunk_used;
  assign s_seg_run = (s_run_max < {2'd0, s_chunk_left}) ? s_run_max : {2'd0, s_chunk_left};

  assign s_read_accept = read_req_valid_o && read_req_ready_i;
  assign s_stream_accept = read_data_valid_i && read_data_ready_o;
  assign s_write_accept = write_data_valid_o && write_data_ready_i;
  assign s_cmd_w_accept = write_req_valid_o && write_req_ready_i;

  function automatic logic [3:0] keep_ones(input logic [7:0] value_i);
    logic [3:0] count;
    begin
      count = 4'd0;
      for (int unsigned lane = 0; lane < 8; lane++) begin
        count = count + {3'd0, value_i[lane]};
      end
      return count;
    end
  endfunction

  assign s_keep_count = keep_ones(read_keep_i);
  always_comb begin
    for (int unsigned lane = 0; lane < 8; lane++) begin
      s_keep_rank[lane] = 4'd0;
      for (int unsigned below = 0; below < 8; below++) begin
        if ((below < lane) && read_keep_i[below]) begin
          s_keep_rank[lane] = s_keep_rank[lane] + 4'd1;
        end
      end
    end
  end

  // Gather byte queue: kept beat lanes append at the tail; each cycle one
  // 32-bit raw-half word is popped (the first pop of a word may be partial
  // because gather byte offsets are byte-aligned, not word-aligned).
  assign s_pop_room = 3'd4 - {1'b0, s_q_base_q[1:0]};
  assign s_pop_n = ({3'd0, s_pop_room} > {1'b0, s_q_cnt_q}) ? 3'(s_q_cnt_q) : s_pop_room;
  assign s_q_cnt_pop = s_q_cnt_q - {2'd0, s_pop_n};
  assign s_q_accept = (s_state_q == SchGathStream) && s_stream_accept;
  assign s_seg_stream_done = (s_state_q == SchGathStream) && (s_seg_left_q == 13'd0) &&
      (s_q_cnt_q == 5'd0);

  // gather iterator advance fires once when a segment has fully landed
  assign s_iter_advance = ((s_state_q == SchGathStream) && s_seg_stream_done) ||
      ((s_state_q == SchGathPad) && (s_seg_left_q == 13'd0));
  assign s_iter_wrap = ({1'b0, s_ci_q} + {1'b0, s_seg_run}) >= {1'b0, s_cin_q};

  // padding word write helpers
  assign s_pad_room = 3'd4 - {1'b0, s_pad_head_q[1:0]};
  assign s_pad_n = ({11'd0, s_pad_room} > {1'b0, s_seg_left_q}) ? 3'(s_seg_left_q) : s_pad_room;

  // echo channel mapping: c = g + m*G < cout for gather index g = g0 + j
  assign s_echo_c_next = {21'd0, s_ech_c_q} + {1'b0, s_gather_len_q};
  assign s_echo_c_valid = ({21'd0, s_ech_c_q} < {21'd0, s_cout_q});
  assign s_echo_c_last = !s_echo_c_valid || (s_echo_c_next >= {21'd0, s_cout_q});
  assign s_echo_j_last = (s_ech_j_q == (s_chunk_len_q - 11'd1));
  assign s_ech_byte = s_ech_word_q[{s_ech_j_q[1:0], 3'b000}+:8];

  // Store chunk planning: mirrors the npu_dma burst plan so every write
  // command is executed as exactly one burst (write_done_i per chunk).
  assign s_st_aligned = {s_st_cur_q[31:3], 3'b000};
  assign s_st_span_beats = ({11'd0, s_st_cur_q[2:0]} + {1'b0, s_st_rem_q} + 14'd7) >> 3;
  assign s_st_beats_4k = (13'd4096 - {1'b0, s_st_aligned[11:0]}) >> 3;
  assign s_st_plan_beats = (s_st_span_beats > 14'd16) ? 5'd16 :
      (s_st_span_beats > {1'b0, s_st_beats_4k}) ? 5'(s_st_beats_4k) : 5'(s_st_span_beats);
  assign s_st_plan_room = ({5'd0, s_st_plan_beats, 3'b000} - {10'd0, s_st_cur_q[2:0]});
  assign s_st_plan_bytes = (s_st_rem_q < s_st_plan_room) ? s_st_rem_q : s_st_plan_room;

  assign s_st_beat_addr = s_st_aligned + {24'd0, s_st_beat_idx_q, 3'b000};
  always_comb begin
    for (int unsigned lane = 0; lane < 8; lane++) begin
      s_st_beat_keep[lane] = ((s_st_beat_addr + 32'(lane)) >= s_st_cur_q) &&
          ((s_st_beat_addr + 32'(lane)) < (s_st_cur_q + {19'd0, s_st_cmd_bytes_q}));
    end
  end
  assign s_st_beat_off = 14'($signed({1'b0, s_st_beat_addr}) - $signed({1'b0, s_st_pos_addr_q}));
  // Staging read window for the beat, clamped to the written byte range.
  assign s_st_blo = s_st_beat_off[13] ? 12'd0 : s_st_beat_off[11:0];
  assign s_st_bhi = (({1'b0, s_st_beat_off} + 15'd7) > {2'd0, s_cout_q} - 15'd1) ?
      (s_cout_q[11:0] - 12'd1) : 12'(s_st_beat_off[11:0] + 12'd7);
  assign s_st_wb = {s_st_blo[11:2], 2'b00};
  assign s_st_nwords = 3'({1'b0, s_st_bhi[11:2]} - {1'b0, s_st_blo[11:2]} + 2'd1);
  always_comb begin
    logic [11:0] s_byte_index;
    s_st_beat_data = 64'd0;
    for (int unsigned lane = 0; lane < 8; lane++) begin
      s_byte_index = (12'({1'b0, s_st_beat_off[11:0]}) + {9'd0, lane[2:0]}) - s_st_wb;
      if (s_st_beat_keep[lane]) begin
        unique case (s_byte_index[11:2])
          10'd0:   s_st_beat_data[lane*8+:8] = s_st_w0_q[{s_byte_index[1:0], 3'b000}+:8];
          10'd1:   s_st_beat_data[lane*8+:8] = s_st_w1_q[{s_byte_index[1:0], 3'b000}+:8];
          default: s_st_beat_data[lane*8+:8] = s_st_w2_q[{s_byte_index[1:0], 3'b000}+:8];
        endcase
      end
    end
  end

  assign s_progress = s_stream_accept || s_write_accept || s_cmd_w_accept || s_read_accept ||
      write_done_i || s_pack_done || retired_o || progress_i;
  assign s_wdog_fire = job_active_i && !pause_active_i && !s_fault_seen_q && !s_progress &&
      (s_wdog_q == (s_timeout_q - 32'd1));
  assign s_drain_quiet = !dma_read_busy_i && !dma_write_busy_i && !s_pack_busy &&
      !read_data_valid_i && (s_q_cnt_q == 5'd0);

  assign s_live_counters = {
    s_cnt_retired_q,
    64'd0,
    dma_stall_cycles_i,
    dma_write_bytes_i,
    dma_read_bytes_i,
    64'd0,
    s_cnt_pack_q,
    64'd0,
    s_cnt_pause_q,
    s_cnt_active_q
  };
  assign counters_o = s_live_counters;
  assign term_counters_o = s_term_q;

  assign busy_o = (s_state_q != SchIdle) && (s_state_q != SchStopIdle);
  assign drained_o = (s_state_q == SchStopIdle) || (s_state_q == SchIdle) ||
      ((s_state_q == SchDrainWait) && s_drain_quiet) ||
      ((s_state_q == SchFaultWait) && s_drain_quiet);
  assign rec_ready_o = (s_state_q == SchIdle) && !stop_i && !clear_i;
  assign retired_o = (s_state_q == SchRetire);
  assign completed_o = s_completed_q;
  assign fault_req_o = s_fault_seen_q;
  assign fault_code_o = s_fault_code_q;
  assign fault_addr_o = s_fault_addr_q;
  assign fault_info_o = s_fault_info_q;
  assign fault_desc_o = {16'd0, s_desc_idx_q};

  // Pause acknowledge at a register-safe boundary: no queued gather bytes, no
  // in-flight echo read, no mid-assembly store beat (a presented-but
  // unaccepted write beat may stay), packer idle, no accepted read data still
  // streaming, and the DMA reporting zero accepted obligations.
  assign pause_ok_o = block_new_i && dma_pause_ack_i && !s_pack_busy && !read_data_valid_i &&
      (s_q_cnt_q == 5'd0) && !(s_ech_rd_q && !s_ech_cap_q) &&
      ((s_st_phase_q == 3'd0) || (s_st_phase_q == 3'd4));

  // ---------------------------------------------------------------------
  // DMA command and stream outputs
  // ---------------------------------------------------------------------
  always_comb begin
    read_req_valid_o = 1'b0;
    read_addr_o      = 32'd0;
    read_bytes_o     = 32'd0;
    unique case (s_state_q)
      SchWCmd: begin
        read_req_valid_o = !clear_i;
        read_addr_o      = s_w_base_q + s_woff_q;
        read_bytes_o     = {18'd0, s_wchunk_q};
      end
      SchPCmd: begin
        read_req_valid_o = !clear_i;
        read_addr_o      = s_p_base_q + s_pdone_q;
        read_bytes_o     = {24'd0, s_pchunk_q};
      end
      SchGathCmd: begin
        read_req_valid_o = !clear_i;
        read_addr_o      = s_seg_addr_q;
        read_bytes_o     = {19'd0, s_seg_run};
      end
      default: begin
      end
    endcase
  end

  assign read_data_ready_o = !clear_i &&
      (((s_state_q == SchWStream) || (s_state_q == SchFaultWait)) ||
       ((s_state_q == SchGathStream) && (s_q_cnt_pop <= 5'd8)) ||
       ((s_state_q == SchPStream) && !s_phalf_q));

  assign write_req_valid_o = (s_state_q == SchStoreCmd) && !clear_i;
  assign write_addr_o = s_st_cur_q;
  assign write_bytes_o = {19'd0, s_st_cmd_bytes_q};
  assign write_data_valid_o = (s_state_q == SchStoreBeat) && (s_st_phase_q == 3'd4) && !clear_i;
  assign write_data_o = s_st_beat_data;
  assign write_keep_o = s_st_beat_keep;
  assign write_last_o = (s_st_beat_idx_q == (s_st_beats_q - 5'd1));

  // ---------------------------------------------------------------------
  // Local SRAM and packer port muxing
  // ---------------------------------------------------------------------
  assign s_sram_clear = clear_i || launch_i;

  assign s_raw_read_valid = s_pack_busy ? s_pack_raw_valid :
      ((s_state_q == SchEcho) && !s_ech_rd_q && !block_new_i && !clear_i);
  assign s_raw_read_addr = s_pack_busy ? s_pack_raw_addr : {2'd0, s_ech_j_q};

  assign s_raw_write_valid = ((s_state_q == SchGathStream) && (s_pop_n != 3'd0)) ||
      ((s_state_q == SchGathPad) && !block_new_i && !clear_i && (s_seg_left_q != 13'd0));
  assign s_raw_write_addr = (s_state_q == SchGathPad) ? {2'd0, s_pad_head_q} : {2'd0, s_q_base_q};
  assign s_raw_write_data = (s_state_q == SchGathPad) ? {4{s_zp_q}} :
      32'(({24'd0, s_q_bytes_q[3], s_q_bytes_q[2], s_q_bytes_q[1], s_q_bytes_q[0]}) <<
          {s_q_base_q[1:0], 3'b000});
  assign s_raw_write_strb = (s_state_q == SchGathPad) ?
      (4'(((4'd1 << s_pad_n) - 4'd1) << {2'd0, s_pad_head_q[1:0]})) :
      (4'(((4'd1 << s_pop_n) - 4'd1) << {2'd0, s_q_base_q[1:0]}));

  assign s_pack_write_valid = s_pack_busy ? s_pack_wr_valid :
      ((s_state_q == SchWStream) && s_stream_accept && !clear_i);
  assign s_pack_write_sel_w = !s_pack_busy;
  assign s_pack_write_half = s_pack_busy ? s_half_q : s_whalf_q;
  assign s_pack_write_addr = s_pack_busy ? s_pack_wr_addr : 13'(s_wfill_off_q);
  assign s_pack_write_data = s_pack_busy ? s_pack_wr_data : read_data_i;
  assign s_pack_write_strb = s_pack_busy ? s_pack_wr_strb : read_keep_i;

  assign s_out_valid = ((s_state_q == SchEcho) && s_ech_rd_q && s_ech_cap_q && !block_new_i &&
                        !clear_i && s_echo_c_valid) ||
      ((s_state_q == SchStoreBeat) &&
       (((s_st_phase_q == 3'd0) && !block_new_i) ||
        ((s_st_phase_q == 3'd1) && (s_st_nwords > 3'd1)) ||
        ((s_st_phase_q == 3'd2) && (s_st_nwords > 3'd2))));
  assign s_out_write = (s_state_q == SchEcho);
  assign s_out_addr = (s_state_q == SchEcho) ? s_ech_c_q[11:0] :
      (s_st_wb + {7'd0, s_st_phase_q[1:0], 2'b00});
  assign s_out_wdata = {4{s_ech_byte}};
  assign s_out_wstrb = 4'(4'd1 << s_ech_c_q[1:0]);

  assign s_param_write_valid = (s_state_q == SchPStream) && !clear_i &&
      ((s_stream_accept && !s_phalf_q) || s_phalf_q);
  assign s_param_write_addr = s_poff_q + {10'd0, s_phalf_q, 2'b00};
  assign s_param_write_data = s_phalf_q ? s_pend_data_q : read_data_i[31:0];
  assign s_param_write_strb = s_phalf_q ? s_pend_keep_q : read_keep_i[3:0];

  assign s_pack_start = (s_state_q == SchPackStart) && !block_new_i && !stop_i && !clear_i;

  // ---------------------------------------------------------------------
  // Main state machine
  // ---------------------------------------------------------------------
  always_comb begin
    s_state_d = s_state_q;
    unique case (s_state_q)
      SchIdle: begin
        if (rec_valid_i && rec_ready_o) begin
          s_state_d = (rec_weight_bytes_i != 32'd0) ? SchWCmd :
              (rec_param_bytes_i != 32'd0) ? SchPCmd : SchPosInit;
        end
      end
      SchWCmd: begin
        if (s_read_accept) begin
          s_state_d = SchWStream;
        end
      end
      SchWStream: begin
        if (s_stream_accept && read_last_i) begin
          if ((s_woff_q + {18'd0, s_wchunk_q}) >= s_wbytes_q) begin
            s_state_d = (s_pbytes_q != 32'd0) ? SchPCmd : SchPosInit;
          end else begin
            s_state_d = SchWCmd;
          end
        end
      end
      SchPCmd: begin
        if (s_read_accept) begin
          s_state_d = SchPStream;
        end
      end
      SchPStream: begin
        // a chunk completes when the last beat's high word is written
        if (s_phalf_q && s_pend_last_q) begin
          s_state_d = (s_prem_q <= 32'd128) ? SchPosInit : SchPCmd;
        end
      end
      SchPosInit:    s_state_d = SchGathSeg;
      // Iterator math is registered in SchGathSeg; the address/range decision
      // completes one cycle later from those registers.
      SchGathSeg:    s_state_d = SchGathAddr;
      SchGathAddr: begin
        if (s_in_range_q) begin
          s_state_d = SchGathCmd;
        end else begin
          s_state_d = SchGathPad;
        end
      end
      SchGathCmd: begin
        if (s_read_accept) begin
          s_state_d = SchGathStream;
        end
      end
      SchGathStream: begin
        if (s_seg_stream_done) begin
          if ((s_g_q + {20'd0, s_seg_run} - s_g0_q) >= {22'd0, s_chunk_len_q}) begin
            s_state_d = SchPackStart;
          end else begin
            s_state_d = SchGathSeg;
          end
        end
      end
      SchGathPad: begin
        if (s_seg_left_q == 13'd0) begin
          if ((s_g_q + {20'd0, s_seg_run} - s_g0_q) >= {22'd0, s_chunk_len_q}) begin
            s_state_d = SchPackStart;
          end else begin
            s_state_d = SchGathSeg;
          end
        end
      end
      SchPackStart: begin
        if (s_pack_start && s_pack_ready) begin
          s_state_d = SchPackWait;
        end
      end
      SchPackWait: begin
        if (s_pack_done) begin
          s_state_d = SchEcho;
        end
      end
      SchEcho: begin
        if (s_ech_rd_q && s_ech_cap_q && s_echo_c_last && !block_new_i) begin
          if (s_echo_j_last) begin
            if ((s_g0_q + {22'd0, s_chunk_len_q}) >= s_gather_len_q) begin
              s_state_d = SchStoreInit;
            end else begin
              s_state_d = SchGathSeg;
            end
          end
        end
      end
      SchStoreInit:  s_state_d = SchStoreChunk;
      SchStoreChunk: s_state_d = SchStoreCmd;
      SchStoreCmd: begin
        if (s_cmd_w_accept) begin
          s_state_d = SchStoreBeat;
        end
      end
      SchStoreBeat: begin
        if ((s_st_phase_q == 3'd4) && s_write_accept &&
            (s_st_beat_idx_q == (s_st_beats_q - 5'd1))) begin
          s_state_d = SchStoreWait;
        end
      end
      SchStoreWait: begin
        if (write_done_i) begin
          if ((s_st_rem_q - s_st_cmd_bytes_q) == 13'd0) begin
            s_state_d = (({8'd0, s_pos_q} + 33'd1) == {8'd0, s_pos_count_q}) ? SchRetire :
                SchPosInit;
          end else begin
            s_state_d = SchStoreChunk;
          end
        end
      end
      SchRetire:     s_state_d = SchIdle;
      SchDrainWait: begin
        if (s_drain_quiet) begin
          s_state_d = SchStopIdle;
        end
      end
      SchStopIdle: begin
        if (!stop_i) begin
          s_state_d = SchIdle;
        end
      end
      SchFaultWait: begin
        if (s_drain_quiet) begin
          s_state_d = SchStopIdle;
        end
      end
      default:       s_state_d = SchIdle;
    endcase

    // DMA fault / LOCAL_STATE / watchdog escape: quarantine the current
    // segment and wait for the engine to drain its accepted obligations. The
    // watchdog may also fire from SchIdle while a job is active: the decoder
    // owns that phase (e.g. a stalled descriptor fetch).
    if (!s_fault_seen_q && (s_state_q != SchStopIdle) &&
        (s_state_q != SchDrainWait) && (s_state_q != SchFaultWait) &&
        (dma_fault_i || s_sram_err || s_wdog_fire)) begin
      s_state_d = SchFaultWait;
    end else if (stop_i && !dma_fault_i) begin
      // Stop (abort/quiesce/reset): finish the current DMA segment, start no
      // new one, then drain.
      unique case (s_state_q)
        SchWStream, SchPStream, SchGathStream, SchGathPad: begin
          // stay: the per-state completion exit below is redirected
          s_state_d = s_state_q;
          if ((s_state_q == SchWStream) && s_stream_accept && read_last_i) begin
            s_state_d = SchDrainWait;
          end
          if ((s_state_q == SchPStream) && s_phalf_q && s_pend_last_q) begin
            s_state_d = SchDrainWait;
          end
          if ((s_state_q == SchGathStream) && s_seg_stream_done) begin
            s_state_d = SchDrainWait;
          end
          if ((s_state_q == SchGathPad) && (s_seg_left_q == 13'd0)) begin
            s_state_d = SchDrainWait;
          end
        end
        SchStoreWait: begin
          if (write_done_i) begin
            s_state_d = SchDrainWait;
          end
        end
        SchStoreCmd: begin
          s_state_d = s_cmd_w_accept ? SchStoreBeat : SchDrainWait;
        end
        SchWCmd:    s_state_d = s_read_accept ? SchWStream : SchDrainWait;
        SchPCmd:    s_state_d = s_read_accept ? SchPStream : SchDrainWait;
        SchGathCmd: s_state_d = s_read_accept ? SchGathStream : SchDrainWait;
        SchIdle, SchDrainWait, SchStopIdle, SchFaultWait: begin
        end
        default:    s_state_d = SchDrainWait;
      endcase
    end
    if (clear_i) begin
      s_state_d = SchIdle;
    end
  end

  // ---------------------------------------------------------------------
  // Sequential state
  // ---------------------------------------------------------------------
  always_ff @(posedge clk_hp_i or negedge rst_hp_n_i) begin
    if (!rst_hp_n_i) begin
      s_state_q        <= SchIdle;
      s_op_q           <= '0;
      s_h_q            <= '0;
      s_w_q            <= '0;
      s_cin_q          <= '0;
      s_cout_q         <= '0;
      s_oh_q           <= '0;
      s_ow_q           <= '0;
      s_in0_base_q     <= '0;
      s_out_base_q     <= '0;
      s_w_base_q       <= '0;
      s_p_base_q       <= '0;
      s_irow_q         <= '0;
      s_orow_q         <= '0;
      s_kh_q           <= '0;
      s_kw_q           <= '0;
      s_sh_q           <= '0;
      s_sw_q           <= '0;
      s_pad_t_q        <= '0;
      s_pad_l_q        <= '0;
      s_zp_q           <= '0;
      s_wbytes_q       <= '0;
      s_pbytes_q       <= '0;
      s_desc_idx_q     <= '0;
      s_kp_count_q     <= '0;
      s_gather_len_q   <= '0;
      s_pos_count_q    <= '0;
      s_pos_q          <= '0;
      s_oy_q           <= '0;
      s_ox_q           <= '0;
      s_g_q            <= '0;
      s_g0_q           <= '0;
      s_chunk_len_q    <= '0;
      s_ci_q           <= '0;
      s_kpos_h_q       <= '0;
      s_kpos_w_q       <= '0;
      s_half_q         <= 1'b0;
      s_seg_addr_q     <= '0;
      s_iy_q           <= '0;
      s_ix_q           <= '0;
      s_in_range_q     <= 1'b0;
      s_seg_left_q     <= '0;
      s_pad_head_q     <= '0;
      s_q_cnt_q        <= 5'd0;
      s_q_base_q       <= '0;
      s_woff_q         <= '0;
      s_wchunk_q       <= '0;
      s_wfill_off_q    <= '0;
      s_whalf_q        <= 1'b0;
      s_pdone_q        <= '0;
      s_prem_q         <= '0;
      s_pchunk_q       <= '0;
      s_poff_q         <= '0;
      s_phalf_q        <= 1'b0;
      s_pend_data_q    <= '0;
      s_pend_keep_q    <= '0;
      s_pend_last_q    <= 1'b0;
      s_ech_j_q        <= '0;
      s_ech_c_q        <= '0;
      s_ech_word_q     <= '0;
      s_ech_rd_q       <= 1'b0;
      s_ech_cap_q      <= 1'b0;
      s_st_pos_addr_q  <= '0;
      s_st_cur_q       <= '0;
      s_st_rem_q       <= '0;
      s_st_cmd_bytes_q <= '0;
      s_st_beats_q     <= '0;
      s_st_beat_idx_q  <= '0;
      s_st_phase_q     <= '0;
      s_st_w0_q        <= '0;
      s_st_w1_q        <= '0;
      s_st_w2_q        <= '0;
      s_timeout_q      <= '0;
      s_wdog_q         <= '0;
      s_cnt_active_q   <= '0;
      s_cnt_pause_q    <= '0;
      s_cnt_pack_q     <= '0;
      s_cnt_retired_q  <= '0;
      s_completed_q    <= '0;
      s_term_q         <= '0;
      s_fault_seen_q   <= 1'b0;
      s_fault_code_q   <= '0;
      s_fault_addr_q   <= '0;
      s_fault_info_q   <= '0;
      for (int unsigned slot = 0; slot < 16; slot++) begin
        s_q_bytes_q[slot] <= '0;
      end
    end else begin
      // The terminal bank latches even through a same-cycle recovery commit.
      if (terminal_i) begin
        s_term_q <= s_live_counters;
      end
      if (clear_i) begin
        s_state_q      <= SchIdle;
        s_q_cnt_q      <= 5'd0;
        s_ech_rd_q     <= 1'b0;
        s_ech_cap_q    <= 1'b0;
        s_st_phase_q   <= '0;
        s_wdog_q       <= '0;
        s_fault_seen_q <= 1'b0;
      end else begin
        s_state_q <= s_state_d;

        if (launch_i) begin
          s_timeout_q     <= timeout_cycles_i;
          s_wdog_q        <= '0;
          s_cnt_active_q  <= '0;
          s_cnt_pause_q   <= '0;
          s_cnt_pack_q    <= '0;
          s_cnt_retired_q <= '0;
          s_completed_q   <= '0;
          s_fault_seen_q  <= 1'b0;
        end

        // record latch and derived geometry
        if (rec_valid_i && rec_ready_o) begin
          s_op_q        <= rec_opcode_i;
          s_h_q         <= rec_h_i;
          s_w_q         <= rec_w_i;
          s_cin_q       <= rec_cin_i;
          s_cout_q      <= rec_cout_i;
          s_oh_q        <= rec_oh_i;
          s_ow_q        <= rec_ow_i;
          s_in0_base_q  <= rec_input0_base_i;
          s_out_base_q  <= rec_output_base_i;
          s_w_base_q    <= rec_weight_base_i;
          s_p_base_q    <= rec_param_base_i;
          s_irow_q      <= rec_input0_row_bytes_i;
          s_orow_q      <= rec_output_row_bytes_i;
          s_kh_q        <= rec_kh_i;
          s_kw_q        <= rec_kw_i;
          s_sh_q        <= rec_sh_i;
          s_sw_q        <= rec_sw_i;
          s_pad_t_q     <= rec_pad_top_i;
          s_pad_l_q     <= rec_pad_left_i;
          s_zp_q        <= rec_input0_zero_i;
          s_wbytes_q    <= rec_weight_bytes_i;
          s_pbytes_q    <= rec_param_bytes_i;
          s_desc_idx_q  <= rec_desc_index_i;
          s_kp_count_q  <= s_rec_kp_count;
          s_pos_count_q <= 25'({12'd0, rec_oh_i} * {12'd0, rec_ow_i});
          s_pos_q       <= '0;
          s_oy_q        <= '0;
          s_ox_q        <= '0;
          s_g_q         <= '0;
          s_g0_q        <= '0;
          s_ci_q        <= '0;
          s_kpos_h_q    <= '0;
          s_kpos_w_q    <= '0;
          s_half_q      <= 1'b0;
          s_woff_q      <= '0;
          s_wchunk_q    <= (rec_weight_bytes_i > 32'd8192) ? 14'd8192 : rec_weight_bytes_i[13:0];
          s_wfill_off_q <= '0;
          s_whalf_q     <= 1'b0;
          s_pdone_q     <= '0;
          s_prem_q      <= rec_param_bytes_i;
          s_pchunk_q    <= (rec_param_bytes_i > 32'd128) ? 8'd128 : rec_param_bytes_i[7:0];
          s_poff_q      <= '0;
          s_phalf_q     <= 1'b0;
          s_pend_last_q <= 1'b0;
        end

        // weights fill bookkeeping
        if ((s_state_q == SchWCmd) && s_read_accept) begin
          s_wfill_off_q <= '0;
        end
        if ((s_state_q == SchWStream) && s_stream_accept) begin
          s_wfill_off_q <= s_wfill_off_q + 13'd8;
          if (read_last_i) begin
            s_woff_q  <= s_woff_q + {18'd0, s_wchunk_q};
            s_whalf_q <= ~s_whalf_q;
            if ((s_wbytes_q - (s_woff_q + {18'd0, s_wchunk_q})) > 32'd8192) begin
              s_wchunk_q <= 14'd8192;
            end else begin
              s_wchunk_q <= 14'(s_wbytes_q - (s_woff_q + {18'd0, s_wchunk_q}));
            end
          end
        end

        // parameter fill bookkeeping: 128-byte group chunks into the region
        if ((s_state_q == SchPCmd) && s_read_accept) begin
          s_poff_q      <= s_pdone_q[12:0];
          s_phalf_q     <= 1'b0;
          s_pend_last_q <= 1'b0;
        end
        if ((s_state_q == SchPStream) && s_stream_accept && !s_phalf_q) begin
          s_pend_data_q <= read_data_i[63:32];
          s_pend_keep_q <= read_keep_i[7:4];
          s_pend_last_q <= read_last_i;
          s_phalf_q     <= 1'b1;
        end else if ((s_state_q == SchPStream) && s_phalf_q) begin
          s_poff_q  <= s_poff_q + 13'd8;
          s_phalf_q <= 1'b0;
          if (s_pend_last_q) begin
            s_prem_q <= s_prem_q - {24'd0, s_pchunk_q};
            s_pdone_q <= s_pdone_q + {24'd0, s_pchunk_q};
            s_pchunk_q <= ((s_prem_q - {24'd0, s_pchunk_q}) > 32'd128) ? 8'd128 :
              8'(s_prem_q - {24'd0, s_pchunk_q});
          end
        end

        // per-record gather geometry, completed one multiply level after the
        // accept edge; idempotent on SchPosInit re-entry (later positions of
        // the same record reload the same values)
        if (s_state_q == SchPosInit) begin
          s_gather_len_q <= 33'(s_kp_cin);
          s_chunk_len_q  <= (s_kp_cin > 64'd1024) ? 11'd1024 : 11'(s_kp_cin);
        end

        // gather segment pipeline: iterator position in SchGathSeg, segment
        // address from the registered position in SchGathAddr
        if (s_state_q == SchGathSeg) begin
          s_iy_q       <= s_iy_in;
          s_ix_q       <= s_ix_in;
          s_in_range_q <= s_in_range;
        end
        if (s_state_q == SchGathAddr) begin
          s_seg_addr_q <= s_seg_addr;
        end

        // gather segment launch
        if ((s_state_q == SchGathAddr) && (s_state_d == SchGathCmd)) begin
          s_seg_left_q <= s_seg_run;
          s_q_base_q   <= s_chunk_used;
          s_q_cnt_q    <= 5'd0;
        end
        if ((s_state_q == SchGathAddr) && (s_state_d == SchGathPad)) begin
          s_seg_left_q <= s_seg_run;
          s_pad_head_q <= s_chunk_used;
        end

        // gather byte queue: pop one word per cycle, append on accepted beats
        if ((s_state_q == SchGathStream) && (s_pop_n != 3'd0)) begin
          for (int unsigned idx = 0; idx < 16; idx++) begin
            if ((idx + 32'(s_pop_n)) < 16) begin
              s_q_bytes_q[idx] <= s_q_bytes_q[idx+32'(s_pop_n)];
            end
          end
          s_q_base_q <= s_q_base_q + {8'd0, s_pop_n};
          s_q_cnt_q  <= s_q_cnt_pop;
        end
        if (s_q_accept) begin
          for (int unsigned lane = 0; lane < 8; lane++) begin
            if (read_keep_i[lane]) begin
              s_q_bytes_q[4'(s_q_cnt_pop+{1'b0, s_keep_rank[lane]})] <= read_data_i[lane*8+:8];
            end
          end
          s_q_cnt_q    <= s_q_cnt_pop + {1'b0, s_keep_count};
          s_seg_left_q <= s_seg_left_q - {9'd0, s_keep_count};
        end
        if ((s_state_q == SchGathPad) && !block_new_i && (s_seg_left_q != 13'd0)) begin
          s_pad_head_q <= s_pad_head_q + {8'd0, s_pad_n};
          s_seg_left_q <= s_seg_left_q - {10'd0, s_pad_n};
        end

        // iterator advance at a completed gather segment
        if (s_iter_advance) begin
          s_g_q <= s_g_q + {20'd0, s_seg_run};
          if (s_iter_wrap) begin
            s_ci_q <= '0;
            if (({1'b0, s_kpos_w_q} + 14'd1) == {1'b0, s_kw_lim}) begin
              s_kpos_w_q <= '0;
              s_kpos_h_q <= s_kpos_h_q + 13'd1;
            end else begin
              s_kpos_w_q <= s_kpos_w_q + 13'd1;
            end
          end else begin
            s_ci_q <= s_ci_q + s_seg_run;
          end
        end

        // echo engine
        if ((s_state_q == SchPackWait) && s_pack_done) begin
          s_ech_j_q   <= '0;
          s_ech_c_q   <= 13'(s_g0_q[12:0]);
          s_ech_rd_q  <= 1'b0;
          s_ech_cap_q <= 1'b0;
        end
        if ((s_state_q == SchEcho) && !s_ech_rd_q && !block_new_i && !clear_i) begin
          s_ech_rd_q  <= 1'b1;
          s_ech_cap_q <= 1'b0;
        end
        if ((s_state_q == SchEcho) && s_ech_rd_q && !s_ech_cap_q) begin
          s_ech_word_q <= s_raw_read_data;
          s_ech_cap_q  <= 1'b1;
        end
        if ((s_state_q == SchEcho) && s_ech_rd_q && s_ech_cap_q && !block_new_i) begin
          if (!s_echo_c_last) begin
            s_ech_c_q <= 13'(s_echo_c_next);
          end else if (!s_echo_j_last) begin
            s_ech_j_q   <= s_ech_j_q + 11'd1;
            s_ech_c_q   <= 13'(s_g0_q + {22'd0, s_ech_j_q} + 33'd1);
            s_ech_rd_q  <= 1'b0;
            s_ech_cap_q <= 1'b0;
          end
        end
        if ((s_state_q == SchEcho) && (s_state_d == SchGathSeg)) begin
          // next chunk of the same position
          s_g0_q   <= s_g0_q + {22'd0, s_chunk_len_q};
          s_half_q <= ~s_half_q;
          if ((s_gather_len_q - (s_g0_q + {22'd0, s_chunk_len_q})) > 33'd1024) begin
            s_chunk_len_q <= 11'd1024;
          end else begin
            s_chunk_len_q <= 11'(s_gather_len_q - (s_g0_q + {22'd0, s_chunk_len_q}));
          end
        end

        // store engine
        if (s_state_q == SchStoreInit) begin
          s_st_pos_addr_q <= 32'({32'd0, s_out_base_q} + ({19'd0, s_oy_q} * {32'd0, s_orow_q}) +
                               ({19'd0, s_ox_q} * {51'd0, s_cout_q}));
          s_st_cur_q <= 32'({32'd0, s_out_base_q} + ({19'd0, s_oy_q} * {32'd0, s_orow_q}) +
                          ({19'd0, s_ox_q} * {51'd0, s_cout_q}));
          s_st_rem_q <= s_cout_q;
        end
        if (s_state_q == SchStoreChunk) begin
          s_st_cmd_bytes_q <= s_st_plan_bytes;
          s_st_beats_q     <= s_st_plan_beats;
          s_st_beat_idx_q  <= '0;
          s_st_phase_q     <= '0;
        end
        if (s_state_q == SchStoreBeat) begin
          if ((s_st_phase_q == 3'd0) && !block_new_i) begin
            s_st_phase_q <= 3'd1;
          end else if ((s_st_phase_q == 3'd1) || (s_st_phase_q == 3'd2) ||
                     (s_st_phase_q == 3'd3)) begin
            if (s_st_phase_q == 3'd1) begin
              s_st_w0_q <= s_out_rdata;
            end
            if (s_st_phase_q == 3'd2) begin
              s_st_w1_q <= s_out_rdata;
            end
            if (s_st_phase_q == 3'd3) begin
              s_st_w2_q <= s_out_rdata;
            end
            s_st_phase_q <= s_st_phase_q + 3'd1;
          end else if ((s_st_phase_q == 3'd4) && s_write_accept) begin
            s_st_beat_idx_q <= s_st_beat_idx_q + 5'd1;
            s_st_phase_q    <= '0;
          end
        end
        if ((s_state_q == SchStoreWait) && write_done_i && (s_state_d == SchStoreChunk)) begin
          s_st_cur_q <= s_st_cur_q + {19'd0, s_st_cmd_bytes_q};
          s_st_rem_q <= s_st_rem_q - s_st_cmd_bytes_q;
        end

        // position advance
        if ((s_state_q == SchStoreWait) && write_done_i &&
          ((s_st_rem_q - s_st_cmd_bytes_q) == 13'd0) && (s_state_d == SchPosInit)) begin
          if (({1'b0, s_ox_q} + 14'd1) == {1'b0, s_ow_q}) begin
            s_ox_q <= '0;
            s_oy_q <= s_oy_q + 13'd1;
          end else begin
            s_ox_q <= s_ox_q + 13'd1;
          end
          s_pos_q       <= s_pos_q + 25'd1;
          s_g_q         <= '0;
          s_g0_q        <= '0;
          s_ci_q        <= '0;
          s_kpos_h_q    <= '0;
          s_kpos_w_q    <= '0;
          s_chunk_len_q <= (s_gather_len_q > 33'd1024) ? 11'd1024 : 11'(s_gather_len_q);
        end

        // watchdog
        if (job_active_i && !pause_active_i && !s_fault_seen_q && !launch_i) begin
          if (s_progress) begin
            s_wdog_q <= '0;
          end else if (!s_wdog_fire) begin
            s_wdog_q <= s_wdog_q + 32'd1;
          end
        end

        // counters (saturating)
        if (job_active_i && !pause_active_i && (s_cnt_active_q != 64'hffff_ffff_ffff_ffff)) begin
          s_cnt_active_q <= s_cnt_active_q + 64'd1;
        end
        if (job_active_i && pause_active_i && (s_cnt_pause_q != 64'hffff_ffff_ffff_ffff)) begin
          s_cnt_pause_q <= s_cnt_pause_q + 64'd1;
        end
        if (job_active_i && s_pack_busy && (s_cnt_pack_q != 64'hffff_ffff_ffff_ffff)) begin
          s_cnt_pack_q <= s_cnt_pack_q + 64'd1;
        end
        if (retired_o && (s_cnt_retired_q != 64'hffff_ffff_ffff_ffff)) begin
          s_cnt_retired_q <= s_cnt_retired_q + 64'd1;
          s_completed_q   <= s_completed_q + 32'd1;
        end

        // fault capture: DMA fault wins over LOCAL_STATE wins over NO_PROGRESS
        if (!s_fault_seen_q && (s_state_d == SchFaultWait) && (s_state_q != SchFaultWait)) begin
          s_fault_seen_q <= 1'b1;
          s_q_cnt_q      <= 5'd0;
          if (dma_fault_i) begin
            s_fault_code_q <= dma_fault_code_i;
            s_fault_addr_q <= dma_fault_addr_i;
            s_fault_info_q <= {
              16'd0,
              8'd255,
              4'd0,
              (dma_fault_code_i == `APB4_NPU__FAULT_CODE_AXI_WRITE) ? 2'd2 :
                             (dma_fault_code_i == `APB4_NPU__FAULT_CODE_AXI_READ) ? 2'd1 :
                             (dma_read_busy_i ? 2'd1 : 2'd2),
              dma_fault_resp_i
            };
          end else if (s_sram_err) begin
            s_fault_code_q <= `APB4_NPU__FAULT_CODE_LOCAL_STATE;
            s_fault_addr_q <= 32'd0;
            s_fault_info_q <= FaultInfoInternal;
          end else begin
            s_fault_code_q <= `APB4_NPU__FAULT_CODE_NO_PROGRESS;
            s_fault_addr_q <= 32'd0;
            s_fault_info_q <= FaultInfoInternal;
          end
        end
      end
    end
  end

  // ---------------------------------------------------------------------
  // SRAM-bound hold shim (synthesis only)
  // ---------------------------------------------------------------------
  // The RM_IHPSG13_1P_1024x32_c2_bm_bist hold requirement on DIN/ADDR/BM
  // (~0.9 ns at the IHP130 slow corner) exceeds a flip-flop clock-to-Q
  // minimum (~0.3 ns), and the isolated smoke flow has no place/route hold
  // repair. Two stacked sg13g2_dlygate4sd3 delay gates per bit add ~1 ns of
  // functionally transparent in-cycle delay on every non-constant
  // SRAM-bound net; simulation, lint and non-synthesis flows use the plain
  // nets. Setup slack into the macro ports stays above 10 ns.
  logic         s_raw_write_valid_hd;
  logic         s_half_hd;
  logic [ 12:0] s_raw_write_addr_hd;
  logic [ 31:0] s_raw_write_data_hd;
  logic [  3:0] s_raw_write_strb_hd;
  logic         s_raw_read_valid_hd;
  logic [ 12:0] s_raw_read_addr_hd;
  logic         s_pack_write_valid_hd;
  logic         s_pack_write_sel_w_hd;
  logic         s_pack_write_half_hd;
  logic [ 12:0] s_pack_write_addr_hd;
  logic [ 63:0] s_pack_write_data_hd;
  logic [  7:0] s_pack_write_strb_hd;
  logic         s_out_valid_hd;
  logic         s_out_write_hd;
  logic         s_out_half_hd;
  logic [ 11:0] s_out_addr_hd;
  logic [ 31:0] s_out_wdata_hd;
  logic [  3:0] s_out_wstrb_hd;
  logic         s_param_write_valid_hd;
  logic [ 12:0] s_param_write_addr_hd;
  logic [ 31:0] s_param_write_data_hd;
  logic [  3:0] s_param_write_strb_hd;
  logic [253:0] s_sram_pre;
  logic [253:0] s_sram_hd;

  assign s_sram_pre = {
    s_raw_write_valid,
    s_half_q,
    s_raw_write_addr,
    s_raw_write_data,
    s_raw_write_strb,
    s_raw_read_valid,
    s_raw_read_addr,
    s_pack_write_valid,
    s_pack_write_sel_w,
    s_pack_write_half,
    s_pack_write_addr,
    s_pack_write_data,
    s_pack_write_strb,
    s_out_valid,
    s_out_write,
    s_pos_q[0],
    s_out_addr,
    s_out_wdata,
    s_out_wstrb,
    s_param_write_valid,
    s_param_write_addr,
    s_param_write_data,
    s_param_write_strb
  };

`ifdef SYNTHESIS
  for (genvar hold_bit = 0; hold_bit < 254; hold_bit++) begin : gen_sram_hold
    logic s_mid;
    sg13g2_dlygate4sd3_1 u_hd0 (
        .A(s_sram_pre[hold_bit]),
        .X(s_mid)
    );
    sg13g2_dlygate4sd3_1 u_hd1 (
        .A(s_mid),
        .X(s_sram_hd[hold_bit])
    );
  end
`else
  assign s_sram_hd = s_sram_pre;
`endif

  assign {
    s_raw_write_valid_hd, s_half_hd, s_raw_write_addr_hd, s_raw_write_data_hd,
    s_raw_write_strb_hd, s_raw_read_valid_hd, s_raw_read_addr_hd,
    s_pack_write_valid_hd, s_pack_write_sel_w_hd, s_pack_write_half_hd,
    s_pack_write_addr_hd, s_pack_write_data_hd, s_pack_write_strb_hd,
    s_out_valid_hd, s_out_write_hd, s_out_half_hd, s_out_addr_hd, s_out_wdata_hd,
    s_out_wstrb_hd, s_param_write_valid_hd, s_param_write_addr_hd,
    s_param_write_data_hd, s_param_write_strb_hd
  } = s_sram_hd;

  // ---------------------------------------------------------------------
  // Local storage and packer
  // ---------------------------------------------------------------------
  npu_patch_packer u_patch_packer (
      .clk_i             (clk_hp_i),
      .rst_n_i           (rst_hp_n_i),
      .start_valid_i     (s_pack_start),
      .start_ready_o     (s_pack_ready),
      .start_mode_i      (npu_pkg::PackDense),
      .start_k_i         (s_chunk_len_q),
      .start_positions_i (4'd1),
      .start_channels_i  (4'd8),
      .start_in_zero_i   (s_zp_q),
      .busy_o            (s_pack_busy),
      .done_pulse_o      (s_pack_done),
      .raw_read_valid_o  (s_pack_raw_valid),
      .raw_read_addr_o   (s_pack_raw_addr),
      .raw_read_data_i   (s_raw_read_data),
      .pack_write_valid_o(s_pack_wr_valid),
      .pack_write_addr_o (s_pack_wr_addr),
      .pack_write_data_o (s_pack_wr_data),
      .pack_write_strb_o (s_pack_wr_strb)
  );

  npu_local_sram u_local_sram (
      .clk_i              (clk_hp_i),
      .rst_n_i            (rst_hp_n_i),
      .clear_i            (s_sram_clear),
      .raw_write_valid_i  (s_raw_write_valid_hd),
      .raw_write_half_i   (s_half_hd),
      .raw_write_addr_i   (s_raw_write_addr_hd),
      .raw_write_data_i   (s_raw_write_data_hd),
      .raw_write_strb_i   (s_raw_write_strb_hd),
      .raw_read_valid_i   (s_raw_read_valid_hd),
      .raw_read_half_i    (s_half_hd),
      .raw_read_addr_i    (s_raw_read_addr_hd),
      .raw_read_data_o    (s_raw_read_data),
      .pack_write_valid_i (s_pack_write_valid_hd),
      .pack_write_sel_w_i (s_pack_write_sel_w_hd),
      .pack_write_half_i  (s_pack_write_half_hd),
      .pack_write_addr_i  (s_pack_write_addr_hd),
      .pack_write_data_i  (s_pack_write_data_hd),
      .pack_write_strb_i  (s_pack_write_strb_hd),
      .a_read_valid_i     (1'b0),
      .a_read_half_i      (1'b0),
      .a_read_addr_i      (13'd0),
      .a_read_data_o      (),                        // compute read ports are P4 scope
      .w_read_valid_i     (1'b0),
      .w_read_half_i      (1'b0),
      .w_read_addr_i      (13'd0),
      .w_read_data_o      (),                        // compute read ports are P4 scope
      .out_req_valid_i    (s_out_valid_hd),
      .out_req_write_i    (s_out_write_hd),
      .out_req_half_i     (s_out_half_hd),
      .out_req_addr_i     (s_out_addr_hd),
      .out_req_data_i     (s_out_wdata_hd),
      .out_req_strb_i     (s_out_wstrb_hd),
      .out_read_data_o    (s_out_rdata),
      .param_write_valid_i(s_param_write_valid_hd),
      .param_write_addr_i (s_param_write_addr_hd),
      .param_write_data_i (s_param_write_data_hd),
      .param_write_strb_i (s_param_write_strb_hd),
      .param_read_valid_i (1'b0),
      .param_read_addr_i  (13'd0),
      .param_read_data_o  (),                        // compute read port is P4 scope
      .access_err_sticky_o(s_sram_err),
      .access_err_port_o  ()                         // the port code is diagnostic-only at P3
  );
endmodule
