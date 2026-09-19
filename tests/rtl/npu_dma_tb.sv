`timescale 1ns / 1ps

// NPU-P3 npu_dma unit test: 64-bit byte memory BFM with independent per
// channel LFSR delays (0..3 cycles, seeded), address-qualified SLVERR/DECERR
// injection, bad RID/BID, early/missing RLAST, residual R/B after quarantine
// and in idle, inline protocol checkers (attribute contract, 4 KiB, alignment,
// WLAST sequence, W-after-AW, zero-strobe, WSTRB inside the addressed segment,
// no read overfetch, payload stability under stall, single outstanding per
// direction, VALID retention under pause), directed alignment/length/pause/
// abort/counter cases and a deterministic LCG campaign with recorded seeds.
`include "npu_define.svh"

module npu_dma_tb;
  localparam logic [31:0] SramBase = 32'h3000_0000;
  localparam int unsigned MemoryBytes = 65536;
  localparam int unsigned PhaseTimeout = 100000;

  logic               clk_hp_i = 1'b0;
  logic               rst_hp_n_i = 1'b0;
  logic               clear_i = 1'b0;
  logic               block_new_i = 1'b0;
  logic               pause_ack_o;
  logic               read_req_valid_i = 1'b0;
  logic               read_req_ready_o;
  logic        [31:0] read_addr_i = '0;
  logic        [31:0] read_bytes_i = '0;
  logic               read_data_valid_o;
  logic               read_data_ready_i = 1'b1;
  logic        [63:0] read_data_o;
  logic        [ 7:0] read_keep_o;
  logic               read_last_o;
  logic               write_req_valid_i = 1'b0;
  logic               write_req_ready_o;
  logic        [31:0] write_addr_i = '0;
  logic        [31:0] write_bytes_i = '0;
  logic               write_data_valid_i = 1'b0;
  logic               write_data_ready_o;
  logic        [63:0] write_data_i = '0;
  logic        [ 7:0] write_keep_i = '0;
  logic               write_last_i = 1'b0;
  logic               write_done_o;
  logic               busy_o;
  logic               read_busy_o;
  logic               write_busy_o;
  logic        [63:0] read_bytes_o;
  logic        [63:0] write_bytes_o;
  logic        [63:0] stall_cycles_o;
  logic               fault_o;
  logic        [ 3:0] fault_code_o;
  logic        [31:0] fault_addr_o;
  logic        [ 1:0] fault_resp_o;
  logic               read_cmd_err_o;
  logic               write_cmd_err_o;

  logic        [ 7:0] s_memory                        [0:MemoryBytes-1];
  // read channel BFM state
  logic               s_rvalid_q;
  logic        [ 2:0] s_rid_q;
  logic        [ 1:0] s_rresp_q;
  logic        [31:0] s_raddr_q;
  logic        [63:0] s_rdata_q;
  logic        [ 2:0] s_rsize_q;
  logic        [ 8:0] s_rbeats_q;
  logic        [ 8:0] s_rburst_total_q;
  logic               s_residual_r_valid_q;
  // write channel BFM state
  logic               s_aw_pending_q;
  logic        [31:0] s_awbase_q;
  logic        [31:0] s_awaddr_q;
  logic        [ 8:0] s_wbeats_q;
  logic               s_bvalid_q;
  logic        [ 2:0] s_bid_q;
  logic        [ 1:0] s_bresp_q;
  logic               s_residual_b_valid_q;
  // injection and hold knobs (driven from tasks only)
  logic               s_read_err_en_i;
  logic        [31:0] s_read_err_addr_i;
  logic        [ 1:0] s_read_err_code_i;
  logic               s_write_err_en_i;
  logic        [31:0] s_write_err_addr_i;
  logic        [ 1:0] s_write_err_code_i;
  logic               s_inject_bad_rid_i;
  logic               s_inject_bad_bid_i;
  logic               s_inject_bad_rlast_i;
  logic               s_inject_early_rlast_i;
  logic               s_force_residual_r_i;
  logic               s_force_residual_b_i;
  logic               s_hold_ar_i;
  logic               s_hold_r_i;
  logic               s_hold_aw_i;
  logic               s_hold_w_i;
  logic               s_hold_b_i;
  // random delay engine state
  logic               s_random_delays_i;
  logic               s_random_delay_reseed_i;
  logic               s_random_delay_coverage_clear_i;
  logic        [31:0] s_random_delay_seed_i;
  logic        [31:0] s_ar_delay_lfsr_q;
  logic        [31:0] s_aw_delay_lfsr_q;
  logic        [31:0] s_w_delay_lfsr_q;
  logic        [31:0] s_r_delay_lfsr_q;
  logic        [31:0] s_b_delay_lfsr_q;
  logic        [ 1:0] s_ar_delay_q;
  logic        [ 1:0] s_aw_delay_q;
  logic        [ 1:0] s_w_delay_q;
  logic        [ 1:0] s_r_delay_q;
  logic        [ 1:0] s_b_delay_q;
  logic               s_ar_delay_pending_q;
  logic               s_aw_delay_pending_q;
  logic               s_w_delay_pending_q;
  logic               s_r_delay_pending_q;
  logic               s_b_delay_pending_q;
  logic        [ 3:0] s_ar_delay_modes_q;
  logic        [ 3:0] s_aw_delay_modes_q;
  logic        [ 3:0] s_w_delay_modes_q;
  logic        [ 3:0] s_r_delay_modes_q;
  logic        [ 3:0] s_b_delay_modes_q;
  // read stream expectation (config from tasks, bookkeeping in always blocks)
  logic               s_rd_active_i;
  logic        [31:0] s_rd_seg_addr_i;
  logic        [31:0] s_rd_seg_bytes_i;
  logic        [32:0] s_rd_seg_end_i;
  logic               s_rd_done_clear_i;
  logic        [31:0] s_rd_off_q;
  logic               s_rd_done_q;
  logic               s_ar_check_i;
  logic               s_ar_expect_set_i;
  logic        [31:0] s_ar_expect_addr_i;
  logic        [31:0] s_ar_expect_q;
  // write monitor expectation
  logic               s_wr_active_i;
  logic        [31:0] s_wr_seg_start_i;
  logic        [31:0] s_wr_seg_end_i;
  logic        [32:0] s_wr_end_aligned_i;
  logic               s_wr_clear_i;
  logic        [31:0] s_wr_bytes_seen_q;
  logic               s_aw_check_i;
  logic               s_aw_expect_set_i;
  logic        [31:0] s_aw_expect_addr_i;
  logic        [31:0] s_aw_expect_q;
  // stream backpressure and write gap control
  logic               s_stream_random_bp_i;
  logic        [31:0] s_stream_lfsr_q;
  logic               s_wr_gap_random_i;
  logic        [31:0] s_wr_gap_lfsr;
  // stalled-payload observation
  logic               s_aw_stalled_q;
  logic        [31:0] s_awaddr_stalled_q;
  logic        [ 7:0] s_awlen_stalled_q;
  logic               s_w_stalled_q;
  logic        [63:0] s_wdata_stalled_q;
  logic        [ 7:0] s_wstrb_stalled_q;
  logic               s_wlast_stalled_q;
  logic               s_ar_stalled_q;
  logic        [31:0] s_araddr_stalled_q;
  logic        [ 7:0] s_arlen_stalled_q;
  logic        [ 2:0] s_arsize_stalled_q;
  logic               s_rd_stream_stalled_q;
  logic        [63:0] s_rd_data_stalled_q;
  logic        [ 7:0] s_rd_keep_stalled_q;
  logic               s_rd_last_stalled_q;
  logic               s_clear_q;
  // counters, coverage and bookkeeping
  int unsigned        s_ar_count;
  int unsigned        s_aw_count;
  int unsigned        s_rd_outstanding_q;
  int unsigned        s_wr_outstanding_q;
  int unsigned        s_done_count_q;
  logic               s_done_pending_q;
  logic               s_done_clear_i;
  logic               s_saw_arlen_0_q;
  logic               s_saw_arlen_15_q;
  logic               s_saw_awlen_0_q;
  logic               s_saw_awlen_15_q;
  logic               s_saw_arsize_0_q;
  logic               s_saw_arsize_1_q;
  logic               s_saw_arsize_2_q;
  logic               s_saw_4k_split_q;
  logic               s_overlap_seen_q;
  string              s_phase;
  logic               s_phase_reset_i;
  int unsigned        s_phase_cycles_q;
  logic               s_progress;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) npu_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );

  npu_dma u_dut (
      .clk_hp_i          (clk_hp_i),
      .rst_hp_n_i        (rst_hp_n_i),
      .clear_i           (clear_i),
      .block_new_i       (block_new_i),
      .pause_ack_o       (pause_ack_o),
      .read_req_valid_i  (read_req_valid_i),
      .read_req_ready_o  (read_req_ready_o),
      .read_addr_i       (read_addr_i),
      .read_bytes_i      (read_bytes_i),
      .read_data_valid_o (read_data_valid_o),
      .read_data_ready_i (read_data_ready_i),
      .read_data_o       (read_data_o),
      .read_keep_o       (read_keep_o),
      .read_last_o       (read_last_o),
      .write_req_valid_i (write_req_valid_i),
      .write_req_ready_o (write_req_ready_o),
      .write_addr_i      (write_addr_i),
      .write_bytes_i     (write_bytes_i),
      .write_data_valid_i(write_data_valid_i),
      .write_data_ready_o(write_data_ready_o),
      .write_data_i      (write_data_i),
      .write_keep_i      (write_keep_i),
      .write_last_i      (write_last_i),
      .write_done_o      (write_done_o),
      .busy_o            (busy_o),
      .read_busy_o       (read_busy_o),
      .write_busy_o      (write_busy_o),
      .read_bytes_o      (read_bytes_o),
      .write_bytes_o     (write_bytes_o),
      .stall_cycles_o    (stall_cycles_o),
      .fault_o           (fault_o),
      .fault_code_o      (fault_code_o),
      .fault_addr_o      (fault_addr_o),
      .fault_resp_o      (fault_resp_o),
      .read_cmd_err_o    (read_cmd_err_o),
      .write_cmd_err_o   (write_cmd_err_o),
      .axi4              (npu_axi4)
  );

  always #5 clk_hp_i = ~clk_hp_i;

  function automatic logic [7:0] memory_byte(input logic [31:0] address_i);
    if ((address_i >= SramBase) && (address_i < (SramBase + MemoryBytes))) begin
      return s_memory[address_i-SramBase];
    end
    return 8'd0;
  endfunction

  function automatic logic [63:0] memory_word(input logic [31:0] address_i);
    logic [63:0] data;
    logic [31:0] aligned_address;
    begin
      data            = '0;
      aligned_address = {address_i[31:3], 3'b000};
      for (int unsigned lane = 0; lane < 8; lane++) begin
        data[lane*8+:8] = memory_byte(aligned_address + lane);
      end
      return data;
    end
  endfunction

  function automatic logic [31:0] next_delay_lfsr(input logic [31:0] value_i);
    return {value_i[30:0], value_i[31] ^ value_i[21] ^ value_i[1] ^ value_i[0]};
  endfunction

  function automatic logic [31:0] lcg_next(input logic [31:0] value_i);
    return (value_i * 32'd1664525) + 32'd1013904223;
  endfunction

  function automatic logic [7:0] pat_byte(input logic [31:0] address_i, input logic [31:0] seed_i);
    return address_i[7:0] ^ address_i[15:8] ^ address_i[23:16] ^ seed_i[7:0] ^ seed_i[15:8];
  endfunction

  function automatic logic [3:0] count_ones8(input logic [7:0] value_i);
    logic [3:0] count;
    begin
      count = 4'd0;
      for (int unsigned lane = 0; lane < 8; lane++) begin
        count = count + {3'd0, value_i[lane]};
      end
      return count;
    end
  endfunction

  // Expected read-stream keep mask for the beat at beat_addr_i: full 64-bit
  // lanes in the bulk, largest naturally aligned narrow window at the edges.
  function automatic logic [7:0] tb_beat_keep(input logic [31:0] beat_addr_i,
                                              input logic [31:0] remaining_i);
    logic [3:0] bytes;
    logic [3:0] to_align;
    begin
      to_align = 4'd8 - {1'b0, beat_addr_i[2:0]};
      bytes    = 4'd1;
      if ((beat_addr_i[2:0] == 3'd0) && (remaining_i >= 32'd8)) begin
        bytes = 4'd8;
      end else if ((beat_addr_i[1:0] == 2'd0) && (to_align >= 4'd4) && (remaining_i >= 32'd4)) begin
        bytes = 4'd4;
      end else if ((beat_addr_i[0] == 1'b0) && (to_align >= 4'd2) && (remaining_i >= 32'd2)) begin
        bytes = 4'd2;
      end
      return (8'hff >> (4'd8 - bytes)) << beat_addr_i[2:0];
    end
  endfunction

  function automatic logic [7:0] allowed_mask(
      input logic [31:0] beat_addr_i, input logic [31:0] seg_start_i, input logic [31:0] seg_end_i);
    logic [7:0] mask;
    begin
      mask = 8'd0;
      for (int unsigned lane = 0; lane < 8; lane++) begin
        if (((beat_addr_i + lane) >= seg_start_i) && ((beat_addr_i + lane) < seg_end_i)) begin
          mask[lane] = 1'b1;
        end
      end
      return mask;
    end
  endfunction

  function automatic logic [1:0] bfm_read_resp(input logic [31:0] beat_addr_i);
    if (s_read_err_en_i && (beat_addr_i == s_read_err_addr_i)) begin
      return s_read_err_code_i;
    end
    return 2'b00;
  endfunction

  logic [31:0] s_rd_beat_addr;
  logic [31:0] s_rd_beat_remaining;
  logic [ 7:0] s_rd_expect_keep;
  logic [32:0] s_ar_burst_end;
  logic [32:0] s_aw_burst_end;

  assign s_rd_beat_addr = s_rd_seg_addr_i + s_rd_off_q;
  assign s_rd_beat_remaining = s_rd_seg_bytes_i - s_rd_off_q;
  assign s_rd_expect_keep = tb_beat_keep(s_rd_beat_addr, s_rd_beat_remaining);
  assign s_ar_burst_end      = {1'b0, npu_axi4.araddr} +
                               (({25'd0, npu_axi4.arlen} + 33'd1) << npu_axi4.arsize);
  assign s_aw_burst_end = {1'b0, npu_axi4.awaddr} + (({25'd0, npu_axi4.awlen} + 33'd1) << 3);

  assign s_progress = (npu_axi4.arvalid && npu_axi4.arready) ||
                      (npu_axi4.rvalid && npu_axi4.rready) ||
                      (npu_axi4.awvalid && npu_axi4.awready) ||
                      (npu_axi4.wvalid && npu_axi4.wready) ||
                      (npu_axi4.bvalid && npu_axi4.bready) ||
                      (read_data_valid_o && read_data_ready_i) ||
                      (write_data_valid_i && write_data_ready_o) ||
                      (read_req_valid_i && read_req_ready_o) ||
                      (write_req_valid_i && write_req_ready_o) || write_done_o;

  // Each channel chooses a separately seeded 0..3 cycle delay.  Once chosen,
  // a request or response stays eligible until its handshake, so the BFM has
  // bounded progress and cannot hide a DUT deadlock behind random starvation.
  always_ff @(posedge clk_hp_i or negedge rst_hp_n_i) begin
    if (!rst_hp_n_i) begin
      s_ar_delay_lfsr_q    <= 32'h1f12_3bb5;
      s_aw_delay_lfsr_q    <= 32'h2c34_4cc7;
      s_w_delay_lfsr_q     <= 32'h3d56_5dd9;
      s_r_delay_lfsr_q     <= 32'h4e78_6eeb;
      s_b_delay_lfsr_q     <= 32'h5f9a_7ffd;
      s_ar_delay_q         <= '0;
      s_aw_delay_q         <= '0;
      s_w_delay_q          <= '0;
      s_r_delay_q          <= '0;
      s_b_delay_q          <= '0;
      s_ar_delay_pending_q <= 1'b0;
      s_aw_delay_pending_q <= 1'b0;
      s_w_delay_pending_q  <= 1'b0;
      s_r_delay_pending_q  <= 1'b0;
      s_b_delay_pending_q  <= 1'b0;
      s_ar_delay_modes_q   <= '0;
      s_aw_delay_modes_q   <= '0;
      s_w_delay_modes_q    <= '0;
      s_r_delay_modes_q    <= '0;
      s_b_delay_modes_q    <= '0;
    end else begin
      if (s_random_delay_coverage_clear_i) begin
        s_ar_delay_modes_q <= '0;
        s_aw_delay_modes_q <= '0;
        s_w_delay_modes_q  <= '0;
        s_r_delay_modes_q  <= '0;
        s_b_delay_modes_q  <= '0;
      end
      if (s_random_delay_reseed_i) begin
        s_ar_delay_lfsr_q    <= s_random_delay_seed_i ^ 32'h1f12_3bb5;
        s_aw_delay_lfsr_q    <= s_random_delay_seed_i ^ 32'h2c34_4cc7;
        s_w_delay_lfsr_q     <= s_random_delay_seed_i ^ 32'h3d56_5dd9;
        s_r_delay_lfsr_q     <= s_random_delay_seed_i ^ 32'h4e78_6eeb;
        s_b_delay_lfsr_q     <= s_random_delay_seed_i ^ 32'h5f9a_7ffd;
        s_ar_delay_q         <= '0;
        s_aw_delay_q         <= '0;
        s_w_delay_q          <= '0;
        s_r_delay_q          <= '0;
        s_b_delay_q          <= '0;
        s_ar_delay_pending_q <= 1'b0;
        s_aw_delay_pending_q <= 1'b0;
        s_w_delay_pending_q  <= 1'b0;
        s_r_delay_pending_q  <= 1'b0;
        s_b_delay_pending_q  <= 1'b0;
      end else if (!s_random_delays_i || clear_i) begin
        s_ar_delay_q         <= '0;
        s_aw_delay_q         <= '0;
        s_w_delay_q          <= '0;
        s_r_delay_q          <= '0;
        s_b_delay_q          <= '0;
        s_ar_delay_pending_q <= 1'b0;
        s_aw_delay_pending_q <= 1'b0;
        s_w_delay_pending_q  <= 1'b0;
        s_r_delay_pending_q  <= 1'b0;
        s_b_delay_pending_q  <= 1'b0;
      end else begin
        if (!npu_axi4.arvalid || s_rvalid_q || s_residual_r_valid_q) begin
          s_ar_delay_q         <= '0;
          s_ar_delay_pending_q <= 1'b0;
        end else if (!s_ar_delay_pending_q) begin
          s_ar_delay_q                               <= s_ar_delay_lfsr_q[1:0];
          s_ar_delay_pending_q                       <= 1'b1;
          s_ar_delay_modes_q[s_ar_delay_lfsr_q[1:0]] <= 1'b1;
          s_ar_delay_lfsr_q                          <= next_delay_lfsr(s_ar_delay_lfsr_q);
        end else if (s_ar_delay_q != 2'd0) begin
          s_ar_delay_q <= s_ar_delay_q - 1'b1;
        end else if (npu_axi4.arready) begin
          s_ar_delay_pending_q <= 1'b0;
        end

        if (!npu_axi4.awvalid || s_aw_pending_q || s_bvalid_q || s_residual_b_valid_q) begin
          s_aw_delay_q         <= '0;
          s_aw_delay_pending_q <= 1'b0;
        end else if (!s_aw_delay_pending_q) begin
          s_aw_delay_q                               <= s_aw_delay_lfsr_q[1:0];
          s_aw_delay_pending_q                       <= 1'b1;
          s_aw_delay_modes_q[s_aw_delay_lfsr_q[1:0]] <= 1'b1;
          s_aw_delay_lfsr_q                          <= next_delay_lfsr(s_aw_delay_lfsr_q);
        end else if (s_aw_delay_q != 2'd0) begin
          s_aw_delay_q <= s_aw_delay_q - 1'b1;
        end else if (npu_axi4.awready) begin
          s_aw_delay_pending_q <= 1'b0;
        end

        if (!npu_axi4.wvalid || !s_aw_pending_q || s_bvalid_q || s_residual_b_valid_q) begin
          s_w_delay_q         <= '0;
          s_w_delay_pending_q <= 1'b0;
        end else if (!s_w_delay_pending_q) begin
          s_w_delay_q                              <= s_w_delay_lfsr_q[1:0];
          s_w_delay_pending_q                      <= 1'b1;
          s_w_delay_modes_q[s_w_delay_lfsr_q[1:0]] <= 1'b1;
          s_w_delay_lfsr_q                         <= next_delay_lfsr(s_w_delay_lfsr_q);
        end else if (s_w_delay_q != 2'd0) begin
          s_w_delay_q <= s_w_delay_q - 1'b1;
        end else if (npu_axi4.wready) begin
          s_w_delay_pending_q <= 1'b0;
        end

        if (npu_axi4.arvalid && npu_axi4.arready) begin
          s_r_delay_q                              <= s_r_delay_lfsr_q[1:0];
          s_r_delay_pending_q                      <= 1'b1;
          s_r_delay_modes_q[s_r_delay_lfsr_q[1:0]] <= 1'b1;
          s_r_delay_lfsr_q                         <= next_delay_lfsr(s_r_delay_lfsr_q);
        end else if (s_rvalid_q && npu_axi4.rvalid && npu_axi4.rready) begin
          if (s_rbeats_q == 9'd1) begin
            s_r_delay_pending_q <= 1'b0;
          end else begin
            s_r_delay_q                              <= s_r_delay_lfsr_q[1:0];
            s_r_delay_pending_q                      <= 1'b1;
            s_r_delay_modes_q[s_r_delay_lfsr_q[1:0]] <= 1'b1;
            s_r_delay_lfsr_q                         <= next_delay_lfsr(s_r_delay_lfsr_q);
          end
        end else if (s_rvalid_q && s_r_delay_pending_q) begin
          if (s_r_delay_q == 2'd0) begin
            s_r_delay_pending_q <= 1'b0;
          end else begin
            s_r_delay_q <= s_r_delay_q - 1'b1;
          end
        end else if (!s_rvalid_q) begin
          s_r_delay_pending_q <= 1'b0;
        end

        if (npu_axi4.wvalid && npu_axi4.wready && (s_wbeats_q == 9'd1)) begin
          s_b_delay_q                              <= s_b_delay_lfsr_q[1:0];
          s_b_delay_pending_q                      <= 1'b1;
          s_b_delay_modes_q[s_b_delay_lfsr_q[1:0]] <= 1'b1;
          s_b_delay_lfsr_q                         <= next_delay_lfsr(s_b_delay_lfsr_q);
        end else if (s_bvalid_q && npu_axi4.bvalid && npu_axi4.bready) begin
          s_b_delay_pending_q <= 1'b0;
        end else if (s_bvalid_q && s_b_delay_pending_q) begin
          if (s_b_delay_q == 2'd0) begin
            s_b_delay_pending_q <= 1'b0;
          end else begin
            s_b_delay_q <= s_b_delay_q - 1'b1;
          end
        end else if (!s_bvalid_q) begin
          s_b_delay_pending_q <= 1'b0;
        end
      end
    end
  end

  assign npu_axi4.arready = !s_hold_ar_i && !s_rvalid_q && !s_residual_r_valid_q &&
                            (!s_random_delays_i ||
                             (s_ar_delay_pending_q && (s_ar_delay_q == 2'd0)));
  assign npu_axi4.rid = s_residual_r_valid_q ? 3'd0 : s_rid_q;
  assign npu_axi4.rdata = s_rdata_q;
  assign npu_axi4.rresp = s_residual_r_valid_q ? 2'b00 : s_rresp_q;
  assign npu_axi4.rlast = s_residual_r_valid_q ? 1'b1 :
                          (s_inject_bad_rlast_i ? 1'b0 :
                           (s_inject_early_rlast_i ? (s_rbeats_q == s_rburst_total_q) :
                            (s_rbeats_q == 9'd1)));
  assign npu_axi4.ruser = '0;
  assign npu_axi4.rvalid = !s_hold_r_i &&
                           ((s_rvalid_q && (!s_random_delays_i || !s_r_delay_pending_q)) ||
                            s_residual_r_valid_q);
  assign npu_axi4.awready = !s_hold_aw_i && !s_aw_pending_q && !s_bvalid_q &&
                            !s_residual_b_valid_q &&
                            (!s_random_delays_i ||
                             (s_aw_delay_pending_q && (s_aw_delay_q == 2'd0)));
  assign npu_axi4.wready = !s_hold_w_i && s_aw_pending_q && !s_bvalid_q &&
                           !s_residual_b_valid_q &&
                           (!s_random_delays_i ||
                            (s_w_delay_pending_q && (s_w_delay_q == 2'd0)));
  assign npu_axi4.bid = s_residual_b_valid_q ? 3'd0 : s_bid_q;
  assign npu_axi4.bresp = s_residual_b_valid_q ? 2'b00 : s_bresp_q;
  assign npu_axi4.buser = '0;
  assign npu_axi4.bvalid = !s_hold_b_i &&
                           ((s_bvalid_q && (!s_random_delays_i || !s_b_delay_pending_q)) ||
                            s_residual_b_valid_q);

  // Memory BFM, inline protocol checkers and accepted-transfer accounting.
  always_ff @(posedge clk_hp_i or negedge rst_hp_n_i) begin
    if (!rst_hp_n_i) begin
      s_rvalid_q           <= 1'b0;
      s_rid_q              <= '0;
      s_rresp_q            <= 2'd0;
      s_raddr_q            <= '0;
      s_rdata_q            <= '0;
      s_rsize_q            <= '0;
      s_rbeats_q           <= '0;
      s_rburst_total_q     <= '0;
      s_residual_r_valid_q <= 1'b0;
      s_aw_pending_q       <= 1'b0;
      s_awbase_q           <= '0;
      s_awaddr_q           <= '0;
      s_wbeats_q           <= '0;
      s_bvalid_q           <= 1'b0;
      s_bid_q              <= '0;
      s_bresp_q            <= 2'd0;
      s_residual_b_valid_q <= 1'b0;
      s_ar_count           <= 0;
      s_aw_count           <= 0;
      s_rd_outstanding_q   <= 0;
      s_wr_outstanding_q   <= 0;
      s_done_count_q       <= 0;
      s_done_pending_q     <= 1'b0;
      s_saw_arlen_0_q      <= 1'b0;
      s_saw_arlen_15_q     <= 1'b0;
      s_saw_awlen_0_q      <= 1'b0;
      s_saw_awlen_15_q     <= 1'b0;
      s_saw_arsize_0_q     <= 1'b0;
      s_saw_arsize_1_q     <= 1'b0;
      s_saw_arsize_2_q     <= 1'b0;
      s_saw_4k_split_q     <= 1'b0;
      s_overlap_seen_q     <= 1'b0;
      s_ar_expect_q        <= '0;
      s_aw_expect_q        <= '0;
      s_wr_bytes_seen_q    <= '0;
    end else if (clear_i) begin
      // Model the coordinated fabric flush boundary: every queued target
      // side response is contained before the source can be rearmed.
      s_rvalid_q           <= 1'b0;
      s_rbeats_q           <= '0;
      s_residual_r_valid_q <= 1'b0;
      s_aw_pending_q       <= 1'b0;
      s_wbeats_q           <= '0;
      s_bvalid_q           <= 1'b0;
      s_residual_b_valid_q <= 1'b0;
      s_rd_outstanding_q   <= 0;
      s_wr_outstanding_q   <= 0;
    end else begin
      if (read_busy_o && write_busy_o) begin
        s_overlap_seen_q <= 1'b1;
      end
      if (write_done_o) begin
        s_done_count_q   <= s_done_count_q + 1;
        s_done_pending_q <= 1'b1;
      end
      if (s_done_clear_i) begin
        s_done_pending_q <= 1'b0;
      end
      if (s_wr_clear_i) begin
        s_wr_bytes_seen_q <= '0;
      end
      if (s_ar_expect_set_i) begin
        s_ar_expect_q <= s_ar_expect_addr_i;
      end
      if (s_aw_expect_set_i) begin
        s_aw_expect_q <= s_aw_expect_addr_i;
      end
      if (s_force_residual_r_i && !s_rvalid_q) begin
        s_residual_r_valid_q <= 1'b1;
        s_rdata_q            <= 64'h5a5a_a5a5_3c3c_c3c3;
      end else if (!s_force_residual_r_i && !s_hold_r_i) begin
        s_residual_r_valid_q <= 1'b0;
      end
      if (s_force_residual_b_i && !s_bvalid_q) begin
        s_residual_b_valid_q <= 1'b1;
      end else if (!s_force_residual_b_i && !s_hold_b_i) begin
        s_residual_b_valid_q <= 1'b0;
      end

      if (npu_axi4.arvalid && npu_axi4.arready) begin
        if (s_rd_outstanding_q != 0) begin
          $fatal(1, "NPU DMA issued a second outstanding read");
        end
        if ((npu_axi4.araddr & ((32'd1 << npu_axi4.arsize) - 32'd1)) != 32'd0) begin
          $fatal(1, "NPU DMA emitted an unaligned read transfer");
        end
        if ((npu_axi4.arsize != 3'd3) && (npu_axi4.arlen != 8'd0)) begin
          $fatal(1, "NPU DMA emitted a multi-beat narrow read burst");
        end
        if ({1'b0, npu_axi4.araddr[11:0]} +
            (({5'd0, npu_axi4.arlen} + 13'd1) << npu_axi4.arsize) > 13'd4096) begin
          $fatal(1, "NPU DMA read burst crossed a 4 KiB boundary");
        end
        if (s_ar_check_i) begin
          if (npu_axi4.araddr != s_ar_expect_q) begin
            $fatal(1, "NPU DMA read bursts are not contiguous: expected=%h actual=%h",
                   s_ar_expect_q, npu_axi4.araddr);
          end
          if (s_ar_burst_end > s_rd_seg_end_i) begin
            $fatal(1, "NPU DMA read overfetched its segment");
          end
          if ((s_ar_burst_end[11:0] == 12'd0) && (s_ar_burst_end < s_rd_seg_end_i)) begin
            s_saw_4k_split_q <= 1'b1;
          end
        end
        s_ar_expect_q      <= s_ar_burst_end[31:0];
        s_rvalid_q         <= 1'b1;
        s_rid_q            <= s_inject_bad_rid_i ? 3'd1 : 3'd0;
        s_rresp_q          <= bfm_read_resp(npu_axi4.araddr);
        s_raddr_q          <= npu_axi4.araddr;
        s_rdata_q          <= memory_word(npu_axi4.araddr);
        s_rsize_q          <= npu_axi4.arsize;
        s_rbeats_q         <= {1'b0, npu_axi4.arlen} + 1'b1;
        s_rburst_total_q   <= {1'b0, npu_axi4.arlen} + 1'b1;
        s_ar_count         <= s_ar_count + 1;
        s_rd_outstanding_q <= s_rd_outstanding_q + 1;
        if (npu_axi4.arlen == 8'd0) begin
          s_saw_arlen_0_q <= 1'b1;
        end
        if (npu_axi4.arlen == 8'd15) begin
          s_saw_arlen_15_q <= 1'b1;
        end
        if (npu_axi4.arsize == 3'd0) begin
          s_saw_arsize_0_q <= 1'b1;
        end
        if (npu_axi4.arsize == 3'd1) begin
          s_saw_arsize_1_q <= 1'b1;
        end
        if (npu_axi4.arsize == 3'd2) begin
          s_saw_arsize_2_q <= 1'b1;
        end
      end else if (s_rvalid_q && npu_axi4.rvalid && npu_axi4.rready) begin
        if (s_rbeats_q == 9'd1) begin
          s_rvalid_q         <= 1'b0;
          s_rbeats_q         <= '0;
          s_rd_outstanding_q <= s_rd_outstanding_q - 1;
        end else begin
          s_raddr_q  <= s_raddr_q + (32'd1 << s_rsize_q);
          s_rdata_q  <= memory_word(s_raddr_q + (32'd1 << s_rsize_q));
          s_rresp_q  <= bfm_read_resp(s_raddr_q + (32'd1 << s_rsize_q));
          s_rbeats_q <= s_rbeats_q - 1'b1;
        end
      end

      if (npu_axi4.awvalid && npu_axi4.awready) begin
        if (s_wr_outstanding_q != 0) begin
          $fatal(1, "NPU DMA issued a second outstanding write");
        end
        if (npu_axi4.awaddr[2:0] != 3'd0) begin
          $fatal(1, "NPU DMA emitted an unaligned AXI64 write address");
        end
        if ({1'b0, npu_axi4.awaddr[11:0]} +
            (({5'd0, npu_axi4.awlen} + 13'd1) << 3) > 13'd4096) begin
          $fatal(1, "NPU DMA write burst crossed a 4 KiB boundary");
        end
        if (s_aw_check_i) begin
          if (npu_axi4.awaddr != s_aw_expect_q) begin
            $fatal(1, "NPU DMA write bursts are not contiguous: expected=%h actual=%h",
                   s_aw_expect_q, npu_axi4.awaddr);
          end
          if (s_wr_active_i && (s_aw_burst_end > s_wr_end_aligned_i)) begin
            $fatal(1, "NPU DMA write burst overfetched its segment");
          end
          if ((s_aw_burst_end[11:0] == 12'd0) && (s_aw_burst_end < s_wr_end_aligned_i)) begin
            s_saw_4k_split_q <= 1'b1;
          end
        end
        s_aw_expect_q      <= s_aw_burst_end[31:0];
        s_aw_pending_q     <= 1'b1;
        s_awbase_q         <= npu_axi4.awaddr;
        s_awaddr_q         <= npu_axi4.awaddr;
        s_wbeats_q         <= {1'b0, npu_axi4.awlen} + 1'b1;
        s_aw_count         <= s_aw_count + 1;
        s_wr_outstanding_q <= s_wr_outstanding_q + 1;
        if (npu_axi4.awlen == 8'd0) begin
          s_saw_awlen_0_q <= 1'b1;
        end
        if (npu_axi4.awlen == 8'd15) begin
          s_saw_awlen_15_q <= 1'b1;
        end
      end
      if (npu_axi4.wvalid && npu_axi4.wready) begin
        if (!s_aw_pending_q) begin
          $fatal(1, "NPU DMA issued W without an accepted AW");
        end
        if (npu_axi4.wlast != (s_wbeats_q == 9'd1)) begin
          $fatal(1, "NPU DMA emitted an incorrect WLAST sequence");
        end
        if (npu_axi4.wstrb == 8'd0) begin
          $fatal(1, "NPU DMA emitted a zero-strobe write");
        end
        if (s_wr_active_i && (npu_axi4.wstrb != allowed_mask(
                s_awaddr_q, s_wr_seg_start_i, s_wr_seg_end_i
            ))) begin
          $fatal(1, "NPU DMA WSTRB is not exactly the addressed segment window");
        end
        for (int unsigned lane = 0; lane < 8; lane++) begin
          if (npu_axi4.wstrb[lane]) begin
            if (((s_awaddr_q + lane) < SramBase) ||
                ((s_awaddr_q + lane) >= (SramBase + MemoryBytes))) begin
              $fatal(1, "NPU DMA write escaped the memory BFM");
            end
            s_memory[(s_awaddr_q+lane)-SramBase] <= npu_axi4.wdata[lane*8+:8];
          end
        end
        if (s_wr_active_i) begin
          s_wr_bytes_seen_q <= s_wr_bytes_seen_q + {28'd0, count_ones8(npu_axi4.wstrb)};
        end
        if (s_wbeats_q == 9'd1) begin
          s_aw_pending_q <= 1'b0;
          s_wbeats_q <= '0;
          s_bvalid_q <= 1'b1;
          s_bid_q <= s_inject_bad_bid_i ? 3'd1 : 3'd0;
          s_bresp_q      <= (s_write_err_en_i && (s_awbase_q == s_write_err_addr_i)) ?
                            s_write_err_code_i : 2'd0;
        end else begin
          s_awaddr_q <= s_awaddr_q + 32'd8;
          s_wbeats_q <= s_wbeats_q - 1'b1;
        end
      end else if (s_bvalid_q && npu_axi4.bvalid && npu_axi4.bready) begin
        s_bvalid_q         <= 1'b0;
        s_wr_outstanding_q <= s_wr_outstanding_q - 1;
      end
    end
  end

  // Stalled-payload stability and attribute contract checkers.
  always_ff @(posedge clk_hp_i or negedge rst_hp_n_i) begin
    if (!rst_hp_n_i) begin
      s_aw_stalled_q        <= 1'b0;
      s_awaddr_stalled_q    <= '0;
      s_awlen_stalled_q     <= '0;
      s_w_stalled_q         <= 1'b0;
      s_wdata_stalled_q     <= '0;
      s_wstrb_stalled_q     <= '0;
      s_wlast_stalled_q     <= 1'b0;
      s_ar_stalled_q        <= 1'b0;
      s_araddr_stalled_q    <= '0;
      s_arlen_stalled_q     <= '0;
      s_arsize_stalled_q    <= '0;
      s_rd_stream_stalled_q <= 1'b0;
      s_rd_data_stalled_q   <= '0;
      s_rd_keep_stalled_q   <= '0;
      s_rd_last_stalled_q   <= 1'b0;
      s_clear_q             <= 1'b0;
    end else begin
      s_clear_q <= clear_i;
      if (s_aw_stalled_q && !s_clear_q && !clear_i) begin
        if (!npu_axi4.awvalid || (npu_axi4.awaddr != s_awaddr_stalled_q) ||
            (npu_axi4.awlen != s_awlen_stalled_q)) begin
          $fatal(1, "NPU DMA AW payload changed or was withdrawn while stalled");
        end
      end
      if (s_w_stalled_q && !s_clear_q && !clear_i) begin
        if (!npu_axi4.wvalid || (npu_axi4.wdata != s_wdata_stalled_q) ||
            (npu_axi4.wstrb != s_wstrb_stalled_q) || (npu_axi4.wlast != s_wlast_stalled_q)) begin
          $fatal(1, "NPU DMA W payload changed or was withdrawn while stalled");
        end
      end
      if (s_ar_stalled_q && !s_clear_q && !clear_i) begin
        if (!npu_axi4.arvalid || (npu_axi4.araddr != s_araddr_stalled_q) ||
            (npu_axi4.arlen != s_arlen_stalled_q) || (npu_axi4.arsize != s_arsize_stalled_q)) begin
          $fatal(1, "NPU DMA AR payload changed or was withdrawn while stalled");
        end
      end
      if (s_rd_stream_stalled_q && !s_clear_q && !clear_i) begin
        if (!read_data_valid_o || (read_data_o != s_rd_data_stalled_q) ||
            (read_keep_o != s_rd_keep_stalled_q) || (read_last_o != s_rd_last_stalled_q)) begin
          $fatal(1, "NPU DMA read stream payload changed or was withdrawn while stalled");
        end
      end
      if (npu_axi4.awvalid) begin
        if ((npu_axi4.awid != 3'd0) || (npu_axi4.awlen > 8'd15) ||
            (npu_axi4.awsize != 3'd3) || (npu_axi4.awburst != 2'd1) ||
            (npu_axi4.awlock != 1'b0) || (npu_axi4.awcache != 4'd0) ||
            (npu_axi4.awprot != 3'd0) || (npu_axi4.awqos != 4'd0) ||
            (npu_axi4.awregion != 4'd0) || (npu_axi4.awuser != 1'b0)) begin
          $fatal(1, "NPU DMA AW attributes violate the AXI contract");
        end
      end
      if (npu_axi4.arvalid) begin
        if ((npu_axi4.arid != 3'd0) || (npu_axi4.arlen > 8'd15) ||
            (npu_axi4.arburst != 2'd1) || (npu_axi4.arlock != 1'b0) ||
            (npu_axi4.arcache != 4'd0) || (npu_axi4.arprot != 3'd0) ||
            (npu_axi4.arqos != 4'd0) || (npu_axi4.arregion != 4'd0) ||
            (npu_axi4.aruser != 1'b0)) begin
          $fatal(1, "NPU DMA AR attributes violate the AXI contract");
        end
      end
      if (npu_axi4.wvalid) begin
        if ((npu_axi4.wstrb == 8'd0) || (npu_axi4.wuser != 1'b0)) begin
          $fatal(1, "NPU DMA W attributes violate the AXI contract");
        end
      end
      s_aw_stalled_q        <= npu_axi4.awvalid && !npu_axi4.awready;
      s_awaddr_stalled_q    <= npu_axi4.awaddr;
      s_awlen_stalled_q     <= npu_axi4.awlen;
      s_w_stalled_q         <= npu_axi4.wvalid && !npu_axi4.wready;
      s_wdata_stalled_q     <= npu_axi4.wdata;
      s_wstrb_stalled_q     <= npu_axi4.wstrb;
      s_wlast_stalled_q     <= npu_axi4.wlast;
      s_ar_stalled_q        <= npu_axi4.arvalid && !npu_axi4.arready;
      s_araddr_stalled_q    <= npu_axi4.araddr;
      s_arlen_stalled_q     <= npu_axi4.arlen;
      s_arsize_stalled_q    <= npu_axi4.arsize;
      s_rd_stream_stalled_q <= read_data_valid_o && !read_data_ready_i;
      s_rd_data_stalled_q   <= read_data_o;
      s_rd_keep_stalled_q   <= read_keep_o;
      s_rd_last_stalled_q   <= read_last_o;
    end
  end

  // Read stream byte-accurate checker, stream backpressure and watchdog.
  always_ff @(posedge clk_hp_i or negedge rst_hp_n_i) begin
    if (!rst_hp_n_i) begin
      s_rd_off_q        <= '0;
      s_rd_done_q       <= 1'b0;
      s_stream_lfsr_q   <= 32'h68b1_5db3;
      read_data_ready_i <= 1'b1;
      s_phase_cycles_q  <= 0;
    end else if (clear_i) begin
      s_rd_off_q       <= '0;
      s_rd_done_q      <= 1'b0;
      s_phase_cycles_q <= 0;
    end else begin
      if (s_rd_done_clear_i) begin
        s_rd_done_q <= 1'b0;
        s_rd_off_q  <= '0;
      end
      if (read_data_valid_o && read_data_ready_i) begin
        if (!s_rd_active_i) begin
          $fatal(1, "NPU DMA emitted read stream data with no active segment");
        end
        if (read_keep_o != s_rd_expect_keep) begin
          $fatal(1, "NPU DMA read stream keep mismatch at offset %h: expected=%h actual=%h",
                 s_rd_off_q, s_rd_expect_keep, read_keep_o);
        end
        if (read_last_o != ((s_rd_off_q + {28'd0, count_ones8(
                s_rd_expect_keep
            )}) == s_rd_seg_bytes_i)) begin
          $fatal(1, "NPU DMA read stream last flag mismatch at offset %h", s_rd_off_q);
        end
        for (int unsigned lane = 0; lane < 8; lane++) begin
          if (s_rd_expect_keep[lane] && (read_data_o[lane*8+:8] != memory_byte(
                  {s_rd_beat_addr[31:3], 3'b000} + lane
              ))) begin
            $fatal(1, "NPU DMA read stream data mismatch at offset %h lane %0d", s_rd_off_q, lane);
          end
        end
        s_rd_off_q <= s_rd_off_q + {28'd0, count_ones8(s_rd_expect_keep)};
        if (read_last_o) begin
          s_rd_done_q <= 1'b1;
        end
      end
      if (s_stream_random_bp_i) begin
        s_stream_lfsr_q   <= next_delay_lfsr(s_stream_lfsr_q);
        read_data_ready_i <= s_stream_lfsr_q[1:0] != 2'b11;
      end else begin
        read_data_ready_i <= 1'b1;
      end
      if (s_progress || s_phase_reset_i) begin
        s_phase_cycles_q <= 0;
      end else begin
        s_phase_cycles_q <= s_phase_cycles_q + 1;
        if (s_phase_cycles_q >= PhaseTimeout) begin
          $display("NPU DMA phase timeout dump: phase=%s busy=%b/%b/%b fault=%b code=%h", s_phase,
                   busy_o, read_busy_o, write_busy_o, fault_o, fault_code_o);
          $display(
              "  arvalid=%b rvalid=%b rready=%b awvalid=%b wvalid=%b wready=%b bvalid=%b bready=%b",
              npu_axi4.arvalid, npu_axi4.rvalid, npu_axi4.rready, npu_axi4.awvalid,
              npu_axi4.wvalid, npu_axi4.wready, npu_axi4.bvalid, npu_axi4.bready);
          $display(
              "  bfm: rvalid=%b rbeats=%h aw_pending=%b wbeats=%h bvalid=%b ar=%0d aw=%0d rd_off=%h",
              s_rvalid_q, s_rbeats_q, s_aw_pending_q, s_wbeats_q, s_bvalid_q, s_ar_count,
              s_aw_count, s_rd_off_q);
          $display("  counters: read=%h write=%h stall=%h pause=%b/%b", read_bytes_o,
                   write_bytes_o, stall_cycles_o, block_new_i, pause_ack_o);
          $fatal(1, "NPU DMA phase timed out: %s", s_phase);
        end
      end
    end
  end

  task automatic idle_cycles(input int unsigned cycles_i);
    begin
      repeat (cycles_i) @(posedge clk_hp_i);
    end
  endtask

  task automatic set_phase(input string name_i);
    begin
      @(negedge clk_hp_i);
      s_phase         = name_i;
      s_phase_reset_i = 1'b1;
      @(posedge clk_hp_i);
      @(negedge clk_hp_i);
      s_phase_reset_i = 1'b0;
    end
  endtask

  task automatic clear_memory(input logic [7:0] value_i);
    begin
      for (int unsigned index = 0; index < MemoryBytes; index++) begin
        s_memory[index] = value_i;
      end
    end
  endtask

  task automatic clear_window(input logic [31:0] address_i, input logic [31:0] bytes_i,
                              input logic [7:0] value_i);
    begin
      if ((address_i < SramBase) || ((address_i + bytes_i) > (SramBase + MemoryBytes))) begin
        $fatal(1, "NPU DMA test window escaped the memory BFM");
      end
      for (int unsigned index = 0; index < bytes_i; index++) begin
        s_memory[(address_i+index)-SramBase] = value_i;
      end
    end
  endtask

  task automatic fill_pattern(input logic [31:0] address_i, input logic [31:0] bytes_i,
                              input logic [31:0] seed_i);
    begin
      clear_window(address_i, bytes_i, 8'h00);
      for (int unsigned index = 0; index < bytes_i; index++) begin
        s_memory[(address_i+index)-SramBase] = pat_byte(address_i + index, seed_i);
      end
    end
  endtask

  task automatic verify_region(input logic [31:0] address_i, input logic [31:0] bytes_i,
                               input logic [31:0] seed_i, input logic [7:0] guard_i);
    begin
      if (memory_byte(address_i - 1'b1) != guard_i) begin
        $fatal(1, "NPU DMA changed the leading guard byte at %h", address_i);
      end
      for (int unsigned index = 0; index < bytes_i; index++) begin
        if (memory_byte(address_i + index) != pat_byte(address_i + index, seed_i)) begin
          $fatal(1, "NPU DMA memory mismatch at %h: expected=%h actual=%h", address_i + index,
                 pat_byte(address_i + index, seed_i), memory_byte(address_i + index));
        end
      end
      if (memory_byte(address_i + bytes_i) != guard_i) begin
        $fatal(1, "NPU DMA changed the trailing guard byte at %h", address_i + bytes_i);
      end
    end
  endtask

  task automatic pulse_clear;
    begin
      @(negedge clk_hp_i);
      // Residual epoch beats are withdrawn only under the flush umbrella;
      // withdrawing a stalled VALID outside clear_i would be illegal.
      clear_i              = 1'b1;
      s_force_residual_r_i = 1'b0;
      s_force_residual_b_i = 1'b0;
      repeat (2) @(posedge clk_hp_i);
      @(negedge clk_hp_i);
      clear_i = 1'b0;
      idle_cycles(2);
    end
  endtask

  task automatic setup_read_expect(input logic [31:0] address_i, input logic [31:0] bytes_i);
    begin
      @(negedge clk_hp_i);
      s_rd_seg_addr_i    = address_i;
      s_rd_seg_bytes_i   = bytes_i;
      s_rd_seg_end_i     = {1'b0, address_i} + {1'b0, bytes_i};
      s_rd_active_i      = 1'b1;
      s_rd_done_clear_i  = 1'b1;
      s_ar_check_i       = 1'b1;
      s_ar_expect_set_i  = 1'b1;
      s_ar_expect_addr_i = address_i;
      @(posedge clk_hp_i);
      @(negedge clk_hp_i);
      s_rd_done_clear_i = 1'b0;
      s_ar_expect_set_i = 1'b0;
    end
  endtask

  task automatic finish_read_expect(input logic [31:0] address_i, input logic [31:0] bytes_i);
    begin
      if (s_ar_expect_q != (address_i + bytes_i)) begin
        $fatal(1, "NPU DMA read burst coverage mismatch: end=%h expected=%h", s_ar_expect_q,
               address_i + bytes_i);
      end
      @(negedge clk_hp_i);
      s_rd_active_i = 1'b0;
      s_ar_check_i  = 1'b0;
    end
  endtask

  task automatic setup_write_expect(input logic [31:0] address_i, input logic [31:0] bytes_i);
    begin
      @(negedge clk_hp_i);
      s_wr_seg_start_i   = address_i;
      s_wr_seg_end_i     = address_i + bytes_i;
      s_wr_end_aligned_i = (({1'b0, address_i} + {1'b0, bytes_i} + 33'd7) >> 3) << 3;
      s_wr_active_i      = 1'b1;
      s_wr_clear_i       = 1'b1;
      s_done_clear_i     = 1'b1;
      s_aw_check_i       = 1'b1;
      s_aw_expect_set_i  = 1'b1;
      s_aw_expect_addr_i = {address_i[31:3], 3'b000};
      @(posedge clk_hp_i);
      @(negedge clk_hp_i);
      s_wr_clear_i      = 1'b0;
      s_aw_expect_set_i = 1'b0;
      idle_cycles(1);
      s_done_clear_i = 1'b0;
    end
  endtask

  task automatic finish_write_expect(input logic [31:0] address_i, input logic [31:0] bytes_i);
    logic [31:0] total_beats;
    begin
      total_beats = ({29'd0, address_i[2:0]} + bytes_i + 32'd7) >> 3;
      if (s_wr_bytes_seen_q != bytes_i) begin
        $fatal(1, "NPU DMA write strobe coverage mismatch: seen=%h expected=%h", s_wr_bytes_seen_q,
               bytes_i);
      end
      if (s_aw_expect_q != ({address_i[31:3], 3'b000} + {total_beats, 3'b000})) begin
        $fatal(1, "NPU DMA write burst coverage mismatch: end=%h", s_aw_expect_q);
      end
      @(negedge clk_hp_i);
      s_wr_active_i = 1'b0;
      s_aw_check_i  = 1'b0;
    end
  endtask

  // Handshake tasks sample ready mid-cycle (negedge + settle), i.e. with the
  // exact value the DUT will see at the upcoming posedge; the accepting edge
  // then passes before the task deasserts valid.  Sampling ready after a
  // posedge races with the engine state advancing on acceptance.
  task automatic dut_read_cmd(input logic [31:0] address_i, input logic [31:0] bytes_i);
    logic accepted;
    begin
      @(negedge clk_hp_i);
      read_addr_i      = address_i;
      read_bytes_i     = bytes_i;
      read_req_valid_i = 1'b1;
      accepted         = 1'b0;
      for (int unsigned attempt = 0; (attempt < 2000) && !accepted; attempt++) begin
        #1;
        accepted = read_req_ready_o;
        if (read_cmd_err_o) begin
          $fatal(1, "NPU DMA legal read command was rejected");
        end
        @(posedge clk_hp_i);
      end
      if (!accepted) begin
        $fatal(1, "NPU DMA read command was not accepted");
      end
      @(negedge clk_hp_i);
      read_req_valid_i = 1'b0;
    end
  endtask

  task automatic dut_write_cmd(input logic [31:0] address_i, input logic [31:0] bytes_i);
    logic accepted;
    begin
      @(negedge clk_hp_i);
      write_addr_i      = address_i;
      write_bytes_i     = bytes_i;
      write_req_valid_i = 1'b1;
      accepted          = 1'b0;
      for (int unsigned attempt = 0; (attempt < 2000) && !accepted; attempt++) begin
        #1;
        accepted = write_req_ready_o;
        if (write_cmd_err_o) begin
          $fatal(1, "NPU DMA legal write command was rejected");
        end
        @(posedge clk_hp_i);
      end
      if (!accepted) begin
        $fatal(1, "NPU DMA write command was not accepted");
      end
      @(negedge clk_hp_i);
      write_req_valid_i = 1'b0;
    end
  endtask

  task automatic dut_read_cmd_illegal(input logic [31:0] address_i, input logic [31:0] bytes_i);
    int unsigned ar_before;
    begin
      ar_before = s_ar_count;
      @(negedge clk_hp_i);
      read_addr_i      = address_i;
      read_bytes_i     = bytes_i;
      read_req_valid_i = 1'b1;
      repeat (2) begin
        @(posedge clk_hp_i);
        #1;
        if (read_req_ready_o || !read_cmd_err_o || read_busy_o) begin
          $fatal(1, "NPU DMA illegal read command was not rejected cleanly");
        end
      end
      @(negedge clk_hp_i);
      read_req_valid_i = 1'b0;
      idle_cycles(4);
      if ((s_ar_count != ar_before) || busy_o || fault_o) begin
        $fatal(1, "NPU DMA illegal read command produced traffic or state");
      end
    end
  endtask

  task automatic dut_write_cmd_illegal(input logic [31:0] address_i, input logic [31:0] bytes_i);
    int unsigned aw_before;
    begin
      aw_before = s_aw_count;
      @(negedge clk_hp_i);
      write_addr_i      = address_i;
      write_bytes_i     = bytes_i;
      write_req_valid_i = 1'b1;
      repeat (2) begin
        @(posedge clk_hp_i);
        #1;
        if (write_req_ready_o || !write_cmd_err_o || write_busy_o) begin
          $fatal(1, "NPU DMA illegal write command was not rejected cleanly");
        end
      end
      @(negedge clk_hp_i);
      write_req_valid_i = 1'b0;
      idle_cycles(4);
      if ((s_aw_count != aw_before) || busy_o || fault_o) begin
        $fatal(1, "NPU DMA illegal write command produced traffic or state");
      end
    end
  endtask

  task automatic wr_beat(input logic [31:0] beat_addr_i, input logic [7:0] keep_i,
                         input logic [31:0] seed_i, input logic last_i,
                         input int unsigned timeout_i, input logic expect_err_i,
                         output logic accepted_o, output logic cmd_err_o);
    logic [63:0] data;
    begin
      data = '0;
      for (int unsigned lane = 0; lane < 8; lane++) begin
        if (keep_i[lane]) begin
          data[lane*8+:8] = pat_byte(beat_addr_i + lane, seed_i);
        end
      end
      @(negedge clk_hp_i);
      write_data_i       = data;
      write_keep_i       = keep_i;
      write_last_i       = last_i;
      write_data_valid_i = 1'b1;
      accepted_o         = 1'b0;
      cmd_err_o          = 1'b0;
      for (int unsigned attempt = 0; (attempt < timeout_i) && !accepted_o; attempt++) begin
        #1;
        accepted_o = write_data_ready_o;
        cmd_err_o  = write_cmd_err_o;
        @(posedge clk_hp_i);
      end
      if (cmd_err_o && !expect_err_i) begin
        $fatal(1, "NPU DMA write payload beat raised an unexpected command error");
      end
      if (expect_err_i && !(accepted_o && cmd_err_o)) begin
        $fatal(1, "NPU DMA did not flag the malformed payload beat");
      end
      @(negedge clk_hp_i);
      write_data_valid_i = 1'b0;
      write_last_i       = 1'b0;
    end
  endtask

  // Push payload beats [first_beat_i, beat_limit_i) of the segment; keep and
  // last are computed against the whole segment so split pushes stay exact.
  task automatic push_write_payload(input logic [31:0] address_i, input logic [31:0] bytes_i,
                                    input logic [31:0] seed_i, input logic [31:0] first_beat_i,
                                    input logic [31:0] beat_limit_i, input logic tolerate_fault_i);
    logic [31:0] total_beats;
    logic [31:0] base;
    logic [31:0] beat_addr;
    logic [31:0] last_beat;
    logic [ 7:0] keep;
    logic        accepted;
    logic        cmd_err;
    logic        aborted;
    begin
      total_beats = ({29'd0, address_i[2:0]} + bytes_i + 32'd7) >> 3;
      base        = {address_i[31:3], 3'b000};
      last_beat   = (beat_limit_i < total_beats) ? beat_limit_i : total_beats;
      aborted     = 1'b0;
      for (int unsigned beat = first_beat_i; (beat < last_beat) && !aborted; beat++) begin
        beat_addr = base + {beat, 3'b000};
        keep      = allowed_mask(beat_addr, address_i, address_i + bytes_i);
        if (s_wr_gap_random_i) begin
          s_wr_gap_lfsr = lcg_next(s_wr_gap_lfsr);
          if (s_wr_gap_lfsr[1:0] == 2'd0) begin
            idle_cycles(1);
          end else if (s_wr_gap_lfsr[1:0] == 2'd1) begin
            idle_cycles(2);
          end
        end
        wr_beat(beat_addr, keep, seed_i, beat == (total_beats - 1'b1), 2000, 1'b0, accepted,
                cmd_err);
        if (!accepted) begin
          if (tolerate_fault_i && fault_o) begin
            aborted = 1'b1;
          end else begin
            $fatal(1, "NPU DMA write payload beat %0d was not accepted", beat);
          end
        end
      end
    end
  endtask

  task automatic wait_write_done;
    logic seen;
    begin
      seen = 1'b0;
      for (int unsigned attempt = 0; (attempt < 20000) && !seen; attempt++) begin
        @(posedge clk_hp_i);
        #1;
        seen = s_done_pending_q;
      end
      if (!seen) begin
        $fatal(1, "NPU DMA write done was not pulsed");
      end
      @(negedge clk_hp_i);
      s_done_clear_i = 1'b1;
      idle_cycles(1);
      s_done_clear_i = 1'b0;
    end
  endtask

  task automatic wait_read_done;
    logic seen;
    begin
      seen = 1'b0;
      for (int unsigned attempt = 0; (attempt < 20000) && !seen; attempt++) begin
        @(posedge clk_hp_i);
        #1;
        seen = s_rd_done_q;
      end
      if (!seen) begin
        $fatal(1, "NPU DMA read stream did not complete");
      end
    end
  endtask

  task automatic wait_fault(input logic read_direction_i);
    logic seen;
    begin
      seen = 1'b0;
      for (int unsigned attempt = 0; (attempt < 20000) && !seen; attempt++) begin
        @(posedge clk_hp_i);
        #1;
        if (read_direction_i) begin
          seen = fault_o && !read_busy_o;
        end else begin
          seen = fault_o && !write_busy_o;
        end
      end
      if (!seen) begin
        $fatal(1, "NPU DMA fault was not raised or did not drain");
      end
    end
  endtask

  task automatic wait_fault_raised;
    logic seen;
    begin
      seen = 1'b0;
      for (int unsigned attempt = 0; (attempt < 20000) && !seen; attempt++) begin
        @(posedge clk_hp_i);
        #1;
        seen = fault_o;
      end
      if (!seen) begin
        $fatal(1, "NPU DMA fault was not raised");
      end
    end
  endtask

  task automatic check_fault(input logic [3:0] code_i, input logic [31:0] address_i,
                             input logic [1:0] resp_i);
    begin
      if (!fault_o || (fault_code_o != code_i) || (fault_addr_o != address_i) ||
          (fault_resp_o != resp_i)) begin
        $fatal(1, "NPU DMA fault record mismatch: fault=%b code=%h addr=%h resp=%h", fault_o,
               fault_code_o, fault_addr_o, fault_resp_o);
      end
      idle_cycles(8);
      if (!fault_o || (fault_code_o != code_i)) begin
        $fatal(1, "NPU DMA fault record was not sticky until clear_i");
      end
    end
  endtask

  task automatic do_read(input logic [31:0] address_i, input logic [31:0] bytes_i);
    begin
      setup_read_expect(address_i, bytes_i);
      dut_read_cmd(address_i, bytes_i);
      wait_read_done();
      idle_cycles(2);
      finish_read_expect(address_i, bytes_i);
    end
  endtask

  task automatic do_write(input logic [31:0] address_i, input logic [31:0] bytes_i,
                          input logic [31:0] seed_i);
    begin
      setup_write_expect(address_i, bytes_i);
      dut_write_cmd(address_i, bytes_i);
      push_write_payload(address_i, bytes_i, seed_i, 32'd0, 32'hffff_ffff, 1'b0);
      wait_write_done();
      idle_cycles(2);
      finish_write_expect(address_i, bytes_i);
      verify_region(address_i, bytes_i, seed_i, 8'hc7);
    end
  endtask

  task automatic enable_random_delays;
    begin
      @(negedge clk_hp_i);
      s_random_delay_coverage_clear_i = 1'b1;
      @(posedge clk_hp_i);
      @(negedge clk_hp_i);
      s_random_delay_coverage_clear_i = 1'b0;
      s_random_delays_i               = 1'b1;
    end
  endtask

  task automatic reseed_random_delays(input logic [31:0] seed_i);
    begin
      @(negedge clk_hp_i);
      s_random_delay_seed_i   = seed_i;
      s_random_delay_reseed_i = 1'b1;
      @(posedge clk_hp_i);
      @(negedge clk_hp_i);
      s_random_delay_reseed_i = 1'b0;
    end
  endtask

  task automatic check_random_delay_coverage;
    begin
      @(negedge clk_hp_i);
      s_random_delays_i = 1'b0;
      @(posedge clk_hp_i);
      if ((s_ar_delay_modes_q != 4'hf) || (s_aw_delay_modes_q != 4'hf) ||
          (s_w_delay_modes_q != 4'hf) || (s_r_delay_modes_q != 4'hf) ||
          (s_b_delay_modes_q != 4'hf)) begin
        $fatal(1, "NPU DMA randomized campaign did not cover every independent AXI delay mode");
      end
    end
  endtask

  task automatic wait_pause_ack(input logic expected_i);
    logic seen;
    begin
      seen = 1'b0;
      for (int unsigned attempt = 0; (attempt < 2000) && !seen; attempt++) begin
        @(posedge clk_hp_i);
        #1;
        seen = pause_ack_o == expected_i;
      end
      if (!seen) begin
        $fatal(1, "NPU DMA pause_ack_o did not become %b", expected_i);
      end
    end
  endtask

  task automatic run_alignment_matrix;
    logic        [31:0] src;
    logic        [31:0] dst;
    int unsigned        lengths[4];
    begin
      lengths[0] = 1;
      lengths[1] = 7;
      lengths[2] = 8;
      lengths[3] = 127;
      for (int unsigned offset = 0; offset < 8; offset++) begin
        for (int unsigned len_index = 0; len_index < 4; len_index++) begin
          src = SramBase + 32'h1000 + (offset * 32'h400) + (len_index * 32'h80) + offset;
          dst = SramBase + 32'h9000 + (offset * 32'h400) + (len_index * 32'h80) + offset;
          clear_memory(8'hc7);
          fill_pattern(src, lengths[len_index], 32'h1000 + (offset * 16) + len_index);
          do_read(src, lengths[len_index]);
          do_write(dst, lengths[len_index], 32'h2000 + (offset * 16) + len_index);
        end
      end
      // Multi-burst bulk and a 4 KiB crossing split into several bursts.
      clear_memory(8'hc7);
      fill_pattern(SramBase + 32'h2000, 32'd200, 32'hbeef_0001);
      do_read(SramBase + 32'h2000, 32'd200);
      do_write(SramBase + 32'ha000, 32'd200, 32'hbeef_0002);
      clear_memory(8'hc7);
      fill_pattern(SramBase + 32'h0f85, 32'd300, 32'hbeef_0003);
      do_read(SramBase + 32'h0f85, 32'd300);
      do_write(SramBase + 32'h8f83, 32'd300, 32'hbeef_0004);
      // A legal segment ending exactly at the 32-bit wrap.
      do_read(32'hffff_ff00, 32'd256);
    end
  endtask

  task automatic run_channel_hold(input logic [4:0] channel_i);
    begin
      clear_memory(8'hc7);
      unique case (channel_i)
        5'd0:    s_hold_ar_i = 1'b1;
        5'd1:    s_hold_r_i = 1'b1;
        5'd2:    s_hold_aw_i = 1'b1;
        5'd3:    s_hold_w_i = 1'b1;
        default: s_hold_b_i = 1'b1;
      endcase
      if ((channel_i == 5'd0) || (channel_i == 5'd1)) begin
        fill_pattern(SramBase + 32'h3000, 32'd128, 32'hc001_c0de);
        setup_read_expect(SramBase + 32'h3000, 32'd128);
        dut_read_cmd(SramBase + 32'h3000, 32'd128);
        if (channel_i == 5'd0) begin
          for (int unsigned attempt = 0; (attempt < 256) && !npu_axi4.arvalid; attempt++) begin
            @(posedge clk_hp_i);
          end
          if (!npu_axi4.arvalid) begin
            $fatal(1, "NPU DMA did not present AR for the channel-hold test");
          end
        end else begin
          for (int unsigned attempt = 0; (attempt < 256) && !s_rvalid_q; attempt++) begin
            @(posedge clk_hp_i);
          end
          if (!s_rvalid_q) begin
            $fatal(1, "NPU DMA did not receive R for the channel-hold test");
          end
        end
        idle_cycles(6);
        s_hold_ar_i = 1'b0;
        s_hold_r_i  = 1'b0;
        wait_read_done();
        finish_read_expect(SramBase + 32'h3000, 32'd128);
      end else begin
        setup_write_expect(SramBase + 32'hb000, 32'd128);
        dut_write_cmd(SramBase + 32'hb000, 32'd128);
        push_write_payload(SramBase + 32'hb000, 32'd128, 32'hc002_c0de, 32'd0, 32'hffff_ffff, 1'b0);
        if (channel_i == 5'd2) begin
          for (int unsigned attempt = 0; (attempt < 256) && !npu_axi4.awvalid; attempt++) begin
            @(posedge clk_hp_i);
          end
          if (!npu_axi4.awvalid) begin
            $fatal(1, "NPU DMA did not present AW for the channel-hold test");
          end
        end else if (channel_i == 5'd3) begin
          for (int unsigned attempt = 0; (attempt < 256) && !npu_axi4.wvalid; attempt++) begin
            @(posedge clk_hp_i);
          end
          if (!npu_axi4.wvalid) begin
            $fatal(1, "NPU DMA did not present W for the channel-hold test");
          end
        end else begin
          for (int unsigned attempt = 0; (attempt < 256) && !s_bvalid_q; attempt++) begin
            @(posedge clk_hp_i);
          end
          if (!s_bvalid_q) begin
            $fatal(1, "NPU DMA did not receive B for the channel-hold test");
          end
        end
        idle_cycles(6);
        s_hold_aw_i = 1'b0;
        s_hold_w_i  = 1'b0;
        s_hold_b_i  = 1'b0;
        wait_write_done();
        finish_write_expect(SramBase + 32'hb000, 32'd128);
        verify_region(SramBase + 32'hb000, 32'd128, 32'hc002_c0de, 8'hc7);
      end
    end
  endtask

  task automatic run_simultaneous_hold;
    begin
      clear_memory(8'hc7);
      fill_pattern(SramBase + 32'h3400, 32'd128, 32'hc003_c0de);
      s_hold_ar_i = 1'b1;
      s_hold_r_i  = 1'b1;
      s_hold_aw_i = 1'b1;
      s_hold_w_i  = 1'b1;
      s_hold_b_i  = 1'b1;
      setup_read_expect(SramBase + 32'h3400, 32'd128);
      setup_write_expect(SramBase + 32'hb400, 32'd128);
      dut_read_cmd(SramBase + 32'h3400, 32'd128);
      dut_write_cmd(SramBase + 32'hb400, 32'd128);
      push_write_payload(SramBase + 32'hb400, 32'd128, 32'hc004_c0de, 32'd0, 32'hffff_ffff, 1'b0);
      for (
          int unsigned attempt = 0;
          (attempt < 512) && !(npu_axi4.arvalid && npu_axi4.awvalid);
          attempt++
      ) begin
        @(posedge clk_hp_i);
      end
      if (!npu_axi4.arvalid || !npu_axi4.awvalid) begin
        $fatal(1, "NPU DMA did not present AR and AW for the simultaneous-hold test");
      end
      idle_cycles(4);
      @(negedge clk_hp_i);
      s_hold_ar_i = 1'b0;
      s_hold_aw_i = 1'b0;
      for (
          int unsigned attempt = 0; (attempt < 512) && !(s_rvalid_q && npu_axi4.wvalid); attempt++
      ) begin
        @(posedge clk_hp_i);
      end
      if (!s_rvalid_q || !npu_axi4.wvalid) begin
        $fatal(1, "NPU DMA simultaneous-hold test did not reach R and W");
      end
      idle_cycles(4);
      @(negedge clk_hp_i);
      s_hold_r_i = 1'b0;
      s_hold_w_i = 1'b0;
      for (int unsigned attempt = 0; (attempt < 512) && !s_bvalid_q; attempt++) begin
        @(posedge clk_hp_i);
      end
      if (!s_bvalid_q) begin
        $fatal(1, "NPU DMA simultaneous-hold test did not receive B");
      end
      idle_cycles(4);
      @(negedge clk_hp_i);
      s_hold_b_i = 1'b0;
      wait_read_done();
      wait_write_done();
      finish_read_expect(SramBase + 32'h3400, 32'd128);
      finish_write_expect(SramBase + 32'hb400, 32'd128);
      verify_region(SramBase + 32'hb400, 32'd128, 32'hc004_c0de, 8'hc7);
    end
  endtask

  task automatic run_pause_cases;
    logic [31:0] src;
    logic [31:0] dst;
    begin
      src = SramBase + 32'h3800;
      dst = SramBase + 32'hb800;
      // Pause while AR is presented but unaccepted: VALID and payload are
      // retained, pause_ack_o asserts with the unaccepted VALID, the AR is
      // accepted during the pause and drains, and unblock resumes identically.
      clear_memory(8'hc7);
      fill_pattern(src, 32'd128, 32'hd101_0000);
      s_hold_ar_i = 1'b1;
      setup_read_expect(src, 32'd128);
      dut_read_cmd(src, 32'd128);
      for (int unsigned attempt = 0; (attempt < 256) && !npu_axi4.arvalid; attempt++) begin
        @(posedge clk_hp_i);
      end
      if (!npu_axi4.arvalid) begin
        $fatal(1, "NPU DMA did not present AR for the pause test");
      end
      @(negedge clk_hp_i);
      block_new_i = 1'b1;
      wait_pause_ack(1'b1);
      if (!npu_axi4.arvalid) begin
        $fatal(1, "NPU DMA withdrew an unaccepted AR during pause");
      end
      idle_cycles(8);
      if (!npu_axi4.arvalid || !pause_ack_o) begin
        $fatal(1, "NPU DMA did not retain the unaccepted AR through pause");
      end
      @(negedge clk_hp_i);
      s_hold_ar_i = 1'b0;
      wait_read_done();
      wait_pause_ack(1'b1);
      @(negedge clk_hp_i);
      block_new_i = 1'b0;
      idle_cycles(2);
      if (pause_ack_o) begin
        $fatal(1, "NPU DMA pause_ack_o survived unblock");
      end
      finish_read_expect(src, 32'd128);

      // Pause while AW is presented but unaccepted, then accept during pause
      // and drain W/B entirely from the reserved payload.
      s_hold_aw_i = 1'b1;
      setup_write_expect(dst, 32'd128);
      dut_write_cmd(dst, 32'd128);
      push_write_payload(dst, 32'd128, 32'hd102_0000, 32'd0, 32'hffff_ffff, 1'b0);
      for (int unsigned attempt = 0; (attempt < 256) && !npu_axi4.awvalid; attempt++) begin
        @(posedge clk_hp_i);
      end
      if (!npu_axi4.awvalid) begin
        $fatal(1, "NPU DMA did not present AW for the pause test");
      end
      @(negedge clk_hp_i);
      block_new_i = 1'b1;
      wait_pause_ack(1'b1);
      if (!npu_axi4.awvalid) begin
        $fatal(1, "NPU DMA withdrew an unaccepted AW during pause");
      end
      idle_cycles(8);
      if (!npu_axi4.awvalid || !pause_ack_o) begin
        $fatal(1, "NPU DMA did not retain the unaccepted AW through pause");
      end
      @(negedge clk_hp_i);
      s_hold_aw_i = 1'b0;
      wait_write_done();
      wait_pause_ack(1'b1);
      @(negedge clk_hp_i);
      block_new_i = 1'b0;
      finish_write_expect(dst, 32'd128);
      verify_region(dst, 32'd128, 32'hd102_0000, 8'hc7);

      // Pause mid-gather: ack with busy high and zero accepted obligations;
      // gathering stalls and resumes identically after unblock.
      setup_write_expect(dst + 32'h100, 32'd128);
      dut_write_cmd(dst + 32'h100, 32'd128);
      push_write_payload(dst + 32'h100, 32'd128, 32'hd103_0000, 32'd0, 32'd3, 1'b0);
      @(negedge clk_hp_i);
      block_new_i = 1'b1;
      wait_pause_ack(1'b1);
      if (!write_busy_o || write_data_ready_o) begin
        $fatal(1, "NPU DMA pause mid-gather did not ack busy with ready low");
      end
      idle_cycles(6);
      @(negedge clk_hp_i);
      block_new_i = 1'b0;
      push_write_payload(dst + 32'h100, 32'd128, 32'hd103_0000, 32'd3, 32'hffff_ffff, 1'b0);
      wait_write_done();
      finish_write_expect(dst + 32'h100, 32'd128);
      verify_region(dst + 32'h100, 32'd128, 32'hd103_0000, 8'hc7);

      // Pause on an idle engine acknowledges immediately and creates nothing.
      @(negedge clk_hp_i);
      block_new_i = 1'b1;
      idle_cycles(2);
      if (!pause_ack_o || busy_o) begin
        $fatal(1, "NPU DMA idle pause did not ack immediately");
      end
      @(negedge clk_hp_i);
      block_new_i = 1'b0;
      idle_cycles(2);
    end
  endtask

  task automatic run_read_error_case(input logic [1:0] resp_i);
    logic        [31:0] src;
    int unsigned        ar_before;
    logic        [63:0] bytes_before;
    begin
      // A 256-byte segment whose first 16-beat burst errors mid-burst: the
      // burst drains, the second burst is never issued, and the fault sticks.
      src = SramBase + 32'h4000;
      clear_memory(8'hc7);
      fill_pattern(src, 32'd256, 32'he001_0000);
      setup_read_expect(src, 32'd256);
      ar_before    = s_ar_count;
      bytes_before = read_bytes_o;
      @(negedge clk_hp_i);
      s_read_err_en_i   = 1'b1;
      s_read_err_addr_i = src + 32'd40;
      s_read_err_code_i = resp_i;
      dut_read_cmd(src, 32'd256);
      wait_fault(1'b1);
      idle_cycles(40);
      check_fault(`APB4_NPU__FAULT_CODE_AXI_READ, src + 32'd40, resp_i);
      if ((s_ar_count - ar_before) != 1) begin
        $fatal(1, "NPU DMA issued a new read burst after a read fault");
      end
      if ((read_bytes_o - bytes_before) != 64'd128) begin
        $fatal(1, "NPU DMA read byte counter did not include the errored burst: %h",
               read_bytes_o - bytes_before);
      end
      if (read_req_ready_o) begin
        $fatal(1, "NPU DMA accepted read commands while faulted");
      end
      @(negedge clk_hp_i);
      s_read_err_en_i = 1'b0;
      s_rd_active_i   = 1'b0;
      s_ar_check_i    = 1'b0;
      pulse_clear();
      if (fault_o || busy_o || (read_bytes_o != 64'd0)) begin
        $fatal(1, "NPU DMA clear_i did not reset fault and counters");
      end
      do_read(src, 32'd64);
    end
  endtask

  task automatic run_write_error_case(input logic [1:0] resp_i);
    logic        [31:0] dst;
    int unsigned        aw_before;
    int unsigned        done_before;
    logic        [63:0] bytes_before;
    begin
      dst = SramBase + 32'hc000;
      clear_memory(8'hc7);
      setup_write_expect(dst, 32'd256);
      aw_before    = s_aw_count;
      done_before  = s_done_count_q;
      bytes_before = write_bytes_o;
      @(negedge clk_hp_i);
      s_write_err_en_i   = 1'b1;
      s_write_err_addr_i = {dst[31:3], 3'b000};
      s_write_err_code_i = resp_i;
      dut_write_cmd(dst, 32'd256);
      push_write_payload(dst, 32'd256, 32'he002_0000, 32'd0, 32'hffff_ffff, 1'b1);
      wait_fault(1'b0);
      check_fault(`APB4_NPU__FAULT_CODE_AXI_WRITE, {dst[31:3], 3'b000} + 32'd120, resp_i);
      if ((s_aw_count - aw_before) != 1) begin
        $fatal(1, "NPU DMA issued a new write burst after a write fault");
      end
      if ((s_done_count_q - done_before) != 0) begin
        $fatal(1, "NPU DMA pulsed write_done_o for an errored burst");
      end
      if ((write_bytes_o - bytes_before) != 64'd128) begin
        $fatal(1, "NPU DMA write byte counter did not include the errored burst: %h",
               write_bytes_o - bytes_before);
      end
      @(negedge clk_hp_i);
      s_write_err_en_i = 1'b0;
      s_wr_active_i    = 1'b0;
      s_aw_check_i     = 1'b0;
      pulse_clear();
      if (fault_o || busy_o || (write_bytes_o != 64'd0)) begin
        $fatal(1, "NPU DMA clear_i did not reset fault and counters");
      end
      clear_memory(8'hc7);
      do_write(dst, 32'd64, 32'he003_0000);
    end
  endtask

  task automatic run_read_protocol_case(input logic [2:0] mode_i, input logic [31:0] src_i,
                                        input logic [31:0] expected_addr_i);
    begin
      clear_memory(8'hc7);
      fill_pattern(src_i, 32'd64, 32'he004_0000);
      setup_read_expect(src_i, 32'd64);
      @(negedge clk_hp_i);
      s_inject_bad_rid_i     = mode_i == 3'd0;
      s_inject_early_rlast_i = mode_i == 3'd1;
      s_inject_bad_rlast_i   = mode_i == 3'd2;
      dut_read_cmd(src_i, 32'd64);
      wait_fault_raised();
      check_fault(`APB4_NPU__FAULT_CODE_AXI_PROTOCOL, expected_addr_i, 2'b00);
      if (mode_i != 3'd2) begin
        // Quarantine: the remaining beats are presented but never accepted.
        idle_cycles(6);
        if (!npu_axi4.rvalid || npu_axi4.rready) begin
          $fatal(1, "NPU DMA did not quarantine the malformed read channel");
        end
      end
      @(negedge clk_hp_i);
      s_inject_bad_rid_i     = 1'b0;
      s_inject_early_rlast_i = 1'b0;
      s_inject_bad_rlast_i   = 1'b0;
      s_rd_active_i          = 1'b0;
      s_ar_check_i           = 1'b0;
      pulse_clear();
      if (mode_i == 3'd0) begin
        // A residual late R from the flushed epoch is refused and flagged.
        @(negedge clk_hp_i);
        s_force_residual_r_i = 1'b1;
        wait_fault_raised();
        idle_cycles(4);
        if (!fault_o || (fault_code_o != `APB4_NPU__FAULT_CODE_AXI_PROTOCOL)) begin
          $fatal(1, "NPU DMA did not flag a residual late R as AXI_PROTOCOL");
        end
        if (npu_axi4.rready) begin
          $fatal(1, "NPU DMA accepted a residual R after quarantine recovery");
        end
        pulse_clear();
      end
      if (fault_o || busy_o) begin
        $fatal(1, "NPU DMA clear_i did not recover the quarantined read channel");
      end
      do_read(src_i, 32'd64);
    end
  endtask

  task automatic run_residual_idle_case;
    begin
      clear_memory(8'hc7);
      fill_pattern(SramBase + 32'h4800, 32'd32, 32'he005_0000);
      do_read(SramBase + 32'h4800, 32'd32);
      // A residual R with no outstanding read is impossible sequencing.
      @(negedge clk_hp_i);
      s_force_residual_r_i = 1'b1;
      wait_fault_raised();
      idle_cycles(4);
      if (!fault_o || (fault_code_o != `APB4_NPU__FAULT_CODE_AXI_PROTOCOL)) begin
        $fatal(1, "NPU DMA did not flag a residual idle R as AXI_PROTOCOL");
      end
      pulse_clear();
      do_read(SramBase + 32'h4800, 32'd32);
    end
  endtask

  task automatic run_write_protocol_case;
    logic        [31:0] dst;
    int unsigned        done_before;
    begin
      dst = SramBase + 32'hc800;
      clear_memory(8'hc7);
      setup_write_expect(dst, 32'd64);
      done_before = s_done_count_q;
      @(negedge clk_hp_i);
      s_inject_bad_bid_i = 1'b1;
      dut_write_cmd(dst, 32'd64);
      push_write_payload(dst, 32'd64, 32'he006_0000, 32'd0, 32'hffff_ffff, 1'b1);
      wait_fault_raised();
      idle_cycles(4);
      if (!fault_o || (fault_code_o != `APB4_NPU__FAULT_CODE_AXI_PROTOCOL)) begin
        $fatal(1, "NPU DMA did not flag a bad BID as AXI_PROTOCOL");
      end
      if ((s_done_count_q - done_before) != 0) begin
        $fatal(1, "NPU DMA pulsed write_done_o for a malformed B");
      end
      // Quarantine: a residual late B from the old epoch is refused.
      @(negedge clk_hp_i);
      s_force_residual_b_i = 1'b1;
      idle_cycles(6);
      if (!npu_axi4.bvalid || npu_axi4.bready) begin
        $fatal(1, "NPU DMA accepted a residual B from the old epoch");
      end
      @(negedge clk_hp_i);
      s_inject_bad_bid_i = 1'b0;
      s_wr_active_i      = 1'b0;
      s_aw_check_i       = 1'b0;
      pulse_clear();
      if (fault_o || busy_o) begin
        $fatal(1, "NPU DMA clear_i did not recover the quarantined write channel");
      end
      clear_memory(8'hc7);
      do_write(dst, 32'd64, 32'he007_0000);
    end
  endtask

  task automatic run_write_stream_err_case(input logic early_last_i);
    logic        [31:0] dst;
    logic               accepted;
    logic               cmd_err;
    int unsigned        aw_before;
    begin
      // A write_last_i that does not match the planned segment end is a
      // local command-stream rejection, never an AXI transaction.
      dst = SramBase + 32'hd400;
      clear_memory(8'hc7);
      setup_write_expect(dst, 32'd64);
      aw_before = s_aw_count;
      dut_write_cmd(dst, 32'd64);
      for (int unsigned beat = 0; beat < 5; beat++) begin
        wr_beat(dst + (beat * 32'd8), 8'hff, 32'he008_0000, 1'b0, 2000, 1'b0, accepted, cmd_err);
        if (!accepted) begin
          $fatal(1, "NPU DMA refused a legal mid-segment payload beat");
        end
      end
      // Assert write_last_i early, or withhold it on the final planned beat.
      if (early_last_i) begin
        wr_beat(dst + 32'd40, 8'hff, 32'he008_0000, 1'b1, 2000, 1'b1, accepted, cmd_err);
      end else begin
        wr_beat(dst + 32'd40, 8'hff, 32'he008_0000, 1'b0, 2000, 1'b0, accepted, cmd_err);
        wr_beat(dst + 32'd48, 8'hff, 32'he008_0000, 1'b0, 2000, 1'b0, accepted, cmd_err);
        wr_beat(dst + 32'd56, 8'hff, 32'he008_0000, 1'b0, 2000, 1'b1, accepted, cmd_err);
      end
      if (!accepted || !cmd_err) begin
        $fatal(1, "NPU DMA wedged instead of rejecting the payload stream");
      end
      idle_cycles(4);
      if (fault_o || (s_aw_count != aw_before) || write_busy_o) begin
        $fatal(1, "NPU DMA payload-stream rejection produced AXI state");
      end
      @(negedge clk_hp_i);
      s_wr_active_i = 1'b0;
      s_aw_check_i  = 1'b0;
      do_write(dst, 32'd64, 32'he009_0000);
    end
  endtask

  task automatic run_clear_cases;
    logic [31:0] src;
    logic [31:0] dst;
    begin
      src = SramBase + 32'h5000;
      dst = SramBase + 32'hd000;
      // clear_i mid read burst: presented and accepted state cancels.
      clear_memory(8'hc7);
      fill_pattern(src, 32'd128, 32'hf001_0000);
      setup_read_expect(src, 32'd128);
      s_hold_r_i = 1'b1;
      dut_read_cmd(src, 32'd128);
      for (int unsigned attempt = 0; (attempt < 256) && !s_rvalid_q; attempt++) begin
        @(posedge clk_hp_i);
      end
      if (!s_rvalid_q) begin
        $fatal(1, "NPU DMA did not reach R for the clear test");
      end
      @(negedge clk_hp_i);
      s_rd_active_i = 1'b0;
      s_ar_check_i  = 1'b0;
      pulse_clear();
      if (busy_o || fault_o || read_data_valid_o || npu_axi4.arvalid || npu_axi4.rready) begin
        $fatal(1, "NPU DMA clear_i mid read burst did not return to clean idle");
      end
      @(negedge clk_hp_i);
      s_hold_r_i = 1'b0;
      do_read(src, 32'd128);

      // clear_i with AW presented but unaccepted: no W ever follows.
      s_hold_aw_i = 1'b1;
      setup_write_expect(dst, 32'd64);
      dut_write_cmd(dst, 32'd64);
      push_write_payload(dst, 32'd64, 32'hf002_0000, 32'd0, 32'hffff_ffff, 1'b0);
      for (int unsigned attempt = 0; (attempt < 256) && !npu_axi4.awvalid; attempt++) begin
        @(posedge clk_hp_i);
      end
      if (!npu_axi4.awvalid) begin
        $fatal(1, "NPU DMA did not present AW for the clear test");
      end
      @(negedge clk_hp_i);
      s_wr_active_i = 1'b0;
      s_aw_check_i  = 1'b0;
      pulse_clear();
      if (busy_o || npu_axi4.awvalid || npu_axi4.wvalid) begin
        $fatal(1, "NPU DMA clear_i with presented AW did not cancel the write");
      end
      idle_cycles(4);
      if (memory_byte(dst) != 8'hc7) begin
        $fatal(1, "NPU DMA wrote payload after clear_i cancelled its AW");
      end
      @(negedge clk_hp_i);
      s_hold_aw_i = 1'b0;
      do_write(dst, 32'd64, 32'hf003_0000);
    end
  endtask

  task automatic run_counter_case;
    logic [63:0] stall_before;
    logic [63:0] stall_after;
    begin
      pulse_clear();
      if ((read_bytes_o != 64'd0) || (write_bytes_o != 64'd0) || (stall_cycles_o != 64'd0)) begin
        $fatal(1, "NPU DMA counters were not zero after clear_i");
      end
      clear_memory(8'hc7);
      fill_pattern(SramBase + 32'h5405, 32'd100, 32'h0a10_0000);
      do_read(SramBase + 32'h5405, 32'd100);
      if (read_bytes_o != 64'd100) begin
        $fatal(1, "NPU DMA read_bytes_o mismatch: %h", read_bytes_o);
      end
      do_write(SramBase + 32'hd805, 32'd100, 32'h0a20_0000);
      if (write_bytes_o != 64'd100) begin
        $fatal(1, "NPU DMA write_bytes_o mismatch: %h", write_bytes_o);
      end
      stall_before = stall_cycles_o;
      idle_cycles(30);
      if (stall_cycles_o != stall_before) begin
        $fatal(1, "NPU DMA stall counter advanced while idle");
      end
      // Held channels must produce observable AXI handshake stalls.
      s_hold_ar_i = 1'b1;
      setup_read_expect(SramBase + 32'h5800, 32'd64);
      dut_read_cmd(SramBase + 32'h5800, 32'd64);
      for (int unsigned attempt = 0; (attempt < 256) && !npu_axi4.arvalid; attempt++) begin
        @(posedge clk_hp_i);
      end
      idle_cycles(8);
      s_hold_ar_i = 1'b0;
      wait_read_done();
      finish_read_expect(SramBase + 32'h5800, 32'd64);
      stall_after = stall_cycles_o;
      if (stall_after <= stall_before) begin
        $fatal(1, "NPU DMA stall counter did not advance under AXI stalls");
      end
    end
  endtask

  task automatic run_overlap_case;
    logic [31:0] src;
    logic [31:0] dst;
    begin
      src = SramBase + 32'h6000;
      dst = SramBase + 32'he000;
      clear_memory(8'hc7);
      fill_pattern(src, 32'd200, 32'h0b01_0000);
      setup_read_expect(src, 32'd200);
      setup_write_expect(dst, 32'd200);
      dut_read_cmd(src, 32'd200);
      dut_write_cmd(dst, 32'd200);
      push_write_payload(dst, 32'd200, 32'h0b02_0000, 32'd0, 32'hffff_ffff, 1'b0);
      wait_read_done();
      wait_write_done();
      finish_read_expect(src, 32'd200);
      finish_write_expect(dst, 32'd200);
      verify_region(dst, 32'd200, 32'h0b02_0000, 8'hc7);
      if (!s_overlap_seen_q) begin
        $fatal(1, "NPU DMA read and write channels did not overlap");
      end
    end
  endtask

  task automatic run_random_campaign;
    logic        [31:0] random_value;
    logic        [31:0] src;
    logic        [31:0] dst;
    logic        [31:0] bytes;
    logic        [31:0] seed;
    int unsigned        lengths      [6];
    int unsigned        completed;
    begin
      lengths[0] = 1;
      lengths[1] = 7;
      lengths[2] = 8;
      lengths[3] = 16;
      lengths[4] = 127;
      lengths[5] = 0;
      completed  = 0;
      enable_random_delays();
      @(negedge clk_hp_i);
      s_stream_random_bp_i = 1'b1;
      s_wr_gap_random_i    = 1'b1;
      for (int unsigned seed_index = 0; seed_index < 10; seed_index++) begin
        reseed_random_delays(32'h9e37_79b9 ^ seed_index);
        random_value = 32'h9e37_79b9 ^ seed_index;
        for (int unsigned iteration = 0; iteration < 100; iteration++) begin
          random_value = lcg_next(random_value);
          seed         = random_value ^ 32'h5d3a_0000;
          lengths[5]   = 32'd200 + ({27'd0, random_value[13:9]} * 32'd9);
          if (random_value[17]) begin
            bytes = lengths[random_value[21:19]%6];
          end else begin
            bytes = 32'd1 + ({29'd0, random_value[8:1]} % 32'd64);
          end
          if (bytes > 32'd400) begin
            bytes = 32'd400;
          end
          src = SramBase + 32'h1000 + ({17'd0, random_value[30:16]} % 32'd20000);
          src = {src[31:3], random_value[15:13]};
          if ((src + bytes) >= (SramBase + 32'h7000)) begin
            src = SramBase + 32'h1000 + {29'd0, random_value[15:13]};
          end
          dst = SramBase + 32'h8000 + ({17'd0, random_value[14:0]} % 32'd20000);
          dst = {dst[31:3], random_value[12:10]};
          if ((dst + bytes) >= (SramBase + 32'hf000)) begin
            dst = SramBase + 32'h8000 + {29'd0, random_value[12:10]};
          end
          unique case (random_value[25:24] % 3)
            0: begin
              clear_window(src - 1'b1, bytes + 32'd2, 8'hc7);
              fill_pattern(src, bytes, seed);
              do_read(src, bytes);
            end
            1: begin
              clear_window(dst - 1'b1, bytes + 32'd2, 8'hc7);
              do_write(dst, bytes, seed);
            end
            default: begin
              clear_window(src - 1'b1, bytes + 32'd2, 8'hc7);
              clear_window(dst - 1'b1, bytes + 32'd2, 8'hc7);
              fill_pattern(src, bytes, seed);
              setup_read_expect(src, bytes);
              setup_write_expect(dst, bytes);
              dut_read_cmd(src, bytes);
              dut_write_cmd(dst, bytes);
              push_write_payload(dst, bytes, seed, 32'd0, 32'hffff_ffff, 1'b0);
              wait_read_done();
              wait_write_done();
              finish_read_expect(src, bytes);
              finish_write_expect(dst, bytes);
              verify_region(dst, bytes, seed, 8'hc7);
            end
          endcase
          completed++;
        end
        $display("NPU DMA random campaign seed %0d complete (delay seed %h)", seed_index,
                 32'h9e37_79b9 ^ seed_index);
      end
      @(negedge clk_hp_i);
      s_stream_random_bp_i = 1'b0;
      s_wr_gap_random_i    = 1'b0;
      if (completed != 1000) begin
        $fatal(1, "NPU DMA randomized campaign did not execute 1000 segments");
      end
      check_random_delay_coverage();
    end
  endtask

  initial begin
    s_inject_bad_rid_i              = 1'b0;
    s_inject_bad_bid_i              = 1'b0;
    s_inject_bad_rlast_i            = 1'b0;
    s_inject_early_rlast_i          = 1'b0;
    s_force_residual_r_i            = 1'b0;
    s_force_residual_b_i            = 1'b0;
    s_read_err_en_i                 = 1'b0;
    s_read_err_addr_i               = '0;
    s_read_err_code_i               = 2'd0;
    s_write_err_en_i                = 1'b0;
    s_write_err_addr_i              = '0;
    s_write_err_code_i              = 2'd0;
    s_hold_ar_i                     = 1'b0;
    s_hold_r_i                      = 1'b0;
    s_hold_aw_i                     = 1'b0;
    s_hold_w_i                      = 1'b0;
    s_hold_b_i                      = 1'b0;
    s_random_delays_i               = 1'b0;
    s_random_delay_reseed_i         = 1'b0;
    s_random_delay_coverage_clear_i = 1'b0;
    s_random_delay_seed_i           = '0;
    s_rd_active_i                   = 1'b0;
    s_rd_seg_addr_i                 = '0;
    s_rd_seg_bytes_i                = '0;
    s_rd_seg_end_i                  = '0;
    s_rd_done_clear_i               = 1'b0;
    s_ar_check_i                    = 1'b0;
    s_ar_expect_set_i               = 1'b0;
    s_ar_expect_addr_i              = '0;
    s_wr_active_i                   = 1'b0;
    s_wr_seg_start_i                = '0;
    s_wr_seg_end_i                  = '0;
    s_wr_end_aligned_i              = '0;
    s_wr_clear_i                    = 1'b0;
    s_done_clear_i                  = 1'b0;
    s_aw_check_i                    = 1'b0;
    s_aw_expect_set_i               = 1'b0;
    s_aw_expect_addr_i              = '0;
    s_stream_random_bp_i            = 1'b0;
    s_wr_gap_random_i               = 1'b0;
    s_wr_gap_lfsr                   = 32'h1bad_b002;
    s_phase                         = "reset";
    s_phase_reset_i                 = 1'b0;

    repeat (3) @(posedge clk_hp_i);
    rst_hp_n_i = 1'b1;
    idle_cycles(2);
    if (busy_o || fault_o || pause_ack_o || read_data_valid_o || write_done_o) begin
      $fatal(1, "NPU DMA did not reset to clean idle");
    end

    // clear_i on an idle engine creates no artificial events.
    set_phase("idle clear");
    pulse_clear();
    if (busy_o || fault_o || (s_done_count_q != 0) || (stall_cycles_o != 64'd0)) begin
      $fatal(1, "NPU DMA idle clear_i created artificial events");
    end

    set_phase("command rejection");
    dut_read_cmd_illegal(SramBase + 32'h100, 32'd0);
    dut_read_cmd_illegal(32'hffff_ff00, 32'h0000_0200);
    dut_write_cmd_illegal(SramBase + 32'h8000, 32'd0);
    dut_write_cmd_illegal(32'hffff_ff80, 32'h0000_0100);

    set_phase("alignment matrix");
    run_alignment_matrix();

    set_phase("channel holds");
    for (int unsigned channel = 0; channel < 5; channel++) begin
      run_channel_hold(channel[4:0]);
    end
    run_simultaneous_hold();

    set_phase("pause cases");
    run_pause_cases();

    set_phase("read SLVERR");
    run_read_error_case(2'd2);
    set_phase("read DECERR");
    run_read_error_case(2'd3);
    set_phase("write SLVERR");
    run_write_error_case(2'd2);
    set_phase("write DECERR");
    run_write_error_case(2'd3);

    set_phase("bad RID quarantine");
    run_read_protocol_case(3'd0, SramBase + 32'h4400, SramBase + 32'h4400);
    set_phase("early RLAST");
    run_read_protocol_case(3'd1, SramBase + 32'h4400, SramBase + 32'h4400);
    set_phase("missing RLAST");
    run_read_protocol_case(3'd2, SramBase + 32'h4400, SramBase + 32'h4400 + 32'd56);
    set_phase("residual idle R");
    run_residual_idle_case();
    set_phase("bad BID quarantine");
    run_write_protocol_case();

    set_phase("write stream early last");
    run_write_stream_err_case(1'b1);
    set_phase("write stream missing last");
    run_write_stream_err_case(1'b0);

    set_phase("clear cases");
    run_clear_cases();

    set_phase("counters");
    run_counter_case();

    set_phase("overlap");
    run_overlap_case();

    set_phase("random campaign");
    run_random_campaign();

    if (!s_saw_arlen_0_q || !s_saw_arlen_15_q || !s_saw_awlen_0_q || !s_saw_awlen_15_q ||
        !s_saw_arsize_0_q || !s_saw_arsize_1_q || !s_saw_arsize_2_q || !s_saw_4k_split_q ||
        !s_overlap_seen_q) begin
      $fatal(1, "NPU DMA campaign missed required burst or alignment coverage");
    end

    $display("NPU DMA test passed");
    $finish;
  end

  initial begin
    repeat (6000000) @(posedge clk_hp_i);
    $fatal(1, "NPU DMA test timed out");
  end
endmodule
