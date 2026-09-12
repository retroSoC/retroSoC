`timescale 1ns / 1ps

module apu_kws_engine_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  logic enable_i = 1'b0;
  logic counter_clear_i = 1'b0;
  logic xrun_clear_i = 1'b0;
  logic disable_i = 1'b0;
  logic flush_busy_i = 1'b0;
  logic [31:0] status_o, result_o, frame_count_o, inference_count_o, hit_count_o, overrun_count_o;
  logic [31:0] timestamp_lo_o, timestamp_hi_o, model_status_o, model_actual_crc_o;
  logic memory_start_ready_o;
  logic memory_dma_request_valid_o, memory_dma_ready_o, memory_done_o, memory_error_o;
  logic [31:0] memory_input_used_o;
  logic        memory_window = 1'b0;
  logic        memory_start = 1'b0;
  logic        memory_dma_request_ready = 1'b0;
  logic [31:0] memory_dma_data = 32'd0;
  logic [ 3:0] memory_dma_keep = 4'd0;
  logic        memory_dma_last = 1'b0;
  logic        memory_dma_valid = 1'b0;
  logic        memory_dma_done = 1'b0;
  logic        memory_dma_error = 1'b0;
  logic [ 5:0] memory_dma_error_code = 6'd0;
  logic [ 3:0] memory_dma_error_stage = 4'd0;
  logic [ 1:0] memory_dma_error_resp = 2'd0;
  logic [31:0] memory_dma_error_address = 32'd0;
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
  logic [15:0][7:0] model_data_i, model_store_data;
  logic              scratch_clear;
  logic [19:0][15:0] scratch_read_addr;
  logic [19:0][31:0] scratch_read_data;
  logic [ 5:0]       scratch_write_valid;
  logic [ 5:0][15:0] scratch_write_addr;
  logic [ 5:0][31:0] scratch_write_data;
  logic [ 5:0][ 3:0] scratch_write_strb;
  logic              scratch_access_err;
  logic [ 7:0]       mfcc_bytes                [  0:489];
  logic [ 7:0]       expected_layers           [0:72087];
  logic              use_apum = 1'b0;
  logic              check_layers = 1'b0;
  logic [31:0]       sequencer_timeout = 32'd0;

  function automatic logic [7:0] synthetic_model_byte(input logic [14:0] address_i);
    begin
      synthetic_model_byte = 8'd0;
      if ((address_i >= 15'h7630) && (address_i < 15'h7660) && (address_i[1:0] == 2'd3)) begin
        synthetic_model_byte = 8'h40;
      end
      case (address_i)
        15'h7614: synthetic_model_byte = 8'he8;
        15'h7615: synthetic_model_byte = 8'h03;
        default: begin
        end
      endcase
    end
  endfunction

  function automatic logic [7:0] scratch_byte(input integer offset_i);
    scratch_byte = u_kws_sram_client.mem[8192+(offset_i/4)][8*(offset_i%4)+:8];
  endfunction

  task automatic check_layer(input integer layer_i);
    integer       base;
    integer       length;
    logic   [7:0] actual;
    begin
      if (layer_i < 9) begin
        base   = layer_i * 8000;
        length = 8000;
      end else if (layer_i == 9) begin
        base   = 72000;
        length = 64;
      end else begin
        base   = 72064;
        length = 12;
      end
      for (int element = 0; element < length; element++) begin
        if (layer_i == 10) begin
          actual = scratch_byte(`RETROSOC_APU_KWS__SCRATCH_LOGITS_BASE + element);
        end else if ((layer_i & 1) != 0) begin
          actual = scratch_byte(`RETROSOC_APU_KWS__SCRATCH_B_BASE + element);
        end else begin
          actual = scratch_byte(`RETROSOC_APU_KWS__SCRATCH_A_BASE + element);
        end
        if (actual != expected_layers[base+element]) begin
          $fatal(1, "KWS layer %0d element %0d mismatch actual=%02x expected=%02x", layer_i,
                 element, actual, expected_layers[base+element]);
        end
      end
    end
  endtask

  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) stream_i (
      clk_i,
      rst_n_i
  );
  always #5 clk_i = ~clk_i;
  assign stream_i.tvalid = enable_i;
  assign stream_i.tdata  = 32'd0;
  assign stream_i.tkeep  = 4'hf;
  assign stream_i.tstrb  = 4'hf;
  assign stream_i.tlast  = 1'b0;
  assign stream_i.tid    = '0;
  assign stream_i.tdest  = '0;
  assign stream_i.tuser  = '0;
  assign stream_i.tready = rx_ready_o;
  for (genvar lane = 0; lane < 16; lane++) begin : gen_model_data
    assign model_data_i[lane] = use_apum ? model_store_data[lane] : synthetic_model_byte(
        model_addr_o[lane]
    );
  end

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
      .counter_clear_i             (counter_clear_i),
      .xrun_clear_i                (xrun_clear_i),
      .abort_i                     (1'b0),
      .quiesce_i                   (1'b0),
      .disable_i                   (disable_i),
      .flush_busy_i                (flush_busy_i),
      .enable_i                    (enable_i),
      .memory_window_i             (memory_window),
      .clear_history_i             (1'b0),
      .model_valid_i               (1'b1),
      .model_lock_i                (1'b1),
      .sequencer_timeout_i         (sequencer_timeout),
      .kws_config_i                (16'h0380),
      .memory_start_i              (memory_start),
      .memory_start_ready_o        (memory_start_ready_o),
      .memory_address_i            (32'h0001_0000),
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
      .memory_dma_error_i          (memory_dma_error),
      .memory_dma_error_code_i     (memory_dma_error_code),
      .memory_dma_error_stage_i    (memory_dma_error_stage),
      .memory_dma_error_resp_i     (memory_dma_error_resp),
      .memory_dma_error_address_i  (memory_dma_error_address),
      .memory_done_o               (memory_done_o),
      .memory_error_o              (memory_error_o),
      .memory_error_code_o         (memory_error_code_o),
      .memory_error_stage_o        (memory_error_stage_o),
      .memory_error_resp_o         (memory_error_resp_o),
      .memory_error_address_o      (memory_error_address_o),
      .memory_error_detail_o       (memory_error_detail_o),
      .memory_input_used_o         (memory_input_used_o),
      .input_config_i              (32'h01043e80),
      .model_addr_o                (model_addr_o),
      .model_data_i                (model_data_i),
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

  initial begin
    integer accepted_samples;
    integer elapsed_cycles;
    string  apum_hex;
    string  mfcc_hex;
    string  layers_hex;
    integer observed_operator;

    repeat (2) @(negedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    if (!model_valid_o || !model_lock_o) $fatal(1, "KWS model admission was not observed");
    dut.s_frame_count_q     = 32'd11;
    dut.s_inference_count_q = 32'd12;
    dut.s_hit_count_q       = 32'd13;
    dut.s_overrun_count_q   = 32'd14;
    dut.s_epoch_samples_q   = 32'd1234;
    dut.s_result_q          = 32'h0001_5507;
    dut.s_result_valid_q    = 1'b1;
    counter_clear_i         = 1'b1;
    @(negedge clk_i);
    counter_clear_i = 1'b0;
    if ((frame_count_o != 32'd0) || (inference_count_o != 32'd0) ||
        (hit_count_o != 32'd0) || (overrun_count_o != 32'd0)) begin
      $fatal(1, "KWS counter clear did not clear all four counters");
    end
    if ((dut.s_epoch_samples_q != 32'd1234) || (result_o != 32'h0001_5507) ||
        !status_o[7] || !model_valid_o || !model_lock_o || scratch_clear) begin
      $fatal(1, "KWS counter clear disturbed model, history, result, or scratch state");
    end
    dut.s_overrun_sticky_q = 1'b1;
    xrun_clear_i           = 1'b1;
    @(negedge clk_i);
    xrun_clear_i = 1'b0;
    if (status_o[4]) $fatal(1, "KWS stream-xrun W1C did not clear sticky overrun");
    enable_i        = 1'b1;
    flush_busy_i    = 1'b1;
    xrun_clear_i    = 1'b1;
    counter_clear_i = 1'b1;
    @(negedge clk_i);
    enable_i        = 1'b0;
    flush_busy_i    = 1'b0;
    xrun_clear_i    = 1'b0;
    counter_clear_i = 1'b0;
    if (!status_o[4] || !irq_set_o[`APB4_APU__IRQ_STREAM_XRUN] || (overrun_count_o != 32'd0)) begin
      $fatal(1, "KWS hardware overrun did not win stream-xrun clear");
    end
    xrun_clear_i = 1'b1;
    @(negedge clk_i);
    xrun_clear_i = 1'b0;
    if (status_o[4]) $fatal(1, "KWS sticky overrun did not clear after hardware event");

    enable_i = 1'b1;
    @(negedge clk_i);
    if (!status_o[0] || !rx_ready_o) $fatal(1, "KWS listener did not enter continuous capture");
    for (int front_state = 1; front_state <= 8; front_state++) begin
      dut.s_front_state_q = front_state;
      disable_i           = 1'b1;
      #1;
      if (!busy_o || !status_o[1] || rx_ready_o) begin
        $fatal(1, "KWS disable did not drain frontend state %0d", front_state);
      end
      dut.s_front_state_q = 4'd0;
      disable_i           = 1'b0;
    end
    dut.s_infer_state_q = 4'd2;
    disable_i           = 1'b1;
    #1;
    if (!busy_o || !status_o[1] || rx_ready_o) begin
      $fatal(1, "KWS disable did not drain inference");
    end
    dut.s_infer_state_q   = 4'd0;
    disable_i             = 1'b0;
    dut.s_frame_pending_q = 1'b1;
    disable_i             = 1'b1;
    #1;
    if (!busy_o || !status_o[1]) begin
      $fatal(1, "KWS disable ignored pending frontend work");
    end
    dut.s_frame_pending_q  = 1'b0;
    disable_i              = 1'b0;
    dut.s_mem_dma_active_q = 1'b1;
    dut.s_mem_job_q        = 1'b1;
    disable_i              = 1'b1;
    #1;
    if (!busy_o || rx_ready_o) $fatal(1, "KWS disable did not drain memory DMA");
    dut.s_mem_dma_active_q = 1'b0;
    dut.s_mem_job_q        = 1'b0;
    #1;
    if (!idle_o) begin
      $fatal(
          1,
          "KWS disable did not become idle after drain front=%0d infer=%0d req=%0b dma=%0b job=%0b listen=%0b",
          dut.s_front_state_q, dut.s_infer_state_q, dut.s_mem_req_q, dut.s_mem_dma_active_q,
          dut.s_mem_job_q, dut.s_listening);
    end
    memory_window = 1'b1;
    #1;
    if (!memory_start_ready_o) begin
      $fatal(1, "KWS disable blocked an operation accepted before the drain boundary");
    end
    memory_start = 1'b1;
    @(negedge clk_i);
    memory_start = 1'b0;
    if (!memory_dma_request_valid_o || !busy_o) begin
      $fatal(1, "accepted KWS memory-window job was dropped during disable");
    end
    disable_i     = 1'b0;
    memory_window = 1'b0;
    enable_i      = 1'b0;

    rst_n_i       = 1'b0;
    repeat (2) @(negedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    if ($value$plusargs("APUM_HEX=%s", apum_hex) && $value$plusargs("MFCC_HEX=%s", mfcc_hex)) begin
      $readmemh(apum_hex, u_kws_sram_client.mem, 0, 8191);
      $readmemh(mfcc_hex, mfcc_bytes);
      if ($value$plusargs("LAYERS_HEX=%s", layers_hex)) begin
        $readmemh(layers_hex, expected_layers);
        check_layers = 1'b1;
      end
      use_apum = 1'b1;
      for (int feature = 0; feature < 490; feature++) begin
        u_kws_sram_client.mem[
            8192+((`RETROSOC_APU_KWS__SCRATCH_MFCC_BASE+feature)/4)
        ][8*((`RETROSOC_APU_KWS__SCRATCH_MFCC_BASE+feature)%4)+:8] = mfcc_bytes[feature];
      end
      dut.s_operator_q    = 4'd0;
      dut.s_output_q      = 14'd0;
      dut.s_infer_state_q = 4'd1;
      elapsed_cycles      = 0;
      observed_operator   = 0;
      while ((inference_count_o == 0) && (elapsed_cycles < 600000)) begin
        @(negedge clk_i);
        if (check_layers && (dut.s_operator_q != observed_operator)) begin
          check_layer(observed_operator);
          observed_operator = dut.s_operator_q;
        end
        elapsed_cycles++;
      end
      if ((inference_count_o != 1) || (result_o[7:0] != 8'd7)) begin
        $display(
            "golden inference=%0d result=%08x fault=%0b/%0d stage=%0d detail=%08x op=%0d output=%0d",
            inference_count_o, result_o, fault_valid_o, fault_code_o, fault_stage_o,
            fault_detail_o, dut.s_operator_q, dut.s_output_q);
        for (int class_index = 0; class_index < 12; class_index++) begin
          $display("class=%0d logits=%0d softmax=%0d", class_index, scratch_byte(
                   `RETROSOC_APU_KWS__SCRATCH_LOGITS_BASE + class_index), scratch_byte(
                   `RETROSOC_APU_KWS__SCRATCH_SOFTMAX_BASE + class_index));
        end
        $fatal(1, "frozen APUM inference did not classify the official Stop feature");
      end
      for (int class_index = 0; class_index < 12; class_index++) begin
        if (check_layers && (scratch_byte(
                `RETROSOC_APU_KWS__SCRATCH_SOFTMAX_BASE + class_index
            ) != expected_layers[72076+class_index])) begin
          $fatal(1, "frozen APUM inference Softmax byte mismatch");
        end
      end
      rst_n_i = 1'b0;
      repeat (2) @(negedge clk_i);
      use_apum = 1'b0;
      rst_n_i  = 1'b1;
      @(negedge clk_i);
    end

    memory_window = 1'b1;
    enable_i      = 1'b1;
    memory_start  = 1'b1;
    @(negedge clk_i);
    memory_start = 1'b0;
    wait (memory_dma_request_valid_o);
    if ((memory_dma_request_address_o != 32'h0001_0000) ||
        (memory_dma_request_bytes_o != 32'd32000)) begin
      $fatal(1, "KWS memory DMA request mismatch");
    end
    memory_dma_request_ready = 1'b1;
    @(negedge clk_i);
    memory_dma_request_ready = 1'b0;
    for (int word_index = 0; word_index < 8000; word_index++) begin
      memory_dma_data  = 32'd0;
      memory_dma_keep  = 4'hf;
      memory_dma_last  = word_index == 7999;
      memory_dma_valid = 1'b1;
      do @(negedge clk_i); while (!memory_dma_ready_o);
    end
    memory_dma_valid = 1'b0;
    memory_dma_last  = 1'b0;
    memory_dma_done  = 1'b1;
    @(negedge clk_i);
    memory_dma_done = 1'b0;
    elapsed_cycles  = 0;
    while (!memory_done_o && (elapsed_cycles < 3000000)) begin
      @(negedge clk_i);
      elapsed_cycles++;
    end
    if (!memory_done_o || memory_error_o || (frame_count_o != 32'd49) ||
        (inference_count_o != 32'd1) || (result_o[7:0] != 8'd5) ||
        (memory_input_used_o != 32'd32000)) begin
      $fatal(1, "bounded KWS memory job did not complete with a fresh result");
    end

    rst_n_i       = 1'b0;
    enable_i      = 1'b0;
    memory_window = 1'b0;
    repeat (2) @(negedge clk_i);
    rst_n_i       = 1'b1;
    enable_i      = 1'b1;
    memory_window = 1'b1;
    memory_start  = 1'b1;
    @(negedge clk_i);
    memory_start = 1'b0;
    wait (memory_dma_request_valid_o);
    memory_dma_request_ready = 1'b1;
    @(negedge clk_i);
    memory_dma_request_ready = 1'b0;
    memory_dma_error         = 1'b1;
    memory_dma_error_code    = `APB4_APU__ERROR_CODE_AXI_READ;
    memory_dma_error_stage   = `APB4_APU__ERROR_STAGE_DMA_READ;
    memory_dma_error_resp    = 2'd2;
    memory_dma_error_address = 32'h0001_2340;
    memory_dma_done          = 1'b1;
    @(negedge clk_i);
    memory_dma_done  = 1'b0;
    memory_dma_error = 1'b0;
    wait (memory_done_o);
    if (!memory_error_o || (memory_error_code_o != `APB4_APU__ERROR_CODE_AXI_READ) ||
        (memory_error_stage_o != `APB4_APU__ERROR_STAGE_DMA_READ) ||
        (memory_error_resp_o != 2'd2) || (memory_error_address_o != 32'h0001_2340) ||
        (memory_error_detail_o != 32'd0)) begin
      $fatal(1, "KWS memory DMA failure did not preserve its exact tuple");
    end

    rst_n_i       = 1'b0;
    enable_i      = 1'b0;
    memory_window = 1'b0;
    repeat (2) @(negedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    enable_i         = 1'b1;
    accepted_samples = 0;
    elapsed_cycles   = 0;
    while ((accepted_samples < 16000) && (elapsed_cycles < 2000000)) begin
      @(posedge clk_i);
      if (stream_i.tvalid && stream_i.tready) accepted_samples++;
      elapsed_cycles++;
    end
    if (accepted_samples != 16000) $fatal(1, "KWS did not consume exactly one diagnostic window");
    @(negedge clk_i);
    enable_i = 1'b0;
    while ((inference_count_o == 0) && (elapsed_cycles < 3000000)) begin
      @(negedge clk_i);
      elapsed_cycles++;
    end
    if (frame_count_o != 49 || inference_count_o != 1 || !status_o[7]) begin
      $display(
          "accepted=%0d elapsed=%0d frames=%0d inferences=%0d status=%08x fault=%0b/%0d stage=%0d detail=%08x front=%0d infer=%0d op=%0d output=%0d term=%0d",
          accepted_samples, elapsed_cycles, frame_count_o, inference_count_o, status_o,
          fault_valid_o, fault_code_o, fault_stage_o, fault_detail_o, dut.s_front_state_q,
          dut.s_infer_state_q, dut.s_operator_q, dut.s_output_q, dut.s_term_q);
      $fatal(1, "KWS continuous window did not complete");
    end
    if (result_o[7:0] != 8'd5) $fatal(1, "KWS result did not depend on model SRAM data");

    rst_n_i  = 1'b0;
    enable_i = 1'b0;
    repeat (2) @(negedge clk_i);
    sequencer_timeout = 32'd3;
    rst_n_i           = 1'b1;
    @(negedge clk_i);
    enable_i       = 1'b1;
    elapsed_cycles = 0;
    while (!fault_valid_o && (elapsed_cycles < 2000)) begin
      @(negedge clk_i);
      elapsed_cycles++;
    end
    if (!fault_valid_o || (fault_code_o != 6'd14) || (fault_stage_o != 4'd9)) begin
      $fatal(1, "KWS frontend no-progress watchdog did not fail closed");
    end
    $display("APU-P7 KWS engine directed test passed");
    $finish;
  end
endmodule
