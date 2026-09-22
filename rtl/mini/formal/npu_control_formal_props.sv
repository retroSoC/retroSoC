// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module npu_control_formal;
  (* anyseq *) (* gclk *)reg           clk_i;
  wire          rst_n_i;
  wire          f_past_valid;
  wire  [  1:0] scenario;
  wire  [  6:0] cycle;
  wire          launch_req_valid;
  wire          launch_req_ready;
  wire  [127:0] launch_req_payload;
  wire          result_valid;
  wire          result_ready;
  wire  [169:0] result_payload;
  wire          snapshot_req_valid;
  wire          snapshot_req_ready;
  wire          snapshot_resp_valid;
  wire          snapshot_resp_ready;
  wire  [671:0] snapshot_resp_payload;
  wire          resource_quiesce;
  wire          block_ack;
  wire          link_up;
  wire          flush_active;
  wire  [ 31:0] recovery_generation;
  wire          hp_launch_valid;
  wire          hp_launch_ready;
  wire  [127:0] hp_launch_payload;
  wire          hp_result_valid;
  wire          hp_result_ready;
  wire  [169:0] hp_result_payload;
  wire          hp_snapshot_req_valid;
  wire          hp_snapshot_req_ready;
  wire          hp_snapshot_resp_valid;
  wire          hp_snapshot_resp_ready;
  wire  [671:0] hp_snapshot_resp_payload;

  logic         s_launch_seen_q;
  logic         s_result_seen_q;
  logic         s_snapshot_seen_q;

  npu_control_formal_design u_design (.*);

  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      s_launch_seen_q   <= 1'b0;
      s_result_seen_q   <= 1'b0;
      s_snapshot_seen_q <= 1'b0;
    end else begin
      assume (scenario <= 2'd3);
      if (hp_launch_valid && hp_launch_ready) begin
        assert (link_up);
        assert (hp_launch_payload == launch_req_payload);
        assert (!s_launch_seen_q);
        s_launch_seen_q <= 1'b1;
      end
      if (result_valid && result_ready) begin
        assert (result_payload == hp_result_payload);
        assert (!s_result_seen_q);
        s_result_seen_q <= 1'b1;
      end
      if (snapshot_resp_valid && snapshot_resp_ready) begin
        assert (snapshot_resp_payload == hp_snapshot_resp_payload);
        assert (!s_snapshot_seen_q);
        s_snapshot_seen_q <= 1'b1;
      end
      if (!link_up) begin
        assert (!hp_launch_valid);
        assert (!hp_snapshot_req_valid);
      end
      if (block_ack) begin
        assert (resource_quiesce);
        assert (!launch_req_valid);
      end
    end

    if (f_past_valid && $past(rst_n_i)) begin
      if ($past(hp_launch_valid && !hp_launch_ready)) begin
        assert (hp_launch_valid);
        assert (hp_launch_payload == $past(hp_launch_payload));
      end
      if ($past(result_valid && !result_ready)) begin
        assert (result_valid);
        assert (result_payload == $past(result_payload));
      end
      if ($past(snapshot_resp_valid && !snapshot_resp_ready)) begin
        assert (snapshot_resp_valid);
        assert (snapshot_resp_payload == $past(snapshot_resp_payload));
      end
    end

    cover (rst_n_i && s_launch_seen_q && s_result_seen_q);
    cover (rst_n_i && s_snapshot_seen_q);
    cover (rst_n_i && block_ack);
    cover (rst_n_i && flush_active);
    cover (rst_n_i && (recovery_generation != 32'd0));
  end
endmodule
