// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_p3_microcode_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  logic start_i, abort_i, resource_reset_i, soft_reset_i, counter_clear_i;
  logic [31:0] image_addr_i, image_size_i, expected_crc_i;
  logic dma_request_valid, dma_request_ready;
  logic [31:0] dma_request_addr, dma_request_bytes;
  logic [31:0] dma_data;
  logic [ 3:0] dma_keep;
  logic dma_last, dma_valid, dma_ready, dma_done, dma_error;
  logic store_active, store_read, store_write, store_valid;
  logic [10:0] store_addr;
  logic [63:0] store_write_data, store_read_data;
  logic [7:0] mc_status;
  logic [31:0] mc_abi, mc_actual_crc, mc_load_count;
  logic [63:0] mc_build_id;
  logic mc_lock, mc_load_done, mc_abort_done, mc_fault_valid, mc_idle;
  logic [5:0] mc_fault_code;
  logic [3:0] mc_fault_stage;
  logic [1:0] mc_fault_resp;
  logic [31:0] mc_fault_addr, mc_fault_detail;
  logic [2:0][10:0] entry_pc, entry_first, entry_last;
  logic [2:0][15:0] entry_max_loop;
  logic [2:0][23:0] entry_max_retired;
  logic seq_launch, seq_stall, seq_fetch, seq_fetch_valid, seq_trapped, seq_trap_event;
  logic seq_abort_done, seq_fault_valid, seq_idle;
  logic [10:0] seq_fetch_addr;
  logic [63:0] seq_fetch_data, seq_perf_retired;
  logic [31:0] seq_status, seq_retired, seq_timeout;
  logic [15:0][31:0] seq_gpr;
  logic [ 5:0]       seq_fault_code;
  logic [ 3:0]       seq_fault_stage;
  logic [ 1:0]       seq_fault_resp;
  logic [ 7:0]       seq_fault_index;
  logic [31:0] seq_fault_addr, seq_fault_detail;
  logic [31:0] image               [0:4095];
  logic        transfer_active_q;
  logic [11:0] transfer_word_q;
  logic [11:0] transfer_beat_q;
  logic [31:0] transfer_bytes_q;
  logic [31:0] saved_word;
  logic [ 3:0] dma_request_count_q;
  logic [11:0] store_write_count_q;
  string image_path, invalid_cf_image_path, invalid_loop_image_path, diagnostic_image_path;
  string lexical_path_image_path, deep_path_image_path;

  always #5 clk_i = ~clk_i;
  always @(posedge clk_i) begin
    if (mc_status[0] && (mc_status[7:1] != 7'd0)) begin
      $fatal(1, "APU-P3 loader exposed non-atomic status");
    end
  end

  assign dma_request_ready = 1'b1;
  assign dma_valid         = transfer_active_q;
  assign dma_data          = image[transfer_word_q];
  assign dma_keep          = 4'hf;
  assign dma_last          = transfer_beat_q == ((transfer_bytes_q >> 2) - 1'b1);

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      transfer_active_q   <= 1'b0;
      transfer_word_q     <= 12'd0;
      transfer_beat_q     <= 12'd0;
      transfer_bytes_q    <= 32'd0;
      dma_done            <= 1'b0;
      dma_request_count_q <= 4'd0;
      store_write_count_q <= 12'd0;
    end else begin
      dma_done <= 1'b0;
      if (dma_request_valid && dma_request_ready) begin
        dma_request_count_q <= dma_request_count_q + 1'b1;
        transfer_active_q   <= 1'b1;
        transfer_word_q     <= 12'((dma_request_addr - image_addr_i) >> 2);
        transfer_beat_q     <= 12'd0;
        transfer_bytes_q    <= dma_request_bytes;
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
      if (abort_i || resource_reset_i) begin
        transfer_active_q <= 1'b0;
        dma_done          <= 1'b1;
      end
      if (store_write) begin
        if (dma_request_count_q < 4'd3) begin
          $fatal(1, "APU-P3 control-store write preceded descriptor/range admission");
        end
        store_write_count_q <= store_write_count_q + 1'b1;
      end
    end
  end

  apu_microcode_loader u_loader (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .start_i            (start_i),
      .abort_i            (abort_i),
      .resource_reset_i   (resource_reset_i),
      .soft_reset_i       (soft_reset_i),
      .counter_clear_i    (counter_clear_i),
      .image_addr_i       (image_addr_i),
      .image_size_i       (image_size_i),
      .expected_crc_i     (expected_crc_i),
      .dma_request_valid_o(dma_request_valid),
      .dma_request_ready_i(dma_request_ready),
      .dma_request_addr_o (dma_request_addr),
      .dma_request_bytes_o(dma_request_bytes),
      .dma_data_i         (dma_data),
      .dma_keep_i         (dma_keep),
      .dma_last_i         (dma_last),
      .dma_valid_i        (dma_valid),
      .dma_ready_o        (dma_ready),
      .dma_done_i         (dma_done),
      .dma_err_i          (dma_error),
      .dma_err_code_i     (6'd15),
      .dma_err_stage_i    (4'd3),
      .dma_err_resp_i     (2'd2),
      .dma_err_addr_i     (image_addr_i),
      .store_active_o     (store_active),
      .store_read_o       (store_read),
      .store_write_o      (store_write),
      .store_addr_o       (store_addr),
      .store_data_o       (store_write_data),
      .store_data_i       (store_read_data),
      .store_valid_i      (store_valid),
      .stat_o             (mc_status),
      .abi_o              (mc_abi),
      .build_id_o         (mc_build_id),
      .lock_o             (mc_lock),
      .actual_crc_o       (mc_actual_crc),
      .load_count_o       (mc_load_count),
      .entry_pc_o         (entry_pc),
      .entry_first_o      (entry_first),
      .entry_last_o       (entry_last),
      .entry_max_loop_o   (entry_max_loop),
      .entry_max_retired_o(entry_max_retired),
      .load_done_o        (mc_load_done),
      .abort_done_o       (mc_abort_done),
      .fault_valid_o      (mc_fault_valid),
      .fault_code_o       (mc_fault_code),
      .fault_stage_o      (mc_fault_stage),
      .fault_resp_o       (mc_fault_resp),
      .fault_addr_o       (mc_fault_addr),
      .fault_detail_o     (mc_fault_detail),
      .idle_o             (mc_idle)
  );

  apu_control_store u_store (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
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

  apu_codec_sequencer u_sequencer (
      .clk_i                   (clk_i),
      .rst_n_i                 (rst_n_i),
      .soft_reset_i            (soft_reset_i),
      .resource_reset_i        (resource_reset_i),
      .counter_clear_i         (counter_clear_i),
      .abort_i                 (abort_i),
      .launch_i                (seq_launch),
      .launch_entry_i          (2'd0),
      .image_valid_i           (mc_status[`APB4_APU__MC_STATUS_VALID]),
      .timeout_i               (seq_timeout),
      .entry_pc_i              (entry_pc),
      .entry_first_i           (entry_first),
      .entry_last_i            (entry_last),
      .entry_max_loop_i        (entry_max_loop),
      .entry_max_retired_i     (entry_max_retired),
      .input_exhausted_i       (1'b1),
      .input_ready_i           (1'b0),
      .output_ready_i          (1'b1),
      .kernel_done_i           (1'b0),
      .transport_idle_success_i(1'b1),
      .dma_idle_success_i      (1'b1),
      .tx_idle_i               (1'b1),
      .ring_writeback_idle_i   (1'b1),
      .stall_i                 (seq_stall),
      .cause_valid_i           (1'b0),
      .cause_code_i            (6'd0),
      .cause_stage_i           (4'd0),
      .cause_resp_i            (2'd0),
      .cause_index_i           (8'd0),
      .cause_addr_i            (32'd0),
      .cause_detail_i          (32'd0),
      .transport_req_valid_o   (),
      .transport_req_ready_i   (1'b0),
      .transport_opcode_o      (),
      .transport_dst_o         (),
      .transport_aux_o         (),
      .transport_event_o       (),
      .transport_source0_o     (),
      .transport_source1_o     (),
      .transport_result_valid_i(1'b0),
      .transport_result_dst_i  (4'd0),
      .transport_result_data_i (32'd0),
      .fetch_o                 (seq_fetch),
      .fetch_addr_o            (seq_fetch_addr),
      .fetch_data_i            (seq_fetch_data),
      .fetch_valid_i           (seq_fetch_valid),
      .stat_o                  (seq_status),
      .retired_o               (seq_retired),
      .gpr_o                   (seq_gpr),
      .trapped_o               (seq_trapped),
      .trap_event_o            (seq_trap_event),
      .end_event_o             (),
      .abort_done_o            (seq_abort_done),
      .fault_valid_o           (seq_fault_valid),
      .fault_code_o            (seq_fault_code),
      .fault_stage_o           (seq_fault_stage),
      .fault_resp_o            (seq_fault_resp),
      .fault_index_o           (seq_fault_index),
      .fault_addr_o            (seq_fault_addr),
      .fault_detail_o          (seq_fault_detail),
      .perf_retired_o          (seq_perf_retired),
      .launch_epoch_o          (),
      .idle_o                  (seq_idle)
  );

  task automatic hard_reset;
    begin
      rst_n_i = 1'b0;
      repeat (3) @(posedge clk_i);
      rst_n_i = 1'b1;
      repeat (2) @(posedge clk_i);
    end
  endtask

  task automatic start_load;
    begin
      @(negedge clk_i);
      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
    end
  endtask

  task automatic wait_loader_idle;
    begin
      for (int unsigned cycle = 0; cycle < 10000; cycle++) begin
        @(posedge clk_i);
        if (mc_idle) return;
      end
      $display("loader state=%0d entry=%0d pc=%0d paths=%0d stop=%0d/%0d", u_loader.s_state_q,
               u_loader.s_scan_entry_q, u_loader.s_scan_pc_q, u_loader.s_path_stack_count_q,
               u_loader.s_path_stop_valid_q, u_loader.s_path_stop_pc_q);
      $fatal(1, "APU-P3 loader did not become idle");
    end
  endtask

  initial begin
    if (!$value$plusargs("IMAGE=%s", image_path)) $fatal(1, "IMAGE plusarg missing");
    if (!$value$plusargs("INVALID_CF_IMAGE=%s", invalid_cf_image_path)) begin
      $fatal(1, "INVALID_CF_IMAGE plusarg missing");
    end
    if (!$value$plusargs("INVALID_LOOP_IMAGE=%s", invalid_loop_image_path)) begin
      $fatal(1, "INVALID_LOOP_IMAGE plusarg missing");
    end
    if (!$value$plusargs("DIAGNOSTIC_IMAGE=%s", diagnostic_image_path)) begin
      $fatal(1, "DIAGNOSTIC_IMAGE plusarg missing");
    end
    if (!$value$plusargs("LEXICAL_PATH_IMAGE=%s", lexical_path_image_path)) begin
      $fatal(1, "LEXICAL_PATH_IMAGE plusarg missing");
    end
    if (!$value$plusargs("DEEP_PATH_IMAGE=%s", deep_path_image_path)) begin
      $fatal(1, "DEEP_PATH_IMAGE plusarg missing");
    end
    $readmemh(image_path, image);
    start_i          = 1'b0;
    abort_i          = 1'b0;
    resource_reset_i = 1'b0;
    soft_reset_i     = 1'b0;
    counter_clear_i  = 1'b0;
    dma_error        = 1'b0;
    seq_launch       = 1'b0;
    seq_stall        = 1'b0;
    seq_timeout      = 32'd16;
    image_addr_i     = 32'h3000_0000;
    image_size_i     = image[2];
    expected_crc_i   = image[11];

    hard_reset();
    start_load();
    wait_loader_idle();
    if ((mc_status != 8'h02) || !mc_lock || (mc_abi != 32'h0001_0000) ||
        (mc_actual_crc != image[11]) || (mc_load_count != 32'd1) ||
        (mc_build_id != 64'h1122_3344_5566_7788)) begin
      $display("status=%h lock=%0d abi=%h crc=%h expected=%h count=%h build=%h fault=%0d/%0d/%h/%h",
               mc_status, mc_lock, mc_abi, mc_actual_crc, image[11], mc_load_count, mc_build_id,
               mc_fault_code, mc_fault_stage, mc_fault_addr, mc_fault_detail);
      $fatal(1, "APU-P3 successful publication state mismatch");
    end
    if ((dma_request_count_q != 4'd3) || (store_write_count_q == 12'd0)) begin
      $fatal(1, "APU-P3 staged header/descriptor/payload transfer mismatch");
    end
    saved_word = u_store.mem[0][31:0];
    @(negedge clk_i);
    soft_reset_i = 1'b1;
    @(negedge clk_i);
    soft_reset_i = 1'b0;
    @(posedge clk_i);
    if (!mc_lock || (mc_status != 8'h02) || (mc_abi != 32'h0001_0000) ||
        (u_store.mem[0][31:0] != saved_word)) begin
      $fatal(1, "APU-P3 idle soft reset did not preserve the published image");
    end
    @(negedge clk_i);
    seq_launch = 1'b1;
    @(negedge clk_i);
    seq_launch = 1'b0;
    wait (seq_idle);
    @(posedge clk_i);
    if (seq_trapped || (seq_retired != 32'd36) || (seq_gpr[2] != 32'd9) ||
        (seq_gpr[3] != 32'ha5) || (seq_gpr[4] != 32'hffff_fff8) ||
        (seq_gpr[5] != 32'hffff_fff8) || (seq_gpr[6] != 32'h66) ||
        (seq_gpr[8] != 32'd10) || (seq_gpr[9] != 32'd2) ||
        (seq_gpr[10] != 32'hffff_fff8) || (seq_gpr[11] != 32'd5) ||
        (seq_gpr[12] != 32'd7) || (seq_gpr[13] != 32'd9) ||
        (seq_gpr[14] != 32'd11) || (seq_gpr[15] != 32'd5) ||
        (seq_status[18:15] != 4'd1)) begin
      $display("seq trapped=%0d retired=%0d r0=%h r1=%h r2=%h r3=%h status=%h", seq_trapped,
               seq_retired, seq_gpr[0], seq_gpr[1], seq_gpr[2], seq_gpr[3], seq_status);
      $fatal(1, "APU-P3 sequencer execution or END retention mismatch");
    end

    @(negedge clk_i);
    seq_launch = 1'b1;
    @(negedge clk_i);
    seq_launch = 1'b0;
    wait (u_sequencer.s_state_q == 2'd2);
    @(negedge clk_i);
    abort_i = 1'b1;
    @(posedge clk_i);
    #1;
    abort_i = 1'b0;
    if (!seq_abort_done || seq_trapped || (seq_retired != 32'd0) ||
        (seq_status[10:0] != 11'd0)) begin
      $fatal(1, "APU-P3 sequencer abort retention mismatch");
    end

    saved_word     = u_store.mem[0][31:0];
    u_store.mem[0] = 64'h0200_0000_dead_beef;
    @(negedge clk_i);
    seq_launch = 1'b1;
    @(negedge clk_i);
    seq_launch = 1'b0;
    wait (u_sequencer.s_state_q == 2'd3);
    @(negedge clk_i);
    abort_i = 1'b1;
    @(posedge clk_i);
    #1;
    if (!seq_trapped || seq_abort_done || !seq_trap_event ||
        (seq_fault_detail != 32'hdead_beef) || (seq_retired != 32'd0)) begin
      $fatal(1, "APU-P3 explicit trap did not outrank simultaneous abort");
    end
    @(negedge clk_i);
    abort_i        = 1'b0;
    u_store.mem[0] = {32'h1100_0000, saved_word};

    u_store.mem[0] = 64'h0300_0000_0000_07ff;
    @(negedge clk_i);
    seq_launch = 1'b1;
    @(negedge clk_i);
    seq_launch = 1'b0;
    wait (seq_trap_event);
    #1;
    if (!seq_trapped || (seq_fault_detail[7:0] != 8'd2) || (seq_retired != 32'd0)) begin
      $fatal(1, "APU-P3 branch-overflow trap mismatch");
    end

    u_store.mem[0] = 64'd0;
    seq_timeout    = 32'd1;
    @(negedge clk_i);
    seq_launch = 1'b1;
    abort_i    = 1'b1;
    @(negedge clk_i);
    seq_launch = 1'b0;
    wait (seq_trap_event);
    #1;
    abort_i = 1'b0;
    if (!seq_trapped || seq_abort_done || (seq_fault_detail[7:0] != 8'd7) ||
        (seq_retired != 32'd0) || (seq_status[18:11] != 8'd0)) begin
      $fatal(1, "APU-P3 timeout-one fetch watchdog or precedence mismatch");
    end

    seq_timeout = 32'd16;
    @(negedge clk_i);
    seq_launch = 1'b1;
    @(negedge clk_i);
    seq_launch = 1'b0;
    wait (u_sequencer.s_state_q == 2'd3);
    seq_stall = 1'b1;
    wait (seq_trap_event);
    #1;
    seq_stall = 1'b0;
    if (!seq_trapped || (seq_fault_detail[7:0] != 8'd7) || (seq_retired != 32'd0)) begin
      $fatal(1, "APU-P3 watchdog trap mismatch");
    end
    u_store.mem[0] = 64'h1100_0000_0000_0005;

    hard_reset();
    $readmemh(invalid_cf_image_path, image);
    image_size_i   = image[2];
    expected_crc_i = image[11];
    start_load();
    wait_loader_idle();
    if ((mc_status != 8'h10) || mc_lock || (mc_fault_code != 6'd9) ||
        (mc_fault_detail[7:0] != 8'd3) || (mc_fault_addr != image_addr_i + 32'd208)) begin
      $fatal(1, "APU-P3 path-sensitive empty-return proof mismatch");
    end

    hard_reset();
    $readmemh(invalid_loop_image_path, image);
    image_size_i   = image[2];
    expected_crc_i = image[11];
    start_load();
    wait_loader_idle();
    if ((mc_status != 8'h10) || mc_lock || (mc_fault_code != 6'd9) ||
        (mc_fault_detail[7:0] != 8'd4) || (mc_fault_addr != image_addr_i + 32'd216)) begin
      $fatal(1, "APU-P3 path-sensitive skipped-loop-setup proof mismatch");
    end

    hard_reset();
    $readmemh(diagnostic_image_path, image);
    image_size_i   = image[2];
    expected_crc_i = image[11];
    start_load();
    wait_loader_idle();
    if ((mc_status != 8'h10) || mc_lock || (mc_fault_code != 6'd9) ||
        (mc_fault_detail[7:0] != 8'd3) || (mc_fault_detail[18:8] != 11'd1) ||
        (mc_fault_addr != image_addr_i + 32'd200)) begin
      $fatal(1, "APU-P3 path diagnostic did not select the lowest-PC failure");
    end

    hard_reset();
    $readmemh(lexical_path_image_path, image);
    image_size_i   = image[2];
    expected_crc_i = image[11];
    start_load();
    wait_loader_idle();
    if ((mc_status != 8'h10) || mc_lock || (mc_fault_code != 6'd9) ||
        (mc_fault_detail[7:0] != 8'd3) || (mc_fault_detail[18:8] != 11'd2) ||
        (mc_fault_addr != image_addr_i + 32'd208)) begin
      $fatal(1, "APU-P3 lexical/path diagnostic order mismatch");
    end

    hard_reset();
    $readmemh(deep_path_image_path, image);
    image_size_i   = image[2];
    expected_crc_i = image[11];
    start_load();
    wait_loader_idle();
    if ((mc_status != 8'h02) || !mc_lock || (mc_fault_code != 6'd0)) begin
      $fatal(1, "APU-P3 valid deep conditional path proof was rejected");
    end

    hard_reset();
    $readmemh(image_path, image);
    image_size_i   = image[2];
    expected_crc_i = image[11];
    start_load();
    wait_loader_idle();
    if ((mc_status != 8'h02) || !mc_lock || (mc_load_count != 32'd1)) begin
      $fatal(1, "APU-P3 valid reload after proof rejection failed");
    end

    @(negedge clk_i);
    counter_clear_i = 1'b1;
    @(negedge clk_i);
    counter_clear_i = 1'b0;
    @(posedge clk_i);
    if ((mc_load_count != 32'd0) || !mc_lock || (mc_status != 8'h02)) begin
      $display("counter clear count=%h lock=%0d status=%h", mc_load_count, mc_lock, mc_status);
      $fatal(1, "APU-P3 counter clear did not preserve the published image");
    end
    hard_reset();
    saved_word = image[0];
    image[0]   = 32'd0;
    start_load();
    wait_loader_idle();
    if ((mc_status != 8'h04) || (mc_fault_code != 6'd9) || (mc_fault_addr != image_addr_i))
      $fatal(1, "APU-P3 header diagnostic mismatch");
    if ((dma_request_count_q != 4'd1) || (store_write_count_q != 12'd0)) begin
      $fatal(1, "APU-P3 invalid header reached payload/control store");
    end
    image[0] = saved_word;

    hard_reset();
    saved_word = image[21];
    image[21]  = 32'd0;
    start_load();
    wait_loader_idle();
    if ((mc_status != 8'h08) || (mc_fault_code != 6'd9) || (mc_actual_crc != 32'd0) ||
        (mc_fault_addr != image_addr_i + 32'd84))
      $fatal(1, "APU-P3 range diagnostic mismatch");
    if (store_write_count_q != 12'd0) begin
      $fatal(1, "APU-P3 invalid descriptor mutated the control store");
    end
    image[21] = saved_word;

    hard_reset();
    saved_word = image[5];
    image[5]   = image[2] + 32'd4;
    start_load();
    wait_loader_idle();
    if ((mc_status != 8'h08) || (mc_fault_code != 6'd9) || (mc_actual_crc != 32'd0) ||
        (mc_fault_addr != image_addr_i + 32'd20) || (store_write_count_q != 12'd0)) begin
      $fatal(1, "APU-P3 zero-byte table offset did not fail as an early range error");
    end
    image[5] = saved_word;

    hard_reset();
    saved_word = image[49];
    image[49]  = image[49] | 32'h0000_1000;
    start_load();
    wait_loader_idle();
    if ((mc_status != 8'h10) || (mc_fault_code != 6'd9) || (mc_actual_crc == 32'd0))
      $fatal(1, "APU-P3 control diagnostic mismatch");
    image[49] = saved_word;

    hard_reset();
    saved_word = image[5];
    image[5]   = 32'h0000_0040;
    start_load();
    wait_loader_idle();
    if ((mc_status != 8'h20) || (mc_actual_crc == 32'd0)) begin
      $fatal(1, "APU-P3 table error precedence mismatch");
    end
    image[5] = saved_word;

    hard_reset();
    saved_word = image[49];
    image[49]  = (image[49] & 32'h0fff_ffff) | 32'h2000_0000;
    start_load();
    wait_loader_idle();
    if ((mc_status != 8'h80) || (mc_fault_code != 6'd10)) begin
      $fatal(1, "APU-P3 capability diagnostic mismatch");
    end
    image[49] = saved_word;

    hard_reset();
    expected_crc_i = image[11] ^ 32'd1;
    start_load();
    wait_loader_idle();
    if ((mc_status != 8'h40) || (mc_fault_detail != mc_actual_crc)) begin
      $fatal(1, "APU-P3 CRC diagnostic mismatch");
    end
    expected_crc_i = image[11];

    hard_reset();
    start_load();
    wait (u_loader.s_state_q == 5'd14);
    @(negedge clk_i);
    abort_i = 1'b1;
    @(posedge clk_i);
    #1;
    abort_i = 1'b0;
    if (!mc_idle || !mc_abort_done || mc_lock || (mc_status != 8'd0)) begin
      $fatal(1, "APU-P3 path-stack pop abort mismatch");
    end

    hard_reset();
    start_load();
    wait (u_loader.s_state_q == 5'd14);
    @(negedge clk_i);
    resource_reset_i = 1'b1;
    @(posedge clk_i);
    #1;
    resource_reset_i = 1'b0;
    if (!mc_idle || mc_lock || (mc_status != 8'd0) || (mc_fault_code != 6'd21)) begin
      $fatal(1, "APU-P3 path-stack pop resource-reset mismatch");
    end

    hard_reset();
    start_load();
    repeat (8) @(posedge clk_i);
    dma_error = 1'b1;
    @(posedge clk_i);
    dma_error = 1'b0;
    wait_loader_idle();
    if ((mc_status != 8'd0) || (mc_actual_crc != 32'd0) ||
        (mc_fault_code != 6'd15) || (mc_fault_resp != 2'd2)) begin
      $fatal(1, "APU-P3 AXI failure diagnostic mismatch");
    end

    hard_reset();
    start_load();
    repeat (8) @(posedge clk_i);
    abort_i = 1'b1;
    @(posedge clk_i);
    abort_i = 1'b0;
    wait_loader_idle();
    if (mc_lock || (mc_status != 8'd0) || !mc_abort_done) begin
      $fatal(1, "APU-P3 abort did not cancel publication");
    end

    hard_reset();
    start_load();
    repeat (8) @(posedge clk_i);
    resource_reset_i = 1'b1;
    @(posedge clk_i);
    resource_reset_i = 1'b0;
    wait_loader_idle();
    if (mc_lock || (mc_status != 8'd0) || (mc_fault_code != 6'd21)) begin
      $fatal(1, "APU-P3 resource reset did not cancel publication");
    end

    $display("APU-P3 loader, control store, and sequencer tests passed");
    $finish;
  end

  initial begin
    repeat (20000) @(posedge clk_i);
    $fatal(1, "APU-P3 focused test timed out");
  end

  logic s_unused;
  assign s_unused = ^dma_request_addr ^ ^dma_request_bytes ^ mc_load_done ^ mc_fault_valid ^
      ^mc_fault_stage ^ ^mc_fault_resp ^ ^mc_fault_detail ^ seq_trap_event ^ seq_abort_done ^
      seq_fault_valid ^ ^seq_fault_code ^ ^seq_fault_stage ^ ^seq_fault_resp ^
      ^seq_fault_index ^ ^seq_fault_addr ^ ^seq_fault_detail ^ ^seq_perf_retired;
endmodule
