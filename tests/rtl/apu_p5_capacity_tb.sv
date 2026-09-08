// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_p5_capacity_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  logic start_i, seq_launch;
  logic [1:0] seq_launch_entry;
  logic [31:0] image_addr_i, image_size_i, expected_crc_i;
  logic dma_request_valid, dma_ready, dma_done;
  logic [31:0] dma_request_addr, dma_request_bytes, dma_data;
  logic [3:0] dma_keep;
  logic dma_last, dma_valid;
  logic store_active, store_read, store_write, store_valid;
  logic [11:0] store_addr;
  logic [63:0] store_write_data, store_read_data;
  logic [7:0] mc_status;
  logic [31:0] mc_abi, mc_actual_crc;
  logic [63:0] mc_build_id;
  logic mc_lock, mc_idle;
  logic [2:0][11:0] entry_pc, entry_first, entry_last;
  logic [2:0][15:0] entry_max_loop;
  logic [2:0][23:0] entry_max_retired;
  logic seq_fetch, seq_fetch_valid, seq_idle, seq_trapped, seq_trap_event;
  logic [11:0] seq_fetch_addr;
  logic [63:0] seq_fetch_data;
  logic [31:0] seq_status, seq_retired, seq_fault_addr, seq_fault_detail;
  logic [15:0][31:0] seq_gpr;
  logic              loader_fault_valid;
  logic [5:0] loader_fault_code, loader_fault_code_q;
  logic [3:0] loader_fault_stage, loader_fault_stage_q;
  logic [1:0] loader_fault_resp, loader_fault_resp_q;
  logic [31:0] loader_fault_addr, loader_fault_addr_q;
  logic [31:0] loader_fault_detail, loader_fault_detail_q;
  logic        loader_fault_seen_q;
  logic [31:0] image               [0:8447];
  logic        transfer_active_q;
  logic [13:0] transfer_word_q, transfer_beat_q;
  logic  [31:0] transfer_bytes_q;
  string        image_path;

  always #5 clk_i = ~clk_i;

  assign dma_valid = transfer_active_q;
  assign dma_data  = image[transfer_word_q];
  assign dma_keep  = 4'hf;
  assign dma_last  = transfer_beat_q == ((transfer_bytes_q >> 2) - 1'b1);

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      transfer_active_q     <= 1'b0;
      transfer_word_q       <= 14'd0;
      transfer_beat_q       <= 14'd0;
      transfer_bytes_q      <= 32'd0;
      dma_done              <= 1'b0;
      loader_fault_seen_q   <= 1'b0;
      loader_fault_code_q   <= 6'd0;
      loader_fault_stage_q  <= 4'd0;
      loader_fault_resp_q   <= 2'd0;
      loader_fault_addr_q   <= 32'd0;
      loader_fault_detail_q <= 32'd0;
    end else begin
      dma_done <= 1'b0;
      if (dma_request_valid) begin
        transfer_active_q <= 1'b1;
        transfer_word_q   <= 14'((dma_request_addr - image_addr_i) >> 2);
        transfer_beat_q   <= 14'd0;
        transfer_bytes_q  <= dma_request_bytes;
      end
      if (dma_valid && dma_ready) begin
        if (dma_last) begin
          transfer_active_q <= 1'b0;
          dma_done          <= 1'b1;
        end else begin
          transfer_word_q <= transfer_word_q + 1'b1;
          transfer_beat_q <= transfer_beat_q + 1'b1;
        end
      end
    end
  end

  always @(negedge clk_i) begin
    if (loader_fault_valid) begin
      loader_fault_seen_q   <= 1'b1;
      loader_fault_code_q   <= loader_fault_code;
      loader_fault_stage_q  <= loader_fault_stage;
      loader_fault_resp_q   <= loader_fault_resp;
      loader_fault_addr_q   <= loader_fault_addr;
      loader_fault_detail_q <= loader_fault_detail;
    end
  end

  apu_microcode_loader #(
      .PathStackDepth(4096),
      .EnableP4      (1'b1),
      .EnableP5      (1'b1)
  ) u_loader (
      .clk_i,
      .rst_n_i,
      .start_i,
      .abort_i               (1'b0),
      .resource_reset_i      (1'b0),
      .soft_reset_i          (1'b0),
      .counter_clear_i       (1'b0),
      .image_addr_i,
      .image_size_i,
      .expected_crc_i,
      .dma_request_valid_o   (dma_request_valid),
      .dma_request_ready_i   (1'b1),
      .dma_request_addr_o    (dma_request_addr),
      .dma_request_bytes_o   (dma_request_bytes),
      .dma_data_i            (dma_data),
      .dma_keep_i            (dma_keep),
      .dma_last_i            (dma_last),
      .dma_valid_i           (dma_valid),
      .dma_ready_o           (dma_ready),
      .dma_done_i            (dma_done),
      .dma_err_i             (1'b0),
      .dma_err_code_i        (6'd0),
      .dma_err_stage_i       (4'd0),
      .dma_err_resp_i        (2'd0),
      .dma_err_addr_i        (32'd0),
      .store_active_o        (store_active),
      .store_read_o          (store_read),
      .store_write_o         (store_write),
      .store_addr_o          (store_addr),
      .store_data_o          (store_write_data),
      .store_data_i          (store_read_data),
      .store_valid_i         (store_valid),
      .local_write_o         (),
      .local_addr_o          (),
      .local_data_o          (),
      .local_strb_o          (),
      .table_bytes_o         (),
      .stat_o                (mc_status),
      .abi_o                 (mc_abi),
      .build_id_o            (mc_build_id),
      .lock_o                (mc_lock),
      .actual_crc_o          (mc_actual_crc),
      .load_count_o          (),
      .entry_pc_o            (entry_pc),
      .entry_first_o         (entry_first),
      .entry_last_o          (entry_last),
      .entry_max_loop_o      (entry_max_loop),
      .entry_max_retired_o   (entry_max_retired),
      .entry_scratch_base_o  (),
      .entry_scratch_bytes_o (),
      .entry_primitive_mask_o(),
      .entry_table_offset_o  (),
      .entry_table_bytes_o   (),
      .load_done_o           (),
      .abort_done_o          (),
      .fault_valid_o         (loader_fault_valid),
      .fault_code_o          (loader_fault_code),
      .fault_stage_o         (loader_fault_stage),
      .fault_resp_o          (loader_fault_resp),
      .fault_addr_o          (loader_fault_addr),
      .fault_detail_o        (loader_fault_detail),
      .proof_visit_count_o   (),
      .proof_memo_full_o     (),
      .idle_o                (mc_idle)
  );

  apu_control_store #(
      .Depth(4096)
  ) u_store (
      .clk_i,
      .rst_n_i,
      .loader_active_i(store_active),
      .loader_read_i  (store_read),
      .loader_write_i (store_write),
      .loader_addr_i  (store_addr),
      .loader_data_i  (store_write_data),
      .loader_data_o  (store_read_data),
      .loader_valid_o (store_valid),
      .image_valid_i  (mc_status[`APB4_APU__MC_STATUS_VALID]),
      .fetch_i        (seq_fetch),
      .fetch_addr_i   (seq_fetch_addr),
      .fetch_data_o   (seq_fetch_data),
      .fetch_valid_o  (seq_fetch_valid)
  );

  apu_codec_sequencer #(
      .EnableP4(1'b1),
      .EnableP5(1'b1)
  ) u_sequencer (
      .clk_i,
      .rst_n_i,
      .soft_reset_i             (1'b0),
      .resource_reset_i         (1'b0),
      .counter_clear_i          (1'b0),
      .abort_i                  (1'b0),
      .launch_i                 (seq_launch),
      .launch_entry_i           (seq_launch_entry),
      .image_valid_i            (mc_status[`APB4_APU__MC_STATUS_VALID]),
      .image_abi_i              (mc_abi),
      .timeout_i                (32'd65535),
      .entry_pc_i               (entry_pc),
      .entry_first_i            (entry_first),
      .entry_last_i             (entry_last),
      .entry_max_loop_i         (entry_max_loop),
      .entry_max_retired_i      (entry_max_retired),
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
      .dma_idle_success_i       (1'b1),
      .tx_idle_i                (1'b1),
      .ring_writeback_idle_i    (1'b1),
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
      .transport_req_valid_o    (),
      .transport_req_ready_i    (1'b0),
      .transport_opcode_o       (),
      .transport_dst_o          (),
      .transport_aux_o          (),
      .transport_event_o        (),
      .transport_source0_o      (),
      .transport_source1_o      (),
      .transport_result_valid_i (1'b0),
      .transport_result_dst_i   (4'd0),
      .transport_result_data_i  (32'd0),
      .fetch_o                  (seq_fetch),
      .fetch_addr_o             (seq_fetch_addr),
      .fetch_data_i             (seq_fetch_data),
      .fetch_valid_i            (seq_fetch_valid),
      .stat_o                   (seq_status),
      .retired_o                (seq_retired),
      .gpr_o                    (seq_gpr),
      .trapped_o                (seq_trapped),
      .trap_event_o             (seq_trap_event),
      .end_event_o              (),
      .abort_done_o             (),
      .fault_valid_o            (),
      .fault_code_o             (),
      .fault_stage_o            (),
      .fault_resp_o             (),
      .fault_index_o            (),
      .fault_addr_o             (seq_fault_addr),
      .fault_detail_o           (seq_fault_detail),
      .perf_retired_o           (),
      .active_scratch_base_o    (),
      .active_scratch_bytes_o   (),
      .active_primitive_mask_o  (),
      .active_table_offset_o    (),
      .active_table_bytes_o     (),
      .launch_epoch_o           (),
      .idle_o                   (seq_idle)
  );

  initial begin
    logic [31:0] expected_status;
    logic [31:0] expected_fault_addr;
    logic [31:0] expected_fault_detail;
    logic [ 5:0] expected_fault_code;
    logic        expect_failure;

    if (!$value$plusargs("IMAGE=%s", image_path)) $fatal(1, "IMAGE plusarg missing");
    expect_failure        = $value$plusargs("EXPECT_STATUS=%h", expected_status);
    expected_fault_addr   = 32'd0;
    expected_fault_detail = 32'd0;
    expected_fault_code   = `APB4_APU__ERROR_CODE_MICROCODE;
    void'($value$plusargs("EXPECT_FAULT_ADDR=%h", expected_fault_addr));
    void'($value$plusargs("EXPECT_FAULT_DETAIL=%h", expected_fault_detail));
    void'($value$plusargs("EXPECT_FAULT_CODE=%h", expected_fault_code));
    $readmemh(image_path, image);
    start_i          = 1'b0;
    seq_launch       = 1'b0;
    seq_launch_entry = 2'd0;
    image_addr_i     = 32'h3000_0000;
    image_size_i     = image[2];
    expected_crc_i   = image[11];
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    start_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b0;
    wait (mc_status[`APB4_APU__MC_STATUS_BUSY]);
    wait (!mc_status[`APB4_APU__MC_STATUS_BUSY]);
    @(posedge clk_i);
    if (expect_failure) begin
      if ((mc_status != expected_status[7:0]) || mc_lock ||
          mc_status[`APB4_APU__MC_STATUS_VALID] || !loader_fault_seen_q ||
          (loader_fault_code_q != expected_fault_code) ||
          (loader_fault_stage_q != `APB4_APU__ERROR_STAGE_LOADER) ||
          (loader_fault_resp_q != 2'd0) || (loader_fault_addr_q != expected_fault_addr) ||
          (loader_fault_detail_q != expected_fault_detail)) begin
        $fatal(1, "APU-P5 rejection mismatch status=%h lock=%b fault=%b/%0d/%0d/%0d/%h/%h",
               mc_status, mc_lock, loader_fault_seen_q, loader_fault_code_q, loader_fault_stage_q,
               loader_fault_resp_q, loader_fault_addr_q, loader_fault_detail_q);
      end
      $display("APU-P5 version rejection passed status=%h", mc_status);
      $finish;
    end
    if ((mc_status != 8'h02) || !mc_lock || (mc_abi != `APB4_APU__APUMC_ABI_V2) ||
        (mc_actual_crc != expected_crc_i) || (entry_pc[0] != 12'd2045) ||
        (entry_pc[1] != 12'd0) || (entry_pc[2] != 12'd2048) ||
        (entry_last[2] != 12'd4093)) begin
      $fatal(
          1,
          "APU-P5 V2 publication mismatch status=%h abi=%h header=%h v2=%b entries=%0d/%0d/%0d control=%h/%h pc=%0d instr=%h valid=%b scanerr=%b target=%0d targeterr=%b",
          mc_status, mc_abi, u_loader.s_header_q[1], u_loader.s_header_v2, entry_pc[0], entry_pc[2],
          entry_last[2], u_loader.s_scan_control_addr_q, u_loader.s_scan_control_detail_q,
          u_loader.s_scan_control_pc_q, u_loader.s_scan_instruction,
          apu_microcode_pkg::instruction_encoding_valid(u_loader.s_scan_instruction, 1'b1),
          u_loader.s_scan_instruction_err, u_loader.s_scan_target, u_loader.s_scan_target_err);
    end
    if ((u_store.mem[0] == u_store.mem[2048]) || (u_store.mem[2048] == u_store.mem[3072])) begin
      $fatal(1, "APU-P5 control-store depth banks aliased");
    end
    @(negedge clk_i);
    seq_launch_entry = 2'd0;
    seq_launch       = 1'b1;
    @(negedge clk_i);
    seq_launch = 1'b0;
    wait (seq_idle);
    if (seq_trapped || seq_trap_event || (seq_retired != 32'd2) ||
        !seq_status[`APB4_APU__SEQUENCER_STATUS_PC_HIGH] ||
        (seq_status[10:0] != 11'd2046)) begin
      $fatal(1, "APU-P5 V2 branch mismatch status=%h retired=%0d fault=%h/%h", seq_status,
             seq_retired, seq_fault_addr, seq_fault_detail);
    end
    @(negedge clk_i);
    seq_launch_entry = 2'd2;
    seq_launch       = 1'b1;
    @(negedge clk_i);
    seq_launch = 1'b0;
    wait (seq_idle);
    if (seq_trapped || seq_trap_event || (seq_retired != 32'd2046) ||
        (seq_gpr[1] != 32'h0000_0800) || (seq_gpr[2] != 32'h0000_0c00) ||
        !seq_status[`APB4_APU__SEQUENCER_STATUS_PC_HIGH] ||
        (seq_status[10:0] != 11'd2045)) begin
      $fatal(1, "APU-P5 high-PC execution mismatch status=%h retired=%0d fault=%h/%h", seq_status,
             seq_retired, seq_fault_addr, seq_fault_detail);
    end
    $display("APU-P5 4096-word loader/store/sequencer passed");
    $finish;
  end

  initial begin
    repeat (200000) @(posedge clk_i);
    $fatal(1, "APU-P5 capacity timeout");
  end
endmodule
