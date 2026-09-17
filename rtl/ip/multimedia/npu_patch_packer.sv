// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// NPU patch packer: bounded NHWC gather transpose from a raw gather half into
// packed A rows. Dense (PackDense): packed row k (byte address k*8) holds
// byte lane p = raw_byte(p*K + k) for p < M and the input zero point above;
// raw layout is [spatial_lane][k_in_slice]. Depthwise (PackDepthwise): packed
// row (s*K + k) holds lane c = raw_byte((s*K + k)*8 + c) for c < channels and
// the input zero point above; raw layout is [spatial_lane][kernel_k]
// [channel_lane] and K <= 9. Contract refinement: the raw read and packed
// write addresses are [12:0] so they span an 8192-byte half.
//
// Serial gather: one raw 32-bit read per produced byte, pipelined one byte
// per cycle after the one-cycle synchronous-read fill. A packed 64-bit row
// retires every (lane_count + 2) cycles, i.e. 0.8 bytes/cycle at M = 8.
module npu_patch_packer (
    input  logic                       clk_i,
    input  logic                       rst_n_i,
    input  logic                       start_valid_i,
    output logic                       start_ready_o,
    input  npu_pkg::pack_mode_e        start_mode_i,
    input  logic                [10:0] start_k_i,           // dense 1..1024, depthwise 1..9
    input  logic                [ 3:0] start_positions_i,   // dense: M output positions 1..8
    input  logic                [ 3:0] start_channels_i,    // depthwise: valid channel lanes 1..8
    input  logic signed         [ 7:0] start_in_zero_i,
    output logic                       busy_o,
    output logic                       done_pulse_o,
    output logic                       raw_read_valid_o,
    output logic                [12:0] raw_read_addr_o,
    input  logic                [31:0] raw_read_data_i,
    output logic                       pack_write_valid_o,
    output logic                [12:0] pack_write_addr_o,
    output logic                [63:0] pack_write_data_o,
    output logic                [ 7:0] pack_write_strb_o
);
  typedef enum logic [1:0] {
    Idle,
    Gather,
    Write,
    Done
  } state_e;

  state_e                     s_state_d;
  state_e                     s_state_q;
  npu_pkg::pack_mode_e        s_mode_q;
  logic                [10:0] s_k_q;
  logic                [ 3:0] s_positions_q;
  logic                [ 3:0] s_channels_q;
  logic signed         [ 7:0] s_in_zero_q;
  logic                [10:0] s_row_cnt_q;
  logic                [ 3:0] s_issue_lane_q;
  logic                [ 3:0] s_capture_cnt_q;
  logic                [ 2:0] s_capture_lane_q;
  logic                [ 1:0] s_capture_sel_q;
  logic                       s_inflight_q;
  logic                [12:0] s_lane_base_q;
  logic                [63:0] s_row_q;
  logic                [ 3:0] s_lane_count;
  logic                [10:0] s_row_total;
  logic                [12:0] s_issue_addr;
  logic                       s_issue_fire;
  logic                       s_last_capture;
  logic                       s_row_start;

  // Valid lanes per row: M dense positions, channel lanes depthwise. Row
  // count: K dense rows, M*K depthwise rows (K <= 9, so the product fits).
  assign s_lane_count = (s_mode_q == npu_pkg::PackDense) ? s_positions_q : s_channels_q;
  assign s_row_total = (s_mode_q == npu_pkg::PackDense) ? s_k_q :
      11'(8'(s_positions_q) * 8'(s_k_q[3:0]));
  // Dense byte address lane*K + row (lane base accumulated per issued lane);
  // depthwise byte address row*8 + lane ([spatial][kernel_k][channel] order).
  assign s_issue_addr = (s_mode_q == npu_pkg::PackDense) ?
      s_lane_base_q + {2'b00, s_row_cnt_q} :
      {s_row_cnt_q[9:0], 3'b000} + {10'd0, s_issue_lane_q[2:0]};
  assign s_issue_fire = (s_state_q == Gather) && (s_issue_lane_q < s_lane_count);
  assign s_last_capture = (s_state_q == Gather) && s_inflight_q &&
      (s_capture_cnt_q == (s_lane_count - 4'd1));

  always_comb begin
    s_state_d   = s_state_q;
    s_row_start = 1'b0;
    unique case (s_state_q)
      Idle: begin
        if (start_valid_i) begin
          s_state_d   = Gather;
          s_row_start = 1'b1;
        end
      end
      Gather: begin
        if (s_last_capture) begin
          s_state_d = Write;
        end
      end
      Write: begin
        if (s_row_cnt_q == (s_row_total - 11'd1)) begin
          s_state_d = Done;
        end else begin
          s_state_d   = Gather;
          s_row_start = 1'b1;
        end
      end
      Done: begin
        s_state_d = Idle;
      end
      default: begin
        s_state_d = Idle;
      end
    endcase
  end

  assign start_ready_o      = (s_state_q == Idle);
  assign busy_o             = (s_state_q != Idle);
  assign done_pulse_o       = (s_state_q == Done);
  assign raw_read_valid_o   = s_issue_fire;
  assign raw_read_addr_o    = s_issue_addr;
  assign pack_write_valid_o = (s_state_q == Write);
  assign pack_write_addr_o  = {s_row_cnt_q[9:0], 3'b000};
  assign pack_write_data_o  = s_row_q;
  assign pack_write_strb_o  = 8'hff;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q        <= Idle;
      s_mode_q         <= npu_pkg::PackDense;
      s_k_q            <= 11'd1;
      s_positions_q    <= 4'd1;
      s_channels_q     <= 4'd1;
      s_in_zero_q      <= 8'd0;
      s_row_cnt_q      <= 11'd0;
      s_issue_lane_q   <= 4'd0;
      s_capture_cnt_q  <= 4'd0;
      s_capture_lane_q <= 3'd0;
      s_capture_sel_q  <= 2'd0;
      s_inflight_q     <= 1'b0;
      s_lane_base_q    <= 13'd0;
      s_row_q          <= 64'd0;
    end else begin
      s_state_q    <= s_state_d;
      s_inflight_q <= s_issue_fire;
      if ((s_state_q == Idle) && start_valid_i) begin
        s_mode_q      <= start_mode_i;
        s_k_q         <= start_k_i;
        s_positions_q <= start_positions_i;
        s_channels_q  <= start_channels_i;
        s_in_zero_q   <= start_in_zero_i;
        s_row_cnt_q   <= 11'd0;
      end
      if (s_row_start) begin
        s_issue_lane_q  <= 4'd0;
        s_capture_cnt_q <= 4'd0;
        s_lane_base_q   <= 13'd0;
        // Invalid lanes keep the input zero point; valid lanes are overwritten
        // by captures.
        s_row_q         <= {8{(s_state_q == Idle) ? start_in_zero_i : s_in_zero_q}};
      end
      if (s_issue_fire) begin
        s_issue_lane_q   <= s_issue_lane_q + 4'd1;
        s_capture_lane_q <= s_issue_lane_q[2:0];
        s_capture_sel_q  <= s_issue_addr[1:0];
        if (s_mode_q == npu_pkg::PackDense) begin
          s_lane_base_q <= s_lane_base_q + {2'b00, s_k_q};
        end
      end
      if (s_inflight_q && (s_state_q == Gather)) begin
        s_row_q[s_capture_lane_q*8+:8] <= raw_read_data_i[s_capture_sel_q*8+:8];
        s_capture_cnt_q                <= s_capture_cnt_q + 4'd1;
      end
      if ((s_state_q == Write) && (s_state_d == Gather)) begin
        s_row_cnt_q <= s_row_cnt_q + 11'd1;
      end
    end
  end

`ifndef SV_ASSRT_DISABLE
  always_ff @(posedge clk_i) begin
    if (rst_n_i && (s_state_q == Idle) && start_valid_i) begin
      assert ((start_k_i >= 11'd1) && (start_k_i <= 11'(npu_pkg::MaxKSlice)));
      assert ((start_positions_i >= 4'd1) && (start_positions_i <= 4'd8));
      assert ((start_channels_i >= 4'd1) && (start_channels_i <= 4'd8));
      if (start_mode_i == npu_pkg::PackDepthwise) begin
        assert (start_k_i <= 11'd9);
      end
    end
  end
`endif
endmodule
