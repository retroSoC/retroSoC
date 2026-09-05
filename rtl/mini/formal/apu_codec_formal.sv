// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_codec_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic [2:0]  scenario,
    output logic [ 5:0] cycle,
    output logic        block_new,
    output logic        context_ready,
    output logic        request_valid,
    output logic        request_ready,
    output logic        dma_request_valid,
    output logic        dma_request_ready,
    output logic [31:0] dma_request_addr,
    output logic [31:0] dma_request_bytes,
    output logic        memory_claim,
    output logic        memory_request,
    output logic        fault_valid,
    output logic [5:0]  fault_code,
    output logic [3:0]  fault_stage,
    output logic [31:0] fault_detail
);
  (* anyconst *)logic   [2:0]  f_scenario;
  logic [   5:0] s_cycle_q;
  logic [1023:0] s_descriptor;

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

  always_comb begin
    s_descriptor = '0;
    s_descriptor[(2*32)+:32] = 32'h1000_0000;
    s_descriptor[(3*32)+:32] = 32'd64;
    s_descriptor[(4*32)+:32] = 32'h2000_0000;
    s_descriptor[(5*32)+:32] = 32'd4;
    s_descriptor[(7*32)+:32] = 32'd48000 | (32'd2 << 17);
  end
  assign scenario              = f_scenario;
  assign block_new             = (f_scenario == 3'd3) && (s_cycle_q >= 6'd22);
  assign request_valid         = s_cycle_q >= 6'd22;
  assign dma_request_ready     = 1'b0;
  assign dma_read_axis.tdata   = 32'd0;
  assign dma_read_axis.tkeep   = 4'hf;
  assign dma_read_axis.tstrb   = 4'hf;
  assign dma_read_axis.tlast   = 1'b1;
  assign dma_read_axis.tid     = '0;
  assign dma_read_axis.tdest   = '0;
  assign dma_read_axis.tuser   = '0;
  assign dma_read_axis.tvalid  = 1'b0;
  assign dma_write_axis.tready = 1'b0;
  assign tx_axis.tready        = 1'b0;

  apu_codec_transport u_dut (
      .clk_i,
      .rst_n_i,
      .flush_i                 (1'b0),
      .abort_i                 (1'b0),
      .block_new_i             (block_new),
      .job_start_i             (s_cycle_q == 6'd1),
      .job_finish_i            (1'b0),
      .descriptor_i            (s_descriptor),
      .scratch_base_i          (17'd0),
      .scratch_bytes_i         (17'd256),
      .context_ready_o         (context_ready),
      .request_valid_i         (request_valid),
      .request_ready_o         (request_ready),
      .request_detail_aux_i    (5'd0),
      .request_pc_i            (11'd7),
      .request_opcode_i        ((f_scenario == 3'd2) ? 4'd1 : 4'd0),
      .request_dst_i           (4'd2),
      .request_aux_i           (4'd0),
      .request_event_i         (2'd0),
      .request_source0_i       ((f_scenario == 3'd1) ? 32'd2 : 32'd0),
      .request_source1_i       ((f_scenario == 3'd2) ? 32'd8 : 32'd4),
      .result_valid_o          (),
      .result_dst_o            (),
      .result_data_o           (),
      .dma_request_valid_o     (dma_request_valid),
      .dma_request_ready_i     (dma_request_ready),
      .dma_request_write_o     (),
      .dma_request_addr_o      (dma_request_addr),
      .dma_request_bytes_o     (dma_request_bytes),
      .dma_read_axis,
      .dma_write_axis,
      .memory_claim_o          (memory_claim),
      .memory_req_o            (memory_request),
      .memory_write_o          (),
      .memory_addr_o           (),
      .memory_data_o           (),
      .memory_strb_o           (),
      .memory_ready_i          (1'b1),
      .memory_valid_i          (1'b0),
      .memory_data_i           (32'd0),
      .memory_error_i          (1'b0),
      .input_fifo_valid_o      (),
      .input_fifo_data_o       (),
      .input_fifo_ready_i      (1'b1),
      .input_fifo_count_i      (7'd0),
      .output_fifo_valid_i     (1'b0),
      .output_fifo_data_i      (41'd0),
      .output_fifo_accept_o    (),
      .output_fifo_count_i     (7'd0),
      .output_fifo_push_valid_o(),
      .output_fifo_push_data_o (),
      .output_fifo_push_ready_i(1'b1),
      .tx_axis,
      .tx_empty_i              (1'b1),
      .dma_done_i              (1'b0),
      .dma_error_i             (1'b0),
      .dma_error_code_i        (6'd0),
      .dma_error_stage_i       (4'd0),
      .dma_error_resp_i        (2'd0),
      .dma_error_addr_i        (32'd0),
      .dma_write_burst_done_i  (1'b0),
      .dma_write_burst_bytes_i (32'd0),
      .fault_valid_o           (fault_valid),
      .fault_code_o            (fault_code),
      .fault_stage_o           (fault_stage),
      .fault_resp_o            (),
      .fault_addr_o            (),
      .fault_detail_o          (fault_detail),
      .input_used_o            (),
      .output_bytes_o          (),
      .frames_o                (),
      .source_info_o           (),
      .cycles_o                (),
      .detail_o                (),
      .diagnostic_offset_o     (),
      .result_code_o           (),
      .result_stage_o          (),
      .result_resp_o           (),
      .event_input_o           (),
      .event_output_o          (),
      .frame_commit_o          (),
      .tx_session_active_o     (),
      .input_pending_o         (),
      .output_pending_o        (),
      .job_done_o              (),
      .idle_o                  ()
  );

  assign cycle = s_cycle_q;

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
    if (!rst_n_i) s_cycle_q <= 6'd0;
    else if (s_cycle_q != 6'h3f) s_cycle_q <= s_cycle_q + 1'b1;
  end
endmodule
