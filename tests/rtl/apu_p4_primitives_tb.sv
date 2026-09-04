// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_p4_primitives_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  logic flush_i, epoch_clear_i, image_valid_i;
  logic req_valid, req_ready;
  logic [63:0] instruction;
  logic [31:0] source0, source1, destination;
  logic result_valid, result_kernel, result_error, kernel_done, dispatcher_busy;
  logic [ 3:0]       result_dst;
  logic [ 3:0][31:0] result_data;
  logic [ 2:0]       result_words;
  logic [ 5:0]       error_code;
  logic [ 3:0]       error_stage;
  logic [ 7:0]       error_reason;
  logic [31:0]       result_cycles;
  logic input_exhausted, input_ready, output_ready;
  logic [6:0] input_count, output_count;
  logic input_valid, input_accept, output_valid, output_accept;
  logic [40:0] input_data, output_data;
  logic dispatcher_memory_req, dispatcher_memory_write;
  logic [16:0] dispatcher_memory_addr;
  logic [31:0] dispatcher_memory_data;
  logic [ 3:0] dispatcher_memory_strb;
  logic memory_valid, memory_error, memory_ready;
  logic [31:0] memory_read_data;
  logic loader_active, loader_req;
  logic [16:0] loader_addr;
  logic [31:0] loader_data;
  logic [ 3:0] loader_strb;
  logic inject_active, inject_req, inject_write;
  logic [16:0] inject_addr;
  logic [31:0] inject_data;
  logic [ 3:0] inject_strb;
  logic codec_req, codec_write;
  logic   [16:0] codec_addr;
  logic   [31:0] codec_data;
  logic   [ 3:0] codec_strb;
  logic          s_latency_active_q;
  logic   [31:0] s_latency_cycles_q;
  logic   [31:0] s_dispatcher_request_count_q;
  logic   [31:0] s_dispatcher_write_count_q;
  logic   [31:0] requant_vectors              [0:255];
  integer        requant_vector_count;
  string         requant_vector_path;

  always #5 clk_i = ~clk_i;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_latency_active_q <= 1'b0;
      s_latency_cycles_q <= 32'd0;
    end else if (flush_i) begin
      s_latency_active_q <= 1'b0;
      s_latency_cycles_q <= 32'd0;
    end else if (result_valid) begin
      if (s_latency_active_q && (s_latency_cycles_q > result_cycles)) begin
        $fatal(1, "APU-P4 request latency exceeded bound actual=%0d bound=%0d instruction=%016x",
               s_latency_cycles_q, result_cycles, instruction);
      end
      s_latency_active_q <= 1'b0;
      s_latency_cycles_q <= 32'd0;
    end else if (req_valid && req_ready) begin
      s_latency_active_q <= 1'b1;
      s_latency_cycles_q <= 32'd0;
    end else if (s_latency_active_q) begin
      s_latency_cycles_q <= s_latency_cycles_q + 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_dispatcher_request_count_q <= 32'd0;
      s_dispatcher_write_count_q   <= 32'd0;
    end else begin
      if (dispatcher_memory_req && memory_ready) begin
        s_dispatcher_request_count_q <= s_dispatcher_request_count_q + 1'b1;
      end
      if (dispatcher_memory_req && dispatcher_memory_write && memory_ready) begin
        s_dispatcher_write_count_q <= s_dispatcher_write_count_q + 1'b1;
      end
    end
  end

  assign codec_req   = inject_active ? inject_req : dispatcher_memory_req;
  assign codec_write = inject_active ? inject_write : dispatcher_memory_write;
  assign codec_addr  = inject_active ? inject_addr : dispatcher_memory_addr;
  assign codec_data  = inject_active ? inject_data : dispatcher_memory_data;
  assign codec_strb  = inject_active ? inject_strb : dispatcher_memory_strb;

  apu_local_sram u_local_sram (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .image_valid_i     (image_valid_i),
      .table_bytes_i     (16'h1800),
      .epoch_clear_i     (epoch_clear_i),
      .loader_active_i   (loader_active),
      .loader_req_i      (loader_req),
      .loader_addr_i     (loader_addr),
      .loader_data_i     (loader_data),
      .loader_strb_i     (loader_strb),
      .loader_ready_o    (),
      .codec_req_i       (codec_req),
      .codec_write_i     (codec_write),
      .codec_addr_i      (codec_addr),
      .codec_data_i      (codec_data),
      .codec_strb_i      (codec_strb),
      .codec_ready_o     (memory_ready),
      .codec_data_o      (memory_read_data),
      .codec_valid_o     (memory_valid),
      .codec_access_err_o(memory_error)
  );

  apu_primitive_dispatcher u_dut (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .flush_i          (flush_i),
      .req_valid_i      (req_valid),
      .req_ready_o      (req_ready),
      .instruction_i    (instruction),
      .source0_i        (source0),
      .source1_i        (source1),
      .destination_i    (destination),
      .scratch_base_i   (17'h02000),
      .scratch_bytes_i  (17'h04000),
      .table_offset_i   (16'h0000),
      .table_bytes_i    (16'h1800),
      .result_valid_o   (result_valid),
      .result_dst_o     (result_dst),
      .result_data_o    (result_data),
      .result_words_o   (result_words),
      .result_kernel_o  (result_kernel),
      .error_o          (result_error),
      .error_code_o     (error_code),
      .error_stage_o    (error_stage),
      .error_reason_o   (error_reason),
      .cycles_o         (result_cycles),
      .kernel_done_o    (kernel_done),
      .busy_o           (dispatcher_busy),
      .input_exhausted_o(input_exhausted),
      .input_ready_o    (input_ready),
      .output_ready_o   (output_ready),
      .input_count_o    (input_count),
      .output_count_o   (output_count),
      .kernel_busy_o    (),
      .memory_req_o     (dispatcher_memory_req),
      .memory_write_o   (dispatcher_memory_write),
      .memory_addr_o    (dispatcher_memory_addr),
      .memory_data_o    (dispatcher_memory_data),
      .memory_strb_o    (dispatcher_memory_strb),
      .memory_valid_i   (memory_valid),
      .memory_data_i    (memory_read_data),
      .memory_error_i   (memory_error),
      .input_valid_i    (input_valid),
      .input_data_i     (input_data),
      .input_accept_o   (input_accept),
      .output_valid_o   (output_valid),
      .output_data_o    (output_data),
      .output_accept_i  (output_accept)
  );

  function automatic logic [63:0] encode_instruction(
      input logic [3:0] instruction_class_i, input logic [3:0] opcode_i, input logic [3:0] dst_i,
      input logic [3:0] src0_i, input logic [3:0] src1_i, input logic [7:0] aux_i,
      input logic [31:0] immediate_i);
    return {instruction_class_i, opcode_i, 4'd0, dst_i, src0_i, src1_i, aux_i, immediate_i};
  endfunction

  function automatic logic [15:0] expected_resample_frames(input logic [3:0] profile_i);
    begin
      unique case (profile_i)
        4'd0, 4'd1, 4'd2: expected_resample_frames = 16'd1;
        4'd3:             expected_resample_frames = 16'd2;
        4'd4:             expected_resample_frames = 16'd2;
        4'd5:             expected_resample_frames = 16'd2;
        4'd6:             expected_resample_frames = 16'd3;
        4'd7:             expected_resample_frames = 16'd4;
        4'd8:             expected_resample_frames = 16'd6;
        4'd9:             expected_resample_frames = 16'd8;
        4'd10:            expected_resample_frames = 16'd12;
        4'd11:            expected_resample_frames = 16'd3;
        4'd12:            expected_resample_frames = 16'd5;
        4'd13:            expected_resample_frames = 16'd9;
        4'd14:            expected_resample_frames = 16'd1;
        default:          expected_resample_frames = 16'd2;
      endcase
    end
  endfunction

  task automatic hard_reset;
    begin
      rst_n_i = 1'b0;
      repeat (3) @(posedge clk_i);
      rst_n_i = 1'b1;
      repeat (2) @(posedge clk_i);
    end
  endtask

  task automatic publish_table_word(input logic [16:0] address_i, input logic [31:0] data_i);
    begin
      @(negedge clk_i);
      loader_active = 1'b1;
      loader_req    = 1'b1;
      loader_addr   = address_i;
      loader_data   = data_i;
      loader_strb   = 4'hf;
      @(negedge clk_i);
      loader_active = 1'b0;
      loader_req    = 1'b0;
    end
  endtask

  task automatic inject_word(input logic [16:0] address_i, input logic [31:0] data_i);
    begin
      @(negedge clk_i);
      inject_active = 1'b1;
      inject_req    = 1'b1;
      inject_write  = 1'b1;
      inject_addr   = address_i;
      inject_data   = data_i;
      inject_strb   = 4'hf;
      @(negedge clk_i);
      inject_active = 1'b0;
      inject_req    = 1'b0;
      inject_write  = 1'b0;
    end
  endtask

  task automatic read_word(input logic [16:0] address_i, output logic [31:0] data_o);
    begin
      @(negedge clk_i);
      inject_active = 1'b1;
      inject_req    = 1'b1;
      inject_write  = 1'b0;
      inject_addr   = address_i;
      @(negedge clk_i);
      inject_req = 1'b0;
      for (int cycle = 0; cycle < 4; cycle++) begin
        @(posedge clk_i);
        if (memory_valid) begin
          data_o        = memory_read_data;
          inject_active = 1'b0;
          return;
        end
      end
      $fatal(1, "APU-P4 injected read timed out");
    end
  endtask

  task automatic push_input(input logic [40:0] data_i);
    begin
      @(negedge clk_i);
      input_data  = data_i;
      input_valid = 1'b1;
      do @(posedge clk_i); while (!input_accept);
      @(negedge clk_i);
      input_valid = 1'b0;
    end
  endtask

  task automatic issue(input logic [63:0] instruction_i, input logic [31:0] source0_i,
                       input logic [31:0] source1_i, input logic [31:0] destination_i,
                       output logic [31:0] result0_o, output logic [31:0] cycles_o);
    begin
      int wall_cycles;
      wall_cycles = 0;
      @(negedge clk_i);
      instruction = instruction_i;
      source0     = source0_i;
      source1     = source1_i;
      destination = destination_i;
      req_valid   = 1'b1;
      for (int cycle = 0; cycle < 10000; cycle++) begin
        @(posedge clk_i);
        if (req_ready) begin
          wall_cycles = 1;
          @(negedge clk_i);
          req_valid = 1'b0;
          break;
        end
      end
      for (int cycle = 0; cycle < 20000; cycle++) begin
        @(posedge clk_i);
        wall_cycles++;
        if (result_valid) begin
          if (result_error) begin
            $fatal(1, "APU-P4 operation failed code=%0d stage=%0d reason=%0d", error_code,
                   error_stage, error_reason);
          end
          result0_o = result_data[0];
          cycles_o  = result_cycles;
          if (result_kernel && (u_dut.u_kernel_engine.s_cycles_q > result_cycles)) begin
            $fatal(1, "APU-P4 wall latency exceeded bound actual=%0d bound=%0d opcode=%0d",
                   u_dut.u_kernel_engine.s_cycles_q, result_cycles, instruction_i[59:56]);
          end
          if (result_kernel && (wall_cycles > result_cycles)) begin
            $fatal(1, "APU-P4 external latency exceeded bound actual=%0d bound=%0d opcode=%0d",
                   wall_cycles, result_cycles, instruction_i[59:56]);
          end
          return;
        end
      end
      $fatal(1, "APU-P4 operation timed out");
    end
  endtask

  task automatic issue_expect_error(
      input logic [63:0] instruction_i, input logic [31:0] source0_i, input logic [31:0] source1_i,
      input logic [31:0] destination_i, input logic [5:0] expected_code_i,
      input logic [3:0] expected_stage_i, input logic [7:0] expected_reason_i);
    begin
      logic [31:0] s_write_count_before;
      s_write_count_before = s_dispatcher_write_count_q;
      @(negedge clk_i);
      instruction = instruction_i;
      source0     = source0_i;
      source1     = source1_i;
      destination = destination_i;
      req_valid   = 1'b1;
      for (int cycle = 0; cycle < 1000; cycle++) begin
        @(posedge clk_i);
        if (result_valid) begin
          if (!result_error || (error_code != expected_code_i) ||
              (error_stage != expected_stage_i) || (error_reason != expected_reason_i)) begin
            $fatal(1, "APU-P4 error tuple mismatch got=%0d/%0d/%0d expected=%0d/%0d/%0d",
                   error_code, error_stage, error_reason, expected_code_i, expected_stage_i,
                   expected_reason_i);
          end
          @(negedge clk_i);
          req_valid = 1'b0;
          if ((result_words != 3'd0) || (result_data != '0)) begin
            $fatal(1, "APU-P4 error exposed destination data words=%0d data=%h", result_words,
                   result_data);
          end
          if (s_dispatcher_write_count_q != s_write_count_before) begin
            $fatal(
                1,
                "APU-P4 rejected operation wrote local SRAM before=%0d after=%0d instruction=%016x",
                s_write_count_before, s_dispatcher_write_count_q, instruction_i);
          end
          return;
        end
        if (req_ready) begin
          @(negedge clk_i);
          req_valid = 1'b0;
        end
      end
      $fatal(1, "APU-P4 expected error timed out");
    end
  endtask

  task automatic issue_expect_corpus_error(
      input logic [63:0] instruction_i, input logic [31:0] source0_i, input logic [31:0] source1_i,
      input logic [31:0] destination_i, input logic [5:0] expected_code_i,
      input logic [3:0] expected_stage_i, input logic [7:0] expected_reason_i,
      input logic check_latency_i, input logic [31:0] maximum_cycles_i,
      input logic check_no_memory_request_i);
    begin
      logic [31:0] s_request_count_before;
      s_request_count_before = s_dispatcher_request_count_q;
      issue_expect_error(instruction_i, source0_i, source1_i, destination_i, expected_code_i,
                         expected_stage_i, expected_reason_i);
      if (check_latency_i && (result_cycles > maximum_cycles_i)) begin
        $fatal(1, "APU-P4 fault latency exceeded bound actual=%0d bound=%0d instruction=%016x",
               result_cycles, maximum_cycles_i, instruction_i);
      end
      if (check_no_memory_request_i &&
          (s_dispatcher_request_count_q != s_request_count_before)) begin
        $fatal(1, "APU-P4 rejected local operation reached SRAM instruction=%016x", instruction_i);
      end
    end
  endtask

  initial begin
    logic [31:0] observed, cycles;
    requant_vector_count = 0;
    if ($value$plusargs("VECTOR_COUNT=%d", requant_vector_count)) begin
      if (!$value$plusargs("VECTORS=%s", requant_vector_path)) begin
        $fatal(1, "APU-P4 vector path missing");
      end
      $readmemh(requant_vector_path, requant_vectors);
    end
    flush_i       = 1'b0;
    epoch_clear_i = 1'b0;
    image_valid_i = 1'b0;
    req_valid     = 1'b0;
    instruction   = 64'd0;
    source0       = 32'd0;
    source1       = 32'd0;
    destination   = 32'd0;
    input_valid   = 1'b0;
    input_data    = 41'd0;
    output_accept = 1'b0;
    loader_active = 1'b0;
    loader_req    = 1'b0;
    loader_addr   = 17'd0;
    loader_data   = 32'd0;
    loader_strb   = 4'd0;
    inject_active = 1'b0;
    inject_req    = 1'b0;
    inject_write  = 1'b0;
    inject_addr   = 17'd0;
    inject_data   = 32'd0;
    inject_strb   = 4'd0;

    hard_reset();
    publish_table_word(17'h00000, 32'h0001_0001);
    image_valid_i = 1'b1;
    epoch_clear_i = 1'b1;
    @(posedge clk_i);
    epoch_clear_i = 1'b0;

    inject_word(17'h1a000, 32'h1357_9bdf);
    read_word(17'h1a000, observed);
    if (observed != 32'h1357_9bdf) $fatal(1, "APU-P4 internal-bank mapping mismatch");

    issue(encode_instruction(4'd4, 4'd1, 4'd0, 4'd0, 4'd1, 8'd0, 32'd0), 32'd0, 32'ha5a5_5a5a,
          32'd0, observed, cycles);
    issue(encode_instruction(4'd4, 4'd0, 4'd2, 4'd0, 4'd0, 8'd0, 32'd0), 32'd0, 32'd0, 32'd0,
          observed, cycles);
    if ((observed != 32'ha5a5_5a5a) || (cycles != 32'd2)) begin
      $fatal(1, "APU-P4 local load/store mismatch");
    end

    push_input({1'b0, 5'd0, 3'd4, 32'hdead_beef});
    issue(encode_instruction(4'd4, 4'd5, 4'd4, 4'd0, 4'd0, 8'd0, 32'd0), 32'd0, 32'd0, 32'd0,
          observed, cycles);
    if ((observed != 32'hdead_beef) || (result_data[1] != 32'd4)) begin
      $fatal(1, "APU-P4 FIFO pop mismatch");
    end
    issue(encode_instruction(4'd4, 4'd6, 4'd0, 4'd4, 4'd5, 8'd0, 32'd0), 32'h0102_0304,
          32'h0000_0104, 32'd0, observed, cycles);
    if (!output_valid || (output_data != {1'b1, 5'd0, 3'd4, 32'h0102_0304})) begin
      $fatal(1, "APU-P4 FIFO push mismatch");
    end
    output_accept = 1'b1;
    @(posedge clk_i);
    output_accept = 1'b0;

    push_input({1'b1, 5'd0, 3'd4, 32'h4433_2211});
    issue(encode_instruction(4'd2, 4'd0, 4'd0, 4'd0, 4'd0, 8'd0, 32'd16), 32'd0, 32'd0, 32'd0,
          observed, cycles);
    if ((observed != 32'd32) || (cycles != 32'd3)) $fatal(1, "APU-P4 REFILL mismatch");
    issue(encode_instruction(4'd2, 4'd1, 4'd1, 4'd0, 4'd0, 8'd0, 32'd8), 32'd0, 32'd0, 32'd0,
          observed, cycles);
    if (observed != 32'h11) $fatal(1, "APU-P4 PEEK mismatch");
    issue(encode_instruction(4'd2, 4'd2, 4'd1, 4'd0, 4'd0, 8'd0, 32'd8), 32'd0, 32'd0, 32'd0,
          observed, cycles);
    if (observed != 32'h11) $fatal(1, "APU-P4 GET mismatch");
    issue(encode_instruction(4'd2, 4'd5, 4'd2, 4'd3, 4'd4, 8'd16, 32'd2), 32'h3344, 32'hffff, 32'd0,
          observed, cycles);
    if ((observed != 32'd1) || (cycles != 32'd4)) $fatal(1, "APU-P4 FRAME_SYNC mismatch");
    issue(encode_instruction(4'd2, 4'd3, 4'd0, 4'd0, 4'd0, 8'd0, 32'd4), 32'd0, 32'd0, 32'd0,
          observed, cycles);
    issue(encode_instruction(4'd2, 4'd4, 4'd0, 4'd0, 4'd0, 8'd0, 32'd0), 32'd0, 32'd0, 32'd0,
          observed, cycles);
    issue(encode_instruction(4'd2, 4'd6, 4'd5, 4'd6, 4'd7, 8'd0, 32'd0), 32'd0, 32'h31, 32'd0,
          observed, cycles);
    if (observed != 32'h97) $fatal(1, "APU-P4 CRC8 mismatch");
    issue(encode_instruction(4'd2, 4'd7, 4'd5, 4'd6, 4'd7, 8'd0, 32'd0), 32'd0, 32'h31, 32'd0,
          observed, cycles);
    if (observed != 32'h80a5) $fatal(1, "APU-P4 CRC16 mismatch");

    flush_i = 1'b1;
    @(posedge clk_i);
    flush_i = 1'b0;
    read_word(17'h00000, observed);
    if (observed != 32'h0001_0001) $fatal(1, "APU-P4 table preload mismatch");
    push_input({1'b1, 5'd0, 3'd1, 32'h0000_0000});
    issue(encode_instruction(4'd3, 4'd0, 4'd2, 4'd0, 4'd1, 8'd1, 32'd0), 32'd0, 32'd1, 32'd0,
          observed, cycles);
    if (observed != 32'd1) begin
      $fatal(1, "APU-P4 Huffman mismatch observed=%08x symbol=%08x memory=%08x", observed,
             u_dut.u_entropy_engine.s_symbol_q, memory_read_data);
    end

    flush_i = 1'b1;
    @(posedge clk_i);
    flush_i = 1'b0;
    for (int index = 0; index < 32; index++) begin
      publish_table_word(17'(index * 4), 32'((5 << 16) | index));
    end
    push_input({1'b1, 5'd0, 3'd1, 32'h0000_00f8});
    issue(encode_instruction(4'd3, 4'd0, 4'd2, 4'd0, 4'd1, 8'd5, 32'd0), 32'd0, 32'd32, 32'd0,
          observed, cycles);
    if ((observed != 32'd31) || (cycles != 32'd58)) begin
      $fatal(1, "APU-P4 32-entry Huffman mismatch observed=%0d cycles=%0d", observed, cycles);
    end

    flush_i = 1'b1;
    @(posedge clk_i);
    flush_i = 1'b0;
    publish_table_word(17'h00000, 32'h0001_0023);
    push_input({1'b1, 5'd0, 3'd1, 32'h0000_0000});
    issue(encode_instruction(4'd3, 4'd1, 4'd2, 4'd0, 4'd1, 8'd1, 32'd0), 32'd0, 32'd1, 32'd0,
          observed, cycles);
    if ((observed != 32'd2) || (result_data[1] != 32'd3)) $fatal(1, "APU-P4 Huffman pair mismatch");

    flush_i = 1'b1;
    @(posedge clk_i);
    flush_i = 1'b0;
    publish_table_word(17'h00000, 32'h0001_000a);
    push_input({1'b1, 5'd0, 3'd1, 32'h0000_0000});
    issue(encode_instruction(4'd3, 4'd2, 4'd2, 4'd0, 4'd1, 8'd1, 32'd0), 32'd0, 32'd1, 32'd0,
          observed, cycles);
    if ((observed != 32'd1) || (result_data[1] != 32'd0) ||
        (result_data[2] != 32'd1) || (result_data[3] != 32'd0)) begin
      $fatal(1, "APU-P4 Huffman quad mismatch");
    end

    flush_i = 1'b1;
    @(posedge clk_i);
    flush_i = 1'b0;
    push_input({1'b1, 5'd0, 3'd1, 32'h0000_0020});
    issue(encode_instruction(4'd3, 4'd3, 4'd2, 4'd0, 4'd0, 8'd0, 32'd8), 32'd0, 32'd0, 32'd0,
          observed, cycles);
    if (observed != 32'd2) $fatal(1, "APU-P4 unary mismatch");

    flush_i = 1'b1;
    @(posedge clk_i);
    flush_i = 1'b0;
    push_input({1'b1, 5'd0, 3'd1, 32'h0000_0040});
    issue(encode_instruction(4'd3, 4'd4, 4'd2, 4'd0, 4'd1, 8'd0, 32'd0), 32'd1, 32'd0, 32'd0,
          observed, cycles);
    if (observed != 32'd1) $fatal(1, "APU-P4 Rice4 mismatch");

    flush_i = 1'b1;
    @(posedge clk_i);
    flush_i = 1'b0;
    push_input({1'b1, 5'd0, 3'd1, 32'h0000_0040});
    issue(encode_instruction(4'd3, 4'd5, 4'd2, 4'd0, 4'd1, 8'd0, 32'd0), 32'd1, 32'd0, 32'd0,
          observed, cycles);
    if (observed != 32'd1) $fatal(1, "APU-P4 Rice5 mismatch");

    flush_i = 1'b1;
    @(posedge clk_i);
    flush_i = 1'b0;
    push_input({1'b1, 5'd0, 3'd1, 32'h0000_00c0});
    issue(encode_instruction(4'd3, 4'd6, 4'd2, 4'd0, 4'd1, 8'd0, 32'd0), 32'd4, 32'd1, 32'd0,
          observed, cycles);
    if (observed != 32'hffff_fffb) $fatal(1, "APU-P4 sign restore mismatch");

    issue_expect_error(encode_instruction(4'd4, 4'd6, 4'd0, 4'd0, 4'd1, 8'd0, 32'd0), 32'h1234_5678,
                       32'd0, 32'd0, `APB4_APU__ERROR_CODE_OVERFLOW,
                       `APB4_APU__ERROR_STAGE_RESAMPLER, 8'd9);
    if (output_valid) $fatal(1, "APU-P4 rejected FIFO push mutated output FIFO");
    issue_expect_error(encode_instruction(4'd4, 4'd0, 4'd0, 4'd0, 4'd0, 8'd0, 32'd0), 32'd1, 32'd0,
                       32'd0, `APB4_APU__ERROR_CODE_SEQUENCER, `APB4_APU__ERROR_STAGE_LIFECYCLE,
                       8'd5);
    issue_expect_error(encode_instruction(4'd3, 4'd0, 4'd0, 4'd0, 4'd1, 8'd1, 32'd0), 32'h1800,
                       32'd1, 32'd0, `APB4_APU__ERROR_CODE_SEQUENCER,
                       `APB4_APU__ERROR_STAGE_LIFECYCLE, 8'd5);

    flush_i = 1'b1;
    @(posedge clk_i);
    flush_i = 1'b0;
    push_input({1'b1, 5'd0, 3'd1, 32'h0000_0000});
    issue_expect_error(encode_instruction(4'd2, 4'd2, 4'd0, 4'd0, 4'd0, 8'd0, 32'd16), 32'd0, 32'd0,
                       32'd0, `APB4_APU__ERROR_CODE_TRUNCATED, `APB4_APU__ERROR_STAGE_BITSTREAM,
                       8'd9);

    flush_i = 1'b1;
    @(posedge clk_i);
    flush_i = 1'b0;
    push_input({1'b1, 5'd0, 3'd1, 32'h0000_0000});
    issue_expect_error(encode_instruction(4'd2, 4'd5, 4'd0, 4'd1, 4'd2, 8'd16, 32'd1), 32'hffff,
                       32'hffff, 32'd0, `APB4_APU__ERROR_CODE_MALFORMED,
                       `APB4_APU__ERROR_STAGE_BITSTREAM, 8'd9);

    flush_i = 1'b1;
    @(posedge clk_i);
    flush_i = 1'b0;
    push_input({1'b1, 5'd0, 3'd1, 32'h0000_0000});
    issue_expect_error(encode_instruction(4'd3, 4'd3, 4'd0, 4'd0, 4'd0, 8'd0, 32'd1), 32'd0, 32'd0,
                       32'd0, `APB4_APU__ERROR_CODE_DECODE, `APB4_APU__ERROR_STAGE_ENTROPY, 8'd9);

    inject_word(17'h02100, 32'd100);
    inject_word(17'h02140, 32'h4000_0000);
    inject_word(17'h02144, 32'd3);
    issue_expect_error(encode_instruction(4'd5, 4'd9, 4'd2, 4'd0, 4'd1, 8'd0, 32'd1), 32'h100,
                       32'h140, 32'h180, `APB4_APU__ERROR_CODE_RECONSTRUCTION,
                       `APB4_APU__ERROR_STAGE_RESAMPLER, 8'd9);

    inject_word(17'h02100, 32'd1000);
    inject_word(17'h02140, 32'h4000_0000);
    inject_word(17'h02180, 32'h0000_0140);
    issue_expect_error(encode_instruction(4'd5, 4'd0, 4'd2, 4'd0, 4'd1, 8'h80, 32'd1), 32'h101,
                       32'h180, 32'h1c0, `APB4_APU__ERROR_CODE_SEQUENCER,
                       `APB4_APU__ERROR_STAGE_LIFECYCLE, 8'd5);
    issue_expect_error(encode_instruction(4'd5, 4'd0, 4'd2, 4'd0, 4'd1, 8'h80, 32'd1), 32'h100,
                       32'h181, 32'h1c0, `APB4_APU__ERROR_CODE_SEQUENCER,
                       `APB4_APU__ERROR_STAGE_LIFECYCLE, 8'd5);
    issue_expect_error(encode_instruction(4'd5, 4'd0, 4'd2, 4'd0, 4'd1, 8'h80, 32'd1), 32'h100,
                       32'h180, 32'h1c1, `APB4_APU__ERROR_CODE_SEQUENCER,
                       `APB4_APU__ERROR_STAGE_LIFECYCLE, 8'd5);
    inject_word(17'h02180, 32'h0000_0141);
    issue_expect_error(encode_instruction(4'd5, 4'd0, 4'd2, 4'd0, 4'd1, 8'h80, 32'd1), 32'h100,
                       32'h180, 32'h1c0, `APB4_APU__ERROR_CODE_SEQUENCER,
                       `APB4_APU__ERROR_STAGE_LIFECYCLE, 8'd5);
    inject_word(17'h02180, 32'h0000_0140);
    issue(encode_instruction(4'd5, 4'd0, 4'd2, 4'd0, 4'd1, 8'h80, 32'd1), 32'h100, 32'h180, 32'h1c0,
          observed, cycles);
    if ((observed != 32'd1) || (cycles != 32'd12) || !result_kernel || !kernel_done) begin
      $fatal(1, "APU-P4 REQUANT completion mismatch result=%0d cycles=%0d kernel=%0d done=%0d",
             observed, cycles, result_kernel, kernel_done);
    end
    read_word(17'h021c0, observed);
    if (observed != 32'd1000) $fatal(1, "APU-P4 REQUANT data mismatch");

    inject_word(17'h02200, 32'd10);
    inject_word(17'h02240, 32'd3);
    inject_word(17'h02280, 32'h0000_0240);
    issue(encode_instruction(4'd5, 4'd1, 4'd2, 4'd0, 4'd1, 8'd1, 32'd1), 32'h200, 32'h280, 32'h300,
          observed, cycles);
    if ((observed != 32'd2) || (cycles != 32'd12)) $fatal(1, "APU-P4 STEREO mismatch");
    read_word(17'h02304, observed);
    if (observed != 32'd7) $fatal(1, "APU-P4 STEREO output mismatch");

    for (int index = 0; index < 1536; index++) begin
      publish_table_word(17'(index * 4), 32'd0);
    end
    for (int row = 0; row < 6; row++) begin
      publish_table_word(17'(((row * 6) + row) * 4), 32'h4000_0000);
      inject_word(17'(17'h02400 + (row * 4)), 32'(row + 1));
    end
    inject_word(17'h02480, 32'h8000_0000);
    issue(encode_instruction(4'd5, 4'd2, 4'd2, 4'd0, 4'd1, 8'd0, 32'd1), 32'h400, 32'h480, 32'h500,
          observed, cycles);
    if ((observed != 32'd12) || (cycles != 32'd102)) $fatal(1, "APU-P4 IMDCT6 mismatch");
    read_word(17'h02514, observed);
    if (observed != 32'd6) $fatal(1, "APU-P4 IMDCT6 output mismatch");

    for (int index = 0; index < 648; index++) begin
      publish_table_word(17'(index * 4), 32'd0);
    end
    for (int row = 0; row < 18; row++) begin
      publish_table_word(17'(((row * 18) + row) * 4), 32'h4000_0000);
      inject_word(17'(17'h02600 + (row * 4)), 32'(row + 1));
    end
    inject_word(17'h02680, 32'h8000_0000);
    issue(encode_instruction(4'd5, 4'd3, 4'd2, 4'd0, 4'd1, 8'd0, 32'd1), 32'h600, 32'h680, 32'h700,
          observed, cycles);
    if ((observed != 32'd36) || (cycles != 32'd714)) $fatal(1, "APU-P4 IMDCT18 mismatch");
    read_word(17'h02744, observed);
    if (observed != 32'd18) $fatal(1, "APU-P4 IMDCT18 output mismatch");

    for (int index = 0; index < 1536; index++) begin
      publish_table_word(17'(index * 4), 32'd0);
    end
    for (int row = 0; row < 32; row++) begin
      publish_table_word(17'(((row * 32) + row) * 4), 32'h4000_0000);
      publish_table_word(17'(17'h01000 + (row * 4)), 32'h4000_0000);
      inject_word(17'(17'h02000 + (row * 4)), 32'(row + 1));
    end
    for (int index = 0; index < 512; index++) begin
      inject_word(17'(17'h03000 + (index * 4)), 32'd0);
    end
    inject_word(17'h02800, 32'h8000_0000);
    inject_word(17'h02804, 32'h8000_1000);
    inject_word(17'h02808, 32'h0000_1000);
    inject_word(17'h0280c, 32'd0);
    issue(encode_instruction(4'd5, 4'd4, 4'd2, 4'd0, 4'd1, 8'd0, 32'd1), 32'h000, 32'h800, 32'h2000,
          observed, cycles);
    if ((observed != 32'd32) || (cycles != 32'd2312)) $fatal(1, "APU-P4 DCT32 mismatch");
    read_word(17'h0407c, observed);
    if (observed != 32'd32) $fatal(1, "APU-P4 DCT32 output mismatch");

    inject_word(17'h04200, 32'd1);
    inject_word(17'h04204, 32'd1);
    inject_word(17'h04240, 32'd2);
    inject_word(17'h04244, 32'd1);
    inject_word(17'h04280, 32'h0000_2240);
    issue(encode_instruction(4'd5, 4'd5, 4'd2, 4'd0, 4'd1, 8'd2, 32'd2), 32'h2200, 32'h2280,
          32'h2300, observed, cycles);
    if ((observed != 32'd2) || (cycles != 32'd20)) $fatal(1, "APU-P4 FIXED mismatch");
    read_word(17'h04304, observed);
    if (observed != 32'd7) $fatal(1, "APU-P4 FIXED output mismatch");

    inject_word(17'h04400, 32'd1);
    inject_word(17'h04404, 32'd1);
    inject_word(17'h04440, 32'd1);
    inject_word(17'h04444, 32'd1);
    inject_word(17'h04480, 32'd1);
    inject_word(17'h04484, 32'd0);
    inject_word(17'h044c0, 32'h0000_2440);
    inject_word(17'h044c4, 32'h0000_2480);
    inject_word(17'h044c8, 32'd0);
    issue(encode_instruction(4'd5, 4'd6, 4'd2, 4'd0, 4'd1, 8'd2, 32'd2), 32'h2400, 32'h24c0,
          32'h2500, observed, cycles);
    if ((observed != 32'd2) || (cycles != 32'd26)) $fatal(1, "APU-P4 LPC mismatch");
    read_word(17'h04504, observed);
    if (observed != 32'd4) $fatal(1, "APU-P4 LPC output mismatch");

    inject_word(17'h04600, 32'd10);
    inject_word(17'h04640, 32'd3);
    inject_word(17'h04680, 32'h0000_2640);
    issue(encode_instruction(4'd5, 4'd7, 4'd2, 4'd0, 4'd1, 8'd1, 32'd1), 32'h2600, 32'h2680,
          32'h2700, observed, cycles);
    if (observed != 32'd2) $fatal(1, "APU-P4 DECORRELATE mismatch");
    read_word(17'h04704, observed);
    if (observed != 32'd7) $fatal(1, "APU-P4 DECORRELATE output mismatch");

    for (int profile = 0; profile < 16; profile++) begin
      flush_i = 1'b1;
      @(posedge clk_i);
      flush_i = 1'b0;
      for (int index = 0; index < 17; index++) begin
        inject_word(17'(17'h048e4 + (index * 4)), 32'd0);
      end
      inject_word(17'h04a00, 32'h8000_0000);
      inject_word(17'h04a04, 32'h8000_0800);
      inject_word(17'h04a08, 32'h8000_1000);
      inject_word(17'h04a0c, 32'd0);
      inject_word(17'h04a10, 32'd0);
      inject_word(17'h04a14, 32'd0);
      inject_word(17'h04a18, 32'd0);
      inject_word(17'h04a1c, 32'd1);
      issue(encode_instruction(4'd5, 4'd8, 4'd2, 4'd0, 4'd1, 8'(profile), 32'd1), 32'h2900,
            32'h2a00, 32'h2b00, observed, cycles);
      if (observed != expected_resample_frames(4'(profile))) begin
        $fatal(1, "APU-P4 RESAMPLE profile %0d mismatch result=%0d", profile, observed);
      end
    end
    issue_expect_error(encode_instruction(4'd5, 4'd8, 4'd2, 4'd0, 4'd1, 8'd14, 32'd1), 32'h2900,
                       32'h2a00, 32'h2b00, `APB4_APU__ERROR_CODE_RECONSTRUCTION,
                       `APB4_APU__ERROR_STAGE_RESAMPLER, 8'd9);

    inject_word(17'h04c00, 32'd100);
    inject_word(17'h04c40, 32'h4000_0000);
    inject_word(17'h04c44, 32'd1);
    issue(encode_instruction(4'd5, 4'd9, 4'd2, 4'd0, 4'd1, 8'd4, 32'd1), 32'h2c00, 32'h2c40,
          32'h2d00, observed, cycles);
    if ((observed != 32'd4) || (cycles != 32'd18)) $fatal(1, "APU-P4 PCM_PACK mismatch");
    read_word(17'h04d00, observed);
    if (observed != 32'h0064_0064) $fatal(1, "APU-P4 PCM_PACK output mismatch");

`ifdef APU_P4_SHARED_CORPUS
    `include "apu_p4_corpus_generated.svh"
`endif

    for (int vector_index = 0; vector_index < requant_vector_count; vector_index++) begin
      inject_word(17'h02e00, requant_vectors[(vector_index*4)]);
      inject_word(17'h02e40, requant_vectors[(vector_index*4)+1]);
      inject_word(17'h02e80, 32'h0000_0e40);
      issue(encode_instruction(
            4'd5, 4'd0, 4'd2, 4'd0, 4'd1, requant_vectors[(vector_index*4)+2][7:0], 32'd1),
            32'h0e00, 32'h0e80, 32'h0ec0, observed, cycles);
      read_word(17'h02ec0, observed);
      if (observed != requant_vectors[(vector_index*4)+3]) begin
        $fatal(1, "APU-P4 requant differential mismatch vector=%0d got=%08x expected=%08x",
               vector_index, observed, requant_vectors[(vector_index*4)+3]);
      end
    end

    $display("APU_P4_PRIMITIVES_PASS");
    $finish;
  end

  logic s_unused;
  assign s_unused = memory_ready ^ input_exhausted ^ input_ready ^ output_ready ^
      dispatcher_busy ^ ^result_dst ^ ^result_words;
endmodule
