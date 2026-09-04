// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_primitives_formal_design (
    // verilog_format: off -- preserve formal observation columns
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic [ 2:0] scenario_o,
    output logic [ 2:0] phase_o,
    output logic        request_valid_o,
    output logic        request_ready_o,
    output logic [ 3:0] request_class_o,
    output logic        request_accept_o,
    output logic        kernel_busy_o,
    output logic        kernel_outstanding_o,
    output logic [31:0] kernel_latency_o,
    output logic        result_valid_o,
    output logic        result_kernel_o,
    output logic        result_error_o,
    output logic [ 5:0] result_error_code_o,
    output logic [ 3:0] result_error_stage_o,
    output logic [ 7:0] result_error_reason_o,
    output logic [31:0] result_cycles_o,
    output logic        done_o,
    output logic        last_error_o,
    output logic [ 5:0] last_error_code_o,
    output logic [ 3:0] last_error_stage_o,
    output logic [ 7:0] last_error_reason_o,
    output logic [31:0] last_data_o,
    output logic [ 6:0] input_count_o,
    output logic [ 6:0] output_count_o,
    output logic        memory_request_o
    // verilog_format: on
);
`ifdef APU_PRIMITIVES_FORMAL_SCENARIO
  localparam logic [2:0] f_scenario = `APU_PRIMITIVES_FORMAL_SCENARIO;
