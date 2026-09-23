// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`timescale 1ns / 1ps

// APU-P7 KWS end-to-end accuracy qualification fixture. Each window is a
// plusarg-selected 32000-byte padded PCM image driven through operation 1
// (one KWS memory window) on the real frontend/inference RTL path with the
// frozen APUM model resident in the KWS SRAM model reservation. Classifier
// history and counters are reset at every idle boundary between windows.
// The fixture fails closed on any DMA protocol, error, or timeout condition.
module apu_p7_accuracy_tb;
  localparam int unsigned PcmWords = 8000;
  localparam int unsigned ModelWords = 8192;
  localparam logic [15:0] KwsConfig = 16'h0180;  // debounce=1, threshold=128
  localparam logic [31:0] InputConfig = 32'h0102_3e80;  // mono/16000/16 S16_LE
  localparam logic [31:0] MemoryBase = 32'h0001_0000;

  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        clear_history = 1'b0;
  logic        counter_clear = 1'b0;
  logic        memory_start = 1'b0;
  logic        memory_dma_request_ready = 1'b0;
  logic [31:0] memory_dma_data = 32'd0;
  logic [ 3:0] memory_dma_keep = 4'd0;
  logic        memory_dma_last = 1'b0;
  logic        memory_dma_valid = 1'b0;
  logic        memory_dma_done = 1'b0;
  logic [31:0] status_o, result_o, frame_count_o, inference_count_o, hit_count_o;
  logic [31:0] overrun_count_o, timestamp_lo_o, timestamp_hi_o;
  logic [31:0] model_status_o, model_actual_crc_o, memory_input_used_o;
  logic memory_start_ready_o;
  logic memory_dma_request_valid_o, memory_done_o, memory_error_o;
  logic [31:0] memory_dma_request_address_o, memory_dma_request_bytes_o;
  logic [5:0] memory_error_code_o;
  logic [3:0] memory_error_stage_o;
  logic [1:0] memory_error_resp_o;
  logic [31:0] memory_error_address_o, memory_error_detail_o;
  logic [10:0] irq_set_o;
  logic fault_valid_o, model_valid_o, model_lock_o, busy_o, idle_o, rx_ready_o;
  logic [5:0] fault_code_o;
  logic [3:0] fault_stage_o;
  logic [1:0] fault_resp_o;
  logic [7:0] fault_index_o;
  logic [31:0] fault_addr_o, fault_detail_o;
  logic [15:0][14:0] model_addr_o;
  logic [15:0][ 7:0] model_store_data;
  logic              scratch_clear;
  logic [19:0][15:0] scratch_read_addr;
  logic [19:0][31:0] scratch_read_data;
  logic [ 5:0]       scratch_write_valid;
  logic [ 5:0][15:0] scratch_write_addr;
  logic [ 5:0][31:0] scratch_write_data;
  logic [ 5:0][ 3:0] scratch_write_strb;
  logic              scratch_access_err;
  logic [31:0]       pcm_mem             [0:PcmWords-1];

  always #5 clk_i = ~clk_i;

  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) stream_i (
      clk_i,
      rst_n_i
  );
  assign stream_i.tvalid = 1'b0;
  assign stream_i.tdata  = 32'd0;
  assign stream_i.tkeep  = 4'hf;
  assign stream_i.tstrb  = 4'hf;
  assign stream_i.tlast  = 1'b0;
  assign stream_i.tid    = '0;
  assign stream_i.tdest  = '0;
  assign stream_i.tuser  = '0;
  assign stream_i.tready = rx_ready_o;

  apu_kws_sram_client u_kws_sram_client (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .req_i                (1'b0),
      .write_i              (1'b0),
      .addr_i               (17'd0),
      .data_i               (32'd0),
      .strb_i               (4'd0),
      .ready_o              (),
      .data_o               (),
      .valid_o              (),
      .access_err_o         (),
      .model_addr_i         (model_addr_o),
      .model_data_o         (model_store_data),
      .scratch_clear_i      (scratch_clear),
      .scratch_read_addr_i  (scratch_read_addr),
      .scratch_read_data_o  (scratch_read_data),
      .scratch_write_valid_i(scratch_write_valid),
      .scratch_write_addr_i (scratch_write_addr),
      .scratch_write_data_i (scratch_write_data),
      .scratch_write_strb_i (scratch_write_strb),
      .scratch_access_err_o (scratch_access_err)
  );

  apu_kws_engine dut (
      .clk_i                       (clk_i),
      .rst_n_i                     (rst_n_i),
      .soft_reset_i                (1'b0),
      .resource_reset_i            (1'b0),
      .counter_clear_i             (counter_clear),
      .xrun_clear_i                (1'b0),
      .abort_i                     (1'b0),
      .quiesce_i                   (1'b0),
      .disable_i                   (1'b0),
      .flush_busy_i                (1'b0),
      .enable_i                    (1'b1),
      .memory_window_i             (1'b1),
      .clear_history_i             (clear_history),
      .model_valid_i               (1'b1),
      .model_lock_i                (1'b1),
      .sequencer_timeout_i         (32'd0),
      .memory_start_i              (memory_start),
      .memory_start_ready_o        (memory_start_ready_o),
      .memory_address_i            (MemoryBase),
      .memory_dma_request_valid_o  (memory_dma_request_valid_o),
      .memory_dma_request_ready_i  (memory_dma_request_ready),
      .memory_dma_request_address_o(memory_dma_request_address_o),
      .memory_dma_request_bytes_o  (memory_dma_request_bytes_o),
      .memory_dma_data_i           (memory_dma_data),
      .memory_dma_keep_i           (memory_dma_keep),
      .memory_dma_last_i           (memory_dma_last),
      .memory_dma_valid_i          (memory_dma_valid),
      .memory_dma_ready_o          (memory_dma_ready_o),
      .memory_dma_done_i           (memory_dma_done),
      .memory_dma_error_i          (1'b0),
      .memory_dma_error_code_i     (6'd0),
      .memory_dma_error_stage_i    (4'd0),
      .memory_dma_error_resp_i     (2'd0),
      .memory_dma_error_address_i  (32'd0),
      .memory_done_o               (memory_done_o),
      .memory_error_o              (memory_error_o),
      .memory_error_code_o         (memory_error_code_o),
      .memory_error_stage_o        (memory_error_stage_o),
      .memory_error_resp_o         (memory_error_resp_o),
      .memory_error_address_o      (memory_error_address_o),
      .memory_error_detail_o       (memory_error_detail_o),
      .memory_input_used_o         (memory_input_used_o),
      .kws_config_i                (KwsConfig),
      .input_config_i              (InputConfig),
      .model_addr_o                (model_addr_o),
      .model_data_i                (model_store_data),
      .scratch_clear_o             (scratch_clear),
      .scratch_read_addr_o         (scratch_read_addr),
      .scratch_read_data_i         (scratch_read_data),
      .scratch_write_valid_o       (scratch_write_valid),
      .scratch_write_addr_o        (scratch_write_addr),
      .scratch_write_data_o        (scratch_write_data),
      .scratch_write_strb_o        (scratch_write_strb),
      .scratch_access_err_i        (scratch_access_err),
      .stream_i                    (stream_i),
      .rx_ready_o                  (rx_ready_o),
      .status_o                    (status_o),
      .result_o                    (result_o),
      .timestamp_lo_o              (timestamp_lo_o),
      .timestamp_hi_o              (timestamp_hi_o),
      .frame_count_o               (frame_count_o),
      .inference_count_o           (inference_count_o),
      .hit_count_o                 (hit_count_o),
      .overrun_count_o             (overrun_count_o),
      .model_status_o              (model_status_o),
      .model_actual_crc_o          (model_actual_crc_o),
      .irq_set_o                   (irq_set_o),
      .fault_valid_o               (fault_valid_o),
      .fault_code_o                (fault_code_o),
      .fault_stage_o               (fault_stage_o),
      .fault_resp_o                (fault_resp_o),
      .fault_index_o               (fault_index_o),
      .fault_addr_o                (fault_addr_o),
      .fault_detail_o              (fault_detail_o),
      .model_valid_o               (model_valid_o),
      .model_lock_o                (model_lock_o),
      .busy_o                      (busy_o),
      .idle_o                      (idle_o)
  );

  task automatic run_window(input int unsigned window_index, input string pcm_dir,
                            input int unsigned max_window_cycles);
    string       pcm_path;
    int unsigned word_index;
    int unsigned elapsed;
    begin
      pcm_path = $sformatf("%s/pcm_%06d.hex", pcm_dir, window_index);
      $readmemh(pcm_path, pcm_mem);
      @(negedge clk_i);
      clear_history = 1'b1;
      counter_clear = 1'b1;
      @(negedge clk_i);
      clear_history = 1'b0;
      counter_clear = 1'b0;
      @(negedge clk_i);
      if (!memory_start_ready_o) begin
        $fatal(1, "KWS memory window %0d was not accepted at the idle boundary", window_index);
      end
      memory_start = 1'b1;
      @(negedge clk_i);
      memory_start = 1'b0;
      elapsed      = 0;
      while (!memory_dma_request_valid_o) begin
        @(negedge clk_i);
        elapsed++;
        if (elapsed > 1000)
          $fatal(1, "KWS memory window %0d never raised its DMA request", window_index);
      end
      if ((memory_dma_request_address_o != MemoryBase) ||
          (memory_dma_request_bytes_o != 32'd32000)) begin
        $fatal(1, "KWS memory window %0d DMA request mismatch", window_index);
      end
      memory_dma_request_ready = 1'b1;
      @(negedge clk_i);
      memory_dma_request_ready = 1'b0;
      for (word_index = 0; word_index < PcmWords; word_index++) begin
        memory_dma_data  = pcm_mem[word_index];
        memory_dma_keep  = 4'hf;
        memory_dma_last  = word_index == PcmWords - 1;
        memory_dma_valid = 1'b1;
        do @(negedge clk_i); while (!memory_dma_ready_o);
      end
      memory_dma_valid = 1'b0;
      memory_dma_last  = 1'b0;
      memory_dma_done  = 1'b1;
      @(negedge clk_i);
      memory_dma_done = 1'b0;
      elapsed         = 0;
      while (!memory_done_o && (elapsed < max_window_cycles)) begin
        @(negedge clk_i);
        elapsed++;
      end
      if (!memory_done_o) begin
        $fatal(1, "KWS memory window %0d did not complete within %0d cycles", window_index,
               max_window_cycles);
      end
      if (memory_error_o) begin
        $fatal(1, "KWS memory window %0d error code=%0d stage=%0d address=%08x detail=%08x",
               window_index, memory_error_code_o, memory_error_stage_o, memory_error_address_o,
               memory_error_detail_o);
      end
      if (memory_input_used_o != 32'd32000) begin
        $fatal(1, "KWS memory window %0d consumed %0d input bytes", window_index,
               memory_input_used_o);
      end
      if ((frame_count_o != 32'd49) || (inference_count_o != 32'd1) || !status_o[7] ||
          fault_valid_o) begin
        $fatal(1,
               "KWS memory window %0d frames=%0d inferences=%0d status=%08x fault=%0b/%0d/%0d/%08x",
               window_index, frame_count_o, inference_count_o, status_o, fault_valid_o,
               fault_code_o, fault_stage_o, fault_detail_o);
      end
      $display("KWS_RESULT %0d %0d %0d %0d", window_index, result_o[7:0], result_o[15:8],
               result_o[16]);
    end
  endtask

  initial begin
    string       apum_hex;
    string       pcm_dir;
    int unsigned first_index;
    int unsigned window_count;
    int unsigned max_window_cycles;

    if (!$value$plusargs("APUM_HEX=%s", apum_hex)) $fatal(1, "missing +APUM_HEX=<path>");
    if (!$value$plusargs("PCM_DIR=%s", pcm_dir)) $fatal(1, "missing +PCM_DIR=<path>");
    if (!$value$plusargs("WINDOW_COUNT=%d", window_count)) begin
      $fatal(1, "missing +WINDOW_COUNT=<n>");
    end
    if (!$value$plusargs("FIRST_INDEX=%d", first_index)) first_index = 0;
    if (!$value$plusargs("MAX_WINDOW_CYCLES=%d", max_window_cycles)) begin
      max_window_cycles = 4000000;
    end
    if (window_count == 0) $fatal(1, "WINDOW_COUNT must be positive");

    repeat (4) @(negedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    if (!model_valid_o || !model_lock_o) $fatal(1, "KWS model admission was not observed");
    $readmemh(apum_hex, u_kws_sram_client.mem, 0, ModelWords - 1);

    for (int unsigned window = first_index; window < first_index + window_count; window++) begin
      run_window(window, pcm_dir, max_window_cycles);
    end
    $display("APU_P7_ACCURACY_COMPLETE windows=%0d first=%0d", window_count, first_index);
    $finish;
  end
endmodule
