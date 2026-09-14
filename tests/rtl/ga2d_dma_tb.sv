`timescale 1ns / 1ps

`include "ga2d_define.svh"

module ga2d_dma_tb;
  localparam logic [31:0] SramBase = 32'h3000_0000;
  localparam int unsigned MemoryBytes = 32768;
  localparam logic [2:0] IrqDoneMask = 3'b001 << `APB4_GA2D__IRQ_DONE;
  localparam logic [2:0] IrqErrorMask = 3'b001 << `APB4_GA2D__IRQ_ERROR;
  localparam logic [2:0] IrqAbortDoneMask = 3'b001 << `APB4_GA2D__IRQ_ABORT_DONE;

  logic               clk_i = 1'b0;
  logic               rst_n_i = 1'b0;
  logic               resource_quiesce_i = 1'b0;
  logic               resource_reset_i = 1'b0;
  logic               source_stop_i = 1'b0;
  logic               source_safe_idle_i = 1'b1;
  logic               block_ack_i = 1'b0;
  logic               bridge_clear_busy_i = 1'b0;
  logic        [ 7:0] bridge_epoch_i = 8'd0;
  logic               data_ready_i = 1'b1;
  logic        [ 1:0] mem_pad_mode_i = 2'd0;
  logic               idle_o;
  logic               core_safe_idle_o;
  logic               irq_o;
  logic        [ 7:0] s_memory                        [0:MemoryBytes-1];
  logic               s_rvalid_q;
  logic        [ 2:0] s_rid_q;
  logic        [ 1:0] s_rresp_q;
  logic        [31:0] s_raddr_q;
  logic        [63:0] s_rdata_q;
  logic        [ 2:0] s_rsize_q;
  logic        [ 8:0] s_rbeats_q;
  logic               s_residual_r_pending_q;
  logic               s_residual_r_valid_q;
  logic        [ 1:0] s_residual_r_delay_q;
  logic               s_aw_pending_q;
  logic        [31:0] s_awaddr_q;
  logic        [ 8:0] s_wbeats_q;
  logic               s_bvalid_q;
  logic        [ 2:0] s_bid_q;
  logic        [ 1:0] s_bresp_q;
  logic               s_residual_b_pending_q;
  logic               s_residual_b_valid_q;
  logic        [ 1:0] s_residual_b_delay_q;
  logic               s_inject_read_error;
  logic               s_inject_write_error;
  logic               s_inject_read_decerr;
  logic               s_inject_write_decerr;
  logic               s_inject_bad_rid;
  logic               s_inject_bad_rlast;
  logic               s_inject_bad_bid;
  logic               s_schedule_residual_r_i;
  logic               s_schedule_residual_b_i;
  logic               s_hold_ar_i;
  logic               s_hold_r_i;
  logic               s_hold_aw_i;
  logic               s_hold_w_i;
  logic               s_hold_b_i;
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
  logic               s_clear_burst_observations_i;
  logic               s_check_read_bounds_i;
  logic        [31:0] s_read_row0_start_i;
  logic        [31:0] s_read_row0_end_i;
  logic        [31:0] s_read_row1_start_i;
  logic        [31:0] s_read_row1_end_i;
  logic               s_check_write_bounds_i;
  logic        [31:0] s_write_row0_start_i;
  logic        [31:0] s_write_row0_end_i;
  logic        [31:0] s_write_row1_start_i;
  logic        [31:0] s_write_row1_end_i;
  logic               s_saw_arsize_0_q;
  logic               s_saw_arsize_1_q;
  logic               s_saw_arsize_2_q;
  logic               s_saw_arlen_0_q;
  logic               s_saw_arlen_14_q;
  logic               s_saw_arlen_15_q;
  logic               s_saw_awlen_0_q;
  logic               s_saw_awlen_7_q;
  logic               s_saw_awlen_14_q;
  logic               s_saw_awlen_15_q;
  int unsigned        s_ar_count;
  int unsigned        s_aw_count;
  int unsigned        s_ar_count_before_validation;
  int unsigned        s_aw_count_before_validation;
  logic               s_aw_stalled_q;
  logic        [31:0] s_awaddr_stalled_q;
  logic        [ 7:0] s_awlen_stalled_q;
  logic        [ 2:0] s_awsize_stalled_q;
  logic               s_w_stalled_q;
  logic        [63:0] s_wdata_stalled_q;
  logic        [ 7:0] s_wstrb_stalled_q;
  logic               s_ar_stalled_q;
  logic        [31:0] s_araddr_stalled_q;
  logic        [ 7:0] s_arlen_stalled_q;
  logic        [ 2:0] s_arsize_stalled_q;
  logic               s_source_stop_seen_q;
  logic               s_aw_allowed_after_stop_q;
  logic               s_ar_allowed_after_stop_q;
  logic               s_previous_awvalid_q;
  logic               s_previous_arvalid_q;

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) ga2d_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

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

  assign ga2d_axi4.arready = !s_hold_ar_i && !s_rvalid_q && !s_residual_r_pending_q &&
                             !s_residual_r_valid_q &&
                             (!s_random_delays_i ||
                              (s_ar_delay_pending_q && (s_ar_delay_q == 2'd0)));
  assign ga2d_axi4.rid = s_residual_r_valid_q ? 3'd0 : s_rid_q;
  assign ga2d_axi4.rdata = s_rdata_q;
  assign ga2d_axi4.rresp = s_rresp_q;
  assign ga2d_axi4.rlast   = s_residual_r_valid_q ? 1'b1 :
                             (!s_inject_bad_rlast && (s_rbeats_q == 9'd1));
  assign ga2d_axi4.ruser = '0;
  assign ga2d_axi4.rvalid  = !s_hold_r_i &&
                             ((s_rvalid_q && (!s_random_delays_i || !s_r_delay_pending_q)) ||
                              s_residual_r_valid_q);
  assign ga2d_axi4.awready = !s_hold_aw_i && !s_aw_pending_q && !s_bvalid_q &&
                             !s_residual_b_pending_q && !s_residual_b_valid_q &&
                             (!s_random_delays_i ||
                              (s_aw_delay_pending_q && (s_aw_delay_q == 2'd0)));
  assign ga2d_axi4.wready  = !s_hold_w_i && s_aw_pending_q && !s_bvalid_q &&
                             !s_residual_b_pending_q && !s_residual_b_valid_q &&
                             (!s_random_delays_i ||
                              (s_w_delay_pending_q && (s_w_delay_q == 2'd0)));
  assign ga2d_axi4.bid = s_residual_b_valid_q ? 3'd0 : s_bid_q;
  assign ga2d_axi4.bresp = s_bresp_q;
  assign ga2d_axi4.buser = '0;
  assign ga2d_axi4.bvalid  = !s_hold_b_i &&
                             ((s_bvalid_q && (!s_random_delays_i || !s_b_delay_pending_q)) ||
                              s_residual_b_valid_q);

  apb4_ga2d u_dut (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .resource_quiesce_i (resource_quiesce_i),
      .resource_reset_i   (resource_reset_i),
      .source_stop_i      (source_stop_i),
      .source_safe_idle_i (source_safe_idle_i),
      .block_ack_i        (block_ack_i),
      .bridge_clear_busy_i(bridge_clear_busy_i),
      .bridge_epoch_i     (bridge_epoch_i),
      .data_ready_i       (data_ready_i),
      .mem_pad_mode_i     (mem_pad_mode_i),
      .apb4               (apb4),
      .ga2d_axi4          (ga2d_axi4),
      .idle_o             (idle_o),
      .core_safe_idle_o   (core_safe_idle_o),
      .irq_o              (irq_o)
  );

  // Each channel chooses a separately seeded 0..3 cycle delay.  Once chosen,
  // a request or response stays eligible until its handshake, so the BFM has
  // bounded progress and cannot hide a DUT deadlock behind random starvation.
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
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
      end else if (!s_random_delays_i || bridge_clear_busy_i) begin
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
        if (!ga2d_axi4.arvalid || s_rvalid_q || s_residual_r_pending_q ||
            s_residual_r_valid_q) begin
          s_ar_delay_q         <= '0;
          s_ar_delay_pending_q <= 1'b0;
        end else if (!s_ar_delay_pending_q) begin
          s_ar_delay_q                               <= s_ar_delay_lfsr_q[1:0];
          s_ar_delay_pending_q                       <= 1'b1;
          s_ar_delay_modes_q[s_ar_delay_lfsr_q[1:0]] <= 1'b1;
          s_ar_delay_lfsr_q                          <= next_delay_lfsr(s_ar_delay_lfsr_q);
        end else if (s_ar_delay_q != 2'd0) begin
          s_ar_delay_q <= s_ar_delay_q - 1'b1;
        end else if (ga2d_axi4.arready) begin
          s_ar_delay_pending_q <= 1'b0;
        end

        if (!ga2d_axi4.awvalid || s_aw_pending_q || s_bvalid_q ||
            s_residual_b_pending_q || s_residual_b_valid_q) begin
          s_aw_delay_q         <= '0;
          s_aw_delay_pending_q <= 1'b0;
        end else if (!s_aw_delay_pending_q) begin
          s_aw_delay_q                               <= s_aw_delay_lfsr_q[1:0];
          s_aw_delay_pending_q                       <= 1'b1;
          s_aw_delay_modes_q[s_aw_delay_lfsr_q[1:0]] <= 1'b1;
          s_aw_delay_lfsr_q                          <= next_delay_lfsr(s_aw_delay_lfsr_q);
        end else if (s_aw_delay_q != 2'd0) begin
          s_aw_delay_q <= s_aw_delay_q - 1'b1;
        end else if (ga2d_axi4.awready) begin
          s_aw_delay_pending_q <= 1'b0;
        end

        if (!ga2d_axi4.wvalid || !s_aw_pending_q || s_bvalid_q ||
            s_residual_b_pending_q || s_residual_b_valid_q) begin
          s_w_delay_q         <= '0;
          s_w_delay_pending_q <= 1'b0;
        end else if (!s_w_delay_pending_q) begin
          s_w_delay_q                              <= s_w_delay_lfsr_q[1:0];
          s_w_delay_pending_q                      <= 1'b1;
          s_w_delay_modes_q[s_w_delay_lfsr_q[1:0]] <= 1'b1;
          s_w_delay_lfsr_q                         <= next_delay_lfsr(s_w_delay_lfsr_q);
        end else if (s_w_delay_q != 2'd0) begin
          s_w_delay_q <= s_w_delay_q - 1'b1;
        end else if (ga2d_axi4.wready) begin
          s_w_delay_pending_q <= 1'b0;
        end

        if (ga2d_axi4.arvalid && ga2d_axi4.arready) begin
          s_r_delay_q                              <= s_r_delay_lfsr_q[1:0];
          s_r_delay_pending_q                      <= 1'b1;
          s_r_delay_modes_q[s_r_delay_lfsr_q[1:0]] <= 1'b1;
          s_r_delay_lfsr_q                         <= next_delay_lfsr(s_r_delay_lfsr_q);
        end else if (s_rvalid_q && ga2d_axi4.rvalid && ga2d_axi4.rready) begin
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

        if (ga2d_axi4.wvalid && ga2d_axi4.wready && (s_wbeats_q == 9'd1)) begin
          s_b_delay_q                              <= s_b_delay_lfsr_q[1:0];
          s_b_delay_pending_q                      <= 1'b1;
          s_b_delay_modes_q[s_b_delay_lfsr_q[1:0]] <= 1'b1;
          s_b_delay_lfsr_q                         <= next_delay_lfsr(s_b_delay_lfsr_q);
        end else if (s_bvalid_q && ga2d_axi4.bvalid && ga2d_axi4.bready) begin
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

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_rvalid_q                <= 1'b0;
      s_rid_q                   <= '0;
      s_rresp_q                 <= 2'd0;
      s_raddr_q                 <= '0;
      s_rdata_q                 <= '0;
      s_rsize_q                 <= '0;
      s_rbeats_q                <= '0;
      s_residual_r_pending_q    <= 1'b0;
      s_residual_r_valid_q      <= 1'b0;
      s_residual_r_delay_q      <= '0;
      s_aw_pending_q            <= 1'b0;
      s_awaddr_q                <= '0;
      s_wbeats_q                <= '0;
      s_bvalid_q                <= 1'b0;
      s_bid_q                   <= '0;
      s_bresp_q                 <= 2'd0;
      s_residual_b_pending_q    <= 1'b0;
      s_residual_b_valid_q      <= 1'b0;
      s_residual_b_delay_q      <= '0;
      s_ar_count                <= 0;
      s_aw_count                <= 0;
      s_saw_arsize_0_q          <= 1'b0;
      s_saw_arsize_1_q          <= 1'b0;
      s_saw_arsize_2_q          <= 1'b0;
      s_saw_arlen_0_q           <= 1'b0;
      s_saw_arlen_14_q          <= 1'b0;
      s_saw_arlen_15_q          <= 1'b0;
      s_saw_awlen_0_q           <= 1'b0;
      s_saw_awlen_7_q           <= 1'b0;
      s_saw_awlen_14_q          <= 1'b0;
      s_saw_awlen_15_q          <= 1'b0;
      s_source_stop_seen_q      <= 1'b0;
      s_aw_allowed_after_stop_q <= 1'b0;
      s_ar_allowed_after_stop_q <= 1'b0;
      s_previous_awvalid_q      <= 1'b0;
      s_previous_arvalid_q      <= 1'b0;
    end else begin
      if (!source_stop_i) begin
        s_source_stop_seen_q      <= 1'b0;
        s_aw_allowed_after_stop_q <= 1'b0;
        s_ar_allowed_after_stop_q <= 1'b0;
      end else if (!s_source_stop_seen_q) begin
        s_source_stop_seen_q <= 1'b1;
        s_aw_allowed_after_stop_q <= s_previous_awvalid_q &&
                                    ga2d_axi4.awvalid && !ga2d_axi4.awready;
        s_ar_allowed_after_stop_q <= s_previous_arvalid_q &&
                                    ga2d_axi4.arvalid && !ga2d_axi4.arready;
      end
      if (s_clear_burst_observations_i) begin
        s_saw_arsize_0_q <= 1'b0;
        s_saw_arsize_1_q <= 1'b0;
        s_saw_arsize_2_q <= 1'b0;
        s_saw_arlen_0_q  <= 1'b0;
        s_saw_arlen_14_q <= 1'b0;
        s_saw_arlen_15_q <= 1'b0;
        s_saw_awlen_0_q  <= 1'b0;
        s_saw_awlen_7_q  <= 1'b0;
        s_saw_awlen_14_q <= 1'b0;
        s_saw_awlen_15_q <= 1'b0;
      end
      if (bridge_clear_busy_i) begin
        // Model the existing bridge clear boundary: it contains every queued
        // target-side response before the local source can be rearmed.
        s_rvalid_q             <= 1'b0;
        s_rbeats_q             <= '0;
        s_residual_r_pending_q <= 1'b0;
        s_residual_r_valid_q   <= 1'b0;
        s_residual_r_delay_q   <= '0;
        s_aw_pending_q         <= 1'b0;
        s_wbeats_q             <= '0;
        s_bvalid_q             <= 1'b0;
        s_residual_b_pending_q <= 1'b0;
        s_residual_b_valid_q   <= 1'b0;
        s_residual_b_delay_q   <= '0;
        s_previous_awvalid_q   <= 1'b0;
        s_previous_arvalid_q   <= 1'b0;
      end else begin
        if (ga2d_axi4.arvalid && ga2d_axi4.arready) begin
          if (source_stop_i &&
            ((!s_source_stop_seen_q && !s_previous_arvalid_q) ||
             (s_source_stop_seen_q && !s_ar_allowed_after_stop_q))) begin
            $fatal(1, "GA2D issued a new AR after source stop");
          end
          if ((ga2d_axi4.arlen != 8'd0) && (ga2d_axi4.arsize != 3'd3)) begin
            $fatal(1, "GA2D emitted a non-full-width read burst");
          end
          if ((ga2d_axi4.araddr & ((32'd1 << ga2d_axi4.arsize) - 1'b1)) != 32'd0) begin
            $fatal(1, "GA2D emitted an unaligned read transfer");
          end
          if ({1'b0, ga2d_axi4.araddr[11:0]} +
            (({5'd0, ga2d_axi4.arlen} + 13'd1) << ga2d_axi4.arsize) > 13'd4096) begin
            $fatal(1, "GA2D read burst crossed a 4 KiB boundary");
          end
          if (s_check_read_bounds_i &&
            !(((ga2d_axi4.araddr >= s_read_row0_start_i) &&
               ({1'b0, ga2d_axi4.araddr} +
                (({25'd0, ga2d_axi4.arlen} + 33'd1) << ga2d_axi4.arsize) <=
                {1'b0, s_read_row0_end_i})) ||
              ((ga2d_axi4.araddr >= s_read_row1_start_i) &&
               ({1'b0, ga2d_axi4.araddr} +
                (({25'd0, ga2d_axi4.arlen} + 33'd1) << ga2d_axi4.arsize) <=
                {1'b0, s_read_row1_end_i})))) begin
            $fatal(1, "GA2D read padding or crossed a logical source row");
          end
          s_rvalid_q <= 1'b1;
          s_rid_q    <= s_inject_bad_rid ? 3'd1 : 3'd0;
          s_rresp_q  <= s_inject_read_decerr ? 2'd3 : (s_inject_read_error ? 2'd2 : 2'd0);
          s_raddr_q  <= ga2d_axi4.araddr;
          s_rdata_q  <= memory_word(ga2d_axi4.araddr);
          s_rsize_q  <= ga2d_axi4.arsize;
          s_rbeats_q <= {1'b0, ga2d_axi4.arlen} + 1'b1;
          s_ar_count <= s_ar_count + 1;
          if (ga2d_axi4.arsize == 3'd0) begin
            s_saw_arsize_0_q <= 1'b1;
          end
          if (ga2d_axi4.arsize == 3'd1) begin
            s_saw_arsize_1_q <= 1'b1;
          end
          if (ga2d_axi4.arsize == 3'd2) begin
            s_saw_arsize_2_q <= 1'b1;
          end
          if (ga2d_axi4.arlen == 8'd14) begin
            s_saw_arlen_14_q <= 1'b1;
          end
          if (ga2d_axi4.arlen == 8'd0) begin
            s_saw_arlen_0_q <= 1'b1;
          end
          if (ga2d_axi4.arlen == 8'd15) begin
            s_saw_arlen_15_q <= 1'b1;
          end
        end else if (s_rvalid_q && ga2d_axi4.rvalid && ga2d_axi4.rready) begin
          if (s_rbeats_q == 9'd1) begin
            s_rvalid_q <= 1'b0;
            s_rbeats_q <= '0;
            if (s_schedule_residual_r_i) begin
              s_residual_r_pending_q <= 1'b1;
              s_residual_r_delay_q   <= 2'd2;
            end
          end else begin
            s_raddr_q  <= s_raddr_q + (32'd1 << s_rsize_q);
            s_rdata_q  <= memory_word(s_raddr_q + (32'd1 << s_rsize_q));
            s_rbeats_q <= s_rbeats_q - 1'b1;
          end
        end
        if (s_residual_r_pending_q) begin
          if (s_residual_r_delay_q == 2'd0) begin
            s_residual_r_pending_q <= 1'b0;
            s_residual_r_valid_q   <= 1'b1;
          end else begin
            s_residual_r_delay_q <= s_residual_r_delay_q - 1'b1;
          end
        end else if (s_residual_r_valid_q && ga2d_axi4.rvalid && ga2d_axi4.rready) begin
          s_residual_r_valid_q <= 1'b0;
        end
        if (ga2d_axi4.arvalid && ga2d_axi4.arready && s_source_stop_seen_q) begin
          s_ar_allowed_after_stop_q <= 1'b0;
        end

        if (ga2d_axi4.awvalid && ga2d_axi4.awready) begin
          if (source_stop_i &&
            ((!s_source_stop_seen_q && !s_previous_awvalid_q) ||
             (s_source_stop_seen_q && !s_aw_allowed_after_stop_q))) begin
            $fatal(1, "GA2D issued a new AW after source stop");
          end
          if (s_check_write_bounds_i && (ga2d_axi4.awlen != 8'd0) &&
            !(((ga2d_axi4.awaddr >= s_write_row0_start_i) &&
               ({1'b0, ga2d_axi4.awaddr} +
                (({25'd0, ga2d_axi4.awlen} + 33'd1) << 3) <=
                {1'b0, s_write_row0_end_i})) ||
              ((ga2d_axi4.awaddr >= s_write_row1_start_i) &&
               ({1'b0, ga2d_axi4.awaddr} +
                (({25'd0, ga2d_axi4.awlen} + 33'd1) << 3) <=
                {1'b0, s_write_row1_end_i})))) begin
            $fatal(1, "GA2D write burst crossed a logical destination row");
          end
          if (ga2d_axi4.awaddr[2:0] != 3'd0) begin
            $fatal(1, "GA2D emitted an unaligned AXI64 write address");
          end
          if ({1'b0, ga2d_axi4.awaddr[11:0]} +
            (({5'd0, ga2d_axi4.awlen} + 13'd1) << 3) > 13'd4096) begin
            $fatal(1, "GA2D write burst crossed a 4 KiB boundary");
          end
          s_aw_pending_q <= 1'b1;
          s_awaddr_q     <= ga2d_axi4.awaddr;
          s_wbeats_q     <= {1'b0, ga2d_axi4.awlen} + 1'b1;
          s_aw_count     <= s_aw_count + 1;
          if (ga2d_axi4.awlen == 8'd14) begin
            s_saw_awlen_14_q <= 1'b1;
          end
          if (ga2d_axi4.awlen == 8'd0) begin
            s_saw_awlen_0_q <= 1'b1;
          end
          if (ga2d_axi4.awlen == 8'd7) begin
            s_saw_awlen_7_q <= 1'b1;
          end
          if (ga2d_axi4.awlen == 8'd15) begin
            s_saw_awlen_15_q <= 1'b1;
          end
        end
        if (ga2d_axi4.wvalid && ga2d_axi4.wready) begin
          if (!s_aw_pending_q) begin
            $fatal(1, "GA2D issued W without an accepted AW");
          end
          if (ga2d_axi4.wlast != (s_wbeats_q == 9'd1)) begin
            $fatal(1, "GA2D emitted an incorrect WLAST sequence");
          end
          for (int unsigned lane = 0; lane < 8; lane++) begin
            if (ga2d_axi4.wstrb[lane]) begin
              if (s_check_write_bounds_i &&
                !((((s_awaddr_q + lane) >= s_write_row0_start_i) &&
                   ((s_awaddr_q + lane) < s_write_row0_end_i)) ||
                  (((s_awaddr_q + lane) >= s_write_row1_start_i) &&
                   ((s_awaddr_q + lane) < s_write_row1_end_i)))) begin
                $fatal(1, "GA2D wrote padding or crossed a logical destination row");
              end
              if ((s_awaddr_q + lane) < SramBase ||
                (s_awaddr_q + lane) >= (SramBase + MemoryBytes)) begin
                $fatal(1, "GA2D write escaped the SRAM BFM");
              end
              s_memory[(s_awaddr_q+lane)-SramBase] <= ga2d_axi4.wdata[lane*8+:8];
            end
          end
          if (s_wbeats_q == 9'd1) begin
            s_aw_pending_q <= 1'b0;
            s_wbeats_q     <= '0;
            s_bvalid_q     <= 1'b1;
            s_bid_q        <= s_inject_bad_bid ? 3'd1 : 3'd0;
            s_bresp_q      <= s_inject_write_decerr ? 2'd3 : (s_inject_write_error ? 2'd2 : 2'd0);
          end else begin
            s_awaddr_q <= s_awaddr_q + 32'd8;
            s_wbeats_q <= s_wbeats_q - 1'b1;
          end
        end else if (s_bvalid_q && ga2d_axi4.bvalid && ga2d_axi4.bready) begin
          s_bvalid_q <= 1'b0;
          if (s_schedule_residual_b_i) begin
            s_residual_b_pending_q <= 1'b1;
            s_residual_b_delay_q   <= 2'd2;
          end
        end
        if (s_residual_b_pending_q) begin
          if (s_residual_b_delay_q == 2'd0) begin
            s_residual_b_pending_q <= 1'b0;
            s_residual_b_valid_q   <= 1'b1;
          end else begin
            s_residual_b_delay_q <= s_residual_b_delay_q - 1'b1;
          end
        end else if (s_residual_b_valid_q && ga2d_axi4.bvalid && ga2d_axi4.bready) begin
          s_residual_b_valid_q <= 1'b0;
        end
        if (ga2d_axi4.awvalid && ga2d_axi4.awready && s_source_stop_seen_q) begin
          s_aw_allowed_after_stop_q <= 1'b0;
        end
        s_previous_awvalid_q <= ga2d_axi4.awvalid;
        s_previous_arvalid_q <= ga2d_axi4.arvalid;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_aw_stalled_q     <= 1'b0;
      s_awaddr_stalled_q <= '0;
      s_awlen_stalled_q  <= '0;
      s_awsize_stalled_q <= '0;
      s_w_stalled_q      <= 1'b0;
      s_wdata_stalled_q  <= '0;
      s_wstrb_stalled_q  <= '0;
      s_ar_stalled_q     <= 1'b0;
      s_araddr_stalled_q <= '0;
      s_arlen_stalled_q  <= '0;
      s_arsize_stalled_q <= '0;
    end else begin
      if (s_aw_stalled_q) begin
        if (!ga2d_axi4.awvalid || (ga2d_axi4.awaddr != s_awaddr_stalled_q) ||
            (ga2d_axi4.awlen != s_awlen_stalled_q) ||
            (ga2d_axi4.awsize != s_awsize_stalled_q)) begin
          $fatal(1, "GA2D AW payload changed while stalled");
        end
      end
      if (s_w_stalled_q) begin
        if (!ga2d_axi4.wvalid || (ga2d_axi4.wdata != s_wdata_stalled_q) ||
            (ga2d_axi4.wstrb != s_wstrb_stalled_q)) begin
          $fatal(1, "GA2D W payload changed while stalled");
        end
      end
      if (s_ar_stalled_q) begin
        if (!ga2d_axi4.arvalid || (ga2d_axi4.araddr != s_araddr_stalled_q) ||
            (ga2d_axi4.arlen != s_arlen_stalled_q) ||
            (ga2d_axi4.arsize != s_arsize_stalled_q)) begin
          $fatal(1, "GA2D AR payload changed while stalled");
        end
      end
      if (ga2d_axi4.awvalid) begin
        if ((ga2d_axi4.awid != 3'd0) || (ga2d_axi4.awlen > 8'd15) ||
            (ga2d_axi4.awsize != 3'd3) || (ga2d_axi4.awburst != 2'd1) ||
            (ga2d_axi4.awlock != 1'b0) || (ga2d_axi4.awcache != 4'd0) ||
            (ga2d_axi4.awprot != 3'd0) || (ga2d_axi4.awqos != 4'd0) ||
            (ga2d_axi4.awregion != 4'd0)) begin
          $fatal(1, "GA2D AW attributes violate the P4 AXI contract");
        end
      end
      if (ga2d_axi4.arvalid) begin
        if ((ga2d_axi4.arid != 3'd0) || (ga2d_axi4.arlen > 8'd15) ||
            (ga2d_axi4.arburst != 2'd1) || (ga2d_axi4.arlock != 1'b0) ||
            (ga2d_axi4.arcache != 4'd0) || (ga2d_axi4.arprot != 3'd0) ||
            (ga2d_axi4.arqos != 4'd0) || (ga2d_axi4.arregion != 4'd0)) begin
          $fatal(1, "GA2D AR attributes violate the P4 AXI contract");
        end
      end
      if (ga2d_axi4.wvalid && (ga2d_axi4.wstrb == 8'd0)) begin
        $fatal(1, "GA2D emitted a zero-strobe write");
      end
      s_aw_stalled_q     <= ga2d_axi4.awvalid && !ga2d_axi4.awready;
      s_awaddr_stalled_q <= ga2d_axi4.awaddr;
      s_awlen_stalled_q  <= ga2d_axi4.awlen;
      s_awsize_stalled_q <= ga2d_axi4.awsize;
      s_w_stalled_q      <= ga2d_axi4.wvalid && !ga2d_axi4.wready;
      s_wdata_stalled_q  <= ga2d_axi4.wdata;
      s_wstrb_stalled_q  <= ga2d_axi4.wstrb;
      s_ar_stalled_q     <= ga2d_axi4.arvalid && !ga2d_axi4.arready;
      s_araddr_stalled_q <= ga2d_axi4.araddr;
      s_arlen_stalled_q  <= ga2d_axi4.arlen;
      s_arsize_stalled_q <= ga2d_axi4.arsize;
    end
  end

  task automatic apb_write(input logic [11:0] offset_i, input logic [31:0] value_i,
                           input logic expected_error_i);
    begin
      @(negedge clk_i);
      apb4.paddr   = {20'd0, offset_i};
      apb4.pwrite  = 1'b1;
      apb4.pwdata  = value_i;
      apb4.pstrb   = 4'hf;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b1;
      @(posedge clk_i);
      #1;
      if (!apb4.pready || (apb4.pslverr != expected_error_i)) begin
        $fatal(1, "GA2D APB write response mismatch at %h", offset_i);
      end
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
    end
  endtask

  task automatic apb_read(input logic [11:0] offset_i, output logic [31:0] value_o);
    begin
      @(negedge clk_i);
      apb4.paddr   = {20'd0, offset_i};
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b1;
      @(posedge clk_i);
      #1;
      if (!apb4.pready || apb4.pslverr) begin
        $fatal(1, "GA2D APB read response mismatch at %h", offset_i);
      end
      value_o = apb4.prdata;
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  task automatic wait_for_terminal(input logic expected_done_i, input logic expected_error_i,
                                   input logic expected_abort_i);
    logic [31:0] status;
    logic        terminal_seen;
    begin
      terminal_seen = 1'b0;
      for (int unsigned attempt = 0; (attempt < 2000) && !terminal_seen; attempt++) begin
        apb_read(`APB4_GA2D__STATUS, status);
        if (!status[`APB4_GA2D__STATUS_BUSY] &&
            (status[`APB4_GA2D__STATUS_DONE] ||
             status[`APB4_GA2D__STATUS_ERROR] ||
             status[`APB4_GA2D__STATUS_ABORTED])) begin
          if ((status[`APB4_GA2D__STATUS_DONE] != expected_done_i) ||
              (status[`APB4_GA2D__STATUS_ERROR] != expected_error_i) ||
              (status[`APB4_GA2D__STATUS_ABORTED] != expected_abort_i)) begin
            $fatal(1, "GA2D terminal status mismatch: %h", status);
          end
          terminal_seen = 1'b1;
        end
      end
      if (!terminal_seen) begin
        $fatal(1, "GA2D DMA terminal state timed out");
      end
    end
  endtask

  task automatic wait_for_runtime_error(output logic [31:0] status_o);
    logic error_seen;
    begin
      error_seen = 1'b0;
      status_o   = '0;
      for (int unsigned attempt = 0; (attempt < 2000) && !error_seen; attempt++) begin
        apb_read(`APB4_GA2D__STATUS, status_o);
        if (status_o[`APB4_GA2D__STATUS_ERROR]) begin
          error_seen = 1'b1;
        end
      end
      if (!error_seen) begin
        $fatal(1, "GA2D runtime error was not reported");
      end
    end
  endtask

  task automatic clear_memory(input logic [7:0] value_i);
    begin
      for (int unsigned index = 0; index < MemoryBytes; index++) begin
        s_memory[index] = value_i;
      end
    end
  endtask

  task automatic clear_burst_observations;
    begin
      @(negedge clk_i);
      s_clear_burst_observations_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      s_clear_burst_observations_i = 1'b0;
    end
  endtask

  function automatic logic [15:0] rgb565_fill_pixel(input logic [31:0] color_i);
    return {color_i[23:19], color_i[15:10], color_i[7:3]};
  endfunction

  function automatic logic [31:0] fill_pixel(input logic [2:0] format_i,
                                             input logic [31:0] color_i);
    logic [15:0] rgb565;
    begin
      rgb565 = rgb565_fill_pixel(color_i);
      unique case (format_i)
        `APB4_GA2D__FORMAT_RGB565:   return {16'd0, rgb565};
        `APB4_GA2D__FORMAT_RGB888:   return {8'd0, color_i[7:0], color_i[15:8], color_i[23:16]};
        `APB4_GA2D__FORMAT_XRGB8888: return {8'hff, color_i[23:0]};
        default:                     return color_i;
      endcase
    end
  endfunction

  task automatic configure_fill(input logic [2:0] format_i, input logic [15:0] width_i,
                                input logic [15:0] height_i, input logic [31:0] destination_i,
                                input logic [31:0] pitch_i, input logic [31:0] color_i);
    begin
      apb_write(`APB4_GA2D__JOB_CONFIG, 32'd0, 1'b0);
      apb_write(`APB4_GA2D__COLOR, color_i, 1'b0);
      apb_write(`APB4_GA2D__SIZE, {height_i, width_i}, 1'b0);
      apb_write(`APB4_GA2D__DST_ADDRESS, destination_i, 1'b0);
      apb_write(`APB4_GA2D__DST_PITCH, pitch_i, 1'b0);
      apb_write(`APB4_GA2D__DST_FORMAT, {29'd0, format_i}, 1'b0);
    end
  endtask

  task automatic configure_copy(
      input logic [2:0] format_i, input logic [15:0] width_i, input logic [15:0] height_i,
      input logic [31:0] foreground_i, input logic [31:0] foreground_pitch_i,
      input logic [31:0] destination_i, input logic [31:0] destination_pitch_i);
    begin
      apb_write(`APB4_GA2D__JOB_CONFIG, 32'd1, 1'b0);
      apb_write(`APB4_GA2D__SIZE, {height_i, width_i}, 1'b0);
      apb_write(`APB4_GA2D__FG_ADDRESS, foreground_i, 1'b0);
      apb_write(`APB4_GA2D__FG_PITCH, foreground_pitch_i, 1'b0);
      apb_write(`APB4_GA2D__FG_FORMAT, {29'd0, format_i}, 1'b0);
      apb_write(`APB4_GA2D__DST_ADDRESS, destination_i, 1'b0);
      apb_write(`APB4_GA2D__DST_PITCH, destination_pitch_i, 1'b0);
      apb_write(`APB4_GA2D__DST_FORMAT, {29'd0, format_i}, 1'b0);
    end
  endtask

  task automatic start_job;
    begin
      apb_write(`APB4_GA2D__COMMAND, 32'h0000_0001, 1'b0);
    end
  endtask

  task automatic read_snapshot64(input logic [11:0] low_offset_i, input logic [11:0] high_offset_i,
                                 output logic [63:0] value_o);
    logic [31:0] low;
    logic [31:0] high;
    begin
      apb_read(low_offset_i, low);
      apb_read(high_offset_i, high);
      value_o = {high, low};
    end
  endtask

  task automatic check_terminal_counters(input logic [63:0] expected_read_bytes_i,
                                         input logic [63:0] expected_write_bytes_i,
                                         input logic [15:0] expected_lines_i);
    logic [63:0] read_bytes;
    logic [63:0] write_bytes;
    logic [31:0] lines;
    begin
      apb_write(`APB4_GA2D__PERF_SNAPSHOT, 32'h0000_0001, 1'b0);
      read_snapshot64(`APB4_GA2D__SNAP_READ_BYTES_LO, `APB4_GA2D__SNAP_READ_BYTES_HI, read_bytes);
      read_snapshot64(`APB4_GA2D__SNAP_WRITE_BYTES_LO, `APB4_GA2D__SNAP_WRITE_BYTES_HI,
                      write_bytes);
      apb_read(`APB4_GA2D__SNAP_LINES_DONE, lines);
      if ((read_bytes != expected_read_bytes_i) ||
          (write_bytes != expected_write_bytes_i) ||
          (lines[15:0] != expected_lines_i)) begin
        $fatal(1, "GA2D terminal accounting mismatch: read=%h write=%h lines=%h", read_bytes,
               write_bytes, lines);
      end
    end
  endtask

  task automatic check_error_code(input logic [6:0] expected_code_i);
    logic [31:0] error_status;
    begin
      apb_read(`APB4_GA2D__ERROR_STATUS, error_status);
      if (!error_status[`APB4_GA2D__ERROR_STATUS_VALID] ||
          (error_status[`APB4_GA2D__ERROR_STATUS_CODE+:7] != expected_code_i)) begin
        $fatal(1, "GA2D error code mismatch: expected=%h actual=%h", expected_code_i,
               error_status[`APB4_GA2D__ERROR_STATUS_CODE+:7]);
      end
    end
  endtask

  task automatic check_error_axi_response(input logic [1:0] expected_response_i);
    logic [31:0] error_status;
    begin
      apb_read(`APB4_GA2D__ERROR_STATUS, error_status);
      if (error_status[`APB4_GA2D__ERROR_STATUS_AXI_RESPONSE+:2] != expected_response_i) begin
        $fatal(1, "GA2D AXI error response mismatch: expected=%h actual=%h", expected_response_i,
               error_status[`APB4_GA2D__ERROR_STATUS_AXI_RESPONSE+:2]);
      end
    end
  endtask

  task automatic clear_first_error;
    logic [31:0] error_status;
    begin
      apb_write(`APB4_GA2D__ERROR_STATUS, 32'h0000_0001, 1'b0);
      apb_read(`APB4_GA2D__ERROR_STATUS, error_status);
      if (error_status[`APB4_GA2D__ERROR_STATUS_VALID]) begin
        $fatal(1, "GA2D ERROR_STATUS W1C did not clear the first-error record");
      end
    end
  endtask

  task automatic check_done_event;
    logic [31:0] irq_state;
    begin
      repeat (2) @(posedge clk_i);
      apb_read(`APB4_GA2D__IRQ_STATE, irq_state);
      if (!irq_state[`APB4_GA2D__IRQ_DONE]) begin
        $fatal(1, "GA2D completion did not latch IRQ_STATE.DONE");
      end
      if (!irq_o) begin
        $fatal(1, "GA2D completion did not assert the enabled raw IRQ");
      end
      apb_write(`APB4_GA2D__IRQ_STATE, {29'd0, IrqDoneMask}, 1'b0);
      apb_read(`APB4_GA2D__IRQ_STATE, irq_state);
      if (irq_state[`APB4_GA2D__IRQ_DONE] || irq_o) begin
        $fatal(1, "GA2D completion IRQ_STATE.DONE W1C did not clear");
      end
    end
  endtask

  task automatic check_error_event;
    logic [31:0] irq_state;
    begin
      repeat (2) @(posedge clk_i);
      apb_read(`APB4_GA2D__IRQ_STATE, irq_state);
      if (!irq_state[`APB4_GA2D__IRQ_ERROR]) begin
        $fatal(1, "GA2D error did not latch IRQ_STATE.ERROR");
      end
      apb_write(`APB4_GA2D__IRQ_STATE, {29'd0, IrqErrorMask}, 1'b0);
      apb_read(`APB4_GA2D__IRQ_STATE, irq_state);
      if (irq_state[`APB4_GA2D__IRQ_ERROR]) begin
        $fatal(1, "GA2D error IRQ_STATE.ERROR W1C did not clear");
      end
    end
  endtask

  task automatic check_abort_done_event;
    logic [31:0] irq_state;
    begin
      repeat (2) @(posedge clk_i);
      apb_read(`APB4_GA2D__IRQ_STATE, irq_state);
      if (!irq_state[`APB4_GA2D__IRQ_ABORT_DONE]) begin
        $fatal(1, "GA2D abort did not latch IRQ_STATE.ABORT_DONE");
      end
      apb_write(`APB4_GA2D__IRQ_STATE, {29'd0, IrqAbortDoneMask}, 1'b0);
      apb_read(`APB4_GA2D__IRQ_STATE, irq_state);
      if (irq_state[`APB4_GA2D__IRQ_ABORT_DONE]) begin
        $fatal(1, "GA2D abort IRQ_STATE.ABORT_DONE W1C did not clear");
      end
    end
  endtask

  task automatic check_first_error_immutability;
    logic [31:0] first_error_status;
    logic [31:0] first_error_address;
    logic [31:0] error_status;
    logic [31:0] error_address;
    begin
      configure_fill(`APB4_GA2D__FORMAT_RGB565, 16'd2, 16'd1, SramBase + MemoryBytes - 2, 32'd4,
                     32'hffff_ffff);
      start_job();
      wait_for_terminal(1'b0, 1'b1, 1'b0);
      apb_read(`APB4_GA2D__ERROR_STATUS, first_error_status);
      apb_read(`APB4_GA2D__ERROR_ADDRESS, first_error_address);
      if ((first_error_status[`APB4_GA2D__ERROR_STATUS_CODE+:7] !=
           `APB4_GA2D__ERROR_ADDRESS_RANGE) ||
          (first_error_address != (SramBase + MemoryBytes - 2))) begin
        $fatal(1, "GA2D first validation error record mismatch");
      end
      check_error_event();

      s_inject_write_error = 1'b1;
      configure_fill(`APB4_GA2D__FORMAT_RGB565, 16'd2, 16'd1, SramBase + 32'h1600, 32'd4,
                     32'h8012_3456);
      start_job();
      wait_for_terminal(1'b0, 1'b1, 1'b0);
      apb_read(`APB4_GA2D__ERROR_STATUS, error_status);
      apb_read(`APB4_GA2D__ERROR_ADDRESS, error_address);
      if ((error_status != first_error_status) || (error_address != first_error_address)) begin
        $fatal(1, "GA2D START overwrote an uncleared first-error record");
      end

      clear_first_error();
      configure_fill(`APB4_GA2D__FORMAT_RGB565, 16'd2, 16'd1, SramBase + 32'h1640, 32'd4,
                     32'h8012_3456);
      start_job();
      wait_for_terminal(1'b0, 1'b1, 1'b0);
      check_error_code(`APB4_GA2D__ERROR_AXI_WRITE);
      s_inject_write_error = 1'b0;
      clear_first_error();
    end
  endtask

  task automatic run_fill_case(input logic [2:0] format_i, input int unsigned bytes_per_pixel_i,
                               input logic [31:0] destination_i, input logic [31:0] pitch_i,
                               input logic [31:0] color_i, input logic [31:0] pixel_i);
    logic [31:0] row;
    begin
      clear_memory(8'hd3);
      s_check_write_bounds_i = 1'b1;
      s_write_row0_start_i   = destination_i;
      s_write_row0_end_i     = destination_i + 3 * bytes_per_pixel_i;
      s_write_row1_start_i   = destination_i + pitch_i;
      s_write_row1_end_i     = destination_i + pitch_i + 3 * bytes_per_pixel_i;
      configure_fill(format_i, 16'd3, 16'd2, destination_i, pitch_i, color_i);
      start_job();
      wait_for_terminal(1'b1, 1'b0, 1'b0);
      check_done_event();
      s_check_write_bounds_i = 1'b0;
      for (int unsigned line = 0; line < 2; line++) begin
        row = destination_i + (line * pitch_i);
        if (memory_byte(row - 1'b1) != 8'hd3) begin
          $fatal(1, "GA2D FILL changed the leading guard");
        end
        for (int unsigned pixel = 0; pixel < 3; pixel++) begin
          for (int unsigned byte_index = 0; byte_index < bytes_per_pixel_i; byte_index++) begin
            if (memory_byte(
                    row + pixel * bytes_per_pixel_i + byte_index
                ) != pixel_i[byte_index*8+:8]) begin
              $fatal(1, "GA2D FILL pixel byte mismatch");
            end
          end
        end
        for (int unsigned padding = 3 * bytes_per_pixel_i; padding < pitch_i; padding++) begin
          if (memory_byte(row + padding) != 8'hd3) begin
            $fatal(1, "GA2D FILL changed row padding");
          end
        end
      end
    end
  endtask

  task automatic run_copy_case(input logic [2:0] format_i, input int unsigned bytes_per_pixel_i,
                               input logic [31:0] foreground_i, input logic [31:0] destination_i);
    logic        [31:0] row_bytes;
    logic        [31:0] pitch;
    logic        [31:0] source_row;
    logic        [31:0] destination_row;
    int unsigned        ar_count_before;
    int unsigned        aw_count_before;
    begin
      clear_memory(8'hc7);
      ar_count_before = s_ar_count;
      aw_count_before = s_aw_count;
      row_bytes       = 3 * bytes_per_pixel_i;
      pitch           = row_bytes + bytes_per_pixel_i;
      for (int unsigned line = 0; line < 2; line++) begin
        source_row = foreground_i + (line * pitch);
        for (int unsigned byte_index = 0; byte_index < row_bytes; byte_index++) begin
          s_memory[(source_row + byte_index) - SramBase] =
              (8'h31 * line) + byte_index + bytes_per_pixel_i;
        end
      end
      s_check_read_bounds_i  = 1'b1;
      s_read_row0_start_i    = foreground_i;
      s_read_row0_end_i      = foreground_i + row_bytes;
      s_read_row1_start_i    = foreground_i + pitch;
      s_read_row1_end_i      = foreground_i + pitch + row_bytes;
      s_check_write_bounds_i = 1'b1;
      s_write_row0_start_i   = destination_i;
      s_write_row0_end_i     = destination_i + row_bytes;
      s_write_row1_start_i   = destination_i + pitch;
      s_write_row1_end_i     = destination_i + pitch + row_bytes;
      configure_copy(format_i, 16'd3, 16'd2, foreground_i, pitch, destination_i, pitch);
      start_job();
      wait_for_terminal(1'b1, 1'b0, 1'b0);
      check_done_event();
      s_check_read_bounds_i  = 1'b0;
      s_check_write_bounds_i = 1'b0;
      for (int unsigned line = 0; line < 2; line++) begin
        source_row      = foreground_i + (line * pitch);
        destination_row = destination_i + (line * pitch);
        if (memory_byte(destination_row - 1'b1) != 8'hc7) begin
          $fatal(1, "GA2D COPY changed the leading guard");
        end
        for (int unsigned byte_index = 0; byte_index < row_bytes; byte_index++) begin
          if (memory_byte(
                  destination_row + byte_index
              ) != memory_byte(
                  source_row + byte_index
              )) begin
            $fatal(
                1,
                "GA2D COPY byte mismatch: line=%0d byte=%0d source=%h value=%h destination=%h value=%h ar=%0d aw=%0d",
                line, byte_index, source_row + byte_index, memory_byte(source_row + byte_index),
                destination_row + byte_index, memory_byte(destination_row + byte_index),
                s_ar_count - ar_count_before, s_aw_count - aw_count_before);
          end
        end
        for (int unsigned padding = row_bytes; padding < pitch; padding++) begin
          if (memory_byte(destination_row + padding) != 8'hc7) begin
            $fatal(1, "GA2D COPY changed row padding");
          end
        end
      end
    end
  endtask

  task automatic enable_random_delays;
    begin
      @(negedge clk_i);
      s_random_delay_coverage_clear_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      s_random_delay_coverage_clear_i = 1'b0;
      s_random_delays_i               = 1'b1;
    end
  endtask

  task automatic reseed_random_delays(input logic [31:0] seed_i);
    begin
      @(negedge clk_i);
      s_random_delay_seed_i   = seed_i;
      s_random_delay_reseed_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      s_random_delay_reseed_i = 1'b0;
    end
  endtask

  task automatic check_random_delay_coverage;
    begin
      @(negedge clk_i);
      s_random_delays_i = 1'b0;
      @(posedge clk_i);
      if ((s_ar_delay_modes_q != 4'hf) || (s_aw_delay_modes_q != 4'hf) ||
          (s_w_delay_modes_q != 4'hf) || (s_r_delay_modes_q != 4'hf) ||
          (s_b_delay_modes_q != 4'hf)) begin
        $fatal(1, "GA2D randomized campaign did not cover every independent AXI delay mode");
      end
    end
  endtask

  task automatic wait_for_protocol_quarantine(input logic read_i);
    logic [31:0] status;
    logic        quarantine_seen;
    begin
      wait_for_runtime_error(status);
      if (!status[`APB4_GA2D__STATUS_DRAINING] ||
          !status[`APB4_GA2D__STATUS_RECOVERY_REQUIRED]) begin
        $fatal(1, "GA2D protocol error did not enter recovery drain");
      end
      check_error_code(`APB4_GA2D__ERROR_AXI_PROTOCOL);
      apb_write(`APB4_GA2D__COMMAND, 32'h0000_0001, 1'b1);
      quarantine_seen = 1'b0;
      for (int unsigned attempt = 0; (attempt < 64) && !quarantine_seen; attempt++) begin
        @(posedge clk_i);
        if (read_i) begin
          quarantine_seen = ga2d_axi4.rvalid && !ga2d_axi4.rready;
        end else begin
          quarantine_seen = ga2d_axi4.bvalid && !ga2d_axi4.bready;
        end
      end
      if (!quarantine_seen) begin
        $fatal(1, "GA2D accepted a residual malformed-response channel before recovery");
      end
    end
  endtask

  task automatic complete_protocol_recovery;
    logic [31:0] status;
    logic        recovered;
    begin
      @(negedge clk_i);
      data_ready_i        = 1'b0;
      bridge_clear_busy_i = 1'b1;
      bridge_epoch_i      = bridge_epoch_i + 1'b1;
      repeat (3) @(posedge clk_i);
      @(negedge clk_i);
      bridge_clear_busy_i = 1'b0;
      repeat (2) @(posedge clk_i);
      @(negedge clk_i);
      data_ready_i = 1'b1;
      recovered    = 1'b0;
      for (int unsigned attempt = 0; (attempt < 128) && !recovered; attempt++) begin
        apb_read(`APB4_GA2D__STATUS, status);
        recovered = !status[`APB4_GA2D__STATUS_BUSY] &&
                    !status[`APB4_GA2D__STATUS_DRAINING] &&
                    !status[`APB4_GA2D__STATUS_RECOVERY_REQUIRED];
      end
      if (!recovered || !core_safe_idle_o) begin
        $fatal(1, "GA2D protocol recovery did not safely contain the old local ID");
      end
    end
  endtask

  task automatic run_read_protocol_quarantine(input logic bad_id_i);
    begin
      clear_memory(8'hc7);
      configure_copy(`APB4_GA2D__FORMAT_RGB565, 16'd4, 16'd1, SramBase + 32'h1200, 32'd8,
                     SramBase + 32'h1400, 32'd8);
      s_inject_bad_rid        = bad_id_i;
      s_inject_bad_rlast      = !bad_id_i;
      s_schedule_residual_r_i = 1'b1;
      start_job();
      wait_for_protocol_quarantine(1'b1);
      s_inject_bad_rid        = 1'b0;
      s_inject_bad_rlast      = 1'b0;
      s_schedule_residual_r_i = 1'b0;
      complete_protocol_recovery();
      clear_first_error();
      run_copy_case(`APB4_GA2D__FORMAT_RGB565, 2, SramBase + 32'h1200, SramBase + 32'h1400);
    end
  endtask

  task automatic run_write_protocol_quarantine;
    begin
      clear_memory(8'hd3);
      configure_fill(`APB4_GA2D__FORMAT_RGB565, 16'd3, 16'd1, SramBase + 32'h1600, 32'd8,
                     32'h8012_3456);
      s_inject_bad_bid        = 1'b1;
      s_schedule_residual_b_i = 1'b1;
      start_job();
      wait_for_protocol_quarantine(1'b0);
      s_inject_bad_bid        = 1'b0;
      s_schedule_residual_b_i = 1'b0;
      complete_protocol_recovery();
      clear_first_error();
      run_fill_case(`APB4_GA2D__FORMAT_RGB565, 2, SramBase + 32'h1600, 32'd8, 32'h8012_3456,
                    32'h0000_11aa);
    end
  endtask

  task automatic hold_after_first_read_response;
    logic response_seen;
    begin
      response_seen = 1'b0;
      for (int unsigned attempt = 0; (attempt < 256) && !response_seen; attempt++) begin
        @(posedge clk_i);
        response_seen = ga2d_axi4.rvalid && ga2d_axi4.rready;
      end
      if (!response_seen) begin
        $fatal(1, "GA2D did not return the first response for the error-drain test");
      end
      @(negedge clk_i);
      s_hold_r_i = 1'b1;
    end
  endtask

  task automatic check_error_and_abort_done_events;
    logic [31:0] irq_state;
    begin
      repeat (2) @(posedge clk_i);
      apb_read(`APB4_GA2D__IRQ_STATE, irq_state);
      if (!irq_state[`APB4_GA2D__IRQ_ERROR] || !irq_state[`APB4_GA2D__IRQ_ABORT_DONE]) begin
        $fatal(1, "GA2D error drain did not retain ERROR and ABORT_DONE IRQ events");
      end
      apb_write(`APB4_GA2D__IRQ_STATE, {29'd0, IrqErrorMask | IrqAbortDoneMask}, 1'b0);
    end
  endtask

  task automatic run_abort_during_error_drain(input logic resource_stop_i);
    logic [31:0] status;
    begin
      clear_memory(8'ha5);
      configure_copy(`APB4_GA2D__FORMAT_RGB565, 16'd8, 16'd1, SramBase + 32'h1200, 32'd16,
                     SramBase + 32'h1400, 32'd16);
      apb_write(`APB4_GA2D__TIMEOUT_CYCLES, 32'd1024, 1'b0);
      s_inject_read_error = 1'b1;
      start_job();
      hold_after_first_read_response();
      wait_for_runtime_error(status);
      if (!status[`APB4_GA2D__STATUS_DRAINING]) begin
        $fatal(1, "GA2D read error did not remain in drain before abort");
      end
      if (resource_stop_i) begin
        @(negedge clk_i);
        resource_quiesce_i = 1'b1;
        source_stop_i      = 1'b1;
        @(posedge clk_i);
      end else begin
        apb_write(`APB4_GA2D__COMMAND, 32'h0000_0002, 1'b0);
      end
      s_inject_read_error = 1'b0;
      @(negedge clk_i);
      s_hold_r_i = 1'b0;
      wait_for_terminal(1'b0, 1'b1, 1'b1);
      check_error_code(`APB4_GA2D__ERROR_AXI_READ);
      check_error_and_abort_done_events();
      if (resource_stop_i) begin
        @(negedge clk_i);
        block_ack_i        = 1'b1;
        resource_quiesce_i = 1'b0;
        source_stop_i      = 1'b0;
        @(posedge clk_i);
        @(negedge clk_i);
        block_ack_i = 1'b0;
      end
      clear_first_error();
    end
  endtask

  task automatic run_fill_burst_case(input logic [15:0] width_i, input logic [31:0] destination_i,
                                     input logic [7:0] expected_awlen_i);
    logic [15:0] pixel;
    logic [31:0] row_bytes;
    begin
      pixel     = rgb565_fill_pixel(32'h8012_3456);
      row_bytes = {16'd0, width_i} * 32'd2;
      clear_memory(8'hd3);
      clear_burst_observations();
      s_check_write_bounds_i = 1'b1;
      s_write_row0_start_i   = destination_i;
      s_write_row0_end_i     = destination_i + row_bytes;
      s_write_row1_start_i   = '0;
      s_write_row1_end_i     = '0;
      configure_fill(`APB4_GA2D__FORMAT_RGB565, width_i, 16'd1, destination_i, row_bytes,
                     32'h8012_3456);
      start_job();
      wait_for_terminal(1'b1, 1'b0, 1'b0);
      s_check_write_bounds_i = 1'b0;
      check_terminal_counters(64'd0, {32'd0, row_bytes}, 16'd1);
      if ((expected_awlen_i == 8'd14) && !s_saw_awlen_14_q) begin
        $fatal(1, "GA2D did not issue the required 15-beat write burst");
      end
      if ((expected_awlen_i == 8'd0) && !s_saw_awlen_0_q) begin
        $fatal(1, "GA2D did not issue the required one-beat write burst");
      end
      if ((expected_awlen_i == 8'd15) && !s_saw_awlen_15_q) begin
        $fatal(1, "GA2D did not issue the required 16-beat write burst");
      end
      if ((expected_awlen_i == 8'd7) && !s_saw_awlen_7_q) begin
        $fatal(1, "GA2D did not split a 4 KiB-crossing row at eight beats");
      end
      if (memory_byte(destination_i - 1'b1) != 8'hd3) begin
        $fatal(1, "GA2D burst FILL changed a leading guard byte");
      end
      for (int unsigned byte_index = 0; byte_index < row_bytes; byte_index++) begin
        if (memory_byte(destination_i + byte_index) != pixel[(byte_index%2)*8+:8]) begin
          $fatal(1, "GA2D burst FILL byte mismatch");
        end
      end
      if (((destination_i + row_bytes) < (SramBase + MemoryBytes)) && (memory_byte(
              destination_i + row_bytes
          ) != 8'hd3)) begin
        $fatal(1, "GA2D burst FILL changed a trailing guard byte");
      end
    end
  endtask

  task automatic run_copy_burst_case(input logic [15:0] width_i, input logic [31:0] foreground_i,
                                     input logic [31:0] destination_i,
                                     input logic [7:0] expected_len_i);
    logic [31:0] row_bytes;
    begin
      row_bytes = {16'd0, width_i} * 32'd2;
      clear_memory(8'hc7);
      for (int unsigned byte_index = 0; byte_index < row_bytes; byte_index++) begin
        s_memory[(foreground_i+byte_index)-SramBase] = 8'h53 + byte_index;
      end
      clear_burst_observations();
      s_check_read_bounds_i  = 1'b1;
      s_read_row0_start_i    = foreground_i;
      s_read_row0_end_i      = foreground_i + row_bytes;
      s_read_row1_start_i    = '0;
      s_read_row1_end_i      = '0;
      s_check_write_bounds_i = 1'b1;
      s_write_row0_start_i   = destination_i;
      s_write_row0_end_i     = destination_i + row_bytes;
      s_write_row1_start_i   = '0;
      s_write_row1_end_i     = '0;
      configure_copy(`APB4_GA2D__FORMAT_RGB565, width_i, 16'd1, foreground_i, row_bytes,
                     destination_i, row_bytes);
      start_job();
      wait_for_terminal(1'b1, 1'b0, 1'b0);
      s_check_read_bounds_i  = 1'b0;
      s_check_write_bounds_i = 1'b0;
      check_terminal_counters({32'd0, row_bytes}, {32'd0, row_bytes}, 16'd1);
      if ((expected_len_i == 8'd14) && (!s_saw_arlen_14_q || !s_saw_awlen_14_q)) begin
        $fatal(1, "GA2D did not issue the required 15-beat COPY bursts");
      end
      if ((expected_len_i == 8'd0) && (!s_saw_arlen_0_q || !s_saw_awlen_0_q)) begin
        $fatal(1, "GA2D did not issue the required one-beat COPY bursts");
      end
      if ((expected_len_i == 8'd15) && (!s_saw_arlen_15_q || !s_saw_awlen_15_q)) begin
        $fatal(1, "GA2D did not issue the required 16-beat COPY bursts");
      end
      if (memory_byte(destination_i - 1'b1) != 8'hc7) begin
        $fatal(1, "GA2D burst COPY changed a leading guard byte");
      end
      for (int unsigned byte_index = 0; byte_index < row_bytes; byte_index++) begin
        if (memory_byte(destination_i + byte_index) != memory_byte(foreground_i + byte_index)) begin
          $fatal(1, "GA2D burst COPY byte mismatch");
        end
      end
      if (memory_byte(destination_i + row_bytes) != 8'hc7) begin
        $fatal(1, "GA2D burst COPY changed a trailing guard byte");
      end
    end
  endtask

  task automatic run_random_job(input logic fill_i, input logic [2:0] format_i,
                                input logic [31:0] random_i, input int unsigned job_i);
    logic        [31:0] foreground;
    logic        [31:0] destination;
    logic        [31:0] pixel;
    logic        [31:0] source_row;
    logic        [31:0] destination_row;
    logic        [15:0] width;
    logic        [15:0] height;
    int unsigned        bytes_per_pixel;
    int unsigned        row_bytes;
    int unsigned        foreground_pitch;
    int unsigned        destination_pitch;
    begin
      width  = (random_i[15:12] % 8) + 1;
      height = (random_i[18:16] % 3) + 1;
      unique case (format_i)
        `APB4_GA2D__FORMAT_RGB565: begin
          bytes_per_pixel = 2;
          foreground      = SramBase + 32'h1000 + ((job_i % 16) * 128) + ((random_i[5:4] % 4) * 2);
          destination     = SramBase + 32'h5000 + ((job_i % 16) * 128) + ((random_i[7:6] % 4) * 2);
        end
        `APB4_GA2D__FORMAT_RGB888: begin
          bytes_per_pixel = 3;
          foreground      = SramBase + 32'h1000 + ((job_i % 16) * 128) + (random_i[2:0] % 8);
          destination     = SramBase + 32'h5000 + ((job_i % 16) * 128) + (random_i[10:8] % 8);
        end
        default: begin
          bytes_per_pixel = 4;
          foreground      = SramBase + 32'h1000 + ((job_i % 16) * 128) + ((random_i[3] % 2) * 4);
          destination     = SramBase + 32'h5000 + ((job_i % 16) * 128) + ((random_i[11] % 2) * 4);
        end
      endcase
      row_bytes         = width * bytes_per_pixel;
      foreground_pitch  = row_bytes + bytes_per_pixel * (random_i[21:20] % 4);
      destination_pitch = row_bytes + bytes_per_pixel * (random_i[23:22] % 4);
      pixel             = fill_pixel(format_i, random_i);
      for (int unsigned line = 0; line < height; line++) begin
        source_row      = foreground + line * foreground_pitch;
        destination_row = destination + line * destination_pitch;
        if (line == 0) begin
          s_memory[(destination_row-SramBase)-1] = 8'hc7;
        end
        for (int unsigned byte_index = 0; byte_index < row_bytes; byte_index++) begin
          s_memory[(destination_row-SramBase)+byte_index] = 8'hc7;
          s_memory[(source_row - SramBase) + byte_index] =
              random_i[(byte_index % 4)*8+:8] ^ line[7:0] ^ byte_index[7:0];
        end
        for (int unsigned padding = row_bytes; padding < foreground_pitch; padding++) begin
          s_memory[(source_row-SramBase)+padding] = 8'hc7;
        end
        for (int unsigned padding = row_bytes; padding < destination_pitch; padding++) begin
          s_memory[(destination_row-SramBase)+padding] = 8'hc7;
        end
      end
      s_memory[(destination+((height-1'b1)*destination_pitch)+row_bytes)-SramBase] = 8'hc7;
      if (fill_i) begin
        configure_fill(format_i, width, height, destination, destination_pitch, random_i);
      end else begin
        configure_copy(format_i, width, height, foreground, foreground_pitch, destination,
                       destination_pitch);
      end
      start_job();
      wait_for_terminal(1'b1, 1'b0, 1'b0);
      if (memory_byte(destination - 1'b1) != 8'hc7) begin
        $fatal(1, "GA2D randomized job changed a leading guard byte");
      end
      for (int unsigned line = 0; line < height; line++) begin
        source_row      = foreground + line * foreground_pitch;
        destination_row = destination + line * destination_pitch;
        for (int unsigned byte_index = 0; byte_index < row_bytes; byte_index++) begin
          if (fill_i) begin
            if (memory_byte(
                    destination_row + byte_index
                ) != pixel[(byte_index%bytes_per_pixel)*8+:8]) begin
              $fatal(1, "GA2D randomized FILL byte mismatch");
            end
          end else if (memory_byte(
                  destination_row + byte_index
              ) != memory_byte(
                  source_row + byte_index
              )) begin
            $fatal(1, "GA2D randomized COPY byte mismatch");
          end
        end
        for (int unsigned padding = row_bytes; padding < destination_pitch; padding++) begin
          if (memory_byte(destination_row + padding) != 8'hc7) begin
            $fatal(1, "GA2D randomized job changed destination padding");
          end
        end
      end
      if (memory_byte(
              destination + ((height - 1'b1) * destination_pitch) + row_bytes
          ) != 8'hc7) begin
        $fatal(1, "GA2D randomized job changed a trailing guard byte");
      end
    end
  endtask

  task automatic run_random_campaign;
    logic        [31:0] random_value;
    logic        [ 2:0] format;
    logic        [ 9:0] seeds_seen;
    int unsigned        completed;
    begin
      completed  = 0;
      seeds_seen = '0;
      enable_random_delays();
      for (int unsigned seed = 0; seed < 10; seed++) begin
        reseed_random_delays(32'h9e37_79b9 ^ seed);
        seeds_seen[seed] = 1'b1;
        random_value     = 32'h9e37_79b9 ^ seed;
        for (int unsigned job = 0; job < 1000; job++) begin
          random_value = (random_value * 32'd1664525) + 32'd1013904223;
          format       = random_value[1:0];
          run_random_job(random_value[2], format, random_value, job);
          completed++;
        end
      end
      if (completed != 10000) begin
        $fatal(1, "GA2D randomized campaign did not execute 10,000 jobs");
      end
      if (seeds_seen != 10'h3ff) begin
        $fatal(1, "GA2D randomized campaign did not execute all ten delay seeds");
      end
      check_random_delay_coverage();
    end
  endtask

  initial begin
    logic [31:0] error_status;
    logic [31:0] status;

    apb4.paddr                      = '0;
    apb4.pprot                      = '0;
    apb4.psel                       = 1'b0;
    apb4.penable                    = 1'b0;
    apb4.pwrite                     = 1'b0;
    apb4.pwdata                     = '0;
    apb4.pstrb                      = '0;
    s_inject_read_error             = 1'b0;
    s_inject_write_error            = 1'b0;
    s_inject_read_decerr            = 1'b0;
    s_inject_write_decerr           = 1'b0;
    s_inject_bad_rid                = 1'b0;
    s_inject_bad_rlast              = 1'b0;
    s_inject_bad_bid                = 1'b0;
    s_schedule_residual_r_i         = 1'b0;
    s_schedule_residual_b_i         = 1'b0;
    s_hold_ar_i                     = 1'b0;
    s_hold_r_i                      = 1'b0;
    s_hold_aw_i                     = 1'b0;
    s_hold_w_i                      = 1'b0;
    s_hold_b_i                      = 1'b0;
    s_random_delays_i               = 1'b0;
    s_random_delay_reseed_i         = 1'b0;
    s_random_delay_coverage_clear_i = 1'b0;
    s_random_delay_seed_i           = '0;
    s_clear_burst_observations_i    = 1'b0;
    s_check_read_bounds_i           = 1'b0;
    s_read_row0_start_i             = '0;
    s_read_row0_end_i               = '0;
    s_read_row1_start_i             = '0;
    s_read_row1_end_i               = '0;
    s_check_write_bounds_i          = 1'b0;
    s_write_row0_start_i            = '0;
    s_write_row0_end_i              = '0;
    s_write_row1_start_i            = '0;
    s_write_row1_end_i              = '0;

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;
    apb_write(`APB4_GA2D__IRQ_ENABLE, {29'd0, IrqDoneMask}, 1'b0);

    run_fill_case(`APB4_GA2D__FORMAT_RGB565, 2, SramBase + 32'h100, 32'd8, 32'h8012_3456,
                  32'h0000_11aa);
    run_fill_case(`APB4_GA2D__FORMAT_RGB888, 3, SramBase + 32'h181, 32'd12, 32'h8012_3456,
                  32'h0056_3412);
    run_fill_case(`APB4_GA2D__FORMAT_XRGB8888, 4, SramBase + 32'h200, 32'd16, 32'h8012_3456,
                  32'hff12_3456);
    run_fill_case(`APB4_GA2D__FORMAT_ARGB8888, 4, SramBase + 32'h280, 32'd16, 32'h8012_3456,
                  32'h8012_3456);

    run_copy_case(`APB4_GA2D__FORMAT_RGB565, 2, SramBase + 32'h400, SramBase + 32'h600);
    clear_burst_observations();
    run_copy_case(`APB4_GA2D__FORMAT_RGB888, 3, SramBase + 32'h501, SramBase + 32'h701);
    if (!s_saw_arsize_0_q || !s_saw_arsize_1_q || !s_saw_arsize_2_q) begin
      $fatal(1, "GA2D did not use aligned 1/2/4-byte RGB888 edge reads");
    end
    run_copy_case(`APB4_GA2D__FORMAT_XRGB8888, 4, SramBase + 32'h800, SramBase + 32'ha00);
    run_copy_case(`APB4_GA2D__FORMAT_ARGB8888, 4, SramBase + 32'hc00, SramBase + 32'he00);

    check_first_error_immutability();

    clear_memory(8'hc7);
    for (int unsigned byte_index = 0; byte_index < 8; byte_index++) begin
      s_memory[32'h1100+byte_index] = 8'h41 + byte_index;
    end
    configure_copy(`APB4_GA2D__FORMAT_RGB565, 16'd4, 16'd1, SramBase + 32'h1100, 32'd8,
                   SramBase + 32'h1300, 32'd8);
    apb_write(`APB4_GA2D__TIMEOUT_CYCLES, 32'd1024, 1'b0);
    s_hold_ar_i = 1'b1;
    start_job();
    for (int unsigned attempt = 0; (attempt < 256) && !ga2d_axi4.arvalid; attempt++) begin
      @(posedge clk_i);
    end
    if (!ga2d_axi4.arvalid) begin
      $fatal(1, "GA2D did not present AR for the channel-stall test");
    end
    s_hold_r_i  = 1'b1;
    s_hold_ar_i = 1'b0;
    for (int unsigned attempt = 0; (attempt < 256) && !s_rvalid_q; attempt++) begin
      @(posedge clk_i);
    end
    if (!s_rvalid_q) begin
      $fatal(1, "GA2D did not receive R for the channel-stall test");
    end
    s_hold_aw_i = 1'b1;
    s_hold_r_i  = 1'b0;
    for (int unsigned attempt = 0; (attempt < 256) && !ga2d_axi4.awvalid; attempt++) begin
      @(posedge clk_i);
    end
    if (!ga2d_axi4.awvalid) begin
      $fatal(1, "GA2D did not present AW for the channel-stall test");
    end
    s_hold_w_i  = 1'b1;
    s_hold_aw_i = 1'b0;
    for (int unsigned attempt = 0; (attempt < 256) && !ga2d_axi4.wvalid; attempt++) begin
      @(posedge clk_i);
    end
    if (!ga2d_axi4.wvalid) begin
      $fatal(1, "GA2D did not present W for the channel-stall test");
    end
    s_hold_b_i = 1'b1;
    s_hold_w_i = 1'b0;
    for (int unsigned attempt = 0; (attempt < 256) && !s_bvalid_q; attempt++) begin
      @(posedge clk_i);
    end
    if (!s_bvalid_q) begin
      $fatal(1, "GA2D did not receive B for the channel-stall test");
    end
    s_hold_b_i = 1'b0;
    wait_for_terminal(1'b1, 1'b0, 1'b0);
    for (int unsigned byte_index = 0; byte_index < 8; byte_index++) begin
      if (memory_byte(
              SramBase + 32'h1300 + byte_index
          ) != memory_byte(
              SramBase + 32'h1100 + byte_index
          )) begin
        $fatal(1, "GA2D channel-stall COPY did not preserve a source byte");
      end
    end

    run_fill_burst_case(16'd4, SramBase + 32'h1700, 8'd0);
    run_fill_burst_case(16'd60, SramBase + 32'h1800, 8'd14);
    run_fill_burst_case(16'd64, SramBase + 32'h1A00, 8'd15);
    run_fill_burst_case(16'd64, SramBase + 32'h0FC0, 8'd7);
    run_fill_burst_case(16'd64, SramBase + MemoryBytes - 32'd128, 8'd15);
    run_copy_burst_case(16'd4, SramBase + 32'h1f00, SramBase + 32'h1f40, 8'd0);
    run_copy_burst_case(16'd60, SramBase + 32'h2000, SramBase + 32'h2400, 8'd14);
    run_copy_burst_case(16'd64, SramBase + 32'h2600, SramBase + 32'h2A00, 8'd15);

    run_random_campaign();

    clear_memory(8'ha5);
    configure_copy(`APB4_GA2D__FORMAT_RGB888, 16'd3, 16'd1, SramBase + 32'h1200, 32'd12,
                   SramBase + 32'h1400, 32'd12);
    s_inject_read_error = 1'b1;
    start_job();
    wait_for_terminal(1'b0, 1'b1, 1'b0);
    check_error_code(`APB4_GA2D__ERROR_AXI_READ);
    check_error_axi_response(2'd2);
    for (int unsigned byte_index = 0; byte_index < 9; byte_index++) begin
      if (memory_byte(SramBase + 32'h1400 + byte_index) != 8'ha5) begin
        $fatal(1, "GA2D emitted an untrusted pixel after a read error");
      end
    end
    s_inject_read_error = 1'b0;
    clear_first_error();

    configure_copy(`APB4_GA2D__FORMAT_RGB888, 16'd3, 16'd1, SramBase + 32'h1200, 32'd12,
                   SramBase + 32'h1400, 32'd12);
    s_inject_read_decerr = 1'b1;
    start_job();
    wait_for_terminal(1'b0, 1'b1, 1'b0);
    check_error_code(`APB4_GA2D__ERROR_AXI_READ);
    check_error_axi_response(2'd3);
    s_inject_read_decerr = 1'b0;
    clear_first_error();

    run_read_protocol_quarantine(1'b1);
    run_read_protocol_quarantine(1'b0);

    configure_fill(`APB4_GA2D__FORMAT_RGB565, 16'd3, 16'd1, SramBase + 32'h1600, 32'd8,
                   32'h8012_3456);
    s_inject_write_error = 1'b1;
    start_job();
    wait_for_terminal(1'b0, 1'b1, 1'b0);
    check_error_code(`APB4_GA2D__ERROR_AXI_WRITE);
    check_error_axi_response(2'd2);
    s_inject_write_error = 1'b0;
    clear_first_error();

    configure_fill(`APB4_GA2D__FORMAT_RGB565, 16'd3, 16'd1, SramBase + 32'h1640, 32'd8,
                   32'h8012_3456);
    s_inject_write_decerr = 1'b1;
    start_job();
    wait_for_terminal(1'b0, 1'b1, 1'b0);
    check_error_code(`APB4_GA2D__ERROR_AXI_WRITE);
    check_error_axi_response(2'd3);
    s_inject_write_decerr = 1'b0;
    clear_first_error();

    run_write_protocol_quarantine();
    run_abort_during_error_drain(1'b0);
    run_abort_during_error_drain(1'b1);

    configure_fill(`APB4_GA2D__FORMAT_RGB565, 16'd2, 16'd1, SramBase + MemoryBytes - 2, 32'd4,
                   32'hffff_ffff);
    s_ar_count_before_validation = s_ar_count;
    s_aw_count_before_validation = s_aw_count;
    start_job();
    wait_for_terminal(1'b0, 1'b1, 1'b0);
    check_error_code(`APB4_GA2D__ERROR_ADDRESS_RANGE);
    clear_first_error();
    if ((s_ar_count != s_ar_count_before_validation) ||
        (s_aw_count != s_aw_count_before_validation)) begin
      $fatal(1, "GA2D validation failure issued AXI traffic");
    end

    configure_fill(`APB4_GA2D__FORMAT_RGB565, 16'd1, 16'd1, SramBase + 32'h1700, 32'd2,
                   32'h8012_3456);
    apb_write(`APB4_GA2D__TIMEOUT_CYCLES, 32'd8, 1'b0);
    s_hold_aw_i = 1'b1;
    start_job();
    wait_for_runtime_error(status);
    if (!status[`APB4_GA2D__STATUS_DRAINING]) begin
      $fatal(1, "GA2D watchdog error did not enter drain");
    end
    apb_read(`APB4_GA2D__ERROR_STATUS, error_status);
    if (error_status[`APB4_GA2D__ERROR_STATUS_CODE+:7] != `APB4_GA2D__ERROR_TIMEOUT) begin
      $fatal(1, "GA2D watchdog error was not attributed as TIMEOUT");
    end
    s_hold_aw_i = 1'b0;
    wait_for_terminal(1'b0, 1'b1, 1'b0);
    if (!core_safe_idle_o) begin
      $fatal(1, "GA2D watchdog drain did not prove core-safe idle");
    end
    resource_reset_i = 1'b1;
    repeat (3) @(posedge clk_i);
    resource_reset_i = 1'b0;
    repeat (3) @(posedge clk_i);
    apb_read(`APB4_GA2D__STATUS, status);
    if (status[`APB4_GA2D__STATUS_RECOVERY_REQUIRED]) begin
      $fatal(1, "GA2D coordinated resource recovery did not clear timeout state");
    end
    apb_write(`APB4_GA2D__COMMAND, 32'h0000_0004, 1'b0);

    configure_fill(`APB4_GA2D__FORMAT_RGB565, 16'd1, 16'd1, SramBase + 32'h1740, 32'd2,
                   32'h8012_3456);
    s_hold_aw_i = 1'b1;
    start_job();
    repeat (3) @(posedge clk_i);
    bridge_clear_busy_i = 1'b1;
    bridge_epoch_i      = bridge_epoch_i + 1'b1;
    @(posedge clk_i);
    bridge_clear_busy_i = 1'b0;
    s_hold_aw_i         = 1'b0;
    wait_for_runtime_error(status);
    apb_read(`APB4_GA2D__ERROR_STATUS, error_status);
    if (error_status[`APB4_GA2D__ERROR_STATUS_CODE+:7] != `APB4_GA2D__ERROR_EPOCH_LOST) begin
      $fatal(1, "GA2D bridge epoch change was not attributed as EPOCH_LOST");
    end
    wait_for_terminal(1'b0, 1'b1, 1'b0);
    resource_reset_i = 1'b1;
    repeat (3) @(posedge clk_i);
    resource_reset_i = 1'b0;
    repeat (3) @(posedge clk_i);
    apb_read(`APB4_GA2D__STATUS, status);
    if (status[`APB4_GA2D__STATUS_RECOVERY_REQUIRED]) begin
      $fatal(1, "GA2D epoch recovery did not wait for the resource reset boundary");
    end
    apb_write(`APB4_GA2D__COMMAND, 32'h0000_0004, 1'b0);

    clear_memory(8'hd3);
    configure_fill(`APB4_GA2D__FORMAT_RGB565, 16'd16, 16'd2, SramBase + 32'h1800, 32'd32,
                   32'h8012_3456);
    apb_write(`APB4_GA2D__TIMEOUT_CYCLES, 32'd64, 1'b0);
    s_hold_aw_i = 1'b1;
    start_job();
    for (int unsigned attempt = 0; (attempt < 256) && !ga2d_axi4.awvalid; attempt++) begin
      @(posedge clk_i);
    end
    if (!ga2d_axi4.awvalid) begin
      $fatal(1, "GA2D did not present AW before the resource-stop test");
    end
    @(posedge clk_i);
    if (!ga2d_axi4.awvalid || ga2d_axi4.awready) begin
      $fatal(1, "GA2D did not retain the stalled AW for a full permit cycle");
    end
    resource_quiesce_i = 1'b1;
    source_stop_i      = 1'b1;
    repeat (2) @(posedge clk_i);
    s_hold_aw_i = 1'b0;
    wait_for_terminal(1'b0, 1'b0, 1'b1);
    check_abort_done_event();
    if (!core_safe_idle_o) begin
      $fatal(1, "GA2D resource stop did not wait for core-safe idle");
    end
    for (int unsigned byte_index = 0; byte_index < 32; byte_index++) begin
      if (memory_byte(SramBase + 32'h1820 + byte_index) != 8'hd3) begin
        $fatal(1, "GA2D emitted an unissued second-row write after source stop");
      end
    end
    block_ack_i = 1'b1;
    repeat (2) @(posedge clk_i);
    resource_quiesce_i = 1'b0;
    source_stop_i      = 1'b0;
    block_ack_i        = 1'b0;
    repeat (4) @(posedge clk_i);

    $display("GA2D P4 DMA test passed with independent AXI delay coverage");
    $finish;
  end

  initial begin
    repeat (2000000) @(posedge clk_i);
    $fatal(1, "GA2D P4 DMA test timed out");
  end
endmodule