`else
  (* anyconst *) logic [2:0] f_scenario;
`endif

  logic [ 7:0] s_cycle_q;
  logic [ 2:0] s_phase_q;
  logic [63:0] s_instruction;
  logic [31:0] s_source0, s_source1, s_destination;
  logic s_req_valid, s_req_ready;
  logic s_result_valid, s_result_kernel, s_result_error;
  logic [ 3:0]       s_result_dst;
  logic [ 3:0][31:0] s_result_data;
  logic [ 2:0]       s_result_words;
  logic [ 5:0]       s_result_error_code;
  logic [ 3:0]       s_result_error_stage;
  logic [ 7:0]       s_result_error_reason;
  logic [31:0]       s_result_cycles;
  logic s_kernel_done, s_dispatcher_busy;
  logic s_input_exhausted, s_input_ready, s_output_ready;
  logic s_memory_req, s_memory_write, s_memory_valid, s_memory_error;
  logic [16:0] s_memory_addr;
  logic [31:0] s_memory_write_data, s_memory_read_data;
  logic [3:0] s_memory_strb;
  logic s_input_valid, s_input_accept, s_output_valid;
  logic [40:0] s_input_data, s_output_data;
  logic s_inject, s_codec_req, s_codec_write;
  logic [16:0] s_codec_addr;
  logic [31:0] s_codec_data;
  logic [ 3:0] s_codec_strb;
  logic        s_kernel_outstanding_q;
  logic [31:0] s_kernel_latency_q;
  logic s_done_q, s_last_error_q;
  logic [ 5:0] s_last_error_code_q;
  logic [ 3:0] s_last_error_stage_q;
  logic [ 7:0] s_last_error_reason_q;
  logic [31:0] s_last_data_q;

  function automatic logic [63:0] encode_instruction(
      input logic [3:0] class_i, input logic [3:0] opcode_i, input logic [3:0] dst_i,
      input logic [3:0] src0_i, input logic [3:0] src1_i, input logic [7:0] aux_i,
      input logic [31:0] immediate_i);
    return {class_i, opcode_i, 4'd0, dst_i, src0_i, src1_i, aux_i, immediate_i};
  endfunction

  assign scenario_o            = f_scenario;
  assign phase_o               = s_phase_q;
  assign request_valid_o       = s_req_valid;
  assign request_ready_o       = s_req_ready;
  assign request_class_o       = s_instruction[63:60];
  assign request_accept_o      = s_req_valid && s_req_ready;
  assign kernel_outstanding_o  = s_kernel_outstanding_q;
  assign kernel_latency_o      = s_kernel_latency_q;
  assign result_valid_o        = s_result_valid;
  assign result_kernel_o       = s_result_kernel;
  assign result_error_o        = s_result_error;
  assign result_error_code_o   = s_result_error_code;
  assign result_error_stage_o  = s_result_error_stage;
  assign result_error_reason_o = s_result_error_reason;
  assign result_cycles_o       = s_result_cycles;
  assign done_o                = s_done_q;
  assign last_error_o          = s_last_error_q;
  assign last_error_code_o     = s_last_error_code_q;
  assign last_error_stage_o    = s_last_error_stage_q;
  assign last_error_reason_o   = s_last_error_reason_q;
  assign last_data_o           = s_last_data_q;
  assign memory_request_o      = s_memory_req;

  always_comb begin
    s_instruction = 64'd0;
    s_source0     = 32'd0;
    s_source1     = 32'd0;
    s_destination = 32'd0;
    s_req_valid   = 1'b0;
    if (rst_n_i) begin
      unique case (f_scenario)
        3'd0: begin
          s_instruction = encode_instruction(4'd4, 4'd0, 4'd0, 4'd0, 4'd0, 8'd0, 32'd0);
          s_req_valid   = s_phase_q == 3'd0;
        end
        3'd1: begin
          if (s_phase_q == 3'd0) begin
            s_instruction = encode_instruction(4'd4, 4'd1, 4'd0, 4'd0, 4'd1, 8'd0, 32'd0);
            s_source1     = 32'hdead_beef;
            s_req_valid   = 1'b1;
          end else if (s_phase_q == 3'd2) begin
            s_instruction = encode_instruction(4'd4, 4'd0, 4'd0, 4'd0, 4'd0, 8'd0, 32'd0);
            s_req_valid   = 1'b1;
          end
        end
        3'd2: begin
          if (s_phase_q == 3'd0) begin
            s_instruction = encode_instruction(4'd5, 4'd0, 4'd2, 4'd0, 4'd1, 8'h80, 32'd1);
            s_source0     = 32'h20;
            s_source1     = 32'h28;
            s_destination = 32'h2c;
            s_req_valid   = s_cycle_q >= 8'd4;
          end else if (s_phase_q == 3'd1) begin
            s_instruction = encode_instruction(4'd4, 4'd1, 4'd0, 4'd0, 4'd1, 8'd0, 32'd0);
            s_source0     = 32'h30;
            s_source1     = 32'h1357_9bdf;
            s_req_valid   = 1'b1;
          end else if (s_phase_q == 3'd3) begin
            s_instruction = encode_instruction(4'd4, 4'd0, 4'd0, 4'd0, 4'd0, 8'd0, 32'd0);
            s_source0     = 32'h30;
            s_req_valid   = 1'b1;
          end
        end
        3'd3: begin
          s_instruction = encode_instruction(4'd4, 4'd5, 4'd0, 4'd0, 4'd0, 8'd0, 32'd0);
          s_req_valid   = (s_phase_q == 3'd0) && (s_cycle_q >= 8'd2);
        end
        3'd4: begin
          s_instruction = encode_instruction(4'd5, 4'd0, 4'd2, 4'd0, 4'd1, 8'h80, 32'd1);
          s_source0     = 32'h21;
          s_source1     = 32'h28;
          s_destination = 32'h2c;
          s_req_valid   = (s_phase_q == 3'd0) && (s_cycle_q >= 8'd4);
        end
        3'd5: begin
          s_instruction = encode_instruction(4'd4, 4'd6, 4'd0, 4'd0, 4'd1, 8'd0, 32'd0);
          s_source0     = 32'hcafe_f00d;
          s_source1     = 32'h0000_0004;
          s_req_valid   = s_phase_q == 3'd0;
        end
        default: begin
          s_instruction = encode_instruction(4'd4, 4'd1, 4'd0, 4'd0, 4'd1, 8'd0, 32'd1);
          s_source0     = 32'hffff_ffff;
          s_source1     = 32'hdead_beef;
          s_req_valid   = s_phase_q == 3'd0;
        end
      endcase
    end
  end

  assign s_input_valid = (f_scenario == 3'd3) && (s_cycle_q == 8'd1);
  assign s_input_data = {1'b1, 5'd0, 3'd4, 32'h2468_ace0};
  assign s_inject = ((f_scenario == 3'd2) || (f_scenario == 3'd4)) &&
      (s_cycle_q inside {8'd1, 8'd2, 8'd3});
  assign s_codec_req = s_inject || s_memory_req;
  assign s_codec_write = s_inject || s_memory_write;
  assign s_codec_addr = s_inject ?
      ((s_cycle_q == 8'd1) ? 17'h20 : ((s_cycle_q == 8'd2) ? 17'h24 : 17'h28)) :
      s_memory_addr;
  assign s_codec_data = s_inject ?
      ((s_cycle_q == 8'd1) ? 32'd1000 :
       ((s_cycle_q == 8'd2) ? 32'h4000_0000 : 32'h0000_0024)) :
      s_memory_write_data;
  assign s_codec_strb = s_inject ? 4'hf : s_memory_strb;

  apu_local_sram #(
      .MemoryWordCount(64)
  ) u_local_sram (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .image_valid_i     (1'b1),
      .table_bytes_i     (16'd0),
      .epoch_clear_i     (1'b0),
      .loader_active_i   (1'b0),
      .loader_req_i      (1'b0),
      .loader_addr_i     (17'd0),
      .loader_data_i     (32'd0),
      .loader_strb_i     (4'd0),
      .loader_ready_o    (),
      .codec_req_i       (s_codec_req),
      .codec_write_i     (s_codec_write),
      .codec_addr_i      (s_codec_addr),
      .codec_data_i      (s_codec_data),
      .codec_strb_i      (s_codec_strb),
      .codec_ready_o     (),
      .codec_data_o      (s_memory_read_data),
      .codec_valid_o     (s_memory_valid),
      .codec_access_err_o(s_memory_error)
  );

  apu_primitive_dispatcher u_dispatcher (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .flush_i          (1'b0),
      .req_valid_i      (s_req_valid),
      .req_ready_o      (s_req_ready),
      .instruction_i    (s_instruction),
      .source0_i        (s_source0),
      .source1_i        (s_source1),
      .destination_i    (s_destination),
      .scratch_base_i   (17'd0),
      .scratch_bytes_i  (17'h100),
      .table_offset_i   (16'd0),
      .table_bytes_i    (16'd0),
      .result_valid_o   (s_result_valid),
      .result_dst_o     (s_result_dst),
      .result_data_o    (s_result_data),
      .result_words_o   (s_result_words),
      .result_kernel_o  (s_result_kernel),
      .error_o          (s_result_error),
      .error_code_o     (s_result_error_code),
      .error_stage_o    (s_result_error_stage),
      .error_reason_o   (s_result_error_reason),
      .cycles_o         (s_result_cycles),
      .kernel_done_o    (s_kernel_done),
      .busy_o           (s_dispatcher_busy),
      .input_exhausted_o(s_input_exhausted),
      .input_ready_o    (s_input_ready),
      .output_ready_o   (s_output_ready),
      .input_count_o    (input_count_o),
      .output_count_o   (output_count_o),
      .kernel_busy_o    (kernel_busy_o),
      .memory_req_o     (s_memory_req),
      .memory_write_o   (s_memory_write),
      .memory_addr_o    (s_memory_addr),
      .memory_data_o    (s_memory_write_data),
      .memory_strb_o    (s_memory_strb),
      .memory_valid_i   (s_memory_valid),
      .memory_data_i    (s_memory_read_data),
      .memory_error_i   (s_memory_error),
      .input_valid_i    (s_input_valid),
      .input_data_i     (s_input_data),
      .input_accept_o   (s_input_accept),
      .output_valid_o   (s_output_valid),
      .output_data_o    (s_output_data),
      .output_accept_i  (1'b0)
  );

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
    if (!rst_n_i) begin
      s_cycle_q              <= 8'd0;
      s_phase_q              <= 3'd0;
      s_kernel_outstanding_q <= 1'b0;
      s_kernel_latency_q     <= 32'd0;
      s_done_q               <= 1'b0;
      s_last_error_q         <= 1'b0;
      s_last_error_code_q    <= 6'd0;
      s_last_error_stage_q   <= 4'd0;
      s_last_error_reason_q  <= 8'd0;
      s_last_data_q          <= 32'd0;
    end else begin
      s_cycle_q <= s_cycle_q + 1'b1;
      if (s_kernel_outstanding_q) s_kernel_latency_q <= s_kernel_latency_q + 1'b1;
      if (request_accept_o && (request_class_o == `APB4_APU__MC_CLASS_KERNEL)) begin
        s_kernel_outstanding_q <= 1'b1;
        s_kernel_latency_q     <= 32'd1;
      end
      if (s_result_valid) begin
        s_last_error_q        <= s_result_error;
        s_last_error_code_q   <= s_result_error_code;
        s_last_error_stage_q  <= s_result_error_stage;
        s_last_error_reason_q <= s_result_error_reason;
        s_last_data_q         <= s_result_data[0];
        if (s_result_kernel) s_kernel_outstanding_q <= 1'b0;
      end

      unique case (f_scenario)
        3'd0, 3'd3, 3'd4, 3'd5, 3'd6: begin
          if (request_accept_o) s_phase_q <= 3'd1;
          if (s_result_valid) begin
            s_phase_q <= 3'd7;
            s_done_q  <= 1'b1;
          end
        end
        3'd1: begin
          if ((s_phase_q == 3'd0) && request_accept_o) s_phase_q <= 3'd1;
          if ((s_phase_q == 3'd1) && s_result_valid) s_phase_q <= 3'd2;
          if ((s_phase_q == 3'd2) && request_accept_o) s_phase_q <= 3'd3;
          if ((s_phase_q == 3'd3) && s_result_valid) begin
            s_phase_q <= 3'd7;
            s_done_q  <= 1'b1;
          end
        end
        default: begin
          if ((s_phase_q == 3'd0) && request_accept_o) s_phase_q <= 3'd1;
          if ((s_phase_q == 3'd1) && request_accept_o) s_phase_q <= 3'd2;
          if ((s_phase_q == 3'd2) && s_result_valid && !s_result_kernel) s_phase_q <= 3'd3;
          if ((s_phase_q == 3'd3) && request_accept_o) s_phase_q <= 3'd4;
          if ((s_phase_q == 3'd4) && s_result_valid) begin
            s_phase_q <= 3'd7;
            s_done_q  <= 1'b1;
          end
        end
      endcase
    end
  end

  logic s_unused;
  assign s_unused = s_result_dst[0] ^ s_result_words[0] ^ s_kernel_done ^ s_dispatcher_busy ^
      s_input_exhausted ^ s_input_ready ^ s_output_ready ^ s_input_accept ^ s_output_valid ^
      s_output_data[0];
endmodule
