// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_p4_sequencer_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  logic soft_reset_i, resource_reset_i, abort_i, counter_clear_i, launch_i;
  logic store_loader_active, store_loader_write;
  logic [10:0] store_loader_addr;
  logic [63:0] store_loader_data, store_loader_read_data;
  logic store_loader_valid;
  logic fetch, fetch_valid;
  logic [10:0] fetch_addr;
  logic [63:0] fetch_data;
  logic [2:0][10:0] entry_pc, entry_first, entry_last;
  logic [2:0][15:0] entry_max_loop;
  logic [2:0][23:0] entry_max_retired;
  logic [2:0][16:0] entry_scratch_base, entry_scratch_bytes;
  logic [2:0][31:0] entry_primitive_mask;
  logic [2:0][15:0] entry_table_offset, entry_table_bytes;
  logic primitive_req_valid, primitive_req_ready, primitive_result_valid;
  logic [63:0] primitive_instruction;
  logic [31:0] primitive_source0, primitive_source1, primitive_destination;
  logic [3:0]       primitive_result_dst;
  logic [3:0][31:0] primitive_result_data;
  logic [2:0]       primitive_result_words;
  logic primitive_result_kernel, primitive_error, primitive_kernel_done, primitive_busy;
  logic [5:0] primitive_error_code;
  logic [3:0] primitive_error_stage;
  logic [7:0] primitive_error_reason;
  logic primitive_input_exhausted, primitive_input_ready, primitive_output_ready;
  logic memory_req, memory_write, memory_valid, memory_error;
  logic [16:0] memory_addr;
  logic [31:0] memory_write_data, memory_read_data;
  logic [3:0] memory_strb;
  logic inject_active, inject_req, inject_write;
  logic [16:0] inject_addr;
  logic [31:0] inject_data;
  logic [ 3:0] inject_strb;
  logic codec_req, codec_write;
  logic [16:0] codec_addr;
  logic [31:0] codec_data;
  logic [ 3:0] codec_strb;
  logic [31:0] status, retired;
  logic [15:0][31:0] gpr;
  logic trapped, trap_event, abort_done, fault_valid, sequencer_idle;
  logic [5:0] fault_code;
  logic [3:0] fault_stage;
  logic [1:0] fault_resp;
  logic [7:0] fault_index;
  logic [31:0] fault_addr, fault_detail;
  logic [63:0] perf_retired;
  logic [16:0] active_scratch_base, active_scratch_bytes;
  logic [31:0] active_primitive_mask;
  logic [15:0] active_table_offset, active_table_bytes;
  logic launch_epoch;

  always #5 clk_i = ~clk_i;

  always_ff @(posedge clk_i) begin
    if (rst_n_i && primitive_busy && primitive_req_valid &&
        (primitive_instruction[63:60] != `APB4_APU__MC_CLASS_KERNEL)) begin
      $fatal(1, "APU-P4 issued a second primitive while the kernel owned local SRAM");
    end
  end

  assign codec_req   = inject_active ? inject_req : memory_req;
  assign codec_write = inject_active ? inject_write : memory_write;
  assign codec_addr  = inject_active ? inject_addr : memory_addr;
  assign codec_data  = inject_active ? inject_data : memory_write_data;
  assign codec_strb  = inject_active ? inject_strb : memory_strb;

  apu_control_store u_control_store (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .loader_active_i(store_loader_active),
      .loader_read_i  (1'b0),
      .loader_write_i (store_loader_write),
      .loader_addr_i  (store_loader_addr),
      .loader_data_i  (store_loader_data),
      .loader_data_o  (store_loader_read_data),
      .loader_valid_o (store_loader_valid),
      .image_valid_i  (1'b1),
      .fetch_i        (fetch),
      .fetch_addr_i   (fetch_addr),
      .fetch_data_o   (fetch_data),
      .fetch_valid_o  (fetch_valid)
  );

  apu_local_sram u_local_sram (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .image_valid_i     (1'b1),
      .table_bytes_i     (16'd0),
      .epoch_clear_i     (launch_epoch || soft_reset_i || resource_reset_i || abort_i),
      .loader_active_i   (1'b0),
      .loader_req_i      (1'b0),
      .loader_addr_i     (17'd0),
      .loader_data_i     (32'd0),
      .loader_strb_i     (4'd0),
      .loader_ready_o    (),
      .codec_req_i       (codec_req),
      .codec_write_i     (codec_write),
      .codec_addr_i      (codec_addr),
      .codec_data_i      (codec_data),
      .codec_strb_i      (codec_strb),
      .codec_ready_o     (),
      .codec_data_o      (memory_read_data),
      .codec_valid_o     (memory_valid),
      .codec_access_err_o(memory_error)
  );

  apu_primitive_dispatcher u_dispatcher (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .flush_i          (launch_epoch || soft_reset_i || resource_reset_i || abort_i),
      .req_valid_i      (primitive_req_valid),
      .req_ready_o      (primitive_req_ready),
      .instruction_i    (primitive_instruction),
      .source0_i        (primitive_source0),
      .source1_i        (primitive_source1),
      .destination_i    (primitive_destination),
      .scratch_base_i   (active_scratch_base),
      .scratch_bytes_i  (active_scratch_bytes),
      .table_offset_i   (active_table_offset),
      .table_bytes_i    (active_table_bytes),
      .result_valid_o   (primitive_result_valid),
      .result_dst_o     (primitive_result_dst),
      .result_data_o    (primitive_result_data),
      .result_words_o   (primitive_result_words),
      .result_kernel_o  (primitive_result_kernel),
      .error_o          (primitive_error),
      .error_code_o     (primitive_error_code),
      .error_stage_o    (primitive_error_stage),
      .error_reason_o   (primitive_error_reason),
      .cycles_o         (),
      .kernel_done_o    (primitive_kernel_done),
      .busy_o           (primitive_busy),
      .input_exhausted_o(primitive_input_exhausted),
      .input_ready_o    (primitive_input_ready),
      .output_ready_o   (primitive_output_ready),
      .input_count_o    (),
      .output_count_o   (),
      .kernel_busy_o    (),
      .memory_req_o     (memory_req),
      .memory_write_o   (memory_write),
      .memory_addr_o    (memory_addr),
      .memory_data_o    (memory_write_data),
      .memory_strb_o    (memory_strb),
      .memory_valid_i   (memory_valid),
      .memory_data_i    (memory_read_data),
      .memory_error_i   (memory_error),
      .input_valid_i    (1'b0),
      .input_data_i     (41'd0),
      .input_accept_o   (),
      .output_valid_o   (),
      .output_data_o    (),
      .output_accept_i  (1'b0)
  );

  apu_codec_sequencer #(
      .EnableP4(1'b1)
  ) u_sequencer (
      .clk_i                    (clk_i),
      .rst_n_i                  (rst_n_i),
      .soft_reset_i             (soft_reset_i),
      .resource_reset_i         (resource_reset_i),
      .counter_clear_i          (counter_clear_i),
      .abort_i                  (abort_i),
      .launch_i                 (launch_i),
      .launch_entry_i           (2'd0),
      .image_valid_i            (1'b1),
      .timeout_i                (32'd4096),
      .entry_pc_i               (entry_pc),
      .entry_first_i            (entry_first),
      .entry_last_i             (entry_last),
      .entry_max_loop_i         (entry_max_loop),
      .entry_max_retired_i      (entry_max_retired),
      .entry_scratch_base_i     (entry_scratch_base),
      .entry_scratch_bytes_i    (entry_scratch_bytes),
      .entry_primitive_mask_i   (entry_primitive_mask),
      .entry_table_offset_i     (entry_table_offset),
      .entry_table_bytes_i      (entry_table_bytes),
      .input_exhausted_i        (primitive_input_exhausted),
      .input_ready_i            (primitive_input_ready),
      .output_ready_i           (primitive_output_ready),
      .kernel_done_i            (primitive_kernel_done),
      .transport_idle_success_i (1'b1),
      .stall_i                  (1'b0),
      .cause_valid_i            (1'b0),
      .cause_code_i             (6'd0),
      .cause_stage_i            (4'd0),
      .cause_resp_i             (2'd0),
      .cause_index_i            (8'd0),
      .cause_addr_i             (32'd0),
      .cause_detail_i           (32'd0),
      .primitive_req_valid_o    (primitive_req_valid),
      .primitive_req_ready_i    (primitive_req_ready),
      .primitive_instruction_o  (primitive_instruction),
      .primitive_source0_o      (primitive_source0),
      .primitive_source1_o      (primitive_source1),
      .primitive_destination_o  (primitive_destination),
      .primitive_result_valid_i (primitive_result_valid),
      .primitive_result_dst_i   (primitive_result_dst),
      .primitive_result_data_i  (primitive_result_data),
      .primitive_result_words_i (primitive_result_words),
      .primitive_result_kernel_i(primitive_result_kernel),
      .primitive_error_i        (primitive_error),
      .primitive_error_code_i   (primitive_error_code),
      .primitive_error_stage_i  (primitive_error_stage),
      .primitive_error_reason_i (primitive_error_reason),
      .fetch_o                  (fetch),
      .fetch_addr_o             (fetch_addr),
      .fetch_data_i             (fetch_data),
      .fetch_valid_i            (fetch_valid),
      .stat_o                   (status),
      .retired_o                (retired),
      .gpr_o                    (gpr),
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
      .perf_retired_o           (perf_retired),
      .active_scratch_base_o    (active_scratch_base),
      .active_scratch_bytes_o   (active_scratch_bytes),
      .active_primitive_mask_o  (active_primitive_mask),
      .active_table_offset_o    (active_table_offset),
      .active_table_bytes_o     (active_table_bytes),
      .launch_epoch_o           (launch_epoch),
      .idle_o                   (sequencer_idle)
  );

  function automatic logic [63:0] encode_instruction(
      input logic [3:0] instruction_class_i, input logic [3:0] opcode_i, input logic [3:0] dst_i,
      input logic [3:0] src0_i, input logic [3:0] src1_i, input logic [7:0] aux_i,
      input logic [31:0] immediate_i);
    return {instruction_class_i, opcode_i, 4'd0, dst_i, src0_i, src1_i, aux_i, immediate_i};
  endfunction

  task automatic load_instruction(input logic [10:0] address_i, input logic [63:0] data_i);
    begin
      @(negedge clk_i);
      store_loader_active = 1'b1;
      store_loader_write  = 1'b1;
      store_loader_addr   = address_i;
      store_loader_data   = data_i;
      @(negedge clk_i);
      store_loader_write = 1'b0;
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

  initial begin
    soft_reset_i         = 1'b0;
    resource_reset_i     = 1'b0;
    abort_i              = 1'b0;
    counter_clear_i      = 1'b0;
    launch_i             = 1'b0;
    store_loader_active  = 1'b0;
    store_loader_write   = 1'b0;
    store_loader_addr    = 11'd0;
    store_loader_data    = 64'd0;
    inject_active        = 1'b0;
    inject_req           = 1'b0;
    inject_write         = 1'b0;
    inject_addr          = 17'd0;
    inject_data          = 32'd0;
    inject_strb          = 4'd0;
    entry_pc             = {11'd0, 11'd0, 11'd0};
    entry_first          = {11'd0, 11'd0, 11'd0};
    entry_last           = {11'd10, 11'd10, 11'd10};
    entry_max_loop       = {16'd4, 16'd4, 16'd4};
    entry_max_retired    = {24'd32, 24'd32, 24'd32};
    entry_scratch_base   = {17'd0, 17'd0, 17'd0};
    entry_scratch_bytes  = {17'h06000, 17'h06000, 17'h06000};
    entry_primitive_mask = {32'h0000_0070, 32'h0000_0070, 32'h0000_0070};
    entry_table_offset   = {16'd0, 16'd0, 16'd0};
    entry_table_bytes    = {16'd0, 16'd0, 16'd0};

    rst_n_i              = 1'b0;
    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (2) @(posedge clk_i);

    load_instruction(11'd0, encode_instruction(4'd1, 4'd1, 4'd0, 4'd0, 4'd0, 8'd0, 32'h0000_0100));
    load_instruction(11'd1, encode_instruction(4'd1, 4'd1, 4'd1, 4'd0, 4'd0, 8'd0, 32'h0000_0180));
    load_instruction(11'd2, encode_instruction(4'd1, 4'd1, 4'd4, 4'd0, 4'd0, 8'd0, 32'h0000_01c0));
    load_instruction(11'd3, encode_instruction(4'd1, 4'd1, 4'd5, 4'd0, 4'd0, 8'd0, 32'h0000_0200));
    load_instruction(11'd4, encode_instruction(4'd1, 4'd1, 4'd6, 4'd0, 4'd0, 8'd0, 32'h1234_5678));
    load_instruction(11'd5, encode_instruction(4'd5, 4'd0, 4'd4, 4'd0, 4'd1, 8'h80, 32'd1));
    load_instruction(11'd6, encode_instruction(4'd1, 4'd1, 4'd7, 4'd0, 4'd0, 8'd0, 32'h0000_0055));
    load_instruction(11'd7, encode_instruction(4'd4, 4'd1, 4'd0, 4'd5, 4'd6, 8'd0, 32'd0));
    load_instruction(11'd8, encode_instruction(4'd0, 4'd8, 4'd0, 4'd0, 4'd0, 8'd1, 32'd0));
    load_instruction(11'd9, encode_instruction(4'd4, 4'd0, 4'd3, 4'd5, 4'd0, 8'd0, 32'd0));
    load_instruction(11'd10, encode_instruction(4'd0, 4'd1, 4'd0, 4'd0, 4'd0, 8'd0, 32'd0));

    @(negedge clk_i);
    launch_i = 1'b1;
    @(negedge clk_i);
    launch_i            = 1'b0;
    store_loader_active = 1'b0;
    inject_word(17'h00100, 32'd1000);
    inject_word(17'h00140, 32'h4000_0000);
    inject_word(17'h00180, 32'h0000_0140);
    for (int cycle = 0; cycle < 10000; cycle++) begin
      @(posedge clk_i);
      if (fault_valid || trapped) begin
        $fatal(
            1,
            "APU-P4 sequencer fault code=%0d detail=%08x status=%08x insn=%016x legal=%0d r5=%08x r6=%08x valid=%0d",
            fault_code, fault_detail, status, u_sequencer.s_instruction_q,
            apu_microcode_pkg::instruction_encoding_valid(u_sequencer.s_instruction_q), gpr[5],
            gpr[6], u_local_sram.s_mutable_valid_q[17'h00200>>2]);
      end
      if (sequencer_idle && !primitive_busy && (retired != 32'd0)) break;
      if (cycle == 9999) $fatal(1, "APU-P4 sequencer timed out");
    end
    if ((gpr[3] != 32'h1234_5678) || (gpr[4] != 32'd1) || (gpr[7] != 32'h55) ||
        (retired != 32'd11) || (perf_retired != 64'd11)) begin
      $fatal(1, "APU-P4 sequencer mismatch r3=%0d r4=%0d r7=%0d retired=%0d perf=%0d", gpr[3],
             gpr[4], gpr[7], retired, perf_retired);
    end

    @(negedge clk_i);
    store_loader_active = 1'b1;
    launch_i            = 1'b1;
    @(negedge clk_i);
    launch_i            = 1'b0;
    store_loader_active = 1'b0;
    @(posedge clk_i);
    if (u_local_sram.s_mutable_valid_q[17'h00200>>2] ||
        u_dispatcher.u_kernel_engine.s_resample_profile_valid_q) begin
      $fatal(1, "APU-P4 launch did not clear the mutable-data epoch");
    end
    inject_word(17'h00100, 32'd2000);
    inject_word(17'h00140, 32'h4000_0000);
    inject_word(17'h00180, 32'h0000_0140);
    for (int cycle = 0; cycle < 10000; cycle++) begin
      @(posedge clk_i);
      if (fault_valid || trapped) begin
        $fatal(1, "APU-P4 second launch fault code=%0d detail=%08x", fault_code, fault_detail);
      end
      if (sequencer_idle && !primitive_busy && (retired != 32'd0)) break;
      if (cycle == 9999) $fatal(1, "APU-P4 second launch timed out");
    end
    if ((gpr[3] != 32'h1234_5678) || (gpr[4] != 32'd1) || (retired != 32'd11)) begin
      $fatal(1, "APU-P4 second launch result mismatch");
    end
    $display("APU_P4_SEQUENCER_PASS");
    $finish;
  end

  logic s_unused;
  assign s_unused = store_loader_read_data[0] ^ store_loader_valid ^ trap_event ^ abort_done ^
      fault_stage[0] ^ fault_resp[0] ^ fault_index[0] ^ fault_addr[0] ^
      active_primitive_mask[0];
endmodule
