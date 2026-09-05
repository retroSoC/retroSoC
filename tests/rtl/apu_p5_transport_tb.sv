// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_p5_transport_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  logic flush_i, abort_i, block_new_i, job_start_i, job_finish_i;
  logic [1023:0] descriptor_i;
  logic context_ready, request_valid, request_ready;
  logic [63:0] request_instruction;
  logic [31:0] request_source0, request_source1;
  logic        result_valid;
  logic [ 3:0] result_dst;
  logic [31:0] result_data;
  logic dma_request_valid, dma_request_ready, dma_request_write;
  logic [31:0] dma_request_addr, dma_request_bytes;
  logic memory_claim, memory_req, memory_write, memory_ready, memory_valid, memory_error;
  logic [16:0] memory_addr;
  logic [31:0] memory_write_data, memory_read_data;
  logic [3:0] memory_strb;
  logic input_valid, input_ready, output_valid, output_accept, output_push_valid, output_push_ready;
  logic [40:0] input_data, output_data, output_push_data;
  logic [6:0] input_count, output_count;
  logic dma_done, dma_error;
  logic dma_error_q, dma_write_burst_done_q, dma_write_active_q, dma_fault_after_prefix_q;
  logic [31:0] dma_write_burst_bytes_q;
  logic [6:0] dma_write_beat_q;
  logic tx_ready_q;
  logic fault_valid, event_input, event_output, tx_active, input_pending, output_pending;
  logic [5:0] fault_code;
  logic [3:0] fault_stage;
  logic [31:0] fault_addr, fault_detail;
  logic job_done, idle;
  logic [31:0] transport_output_bytes;
  logic [31:0] local_memory           [0:255];
  logic        memory_read_pending_q;
  logic [ 7:0] memory_read_addr_q;
  logic [ 1:0] dma_read_word_q;
  logic dma_read_active_q, dma_done_pending_q;
  logic [ 1:0] tx_words_q;
  logic        tx_last_seen_q;
  logic [ 2:0] tx_last_count_q;
  logic [31:0] held_tx_data_q;
  logic        held_tx_last_q;
  logic [ 1:0] tx_words_before_q;
  logic [ 2:0] tx_last_before_q;

  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) dma_read_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) dma_write_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) tx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  assign dma_request_ready     = 1'b1;
  assign dma_write_axis.tready = 1'b1;
  assign tx_axis.tready        = tx_ready_q;
  assign memory_ready          = 1'b1;
  assign memory_error          = 1'b0;
  assign dma_error             = dma_error_q;

  assign dma_read_axis.tdata   = dma_read_word_q == 2'd0 ? 32'h4443_4241 : 32'h4847_4645;
  assign dma_read_axis.tkeep   = 4'hf;
  assign dma_read_axis.tstrb   = 4'hf;
  assign dma_read_axis.tlast   = dma_read_word_q == 2'd1;
  assign dma_read_axis.tid     = '0;
  assign dma_read_axis.tdest   = '0;
  assign dma_read_axis.tuser   = '0;
  assign dma_read_axis.tvalid  = dma_read_active_q;
  assign dma_done              = dma_done_pending_q;

  stream_fifo #(
      .DATA_WIDTH      (41),
      .BUFFER_DEPTH    (64),
      .LOG_BUFFER_DEPTH(6)
  ) u_input_fifo (
      .clk_i,
      .rst_n_i,
      .flush_i,
      .full_o (),
      .empty_o(),
      .cnt_o  (input_count),
      .dat_i  (input_data),
      .push_i (input_valid && input_ready),
      .dat_o  (),
      .pop_i  (1'b0)
  );
  assign input_ready = input_valid && (input_count != 7'd64);

  stream_fifo #(
      .DATA_WIDTH      (41),
      .BUFFER_DEPTH    (64),
      .LOG_BUFFER_DEPTH(6)
  ) u_output_fifo (
      .clk_i,
      .rst_n_i,
      .flush_i,
      .full_o (),
      .empty_o(),
      .cnt_o  (output_count),
      .dat_i  (output_push_data),
      .push_i (output_push_valid && output_push_ready),
      .dat_o  (output_data),
      .pop_i  (output_accept && output_valid)
  );
  assign output_push_ready = output_push_valid && (output_count != 7'd64);
  assign output_valid      = output_count != 7'd0;

  apu_codec_transport u_dut (
      .clk_i,
      .rst_n_i,
      .flush_i,
      .abort_i,
      .block_new_i,
      .job_start_i,
      .job_finish_i,
      .descriptor_i,
      .scratch_base_i          (17'd0),
      .scratch_bytes_i         (17'd256),
      .context_ready_o         (context_ready),
      .request_valid_i         (request_valid),
      .request_ready_o         (request_ready),
      .request_detail_aux_i    (request_instruction[36:32]),
      .request_pc_i            (11'd0),
      .request_opcode_i        (request_instruction[59:56]),
      .request_dst_i           (request_instruction[51:48]),
      .request_aux_i           (request_instruction[35:32]),
      .request_event_i         (request_instruction[7:6]),
      .request_source0_i       (request_source0),
      .request_source1_i       (request_source1),
      .result_valid_o          (result_valid),
      .result_dst_o            (result_dst),
      .result_data_o           (result_data),
      .dma_request_valid_o     (dma_request_valid),
      .dma_request_ready_i     (dma_request_ready),
      .dma_request_write_o     (dma_request_write),
      .dma_request_addr_o      (dma_request_addr),
      .dma_request_bytes_o     (dma_request_bytes),
      .dma_read_axis,
      .dma_write_axis,
      .memory_claim_o          (memory_claim),
      .memory_req_o            (memory_req),
      .memory_write_o          (memory_write),
      .memory_addr_o           (memory_addr),
      .memory_data_o           (memory_write_data),
      .memory_strb_o           (memory_strb),
      .memory_ready_i          (memory_ready),
      .memory_valid_i          (memory_valid),
      .memory_data_i           (memory_read_data),
      .memory_error_i          (memory_error),
      .input_fifo_valid_o      (input_valid),
      .input_fifo_data_o       (input_data),
      .input_fifo_ready_i      (input_ready),
      .input_fifo_count_i      (input_count),
      .output_fifo_valid_i     (output_valid),
      .output_fifo_data_i      (output_data),
      .output_fifo_accept_o    (output_accept),
      .output_fifo_count_i     (output_count),
      .output_fifo_push_valid_o(output_push_valid),
      .output_fifo_push_data_o (output_push_data),
      .output_fifo_push_ready_i(output_push_ready),
      .tx_axis,
      .tx_empty_i              (1'b1),
      .dma_done_i              (dma_done),
      .dma_error_i             (dma_error),
      .dma_error_code_i        (`APB4_APU__ERROR_CODE_AXI_WRITE),
      .dma_error_stage_i       (`APB4_APU__ERROR_STAGE_DMA_WRITE),
      .dma_error_resp_i        (2'd2),
      .dma_error_addr_i        (32'h2000_0040),
      .dma_write_burst_done_i  (dma_write_burst_done_q),
      .dma_write_burst_bytes_i (dma_write_burst_bytes_q),
      .fault_valid_o           (fault_valid),
      .fault_code_o            (fault_code),
      .fault_stage_o           (fault_stage),
      .fault_resp_o            (),
      .fault_addr_o            (fault_addr),
      .fault_detail_o          (fault_detail),
      .input_used_o            (),
      .output_bytes_o          (transport_output_bytes),
      .frames_o                (),
      .source_info_o           (),
      .cycles_o                (),
      .detail_o                (),
      .diagnostic_offset_o     (),
      .result_code_o           (),
      .result_stage_o          (),
      .result_resp_o           (),
      .event_input_o           (event_input),
      .event_output_o          (event_output),
      .frame_commit_o          (),
      .tx_session_active_o     (tx_active),
      .input_pending_o         (input_pending),
      .output_pending_o        (output_pending),
      .job_done_o              (job_done),
      .idle_o                  (idle)
  );

  always_ff @(posedge clk_i) begin
    memory_valid <= memory_read_pending_q;
    if (memory_read_pending_q) memory_read_data <= local_memory[memory_read_addr_q];
    memory_read_pending_q <= memory_req && memory_ready && !memory_write;
    if (memory_req && memory_ready && !memory_write) memory_read_addr_q <= memory_addr[9:2];
    if (memory_req && memory_ready && memory_write) begin
      for (int lane = 0; lane < 4; lane++) begin
        if (memory_strb[lane])
          local_memory[memory_addr[9:2]][lane*8+:8] <= memory_write_data[lane*8+:8];
      end
    end

    dma_done_pending_q      <= 1'b0;
    dma_error_q             <= 1'b0;
    dma_write_burst_done_q  <= 1'b0;
    dma_write_burst_bytes_q <= 32'd0;
    if (dma_request_valid && dma_request_ready && !dma_request_write) begin
      dma_read_active_q <= 1'b1;
      dma_read_word_q   <= 2'd0;
      if (dma_request_addr != 32'h1000_0000 || dma_request_bytes != 32'd8)
        $fatal(1, "P5 refill DMA command mismatch");
    end else if (dma_read_active_q && dma_read_axis.tready) begin
      if (dma_read_word_q == 2'd1) begin
        dma_read_active_q  <= 1'b0;
        dma_done_pending_q <= 1'b1;
      end else begin
        dma_read_word_q <= dma_read_word_q + 1'b1;
      end
    end
    if (dma_request_valid && dma_request_ready && dma_request_write) begin
      dma_write_active_q <= 1'b1;
      dma_write_beat_q   <= 7'd0;
    end else if (dma_write_active_q && dma_write_axis.tvalid && dma_write_axis.tready) begin
      if (dma_write_beat_q == 7'd15) begin
        dma_write_burst_done_q  <= 1'b1;
        dma_write_burst_bytes_q <= 32'd64;
      end
      if (dma_write_axis.tlast) begin
        dma_write_active_q <= 1'b0;
        dma_done_pending_q <= 1'b1;
        dma_error_q        <= dma_fault_after_prefix_q;
        if (!dma_fault_after_prefix_q && (dma_write_beat_q != 7'd15)) begin
          dma_write_burst_done_q  <= 1'b1;
          dma_write_burst_bytes_q <= {25'd0, dma_write_beat_q + 1'b1} << 2;
        end
      end else begin
        dma_write_beat_q <= dma_write_beat_q + 1'b1;
      end
    end
    if (tx_axis.tvalid && tx_axis.tready) begin
      tx_words_q <= tx_words_q + 1'b1;
      if (tx_axis.tlast) begin
        tx_last_seen_q  <= 1'b1;
        tx_last_count_q <= tx_last_count_q + 1'b1;
      end
    end
  end

  function automatic logic [63:0] transport_instruction(input logic [3:0] opcode_i,
                                                        input logic [3:0] dst_i);
    return {4'd6, opcode_i, 4'd0, dst_i, 4'd0, 4'd1, 8'd0, 32'd0};
  endfunction

  task automatic issue(input logic [3:0] opcode_i, input logic [3:0] dst_i,
                       input logic [31:0] source0_i, input logic [31:0] source1_i);
    begin
      @(negedge clk_i);
      request_instruction = transport_instruction(opcode_i, dst_i);
      request_source0     = source0_i;
      request_source1     = source1_i;
      request_valid       = 1'b1;
      do @(posedge clk_i); while (!request_ready);
      @(negedge clk_i);
      request_valid = 1'b0;
    end
  endtask

  task automatic wait_result(input logic [3:0] expected_dst_i, input logic [31:0] expected_data_i);
    begin
      for (int cycle = 0; cycle < 500; cycle++) begin
        @(posedge clk_i);
        if (result_valid) begin
          if (result_dst != expected_dst_i || result_data != expected_data_i)
            $fatal(
                1,
                "P5 transport result mismatch got dst=%0d data=%0d expected=%0d/%0d state=%0d actual=%0d",
                result_dst,
                result_data,
                expected_dst_i,
                expected_data_i,
                u_dut.s_state_q,
                u_dut.s_actual_q
            );
          return;
        end
      end
      $fatal(1, "P5 transport result timeout");
    end
  endtask

  task automatic begin_job(input logic [31:0] control_i, input logic [31:0] output_addr_i,
                           input logic [31:0] output_capacity_i);
    begin
      @(negedge clk_i);
      descriptor_i             = '0;
      descriptor_i[(0*32)+:32] = control_i;
      descriptor_i[(2*32)+:32] = 32'h1000_0000;
      descriptor_i[(3*32)+:32] = 32'd8;
      descriptor_i[(4*32)+:32] = output_addr_i;
      descriptor_i[(5*32)+:32] = output_capacity_i;
      descriptor_i[(7*32)+:32] = 32'd48000 | (32'd2 << 17);
      job_start_i              = 1'b1;
      @(negedge clk_i);
      job_start_i = 1'b0;
      wait (context_ready);
    end
  endtask

  task automatic expect_fault(input logic [5:0] code_i, input logic [3:0] stage_i,
                              input logic [7:0] reason_i);
    begin
      for (int cycle = 0; cycle < 500 && !fault_valid; cycle++) @(posedge clk_i);
      if (!fault_valid || fault_code != code_i || fault_stage != stage_i ||
          fault_detail[7:0] != reason_i)
        $fatal(
            1,
            "P5 fault mismatch valid=%0d code=%0d stage=%0d detail=%h expected=%0d/%0d/%0d",
            fault_valid,
            fault_code,
            fault_stage,
            fault_detail,
            code_i,
            stage_i,
            reason_i
        );
      wait (job_done);
    end
  endtask

  initial begin
    flush_i                  = 1'b0;
    abort_i                  = 1'b0;
    block_new_i              = 1'b0;
    job_start_i              = 1'b0;
    job_finish_i             = 1'b0;
    descriptor_i             = '0;
    descriptor_i[8]          = 1'b1;
    descriptor_i[(2*32)+:32] = 32'h1000_0000;
    descriptor_i[(3*32)+:32] = 32'd8;
    descriptor_i[(7*32)+:32] = 32'd48000 | (32'd2 << 17);
    request_valid            = 1'b0;
    request_instruction      = 64'd0;
    request_source0          = 32'd0;
    request_source1          = 32'd0;
    memory_valid             = 1'b0;
    memory_read_pending_q    = 1'b0;
    dma_read_active_q        = 1'b0;
    dma_done_pending_q       = 1'b0;
    dma_error_q              = 1'b0;
    dma_write_burst_done_q   = 1'b0;
    dma_write_burst_bytes_q  = 32'd0;
    dma_write_active_q       = 1'b0;
    dma_fault_after_prefix_q = 1'b0;
    dma_write_beat_q         = 7'd0;
    tx_ready_q               = 1'b1;
    tx_words_q               = 2'd0;
    tx_last_seen_q           = 1'b0;
    tx_last_count_q          = 3'd0;
    held_tx_data_q           = 32'd0;
    held_tx_last_q           = 1'b0;
    tx_words_before_q        = 2'd0;
    tx_last_before_q         = 3'd0;
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    job_start_i = 1'b1;
    @(negedge clk_i);
    job_start_i = 1'b0;
    wait (context_ready);
    if (local_memory[(192+32)/4] != 32'd8)
      $fatal(1, "P5 context input length mismatch: %0d", local_memory[(192+32)/4]);

    local_memory[4]          = 32'h0403_0201;
    local_memory[5]          = 32'h0807_0605;
    local_memory[(192+24)/4] = 32'h0084_bb80;
    local_memory[(192+28)/4] = 32'd1;
    issue(`APB4_APU__MC_TRANSPORT_INPUT_REFILL, 4'd2, 32'd0, 32'd8);
    issue(`APB4_APU__MC_TRANSPORT_OUTPUT_STREAM, 4'd3, 32'd16, 32'd8);
    if (!input_pending || !output_pending) $fatal(1, "P5 independent pending commands missing");
    wait_result(4'd2, 32'd8);
    if (input_count != 7'd2 || local_memory[0] != 32'h4443_4241 || local_memory[1] != 32'h4847_4645)
      $fatal(1, "P5 refill publication mismatch");
    wait_result(4'd3, 32'd8);
    if (tx_words_q != 2'd2 || !tx_last_seen_q || output_count != 7'd0)
      $fatal(1, "P5 TX/TLAST drain mismatch");

    issue(`APB4_APU__MC_TRANSPORT_FRAME_COMMIT, 4'd0, 32'd4, 32'd4);
    wait_result(4'd0, 32'd0);
    issue(`APB4_APU__MC_TRANSPORT_FRAME_COMMIT, 4'd0, 32'd4, 32'd4);
    wait_result(4'd0, 32'd0);
    local_memory[(192+16)/4] = 32'd8;
    local_memory[(192+20)/4] = 32'd8;

    @(negedge clk_i);
    job_finish_i = 1'b1;
    @(negedge clk_i);
    job_finish_i = 1'b0;
    wait (job_done);
    if (fault_valid || input_pending || output_pending || tx_active)
      $fatal(1, "P5 terminal state mismatch");

    begin_job(32'd0, 32'h2000_0000, 32'd256);
    local_memory[(192+24)/4] = 32'h0084_bb80;
    local_memory[(192+28)/4] = 32'd0;
    for (int word = 0; word < 32; word++) local_memory[4+word] = 32'(word);
    dma_fault_after_prefix_q = 1'b1;
    issue(`APB4_APU__MC_TRANSPORT_OUTPUT_COMMIT, 4'd3, 32'd16, 32'd128);
    expect_fault(`APB4_APU__ERROR_CODE_AXI_WRITE, `APB4_APU__ERROR_STAGE_DMA_WRITE, 8'd0);
    if (transport_output_bytes != 32'd64)
      $fatal(1, "P5 successful-B prefix mismatch %0d", transport_output_bytes);
    dma_fault_after_prefix_q = 1'b0;

    begin_job(32'd1 << 8, 32'd0, 32'd0);
    local_memory[4]          = 32'h0403_0201;
    local_memory[5]          = 32'h0807_0605;
    local_memory[(192+24)/4] = 32'h0084_bb80;
    local_memory[(192+28)/4] = 32'd1;
    tx_ready_q               = 1'b0;
    issue(`APB4_APU__MC_TRANSPORT_OUTPUT_STREAM, 4'd3, 32'd16, 32'd8);
    wait (tx_axis.tvalid);
    held_tx_data_q    = tx_axis.tdata;
    held_tx_last_q    = tx_axis.tlast;
    tx_words_before_q = tx_words_q;
    tx_last_before_q  = tx_last_count_q;
    abort_i           = 1'b1;
    repeat (3) begin
      @(posedge clk_i);
      if (!tx_axis.tvalid || tx_axis.tdata != held_tx_data_q || tx_axis.tlast != held_tx_last_q)
        $fatal(1, "P5 stalled stream payload changed during abort");
    end
    @(negedge clk_i);
    tx_ready_q = 1'b1;
    @(posedge clk_i);
    while (!(tx_axis.tvalid && tx_axis.tready)) @(posedge clk_i);
    @(negedge clk_i);
    abort_i = 1'b0;
    wait (job_done);
    if ((transport_output_bytes != 32'd4) ||
        (tx_words_q != (tx_words_before_q + 1'b1)) ||
        (tx_last_count_q != tx_last_before_q))
      $fatal(1, "P5 abort stream accounting/TLAST mismatch");

    begin_job(32'd0, 32'h2000_0000, 32'd4);
    local_memory[(192+24)/4] = 32'h0084_bb80;
    issue(`APB4_APU__MC_TRANSPORT_OUTPUT_COMMIT, 4'd3, 32'd16, 32'd8);
    expect_fault(`APB4_APU__ERROR_CODE_RECONSTRUCTION, `APB4_APU__ERROR_STAGE_DMA_WRITE, 8'h51);
    if (dma_request_valid || memory_write) $fatal(1, "capacity rejection mutated transport state");

    begin_job(32'd1 << 8, 32'd0, 32'd0);
    issue(`APB4_APU__MC_TRANSPORT_INPUT_REFILL, 4'd2, 32'd2, 32'd8);
    expect_fault(`APB4_APU__ERROR_CODE_SEQUENCER, `APB4_APU__ERROR_STAGE_LIFECYCLE, 8'd5);
    if (dma_request_valid || memory_write) $fatal(1, "alignment rejection mutated transport state");

    begin_job(32'd1 << 8, 32'd0, 32'd0);
    issue(`APB4_APU__MC_TRANSPORT_JOB_RESULT, 4'd0, 32'd23, 32'd0);
    expect_fault(`APB4_APU__ERROR_CODE_SEQUENCER, `APB4_APU__ERROR_STAGE_LIFECYCLE, 8'd1);

    begin_job(32'd1 << 8, 32'd0, 32'd0);
    issue(`APB4_APU__MC_TRANSPORT_FRAME_COMMIT, 4'd0, 32'd0, 32'd4);
    expect_fault(`APB4_APU__ERROR_CODE_SEQUENCER, `APB4_APU__ERROR_STAGE_LIFECYCLE, 8'd9);
    $display("APU-P5 production transport passed");
    $finish;
  end

  initial begin
    repeat (3000) @(posedge clk_i);
    $fatal(1, "APU-P5 transport timeout");
  end

  logic s_unused;
  assign s_unused = memory_claim ^ idle ^ event_input ^ event_output ^ dma_write_axis.tvalid;
endmodule
