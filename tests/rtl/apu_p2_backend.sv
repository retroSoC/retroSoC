// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// Verification-only deterministic endpoint for the production P2 ring scheduler.
module apu_p2_backend (
    input  logic          clk_i,
    input  logic          rst_n_i,
    input  logic          abort_i,
    input  logic          hold_result_i,
    input  logic          result_error_i,
    input  logic [   5:0] result_code_i,
    input  logic [   3:0] result_stage_i,
    input  logic [   1:0] result_resp_i,
    input  logic          job_valid_i,
    output logic          job_ready_o,
    input  logic [1023:0] descriptor_i,
    input  logic [   7:0] index_i,
    output logic          result_valid_o,
    input  logic          result_ready_i,
    output logic          result_error_o,
    output logic [   5:0] result_code_o,
    output logic [   3:0] result_stage_o,
    output logic [   1:0] result_resp_o,
    output logic [  31:0] input_used_o,
    output logic [  31:0] output_bytes_o,
    output logic [  31:0] frames_o,
    output logic [  31:0] source_info_o,
    output logic [  31:0] cycles_o,
    output logic [  31:0] detail_o,
    output logic [  31:0] accepted_jobs_o
);
  logic        s_pending_q;
  logic        s_error_q;
  logic [ 5:0] s_code_q;
  logic [ 3:0] s_stage_q;
  logic [ 1:0] s_resp_q;
  logic [ 7:0] s_index_q;
  logic [31:0] s_input_length_q;
  logic [31:0] s_output_capacity_q;
  logic [31:0] s_accepted_jobs_q;

  assign job_ready_o     = !s_pending_q && !abort_i;
  assign result_valid_o  = s_pending_q && !hold_result_i;
  assign result_error_o  = s_error_q;
  assign result_code_o   = s_code_q;
  assign result_stage_o  = s_stage_q;
  assign result_resp_o   = s_resp_q;
  assign input_used_o    = s_input_length_q;
  assign output_bytes_o  = s_output_capacity_q;
  assign frames_o        = s_input_length_q >> 2;
  assign source_info_o   = 32'h0004_0000 | {24'd0, s_index_q};
  assign cycles_o        = 32'd64 + {24'd0, s_index_q};
  assign detail_o        = 32'h5032_0000 | {24'd0, s_index_q};
  assign accepted_jobs_o = s_accepted_jobs_q;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_pending_q         <= 1'b0;
      s_error_q           <= 1'b0;
      s_code_q            <= 6'd0;
      s_stage_q           <= 4'd0;
      s_resp_q            <= 2'd0;
      s_index_q           <= 8'd0;
      s_input_length_q    <= 32'd0;
      s_output_capacity_q <= 32'd0;
      s_accepted_jobs_q   <= 32'd0;
    end else begin
      if (abort_i) s_pending_q <= 1'b0;
      if (job_valid_i && job_ready_o) begin
        s_pending_q         <= 1'b1;
        s_error_q           <= result_error_i;
        s_code_q            <= result_code_i;
        s_stage_q           <= result_stage_i;
        s_resp_q            <= result_resp_i;
        s_index_q           <= index_i;
        s_input_length_q    <= descriptor_i[(3*32)+:32];
        s_output_capacity_q <= descriptor_i[(5*32)+:32];
        s_accepted_jobs_q   <= s_accepted_jobs_q + 1'b1;
      end
      if (result_valid_o && result_ready_i) s_pending_q <= 1'b0;
    end
  end
endmodule
