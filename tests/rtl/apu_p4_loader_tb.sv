// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_p4_loader_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  logic start_i, abort_i, resource_reset_i, soft_reset_i, counter_clear_i;
  logic [31:0] image_addr_i, image_size_i, expected_crc_i;
  logic dma_request_valid, dma_request_ready, dma_ready, dma_done;
  logic [31:0] dma_request_addr, dma_request_bytes, dma_data;
  logic [3:0] dma_keep;
  logic dma_last, dma_valid;
  logic store_active, store_read, store_write, store_valid;
  logic [10:0] store_addr, fetch_addr;
  logic [63:0] store_write_data, store_read_data, fetch_data;
  logic fetch, fetch_valid;
  logic        local_write;
  logic [16:0] local_addr;
  logic [31:0] local_data, local_read_data;
  logic [3:0] local_strb;
  logic local_read_req, local_read_valid, local_read_error;
  logic [15:0] table_bytes;
  logic [ 7:0] status;
  logic [31:0] abi, actual_crc, load_count;
  logic [63:0] build_id;
  logic lock, load_done, abort_done, fault_valid, loader_idle;
  logic [5:0] fault_code;
  logic [3:0] fault_stage;
  logic [1:0] fault_resp;
  logic [31:0] fault_addr, fault_detail;
  logic [2:0][10:0] entry_pc, entry_first, entry_last;
  logic [2:0][15:0] entry_max_loop;
  logic [2:0][23:0] entry_max_retired;
  logic [2:0][16:0] entry_scratch_base, entry_scratch_bytes;
  logic [2:0][31:0] entry_primitive_mask;
  logic [2:0][15:0] entry_table_offset, entry_table_bytes;
  logic [31:0] image             [0:4095];
  logic        transfer_active_q;
  logic [11:0] transfer_word_q, transfer_beat_q;
  logic [31:0] transfer_bytes_q;
  logic [ 3:0] request_count_q;
  logic [11:0] store_write_count_q, table_write_count_q;
  string image_path, invalid_image_path;

  always #5 clk_i = ~clk_i;

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
      request_count_q     <= 4'd0;
      store_write_count_q <= 12'd0;
      table_write_count_q <= 12'd0;
      dma_done            <= 1'b0;
    end else begin
      dma_done <= 1'b0;
      if (dma_request_valid && dma_request_ready) begin
        transfer_active_q <= 1'b1;
        transfer_word_q   <= 12'((dma_request_addr - image_addr_i) >> 2);
        transfer_beat_q   <= 12'd0;
        transfer_bytes_q  <= dma_request_bytes;
        request_count_q   <= request_count_q + 1'b1;
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
      if (store_write) begin
        if (request_count_q < 4'd3) $fatal(1, "P4 store write preceded range admission");
        store_write_count_q <= store_write_count_q + 1'b1;
      end
      if (local_write) begin
        if (request_count_q < 4'd3) $fatal(1, "P4 table write preceded range admission");
        if (local_addr >= table_bytes) $fatal(1, "P4 loader wrote outside table payload");
        table_write_count_q <= table_write_count_q + 1'b1;
      end
    end
  end

  apu_microcode_loader #(
      .EnableP4(1'b1)
  ) u_loader (
      .clk_i                 (clk_i),
      .rst_n_i               (rst_n_i),
      .start_i               (start_i),
      .abort_i               (abort_i),
      .resource_reset_i      (resource_reset_i),
      .soft_reset_i          (soft_reset_i),
      .counter_clear_i       (counter_clear_i),
      .image_addr_i          (image_addr_i),
      .image_size_i          (image_size_i),
      .expected_crc_i        (expected_crc_i),
      .dma_request_valid_o   (dma_request_valid),
      .dma_request_ready_i   (dma_request_ready),
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
      .local_write_o         (local_write),
      .local_addr_o          (local_addr),
      .local_data_o          (local_data),
      .local_strb_o          (local_strb),
      .table_bytes_o         (table_bytes),
      .stat_o                (status),
      .abi_o                 (abi),
      .build_id_o            (build_id),
      .lock_o                (lock),
      .actual_crc_o          (actual_crc),
      .load_count_o          (load_count),
      .entry_pc_o            (entry_pc),
      .entry_first_o         (entry_first),
      .entry_last_o          (entry_last),
      .entry_max_loop_o      (entry_max_loop),
      .entry_max_retired_o   (entry_max_retired),
      .entry_scratch_base_o  (entry_scratch_base),
      .entry_scratch_bytes_o (entry_scratch_bytes),
      .entry_primitive_mask_o(entry_primitive_mask),
      .entry_table_offset_o  (entry_table_offset),
      .entry_table_bytes_o   (entry_table_bytes),
      .load_done_o           (load_done),
      .abort_done_o          (abort_done),
      .fault_valid_o         (fault_valid),
      .fault_code_o          (fault_code),
      .fault_stage_o         (fault_stage),
      .fault_resp_o          (fault_resp),
      .fault_addr_o          (fault_addr),
      .fault_detail_o        (fault_detail),
      .idle_o                (loader_idle)
  );

  apu_control_store u_control_store (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .loader_active_i(store_active),
      .loader_read_i  (store_read),
      .loader_write_i (store_write),
      .loader_addr_i  (store_addr),
      .loader_data_i  (store_write_data),
      .loader_data_o  (store_read_data),
      .loader_valid_o (store_valid),
      .image_valid_i  (status[`APB4_APU__MC_STATUS_VALID]),
      .fetch_i        (fetch),
      .fetch_addr_i   (fetch_addr),
      .fetch_data_o   (fetch_data),
      .fetch_valid_o  (fetch_valid)
  );

  apu_local_sram u_local_sram (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .image_valid_i     (status[`APB4_APU__MC_STATUS_VALID]),
      .table_bytes_i     (table_bytes),
      .epoch_clear_i     (1'b0),
      .loader_active_i   (!loader_idle),
      .loader_req_i      (local_write),
      .loader_addr_i     (local_addr),
      .loader_data_i     (local_data),
      .loader_strb_i     (local_strb),
      .loader_ready_o    (),
      .codec_req_i       (local_read_req),
      .codec_write_i     (1'b0),
      .codec_addr_i      (17'd0),
      .codec_data_i      (32'd0),
      .codec_strb_i      (4'd0),
      .codec_ready_o     (),
      .codec_data_o      (local_read_data),
      .codec_valid_o     (local_read_valid),
      .codec_access_err_o(local_read_error)
  );

  task automatic hard_reset;
    begin
      rst_n_i = 1'b0;
      repeat (3) @(posedge clk_i);
      rst_n_i = 1'b1;
      repeat (2) @(posedge clk_i);
    end
  endtask

  initial begin
    if (!$value$plusargs("IMAGE=%s", image_path)) $fatal(1, "IMAGE plusarg missing");
    if (!$value$plusargs("INVALID_IMAGE=%s", invalid_image_path)) begin
      $fatal(1, "INVALID_IMAGE plusarg missing");
    end
    $readmemh(image_path, image);
    start_i          = 1'b0;
    abort_i          = 1'b0;
    resource_reset_i = 1'b0;
    soft_reset_i     = 1'b0;
    counter_clear_i  = 1'b0;
    image_addr_i     = 32'h2000_0000;
    image_size_i     = image[2];
    expected_crc_i   = image[11];
    fetch            = 1'b0;
    fetch_addr       = 11'd0;
    local_read_req   = 1'b0;
    hard_reset();

    @(negedge clk_i);
    start_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b0;
    for (int cycle = 0; cycle < 30000; cycle++) begin
      @(posedge clk_i);
      if (loader_idle && status[`APB4_APU__MC_STATUS_VALID]) break;
      if (fault_valid) $fatal(1, "P4 loader fault code=%0d detail=%08x", fault_code, fault_detail);
      if (cycle == 29999) $fatal(1, "P4 loader timed out");
    end
    if (!lock || !load_done || (abi != 32'h0001_0000) || (table_bytes != 16'd4) ||
        (store_write_count_q != 12'd2) || (table_write_count_q != 12'd1)) begin
      $fatal(1, "P4 loader publication mismatch");
    end
    if ((entry_scratch_base[0] != 17'h01000) || (entry_scratch_bytes[0] != 17'h01000) ||
        (entry_primitive_mask[0] != 32'h0000_0040) ||
        (entry_table_bytes[0] != 16'd4)) begin
      $fatal(1, "P4 descriptor publication mismatch");
    end

    @(negedge clk_i);
    fetch = 1'b1;
    @(negedge clk_i);
    fetch = 1'b0;
    if (!fetch_valid || (fetch_data != 64'h0800_0001_0000_0000)) begin
      $fatal(1, "P4 control-store publication mismatch");
    end
    @(negedge clk_i);
    local_read_req = 1'b1;
    @(negedge clk_i);
    local_read_req = 1'b0;
    if (!local_read_valid || local_read_error || (local_read_data != 32'h0001_0001)) begin
      $fatal(1, "P4 table publication mismatch");
    end

    @(negedge clk_i);
    soft_reset_i = 1'b1;
    @(negedge clk_i);
    soft_reset_i = 1'b0;
    @(posedge clk_i);
    if (!status[`APB4_APU__MC_STATUS_VALID] || !lock || (table_bytes != 16'd4)) begin
      $fatal(1, "P4 soft reset did not retain the locked image");
    end

    hard_reset();
    $readmemh(invalid_image_path, image);
    image_size_i   = image[2];
    expected_crc_i = image[11];
    @(negedge clk_i);
    start_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b0;
    for (int cycle = 0; cycle < 1000; cycle++) begin
      @(posedge clk_i);
      if (fault_valid) begin
        if ((fault_code != `APB4_APU__ERROR_CODE_MICROCODE) ||
            (fault_stage != `APB4_APU__ERROR_STAGE_LOADER) ||
            (fault_addr != image_addr_i + 32'd92) || (fault_detail != 32'h0000_0008)) begin
          $fatal(1, "P4 zero-byte table diagnostic mismatch");
        end
        break;
      end
      if (cycle == 999) $fatal(1, "P4 invalid-table load timed out");
    end
    if (status[`APB4_APU__MC_STATUS_VALID] || lock || !status[5] ||
        (store_write_count_q != 12'd0) || (table_write_count_q != 12'd0)) begin
      $fatal(1, "P4 invalid descriptor mutated unpublished stores");
    end
    $display("APU_P4_LOADER_PASS");
    $finish;
  end

  logic s_unused;
  assign s_unused = abort_done ^ ^actual_crc ^ ^load_count ^ ^build_id ^ ^entry_pc ^
      ^entry_first ^ ^entry_last ^ ^entry_max_loop ^ ^entry_max_retired ^
      ^entry_table_offset ^ fault_stage[0] ^ fault_resp[0] ^ fault_addr[0];
endmodule
