// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_kws_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        dma_request_valid,
    output logic [31:0] dma_request_address,
    output logic [31:0] dma_request_bytes,
    output logic        dma_ready,
    output logic        local_request,
    output logic        valid,
    output logic        lock,
    output logic        done,
    output logic        abort_done,
    output logic        loader_busy,
    output logic [ 5:0] error_code,
    output logic [ 3:0] error_stage,
    output logic [ 1:0] error_resp,
    output logic [31:0] error_address,
    output logic [31:0] error_detail,
    output logic        early_error_pending,
    output logic [ 5:0] expected_error_code,
    output logic [ 3:0] expected_error_stage,
    output logic [ 1:0] expected_error_resp,
    output logic [31:0] expected_error_address,
    output logic [31:0] requested_size,
    output logic        kws_direct_allowed,
    output logic        kws_start,
    output logic        kws_start_ready,
    output logic        kws_abort,
    output logic        kws_direct_done,
    output logic        kws_transport_start,
    output logic        kws_busy,
    output logic        kws_idle
);
  logic          s_start_q;
  logic [  31:0] s_address_q;
  (* anyconst *)logic [  31:0] s_size_q;
  logic [  31:0] s_expected_crc_q;
  logic [1023:0] s_kws_descriptor;
  (* anyseq *)logic          s_loader_abort;
  (* anyseq *)logic          s_dma_done;
  (* anyseq *)logic          s_dma_error;
  (* anyseq *)logic [   5:0] s_dma_error_code;
  (* anyseq *)logic [   3:0] s_dma_error_stage;
  (* anyseq *)logic [   1:0] s_dma_error_resp;
  (* anyseq *)logic [  31:0] s_dma_error_address;
  (* anyseq *)logic          s_kws_start_ready;
  (* anyseq *)logic          s_kws_abort;

  assign requested_size = s_size_q;

  always_comb begin
    s_kws_descriptor             = '0;
    s_kws_descriptor[(0*32)+:32] = 32'd1;
    s_kws_descriptor[(2*32)+:32] = 32'h1000_0000;
    s_kws_descriptor[(3*32)+:32] = 32'd32000;
    s_kws_descriptor[(6*32)+:32] = 32'h0102_3e80;
    s_kws_descriptor[(9*32)+:32] = 32'h0000_0180;
  end

  apu_kws_model_loader u_dut (
      .clk_i                   (clk_i),
      .rst_n_i                 (rst_n_i),
      .start_i                 (s_start_q),
      .abort_i                 (s_loader_abort),
      .soft_reset_i            (1'b0),
      .resource_reset_request_i(1'b0),
      .resource_reset_i        (1'b0),
      .quiesce_i               (1'b1),
      .address_i               (s_address_q),
      .size_i                  (s_size_q),
      .expected_crc_i          (s_expected_crc_q),
      .acl_base_i              (32'd0),
      .acl_limit_i             (32'hffff_ffff),
      .dma_request_valid_o     (dma_request_valid),
      .dma_request_ready_i     (1'b1),
      .dma_request_address_o   (dma_request_address),
      .dma_request_bytes_o     (dma_request_bytes),
      .dma_data_i              (32'd0),
      .dma_keep_i              (4'hf),
      .dma_last_i              (1'b0),
      .dma_valid_i             (1'b0),
      .dma_ready_o             (dma_ready),
      .dma_done_i              (s_dma_done),
      .dma_error_i             (s_dma_done && s_dma_error),
      .dma_error_code_i        (s_dma_error_code),
      .dma_error_stage_i       (s_dma_error_stage),
      .dma_error_resp_i        (s_dma_error_resp),
      .dma_error_address_i     (s_dma_error_address),
      .local_request_o         (local_request),
      .local_address_o         (),
      .local_data_o            (),
      .local_strb_o            (),
      .local_ready_i           (1'b1),
      .busy_o                  (loader_busy),
      .valid_o                 (valid),
      .lock_o                  (lock),
      .actual_crc_o            (),
      .status_o                (),
      .error_code_o            (error_code),
      .error_stage_o           (error_stage),
      .error_resp_o            (error_resp),
      .error_address_o         (error_address),
      .error_detail_o          (error_detail),
      .config_publish_o        (),
      .config_default_o        (),
      .done_o                  (done),
      .abort_done_o            (abort_done)
  );

  apu_codec_controller #(
      .EnableP7(1'b1)
  ) u_controller (
      .clk_i                        (clk_i),
      .rst_n_i                      (rst_n_i),
      .soft_reset_i                 (1'b0),
      .resource_reset_request_i     (1'b0),
      .resource_reset_apply_i       (1'b0),
      .abort_i                      (s_kws_abort),
      .quiesce_i                    (1'b0),
      .block_new_i                  (1'b0),
      .ring_enabled_i               (1'b0),
      .ring_base_i                  (32'd0),
      .read_base_i                  (32'h1000_0000),
      .read_limit_i                 (32'h1000_7cff),
      .write_base_i                 (32'hffff_ffff),
      .write_limit_i                (32'd0),
      .direct_start_i               (s_start_q),
      .direct_descriptor_i          (s_kws_descriptor),
      .direct_allowed_o             (kws_direct_allowed),
      .ring_job_valid_i             (1'b0),
      .ring_descriptor_i            ('0),
      .ring_index_i                 (8'd0),
      .ring_result_ready_i          (1'b0),
      .microcode_valid_i            (1'b1),
      .microcode_lock_i             (1'b1),
      .kws_model_valid_i            (1'b1),
      .kws_model_lock_i             (1'b1),
      .kws_memory_armed_i           (1'b1),
      .entry_scratch_base_i         ('0),
      .entry_scratch_bytes_i        ('0),
      .sequencer_idle_i             (1'b1),
      .sequencer_end_i              (1'b0),
      .sequencer_trap_i             (1'b0),
      .sequencer_fault_code_i       (6'd0),
      .sequencer_fault_stage_i      (4'd0),
      .sequencer_fault_resp_i       (2'd0),
      .sequencer_fault_detail_i     (32'd0),
      .transport_job_start_o        (kws_transport_start),
      .transport_context_ready_i    (1'b0),
      .transport_job_done_i         (1'b0),
      .transport_frame_commit_i     (1'b0),
      .transport_input_used_i       (32'd0),
      .transport_output_bytes_i     (32'd0),
      .transport_frames_i           (32'd0),
      .transport_source_info_i      (32'd0),
      .transport_cycles_i           (32'd0),
      .transport_detail_i           (32'd0),
      .transport_diagnostic_offset_i(32'd0),
      .transport_result_code_i      (6'd0),
      .transport_result_stage_i     (4'd0),
      .transport_result_resp_i      (2'd0),
      .kws_start_o                  (kws_start),
      .kws_start_ready_i            (s_kws_start_ready),
      .kws_config_valid_o           (),
      .kws_config_o                 (),
      .kws_done_i                   (1'b0),
      .kws_error_i                  (1'b0),
      .kws_error_code_i             (6'd0),
      .kws_error_stage_i            (4'd0),
      .kws_error_resp_i             (2'd0),
      .kws_error_address_i          (32'd0),
      .kws_error_detail_i           (32'd0),
      .kws_input_used_i             (32'd0),
      .kws_result_i                 (32'd0),
      .direct_done_o                (kws_direct_done),
      .busy_o                       (kws_busy),
      .idle_o                       (kws_idle)
  );

  assign kws_start_ready = s_kws_start_ready;
  assign kws_abort       = s_kws_abort;

  initial begin
    rst_n_i          = 1'b0;
    f_past_valid     = 1'b0;
    s_start_q        = 1'b0;
    s_address_q      = 32'h1000_0000;
    s_expected_crc_q = 32'hb903_4b22;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
    s_start_q    <= !f_past_valid;
    if (!rst_n_i) begin
      early_error_pending    <= 1'b0;
      expected_error_code    <= 6'd0;
      expected_error_stage   <= 4'd0;
      expected_error_resp    <= 2'd0;
      expected_error_address <= 32'd0;
    end else begin
      if (dma_ready && s_dma_done && s_dma_error) begin
        early_error_pending    <= 1'b1;
        expected_error_code    <= s_dma_error_code;
        expected_error_stage   <= s_dma_error_stage;
        expected_error_resp    <= s_dma_error_resp;
        expected_error_address <= s_dma_error_address;
      end
      if (done) early_error_pending <= 1'b0;
    end
  end
endmodule
