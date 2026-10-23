// Verification-only transaction accounting. No DUT signal is driven.
module tiny_p10_observer #(
    parameter integer Owners = 3
) (
    input logic                   clk_i,
    input logic                   rst_n_i,
    input logic                   enable_i,
    input logic [Owners-1:0]      read_accept_i,
    input logic [Owners-1:0]      read_done_i,
    input logic [Owners-1:0]      write_accept_i,
    input logic [Owners-1:0]      write_done_i,
    input logic [Owners-1:0]      error_i,
    input logic [Owners-1:0][7:0] read_bytes_i,
    input logic [Owners-1:0][7:0] write_bytes_i,
    input logic [Owners-1:0][4:0] stalled_i,
    input logic [       5:0]      active_targets_i,
    input logic [       3:0]      bank_issues_i,
    input logic                   dma_beat_overlap_i
);
  longint unsigned s_cycle = 0;
  integer          s_window = 0;
  logic            s_previous = 0;
  logic [Owners-1:0] s_read_pending = 0, s_write_pending = 0;
  longint unsigned s_read_start[Owners], s_write_start[Owners];
  longint unsigned s_reads[Owners], s_writes[Owners], s_read_done[Owners], s_write_done[Owners];
  longint unsigned s_read_bytes[Owners], s_write_bytes[Owners], s_errors[Owners];
  longint unsigned s_read_max[Owners], s_write_max[Owners];
  longint unsigned s_stall[Owners][5], s_stall_max[Owners][5];
  logic [Owners-1:0] s_read_initial = 0, s_write_initial = 0;
  integer s_active_max = 0;
  longint unsigned s_bank_overlap = 0, s_dma_overlap = 0;
  integer s_bank_count;

  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      s_previous      = 0;
      s_read_pending  = 0;
      s_write_pending = 0;
      s_window        = 0;
      s_cycle         = 0;
    end else begin
      s_cycle++;
      if (enable_i && !s_previous) begin
        s_window++;
        s_read_initial  = s_read_pending;
        s_write_initial = s_write_pending;
        s_active_max    = 0;
        s_bank_overlap  = 0;
        s_dma_overlap   = 0;
        for (integer owner = 0; owner < Owners; owner++) begin
          s_reads[owner]       = 0;
          s_writes[owner]      = 0;
          s_read_done[owner]   = 0;
          s_write_done[owner]  = 0;
          s_read_bytes[owner]  = 0;
          s_write_bytes[owner] = 0;
          s_errors[owner]      = 0;
          s_read_max[owner]    = 0;
          s_write_max[owner]   = 0;
          for (integer channel = 0; channel < 5; channel++) begin
            s_stall[owner][channel]     = 0;
            s_stall_max[owner][channel] = 0;
          end
        end
      end
      if (!enable_i && s_previous) begin
        for (integer owner = 0; owner < Owners; owner++) begin
          $display(
              "P10_BUS window=%0d owner=%0d reads=%0d writes=%0d read_done=%0d write_done=%0d read_initial=%0d write_initial=%0d read_pending=%0d write_pending=%0d read_bytes=%0d write_bytes=%0d errors=%0d read_latency_max=%0d write_latency_max=%0d ar_max=%0d r_max=%0d aw_max=%0d w_max=%0d b_max=%0d",
              s_window, owner, s_reads[owner], s_writes[owner], s_read_done[owner],
              s_write_done[owner], s_read_initial[owner], s_write_initial[owner],
              s_read_pending[owner], s_write_pending[owner], s_read_bytes[owner],
              s_write_bytes[owner], s_errors[owner], s_read_max[owner], s_write_max[owner],
              s_stall_max[owner][0], s_stall_max[owner][1], s_stall_max[owner][2],
              s_stall_max[owner][3], s_stall_max[owner][4]);
        end
        $display(
            "P10_CONCURRENCY window=%0d active_targets_max=%0d bank_overlap=%0d dma_beat_overlap=%0d",
            s_window, s_active_max, s_bank_overlap, s_dma_overlap);
      end
      for (integer owner = 0; owner < Owners; owner++) begin
        if (read_accept_i[owner]) begin
          if (s_read_pending[owner]) $fatal(1, "SIM_TEST_FAIL P10 duplicate AR");
          s_read_pending[owner] = 1;
          s_read_start[owner]   = s_cycle;
          if (enable_i) s_reads[owner]++;
        end
        if (write_accept_i[owner]) begin
          if (s_write_pending[owner]) $fatal(1, "SIM_TEST_FAIL P10 duplicate AW");
          s_write_pending[owner] = 1;
          s_write_start[owner]   = s_cycle;
          if (enable_i) s_writes[owner]++;
        end
        if (read_done_i[owner]) begin
          if (!s_read_pending[owner]) $fatal(1, "SIM_TEST_FAIL P10 unsolicited RLAST");
          s_read_pending[owner] = 0;
          if (enable_i) begin
            s_read_done[owner]++;
            if (s_cycle - s_read_start[owner] > s_read_max[owner])
              s_read_max[owner] = s_cycle - s_read_start[owner];
          end
        end
        if (write_done_i[owner]) begin
          if (!s_write_pending[owner]) $fatal(1, "SIM_TEST_FAIL P10 unsolicited B");
          s_write_pending[owner] = 0;
          if (enable_i) begin
            s_write_done[owner]++;
            if (s_cycle - s_write_start[owner] > s_write_max[owner])
              s_write_max[owner] = s_cycle - s_write_start[owner];
          end
        end
        if (enable_i) begin
          s_read_bytes[owner] += 64'(read_bytes_i[owner]);
          s_write_bytes[owner] += 64'(write_bytes_i[owner]);
          if (error_i[owner]) s_errors[owner]++;
          for (integer channel = 0; channel < 5; channel++) begin
            s_stall[owner][channel] = ((stalled_i[owner] >> channel) & 5'b1) != 0 ?
                s_stall[owner][channel] + 1 : 0;
            if (s_stall[owner][channel] > s_stall_max[owner][channel])
              s_stall_max[owner][channel] = s_stall[owner][channel];
          end
        end
      end
      if (enable_i) begin
        if (integer'(active_targets_i) > s_active_max) s_active_max = integer'(active_targets_i);
        s_bank_count = 0;
        for (integer bank = 0; bank < 4; bank++) if (bank_issues_i[bank]) s_bank_count++;
        if (s_bank_count > 1) s_bank_overlap++;
        if (dma_beat_overlap_i) s_dma_overlap++;
      end
      s_previous = enable_i;
    end
  end
endmodule
