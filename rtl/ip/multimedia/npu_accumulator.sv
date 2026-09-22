// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// Two accumulator contexts, each 8x8 checked INT32 sums for numerical
// profile 1. Acquiring a context preloads every sum from the per-channel bias
// (sum[p][c] = bias[c]); the bias is added exactly once per context lifetime,
// so multi-K-slice reductions keep accumulating rows without a new acquire.
// Accepted rows are pipelined: stage A registers the products with a one-hot
// context token, stage B performs the checked INT32 adds one cycle later, so
// the interface sustains one row per cycle. Each context owns its add array;
// there is no shared context-selected sum read. On the first overflowing
// update (lowest sum index p*8+c wins, evaluated with a log-depth encoder)
// the sticky fault and fault_sum_o are latched, the faulting sums retain
// their stored values (no wrap, no saturation), and the context moves to
// Fault. A drain request moves an Accumulate context to DrainPending; once
// its in-flight row has landed in the sums and the single drain port is free,
// the context moves to Draining and publishes the 64 sums exactly once in
// position-major order (p = 0..7, c = 0..7 inside each position) through a
// valid/ready stream. A Fault context never drains and only clear_i releases
// it. clear_i synchronously returns every context to Idle, drops in-flight
// rows, and clears the fault record; it also blocks start/row/drain
// acceptance in the same cycle.
module npu_accumulator (
    input logic clk_i,
    input logic rst_n_i,
    input logic clear_i,
    input logic start_valid_i,
    output logic start_ready_o,
    input logic [npu_pkg::ChannelLanes-1:0][31:0] start_bias_i,
    output logic start_context_o,
    input logic row_valid_i,
    output logic row_ready_o,
    input logic row_context_i,
    input logic [npu_pkg::SpatialLanes-1:0][npu_pkg::ChannelLanes-1:0][16:0] row_products_i,
    input logic drain_valid_i,
    input logic drain_context_i,
    output logic drain_data_valid_o,
    input logic drain_data_ready_i,
    output logic signed [31:0] drain_data_o,
    output logic drain_last_o,
    output logic busy_o,
    output logic fault_sticky_o,
    output logic [5:0] fault_sum_o
);
  typedef enum logic [2:0] {
    Idle,
    Accumulate,
    DrainPending,
    Draining,
    Fault
  } context_state_e;

  localparam logic [5:0] SumLastIndex = 6'(npu_pkg::AccSumCount - 1);

  logic [npu_pkg::AccContextCount-1:0][2:0] s_context_state_d;
  logic [npu_pkg::AccContextCount-1:0][2:0] s_context_state_q;
  logic [npu_pkg::AccContextCount-1:0][npu_pkg::AccSumCount-1:0][npu_pkg::AccWidth-1:0] s_sum_q;
  // Accumulate stage A: accepted-row register with a one-hot context token.
  logic [npu_pkg::AccContextCount-1:0] s_rowa_valid_d;
  logic [npu_pkg::AccContextCount-1:0] s_rowa_valid_q;
  logic [npu_pkg::AccSumCount-1:0][npu_pkg::ProductWidth-1:0] s_rowa_products_q;
  // Accumulate stage B: per-context checked adds and overflow flags.
  logic [npu_pkg::AccContextCount-1:0][npu_pkg::AccSumCount-1:0][npu_pkg::AccWidth-1:0]
      s_rowb_updated;
  logic [npu_pkg::AccContextCount-1:0][npu_pkg::AccSumCount-1:0] s_rowb_overflow;
  logic [npu_pkg::AccContextCount-1:0] s_rowb_apply;
  logic [npu_pkg::AccContextCount-1:0] s_rowb_fault_ctx;
  logic [npu_pkg::AccContextCount-1:0][5:0] s_rowb_index_ctx;
  logic s_rowb_fault;
  logic [5:0] s_rowb_fault_index;
  logic [npu_pkg::AccContextCount-1:0] s_context_idle;
  logic [npu_pkg::AccContextCount-1:0] s_context_accumulating;
  logic [npu_pkg::AccContextCount-1:0] s_context_draining;
  logic [npu_pkg::AccContextCount-1:0] s_pending_ready;
  logic [npu_pkg::AccContextCount-1:0] s_drain_grant;
  logic s_prior_pending_ready;
  logic s_start_accept;
  logic s_row_accept;
  logic s_draining_any;
  logic s_drain_grant_any;
  logic s_drain_context_sel;
  logic s_drain_done;
  logic [5:0] s_drain_index_q;
  logic s_fault_sticky_q;
  logic [5:0] s_fault_sum_q;

  function automatic logic signed [npu_pkg::AccWidth-1:0] sum_update(
      input logic signed [npu_pkg::AccWidth-1:0] sum_i,
      input logic signed [npu_pkg::ProductWidth-1:0] product_i);
    logic signed [npu_pkg::AccWidth-1:0] s_product_ext;
    begin
      s_product_ext = {
        {(npu_pkg::AccWidth - npu_pkg::ProductWidth) {product_i[npu_pkg::ProductWidth-1]}},
        product_i
      };
      return sum_i + s_product_ext;
    end
  endfunction

  function automatic logic sum_overflows(input logic signed [npu_pkg::AccWidth-1:0] sum_i,
                                         input logic signed [npu_pkg::ProductWidth-1:0] product_i);
    logic signed [npu_pkg::AccWidth-1:0] s_product_ext;
    logic signed [npu_pkg::AccWidth-1:0] s_updated;
    begin
      s_product_ext = {
        {(npu_pkg::AccWidth - npu_pkg::ProductWidth) {product_i[npu_pkg::ProductWidth-1]}},
        product_i
      };
      s_updated = sum_i + s_product_ext;
      return (sum_i[npu_pkg::AccWidth-1] == s_product_ext[npu_pkg::AccWidth-1]) &&
          (s_updated[npu_pkg::AccWidth-1] != sum_i[npu_pkg::AccWidth-1]);
    end
  endfunction

  // Log-depth lowest-set-index encoder over the 64 per-sum overflow flags:
  // each level takes the lower half whenever it contains a set bit.
  function automatic logic [5:0] lowest_set_index(input logic [63:0] flags_i);
    logic [31:0] s_w32;
    logic [15:0] s_w16;
    logic [ 7:0] s_w8;
    logic [ 3:0] s_w4;
    logic [ 1:0] s_w2;
    logic [ 5:0] s_index;
    begin
      s_index[5] = ~|flags_i[31:0];
      s_w32      = s_index[5] ? flags_i[63:32] : flags_i[31:0];
      s_index[4] = ~|s_w32[15:0];
      s_w16      = s_index[4] ? s_w32[31:16] : s_w32[15:0];
      s_index[3] = ~|s_w16[7:0];
      s_w8       = s_index[3] ? s_w16[15:8] : s_w16[7:0];
      s_index[2] = ~|s_w8[3:0];
      s_w4       = s_index[2] ? s_w8[7:4] : s_w8[3:0];
      s_index[1] = ~|s_w4[1:0];
      s_w2       = s_index[1] ? s_w4[3:2] : s_w4[1:0];
      s_index[0] = ~s_w2[0];
      return s_index;
    end
  endfunction

  for (genvar ctx = 0; ctx < npu_pkg::AccContextCount; ctx++) begin : gen_decode
    assign s_context_idle[ctx] = s_context_state_q[ctx] == Idle;
    assign s_context_accumulating[ctx] = s_context_state_q[ctx] == Accumulate;
    assign s_context_draining[ctx] = s_context_state_q[ctx] == Draining;
    // clear_i suppresses the stage-B landing of an in-flight row.
    assign s_rowb_apply[ctx] = s_rowa_valid_q[ctx] && !clear_i;
    assign s_rowb_fault_ctx[ctx] = s_rowb_apply[ctx] && (|s_rowb_overflow[ctx]);
    assign s_rowb_index_ctx[ctx] = lowest_set_index(s_rowb_overflow[ctx]);
    // A pending drain may proceed only once the context has no in-flight row.
    assign s_pending_ready[ctx] = (s_context_state_q[ctx] == DrainPending) && !s_rowa_valid_q[ctx];
  end

  assign busy_o = !(&s_context_idle);
  assign start_ready_o = (|s_context_idle) && !clear_i;
  // Stage B always retires a row in one cycle, so stage A never backpressures
  // and the interface sustains one row per cycle.
  assign row_ready_o = s_context_accumulating[row_context_i] && !clear_i;
  assign s_start_accept = start_valid_i && start_ready_o;
  assign s_row_accept = row_valid_i && row_ready_o;
  assign s_draining_any = |s_context_draining;
  assign s_drain_grant_any = |s_drain_grant;
  assign s_drain_done = s_draining_any && drain_data_ready_i && (s_drain_index_q == SumLastIndex);

  assign drain_data_valid_o = s_draining_any;
  assign drain_last_o = s_draining_any && (s_drain_index_q == SumLastIndex);
  assign drain_data_o = s_sum_q[s_drain_context_sel][s_drain_index_q];

  assign fault_sticky_o = s_fault_sticky_q;
  assign fault_sum_o = s_fault_sum_q;

  // One-hot acceptance token for stage A.
  always_comb begin
    s_rowa_valid_d = '0;
    if (s_row_accept) begin
      s_rowa_valid_d[row_context_i] = 1'b1;
    end
  end

  // Lowest Idle context index is acquired; the loop ends with the lowest hit.
  always_comb begin
    start_context_o = 1'b0;
    for (int ctx = int'(npu_pkg::AccContextCount) - 1; ctx >= 0; ctx--) begin
      if (s_context_idle[ctx]) begin
        start_context_o = 1'(ctx);
      end
    end
  end

  // Pending drains are granted lowest-index first once their pipeline stage is
  // empty and the single drain port is free.
  always_comb begin
    s_prior_pending_ready = 1'b0;
    s_drain_grant         = '0;
    for (int ctx = 0; ctx < int'(npu_pkg::AccContextCount); ctx++) begin
      s_drain_grant[ctx]    = s_pending_ready[ctx] && !s_draining_any && !s_prior_pending_ready;
      s_prior_pending_ready = s_prior_pending_ready || s_pending_ready[ctx];
    end
  end

  // Selects the draining context; at most one context can be Draining because
  // grants are blocked while a drain is in flight.
  always_comb begin
    s_drain_context_sel = 1'b0;
    for (int ctx = 0; ctx < int'(npu_pkg::AccContextCount); ctx++) begin
      if (s_context_draining[ctx]) begin
        s_drain_context_sel = 1'(ctx);
      end
    end
  end

  // Stage-B combinational checked update: each context owns its add array, so
  // no context-selected read of the sum bank exists on this path.
  for (genvar ctx = 0; ctx < npu_pkg::AccContextCount; ctx++) begin : gen_stage_b
    for (genvar index = 0; index < npu_pkg::AccSumCount; index++) begin : gen_sum_update
      assign s_rowb_overflow[ctx][index] = sum_overflows(
          s_sum_q[ctx][index], s_rowa_products_q[index]
      );
      assign s_rowb_updated[ctx][index] = sum_update(s_sum_q[ctx][index], s_rowa_products_q[index]);
    end
  end

  // Lowest context index wins the fault record; the loop ends with that hit.
  always_comb begin
    s_rowb_fault       = 1'b0;
    s_rowb_fault_index = 6'd0;
    for (int ctx = int'(npu_pkg::AccContextCount) - 1; ctx >= 0; ctx--) begin
      if (s_rowb_fault_ctx[ctx]) begin
        s_rowb_fault       = 1'b1;
        s_rowb_fault_index = s_rowb_index_ctx[ctx];
      end
    end
  end

  always_comb begin
    s_context_state_d = s_context_state_q;
    for (int ctx = 0; ctx < int'(npu_pkg::AccContextCount); ctx++) begin
      unique case (s_context_state_q[ctx])
        Idle: begin
          if (s_start_accept && (start_context_o == 1'(ctx))) begin
            s_context_state_d[ctx] = Accumulate;
          end
        end
        Accumulate: begin
          if (s_rowb_fault_ctx[ctx]) begin
            s_context_state_d[ctx] = Fault;
          end else if (drain_valid_i && !clear_i && (drain_context_i == 1'(ctx))) begin
            s_context_state_d[ctx] = DrainPending;
          end
        end
        DrainPending: begin
          if (s_rowb_fault_ctx[ctx]) begin
            s_context_state_d[ctx] = Fault;
          end else if (s_drain_grant[ctx]) begin
            s_context_state_d[ctx] = Draining;
          end
        end
        Draining: begin
          if (s_drain_done) begin
            s_context_state_d[ctx] = Idle;
          end
        end
        Fault: begin
        end
        default: begin
          s_context_state_d[ctx] = Idle;
        end
      endcase
    end
    if (clear_i) begin
      s_context_state_d = '0;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_context_state_q <= '0;
    end else begin
      s_context_state_q <= s_context_state_d;
    end
  end

  // Stage-A row register. The products register is fully overwritten on every
  // acceptance, so only the one-hot token needs reset.
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_rowa_valid_q <= '0;
    end else if (clear_i) begin
      s_rowa_valid_q <= '0;
    end else begin
      s_rowa_valid_q <= s_rowa_valid_d;
    end
  end

  always_ff @(posedge clk_i) begin
    if (s_row_accept) begin
      s_rowa_products_q <= row_products_i;
    end
  end

  // On acquire every sum preloads from the per-channel bias; on a stage-B row
  // each non-overflowing sum takes the checked update while an overflowing sum
  // retains its stored value. Sums are not cleared by clear_i because the next
  // acquire fully preloads them before any read.
  for (genvar ctx = 0; ctx < npu_pkg::AccContextCount; ctx++) begin : gen_context
    localparam logic ContextIndex = 1'(ctx);
    for (genvar index = 0; index < npu_pkg::AccSumCount; index++) begin : gen_sum
      localparam int unsigned ChannelIndex = index % npu_pkg::ChannelLanes;

      always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
          s_sum_q[ctx][index] <= 32'd0;
        end else if (s_start_accept && (start_context_o == ContextIndex)) begin
          s_sum_q[ctx][index] <= start_bias_i[ChannelIndex];
        end else if (s_rowb_apply[ctx] && !s_rowb_overflow[ctx][index]) begin
          s_sum_q[ctx][index] <= s_rowb_updated[ctx][index];
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_drain_index_q <= 6'd0;
    end else if (clear_i || s_drain_grant_any || s_drain_done) begin
      s_drain_index_q <= 6'd0;
    end else if (s_draining_any && drain_data_ready_i) begin
      s_drain_index_q <= s_drain_index_q + 6'd1;
    end
  end

  // First fault is retained until clear_i; a later fault in the other context
  // does not overwrite the record.
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_fault_sticky_q <= 1'b0;
      s_fault_sum_q    <= 6'd0;
    end else if (clear_i) begin
      s_fault_sticky_q <= 1'b0;
      s_fault_sum_q    <= 6'd0;
    end else if (s_rowb_fault && !s_fault_sticky_q) begin
      s_fault_sticky_q <= 1'b1;
      s_fault_sum_q    <= s_rowb_fault_index;
    end
  end

`ifndef SV_ASSRT_DISABLE
  logic s_start_stall_q;
  logic s_row_stall_q;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_start_stall_q <= 1'b0;
      s_row_stall_q   <= 1'b0;
    end else begin
      s_start_stall_q <= start_valid_i && !start_ready_o;
      s_row_stall_q   <= row_valid_i && !row_ready_o;
      if (row_valid_i) begin
        assert (int'(row_context_i) < int'(npu_pkg::AccContextCount));
      end
      if (s_start_stall_q) begin
        assert ($stable(start_bias_i));
      end
      if (s_row_stall_q) begin
        assert ($stable(row_context_i));
        assert ($stable(row_products_i));
      end
    end
  end
`endif
endmodule
