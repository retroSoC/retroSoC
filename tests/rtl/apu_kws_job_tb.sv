// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`timescale 1ns / 1ps
`include "apu_define.svh"

module apu_kws_job_tb;
  logic                clk;
  logic                rst_n;
  logic                abort;
  logic                block_new;
  logic                direct_start;
  logic [1023:0]       direct_descriptor;
  logic                direct_allowed;
  logic                ring_job_valid;
  logic                ring_job_ready;
  logic [1023:0]       ring_descriptor;
  logic [   7:0]       ring_index;
  logic                ring_result_valid;
  logic                ring_result_ready;
  logic                ring_result_error;
  logic [   5:0]       ring_result_code;
  logic [   3:0]       ring_result_stage;
  logic [   1:0]       ring_result_resp;
  logic [  31:0]       ring_result_input_used;
  logic [  31:0]       ring_result_frames;
  logic [  31:0]       ring_result_source_info;
  logic [  31:0]       ring_result_cycles;
  logic [  31:0]       ring_result_detail;
  logic [  31:0]       ring_result_kws;
  logic                microcode_valid;
  logic                microcode_lock;
  logic [   2:0][16:0] scratch_base;
  logic [   2:0][16:0] scratch_bytes;
  logic                kws_start;
  logic                kws_start_ready;
  logic                kws_config_valid;
  logic [  15:0]       kws_config;
  logic                kws_done;
  logic                kws_error;
  logic [   5:0]       kws_error_code;
  logic [   3:0]       kws_error_stage;
  logic [   1:0]       kws_error_resp;
  logic [  31:0]       kws_error_address;
  logic [  31:0]       kws_error_detail;
  logic [  31:0]       kws_input_used;
  logic [  31:0]       kws_result;
  logic [  31:0]       job_status;
  logic [  31:0]       job_input_used;
  logic [  31:0]       job_frames;
  logic [  31:0]       job_source_info;
  logic [  31:0]       job_cycles;
  logic [  31:0]       job_detail;
  logic                direct_done;
  logic                fault_valid;
  logic [   5:0]       fault_code;
  logic [   3:0]       fault_stage;
  logic [   1:0]       fault_resp;
  logic [   7:0]       fault_index;
  logic [  31:0]       fault_addr;
  logic [  31:0]       fault_detail;
  logic                busy;
  logic                idle;

  always #5 clk = ~clk;

  apu_codec_controller #(
      .EnableP7(1'b1)
  ) u_dut (
      .clk_i                        (clk),
      .rst_n_i                      (rst_n),
      .soft_reset_i                 (1'b0),
      .resource_reset_request_i     (1'b0),
      .resource_reset_apply_i       (1'b0),
      .abort_i                      (abort),
      .quiesce_i                    (1'b0),
      .block_new_i                  (block_new),
      .ring_enabled_i               (1'b0),
      .ring_base_i                  (32'h0000_4000),
      .read_base_i                  (32'h0000_1000),
      .read_limit_i                 (32'h0002_ffff),
      .write_base_i                 (32'h0000_4000),
      .write_limit_i                (32'h0002_ffff),
      .direct_start_i               (direct_start),
      .direct_descriptor_i          (direct_descriptor),
      .direct_allowed_o             (direct_allowed),
      .ring_job_valid_i             (ring_job_valid),
      .ring_job_ready_o             (ring_job_ready),
      .ring_descriptor_i            (ring_descriptor),
      .ring_index_i                 (ring_index),
      .ring_result_valid_o          (ring_result_valid),
      .ring_result_ready_i          (ring_result_ready),
      .ring_result_error_o          (ring_result_error),
      .ring_result_code_o           (ring_result_code),
      .ring_result_stage_o          (ring_result_stage),
      .ring_result_resp_o           (ring_result_resp),
      .ring_result_input_used_o     (ring_result_input_used),
      .ring_result_frames_o         (ring_result_frames),
      .ring_result_source_info_o    (ring_result_source_info),
      .ring_result_cycles_o         (ring_result_cycles),
      .ring_result_detail_o         (ring_result_detail),
      .ring_result_kws_o            (ring_result_kws),
      .microcode_valid_i            (microcode_valid),
      .microcode_lock_i             (microcode_lock),
      .kws_model_valid_i            (1'b1),
      .kws_model_lock_i             (1'b1),
      .kws_memory_armed_i           (1'b1),
      .entry_scratch_base_i         (scratch_base),
      .entry_scratch_bytes_i        (scratch_bytes),
      .sequencer_idle_i             (1'b1),
      .sequencer_end_i              (1'b0),
      .sequencer_trap_i             (1'b0),
      .sequencer_fault_code_i       (6'd0),
      .sequencer_fault_stage_i      (4'd0),
      .sequencer_fault_resp_i       (2'd0),
      .sequencer_fault_detail_i     (32'd0),
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
      .kws_start_ready_i            (kws_start_ready),
      .kws_config_valid_o           (kws_config_valid),
      .kws_config_o                 (kws_config),
      .kws_done_i                   (kws_done),
      .kws_error_i                  (kws_error),
      .kws_error_code_i             (kws_error_code),
      .kws_error_stage_i            (kws_error_stage),
      .kws_error_resp_i             (kws_error_resp),
      .kws_error_address_i          (kws_error_address),
      .kws_error_detail_i           (kws_error_detail),
      .kws_input_used_i             (kws_input_used),
      .kws_result_i                 (kws_result),
      .job_status_o                 (job_status),
      .job_input_used_o             (job_input_used),
      .job_frames_o                 (job_frames),
      .job_source_info_o            (job_source_info),
      .job_cycles_o                 (job_cycles),
      .job_detail_o                 (job_detail),
      .direct_done_o                (direct_done),
      .fault_valid_o                (fault_valid),
      .fault_code_o                 (fault_code),
      .fault_stage_o                (fault_stage),
      .fault_resp_o                 (fault_resp),
      .fault_index_o                (fault_index),
      .fault_addr_o                 (fault_addr),
      .fault_detail_o               (fault_detail),
      .busy_o                       (busy),
      .idle_o                       (idle)
  );

  task automatic check_condition(input logic condition_i, input string message_i);
    begin
      if (!condition_i) begin
        $display("FAIL: %s", message_i);
        $fatal(1);
      end
    end
  endtask

  task automatic make_kws_descriptor(output logic [1023:0] descriptor_o);
    begin
      descriptor_o             = '0;
      descriptor_o[(0*32)+:32] = 32'd1;
      descriptor_o[(2*32)+:32] = 32'h0001_0000;
      descriptor_o[(3*32)+:32] = 32'd32000;
      descriptor_o[(6*32)+:32] = 32'h0102_3e80;
      descriptor_o[(9*32)+:32] = 32'h0000_0100;
    end
  endtask

  task automatic start_direct_kws;
    begin
      check_condition(direct_allowed, "direct KWS admission unexpectedly failed");
      direct_start = 1'b1;
      @(posedge clk);
      #1 direct_start = 1'b0;
      wait (kws_start);
      @(posedge clk);
      #1;
      check_condition(busy, "direct KWS did not enter wait state");
      check_condition(kws_config_valid && (kws_config == 16'h0100),
                      "direct KWS did not snapshot register configuration");
    end
  endtask

  task automatic expect_invalid_ring(input int unsigned word_index_i,
                                     input logic [31:0] invalid_value_i);
    begin
      make_kws_descriptor(ring_descriptor);
      ring_descriptor[(word_index_i*32)+:32] = invalid_value_i;
      ring_job_valid                         = 1'b1;
      @(posedge clk);
      #1 ring_job_valid = 1'b0;
      check_condition(ring_result_valid && ring_result_error,
                      "invalid KWS ring descriptor did not complete");
      check_condition(
          (ring_result_code == `APB4_APU__ERROR_CODE_INVALID_RING) &&
                          (ring_result_stage == `APB4_APU__ERROR_STAGE_RING) &&
                          (ring_result_resp == 2'd0),
          "invalid KWS ring descriptor returned the wrong status tuple");
      check_condition(ring_result_detail == (32'h0700_0200 | 32'(word_index_i)),
                      "invalid KWS ring descriptor returned the wrong word index");
      check_condition(
          fault_valid &&
                          (fault_code == `APB4_APU__ERROR_CODE_INVALID_RING) &&
                          (fault_stage == `APB4_APU__ERROR_STAGE_RING) &&
                          (fault_resp == 2'd0) && (fault_index == ring_index) &&
                          (fault_detail == (32'h0700_0200 | 32'(word_index_i))),
          "invalid KWS ring first-error tuple did not match writeback");
      ring_result_ready = 1'b1;
      @(posedge clk);
      #1 ring_result_ready = 1'b0;
      check_condition(idle, "invalid KWS ring descriptor did not retire");
    end
  endtask

  initial begin
    clk               = 1'b0;
    rst_n             = 1'b0;
    abort             = 1'b0;
    block_new         = 1'b0;
    direct_start      = 1'b0;
    ring_job_valid    = 1'b0;
    ring_result_ready = 1'b0;
    ring_index        = 8'd3;
    microcode_valid   = 1'b0;
    microcode_lock    = 1'b0;
    scratch_base      = '0;
    scratch_bytes     = '0;
    kws_done          = 1'b0;
    kws_start_ready   = 1'b1;
    kws_error         = 1'b0;
    kws_error_code    = 6'd0;
    kws_error_stage   = 4'd0;
    kws_error_resp    = 2'd0;
    kws_error_address = 32'd0;
    kws_error_detail  = 32'd0;
    kws_input_used    = 32'd0;
    kws_result        = 32'd0;
    make_kws_descriptor(direct_descriptor);
    make_kws_descriptor(ring_descriptor);

    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;
    @(posedge clk);
    #1;

    check_condition(!direct_allowed, "direct KWS bypassed compatibility microcode admission");
    microcode_valid = 1'b1;
    microcode_lock  = 1'b1;
    #1;
    start_direct_kws();
    direct_descriptor[(9*32)+:32] = 32'h0000_ffff;
    #1;
    check_condition(kws_config == 16'h0100,
                    "direct KWS configuration changed after START acceptance");
    direct_descriptor[(9*32)+:32] = 32'h0000_0100;
    kws_result                    = 32'h1122_3344;
    kws_input_used                = 32'd32000;
    kws_done                      = 1'b1;
    @(posedge clk);
    #1 kws_done = 1'b0;
    check_condition(direct_done, "direct KWS completion pulse missing");
    check_condition(job_status[`APB4_APU__JOB_STATUS_DONE], "direct KWS did not complete");
    check_condition(job_input_used == 32'd32000, "direct KWS input-used mismatch");
    check_condition(job_frames == 32'd16000, "direct KWS frame count mismatch");
    check_condition(job_source_info == 32'h0082_3e80, "direct KWS source-info ABI mismatch");
    check_condition(job_detail == 32'd0, "direct KWS success detail mismatch");
    check_condition(job_cycles != 32'd0, "direct KWS cycle count is stale");

    @(posedge clk);
    #1;
    check_condition(idle, "direct KWS did not return idle");

    ring_descriptor[(9*32)+:32] = 32'h0000_02a5;
    ring_job_valid              = 1'b1;
    block_new                   = 1'b1;
    #1;
    check_condition(!ring_job_ready, "KWS disable boundary left ring admission open");
    @(posedge clk);
    #1;
    check_condition(idle, "blocked ring KWS job was accepted");
    block_new = 1'b0;
    @(posedge clk);
    #1 ring_job_valid = 1'b0;
    wait (kws_start);
    block_new       = 1'b1;
    kws_start_ready = 1'b0;
    @(posedge clk);
    #1;
    check_condition(kws_start && busy && !ring_job_ready,
                    "accepted ring KWS start was dropped while disable drained");
    kws_start_ready = 1'b1;
    @(posedge clk);
    #1;
    block_new = 1'b0;
    check_condition(!kws_start && busy, "ready KWS start did not enter wait state");
    check_condition(kws_config_valid && (kws_config == 16'h02a5),
                    "ring KWS ignored descriptor word 9");
    kws_result     = 32'ha5c3_8127;
    kws_input_used = 32'd32000;
    kws_done       = 1'b1;
    @(posedge clk);
    #1 kws_done = 1'b0;
    check_condition(ring_result_valid, "ring KWS result was not published");
    check_condition(!ring_result_error && (ring_result_code == 6'd0), "ring KWS reported an error");
    check_condition(ring_result_input_used == 32'd32000, "ring KWS input-used mismatch");
    check_condition(ring_result_frames == 32'd16000, "ring KWS frame count mismatch");
    check_condition(ring_result_source_info == 32'h0082_3e80, "ring KWS source-info ABI mismatch");
    check_condition(ring_result_detail == 32'd0, "ring KWS success detail mismatch");
    check_condition(ring_result_cycles != 32'd0, "ring KWS cycle count is stale");
    check_condition(ring_result_kws == 32'ha5c3_8127, "ring descriptor word 22 result mismatch");
    kws_result = 32'hdead_beef;
    @(posedge clk);
    #1;
    check_condition(ring_result_kws == 32'ha5c3_8127, "ring KWS result was not atomically latched");
    ring_result_ready = 1'b1;
    @(posedge clk);
    #1 ring_result_ready = 1'b0;
    check_condition(idle, "ring KWS did not return idle");

    ring_job_valid = 1'b1;
    @(posedge clk);
    #1 ring_job_valid = 1'b0;
    wait (kws_start);
    @(posedge clk);
    #1;
    kws_error         = 1'b1;
    kws_error_code    = `APB4_APU__ERROR_CODE_AXI_READ;
    kws_error_stage   = `APB4_APU__ERROR_STAGE_DMA_READ;
    kws_error_resp    = 2'd2;
    kws_error_address = 32'h0001_2340;
    kws_error_detail  = 32'd0;
    kws_input_used    = 32'd128;
    kws_done          = 1'b1;
    @(posedge clk);
    #1;
    kws_done  = 1'b0;
    kws_error = 1'b0;
    check_condition(ring_result_valid && ring_result_error,
                    "ring KWS DMA failure did not complete");
    check_condition((ring_result_input_used == 32'd128) && (ring_result_frames == 32'd64),
                    "ring KWS failure progress mismatch");
    check_condition((ring_result_source_info == 32'd0) && (ring_result_detail == 32'd0),
                    "ring KWS failure fabricated result metadata");
    check_condition(fault_valid && (fault_addr == 32'h0001_2340) && (fault_detail == 32'd0),
                    "ring KWS DMA tuple was not preserved");
    ring_result_ready = 1'b1;
    @(posedge clk);
    #1 ring_result_ready = 1'b0;

    expect_invalid_ring(3, 32'd31998);
    expect_invalid_ring(6, 32'h0104_3e80);
    expect_invalid_ring(9, 32'h0000_0080);
    expect_invalid_ring(24, 32'h0000_0001);

    make_kws_descriptor(direct_descriptor);
    check_condition(direct_allowed, "direct KWS start-boundary admission failed");
    direct_start = 1'b1;
    @(posedge clk);
    #1 direct_start = 1'b0;
    check_condition(kws_start, "direct KWS did not reach the start boundary");
    abort = 1'b1;
    @(posedge clk);
    #1 abort = 1'b0;
    check_condition(direct_done && idle, "abort at KWS start did not complete");
    check_condition(
        job_status[`APB4_APU__JOB_STATUS_ERROR] && job_status[`APB4_APU__JOB_STATUS_ABORTED],
        "abort at KWS start returned the wrong status");

    start_direct_kws();
    kws_input_used = 32'd126;
    abort          = 1'b1;
    @(posedge clk);
    #1 abort = 1'b0;
    check_condition(direct_done && idle, "KWS abort waited for codec transport");
    check_condition(job_status[`APB4_APU__JOB_STATUS_ERROR], "KWS abort did not report error");
    check_condition(job_status[`APB4_APU__JOB_STATUS_ABORTED], "KWS abort bit missing");
    check_condition((job_input_used == 32'd126) && (job_frames == 32'd63),
                    "KWS abort did not preserve consumed input progress");

    direct_descriptor             = '0;
    direct_descriptor[(0*32)+:32] = 32'd0;
    direct_descriptor[(2*32)+:32] = 32'h0000_1000;
    direct_descriptor[(3*32)+:32] = 32'd32000;
    direct_descriptor[(4*32)+:32] = 32'h0001_0000;
    direct_descriptor[(5*32)+:32] = 32'd1024;
    direct_descriptor[(6*32)+:32] = 32'h0102_3e80;
    #1;
    check_condition(!direct_allowed, "codec job bypassed microcode admission");
    scratch_bytes[0] = 17'd64;
    #1;
    check_condition(direct_allowed, "valid codec job was rejected");

    $display("PASS: APU P7 direct/ring KWS job lifecycle");
    $finish;
  end
endmodule
