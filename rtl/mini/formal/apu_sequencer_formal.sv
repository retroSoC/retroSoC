// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_sequencer_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic [ 1:0] scenario,
    output logic [ 5:0] cycle,
    output logic [31:0] status,
    output logic [31:0] retired,
    output logic [31:0] result,
    output logic        trapped,
    output logic        trap_event,
    output logic        abort_done,
    output logic        trap_seen,
    output logic        abort_seen,
    output logic        idle,
    output logic        fault_valid,
    output logic [ 5:0] fault_code,
    output logic [ 3:0] fault_stage,
    output logic [ 1:0] fault_resp,
    output logic [ 7:0] fault_index,
    output logic [31:0] fault_addr,
    output logic [31:0] fault_detail
);
  (* anyconst *)logic [1:0] f_scenario;
  logic [5:0] s_cycle_q;
  logic s_fetch, s_fetch_pending_q;
  logic [10:0] s_fetch_addr, s_fetch_addr_q;
  logic [63:0]       s_fetch_data;
  logic [15:0][31:0] s_gpr;
  logic s_trap_seen_q, s_abort_seen_q;
  logic [2:0][10:0] s_entry_last;
  logic [2:0][23:0] s_entry_max_retired;

  assign scenario = f_scenario;
  assign cycle = s_cycle_q;
  assign result = s_gpr[2];
  assign trap_seen = s_trap_seen_q;
  assign abort_seen = s_abort_seen_q;
  assign s_entry_last = (f_scenario == 2'd3) ? {11'd6, 11'd6, 11'd6} : {11'd3, 11'd3, 11'd3};
  assign s_entry_max_retired = (f_scenario == 2'd3) ?
      {24'd16, 24'd16, 24'd16} : {24'd8, 24'd8, 24'd8};

  always_comb begin
    if (f_scenario == 2'd3) begin
      unique case (s_fetch_addr_q)
        11'd0:   s_fetch_data = 64'h1100_0000_0000_0002;
        11'd1:   s_fetch_data = 64'h0600_0000_0000_0000;
        11'd2:   s_fetch_data = 64'h0000_0000_0000_0000;
        11'd3:   s_fetch_data = 64'h0700_0000_0000_0002;
        11'd4:   s_fetch_data = 64'h0400_0000_0000_0001;
        11'd5:   s_fetch_data = 64'h0100_0000_0000_0000;
        default: s_fetch_data = 64'h0500_0000_0000_0000;
      endcase
    end else begin
      unique case (s_fetch_addr_q)
        11'd0:   s_fetch_data = 64'h1100_0000_0000_0002;
        11'd1:   s_fetch_data = 64'h1101_0000_0000_0003;
        11'd2:   s_fetch_data = 64'h1202_0100_0000_0000;
        default: s_fetch_data = 64'h0100_0000_0000_0000;
      endcase
    end
  end

  apu_codec_sequencer u_dut (
      .clk_i,
      .rst_n_i,
      .soft_reset_i             (1'b0),
      .resource_reset_i         (1'b0),
      .counter_clear_i          (1'b0),
      .abort_i                  ((f_scenario == 2'd2) && (s_cycle_q == 6'd8)),
      .launch_i                 (s_cycle_q == 6'd1),
      .launch_entry_i           (2'd0),
      .image_valid_i            (1'b1),
      .timeout_i                ((f_scenario == 2'd1) ? 32'd1 : 32'd16),
      .entry_pc_i               ({11'd0, 11'd0, 11'd0}),
      .entry_first_i            ({11'd0, 11'd0, 11'd0}),
      .entry_last_i             (s_entry_last),
      .entry_max_loop_i         ({16'd4, 16'd4, 16'd4}),
      .entry_max_retired_i      (s_entry_max_retired),
      .entry_scratch_base_i     ('0),
      .entry_scratch_bytes_i    ('0),
      .entry_primitive_mask_i   ('0),
      .entry_table_offset_i     ('0),
      .entry_table_bytes_i      ('0),
      .input_exhausted_i        (1'b1),
      .input_ready_i            (1'b0),
      .output_ready_i           (1'b1),
      .kernel_done_i            (1'b0),
      .transport_idle_success_i (1'b1),
      .stall_i                  (1'b0),
      .cause_valid_i            (1'b0),
      .cause_code_i             (6'd0),
      .cause_stage_i            (4'd0),
      .cause_resp_i             (2'd0),
      .cause_index_i            (8'd0),
      .cause_addr_i             (32'd0),
      .cause_detail_i           (32'd0),
      .primitive_req_valid_o    (),
      .primitive_req_ready_i    (1'b0),
      .primitive_instruction_o  (),
      .primitive_source0_o      (),
      .primitive_source1_o      (),
      .primitive_destination_o  (),
      .primitive_result_valid_i (1'b0),
      .primitive_result_dst_i   (4'd0),
      .primitive_result_data_i  ('0),
      .primitive_result_words_i (3'd0),
      .primitive_result_kernel_i(1'b0),
      .primitive_error_i        (1'b0),
      .primitive_error_code_i   (6'd0),
      .primitive_error_stage_i  (4'd0),
      .primitive_error_reason_i (8'd0),
      .fetch_o                  (s_fetch),
      .fetch_addr_o             (s_fetch_addr),
      .fetch_data_i             (s_fetch_data),
      .fetch_valid_i            (s_fetch_pending_q),
      .stat_o                   (status),
      .retired_o                (retired),
      .gpr_o                    (s_gpr),
      .trapped_o                (trapped),
      .trap_event_o             (trap_event),
      .abort_done_o             (abort_done),
      .fault_valid_o            (fault_valid),
      .fault_code_o             (fault_code),
      .fault_stage_o            (fault_stage),
      .fault_resp_o             (fault_resp),
      .fault_index_o            (fault_index),
      .fault_addr_o             (fault_addr),
      .fault_detail_o           (fault_detail),
      .perf_retired_o           (),
      .active_scratch_base_o    (),
      .active_scratch_bytes_o   (),
      .active_primitive_mask_o  (),
      .active_table_offset_o    (),
      .active_table_bytes_o     (),
      .launch_epoch_o           (),
      .idle_o                   (idle)
  );

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
    if (!rst_n_i) begin
      s_cycle_q         <= 6'd0;
      s_fetch_pending_q <= 1'b0;
      s_fetch_addr_q    <= 11'd0;
      s_trap_seen_q     <= 1'b0;
      s_abort_seen_q    <= 1'b0;
    end else begin
      if (s_cycle_q != 6'h3f) s_cycle_q <= s_cycle_q + 1'b1;
      s_fetch_pending_q <= s_fetch;
      if (s_fetch) s_fetch_addr_q <= s_fetch_addr;
      if (trap_event) s_trap_seen_q <= 1'b1;
      if (abort_done) s_abort_seen_q <= 1'b1;
    end
  end
endmodule
