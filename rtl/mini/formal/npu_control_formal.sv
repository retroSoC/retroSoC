// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "npu_define.svh"

module npu_control_formal_design (
    input  logic                                         clk_i,
    output logic                                         rst_n_i,
    output logic                                         f_past_valid,
    output logic [                                  1:0] scenario,
    output logic [                                  6:0] cycle,
    output logic                                         launch_req_valid,
    output logic                                         launch_req_ready,
    output logic [  `APB4_NPU__LAUNCH_PAYLOAD_WIDTH-1:0] launch_req_payload,
    output logic                                         result_valid,
    output logic                                         result_ready,
    output logic [  `APB4_NPU__RESULT_PAYLOAD_WIDTH-1:0] result_payload,
    output logic                                         snapshot_req_valid,
    output logic                                         snapshot_req_ready,
    output logic                                         snapshot_resp_valid,
    output logic                                         snapshot_resp_ready,
    output logic [`APB4_NPU__SNAPSHOT_PAYLOAD_WIDTH-1:0] snapshot_resp_payload,
    output logic                                         resource_quiesce,
    output logic                                         block_ack,
    output logic                                         link_up,
    output logic                                         flush_active,
    output logic [                                 31:0] recovery_generation,
    output logic                                         hp_launch_valid,
    output logic                                         hp_launch_ready,
    output logic [  `APB4_NPU__LAUNCH_PAYLOAD_WIDTH-1:0] hp_launch_payload,
    output logic                                         hp_result_valid,
    output logic                                         hp_result_ready,
    output logic [  `APB4_NPU__RESULT_PAYLOAD_WIDTH-1:0] hp_result_payload,
    output logic                                         hp_snapshot_req_valid,
    output logic                                         hp_snapshot_req_ready,
    output logic                                         hp_snapshot_resp_valid,
    output logic                                         hp_snapshot_resp_ready,
    output logic [`APB4_NPU__SNAPSHOT_PAYLOAD_WIDTH-1:0] hp_snapshot_resp_payload
);
  (* anyconst *)logic [                       1:0] f_scenario;
  logic [`APB4_NPU__EPOCH_WIDTH-1:0] s_hp_epoch_req;
  logic [`APB4_NPU__EPOCH_WIDTH-1:0] s_hp_epoch_ack_q;
  logic                              s_hp_busy_q;
  logic                              s_launch_issued_q;
  logic                              s_snapshot_issued_q;

  assign scenario = f_scenario;
  assign rst_n_i = cycle >= 7'd2;
  assign launch_req_valid = rst_n_i && !s_launch_issued_q && (cycle >= 7'd14) && (scenario != 2'd3);
  assign launch_req_payload = `APB4_NPU__LAUNCH_PAYLOAD_WIDTH'(32'h4E50_5536);
  assign result_ready = cycle[0];
  assign snapshot_req_valid = rst_n_i && !s_snapshot_issued_q && (cycle >= 7'd42);
  assign snapshot_resp_ready = cycle[1];
  assign resource_quiesce = rst_n_i && (scenario == 2'd1) && (cycle >= 7'd15);
  assign hp_launch_ready = cycle[0];
  assign hp_result_valid = s_hp_busy_q && (cycle >= 7'd34);
  assign hp_result_payload = `APB4_NPU__RESULT_PAYLOAD_WIDTH'(64'h0000_0001_4E50_5536);
  assign hp_snapshot_req_ready = cycle[0];
  assign hp_snapshot_resp_valid = hp_snapshot_req_valid && (cycle >= 7'd50);
  assign hp_snapshot_resp_payload = `APB4_NPU__SNAPSHOT_PAYLOAD_WIDTH'(64'h0000_0002_4E50_5536);

  npu_control_cdc u_dut (
      .clk_i                     (clk_i),
      .rst_n_i                   (rst_n_i),
      .clk_hp_i                  (clk_i),
      .rst_hp_n_i                (rst_n_i),
      .launch_req_valid_i        (launch_req_valid),
      .launch_req_ready_o        (launch_req_ready),
      .launch_req_payload_i      (launch_req_payload),
      .result_valid_o            (result_valid),
      .result_ready_i            (result_ready),
      .result_payload_o          (result_payload),
      .snapshot_req_valid_i      (snapshot_req_valid),
      .snapshot_req_ready_o      (snapshot_req_ready),
      .snapshot_resp_valid_o     (snapshot_resp_valid),
      .snapshot_resp_ready_i     (snapshot_resp_ready),
      .snapshot_resp_payload_o   (snapshot_resp_payload),
      .soft_reset_i              ((scenario == 2'd2) && (cycle == 7'd36)),
      .shell_idle_i              (!launch_req_valid),
      .resource_quiesce_i        (resource_quiesce),
      .resource_reset_i          (1'b0),
      .link_up_o                 (link_up),
      .flush_active_o            (flush_active),
      .recovery_generation_o     (recovery_generation),
      .block_ack_o               (block_ack),
      .hp_launch_valid_o         (hp_launch_valid),
      .hp_launch_ready_i         (hp_launch_ready),
      .hp_launch_payload_o       (hp_launch_payload),
      .hp_result_valid_i         (hp_result_valid),
      .hp_result_ready_o         (hp_result_ready),
      .hp_result_payload_i       (hp_result_payload),
      .hp_snapshot_req_valid_o   (hp_snapshot_req_valid),
      .hp_snapshot_req_ready_i   (hp_snapshot_req_ready),
      .hp_snapshot_resp_valid_i  (hp_snapshot_resp_valid),
      .hp_snapshot_resp_ready_o  (hp_snapshot_resp_ready),
      .hp_snapshot_resp_payload_i(hp_snapshot_resp_payload),
      .hp_epoch_req_o            (s_hp_epoch_req),
      .hp_epoch_ack_i            (s_hp_epoch_ack_q),
      .hp_quiesce_req_o          (),
      .hp_quiesce_ack_i          (resource_quiesce && !s_hp_busy_q),
      .hp_busy_i                 (s_hp_busy_q),
      .hp_draining_i             (1'b0),
      .hp_pause_active_i         (1'b0),
      .hp_flush_i                ((scenario == 2'd3) && (cycle == 7'd36)),
      .hp_busy_o                 (),
      .hp_draining_o             (),
      .clock_paused_o            ()
  );

  always_ff @(posedge clk_i) begin
    f_past_valid <= 1'b1;
    if (cycle != 7'h7f) begin
      cycle <= cycle + 1'b1;
    end
    if (!rst_n_i) begin
      s_hp_epoch_ack_q    <= '0;
      s_hp_busy_q         <= 1'b0;
      s_launch_issued_q   <= 1'b0;
      s_snapshot_issued_q <= 1'b0;
    end else begin
      s_hp_epoch_ack_q <= s_hp_epoch_req;
      if (launch_req_valid && launch_req_ready) begin
        s_launch_issued_q <= 1'b1;
      end
      if (snapshot_req_valid && snapshot_req_ready) begin
        s_snapshot_issued_q <= 1'b1;
      end
      if (hp_launch_valid && hp_launch_ready) begin
        s_hp_busy_q <= 1'b1;
      end else if (hp_result_valid && hp_result_ready) begin
        s_hp_busy_q <= 1'b0;
      end
    end
  end

  initial begin
    cycle               = '0;
    f_past_valid        = 1'b0;
    s_hp_epoch_ack_q    = '0;
    s_hp_busy_q         = 1'b0;
    s_launch_issued_q   = 1'b0;
    s_snapshot_issued_q = 1'b0;
  end
endmodule
