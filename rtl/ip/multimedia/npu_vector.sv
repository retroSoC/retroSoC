// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// NPU vector unit: one depthwise context of eight checked INT32 lane sums
// plus an independent scalar auxiliary unit (running signed-byte max and
// checked INT32 byte sum). start_valid_i acquires the idle context and
// preloads each lane sum from start_bias_i once (bias is added once, not per
// row). Each accepted depthwise row centers every valid lane byte to signed
// nine bits (byte - in_zero), forms the signed 9x8 product and performs a
// checked INT32 add; any overflow enters Fault with the lowest faulting lane
// index recorded, the sums freeze and never wrap. The scalar aux is usable in
// Idle or Accumulate and is independent of the depthwise handshake; its
// overflow reports the dedicated fault-lane encoding 3'd7 (the aux unit has
// no lane). start_valid_i has priority over a same-cycle aux operation in
// Idle; a depthwise overflow has priority over a same-cycle aux overflow for
// the recorded lane. aux_result_o combinationally reflects the register
// selected by the most recent aux operation (the sum register after
// start/clear). drain_valid_i, accepted only in Accumulate with dw_valid_i
// low, streams the eight lane sums in lane order with exactly-once
// valid/ready handshakes and drain_last_o on the eighth beat; the context
// frees after the final handshake. Fault and drain requests outside their
// accepted states are ignored. Fault releases only via clear_i, which also
// clears the sums and aux registers.
module npu_vector (
    input  logic                                            clk_i,
    input  logic                                            rst_n_i,
    input  logic                                            clear_i,
    input  logic                                            start_valid_i,
    output logic                                            start_ready_o,
    input  logic        [npu_pkg::DepthwiseLanes-1:0][31:0] start_bias_i,
    input  logic                                            dw_valid_i,
    output logic                                            dw_ready_o,
    input  logic        [npu_pkg::DepthwiseLanes-1:0][ 7:0] dw_a_bytes_i,
    input  logic        [npu_pkg::DepthwiseLanes-1:0][ 7:0] dw_w_bytes_i,
    input  logic signed [                        7:0]       dw_in_zero_i,
    input  logic        [npu_pkg::DepthwiseLanes-1:0]       dw_lane_valid_i,
    input  logic                                            aux_valid_i,
    input  logic        [                        1:0]       aux_op_i,
    input  logic signed [                        7:0]       aux_data_i,
    input  logic                                            drain_valid_i,
    output logic                                            drain_data_valid_o,
    input  logic                                            drain_data_ready_i,
    output logic signed [                       31:0]       drain_data_o,
    output logic                                            drain_last_o,
    output logic signed [                       31:0]       aux_result_o,
    output logic                                            busy_o,
    output logic                                            fault_sticky_o,
    output logic        [                        2:0]       fault_lane_o
);
  localparam int unsigned LaneCount = npu_pkg::DepthwiseLanes;
  // Aux opcodes (2'd0 is nop) and the dedicated aux fault-lane encoding.
  localparam logic [1:0] AuxOpMax = 2'd1;
  localparam logic [1:0] AuxOpSum = 2'd2;
  localparam logic [2:0] AuxFaultLane = 3'd7;

  typedef enum logic [1:0] {
    Idle,
    Accumulate,
    Draining,
    Fault
  } state_e;

  state_e                            s_state_d;
  state_e                            s_state_q;
  logic        [LaneCount-1:0][31:0] s_sum_q;
  logic        [          2:0]       s_drain_cnt_q;
  logic        [          2:0]       s_fault_lane_q;
  logic signed [          7:0]       s_aux_max_q;
  logic signed [         31:0]       s_aux_sum_q;
  logic        [          1:0]       s_aux_mode_q;
  logic        [LaneCount-1:0][ 8:0] s_centered;
  logic        [LaneCount-1:0][16:0] s_product;
  logic        [LaneCount-1:0][32:0] s_sum_ext;
  logic        [LaneCount-1:0]       s_lane_ovf;
  logic                              s_dw_ovf_any;
  logic        [          2:0]       s_dw_fault_lane;
  logic        [         32:0]       s_aux_sum_ext;
  logic                              s_aux_ovf;
  logic                              s_dw_accept;
  logic                              s_aux_accept;
  logic                              s_aux_sum_ovf_evt;
  logic                              s_drain_accept;

  // Signed 9-bit centering (byte - in_zero), signed 9x8 product and checked
  // 33-bit accumulation per lane; overflow when the carry into the sign bit
  // differs from the new sign bit.
  for (genvar lane = 0; lane < LaneCount; lane++) begin : gen_lane_datapath
    assign s_centered[lane] = $signed(
        {dw_a_bytes_i[lane][7], dw_a_bytes_i[lane]}
    ) - $signed(
        {dw_in_zero_i[7], dw_in_zero_i}
    );
    assign s_product[lane] = $signed(s_centered[lane]) * $signed(dw_w_bytes_i[lane]);
    assign s_sum_ext[lane] = {s_sum_q[lane][31], s_sum_q[lane]} +
        {{16{s_product[lane][16]}}, s_product[lane]};
    assign s_lane_ovf[lane] = s_sum_ext[lane][32] != s_sum_ext[lane][31];
  end

  assign s_dw_ovf_any = |(dw_lane_valid_i & s_lane_ovf);
  assign s_aux_sum_ext = {s_aux_sum_q[31], s_aux_sum_q} + {{25{aux_data_i[7]}}, aux_data_i};
  assign s_aux_ovf = s_aux_sum_ext[32] != s_aux_sum_ext[31];
  assign s_dw_accept = dw_valid_i && (s_state_q == Accumulate);
  assign s_aux_accept = aux_valid_i && (aux_op_i != 2'd0) &&
      ((s_state_q == Idle) || (s_state_q == Accumulate)) &&
      !((s_state_q == Idle) && start_valid_i);
  assign s_aux_sum_ovf_evt = s_aux_accept && (aux_op_i == AuxOpSum) && s_aux_ovf;
  assign s_drain_accept = drain_valid_i && !dw_valid_i && (s_state_q == Accumulate);

  // Lowest faulting lane wins within a cycle.
  always_comb begin
    s_dw_fault_lane = 3'd0;
    for (int lane = LaneCount - 1; lane >= 0; lane--) begin
      if (dw_lane_valid_i[lane] && s_lane_ovf[lane]) begin
        s_dw_fault_lane = 3'(lane);
      end
    end
  end

  always_comb begin
    s_state_d = s_state_q;
    unique case (s_state_q)
      Idle: begin
        if (start_valid_i) begin
          s_state_d = Accumulate;
        end else if (s_aux_sum_ovf_evt) begin
          s_state_d = Fault;
        end
      end
      Accumulate: begin
        if (s_dw_accept && s_dw_ovf_any) begin
          s_state_d = Fault;
        end else if (s_aux_sum_ovf_evt) begin
          s_state_d = Fault;
        end else if (s_drain_accept) begin
          s_state_d = Draining;
        end
      end
      Draining: begin
        if (drain_data_ready_i && (s_drain_cnt_q == 3'(LaneCount - 1))) begin
          s_state_d = Idle;
        end
      end
      Fault: begin
        s_state_d = Fault;
      end
      default: begin
        s_state_d = Idle;
      end
    endcase
  end

  assign start_ready_o = (s_state_q == Idle);
  assign dw_ready_o = (s_state_q == Accumulate);
  assign drain_data_valid_o = (s_state_q == Draining);
  assign drain_data_o = $signed(s_sum_q[s_drain_cnt_q]);
  assign drain_last_o = (s_state_q == Draining) && (s_drain_cnt_q == 3'(LaneCount - 1));
  assign aux_result_o = (s_aux_mode_q == AuxOpMax) ?
      {{24{s_aux_max_q[7]}}, s_aux_max_q} : s_aux_sum_q;
  assign busy_o = (s_state_q != Idle);
  assign fault_sticky_o = (s_state_q == Fault);
  assign fault_lane_o = s_fault_lane_q;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q      <= Idle;
      s_sum_q        <= '0;
      s_drain_cnt_q  <= 3'd0;
      s_fault_lane_q <= 3'd0;
      s_aux_max_q    <= 8'h80;
      s_aux_sum_q    <= 32'd0;
      s_aux_mode_q   <= 2'd0;
    end else if (clear_i) begin
      s_state_q      <= Idle;
      s_sum_q        <= '0;
      s_drain_cnt_q  <= 3'd0;
      s_fault_lane_q <= 3'd0;
      s_aux_max_q    <= 8'h80;
      s_aux_sum_q    <= 32'd0;
      s_aux_mode_q   <= 2'd0;
    end else begin
      s_state_q <= s_state_d;
      if ((s_state_q == Idle) && start_valid_i) begin
        // Bias preloads each lane sum exactly once at context acquire.
        for (int lane = 0; lane < LaneCount; lane++) begin
          s_sum_q[lane] <= start_bias_i[lane];
        end
        s_drain_cnt_q <= 3'd0;
        s_aux_max_q   <= 8'h80;
        s_aux_sum_q   <= 32'd0;
        s_aux_mode_q  <= 2'd0;
      end
      if (s_dw_accept && !s_dw_ovf_any) begin
        for (int lane = 0; lane < LaneCount; lane++) begin
          if (dw_lane_valid_i[lane]) begin
            s_sum_q[lane] <= s_sum_ext[lane][31:0];
          end
        end
      end
      // Depthwise overflow wins the recorded lane over a same-cycle aux
      // overflow; the aux unit reports its dedicated encoding otherwise.
      if (s_dw_accept && s_dw_ovf_any) begin
        s_fault_lane_q <= s_dw_fault_lane;
      end else if (s_aux_sum_ovf_evt) begin
        s_fault_lane_q <= AuxFaultLane;
      end
      if (s_aux_accept) begin
        if (aux_op_i == AuxOpMax) begin
          if ($signed(aux_data_i) > s_aux_max_q) begin
            s_aux_max_q <= aux_data_i;
          end
          s_aux_mode_q <= AuxOpMax;
        end else if (!s_aux_ovf) begin
          s_aux_sum_q  <= s_aux_sum_ext[31:0];
          s_aux_mode_q <= AuxOpSum;
        end
      end
      if ((s_state_q == Accumulate) && (s_state_d == Draining)) begin
        s_drain_cnt_q <= 3'd0;
      end else if ((s_state_q == Draining) && drain_data_ready_i) begin
        s_drain_cnt_q <= s_drain_cnt_q + 3'd1;
      end
    end
  end

`ifndef SV_ASSRT_DISABLE
  // A stalled drain beat holds its lane sums and lane index: the flag samples
  // "no handshake completed last cycle", so the $stable checks compare across
  // exactly the cycles where no update was allowed.
  logic s_drain_stall_q;
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_drain_stall_q <= 1'b0;
    end else begin
      s_drain_stall_q <= (s_state_q == Draining) && !drain_data_ready_i;
      if (s_drain_stall_q) begin
        assert ($stable(s_sum_q));
        assert ($stable(s_drain_cnt_q));
      end
    end
  end
`endif
endmodule
