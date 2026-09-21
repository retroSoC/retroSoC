// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// NPU-P4 job scheduler: transport ownership and numerical-profile-1 compute
// for one validated descriptor at a time, the per-job PERF counters, the
// no-progress watchdog and the transport-level lifecycle discipline
// (docs/ip/npu.md "Private storage and packing", "Operator and numerical
// profile 1", "Job submission and ordering", counter and watchdog tables).
//
// Transport per descriptor: packed weights stream through the npu_dma read
// channel into the W banks (8192-byte chunks alternating halves), parameters
// stream into the parameter region in 8192-byte windows of 512 16-byte
// records (a window refills every 64 output-channel groups), then per
// TILE_H x TILE_W tile (row-major, edge tiles shortened, staging-bound
// passes of at most 8192/Cout positions) the receptive fields gather into a
// raw half as contiguous input-channel runs (out-of-range padding is
// synthesized locally with the input zero point) and pack through
// npu_patch_packer into the A banks.
//
// Compute per output-channel group of eight lanes: CONV2D/FULLY_CONNECTED
// stream packed A rows (spatial lanes) and W rows (channel lanes), four
// 32-bit bank reads per cycle, into npu_mac_array and npu_accumulator (bias
// preload once at group start; K-slice chunks continue in the same context;
// when the whole reduction fits one A half it is gathered/packed once and
// reused across groups), then scalar-drain through npu_requantizer with the
// group's multiplier/shift records plus the output zero point and ACT
// bounds. DEPTHWISE3X3 runs one output position at a time through npu_vector
// (eight channel lanes, bias preload, lane-masked checked accumulate) with
// the same requantizer drain. MAX/AVERAGE/GLOBAL_AVERAGE_POOL use the vector
// aux (signed-byte max / checked INT32 sum) with padding excluded from the
// geometry, AVERAGE/GLOBAL_AVERAGE dividing ties-away by the valid count
// (Kh*Kw or H*W, shared restoring divider) and clamping per ACT bounds (the
// descriptor zero points must be equal, additionally verified here). ADD
// gathers both inputs (independent bases/strides/zero points), applies the
// pinned 2^20 pre-shift and the three offline multipliers of the 32-byte
// parameter record with a checked INT32 sum (an internal three-stage path
// reproducing npu_requantizer's QM bit-exactly for the two input terms), and
// finishes through the shared requantizer. CLAMP applies the bounds only.
// Every result byte is written into flat output staging (position-major,
// Cout bytes per position) and stored through the P3 burst-planned write
// path; a descriptor retires on the final write's successful B response.
//
// Ordering and lifecycle are unchanged from P3: stop_i finishes the current
// DMA segment and drains; a DMA fault escapes any stream wait immediately;
// pause (block_new_i) starts no new work, retains presented VALID, and
// acknowledges only with zero in-flight items (accumulator/vector context
// sums are stable state and survive the pause). ARITHMETIC faults from the
// accumulator, vector, requantizer or the ADD checked paths capture into the
// job first-fault record (code 7, lane in FAULT_INFO bits15:8), and
// parameter-encoding violations report DESCRIPTOR with the offending record
// address. The counters are live: USEFUL_MACS (unmasked mathematical MACs),
// PACK_CYCLES (packer busy), LOCAL_BANK_STALL_CYCLES (staging bytes blocked
// by the output bank), REQUANT_STALL_CYCLES (drain items blocked by the
// requantizer), plus the P3 DMA/ACTIVE/PAUSE counters.
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
    // P4 compute fields of the same validated record
    input  logic [  7:0] rec_tile_h_i,
    input  logic [  7:0] rec_tile_w_i,
    input  logic [ 15:0] rec_k_slice_i,
    input  logic [ 31:0] rec_input1_base_i,
    input  logic [ 31:0] rec_input1_row_bytes_i,
    input  logic [  7:0] rec_input1_zero_i,
    input  logic [  7:0] rec_output_zero_i,
    input  logic [  7:0] rec_act_min_i,
    input  logic [  7:0] rec_act_max_i,
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

  typedef enum logic [5:0] {
    SchIdle,
    SchWCmd,
    SchWStream,
    SchPCmd,
    SchPStream,
    SchDescInit,
    SchParamRd,
    SchGrpInit,
    SchAccStart,
    SchGathSeg,
    SchGathAddr,
    SchGathCmd,
    SchGathStream,
    SchGathPad,
    SchGathExit,
    SchPackStart,
    SchPackWait,
    SchMacStream,
    SchAccDrain,
    SchVecStart,
    SchVecStream,
    SchVecDrain,
    SchPoolStream,
    SchPoolDiv,
    SchClamp,
    SchAddFeed,
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
  logic [7:0] s_th_q, s_tw_q;
  logic [31:0] s_in1_base_q, s_in1_row_q;
  logic [7:0] s_z1_q, s_zout_q, s_act_min_q, s_act_max_q;
  logic [31:0] s_wbytes_q, s_pbytes_q;
  logic [15:0] s_desc_idx_q;
  logic [31:0] s_gbase_q;  // DMA window base of the current granule
  logic [31:0] s_grow_q;  // DMA window row stride of the current granule
  // derived geometry (P4 compute loop constants)
  logic [63:0] s_rec_kp_count;
  logic [63:0] s_kp_count_q;
  logic [63:0] s_kp_cin;
  logic [32:0] s_gather_len_q;
  logic [24:0] s_full_k_q;  // dense kp*cin, DW 9, pool kh*kw, GAP h*w, else 1
  logic [ 9:0] s_groups_q;  // ceil(cout/8)
  logic [10:0] s_kslice_q;  // descriptor K_SLICE
  logic [ 3:0] s_pass_cap_q;  // staging-bound positions per pass (<=8)
  logic [ 3:0] s_glane_q;  // lanes of the current channel group (<=8)
  // tile/pass/group/slice loop registers
  logic [12:0] s_ty_q, s_tx_q;  // tile base output coords
  logic [3:0] s_trows_q, s_tcols_q;
  logic [3:0] s_dy_q, s_dx_q;  // next unprocessed position within the tile
  logic [ 3:0] s_pbase_q;  // pass base position index within the tile
  logic [ 3:0] s_pcnt_q;  // positions of the current pass (<=8)
  logic [ 3:0] s_pidx_q;  // per-position loop index within the pass
  logic [ 9:0] s_group_q;  // current channel group
  logic [24:0] s_ks0_q;  // current K-slice base within the reduction
  logic [10:0] s_klen_q;  // current K-slice length (<=1024)
  logic        s_a_ready_q;  // dense A-half reuse tag: whole reduction packed
  logic        s_ahalf_q;  // active packed-A half for streaming
  logic        s_ghalf_q;  // raw gather half of the current granule
  logic [33:0] s_wrow_q;  // W row base of the current group
  // position and gather iterators
  logic [12:0] s_oy_q, s_ox_q;
  logic [32:0] s_g_q;
  logic [12:0] s_kloc_q;  // byte index within the current position window
  logic [12:0] s_ci_q;
  logic [12:0] s_kpos_h_q, s_kpos_w_q;
  logic [12:0] s_sn_ci_q;  // slice-start reduction coords (per-position restore)
  logic [12:0] s_sn_kh_q, s_sn_kw_q;
  logic [3:0] s_gdy_q, s_gdx_q;  // gather position coords within the tile
  logic [12:0] s_gcbase_q;  // group channel base (0 dense, group*8 grouped)
  logic [12:0] s_gpos_bytes_q;  // gathered bytes per position of the granule
  logic [24:0] s_granule_q;  // total bytes of the current gather granule
  // current gather segment
  logic [31:0] s_seg_addr;
  logic [31:0] s_seg_addr_q;
  logic [31:0] s_iy_q;
  logic [31:0] s_ix_q;
  logic s_in_range_q;
  logic [12:0] s_seg_run;
  logic [12:0] s_seg_left_q;
  logic [12:0] s_pad_head_q;
  logic [2:0] s_pad_room;
  logic [2:0] s_pad_n;
  // read distributor byte queue (gather beats -> raw half word writes)
  logic [7:0] s_q_bytes_q[16];
  logic [4:0] s_q_cnt_q;
  logic [12:0] s_q_base_q;
  logic [3:0] s_keep_count;
  logic [3:0] s_keep_rank[8];
  logic [2:0] s_pop_room;
  logic [2:0] s_pop_n;
  logic [4:0] s_q_cnt_pop;
  logic s_q_accept;
  // weights/params fill
  logic [31:0] s_woff_q;
  logic [13:0] s_wchunk_q;
  logic [12:0] s_wfill_off_q;
  logic s_whalf_q;
  logic s_w_stream_q;  // weights exceed the two local W halves; fetch per K slice
  logic [31:0] s_pdone_q;
  logic [31:0] s_prem_q;
  logic [7:0] s_pchunk_q;
  logic [12:0] s_poff_q;
  logic s_phalf_q;
  logic s_prefill_q;  // param region window refill in progress
  logic [31:0] s_pend_data_q;
  logic [3:0] s_pend_keep_q;
  logic s_pend_last_q;
  // packer wires
  logic s_pack_start;
  logic s_pack_ready;
  logic s_pack_busy;
  logic s_pack_done;
  logic s_pack_raw_valid;
  logic [12:0] s_pack_raw_addr;
  logic s_pack_wr_valid;
  logic [12:0] s_pack_wr_addr;
  logic [63:0] s_pack_wr_data;
  logic [7:0] s_pack_wr_strb;
  logic [12:0] s_pack_base_q;  // packed-A row base of the current slice
  // parameter slice of the current channel group (16B records)
  logic [5:0] s_pr_count_q;  // param words to read (32 group slice, 8 ADD)
  logic [5:0] s_pr_idx_q;
  logic s_pr_add_q;  // reading the 32-byte ADD record at descriptor init
  logic s_pr_fault;  // parameter-encoding violation in the fetched record
  logic [7:0][31:0] s_pbias_q;
  logic [7:0][31:0] s_pmult_q;
  logic [7:0][7:0] s_pshift_q;
  logic [31:0] s_add_m_q[3];  // ADD m0, m1, mout
  logic [7:0] s_add_s_q[3];  // ADD s0, s1, sout
  // MAC stream pipeline
  logic s_mac_req_valid;
  logic s_mac_req_ready;
  logic s_mac_resp_valid;
  logic s_mac_resp_ready;
  logic [7:0][7:0][16:0] s_mac_resp_products;
  logic [24:0] s_mac_k_q;  // rows issued of the current slice
  logic [24:0] s_mac_done_q;  // rows accepted by the accumulator
  logic s_mac_pend_q;  // one SRAM read in flight toward the MAC
  logic s_acc_start_valid;
  logic s_acc_start_ready;
  logic s_acc_ctx;
  logic s_acc_row_valid;
  logic s_acc_row_ready;
  logic s_acc_drain_valid;
  logic s_acc_drain_data_valid;
  logic s_acc_drain_data_ready;
  logic [31:0] s_acc_drain_data;
  logic s_acc_drain_last;
  logic s_acc_busy;
  logic s_acc_fault;
  logic [5:0] s_acc_fault_sum;
  logic s_ctx_q;  // acquired accumulator context token
  logic [6:0] s_drain_idx_q;  // drain beat index (0..64)
  logic [2:0] s_feed_p_q, s_feed_c_q;  // (position, lane) of the next fed item
  logic [2:0] s_resp_p_q, s_resp_c_q;  // (position, lane) of the next response
  logic        [12:0] s_resp_off_q;  // staging byte offset of the next response
  // vector unit wires
  logic               s_vec_start_valid;
  logic               s_vec_start_ready;
  logic               s_vec_dw_valid;
  logic               s_vec_dw_ready;
  logic               s_vec_aux_valid;
  logic               s_vec_drain_valid;
  logic               s_vec_drain_data_valid;
  logic               s_vec_drain_data_ready;
  logic        [31:0] s_vec_drain_data;
  logic               s_vec_drain_last;
  logic signed [31:0] s_vec_aux_result;
  logic               s_vec_busy;
  logic               s_vec_fault;
  logic        [ 2:0] s_vec_fault_lane;
  logic        [ 3:0] s_vec_k_q;  // DW rows streamed of the current position
  // pool / GAP readback
  logic        [ 1:0] s_rb_sel_q;
  logic               s_rb_pend_q;
  logic        [12:0] s_pool_k_q;  // taps/positions fed for the current channel
  logic        [12:0] s_pool_c_q;  // channel lane being reduced
  logic        [12:0] s_pool_vcnt_q;  // valid taps of the current pool position
  logic signed [31:0] s_pool_total_q                                                    [8];
  logic               s_pool_total_ovf;
  logic signed [31:0] s_pool_total_sel;
  logic signed [31:0] s_pool_total_next;
  logic        [24:0] s_gap_chunk_q;  // positions already rastered of the GAP reduction
  logic        [12:0] s_gap_cpos_q;  // positions of the current GAP chunk
  logic        [12:0] s_gap_cpos_comb;
  // requantizer wires
  logic               s_rq_req_valid;
  logic               s_rq_req_ready;
  logic signed [31:0] s_rq_req_acc;
  logic        [31:0] s_rq_req_mult;
  logic        [ 7:0] s_rq_req_shift;
  logic               s_rq_resp_valid;
  logic               s_rq_resp_ready;
  logic        [ 7:0] s_rq_resp_data;
  logic               s_rq_resp_fault;
  logic        [ 6:0] s_rq_out_q;  // requantizer items in flight
  // ADD inline QM pipeline (bit-exact with npu_requantizer's math)
  logic               s_aqm_v0_q;
  logic signed [31:0] s_aqm_d0_q;
  logic               s_aqm_f0_q;
  logic        [31:0] s_aqm_m0_q;
  logic signed [ 7:0] s_aqm_s0_q;
  logic        [ 6:0] s_aqm_t0_q;
  logic               s_aqm_v1_q;
  logic signed [63:0] s_aqm_p1_q;
  logic               s_aqm_f1_q;
  logic signed [ 7:0] s_aqm_s1_q;
  logic        [ 6:0] s_aqm_t1_q;
  logic               s_aqm_v2_q;
  logic signed [31:0] s_aqm_d2_q;
  logic               s_aqm_f2_q;
  logic        [ 6:0] s_aqm_t2_q;
  logic               s_aqm_s1_free;
  logic               s_aqm_s2_free;
  logic               s_aqm_load0;
  logic signed [31:0] s_add_t0_q;  // held first term of the current output pair
  logic               s_add_total_ovf;
  logic [3:0] s_add_p_q, s_add_c_q;
  logic        s_add_in_q;  // input index of the feed (0/1)
  // shared restoring divider (pool/GAP divide, descriptor pass capacity)
  logic        s_div_busy_q;
  logic [31:0] s_div_num_q;
  logic [24:0] s_div_den_q;
  logic [32:0] s_div_rem_q;
  logic [31:0] s_div_quo_q;
  logic [ 5:0] s_div_cnt_q;
  // store engine
  logic [31:0] s_st_pos_addr_q;
  logic [31:0] s_st_cur_q;
  logic [24:0] s_st_rem_q;
  logic [31:0] s_st_pad_q;  // OUTPUT_ROW_BYTES - OW*Cout (inter-row pad)
  logic [12:0] s_st_cmd_bytes_q;
  logic [ 4:0] s_st_beats_q;
  logic [ 4:0] s_st_beat_idx_q;
  logic [ 2:0] s_st_phase_q;
  logic [31:0] s_st_w0_q, s_st_w1_q, s_st_w2_q;
  logic [12:0] s_st_soff_q;  // staging byte offset of the stored position
  // watchdog and counters
  logic [31:0] s_timeout_q;
  logic [31:0] s_wdog_q;
  logic [63:0] s_cnt_active_q, s_cnt_pause_q, s_cnt_pack_q, s_cnt_retired_q;
  logic [63:0] s_cnt_macs_q, s_cnt_bank_q, s_cnt_rqstall_q;
  logic        [ 31:0] s_completed_q;
  logic        [639:0] s_term_q;
  // fault record
  logic                s_fault_seen_q;
  logic        [  3:0] s_fault_code_q;
  logic        [ 31:0] s_fault_addr_q;
  logic        [ 31:0] s_fault_info_q;
  logic                s_arith_fault;
  logic        [  7:0] s_arith_lane;
  logic                s_desc_fault;
  logic        [ 31:0] s_desc_faddr;
  logic                s_unsup_fault;

  logic                s_is_gap;
  logic                s_is_dense;
  logic                s_is_dw;
  logic                s_is_pool;
  logic                s_is_add;
  logic                s_is_clamp;
  logic                s_is_grouped;  // group-windowed channel gathers (not dense)
  logic                s_a_reuse;  // whole dense reduction fits one A half
  logic        [ 12:0] s_kw_lim;
  logic        [ 31:0] s_iy_in;
  logic        [ 31:0] s_ix_in;
  logic                s_in_range;
  logic        [ 63:0] s_seg_addr_full;
  logic        [ 12:0] s_run_max;
  logic        [ 12:0] s_chunk_left;
  logic                s_seg_pad;
  logic                s_read_accept;
  logic                s_stream_accept;
  logic                s_seg_stream_done;
  logic                s_iter_wrap;
  logic                s_pos_done;
  // store beat planning (mirrors the npu_dma single-burst plan)
  logic        [ 31:0] s_st_aligned;
  logic        [ 13:0] s_st_span_beats;
  logic        [ 33:0] s_st_span_sum;
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
  logic        [ 12:0] s_st_rdaddr;
  logic                s_write_accept;
  logic                s_cmd_w_accept;
  logic                s_progress;
  logic                s_wdog_fire;
  logic                s_drain_quiet;
  logic        [639:0] s_live_counters;
  logic                s_sram_err;
  logic                s_sram_clear;
  logic                s_unit_clear;
  logic                s_iter_advance;
  logic                s_stage_valid;
  logic                s_stage_grant;
  logic        [ 12:0] s_stage_addr;
  logic        [  7:0] s_stage_byte;
  logic                s_store_active;
  // loop-condition registers and helpers
  logic                s_granule_done;
  logic                s_slice_last;
  logic                s_group_last;
  logic                s_drain_done;
  logic                s_vec_drain_done;
  logic                s_pr_done;
  logic                s_pr_pend_q;
  logic                s_pool_stream_last;
  logic                s_gap_more_chunks;
  logic                s_gap_stream_last;
  logic                s_pool_stage_done;
  logic                s_add_done;
  logic                s_add_loop_done_q;
  logic                s_add_in1_q;
  logic                s_add_params_done_q;
  logic                s_pass_last;
  logic                s_tile_last;
  logic        [  6:0] s_tile_m_q;
  logic        [  6:0] s_tile_m_comb;
  logic        [  3:0] s_pcnt_first;
  logic        [  3:0] s_pcnt_next;
  logic        [  3:0] s_pcnt_tile;
  logic        [ 10:0] s_next_klen;
  logic        [ 10:0] s_first_klen;
  logic        [  3:0] s_tile_cols_next;
  logic        [  3:0] s_tile_rows_next;
  logic        [  6:0] s_tile_m_next;
  logic        [ 12:0] s_st_oy;
  logic        [ 12:0] s_st_ox;
  logic                s_st_row_pad;
  logic        [ 31:0] s_pool_div_num;
  logic        [ 24:0] s_pool_div_den;
  logic                s_pool_div_neg;
  logic        [ 12:0] s_resp_cnt_q;
  logic        [ 12:0] s_fed_total_q;
  logic        [  1:0] s_acc_if_q;
  logic                s_pool_loop_last;
  logic        [ 31:0] s_div_quo_next;
  logic        [ 31:0] s_gap_next_num;
  logic                s_gap_next_neg;
  logic        [ 31:0] s_gap_first_num;
  logic                s_gap_first_neg;
  logic                s_div_issued_q;
  logic [3:0] s_st_dy_q, s_st_dx_q;
  logic                     s_param_read_valid;
  logic        [12:0]       s_param_read_addr;
  logic        [ 7:0]       s_mac_a_valid;
  logic        [ 7:0]       s_mac_w_valid;
  logic        [ 7:0][31:0] s_vec_bias;
  logic        [ 1:0]       s_vec_aux_op;
  logic                     s_feed_valid;
  logic                     s_pr_shift_bad;
  logic        [31:0]       s_param_read_data;
  logic                     s_a_read_valid;
  logic        [12:0]       s_a_read_addr;
  logic        [63:0]       s_a_read_data;
  logic                     s_a_read_half;
  logic                     s_w_read_valid;
  logic        [12:0]       s_w_read_addr;
  logic        [63:0]       s_w_read_data;
  logic                     s_w_read_half;
  logic        [24:0]       s_stream_len_q;
  logic        [12:0]       s_vec_row;
  logic        [33:0]       s_wrow_abs;
  logic        [ 9:0]       s_wrow_lsb;
  logic                     s_acc_drain_pulse_q;
  logic                     s_vec_drain_pulse_q;
  logic                     s_pool_take;
  logic                     s_pool_more;
  logic                     s_clamp_more;
  logic                     s_add_more;
  logic                     s_rb_half_q;
  logic        [12:0]       s_add_byte_off;
  logic        [12:0]       s_clamp_off_q;
  logic        [12:0]       s_clamp_stg_q;
  logic        [ 2:0]       s_clamp_c_q;
  logic        [12:0]       s_clamp_len_q;
  logic        [12:0]       s_pool_off_q;
  logic        [ 7:0]       s_pool_byte;
  logic        [ 7:0]       s_clamp_byte;
  logic                     s_pool_stage_q;
  logic                     s_add_total_valid;
  logic signed [31:0]       s_add_total;
  logic        [ 7:0]       s_rb_byte;
  logic [12:0] s_rb_kh_q, s_rb_kw_q;
  logic [12:0] s_pool_kmax_q;
  logic [31:0] s_pool_iy, s_pool_ix;
  logic               s_pool_in;
  logic signed [32:0] s_pool_clamp_in;
  logic signed [32:0] s_pool_div_val;
  logic               s_pool_neg_q;
  logic        [12:0] s_pool_staging_off;
  logic        [12:0] s_pidx_off_q;
  logic        [12:0] s_slot_q;  // word-aligned staging slot stride
  logic        [13:0] s_slot_comb;
  // ADD inline QM path
  logic signed [ 8:0] s_aqm_centered;
  logic signed [ 7:0] s_aqm_zp;
  logic signed [31:0] s_aqm_in_data;
  logic signed [ 7:0] s_aqm_in_shift;
  logic        [31:0] s_aqm_in_mult;
  logic signed [63:0] s_aqm_shifted;
  logic               s_aqm_shift_fault;
  logic        [ 4:0] s_aqm_rdp_exp;
  logic               s_aqm_consume;
  logic               s_raw_rb_valid;
  logic        [12:0] s_raw_rb_addr;
  logic               s_out_half;
  logic               s_raw_read_half;
  logic               s_out_read_valid;
  logic        [11:0] s_out_read_addr;

  // local SRAM and packer port wires
  logic               s_raw_write_valid;
  logic        [12:0] s_raw_write_addr;
  logic        [31:0] s_raw_write_data;
  logic        [ 3:0] s_raw_write_strb;
  logic               s_raw_read_valid;
  logic        [12:0] s_raw_read_addr;
  logic        [31:0] s_raw_read_data;
  logic               s_pack_write_valid;
  logic               s_pack_write_sel_w;
  logic               s_pack_write_half;
  logic        [12:0] s_pack_write_addr;
  logic        [63:0] s_pack_write_data;
  logic        [ 7:0] s_pack_write_strb;
  logic               s_out_valid;
  logic               s_out_write;
  logic        [11:0] s_out_addr;
  logic        [31:0] s_out_wdata;
  logic        [ 3:0] s_out_wstrb;
  logic        [31:0] s_out_rdata;
  logic               s_param_write_valid;
  logic        [12:0] s_param_write_addr;
  logic        [31:0] s_param_write_data;
  logic        [ 3:0] s_param_write_strb;

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
  assign s_is_dense = (s_op_q == `APB4_NPU__OP_CONV2D) || (s_op_q == `APB4_NPU__OP_FULLY_CONNECTED);
  assign s_is_dw = (s_op_q == `APB4_NPU__OP_DEPTHWISE3X3);
  assign s_is_pool = (s_op_q == `APB4_NPU__OP_MAX_POOL) || (s_op_q == `APB4_NPU__OP_AVERAGE_POOL);
  assign s_is_add = (s_op_q == `APB4_NPU__OP_ADD);
  assign s_is_clamp = (s_op_q == `APB4_NPU__OP_CLAMP);
  // Grouped ops gather a group-windowed channel slice per unit (tap/raster
  // position); dense gathers the whole Cin reduction per position.
  assign s_is_grouped = s_is_dw || s_is_pool || s_is_gap || s_is_add || s_is_clamp;
  // A-half reuse: the whole dense reduction packs into one A half.
  assign s_a_reuse = s_is_dense && (s_gather_len_q <= 33'd1024);
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
  // iterator-math cycle (SchGathSeg) and the command output path. The granule
  // window (s_gbase_q/s_grow_q) selects input0 or input1 for ADD.
  assign s_seg_addr_full = {32'd0, s_gbase_q} + {32'd0, s_iy_q} * {32'd0, s_grow_q} +
      ({32'd0, s_ix_q} * {51'd0, s_cin_q}) + {51'd0, s_gcbase_q} + {51'd0, s_ci_q};
  assign s_seg_addr = s_seg_addr_full[31:0];
  // Run bound: dense streams contiguous Cin runs bounded by the position
  // window; grouped ops emit the group's real lanes, then a pad run filling
  // the unit to eight bytes (tail or out-of-range).
  assign s_run_max = s_is_grouped ?
      (({10'd0, s_ci_q[2:0]} >= {10'd0, s_glane_q}) ? ({1'b0, 4'd8} - {1'b0, s_ci_q[2:0]}) :
       ({1'b0, s_glane_q} - {1'b0, s_ci_q[2:0]})) : (s_cin_q - s_ci_q);
  assign s_chunk_left = 13'(s_gpos_bytes_q - {2'd0, s_kloc_q});
  assign s_seg_run = (s_run_max < s_chunk_left) ? s_run_max : s_chunk_left;
  // A pad segment writes local zero-point bytes instead of a DMA fetch: the
  // position is out of range, or a grouped tail lane is beyond the group.
  assign s_seg_pad = !s_in_range_q ||
      (s_is_grouped && ({10'd0, s_ci_q[2:0]} >= {10'd0, s_glane_q}));

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
  assign s_iter_wrap = s_is_grouped ? ({1'b0, s_ci_q[2:0]} + {1'b0, s_seg_run}) >= 5'd8 :
      (({1'b0, s_ci_q} + {1'b0, s_seg_run}) >= {1'b0, s_cin_q});
  assign s_pos_done = ({1'b0, s_kloc_q} + {1'b0, s_seg_run}) >= {1'b0, s_gpos_bytes_q};

  // padding word write helpers
  assign s_pad_room = 3'd4 - {1'b0, s_pad_head_q[1:0]};
  assign s_pad_n = ({11'd0, s_pad_room} > {1'b0, s_seg_left_q}) ? 3'(s_seg_left_q) : s_pad_room;

  // Store chunk planning: mirrors the npu_dma burst plan so every write
  // command is executed as exactly one burst (write_done_i per chunk).
  assign s_st_aligned = {s_st_cur_q[31:3], 3'b000};
  assign s_st_span_sum = ({30'd0, s_st_cur_q[2:0]} + {6'd0, s_st_rem_q} + 34'd7) >> 3;
  assign s_st_span_beats = (s_st_span_sum > 34'd16) ? 14'd17 : 14'(s_st_span_sum);
  assign s_st_beats_4k = (13'd4096 - {1'b0, s_st_aligned[11:0]}) >> 3;
  assign s_st_plan_beats = (s_st_span_beats > 14'd16) ? 5'd16 :
      (s_st_span_beats > {1'b0, s_st_beats_4k}) ? 5'(s_st_beats_4k) : 5'(s_st_span_beats);
  assign s_st_plan_room = ({5'd0, s_st_plan_beats, 3'b000} - {10'd0, s_st_cur_q[2:0]});
  assign s_st_plan_bytes = (s_st_rem_q < {12'd0, s_st_plan_room}) ? 13'(s_st_rem_q) :
      s_st_plan_room;

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
  assign s_st_nwords = (s_st_blo > s_st_bhi) ? 3'd0 :
      3'({1'b0, s_st_bhi[11:2]} - {1'b0, s_st_blo[11:2]} + 2'd1);
  always_comb begin
    logic        [11:0] s_byte_index;
    logic signed [14:0] s_lane_off;
    s_st_beat_data = 64'd0;
    for (int unsigned lane = 0; lane < 8; lane++) begin
      s_byte_index = (12'({1'b0, s_st_beat_off[11:0]}) + {9'd0, lane[2:0]}) - s_st_wb;
      // keep lanes always address bytes at/after the position start, so the
      // signed lane offset is nonnegative exactly where it indexes staging
      s_lane_off   = $signed(s_st_beat_off) + $signed({11'd0, lane[2:0]});
      if (s_st_beat_keep[lane]) begin
        if (s_lane_off >= $signed({2'd0, s_cout_q})) begin
          // inter-row zero padding: never staged, stored as zero
          s_st_beat_data[lane*8+:8] = 8'd0;
        end else begin
          unique case (s_byte_index[11:2])
            10'd0:   s_st_beat_data[lane*8+:8] = s_st_w0_q[{s_byte_index[1:0], 3'b000}+:8];
            10'd1:   s_st_beat_data[lane*8+:8] = s_st_w1_q[{s_byte_index[1:0], 3'b000}+:8];
            default: s_st_beat_data[lane*8+:8] = s_st_w2_q[{s_byte_index[1:0], 3'b000}+:8];
          endcase
        end
      end
    end
  end

  assign s_progress = s_stream_accept || s_write_accept || s_cmd_w_accept || s_read_accept ||
      write_done_i || s_pack_done || retired_o || progress_i ||
      (s_mac_req_valid && s_mac_req_ready) || (s_acc_row_valid && s_acc_row_ready) ||
      (s_vec_dw_valid && s_vec_dw_ready) || s_vec_aux_valid ||
      (s_rq_req_valid && s_rq_req_ready) || (s_rq_resp_valid && s_rq_resp_ready) ||
      s_stage_grant ||
      (s_acc_drain_data_valid && s_acc_drain_data_ready) ||
      (s_vec_drain_data_valid && s_vec_drain_data_ready);
  assign s_wdog_fire = job_active_i && !pause_active_i && !s_fault_seen_q && !s_progress &&
      (s_wdog_q == (s_timeout_q - 32'd1));
  assign s_drain_quiet = !dma_read_busy_i && !dma_write_busy_i && !s_pack_busy &&
      !read_data_valid_i && (s_q_cnt_q == 5'd0) && !s_acc_busy && !s_vec_busy &&
      !s_mac_pend_q && !s_mac_resp_valid && !s_rb_pend_q && !s_aqm_v0_q && !s_aqm_v1_q &&
      !s_aqm_v2_q && !s_div_busy_q;

  assign s_live_counters = {
    s_cnt_retired_q,
    s_cnt_rqstall_q,
    dma_stall_cycles_i,
    dma_write_bytes_i,
    dma_read_bytes_i,
    s_cnt_bank_q,
    s_cnt_pack_q,
    s_cnt_macs_q,
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
  // in-flight MAC/vector/requantizer/readback items, no mid-assembly store
  // beat (a presented-but unaccepted write beat may stay), packer idle, no
  // accepted read data still streaming, and the DMA reporting zero accepted
  // obligations. Held accumulator/vector context sums are stable state, not
  // in-flight work, and survive the pause.
  assign pause_ok_o = block_new_i && dma_pause_ack_i && !s_pack_busy && !read_data_valid_i &&
      (s_q_cnt_q == 5'd0) && (s_rq_out_q == 7'd0) && !s_mac_pend_q && !s_mac_resp_valid &&
      !s_rb_pend_q && !s_aqm_v0_q && !s_aqm_v1_q && !s_aqm_v2_q && !s_div_busy_q &&
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
  // compute units clear on a fabric clear and every launch, and must also
  // clear during the fault drain: a latched ARITHMETIC fault holds the
  // accumulator/vector in their Fault state, which would otherwise keep
  // them busy and deadlock s_drain_quiet in SchFaultWait
  assign s_unit_clear = s_sram_clear || (s_state_q == SchFaultWait);

  // raw gather read port: the packer wins while it runs; compute readback
  // (pool/GAP/ADD/CLAMP streams) owns it otherwise. The read address is the
  // half-relative byte offset; the half select is a separate pin.
  assign s_raw_read_valid = s_pack_busy ? s_pack_raw_valid : s_raw_rb_valid;
  assign s_raw_read_addr = s_pack_busy ? s_pack_raw_addr : s_raw_rb_addr;
  assign s_raw_read_half = s_pack_busy ? s_ghalf_q :
      (s_is_add && (s_state_q == SchAddFeed) ? s_add_in_q : s_rb_half_q);

  assign s_raw_write_valid = ((s_state_q == SchGathStream) && (s_pop_n != 3'd0)) ||
      ((s_state_q == SchGathPad) && !block_new_i && !clear_i && (s_seg_left_q != 13'd0));
  assign s_raw_write_addr = (s_state_q == SchGathPad) ? s_pad_head_q : s_q_base_q;
  assign s_raw_write_data = (s_state_q == SchGathPad) ? {4{s_zp_q}} :
      32'(({24'd0, s_q_bytes_q[3], s_q_bytes_q[2], s_q_bytes_q[1], s_q_bytes_q[0]}) <<
          {s_q_base_q[1:0], 3'b000});
  assign s_raw_write_strb = (s_state_q == SchGathPad) ?
      (4'(((4'd1 << s_pad_n) - 4'd1) << {2'd0, s_pad_head_q[1:0]})) :
      (4'(((4'd1 << s_pop_n) - 4'd1) << {2'd0, s_q_base_q[1:0]}));

  assign s_pack_write_valid = s_pack_busy ? s_pack_wr_valid :
      ((s_state_q == SchWStream) && s_stream_accept && !clear_i);
  assign s_pack_write_sel_w = !s_pack_busy;
  assign s_pack_write_half = s_pack_busy ? s_ahalf_q : s_whalf_q;
  assign s_pack_write_addr = s_pack_busy ? (s_pack_base_q + s_pack_wr_addr) : 13'(s_wfill_off_q);
  assign s_pack_write_data = s_pack_busy ? s_pack_wr_data : read_data_i;
  assign s_pack_write_strb = s_pack_busy ? s_pack_wr_strb : read_keep_i;

  // Output staging port: staging byte writes (requantize drain / pool / clamp)
  // yield to the store engine's read phases. Store-active windows block stage
  // writes so a pass never overwrites bytes the previous pass is draining.
  assign s_store_active = (s_state_q == SchStoreInit) || (s_state_q == SchStoreChunk) ||
      (s_state_q == SchStoreCmd) || (s_state_q == SchStoreBeat) || (s_state_q == SchStoreWait);
  assign s_stage_grant = s_stage_valid && !s_store_active && !clear_i;
  assign s_out_valid = s_stage_grant ||
      ((s_state_q == SchStoreBeat) && (s_st_nwords != 3'd0) &&
       (((s_st_phase_q == 3'd0) && !block_new_i) ||
        ((s_st_phase_q == 3'd1) && (s_st_nwords > 3'd1)) ||
        ((s_st_phase_q == 3'd2) && (s_st_nwords > 3'd2))));
  assign s_out_write = !s_store_active;
  assign s_out_half = s_out_write ? s_stage_addr[12] : s_st_rdaddr[12];
  assign s_out_addr = s_out_write ? s_stage_addr[11:0] : s_st_rdaddr[11:0];
  assign s_out_wdata = {4{s_stage_byte}};
  assign s_out_wstrb = 4'(4'd1 << s_stage_addr[1:0]);
  assign s_st_rdaddr = s_st_soff_q + {1'b0, s_st_wb} + {8'd0, s_st_phase_q[1:0], 2'b00};

  assign s_param_write_valid = (s_state_q == SchPStream) && !clear_i &&
      ((s_stream_accept && !s_phalf_q) || s_phalf_q);
  assign s_param_write_addr = s_poff_q + {10'd0, s_phalf_q, 2'b00};
  assign s_param_write_data = s_phalf_q ? s_pend_data_q : read_data_i[31:0];
  assign s_param_write_strb = s_phalf_q ? s_pend_keep_q : read_keep_i[3:0];

  assign s_pack_start = (s_state_q == SchPackStart) && !block_new_i && !stop_i && !clear_i;

  // ---------------------------------------------------------------------
  // Compute engines: MAC stream, accumulator, vector, requantizer, divider,
  // readback pipeline and the ADD inline QM path
  // ---------------------------------------------------------------------
  // A/W compute reads: one 64-bit row per cycle per operand. Dense streams
  // s_stream_len_q rows; depthwise streams nine rows of one position.
  assign s_a_read_valid = ((s_state_q == SchMacStream) && (s_mac_k_q < s_stream_len_q) &&
                           (!s_mac_pend_q || s_mac_req_ready)) ||
      ((s_state_q == SchVecStream) && (s_vec_k_q < 4'd9) && (!s_mac_pend_q || s_vec_dw_ready));
  assign s_a_read_addr = (s_state_q == SchMacStream) ? 13'(s_mac_k_q[10:0] << 3) :
      13'((s_vec_row << 3));
  assign s_w_read_valid = s_a_read_valid;
  assign s_w_read_addr = s_w_stream_q ?
      ((s_state_q == SchMacStream) ? 13'(s_mac_k_q[9:0] << 3) :
       13'({9'd0, s_vec_k_q} << 3)) : 13'(s_wrow_lsb[9:0] << 3);
  assign s_vec_row = {8'd0, s_pidx_q} * 13'd9 + {9'd0, s_vec_k_q};
  assign s_wrow_abs = {24'd0, s_wrow_q} + {9'd0, s_ks0_q} +
      ((s_state_q == SchMacStream) ? {9'd0, s_mac_k_q} : {30'd0, s_vec_k_q});
  assign s_wrow_lsb = 10'(s_wrow_abs);
  assign s_w_read_half = s_w_stream_q ? 1'b0 : s_wrow_abs[10];
  assign s_a_read_half = s_ahalf_q;

  // MAC array handshake: consume a returned row each cycle. The fault drain
  // also consumes (and drops) a pending response so s_drain_quiet can fire.
  assign s_mac_req_valid = (s_state_q == SchMacStream) && s_mac_pend_q;
  assign s_mac_resp_ready = s_acc_row_ready || (s_state_q == SchFaultWait);
  assign s_acc_row_valid = s_mac_resp_valid;

  // Accumulator context acquire and drain.
  assign s_acc_start_valid = (s_state_q == SchAccStart) && (s_ks0_q == 25'd0);
  assign s_acc_drain_valid = s_acc_drain_pulse_q;
  assign s_feed_valid = ((s_state_q == SchAccDrain) ? ({5'd0, s_drain_idx_q[5:3]} <
      {5'd0, s_pcnt_q}) : 1'b1) && ({5'd0, s_drain_idx_q[2:0]} < {5'd0, s_glane_q});
  assign s_acc_drain_data_ready = (s_state_q == SchAccDrain) &&
      (s_feed_valid ? s_rq_req_ready : 1'b1);
  // Drain feed position/lane derive directly from the drain beat index
  // (dense: index = position*8 + lane; depthwise: index = lane).
  assign s_feed_p_q = (s_state_q == SchAccDrain) ? s_drain_idx_q[5:3] : 3'd0;
  assign s_feed_c_q = s_drain_idx_q[2:0];

  // Vector unit handshake.
  assign s_vec_start_valid = (s_state_q == SchVecStart);
  assign s_vec_dw_valid = (s_state_q == SchVecStream) && s_mac_pend_q;
  assign s_vec_aux_valid = (s_state_q == SchPoolStream) && s_rb_pend_q && s_pool_take;
  assign s_vec_drain_valid = s_vec_drain_pulse_q;
  assign s_vec_drain_data_ready = (s_state_q == SchVecDrain) &&
      (s_is_dw ? (s_feed_valid ? s_rq_req_ready : 1'b1) : 1'b1);

  // Requantizer request mux: accumulator drain (dense), vector drain
  // (depthwise) and ADD checked totals share the scalar pipe.
  assign s_rq_req_valid = ((s_state_q == SchAccDrain) && s_acc_drain_data_valid && s_feed_valid) ||
      ((s_state_q == SchVecDrain) && s_vec_drain_data_valid && s_feed_valid && s_is_dw) ||
      ((s_state_q == SchAddFeed) && s_add_total_valid);
  assign s_rq_req_acc = (s_state_q == SchAddFeed) ? s_add_total :
      ((s_state_q == SchVecDrain) ? s_vec_drain_data : s_acc_drain_data);
  assign s_rq_req_mult = (s_state_q == SchAddFeed) ? s_add_m_q[2] : s_pmult_q[s_feed_c_q];
  assign s_rq_req_shift = (s_state_q == SchAddFeed) ? s_add_s_q[2] : s_pshift_q[s_feed_c_q];

  // Readback issue: pool skips padding taps without a read; clamp/ADD read
  // every byte of the granule.
  assign s_raw_rb_valid = ((s_state_q == SchPoolStream) && !s_rb_pend_q &&
                           (s_pool_k_q < s_pool_kmax_q) && s_pool_in) ||
      ((s_state_q == SchClamp) && !s_rb_pend_q && (s_clamp_off_q < s_clamp_len_q)) ||
      ((s_state_q == SchAddFeed) && !s_rb_pend_q && s_add_more);
  // Readback issue addresses per consumer; the byte lane registers at issue.
  // Offsets are half-relative byte addresses (bit 12 picks the bank pair).
  assign s_raw_rb_addr = (s_state_q == SchPoolStream) ?
      {s_pool_k_q[9:0], s_pool_c_q[2:0]} :
      ((s_state_q == SchAddFeed) ? {1'b0, s_add_byte_off[11:0]} : {1'b0, s_clamp_off_q[11:0]});
  assign s_rb_byte = s_raw_read_data[{s_rb_sel_q, 3'b000}+:8];

  // Staging byte writer mux (one byte per cycle into output staging). A
  // faulting response is consumed without a staging write.
  assign s_stage_valid = (s_rq_resp_valid && !s_rq_resp_fault) ||
      ((s_state_q == SchPoolDiv) && s_pool_stage_q) ||
      ((s_state_q == SchClamp) && s_rb_pend_q &&
       ({10'd0, s_clamp_c_q} < {10'd0, s_glane_q}));
  assign s_stage_addr = (s_state_q == SchClamp) ? s_clamp_stg_q :
      ((s_state_q == SchPoolDiv) ? s_pool_off_q : s_resp_off_q);
  assign s_stage_byte = (s_state_q == SchClamp) ? s_clamp_byte :
      ((s_state_q == SchPoolDiv) ? s_pool_byte : s_rq_resp_data);
  assign s_rq_resp_ready = s_stage_grant || s_rq_resp_fault;

  // Pool/GAP readback geometry: taps decompose through the same kernel-window
  // counters as the gather (s_rb_kh_q/s_rb_kw_q); GAP rasters with kw=w.
  assign s_pool_iy = 32'($signed(
      {19'd0, s_oy_q}
  ) * $signed(
      {24'd0, s_sh_q}
  ) + $signed(
      {19'd0, s_rb_kh_q}
  ) - $signed(
      {24'd0, s_pad_t_q}
  ));
  assign s_pool_ix = 32'($signed(
      {19'd0, s_ox_q}
  ) * $signed(
      {24'd0, s_sw_q}
  ) + $signed(
      {19'd0, s_rb_kw_q}
  ) - $signed(
      {24'd0, s_pad_l_q}
  ));
  assign s_pool_in = s_is_gap || ((s_pool_iy < {19'd0, s_h_q}) && (s_pool_ix < {19'd0, s_w_q}) &&
      !s_pool_iy[31] && !s_pool_ix[31]);
  assign s_pool_more = s_rb_pend_q || (s_pool_k_q < s_pool_kmax_q);
  assign s_pool_take = s_rb_pend_q;
  assign s_pool_off_q = s_pool_staging_off;
  assign s_pool_staging_off = s_is_gap ? ({1'b0, s_gcbase_q} + {10'd0, s_pool_c_q[2:0]}) :
      13'(s_pidx_off_q + {1'b0, s_gcbase_q} + {10'd0, s_pool_c_q[2:0]});
  assign s_pidx_off_q = {8'd0, s_pidx_q} * s_slot_q;
  assign s_slot_comb = ({1'b0, s_cout_q} + 14'd3) & 14'h3ffc;

  // Widened clamp to the activation bounds (pool/GAP/CLAMP output path).
  function automatic logic [7:0] act_clamp(input logic signed [32:0] value_i,
                                           input logic signed [7:0] act_min_i,
                                           input logic signed [7:0] act_max_i);
    logic signed [32:0] s_min_ext;
    logic signed [32:0] s_max_ext;
    begin
      s_min_ext = {{25{act_min_i[7]}}, act_min_i};
      s_max_ext = {{25{act_max_i[7]}}, act_max_i};
      if (value_i > s_max_ext) begin
        return act_max_i;
      end else if (value_i < s_min_ext) begin
        return act_min_i;
      end
      return value_i[7:0];
    end
  endfunction

  assign s_pool_byte = act_clamp(s_pool_clamp_in, s_act_min_q, s_act_max_q);
  assign s_pool_clamp_in = (s_op_q == `APB4_NPU__OP_MAX_POOL) ? {{25{s_vec_aux_result[7]}},
      s_vec_aux_result[7:0]} : s_pool_div_val;
  assign s_pool_div_val = s_pool_neg_q ? -33'({1'b0, s_div_quo_q}) : 33'({1'b0, s_div_quo_q});
  assign s_clamp_byte = act_clamp({{25{s_rb_byte[7]}}, s_rb_byte}, s_act_min_q, s_act_max_q);
  assign s_clamp_more = s_rb_pend_q || (s_clamp_off_q < s_clamp_len_q);

  // ADD inline QM path, bit-exact with npu_requantizer's math. Stage 0
  // registers the checked left shift, stage 1 the 32x32 product, stage 2 the
  // nudge+truncate and RoundingDivideByPOT term. Terms collect into checked
  // INT32 output sums; stage 2 transfers when the collection accepts it.
  assign s_aqm_centered = $signed({s_rb_byte[7], s_rb_byte}) - $signed({s_aqm_zp[7], s_aqm_zp});
  assign s_aqm_zp = s_add_in_q ? s_z1_q : s_zp_q;
  assign s_aqm_in_data = 32'(s_aqm_centered) <<< 20;
  assign s_aqm_in_shift = s_add_in_q ? s_add_s_q[1] : s_add_s_q[0];
  assign s_aqm_in_mult = s_add_in_q ? s_add_m_q[1] : s_add_m_q[0];
  assign s_aqm_shifted = 64'(s_aqm_in_data) <<< s_aqm_in_shift[5:0];
  assign s_aqm_shift_fault = (s_aqm_in_shift > 8'sd0) && (s_aqm_shifted != 64'($signed(
      s_aqm_shifted[31:0]
  )));
  assign s_aqm_rdp_exp = (s_aqm_s1_q < 8'sd0) ? 5'(-s_aqm_s1_q) : 5'd0;
  assign s_add_total = s_add_t0_q + s_aqm_d2_q;
  assign s_add_total_valid = s_aqm_v2_q && s_aqm_t2_q[0] && !s_aqm_f2_q &&
      (s_state_q == SchAddFeed);
  assign s_aqm_consume = s_aqm_v2_q &&
      (!s_aqm_t2_q[0] || ((s_state_q == SchAddFeed) && s_rq_req_ready));

  // Loop-condition helpers
  assign s_granule_done = (s_g_q + {8'd0, s_seg_run}) >= {8'd0, s_granule_q};
  assign s_slice_last = ({1'b0, s_ks0_q} + {15'd0, s_klen_q}) >= {1'b0, s_full_k_q};
  assign s_group_last = ({22'd0, s_group_q} + 32'd1) >= {22'd0, s_groups_q};
  assign s_drain_done = (s_drain_idx_q >= 7'd64) && (s_resp_cnt_q >= s_fed_total_q);
  assign s_vec_drain_done = (s_drain_idx_q >= 7'd8) && (s_resp_cnt_q >= s_fed_total_q);
  assign s_pr_done = (s_pr_idx_q >= s_pr_count_q) && !s_pr_pend_q;
  assign s_pool_stream_last = ({19'd0, s_pool_c_q} + 14'd1) >= {19'd0, s_glane_q};
  // "more chunks" looks past the chunk that just streamed: the current chunk
  // base already counts the chunk being drained
  assign s_gap_more_chunks = (({1'b0, s_gap_chunk_q} + {1'b0, s_gap_cpos_q}) < {1'b0, s_full_k_q});
  assign s_gap_stream_last = s_pool_stream_last && !s_gap_more_chunks;
  assign s_pool_stage_done = s_pool_stage_q && s_stage_grant;
  assign s_div_quo_next = (({s_div_rem_q[31:0], s_div_num_q[31]} >= {9'd0, s_div_den_q}) ?
      {s_div_quo_q[30:0], 1'b1} : {s_div_quo_q[30:0], 1'b0});
  assign s_pool_loop_last = s_pool_stream_last && s_group_last &&
      (({9'd0, s_pidx_q} + 13'd1) >= {9'd0, s_pcnt_q});
  assign s_gap_next_num =
      ((s_pool_total_q[s_pool_c_q[2:0]+3'd1] < 32'sd0) ?
       (32'd0 - s_pool_total_q[s_pool_c_q[2:0]+3'd1]) :
       s_pool_total_q[s_pool_c_q[2:0]+3'd1]) + {8'd0, s_full_k_q[24:1]};
  assign s_gap_next_neg = (s_pool_total_q[s_pool_c_q[2:0]+3'd1] < 32'sd0);
  // GAP chunk size of the next granule (combinational: the granule launch
  // and the chunk-size register update share one SchGrpInit edge)
  assign s_gap_cpos_comb = ((s_full_k_q - {12'd0, s_gap_chunk_q}) > 25'd1024) ? 13'd1024 :
      13'(s_full_k_q - {12'd0, s_gap_chunk_q});
  // GAP divide-phase entry: SchVecDrain resets the channel counter on the
  // same edge, so the first divide operand must address channel 0 explicitly
  assign s_gap_first_num = ((s_pool_total_q[0] < 32'sd0) ? (32'd0 - s_pool_total_q[0]) :
       s_pool_total_q[0]) + {8'd0, s_full_k_q[24:1]};
  assign s_gap_first_neg = (s_pool_total_q[0] < 32'sd0);
  assign s_add_done = s_add_loop_done_q && !s_aqm_v0_q && !s_aqm_v1_q && !s_aqm_v2_q &&
      (s_resp_cnt_q >= s_fed_total_q);
  assign s_pass_last = ({9'd0, s_pbase_q} + {9'd0, s_pcnt_q}) >= {9'd0, s_tile_m_q};
  assign s_tile_last = s_pass_last && ({16'd0, s_tx_q} + {24'd0, s_tw_q} >= {16'd0, s_ow_q}) &&
      ({16'd0, s_ty_q} + {24'd0, s_th_q} >= {16'd0, s_oh_q});

  function automatic logic signed [31:0] nudge_truncate(input logic signed [63:0] product_i);
    logic signed [63:0] s_nudged;
    logic signed [63:0] s_quotient;
    begin
      if (product_i == 64'sh4000_0000_0000_0000) begin
        return 32'sh7fff_ffff;
      end
      s_nudged = product_i + ((product_i >= 64'sd0) ? 64'sd1073741824 : -64'sd1073741823);
      if (s_nudged < 64'sd0) begin
        s_quotient = -((-s_nudged) >>> 31);
      end else begin
        s_quotient = s_nudged >>> 31;
      end
      return 32'(s_quotient);
    end
  endfunction

  function automatic logic signed [31:0] rounding_divide_by_pot(input logic signed [31:0] value_i,
                                                                input logic [4:0] exponent_i);
    logic        [31:0] s_mask;
    logic        [31:0] s_remainder;
    logic        [31:0] s_threshold;
    logic signed [31:0] s_quotient;
    begin
      if (exponent_i == 5'd0) begin
        return value_i;
      end
      s_mask      = (32'd1 << exponent_i) - 32'd1;
      s_remainder = value_i & s_mask;
      s_threshold = (s_mask >> 1) + ((value_i < 32'sd0) ? 32'd1 : 32'd0);
      s_quotient  = value_i >>> exponent_i;
      return s_quotient + ((s_remainder > s_threshold) ? 32'd1 : 32'd0);
    end
  endfunction

  // parameter region window refill condition: a new 512-record window every
  // 64 groups while parameter bytes remain
  logic s_p_window_refill;
  // compute-unit operand masks and parameter read port
  assign s_mac_a_valid = 8'((9'd1 << {1'b0, s_pcnt_q}) - 9'd1);
  assign s_mac_w_valid = 8'((9'd1 << {1'b0, s_glane_q}) - 9'd1);
  assign s_glane_q = ({5'd0, s_cout_q} - {1'b0, s_group_q, 3'b000}) > 18'd8 ? 4'd8 :
      4'(s_cout_q - {s_group_q, 3'b000});
  assign s_vec_bias = s_is_dw ? s_pbias_q : '0;
  assign s_vec_aux_op = (s_op_q == `APB4_NPU__OP_MAX_POOL) ? 2'd1 : 2'd2;
  // parameter region window refill condition: the next 512-record window
  // loads exactly once when the group loop first steps past the windows
  // already streamed (pdone counts window bytes, 8192 each)
  assign s_p_window_refill = (s_pbytes_q != 32'd0) && (s_pdone_q < s_pbytes_q) &&
      ({19'd0, s_pdone_q[31:13]} <= {26'd0, s_group_q[9:6]});
  // parameter region read port: the slice of the current group within its
  // 8192-byte window (window = 64 eight-channel group slices)
  assign s_param_read_valid = (s_state_q == SchParamRd) && !s_pr_done && !s_pr_pend_q;
  assign s_param_read_addr = s_pr_add_q ?
      {8'd0, s_pr_idx_q[2:0], 2'b00} :
      ({s_group_q[5:0], 7'b000_0000} + {4'd0, s_pr_idx_q, 2'b00});

  // ---------------------------------------------------------------------
  // Loop helper expressions
  // ---------------------------------------------------------------------
  // next dense slice length and tile/pass arithmetic
  assign s_next_klen = ((s_full_k_q - s_ks0_q - {14'd0, s_klen_q}) > {14'd0, s_kslice_q}) ?
      s_kslice_q : 11'(s_full_k_q - s_ks0_q - {14'd0, s_klen_q});
  // slice-0 length of a fresh reduction: the granule launch and the slice
  // schedule registers update in the same SchGrpInit cycle, so the launch
  // arithmetic must use this combinational value, not the stale register
  assign s_first_klen = (s_full_k_q > {14'd0, s_kslice_q}) ? s_kslice_q : 11'(s_full_k_q);
  assign s_tile_cols_next = ({16'd0, s_ow_q} - {16'd0, s_tx_q} - {24'd0, s_tw_q}) >
      {24'd0, s_tw_q} ? 4'(s_tw_q[3:0]) : 4'(s_ow_q[3:0] - s_tx_q[3:0] - s_tw_q[3:0]);
  assign s_tile_rows_next = ({16'd0, s_oh_q} - {16'd0, s_ty_q} - {24'd0, s_th_q}) >
      {24'd0, s_th_q} ? 4'(s_th_q[3:0]) : 4'(s_oh_q[3:0] - s_ty_q[3:0] - s_th_q[3:0]);
  assign s_tile_m_next = (({16'd0, s_tx_q} + {24'd0, s_tw_q}) < {16'd0, s_ow_q}) ?
      7'({3'd0, s_trows_q} * {3'd0, s_tile_cols_next}) :
      7'({3'd0, s_tile_rows_next} * {3'd0, s_tw_q[3:0]});
  assign s_tile_m_comb = 7'({3'd0, s_trows_q} * {3'd0, s_tcols_q});
  assign s_pcnt_first = (s_tile_m_comb > {3'd0, s_pass_cap_q}) ? s_pass_cap_q : 4'(s_tile_m_comb);
  assign s_pcnt_next = (({3'd0, s_tile_m_q} - {3'd0, s_pbase_q} - {3'd0, s_pcnt_q}) >
      {3'd0, s_pass_cap_q}) ? s_pass_cap_q :
      4'(s_tile_m_q - s_pbase_q - s_pcnt_q);
  assign s_pcnt_tile = (s_tile_m_next > {3'd0, s_pass_cap_q}) ? s_pass_cap_q : 4'(s_tile_m_next);
  assign s_st_oy = s_ty_q + {9'd0, s_st_dy_q};
  assign s_st_ox = s_tx_q + {9'd0, s_st_dx_q};
  // the position ending an output row also stores the row's zero padding
  // (used span covers full rows except the last, which stops at OW*Cout)
  assign s_st_row_pad = (s_st_pad_q != 32'd0) &&
      ({16'd0, s_st_ox} == ({16'd0, s_ow_q} - 32'd1)) &&
      ({16'd0, s_st_oy} < ({16'd0, s_oh_q} - 32'd1));

  // pool/GAP divide operands: AVERAGE_POOL divides the channel's aux sum by
  // its valid-tap count; GAP divides the running total by H*W.
  assign s_pool_div_num = s_is_gap ?
      ((s_pool_total_q[s_pool_c_q[2:0]] < 32'sd0) ?
       (32'd0 - s_pool_total_q[s_pool_c_q[2:0]]) : s_pool_total_q[s_pool_c_q[2:0]]) +
      {8'd0, s_full_k_q[24:1]} :
      ((s_vec_aux_result < 32'sd0) ? (32'd0 - s_vec_aux_result) : s_vec_aux_result) +
      {19'd0, s_pool_vcnt_q[12:1]};
  assign s_pool_div_den = s_is_gap ? s_full_k_q : {12'd0, s_pool_vcnt_q};
  assign s_pool_div_neg = s_is_gap ? (s_pool_total_q[s_pool_c_q[2:0]] < 32'sd0) :
      (s_vec_aux_result < 32'sd0);
  assign s_pool_total_next = s_pool_total_q[s_pool_c_q[2:0]] + s_vec_aux_result;
  assign s_pool_total_ovf = (({s_pool_total_sel[31], s_pool_total_sel} +
      {s_vec_aux_result[31], s_vec_aux_result}) != {s_pool_total_next[31], s_pool_total_next});
  assign s_pool_total_sel = s_pool_total_q[s_pool_c_q[2:0]];

  // ADD inline-QM elastic stage enables and totals
  assign s_aqm_s2_free = !s_aqm_v2_q || s_aqm_consume;
  assign s_aqm_s1_free = !s_aqm_v1_q || s_aqm_s2_free;
  assign s_aqm_load0 = s_rb_pend_q && (s_state_q == SchAddFeed) && (!s_aqm_v0_q || s_aqm_s1_free);
  assign s_add_total_ovf =
      (({s_add_t0_q[31], s_add_t0_q} + {s_aqm_d2_q[31], s_aqm_d2_q}) !=
       {s_add_total[31], s_add_total});

  // ADD feed iterator: outputs are (position, channel) pairs, two items each
  assign s_add_more = !s_add_loop_done_q && (s_state_q == SchAddFeed) &&
      (!s_aqm_v0_q || s_aqm_s1_free);
  assign s_add_byte_off = {s_add_p_q, 3'b000} + {9'd0, s_add_c_q};

  // parameter-encoding checks at capture time
  assign s_pr_shift_bad = $signed(
      s_param_read_data
  ) > 32'sd30 || $signed(
      s_param_read_data
  ) < -32'sd31;
  assign s_pr_fault = s_pr_add_q ?
      (((s_pr_idx_q[2:0] == 3'd0) && (s_param_read_data != 32'd20)) ||
       ((s_pr_idx_q[2:0] == 3'd7) && (s_param_read_data != 32'd0)) ||
       (((s_pr_idx_q[2:0] == 3'd1) || (s_pr_idx_q[2:0] == 3'd3) ||
         (s_pr_idx_q[2:0] == 3'd5)) && s_param_read_data[31]) ||
       (((s_pr_idx_q[2:0] == 3'd2) || (s_pr_idx_q[2:0] == 3'd4) ||
         (s_pr_idx_q[2:0] == 3'd6)) && s_pr_shift_bad)) :
      (((s_pr_idx_q[1:0] == 2'd3) && (s_param_read_data != 32'd0)) ||
       ((s_pr_idx_q[1:0] == 2'd1) && s_param_read_data[31]) ||
       ((s_pr_idx_q[1:0] == 2'd2) && s_pr_shift_bad));

  // ---------------------------------------------------------------------
  // Main state machine
  // ---------------------------------------------------------------------
  always_comb begin
    s_state_d = s_state_q;
    unique case (s_state_q)
      SchIdle: begin
        if (rec_valid_i && rec_ready_o) begin
          // Up to 16 KiB is resident for the descriptor. Larger tensors are
          // fetched a group/K-slice at a time after packing the matching A.
          s_state_d = ((rec_weight_bytes_i != 32'd0) &&
                       (rec_weight_bytes_i <= 32'd16384)) ? SchWCmd :
              (rec_param_bytes_i != 32'd0) ? SchPCmd : SchDescInit;
        end
      end
      SchWCmd: begin
        if (s_read_accept) begin
          s_state_d = SchWStream;
        end
      end
      SchWStream: begin
        if (s_stream_accept && read_last_i) begin
          if (s_w_stream_q) begin
            s_state_d = SchParamRd;
          end else if ((s_woff_q + {18'd0, s_wchunk_q}) >= s_wbytes_q) begin
            s_state_d = (s_pbytes_q != 32'd0) ? SchPCmd : SchDescInit;
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
          if (s_prem_q <= 32'd128) begin
            s_state_d = s_prefill_q ? SchGrpInit : SchDescInit;
          end else begin
            s_state_d = SchPCmd;
          end
        end
      end
      SchDescInit: begin
        // ADD's 32-byte parameter record is read once before execution; the
        // pass-capacity division then completes the loop constants.
        if (s_is_add && !s_add_params_done_q) begin
          s_state_d = SchParamRd;
        end else if (!s_div_busy_q) begin
          s_state_d = SchGrpInit;
        end
      end
      SchGrpInit: begin
        // Per channel group: refill the parameter region window every 64
        // groups (512 records per window); dense reuses a packed whole
        // reduction when it fits one A half.
        if (s_p_window_refill) begin
          s_state_d = SchPCmd;
        end else if (s_is_dense && s_a_reuse && s_a_ready_q) begin
          s_state_d = s_w_stream_q ? SchWCmd : SchParamRd;
        end else begin
          s_state_d = SchGathSeg;
        end
      end
      SchParamRd: begin
        if (s_pr_done) begin
          if (s_pr_add_q) begin
            s_state_d = SchDescInit;
          end else if (s_is_dw) begin
            s_state_d = SchVecStart;
          end else begin
            s_state_d = SchAccStart;
          end
        end
      end
      SchAccStart: begin
        // a context is acquired only for the first K-slice of a reduction;
        // continuation slices stream into the held context (bias once)
        if ((s_ks0_q != 25'd0) || s_acc_start_ready) begin
          s_state_d = SchMacStream;
        end
      end
      SchGathSeg:    s_state_d = SchGathAddr;
      // Iterator math is registered in SchGathSeg; the address/range decision
      // completes one cycle later from those registers.
      SchGathAddr: begin
        if (s_seg_pad) begin
          s_state_d = SchGathPad;
        end else begin
          s_state_d = SchGathCmd;
        end
      end
      SchGathCmd: begin
        if (s_read_accept) begin
          s_state_d = SchGathStream;
        end
      end
      SchGathStream: begin
        if (s_seg_stream_done) begin
          if (s_granule_done) begin
            s_state_d = (s_is_dense || s_is_dw) ? SchPackStart : SchGathExit;
          end else begin
            s_state_d = SchGathSeg;
          end
        end
      end
      SchGathPad: begin
        if (s_seg_left_q == 13'd0) begin
          if (s_granule_done) begin
            s_state_d = (s_is_dense || s_is_dw) ? SchPackStart : SchGathExit;
          end else begin
            s_state_d = SchGathSeg;
          end
        end
      end
      SchGathExit: begin
        // Granule resident in a raw half: pool/GAP stream it through the
        // vector aux, CLAMP through the clamp path; ADD gathers input1 next.
        if (s_is_add && !s_add_in1_q) begin
          s_state_d = SchGathSeg;
        end else if (s_is_add) begin
          s_state_d = SchAddFeed;
        end else if (s_is_clamp) begin
          s_state_d = SchClamp;
        end else begin
          s_state_d = SchVecStart;
        end
      end
      SchPackStart: begin
        if (s_pack_start && s_pack_ready) begin
          s_state_d = SchPackWait;
        end
      end
      SchPackWait: begin
        if (s_pack_done) begin
          if (s_is_dw) begin
            s_state_d = s_w_stream_q ? SchWCmd : SchParamRd;
          end else if (s_a_reuse && !s_a_ready_q && !s_slice_last) begin
            s_state_d = SchGathSeg;
          end else begin
            s_state_d = s_w_stream_q ? SchWCmd : SchParamRd;
          end
        end
      end
      SchMacStream: begin
        if (s_mac_done_q >= s_stream_len_q && !s_mac_pend_q && !s_mac_resp_valid &&
            (s_acc_if_q == 2'b00)) begin
          if (!s_a_reuse && !s_slice_last) begin
            s_state_d = SchGathSeg;
          end else begin
            s_state_d = SchAccDrain;
          end
        end
      end
      SchAccDrain: begin
        if (s_drain_done) begin
          if (s_group_last) begin
            s_state_d = SchStoreInit;
          end else begin
            s_state_d = SchGrpInit;
          end
        end
      end
      SchVecStart: begin
        if (s_vec_start_ready) begin
          if (s_is_dw) begin
            s_state_d = SchVecStream;
          end else begin
            s_state_d = SchPoolStream;
          end
        end
      end
      SchVecStream: begin
        if ((s_vec_k_q >= 4'd9) && !s_mac_pend_q) begin
          s_state_d = SchVecDrain;
        end
      end
      SchVecDrain: begin
        if (s_vec_drain_done) begin
          if (s_is_dw) begin
            if ({9'd0, s_pidx_q} + 13'd1 < {9'd0, s_pcnt_q}) begin
              s_state_d = SchVecStart;
            end else if (s_group_last) begin
              s_state_d = SchStoreInit;
            end else begin
              s_state_d = SchGrpInit;
            end
          end else if (s_is_gap) begin
            if (!s_pool_stream_last) begin
              s_state_d = SchVecStart;
            end else if (s_gap_more_chunks) begin
              s_state_d = SchGrpInit;
            end else begin
              s_state_d = SchPoolDiv;
            end
          end else begin
            if (!s_pool_stream_last) begin
              s_state_d = SchVecStart;
            end else if (s_pool_loop_last) begin
              s_state_d = SchStoreInit;
            end else begin
              s_state_d = SchGrpInit;
            end
          end
        end
      end
      SchPoolStream: begin
        if (!s_pool_more) begin
          // GAP releases the vector context after every chunk and divides
          // only once the whole H*W reduction is resident in the per-channel
          // totals; local pools divide/stage per channel immediately
          s_state_d = s_is_gap ? SchVecDrain : SchPoolDiv;
        end
      end
      SchPoolDiv: begin
        if (s_pool_stage_done) begin
          if (s_is_gap) begin
            if (s_pool_stream_last) begin
              if (s_group_last) begin
                s_state_d = SchStoreInit;
              end else begin
                s_state_d = SchGrpInit;
              end
            end else begin
              s_state_d = SchPoolDiv;
            end
          end else begin
            s_state_d = SchVecDrain;
          end
        end
      end
      SchClamp: begin
        if (!s_clamp_more) begin
          if (s_group_last) begin
            s_state_d = SchStoreInit;
          end else begin
            s_state_d = SchGrpInit;
          end
        end
      end
      SchAddFeed: begin
        if (s_add_done) begin
          if (s_group_last) begin
            s_state_d = SchStoreInit;
          end else begin
            s_state_d = SchGrpInit;
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
          if ((s_st_rem_q - {12'd0, s_st_cmd_bytes_q}) == 25'd0) begin
            if ({9'd0, s_pidx_q} + 13'd1 < {9'd0, s_pcnt_q}) begin
              // next position of the current pass
              s_state_d = SchStoreInit;
            end else if (s_pass_last && s_tile_last) begin
              s_state_d = SchRetire;
            end else begin
              // next pass of the same tile, or the next tile's first pass
              s_state_d = SchGrpInit;
            end
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

    // DMA fault / LOCAL_STATE / ARITHMETIC / DESCRIPTOR / UNSUPPORTED /
    // watchdog escape in the spec's same-cycle priority order.
    if (!s_fault_seen_q && (s_state_q != SchStopIdle) &&
        (s_state_q != SchDrainWait) && (s_state_q != SchFaultWait) &&
        (dma_fault_i || s_sram_err || s_arith_fault || s_desc_fault || s_unsup_fault ||
         s_wdog_fire)) begin
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
      s_state_q           <= SchIdle;
      s_op_q              <= '0;
      s_h_q               <= '0;
      s_w_q               <= '0;
      s_cin_q             <= '0;
      s_cout_q            <= '0;
      s_oh_q              <= '0;
      s_ow_q              <= '0;
      s_in0_base_q        <= '0;
      s_out_base_q        <= '0;
      s_w_base_q          <= '0;
      s_p_base_q          <= '0;
      s_irow_q            <= '0;
      s_orow_q            <= '0;
      s_kh_q              <= '0;
      s_kw_q              <= '0;
      s_sh_q              <= '0;
      s_sw_q              <= '0;
      s_pad_t_q           <= '0;
      s_pad_l_q           <= '0;
      s_zp_q              <= '0;
      s_th_q              <= '0;
      s_tw_q              <= '0;
      s_in1_base_q        <= '0;
      s_in1_row_q         <= '0;
      s_z1_q              <= '0;
      s_zout_q            <= '0;
      s_act_min_q         <= '0;
      s_act_max_q         <= '0;
      s_wbytes_q          <= '0;
      s_pbytes_q          <= '0;
      s_desc_idx_q        <= '0;
      s_kp_count_q        <= '0;
      s_gather_len_q      <= '0;
      s_full_k_q          <= '0;
      s_groups_q          <= '0;
      s_kslice_q          <= '0;
      s_pass_cap_q        <= '0;
      s_ty_q              <= '0;
      s_tx_q              <= '0;
      s_trows_q           <= '0;
      s_tcols_q           <= '0;
      s_tile_m_q          <= '0;
      s_dy_q              <= '0;
      s_dx_q              <= '0;
      s_pbase_q           <= '0;
      s_pcnt_q            <= '0;
      s_pidx_q            <= '0;
      s_group_q           <= '0;
      s_ks0_q             <= '0;
      s_klen_q            <= '0;
      s_stream_len_q      <= '0;
      s_a_ready_q         <= 1'b0;
      s_ahalf_q           <= 1'b0;
      s_ghalf_q           <= 1'b0;
      s_wrow_q            <= '0;
      s_oy_q              <= '0;
      s_ox_q              <= '0;
      s_g_q               <= '0;
      s_kloc_q            <= '0;
      s_ci_q              <= '0;
      s_kpos_h_q          <= '0;
      s_kpos_w_q          <= '0;
      s_sn_ci_q           <= '0;
      s_sn_kh_q           <= '0;
      s_sn_kw_q           <= '0;
      s_gdy_q             <= '0;
      s_gdx_q             <= '0;
      s_gcbase_q          <= '0;
      s_gpos_bytes_q      <= '0;
      s_granule_q         <= '0;
      s_gbase_q           <= '0;
      s_grow_q            <= '0;
      s_seg_addr_q        <= '0;
      s_iy_q              <= '0;
      s_ix_q              <= '0;
      s_in_range_q        <= 1'b0;
      s_seg_left_q        <= '0;
      s_pad_head_q        <= '0;
      s_q_cnt_q           <= 5'd0;
      s_q_base_q          <= '0;
      s_woff_q            <= '0;
      s_wchunk_q          <= '0;
      s_wfill_off_q       <= '0;
      s_whalf_q           <= 1'b0;
      s_w_stream_q        <= 1'b0;
      s_pdone_q           <= '0;
      s_prem_q            <= '0;
      s_pchunk_q          <= '0;
      s_poff_q            <= '0;
      s_phalf_q           <= 1'b0;
      s_pend_data_q       <= '0;
      s_pend_keep_q       <= '0;
      s_pend_last_q       <= 1'b0;
      s_pack_base_q       <= '0;
      s_pr_count_q        <= '0;
      s_pr_idx_q          <= '0;
      s_pr_add_q          <= 1'b0;
      s_pr_pend_q         <= 1'b0;
      s_mac_k_q           <= '0;
      s_mac_done_q        <= '0;
      s_mac_pend_q        <= 1'b0;
      s_ctx_q             <= 1'b0;
      s_drain_idx_q       <= '0;
      s_resp_p_q          <= '0;
      s_resp_c_q          <= '0;
      s_resp_off_q        <= '0;
      s_resp_cnt_q        <= '0;
      s_fed_total_q       <= '0;
      s_acc_if_q          <= 2'b00;
      s_acc_drain_pulse_q <= 1'b0;
      s_vec_drain_pulse_q <= 1'b0;
      s_vec_k_q           <= '0;
      s_rb_pend_q         <= 1'b0;
      s_rb_half_q         <= 1'b0;
      s_pool_k_q          <= '0;
      s_pool_c_q          <= '0;
      s_pool_kmax_q       <= '0;
      s_pool_vcnt_q       <= '0;
      s_rb_kh_q           <= '0;
      s_rb_kw_q           <= '0;
      s_pool_neg_q        <= 1'b0;
      s_pool_stage_q      <= 1'b0;
      s_gap_chunk_q       <= '0;
      s_gap_cpos_q        <= '0;
      s_add_m_q           <= '{default: '0};
      s_add_s_q           <= '{default: '0};
      s_add_in1_q         <= 1'b0;
      s_add_params_done_q <= 1'b0;
      s_add_loop_done_q   <= 1'b0;
      s_add_p_q           <= '0;
      s_add_c_q           <= '0;
      s_add_in_q          <= 1'b0;
      s_add_t0_q          <= '0;
      s_aqm_v0_q          <= 1'b0;
      s_aqm_d0_q          <= '0;
      s_aqm_f0_q          <= 1'b0;
      s_aqm_m0_q          <= '0;
      s_aqm_s0_q          <= '0;
      s_aqm_t0_q          <= '0;
      s_aqm_v1_q          <= 1'b0;
      s_aqm_p1_q          <= '0;
      s_aqm_f1_q          <= 1'b0;
      s_aqm_s1_q          <= '0;
      s_aqm_t1_q          <= '0;
      s_aqm_v2_q          <= 1'b0;
      s_aqm_d2_q          <= '0;
      s_aqm_f2_q          <= 1'b0;
      s_aqm_t2_q          <= '0;
      s_clamp_off_q       <= '0;
      s_clamp_stg_q       <= '0;
      s_clamp_c_q         <= '0;
      s_clamp_len_q       <= '0;
      s_div_num_q         <= '0;
      s_div_den_q         <= '0;
      s_div_rem_q         <= '0;
      s_div_quo_q         <= '0;
      s_div_cnt_q         <= '0;
      s_div_busy_q        <= 1'b0;
      s_div_issued_q      <= 1'b0;
      s_rq_out_q          <= '0;
      s_st_pos_addr_q     <= '0;
      s_st_cur_q          <= '0;
      s_st_rem_q          <= '0;
      s_st_cmd_bytes_q    <= '0;
      s_st_beats_q        <= '0;
      s_st_beat_idx_q     <= '0;
      s_st_phase_q        <= '0;
      s_st_dy_q           <= '0;
      s_st_dx_q           <= '0;
      s_st_w0_q           <= '0;
      s_st_w1_q           <= '0;
      s_st_w2_q           <= '0;
      s_st_soff_q         <= '0;
      s_slot_q            <= '0;
      s_timeout_q         <= '0;
      s_wdog_q            <= '0;
      s_cnt_active_q      <= '0;
      s_cnt_pause_q       <= '0;
      s_cnt_pack_q        <= '0;
      s_cnt_retired_q     <= '0;
      s_cnt_macs_q        <= '0;
      s_cnt_bank_q        <= '0;
      s_cnt_rqstall_q     <= '0;
      s_completed_q       <= '0;
      s_term_q            <= '0;
      s_fault_seen_q      <= 1'b0;
      s_fault_code_q      <= '0;
      s_fault_addr_q      <= '0;
      s_fault_info_q      <= '0;
      s_arith_fault       <= 1'b0;
      s_arith_lane        <= '0;
      for (int unsigned slot = 0; slot < 16; slot++) begin
        s_q_bytes_q[slot] <= '0;
      end
      for (int unsigned lane = 0; lane < 8; lane++) begin
        s_pbias_q[lane]      <= '0;
        s_pmult_q[lane]      <= '0;
        s_pshift_q[lane]     <= '0;
        s_pool_total_q[lane] <= '0;
      end
    end else begin
      // The terminal bank latches even through a same-cycle recovery commit.
      if (terminal_i) begin
        s_term_q <= s_live_counters;
      end
      if (clear_i) begin
        s_state_q      <= SchIdle;
        s_q_cnt_q      <= 5'd0;
        s_mac_pend_q   <= 1'b0;
        s_rb_pend_q    <= 1'b0;
        s_st_phase_q   <= '0;
        s_wdog_q       <= '0;
        s_fault_seen_q <= 1'b0;
        s_arith_fault  <= 1'b0;
        s_desc_fault   <= 1'b0;
        s_unsup_fault  <= 1'b0;
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
          s_op_q <= rec_opcode_i;
          s_h_q <= rec_h_i;
          s_w_q <= rec_w_i;
          s_cin_q <= rec_cin_i;
          s_cout_q <= rec_cout_i;
          s_oh_q <= rec_oh_i;
          s_ow_q <= rec_ow_i;
          s_in0_base_q <= rec_input0_base_i;
          s_out_base_q <= rec_output_base_i;
          s_w_base_q <= rec_weight_base_i;
          s_p_base_q <= rec_param_base_i;
          s_irow_q <= rec_input0_row_bytes_i;
          s_orow_q <= rec_output_row_bytes_i;
          s_st_pad_q <= rec_output_row_bytes_i - ({19'd0, rec_ow_i} * {19'd0, rec_cout_i});
          s_kh_q <= rec_kh_i;
          s_kw_q <= rec_kw_i;
          s_sh_q <= rec_sh_i;
          s_sw_q <= rec_sw_i;
          s_pad_t_q <= rec_pad_top_i;
          s_pad_l_q <= rec_pad_left_i;
          s_zp_q <= rec_input0_zero_i;
          s_th_q <= rec_tile_h_i;
          s_tw_q <= rec_tile_w_i;
          s_in1_base_q <= rec_input1_base_i;
          s_in1_row_q <= rec_input1_row_bytes_i;
          s_z1_q <= rec_input1_zero_i;
          s_zout_q <= rec_output_zero_i;
          s_act_min_q <= rec_act_min_i;
          s_act_max_q <= rec_act_max_i;
          s_wbytes_q <= rec_weight_bytes_i;
          s_w_stream_q <= rec_weight_bytes_i > 32'd16384;
          s_pbytes_q <= rec_param_bytes_i;
          s_desc_idx_q <= rec_desc_index_i;
          s_kp_count_q <= s_rec_kp_count;
          s_kslice_q <= 11'(rec_k_slice_i[10:0]);
          // per-descriptor loop registers
          s_full_k_q <= 25'(s_rec_kp_count);
          s_groups_q <= 10'(({3'd0, rec_cout_i} + 16'd7) >> 3);
          s_ty_q <= '0;
          s_tx_q <= '0;
          s_trows_q <= (rec_tile_h_i < rec_oh_i[7:0]) ? 4'(rec_tile_h_i[3:0]) : 4'(rec_oh_i[3:0]);
          s_tcols_q <= (rec_tile_w_i < rec_ow_i[7:0]) ? 4'(rec_tile_w_i[3:0]) : 4'(rec_ow_i[3:0]);
          s_dy_q <= '0;
          s_dx_q <= '0;
          // shared loop state from the previous descriptor must restart:
          // the position store/compute index, the pool position trackers,
          // the packed-A row base, the dense slice schedule and the pool
          // channel counter are otherwise stale mid-loop values
          s_pidx_q <= '0;
          s_gdy_q <= '0;
          s_gdx_q <= '0;
          s_pack_base_q <= '0;
          s_ks0_q <= '0;
          s_klen_q <= '0;
          s_sn_ci_q <= '0;
          s_sn_kh_q <= '0;
          s_sn_kw_q <= '0;
          s_pool_c_q <= '0;
          s_pbase_q <= '0;
          s_group_q <= '0;
          s_wrow_q <= '0;
          s_a_ready_q <= 1'b0;
          s_ahalf_q <= 1'b0;
          s_ghalf_q <= 1'b0;
          s_add_in1_q <= 1'b0;
          s_add_params_done_q <= 1'b0;
          s_gap_chunk_q <= '0;
          s_woff_q <= '0;
          s_wchunk_q <= (rec_weight_bytes_i > 32'd8192) ? 14'd8192 : rec_weight_bytes_i[13:0];
          s_wfill_off_q <= '0;
          s_whalf_q <= 1'b0;
          s_pdone_q <= '0;
          s_poff_q <= '0;
          s_phalf_q <= 1'b0;
          s_pend_last_q <= 1'b0;
          // parameter region window 0: the region holds 512 16-byte records;
          // later windows refill as the group loop reaches them
          s_prem_q <= (rec_param_bytes_i > 32'd8192) ? 32'd8192 : rec_param_bytes_i;
          s_pchunk_q <= (rec_param_bytes_i > 32'd128) ? 8'd128 : rec_param_bytes_i[7:0];
          s_prefill_q <= 1'b0;
          s_arith_fault <= 1'b0;
        end

        // weights fill bookkeeping
        // Large weight tensors use the same DMA/fill states as descriptor
        // prefill, but each visit maps just the current group/K-slice to W
        // half zero. K_SLICE<=1024 bounds every dense refill to 8192 bytes.
        if (s_w_stream_q && (s_state_d == SchWCmd) &&
            ((s_state_q == SchGrpInit) || (s_state_q == SchPackWait))) begin
          if (s_is_dw) begin
            s_woff_q   <= 32'(s_wrow_q << 3);
            s_wchunk_q <= 14'd72;
          end else if (s_a_reuse) begin
            s_woff_q   <= 32'(s_wrow_q << 3);
            s_wchunk_q <= 14'(s_full_k_q << 3);
          end else begin
            s_woff_q   <= 32'((s_wrow_q + {9'd0, s_ks0_q}) << 3);
            s_wchunk_q <= 14'({3'd0, s_klen_q} << 3);
          end
          s_wfill_off_q <= '0;
          s_whalf_q     <= 1'b0;
        end
        if ((s_state_q == SchWCmd) && s_read_accept) begin
          s_wfill_off_q <= '0;
        end
        if ((s_state_q == SchWStream) && s_stream_accept) begin
          s_wfill_off_q <= s_wfill_off_q + 13'd8;
          if (read_last_i) begin
            if (!s_w_stream_q) begin
              s_woff_q  <= s_woff_q + {18'd0, s_wchunk_q};
              s_whalf_q <= ~s_whalf_q;
              if ((s_wbytes_q - (s_woff_q + {18'd0, s_wchunk_q})) > 32'd8192) begin
                s_wchunk_q <= 14'd8192;
              end else begin
                s_wchunk_q <= 14'(s_wbytes_q - (s_woff_q + {18'd0, s_wchunk_q}));
              end
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

        // per-record reduction geometry, one multiply level after the accept
        // edge (idempotent while the record stays active)
        if (s_state_q == SchDescInit) begin
          s_gather_len_q <= 33'(s_kp_cin);
          if (s_is_dense) begin
            s_full_k_q <= 25'(s_kp_cin);
          end else begin
            s_full_k_q <= 25'(s_kp_count_q);
          end
        end

        // -----------------------------------------------------------------
        // Descriptor init: pass capacity and the ADD parameter record
        // -----------------------------------------------------------------
        if ((s_state_q != SchDescInit) && (s_state_d == SchDescInit) && !s_is_gap) begin
          s_div_num_q  <= 32'd8192;
          s_div_den_q  <= {11'd0, s_slot_comb};
          s_div_rem_q  <= '0;
          s_div_quo_q  <= '0;
          s_div_cnt_q  <= 6'd32;
          s_div_busy_q <= 1'b1;
        end
        // divider iteration
        if (s_div_busy_q) begin
          if ({s_div_rem_q[31:0], s_div_num_q[31]} >= {9'd0, s_div_den_q}) begin
            s_div_rem_q <= ({s_div_rem_q[31:0], s_div_num_q[31]} - {9'd0, s_div_den_q});
            s_div_quo_q <= {s_div_quo_q[30:0], 1'b1};
          end else begin
            s_div_rem_q <= {s_div_rem_q[31:0], s_div_num_q[31]};
            s_div_quo_q <= {s_div_quo_q[30:0], 1'b0};
          end
          s_div_num_q <= {s_div_num_q[30:0], 1'b0};
          if (s_div_cnt_q == 6'd1) begin
            s_div_busy_q <= 1'b0;
          end
          s_div_cnt_q <= s_div_cnt_q - 6'd1;
        end

        // pass capacity latches the cycle the divider completes, one cycle
        // before the loop constants below evaluate it
        if ((s_state_q == SchDescInit) && s_div_busy_q && (s_div_cnt_q == 6'd1)) begin
          s_pass_cap_q <= (s_div_quo_next > 32'd8) ? 4'd8 : 4'(s_div_quo_next);
          s_slot_q     <= s_slot_comb;
        end

        // dense per-group slice schedule: every group restarts the reduction
        // from slice 0 with a fresh snapshot (skipped on an A-reuse hit)
        if ((s_state_q == SchGrpInit) && s_is_dense && !(s_a_reuse && s_a_ready_q)) begin
          s_ks0_q       <= '0;
          s_klen_q      <= s_first_klen;
          s_sn_ci_q     <= '0;
          s_sn_kh_q     <= '0;
          s_sn_kw_q     <= '0;
          s_ahalf_q     <= 1'b0;
          s_pack_base_q <= '0;
        end

        // parameter region window refill setup before a new window's groups
        if ((s_state_q == SchGrpInit) && (s_state_d == SchPCmd) && s_p_window_refill) begin
          s_prefill_q <= 1'b1;
          s_prem_q <= ((s_pbytes_q - s_pdone_q) > 32'd8192) ? 32'd8192 : (s_pbytes_q - s_pdone_q);
          s_pchunk_q <= ((s_pbytes_q - s_pdone_q) > 32'd128) ? 8'd128 : 8'(s_pbytes_q - s_pdone_q);
        end
        if ((s_state_q == SchPStream) && s_phalf_q && s_pend_last_q && (s_prem_q <= 32'd128)) begin
          s_prefill_q <= 1'b0;
        end

        // group setup: channel-group lanes, base registers, granule launch.
        // Pool granules track one position whose coordinates advance per
        // position; the other ops reload the pass base at every granule.
        if ((s_state_q == SchGrpInit) && (s_state_d == SchGathSeg)) begin
          if (!s_is_pool && !s_is_gap) begin
            s_gdy_q <= s_dy_q;
            s_gdx_q <= s_dx_q;
          end
          // oy/ox of the granule's first position: the pass base for
          // granule-iterating ops, the tracked position for pool
          if (s_is_pool) begin
            s_oy_q <= s_ty_q + {9'd0, s_gdy_q};
            s_ox_q <= s_tx_q + {9'd0, s_gdx_q};
          end else begin
            s_oy_q <= s_ty_q + {9'd0, s_dy_q};
            s_ox_q <= s_tx_q + {9'd0, s_dx_q};
          end
          s_g_q    <= '0;
          s_kloc_q <= '0;
          s_ci_q   <= '0;
          // GAP's raster position continues across the chunks of a group;
          // it restarts only at a new group's first chunk (chunk base zero)
          if (!s_is_gap || (s_gap_chunk_q == 25'd0)) begin
            s_kpos_h_q <= '0;
            s_kpos_w_q <= '0;
          end
          s_gbase_q  <= s_is_add && s_add_in1_q ? s_in1_base_q : s_in0_base_q;
          s_grow_q   <= s_is_add && s_add_in1_q ? s_in1_row_q : s_irow_q;
          s_gcbase_q <= s_is_grouped ? {3'd0, s_group_q, 3'b000} : 13'd0;
          s_ghalf_q  <= s_is_add ? s_add_in1_q : ~s_ghalf_q;
          if (s_is_dense) begin
            // every SchGrpInit granule is slice 0 of a fresh reduction: the
            // slice-start snapshot registers are reset on this same edge, so
            // the launch must use the fresh (zero) reduction coords, never
            // the stale end-of-previous-granule chain
            s_gpos_bytes_q <= {2'd0, s_first_klen};
            s_granule_q    <= 25'({21'd0, s_pcnt_q} * {14'd0, s_first_klen});
            s_ci_q         <= '0;
            s_kpos_h_q     <= '0;
            s_kpos_w_q     <= '0;
          end else if (s_is_dw) begin
            s_gpos_bytes_q <= 13'd72;
            s_granule_q    <= 25'({21'd0, s_pcnt_q} * 25'd72);
          end else if (s_is_gap) begin
            s_gpos_bytes_q <= 13'd8;
            // the chunk size register updates on this same edge, so the
            // granule launch must use the combinational chunk size
            s_granule_q    <= {12'd0, s_gap_cpos_comb, 3'b000};
          end else if (s_is_pool) begin
            s_gpos_bytes_q <= {s_full_k_q[9:0], 3'b000};
            s_granule_q    <= {s_full_k_q[9:0], 3'b000};
          end else begin
            // ADD / CLAMP
            s_gpos_bytes_q <= 13'd8;
            s_granule_q    <= {21'd0, s_pcnt_q, 3'b000};
          end
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
          s_q_base_q   <= s_g_q[12:0];
          s_q_cnt_q    <= 5'd0;
        end
        if ((s_state_q == SchGathAddr) && (s_state_d == SchGathPad)) begin
          s_seg_left_q <= s_seg_run;
          s_pad_head_q <= s_g_q[12:0];
        end

        // gather byte queue: pop one word per cycle, append on accepted beats
        if ((s_state_q == SchGathStream) && (s_pop_n != 3'd0)) begin
          for (int unsigned idx = 0; idx < 16; idx++) begin
            if ((idx + 32'(s_pop_n)) < 16) begin
              s_q_bytes_q[idx] <= s_q_bytes_q[idx+32'(s_pop_n)];
            end
          end
          s_q_base_q <= s_q_base_q + {10'd0, s_pop_n};
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
          s_pad_head_q <= s_pad_head_q + {10'd0, s_pad_n};
          s_seg_left_q <= s_seg_left_q - {10'd0, s_pad_n};
        end

        // iterator advance at a completed gather segment
        if (s_iter_advance) begin
          s_g_q    <= s_g_q + {17'd0, s_seg_run};
          s_kloc_q <= s_pos_done ? 13'd0 : (s_kloc_q + s_seg_run);
          if (s_pos_done) begin
            // position window complete: restore the slice-start reduction
            // coords and advance the gather position
            if (s_is_dense) begin
              s_ci_q     <= s_sn_ci_q;
              s_kpos_h_q <= s_sn_kh_q;
              s_kpos_w_q <= s_sn_kw_q;
            end else begin
              // the channel cursor restarts at lane 0 of the next position
              // (GAP keeps its raster kpos, everything else restarts it too)
              s_ci_q <= '0;
              if (!s_is_gap) begin
                s_kpos_h_q <= '0;
                s_kpos_w_q <= '0;
              end
            end
            if (s_is_gap) begin
              // whole-input raster position advance
              if (({1'b0, s_kpos_w_q} + 14'd1) == {1'b0, s_kw_lim}) begin
                s_kpos_w_q <= '0;
                s_kpos_h_q <= s_kpos_h_q + 13'd1;
              end else begin
                s_kpos_w_q <= s_kpos_w_q + 13'd1;
              end
            end else if (!s_is_pool) begin
              // pool granules hold a single position: the readback streams it
              // with these coordinates still latched, so the position advance
              // belongs to the pool release in SchVecDrain, not here
              if (({1'b0, s_gdx_q} + 5'd1) == {1'b0, s_tcols_q}) begin
                s_gdx_q <= '0;
                s_gdy_q <= s_gdy_q + 4'd1;
                s_ox_q  <= s_tx_q;
                s_oy_q  <= s_ty_q + {9'd0, s_gdy_q} + 13'd1;
              end else begin
                s_gdx_q <= s_gdx_q + 4'd1;
                s_ox_q  <= s_ox_q + 13'd1;
              end
            end
            // slice reduction position snapshot (dense slice chaining)
            if (s_is_dense && s_granule_done) begin
              if (s_iter_wrap) begin
                s_sn_ci_q <= '0;
                if (({1'b0, s_kpos_w_q} + 14'd1) == {1'b0, s_kw_lim}) begin
                  s_sn_kh_q <= s_kpos_h_q + 13'd1;
                  s_sn_kw_q <= '0;
                end else begin
                  s_sn_kh_q <= s_kpos_h_q;
                  s_sn_kw_q <= s_kpos_w_q + 13'd1;
                end
              end else begin
                s_sn_ci_q <= s_ci_q + s_seg_run;
                s_sn_kh_q <= s_kpos_h_q;
                s_sn_kw_q <= s_kpos_w_q;
              end
            end
          end else if (s_iter_wrap) begin
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

        // dense slice chaining: slice advance happens after a reuse
        // pre-gather pack (more slices to pack) or a non-reuse stream
        if ((s_state_q == SchPackWait) && s_pack_done && s_is_dense && s_a_reuse &&
            !s_a_ready_q) begin
          if (!s_slice_last) begin
            s_ks0_q        <= s_ks0_q + {14'd0, s_klen_q};
            s_klen_q       <= s_next_klen;
            // the next slice packs after the rows already in the A half
            s_pack_base_q  <= s_pack_base_q + {3'd0, s_klen_q, 3'b000};
            s_gdy_q        <= s_dy_q;
            s_gdx_q        <= s_dx_q;
            s_oy_q         <= s_ty_q + {9'd0, s_dy_q};
            s_ox_q         <= s_tx_q + {9'd0, s_dx_q};
            s_g_q          <= '0;
            s_kloc_q       <= '0;
            s_ci_q         <= s_sn_ci_q;
            s_kpos_h_q     <= s_sn_kh_q;
            s_kpos_w_q     <= s_sn_kw_q;
            s_gpos_bytes_q <= {2'd0, s_next_klen};
            s_granule_q    <= 25'({21'd0, s_pcnt_q} * {14'd0, s_next_klen});
            s_gbase_q      <= s_in0_base_q;
            s_grow_q       <= s_irow_q;
            s_ghalf_q      <= ~s_ghalf_q;
          end else begin
            s_a_ready_q <= 1'b1;
            // the whole reduction now starts at A row 0 / W row s_wrow_q:
            // rebase the slice cursor so the single full-length MAC stream
            // addresses rows mac_k = 0..full_k-1
            s_ks0_q     <= '0;
          end
        end
        if ((s_state_q == SchMacStream) && (s_state_d == SchGathSeg) && s_is_dense) begin
          // non-reuse slice advance: snapshot already chains the reduction
          s_ks0_q        <= s_ks0_q + {14'd0, s_klen_q};
          s_klen_q       <= s_next_klen;
          s_ahalf_q      <= ~s_ahalf_q;
          s_pack_base_q  <= '0;
          s_gdy_q        <= s_dy_q;
          s_gdx_q        <= s_dx_q;
          s_oy_q         <= s_ty_q + {9'd0, s_dy_q};
          s_ox_q         <= s_tx_q + {9'd0, s_dx_q};
          s_g_q          <= '0;
          s_kloc_q       <= '0;
          s_ci_q         <= s_sn_ci_q;
          s_kpos_h_q     <= s_sn_kh_q;
          s_kpos_w_q     <= s_sn_kw_q;
          s_gpos_bytes_q <= {2'd0, s_next_klen};
          s_granule_q    <= 25'({21'd0, s_pcnt_q} * {14'd0, s_next_klen});
          s_gbase_q      <= s_in0_base_q;
          s_grow_q       <= s_irow_q;
          s_ghalf_q      <= ~s_ghalf_q;
        end

        // MAC stream: issue A/W row reads, consume returned rows. The stream
        // registers re-arm per slice; the context token only on the acquire.
        if ((s_state_q == SchAccStart) && ((s_ks0_q != 25'd0) || s_acc_start_ready)) begin
          if (s_ks0_q == 25'd0) begin
            s_ctx_q <= s_acc_ctx;
          end
          s_mac_k_q      <= '0;
          s_mac_done_q   <= '0;
          s_mac_pend_q   <= 1'b0;
          s_acc_if_q     <= 2'b00;
          // a packed whole reduction (A-reuse) streams all full_k rows in one
          // pass; a K-slice chunk streams only its klen rows
          s_stream_len_q <= s_a_reuse ? s_full_k_q : {14'd0, s_klen_q};
        end
        if ((s_state_q == SchMacStream) && s_a_read_valid) begin
          s_mac_k_q    <= s_mac_k_q + 25'd1;
          s_mac_pend_q <= 1'b1;
        end
        if ((s_state_q == SchMacStream) && s_mac_pend_q && s_mac_req_ready) begin
          if (!s_a_read_valid) begin
            s_mac_pend_q <= 1'b0;
          end
          s_mac_done_q <= s_mac_done_q + 25'd1;
        end
        if ((s_state_q == SchMacStream) && s_mac_resp_valid && s_acc_row_ready) begin
          s_acc_if_q <= {s_acc_if_q[0], 1'b1};
        end else if (s_acc_if_q != 2'b00) begin
          s_acc_if_q <= {1'b0, s_acc_if_q[1]};
        end
        // depthwise stream reuses the same read pipeline
        if ((s_state_q == SchVecStart) && s_vec_start_ready && s_is_dw) begin
          s_vec_k_q    <= '0;
          s_mac_pend_q <= 1'b0;
        end
        if ((s_state_q == SchVecStream) && s_a_read_valid) begin
          s_vec_k_q    <= s_vec_k_q + 4'd1;
          s_mac_pend_q <= 1'b1;
        end
        if ((s_state_q == SchVecStream) && s_mac_pend_q && s_vec_dw_ready) begin
          if (!s_a_read_valid) begin
            s_mac_pend_q <= 1'b0;
          end
        end

        // accumulator drain: request once, then consume 64 sums
        if ((s_state_q != SchAccDrain) && (s_state_d == SchAccDrain)) begin
          s_acc_drain_pulse_q <= 1'b1;
          s_drain_idx_q       <= '0;
          s_resp_p_q          <= '0;
          s_resp_c_q          <= '0;
          s_resp_off_q        <= {3'd0, s_group_q, 3'b000};
          s_resp_cnt_q        <= '0;
          s_fed_total_q       <= 13'({9'd0, s_pcnt_q} * {9'd0, s_glane_q});
        end else begin
          s_acc_drain_pulse_q <= 1'b0;
        end
        if ((s_state_q == SchAccDrain) && s_acc_drain_data_valid && s_acc_drain_data_ready) begin
          s_drain_idx_q <= s_drain_idx_q + 7'd1;
        end

        // vector drain request: once per context
        if ((s_state_q != SchVecDrain) && (s_state_d == SchVecDrain)) begin
          s_vec_drain_pulse_q <= 1'b1;
          if (s_is_dw) begin
            s_drain_idx_q <= '0;
            s_resp_p_q    <= '0;
            s_resp_c_q    <= '0;
            s_resp_off_q  <= s_pidx_off_q + {3'd0, s_group_q, 3'b000};
            s_resp_cnt_q  <= '0;
            s_fed_total_q <= 13'({10'd0, s_glane_q});
          end else begin
            s_drain_idx_q <= '0;
            s_resp_cnt_q  <= '0;
            s_fed_total_q <= '0;
          end
        end else begin
          s_vec_drain_pulse_q <= 1'b0;
        end
        if ((s_state_q == SchVecDrain) && s_vec_drain_data_valid && s_vec_drain_data_ready) begin
          s_drain_idx_q <= s_drain_idx_q + 7'd1;
        end

        // requantizer response bookkeeping: advance (position, lane) and the
        // staging byte offset per accepted response
        if ((s_state_q == SchAccDrain) || (s_state_q == SchVecDrain) ||
            (s_state_q == SchAddFeed)) begin
          if (s_rq_resp_valid && s_rq_resp_ready && !s_rq_resp_fault) begin
            s_resp_cnt_q <= s_resp_cnt_q + 13'd1;
            if (({10'd0, s_resp_c_q} + 14'd1) >= {10'd0, s_glane_q}) begin
              s_resp_c_q   <= '0;
              s_resp_p_q   <= s_resp_p_q + 3'd1;
              s_resp_off_q <= s_resp_off_q + s_slot_q - {9'd0, s_glane_q} + 13'd1;
            end else begin
              s_resp_c_q   <= s_resp_c_q + 3'd1;
              s_resp_off_q <= s_resp_off_q + 13'd1;
            end
          end
        end

        // pool readback stream: taps decompose through s_rb_kh_q/s_rb_kw_q;
        // in-range taps feed the vector aux
        if ((s_state_q == SchVecStart) && s_vec_start_ready && !s_is_dw) begin
          s_pool_k_q    <= '0;
          s_pool_vcnt_q <= '0;
          s_rb_kh_q     <= '0;
          s_rb_kw_q     <= '0;
          s_rb_pend_q   <= 1'b0;
          s_rb_half_q   <= s_ghalf_q;
          s_pool_neg_q  <= 1'b0;
          // taps of the resident granule: the whole pool window, or the
          // current GAP chunk
          s_pool_kmax_q <= s_is_gap ? s_gap_cpos_q : s_full_k_q[12:0];
        end
        if ((s_state_q == SchPoolStream) && s_rb_pend_q) begin
          // returned byte feeds the aux unit
          s_rb_pend_q   <= 1'b0;
          s_pool_vcnt_q <= s_pool_vcnt_q + 13'd1;
        end
        if ((s_state_q == SchPoolStream) && (s_pool_k_q < s_pool_kmax_q)) begin
          if (s_pool_in && !s_rb_pend_q && s_raw_rb_valid) begin
            // issued an in-range tap read; tap advances on the returned feed
            s_rb_pend_q <= 1'b1;
            s_rb_sel_q  <= s_pool_c_q[1:0];
          end else if (!s_pool_in) begin
            // padding tap: excluded, no read
            s_pool_k_q <= s_pool_k_q + 13'd1;
            if (({1'b0, s_rb_kw_q} + 14'd1) == {1'b0, s_kw_lim}) begin
              s_rb_kw_q <= '0;
              s_rb_kh_q <= s_rb_kh_q + 13'd1;
            end else begin
              s_rb_kw_q <= s_rb_kw_q + 13'd1;
            end
          end
        end
        if ((s_state_q == SchPoolStream) && s_rb_pend_q && s_pool_in) begin
          // in-range tap fully consumed: advance the tap
          s_pool_k_q <= s_pool_k_q + 13'd1;
          if (({1'b0, s_rb_kw_q} + 14'd1) == {1'b0, s_kw_lim}) begin
            s_rb_kw_q <= '0;
            s_rb_kh_q <= s_rb_kh_q + 13'd1;
          end else begin
            s_rb_kw_q <= s_rb_kw_q + 13'd1;
          end
        end
        // GAP per-channel running totals (checked merge at stream end)
        if (s_is_gap && (s_state_q == SchPoolStream) && !s_pool_more) begin
          if (s_pool_total_ovf) begin
            s_arith_fault <= 1'b1;
            s_arith_lane  <= 6'(s_pool_c_q[2:0]);
          end
          s_pool_total_q[s_pool_c_q[2:0]] <= s_pool_total_next;
        end

        // pool divide: kick at SchPoolDiv entry, stage on completion
        if ((s_state_q != SchPoolDiv) && (s_state_d == SchPoolDiv)) begin
          s_div_issued_q <= 1'b0;
          s_pool_stage_q <= 1'b0;
          if (s_op_q != `APB4_NPU__OP_MAX_POOL) begin
            // GAP enters only from SchVecDrain, whose channel reset lands on
            // the same edge: the first divide addresses channel 0 explicitly
            s_div_num_q  <= (s_is_gap && (s_state_q == SchVecDrain)) ? s_gap_first_num :
                s_pool_div_num;
            s_div_den_q <= s_pool_div_den;
            s_div_rem_q <= '0;
            s_div_quo_q <= '0;
            s_div_cnt_q <= 6'd32;
            s_div_busy_q <= 1'b1;
            s_pool_neg_q <= (s_is_gap && (s_state_q == SchVecDrain)) ? s_gap_first_neg :
                s_pool_div_neg;
          end
        end
        if ((s_state_q == SchPoolDiv) && s_div_busy_q) begin
          s_div_issued_q <= 1'b1;
        end
        if ((s_state_q == SchPoolDiv) && !s_pool_stage_q &&
            ((s_op_q == `APB4_NPU__OP_MAX_POOL) ||
             ((s_op_q != `APB4_NPU__OP_MAX_POOL) && s_div_issued_q && !s_div_busy_q))) begin
          s_pool_stage_q <= 1'b1;
        end
        if (s_pool_stage_done) begin
          s_pool_stage_q <= 1'b0;
        end
        // GAP divide phase: re-kick per channel until the group completes
        if (s_is_gap && (s_state_q == SchPoolDiv) && s_pool_stage_done) begin
          if (s_pool_stream_last) begin
            s_pool_c_q <= '0;
            if (!s_group_last) begin
              s_group_q     <= s_group_q + 10'd1;
              s_gap_chunk_q <= '0;
              for (int unsigned lane = 0; lane < 8; lane++) begin
                s_pool_total_q[lane] <= '0;
              end
            end
          end else begin
            s_pool_c_q     <= s_pool_c_q + 13'd1;
            s_div_num_q    <= s_gap_next_num;
            s_div_den_q    <= s_full_k_q;
            s_div_rem_q    <= '0;
            s_div_quo_q    <= '0;
            s_div_cnt_q    <= 6'd32;
            s_div_busy_q   <= 1'b1;
            s_div_issued_q <= 1'b0;
            s_pool_neg_q   <= s_gap_next_neg;
          end
        end

        // CLAMP readback: every gathered byte clamps into staging; grouped
        // tail lanes (lane >= glane) are gathered but never staged
        if ((s_state_q == SchGathExit) && (s_state_d == SchClamp)) begin
          s_clamp_off_q <= '0;
          // position-major staging starts at this group's lane base
          s_clamp_stg_q <= {3'd0, s_group_q, 3'b000};
          s_clamp_c_q   <= '0;
          s_clamp_len_q <= s_granule_q[12:0];
          s_rb_pend_q   <= 1'b0;
          s_rb_half_q   <= s_ghalf_q;
        end
        if ((s_state_q == SchClamp) && s_raw_rb_valid) begin
          s_rb_pend_q   <= 1'b1;
          s_rb_sel_q    <= s_clamp_off_q[1:0];
          s_clamp_off_q <= s_clamp_off_q + 13'd1;
        end else if ((s_state_q == SchClamp) && s_rb_pend_q) begin
          s_rb_pend_q <= 1'b0;
          if ({10'd0, s_clamp_c_q} < {10'd0, s_glane_q}) begin
            if (({10'd0, s_clamp_c_q} + 14'd1) >= {10'd0, s_glane_q}) begin
              s_clamp_stg_q <= s_clamp_stg_q + s_slot_q - {9'd0, s_glane_q} + 13'd1;
            end else begin
              s_clamp_stg_q <= s_clamp_stg_q + 13'd1;
            end
          end
          if (({10'd0, s_clamp_c_q} + 14'd1) >= 14'd8) begin
            s_clamp_c_q <= '0;
          end else begin
            s_clamp_c_q <= s_clamp_c_q + 3'd1;
          end
        end

        // ADD feed: alternate input0/input1 items through the inline QM
        if ((s_state_q == SchGathExit) && (s_state_d == SchAddFeed)) begin
          s_add_p_q         <= '0;
          s_add_c_q         <= '0;
          s_add_in_q        <= 1'b0;

          s_add_loop_done_q <= 1'b0;
          s_resp_p_q        <= '0;
          s_resp_c_q        <= '0;
          s_resp_off_q      <= {3'd0, s_group_q, 3'b000};
          s_resp_cnt_q      <= '0;
          s_fed_total_q     <= 13'({9'd0, s_pcnt_q} * {9'd0, s_glane_q});
          s_rb_pend_q       <= 1'b0;
          s_rb_half_q       <= 1'b0;
        end
        if ((s_state_q == SchAddFeed) && s_add_more && !s_rb_pend_q) begin
          s_rb_pend_q <= 1'b1;
          s_rb_sel_q  <= s_add_byte_off[1:0];
        end
        if ((s_state_q == SchAddFeed) && s_rb_pend_q && s_aqm_load0) begin
          s_rb_pend_q <= 1'b0;
          // the returned byte loads inline-QM stage 0 below
          if (s_add_in_q) begin
            s_add_in_q <= 1'b0;
            if (({10'd0, s_add_c_q} + 14'd1) >= {10'd0, s_glane_q}) begin
              s_add_c_q <= '0;
              if (({10'd0, s_add_p_q} + 14'd1) >= {10'd0, s_pcnt_q}) begin
                s_add_loop_done_q <= 1'b1;
              end else begin
                s_add_p_q <= s_add_p_q + 4'd1;
              end
            end else begin
              s_add_c_q <= s_add_c_q + 4'd1;
            end
          end else begin
            s_add_in_q <= 1'b1;
          end
        end

        // ADD inline QM pipeline (elastic three stages)
        if (s_aqm_load0) begin
          s_aqm_v0_q <= 1'b1;
          s_aqm_d0_q <= (s_aqm_in_shift > 8'sd0) ? s_aqm_shifted[31:0] : s_aqm_in_data;
          s_aqm_f0_q <= s_aqm_shift_fault;
          s_aqm_m0_q <= s_aqm_in_mult;
          s_aqm_s0_q <= s_aqm_in_shift;
          s_aqm_t0_q <= {s_add_p_q[2:0], s_add_c_q[2:0], s_add_in_q};
        end else if (s_aqm_s1_free) begin
          s_aqm_v0_q <= 1'b0;
        end
        if (s_aqm_v0_q && s_aqm_s1_free) begin
          s_aqm_v1_q <= 1'b1;
          s_aqm_p1_q <= s_aqm_d0_q * $signed({1'b0, s_aqm_m0_q});
          s_aqm_f1_q <= s_aqm_f0_q;
          s_aqm_s1_q <= s_aqm_s0_q;
          s_aqm_t1_q <= s_aqm_t0_q;
        end else if (s_aqm_s2_free) begin
          s_aqm_v1_q <= 1'b0;
        end
        if (s_aqm_v1_q && s_aqm_s2_free) begin
          s_aqm_v2_q <= 1'b1;
          s_aqm_d2_q <= rounding_divide_by_pot(nudge_truncate(s_aqm_p1_q), s_aqm_rdp_exp);
          s_aqm_f2_q <= s_aqm_f1_q;
          s_aqm_t2_q <= s_aqm_t1_q;
        end else if (s_aqm_consume) begin
          s_aqm_v2_q <= 1'b0;
        end
        if (s_aqm_consume && s_aqm_v2_q) begin
          if (s_aqm_f2_q) begin
            s_arith_fault <= 1'b1;
            s_arith_lane  <= s_aqm_t2_q[6:1];
          end else if (!s_aqm_t2_q[0]) begin
            s_add_t0_q <= s_aqm_d2_q;
          end else if (s_add_total_ovf) begin
            s_arith_fault <= 1'b1;
            s_arith_lane  <= s_aqm_t2_q[6:1];
          end
        end

        // ADD descriptor parameter record done
        if ((s_state_q == SchParamRd) && s_pr_done && s_pr_add_q) begin
          s_add_params_done_q <= 1'b1;
        end
        // ADD granule switch: input0 gathered, gather input1 next
        if ((s_state_q == SchGathExit) && (s_state_d == SchGathSeg) && s_is_add) begin
          s_add_in1_q <= 1'b1;
          s_gdy_q     <= s_dy_q;
          s_gdx_q     <= s_dx_q;
          s_oy_q      <= s_ty_q + {9'd0, s_dy_q};
          s_ox_q      <= s_tx_q + {9'd0, s_dx_q};
          s_g_q       <= '0;
          s_kloc_q    <= '0;
          s_ci_q      <= '0;
          s_kpos_h_q  <= '0;
          s_kpos_w_q  <= '0;
          s_gbase_q   <= s_in1_base_q;
          s_grow_q    <= s_in1_row_q;
          s_ghalf_q   <= 1'b1;
        end

        // parameter slice / ADD record reader: the group-slice read is
        // (re)armed on every entry into SchParamRd (from SchGrpInit on an
        // A-reuse hit, or from SchPackWait after the final slice pack); the
        // ADD record entry from SchDescInit has its own arming below
        if ((s_state_q != SchParamRd) && (s_state_d == SchParamRd) &&
            !((s_state_q == SchDescInit) && s_is_add)) begin
          s_pr_idx_q   <= '0;
          s_pr_pend_q  <= 1'b0;
          s_pr_add_q   <= 1'b0;
          // only the group's real records were streamed into the window:
          // reading past them trips the SRAM valid-row access error
          s_pr_count_q <= {2'd0, s_glane_q, 2'b00};
        end
        if ((s_state_q == SchDescInit) && (s_state_d == SchParamRd) && s_is_add) begin
          s_pr_idx_q   <= '0;
          s_pr_pend_q  <= 1'b0;
          s_pr_add_q   <= 1'b1;
          s_pr_count_q <= 6'd8;
        end
        if ((s_state_q == SchParamRd) && !s_pr_done) begin
          if (!s_pr_pend_q) begin
            s_pr_pend_q <= 1'b1;
          end else begin
            s_pr_pend_q <= 1'b0;
            s_pr_idx_q  <= s_pr_idx_q + 6'd1;
            if (s_pr_add_q) begin
              unique case (s_pr_idx_q[2:0])
                3'd1: s_add_m_q[0] <= s_param_read_data;
                3'd2: s_add_s_q[0] <= s_param_read_data[7:0];
                3'd3: s_add_m_q[1] <= s_param_read_data;
                3'd4: s_add_s_q[1] <= s_param_read_data[7:0];
                3'd5: s_add_m_q[2] <= s_param_read_data;
                3'd6: s_add_s_q[2] <= s_param_read_data[7:0];
                default: begin
                end
              endcase
            end else begin
              unique case (s_pr_idx_q[1:0])
                2'd0: s_pbias_q[s_pr_idx_q[4:2]] <= s_param_read_data;
                2'd1: s_pmult_q[s_pr_idx_q[4:2]] <= s_param_read_data;
                2'd2: s_pshift_q[s_pr_idx_q[4:2]] <= s_param_read_data[7:0];
                default: begin
                end
              endcase
            end
            if (s_pr_fault) begin
              s_desc_fault <= 1'b1;
            end
          end
        end

        // store engine
        if ((s_state_q != SchStoreInit) && (s_state_d == SchStoreInit)) begin
          if ((s_state_q == SchAccDrain) || (s_state_q == SchVecDrain) ||
              (s_state_q == SchClamp) || (s_state_q == SchAddFeed) ||
              (s_state_q == SchPoolDiv) ||
              ((s_state_q == SchStoreWait) && s_pass_last)) begin
            s_pidx_q  <= '0;
            s_st_dy_q <= s_dy_q;
            s_st_dx_q <= s_dx_q;
          end
        end
        if (s_state_q == SchStoreInit) begin
          s_st_pos_addr_q <= 32'({32'd0, s_out_base_q} +
                                 ({19'd0, s_st_oy} * {32'd0, s_orow_q}) +
                                 ({19'd0, s_st_ox} * {51'd0, s_cout_q}));
          s_st_cur_q <= 32'({32'd0, s_out_base_q} + ({19'd0, s_st_oy} * {32'd0, s_orow_q}) +
                            ({19'd0, s_st_ox} * {51'd0, s_cout_q}));
          s_st_rem_q <= {12'd0, s_cout_q} + (s_st_row_pad ? s_st_pad_q[24:0] : 25'd0);
          s_st_soff_q <= s_pidx_off_q;
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
          s_st_rem_q <= s_st_rem_q - {12'd0, s_st_cmd_bytes_q};
        end

        // position / pass / tile advance at a completed position store
        if ((s_state_q == SchStoreWait) && write_done_i &&
            ((s_st_rem_q - {12'd0, s_st_cmd_bytes_q}) == 25'd0)) begin
          if ({9'd0, s_pidx_q} + 13'd1 < {9'd0, s_pcnt_q}) begin
            s_pidx_q <= s_pidx_q + 4'd1;
            if (({1'b0, s_st_dx_q} + 5'd1) == {1'b0, s_tcols_q}) begin
              s_st_dx_q <= '0;
              s_st_dy_q <= s_st_dy_q + 4'd1;
            end else begin
              s_st_dx_q <= s_st_dx_q + 4'd1;
            end
            if (({1'b0, s_dx_q} + 5'd1) == {1'b0, s_tcols_q}) begin
              s_dx_q <= '0;
              s_dy_q <= s_dy_q + 4'd1;
            end else begin
              s_dx_q <= s_dx_q + 4'd1;
            end
          end else if (!s_tile_last) begin
            // a new pass or tile starts a fresh staging window: the position
            // index restarts at slot 0 for both the compute and store loops
            s_pidx_q <= '0;
            // Only one 8192-byte parameter window is resident. If the prior
            // pass reached a later window, rewind the external stream so the
            // new pass's group zero cannot consume those stale records.
            if (s_pbytes_q > 32'd8192) begin
              s_pdone_q     <= '0;
              s_prem_q      <= '0;
              s_pchunk_q    <= '0;
              s_poff_q      <= '0;
              s_phalf_q     <= 1'b0;
              s_pend_last_q <= 1'b0;
            end
            if (s_pass_last) begin
              // next tile
              if (({16'd0, s_tx_q} + {24'd0, s_tw_q}) < {16'd0, s_ow_q}) begin
                s_tx_q    <= s_tx_q + {9'd0, s_tw_q};
                s_tcols_q <= s_tile_cols_next;
              end else begin
                s_tx_q    <= '0;
                s_ty_q    <= s_ty_q + {9'd0, s_th_q};
                s_trows_q <= s_tile_rows_next;
                s_tcols_q <= 4'(s_tw_q[3:0]);
              end
              s_pbase_q <= '0;
              s_dy_q    <= '0;
              s_dx_q    <= '0;
              // pool position trackers restart at each new tile
              if (s_is_pool) begin
                s_gdy_q <= '0;
                s_gdx_q <= '0;
              end
            end else begin
              s_pbase_q <= s_pbase_q + s_pcnt_q;
              // The final position of the old pass did not take the
              // same-pass position-advance branch above. Move the compute
              // cursor to the first position of the next pass now.
              if (({1'b0, s_dx_q} + 5'd1) == {1'b0, s_tcols_q}) begin
                s_dx_q <= '0;
                s_dy_q <= s_dy_q + 4'd1;
              end else begin
                s_dx_q <= s_dx_q + 4'd1;
              end
              if (s_is_pool) begin
                if (({1'b0, s_gdx_q} + 5'd1) == {1'b0, s_tcols_q}) begin
                  s_gdx_q <= '0;
                  s_gdy_q <= s_gdy_q + 4'd1;
                end else begin
                  s_gdx_q <= s_gdx_q + 4'd1;
                end
              end
            end
            s_group_q   <= '0;
            s_wrow_q    <= '0;
            s_a_ready_q <= 1'b0;
            if (s_is_gap) begin
              s_gap_chunk_q <= '0;
            end
          end
        end

        // group advance: dense/depthwise accumulate the W row base per group
        if ((s_state_q == SchAccDrain) && s_drain_done && !s_group_last) begin
          s_group_q <= s_group_q + 10'd1;
          s_wrow_q  <= s_wrow_q + {10'd0, s_full_k_q};
        end
        if ((s_state_q == SchVecDrain) && s_vec_drain_done && s_is_dw) begin
          if ({9'd0, s_pidx_q} + 13'd1 < {9'd0, s_pcnt_q}) begin
            s_pidx_q <= s_pidx_q + 4'd1;
          end else begin
            s_pidx_q <= '0;
            if (!s_group_last) begin
              s_group_q <= s_group_q + 10'd1;
              s_wrow_q  <= s_wrow_q + 34'd9;
            end
          end
        end
        if ((s_state_q == SchClamp) && !s_clamp_more && !s_group_last) begin
          s_group_q <= s_group_q + 10'd1;
        end
        if ((s_state_q == SchAddFeed) && s_add_done && !s_group_last) begin
          s_group_q <= s_group_q + 10'd1;
        end
        // ADD completes a group's input pair: the next granule (next group,
        // pass or tile) starts again from the input0 granule
        if ((s_state_q == SchAddFeed) && s_add_done) begin
          s_add_in1_q <= 1'b0;
        end

        // pool release advance: channel, then group, then position
        if ((s_state_q == SchVecDrain) && s_vec_drain_done && s_is_pool) begin
          if (!s_pool_stream_last) begin
            s_pool_c_q <= s_pool_c_q + 13'd1;
          end else begin
            s_pool_c_q <= '0;
            if (!s_group_last) begin
              s_group_q <= s_group_q + 10'd1;
            end else begin
              s_group_q <= '0;
              if ({9'd0, s_pidx_q} + 13'd1 < {9'd0, s_pcnt_q}) begin
                s_pidx_q <= s_pidx_q + 4'd1;
                if (({1'b0, s_gdx_q} + 5'd1) == {1'b0, s_tcols_q}) begin
                  s_gdx_q <= '0;
                  s_gdy_q <= s_gdy_q + 4'd1;
                end else begin
                  s_gdx_q <= s_gdx_q + 4'd1;
                end
              end
            end
          end
        end

        // GAP release advance: channel, then chunk; divide phase per channel
        if ((s_state_q == SchVecDrain) && s_vec_drain_done && s_is_gap) begin
          if (!s_pool_stream_last) begin
            s_pool_c_q <= s_pool_c_q + 13'd1;
          end else begin
            s_pool_c_q <= '0;
            if (s_gap_more_chunks) begin
              s_gap_chunk_q <= s_gap_chunk_q + {12'd0, s_gap_cpos_q};
            end
          end
        end
        // GAP chunk granule setup for the next chunk gather
        if ((s_state_q == SchVecDrain) && s_vec_drain_done && s_is_gap &&
            s_pool_stream_last && s_gap_more_chunks) begin
          s_gap_cpos_q <= ((s_full_k_q - (s_gap_chunk_q + {12'd0, s_gap_cpos_q})) > 25'd1024) ?
              13'd1024 : 13'(s_full_k_q - (s_gap_chunk_q + {12'd0, s_gap_cpos_q}));
        end
        if (s_is_gap && (s_state_q == SchGrpInit) && (s_state_d == SchGathSeg)) begin
          s_gap_cpos_q <= s_gap_cpos_comb;
        end

        // pass position count and tile position count at pass/tile start
        if ((s_state_q == SchDescInit) && (s_state_d == SchGrpInit)) begin
          s_tile_m_q <= s_tile_m_comb;
          s_pcnt_q   <= s_pcnt_first;
        end
        if ((s_state_q == SchStoreWait) && write_done_i &&
            ((s_st_rem_q - {12'd0, s_st_cmd_bytes_q}) == 25'd0) &&
            ({9'd0, s_pidx_q} + 13'd1 >= {9'd0, s_pcnt_q}) && !s_tile_last) begin
          if (s_pass_last) begin
            s_pcnt_q   <= s_pcnt_tile;
            s_tile_m_q <= s_tile_m_next;
          end else begin
            s_pcnt_q <= s_pcnt_next;
          end
          if (s_is_gap) begin
            for (int unsigned lane = 0; lane < 8; lane++) begin
              s_pool_total_q[lane] <= '0;
            end
          end
        end

        // requantizer items in flight
        if (s_rq_req_valid && s_rq_req_ready) begin
          s_rq_out_q <= s_rq_out_q + 7'd1;
        end
        if (s_rq_resp_valid && s_rq_resp_ready) begin
          s_rq_out_q <= s_rq_out_q - 7'd1;
        end

        // divider iteration
        if (s_div_busy_q) begin
          if ({s_div_rem_q[31:0], s_div_num_q[31]} >= {9'd0, s_div_den_q}) begin
            s_div_rem_q <= ({s_div_rem_q[31:0], s_div_num_q[31]} - {9'd0, s_div_den_q});
            s_div_quo_q <= {s_div_quo_q[30:0], 1'b1};
          end else begin
            s_div_rem_q <= {s_div_rem_q[31:0], s_div_num_q[31]};
            s_div_quo_q <= {s_div_quo_q[30:0], 1'b0};
          end
          s_div_num_q <= {s_div_num_q[30:0], 1'b0};
          if (s_div_cnt_q == 6'd1) begin
            s_div_busy_q <= 1'b0;
          end
          s_div_cnt_q <= s_div_cnt_q - 6'd1;
        end

        // compute-unit fault capture (lowest lane wins per cycle)
        if (s_acc_fault) begin
          s_arith_fault <= 1'b1;
          s_arith_lane  <= {2'd0, s_acc_fault_sum};
        end
        if (s_vec_fault) begin
          s_arith_fault <= 1'b1;
          if (s_is_dw) begin
            s_arith_lane <= {1'b0, s_pidx_q, s_vec_fault_lane};
          end else begin
            s_arith_lane <= 8'd255;
          end
        end
        if (s_rq_resp_valid && s_rq_resp_fault) begin
          s_arith_fault <= 1'b1;
          s_arith_lane  <= {s_resp_p_q, s_resp_c_q};
        end

        // counters (saturating)
        if (job_active_i && (s_mac_req_valid && s_mac_req_ready) &&
            (s_cnt_macs_q != 64'hffff_ffff_ffff_ffff)) begin
          s_cnt_macs_q <= s_cnt_macs_q + {56'd0, ({4'd0, s_pcnt_q} * {4'd0, s_glane_q})};
        end
        if (job_active_i && (s_vec_dw_valid && s_vec_dw_ready) &&
            (s_cnt_macs_q != 64'hffff_ffff_ffff_ffff)) begin
          s_cnt_macs_q <= s_cnt_macs_q + {60'd0, s_glane_q};
        end
        if (job_active_i && s_stage_valid && !s_stage_grant &&
            (s_cnt_bank_q != 64'hffff_ffff_ffff_ffff)) begin
          s_cnt_bank_q <= s_cnt_bank_q + 64'd1;
        end
        if (job_active_i &&
            ((s_acc_drain_data_valid && s_feed_valid && !s_rq_req_ready) ||
             (s_vec_drain_data_valid && s_feed_valid && s_is_dw && !s_rq_req_ready) ||
             (s_add_total_valid && !s_rq_req_ready)) &&
            (s_cnt_rqstall_q != 64'hffff_ffff_ffff_ffff)) begin
          s_cnt_rqstall_q <= s_cnt_rqstall_q + 64'd1;
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

        // fault capture: the spec priority is AXI_*, LOCAL_STATE, ARITHMETIC,
        // DESCRIPTOR, UNSUPPORTED, NO_PROGRESS inside this module
        if (!s_fault_seen_q && (s_state_d == SchFaultWait) && (s_state_q != SchFaultWait)) begin
          s_fault_seen_q <= 1'b1;
          s_q_cnt_q      <= 5'd0;
          // drop every in-flight item toward the compute units: the job is
          // aborted, partial stores are defined
          s_mac_pend_q   <= 1'b0;
          s_rb_pend_q    <= 1'b0;
          s_aqm_v0_q     <= 1'b0;
          s_aqm_v1_q     <= 1'b0;
          s_aqm_v2_q     <= 1'b0;
          s_div_busy_q   <= 1'b0;
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
          end else if (s_arith_fault) begin
            s_fault_code_q <= `APB4_NPU__FAULT_CODE_ARITHMETIC;
            s_fault_addr_q <= 32'd0;
            s_fault_info_q <= {16'd0, s_arith_lane, 4'd0, 2'd0, 2'd0};
          end else if (s_desc_fault) begin
            s_fault_code_q <= `APB4_NPU__FAULT_CODE_DESCRIPTOR;
            s_fault_addr_q <= s_desc_faddr;
            s_fault_info_q <= FaultInfoInternal;
          end else if (s_unsup_fault) begin
            s_fault_code_q <= `APB4_NPU__FAULT_CODE_UNSUPPORTED;
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
  logic         s_ghalf_hd;
  logic         s_raw_read_half_hd;
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
  logic         s_a_read_valid_hd;
  logic         s_a_read_half_hd;
  logic [ 12:0] s_a_read_addr_hd;
  logic         s_w_read_valid_hd;
  logic         s_w_read_half_hd;
  logic [ 12:0] s_w_read_addr_hd;
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
  logic         s_param_read_valid_hd;
  logic [ 12:0] s_param_read_addr_hd;
  logic [298:0] s_sram_pre;
  logic [298:0] s_sram_hd;

  assign s_sram_pre = {
    s_raw_write_valid,
    s_ghalf_q,
    s_raw_write_addr,
    s_raw_write_data,
    s_raw_write_strb,
    s_raw_read_valid,
    s_raw_read_half,
    s_raw_read_addr,
    s_pack_write_valid,
    s_pack_write_sel_w,
    s_pack_write_half,
    s_pack_write_addr,
    s_pack_write_data,
    s_pack_write_strb,
    s_a_read_valid,
    s_a_read_half,
    s_a_read_addr,
    s_w_read_valid,
    s_w_read_half,
    s_w_read_addr,
    s_out_valid,
    s_out_write,
    s_out_half,
    s_out_addr,
    s_out_wdata,
    s_out_wstrb,
    s_param_write_valid,
    s_param_write_addr,
    s_param_write_data,
    s_param_write_strb,
    s_param_read_valid,
    s_param_read_addr
  };

`ifdef SYNTHESIS
  for (genvar hold_bit = 0; hold_bit < 299; hold_bit++) begin : gen_sram_hold
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
    s_raw_write_valid_hd, s_ghalf_hd, s_raw_write_addr_hd, s_raw_write_data_hd,
    s_raw_write_strb_hd, s_raw_read_valid_hd, s_raw_read_half_hd, s_raw_read_addr_hd,
    s_pack_write_valid_hd, s_pack_write_sel_w_hd, s_pack_write_half_hd,
    s_pack_write_addr_hd, s_pack_write_data_hd, s_pack_write_strb_hd,
    s_a_read_valid_hd, s_a_read_half_hd, s_a_read_addr_hd,
    s_w_read_valid_hd, s_w_read_half_hd, s_w_read_addr_hd,
    s_out_valid_hd, s_out_write_hd, s_out_half_hd, s_out_addr_hd, s_out_wdata_hd,
    s_out_wstrb_hd, s_param_write_valid_hd, s_param_write_addr_hd,
    s_param_write_data_hd, s_param_write_strb_hd,
    s_param_read_valid_hd, s_param_read_addr_hd
  } = s_sram_hd;

  // ---------------------------------------------------------------------
  // Local storage, packer and compute units
  // ---------------------------------------------------------------------
  npu_patch_packer u_patch_packer (
      .clk_i             (clk_hp_i),
      .rst_n_i           (rst_hp_n_i),
      .start_valid_i     (s_pack_start),
      .start_ready_o     (s_pack_ready),
      .start_mode_i      (s_is_dw ? npu_pkg::PackDepthwise : npu_pkg::PackDense),
      .start_k_i         (s_is_dw ? 11'd9 : s_klen_q),
      .start_positions_i (s_pcnt_q),
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

  npu_mac_array u_mac_array (
      .clk_i          (clk_hp_i),
      .rst_n_i        (rst_hp_n_i),
      .req_valid_i    (s_mac_req_valid),
      .req_ready_o    (s_mac_req_ready),
      .req_a_bytes_i  (s_a_read_data),
      .req_w_bytes_i  (s_w_read_data),
      .req_in_zero_i  (s_zp_q),
      .req_a_valid_i  (s_mac_a_valid),
      .req_w_valid_i  (s_mac_w_valid),
      .resp_valid_o   (s_mac_resp_valid),
      .resp_ready_i   (s_mac_resp_ready),
      .resp_products_o(s_mac_resp_products)
  );

  npu_accumulator u_accumulator (
      .clk_i             (clk_hp_i),
      .rst_n_i           (rst_hp_n_i),
      .clear_i           (s_unit_clear),
      .start_valid_i     (s_acc_start_valid),
      .start_ready_o     (s_acc_start_ready),
      .start_bias_i      (s_pbias_q),
      .start_context_o   (s_acc_ctx),
      .row_valid_i       (s_acc_row_valid),
      .row_ready_o       (s_acc_row_ready),
      .row_context_i     (s_ctx_q),
      .row_products_i    (s_mac_resp_products),
      .drain_valid_i     (s_acc_drain_valid),
      .drain_context_i   (s_ctx_q),
      .drain_data_valid_o(s_acc_drain_data_valid),
      .drain_data_ready_i(s_acc_drain_data_ready),
      .drain_data_o      (s_acc_drain_data),
      .drain_last_o      (s_acc_drain_last),
      .busy_o            (s_acc_busy),
      .fault_sticky_o    (s_acc_fault),
      .fault_sum_o       (s_acc_fault_sum)
  );

  npu_vector u_vector (
      .clk_i             (clk_hp_i),
      .rst_n_i           (rst_hp_n_i),
      .clear_i           (s_unit_clear),
      .start_valid_i     (s_vec_start_valid),
      .start_ready_o     (s_vec_start_ready),
      .start_bias_i      (s_vec_bias),
      .dw_valid_i        (s_vec_dw_valid),
      .dw_ready_o        (s_vec_dw_ready),
      .dw_a_bytes_i      (s_a_read_data),
      .dw_w_bytes_i      (s_w_read_data),
      .dw_in_zero_i      (s_zp_q),
      .dw_lane_valid_i   (s_mac_w_valid),
      .aux_valid_i       (s_vec_aux_valid),
      .aux_op_i          (s_vec_aux_op),
      .aux_data_i        (s_rb_byte),
      .drain_valid_i     (s_vec_drain_valid),
      .drain_data_valid_o(s_vec_drain_data_valid),
      .drain_data_ready_i(s_vec_drain_data_ready),
      .drain_data_o      (s_vec_drain_data),
      .drain_last_o      (s_vec_drain_last),
      .aux_result_o      (s_vec_aux_result),
      .busy_o            (s_vec_busy),
      .fault_sticky_o    (s_vec_fault),
      .fault_lane_o      (s_vec_fault_lane)
  );

  npu_requantizer u_requantizer (
      .clk_i           (clk_hp_i),
      .rst_n_i         (rst_hp_n_i),
      .req_valid_i     (s_rq_req_valid),
      .req_ready_o     (s_rq_req_ready),
      .req_acc_i       (s_rq_req_acc),
      .req_multiplier_i(s_rq_req_mult),
      .req_shift_i     (s_rq_req_shift),
      .req_zout_i      (s_zout_q),
      .req_act_min_i   (s_act_min_q),
      .req_act_max_i   (s_act_max_q),
      .resp_valid_o    (s_rq_resp_valid),
      .resp_ready_i    (s_rq_resp_ready),
      .resp_data_o     (s_rq_resp_data),
      .resp_fault_o    (s_rq_resp_fault)
  );

  npu_local_sram u_local_sram (
      .clk_i              (clk_hp_i),
      .rst_n_i            (rst_hp_n_i),
      .clear_i            (s_sram_clear),
      .raw_write_valid_i  (s_raw_write_valid_hd),
      .raw_write_half_i   (s_ghalf_hd),
      .raw_write_addr_i   (s_raw_write_addr_hd),
      .raw_write_data_i   (s_raw_write_data_hd),
      .raw_write_strb_i   (s_raw_write_strb_hd),
      .raw_read_valid_i   (s_raw_read_valid_hd),
      .raw_read_half_i    (s_raw_read_half_hd),
      .raw_read_addr_i    (s_raw_read_addr_hd),
      .raw_read_data_o    (s_raw_read_data),
      .pack_write_valid_i (s_pack_write_valid_hd),
      .pack_write_sel_w_i (s_pack_write_sel_w_hd),
      .pack_write_half_i  (s_pack_write_half_hd),
      .pack_write_addr_i  (s_pack_write_addr_hd),
      .pack_write_data_i  (s_pack_write_data_hd),
      .pack_write_strb_i  (s_pack_write_strb_hd),
      .a_read_valid_i     (s_a_read_valid_hd),
      .a_read_half_i      (s_a_read_half_hd),
      .a_read_addr_i      (s_a_read_addr_hd),
      .a_read_data_o      (s_a_read_data),
      .w_read_valid_i     (s_w_read_valid_hd),
      .w_read_half_i      (s_w_read_half_hd),
      .w_read_addr_i      (s_w_read_addr_hd),
      .w_read_data_o      (s_w_read_data),
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
      .param_read_valid_i (s_param_read_valid_hd),
      .param_read_addr_i  (s_param_read_addr_hd),
      .param_read_data_o  (s_param_read_data),
      .access_err_sticky_o(s_sram_err),
      .access_err_port_o  ()                         // the port code is diagnostic-only at P3
  );
endmodule
