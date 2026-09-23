`timescale 1ns / 1ps

module apu_kws_loader_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic          start_i = 1'b0;
  logic          abort_i = 1'b0;
  logic          soft_reset_i = 1'b0;
  logic          resource_reset_request_i = 1'b0;
  logic          resource_reset_i = 1'b0;
  logic          quiesce_i = 1'b1;
  logic   [31:0] address_i = 32'h1000_0000;
  logic   [31:0] size_i = 32'd0;
  logic   [31:0] expected_crc_i = 32'hb903_4b22;
  logic   [31:0] acl_base_i = 32'h1000_0000;
  logic   [31:0] acl_limit_i = 32'h1000_ffff;
  logic          dma_request_valid_o;
  logic          dma_request_ready_i = 1'b1;
  logic   [31:0] dma_request_address_o;
  logic   [31:0] dma_request_bytes_o;
  logic   [31:0] dma_data_i = 32'd0;
  logic   [ 3:0] dma_keep_i = 4'hf;
  logic          dma_last_i = 1'b0;
  logic          dma_valid_i = 1'b0;
  logic          dma_done_i = 1'b0;
  logic          dma_error_i = 1'b0;
  logic   [ 5:0] dma_error_code_i = 6'd0;
  logic   [ 3:0] dma_error_stage_i = 4'd0;
  logic   [ 1:0] dma_error_resp_i = 2'd0;
  logic   [31:0] dma_error_address_i = 32'd0;
  logic          dma_ready_o;
  logic          local_request_o;
  logic          busy_o;
  logic          valid_o;
  logic          lock_o;
  logic          done_o;
  logic          abort_done_o;
  logic   [ 5:0] error_code_o;
  logic   [ 3:0] error_stage_o;
  logic   [ 1:0] error_resp_o;
  logic   [31:0] error_address_o;
  logic   [31:0] error_detail_o;
  logic   [31:0] status_o;
  logic   [31:0] actual_crc_o;
  logic          config_publish_o;
  logic   [15:0] config_default_o;
  logic   [31:0] model_words                     [0:8191];
  integer        local_write_count;
  integer        config_publish_count;
  integer        abort_done_count;
  integer        cycle_count;
  integer        writes_before_success;

  task automatic drive_dma(input integer first_word, input integer word_count,
                           input logic [31:0] expected_address, input logic [31:0] expected_bytes);
    logic accepted;
    begin
      wait (dma_request_valid_o);
      if ((dma_request_address_o != expected_address) ||
          (dma_request_bytes_o != expected_bytes)) begin
        $fatal(1, "model loader emitted the wrong bounded DMA request");
      end
      @(negedge clk_i);
      for (int word_index = 0; word_index < word_count; word_index++) begin
        dma_data_i  = model_words[first_word+word_index];
        dma_last_i  = word_index == (word_count - 1);
        dma_valid_i = 1'b1;
        do begin
          accepted = dma_ready_o;
          @(negedge clk_i);
        end while (!accepted);
      end
      dma_valid_i = 1'b0;
      dma_last_i  = 1'b0;
      dma_done_i  = 1'b1;
      @(negedge clk_i);
      dma_done_i = 1'b0;
    end
  endtask

  task automatic terminate_dma_early(
      input integer first_word, input integer word_count, input logic [31:0] expected_address,
      input logic [31:0] expected_bytes, input logic [5:0] error_code,
      input logic [3:0] error_stage, input logic [1:0] error_resp,
      input logic [31:0] error_address);
    logic accepted;
    begin
      wait (dma_request_valid_o);
      if ((dma_request_address_o != expected_address) ||
          (dma_request_bytes_o != expected_bytes)) begin
        $fatal(1, "model loader emitted the wrong early-terminal DMA request");
      end
      @(negedge clk_i);
      for (int word_index = 0; word_index < word_count; word_index++) begin
        dma_data_i  = model_words[first_word+word_index];
        dma_last_i  = 1'b0;
        dma_valid_i = 1'b1;
        do begin
          accepted = dma_ready_o;
          @(negedge clk_i);
        end while (!accepted);
      end
      dma_valid_i         = 1'b0;
      dma_last_i          = 1'b0;
      dma_error_i         = 1'b1;
      dma_error_code_i    = error_code;
      dma_error_stage_i   = error_stage;
      dma_error_resp_i    = error_resp;
      dma_error_address_i = error_address;
      dma_done_i          = 1'b1;
      @(negedge clk_i);
      dma_done_i  = 1'b0;
      dma_error_i = 1'b0;
    end
  endtask

  always #5 clk_i = ~clk_i;
  always @(posedge clk_i) begin
    cycle_count <= cycle_count + 1;
    if (cycle_count > 40000) begin
      $fatal(1, "loader test watchdog expired state=%0d received=%0d", dut.s_state_q,
             dut.s_received_q);
    end
  end
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      local_write_count    <= 0;
      config_publish_count <= 0;
      abort_done_count     <= 0;
    end else if (local_request_o) begin
      local_write_count <= local_write_count + 1;
    end
    if (rst_n_i && config_publish_o) begin
      config_publish_count <= config_publish_count + 1;
    end
    if (rst_n_i && abort_done_o) begin
      abort_done_count <= abort_done_count + 1;
    end
  end

  apu_kws_model_loader dut (
      .clk_i                   (clk_i),
      .rst_n_i                 (rst_n_i),
      .start_i                 (start_i),
      .abort_i                 (abort_i),
      .soft_reset_i            (soft_reset_i),
      .resource_reset_request_i(resource_reset_request_i),
      .resource_reset_i        (resource_reset_i),
      .quiesce_i               (quiesce_i),
      .address_i               (address_i),
      .size_i                  (size_i),
      .expected_crc_i          (expected_crc_i),
      .acl_base_i              (acl_base_i),
      .acl_limit_i             (acl_limit_i),
      .dma_request_valid_o     (dma_request_valid_o),
      .dma_request_ready_i     (dma_request_ready_i),
      .dma_request_address_o   (dma_request_address_o),
      .dma_request_bytes_o     (dma_request_bytes_o),
      .dma_data_i              (dma_data_i),
      .dma_keep_i              (dma_keep_i),
      .dma_last_i              (dma_last_i),
      .dma_valid_i             (dma_valid_i),
      .dma_ready_o             (dma_ready_o),
      .dma_done_i              (dma_done_i),
      .dma_error_i             (dma_error_i),
      .dma_error_code_i        (dma_error_code_i),
      .dma_error_stage_i       (dma_error_stage_i),
      .dma_error_resp_i        (dma_error_resp_i),
      .dma_error_address_i     (dma_error_address_i),
      .local_request_o         (local_request_o),
      .local_address_o         (),
      .local_data_o            (),
      .local_strb_o            (),
      .local_ready_i           (1'b1),
      .busy_o                  (busy_o),
      .valid_o                 (valid_o),
      .lock_o                  (lock_o),
      .actual_crc_o            (actual_crc_o),
      .status_o                (status_o),
      .error_code_o            (error_code_o),
      .error_stage_o           (error_stage_o),
      .error_resp_o            (error_resp_o),
      .error_address_o         (error_address_o),
      .error_detail_o          (error_detail_o),
      .config_publish_o        (config_publish_o),
      .config_default_o        (config_default_o),
      .done_o                  (done_o),
      .abort_done_o            (abort_done_o)
  );

  initial begin
    string apum_hex;
    string bad_crc_hex;
    string bad_profile_hex;

    cycle_count = 0;
    repeat (2) @(negedge clk_i);
    rst_n_i = 1'b1;
    size_i  = 32'd1;
    start_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b0;
    @(negedge clk_i);
    if ((status_o != 32'h0000_0400) || (error_code_o != `APB4_APU__ERROR_CODE_KWS_MODEL) ||
        dma_request_valid_o || local_request_o || valid_o || lock_o) begin
      $fatal(1, "invalid size must fail before model payload DMA");
    end
    @(negedge clk_i);
    size_i              = 32'd32768;
    dma_request_ready_i = 1'b0;
    start_i             = 1'b1;
    @(posedge clk_i);
    #1;
    if (!dma_request_valid_o || !busy_o) begin
      $fatal(1, "valid admission did not request private model DMA");
    end
    @(negedge clk_i);
    start_i = 1'b0;
    @(negedge clk_i);
    abort_i = 1'b1;
    @(negedge clk_i);
    abort_i = 1'b0;
    repeat (2) @(negedge clk_i);
    if (valid_o || lock_o || dma_ready_o || local_request_o) begin
      $fatal(1, "aborted model DMA published model state");
    end
    if ((abort_done_count != 1) || done_o) begin
      $fatal(1, "idle loader abort completion was not distinct");
    end
    dma_request_ready_i = 1'b1;
    @(negedge clk_i);

    start_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b0;
    wait (dma_ready_o);
    dma_data_i  = 32'h1234_5678;
    dma_valid_i = 1'b1;
    @(negedge clk_i);
    dma_valid_i = 1'b0;
    abort_i     = 1'b1;
    @(negedge clk_i);
    abort_i = 1'b0;
    if (!busy_o || abort_done_o || done_o) begin
      $fatal(1, "active loader abort completed before DMA drain");
    end
    repeat (2) @(negedge clk_i);
    if (!busy_o || abort_done_o) $fatal(1, "loader did not wait for abort drain");
    dma_done_i = 1'b1;
    @(negedge clk_i);
    dma_done_i = 1'b0;
    wait (abort_done_o);
    if (busy_o || done_o || valid_o || lock_o || (status_o != 32'd0)) begin
      $fatal(1, "clean loader abort did not complete without publication or load-done");
    end
    @(negedge clk_i);
    if (config_publish_count != 0) $fatal(1, "aborted model load published KWS_CONFIG");
    if ($value$plusargs("APUM_HEX=%s", apum_hex)) begin
      $readmemh(apum_hex, model_words);
      model_words[0] = model_words[0] ^ 32'd1;
      size_i         = 32'd32768;
      start_i        = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
      drive_dma(0, 16, 32'h1000_0000, 32'd64);
      wait (done_o);
      @(negedge clk_i);
      if ((status_o != 32'h0000_0100) || valid_o || lock_o ||
          (error_address_o != 32'h1000_0000)) begin
        $fatal(1, "malformed header did not report its first invalid word");
      end
      model_words[0] = model_words[0] ^ 32'd1;

      start_i        = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
      terminate_dma_early(0, 3, 32'h1000_0000, 32'd64, `APB4_APU__ERROR_CODE_AXI_READ,
                          `APB4_APU__ERROR_STAGE_DMA_READ, 2'd2, 32'h1000_0010);
      if (!busy_o || done_o || (status_o != 32'd0)) begin
        $fatal(1, "header DMA terminal state became idle before completion");
      end
      wait (done_o);
      @(negedge clk_i);
      if ((error_code_o != `APB4_APU__ERROR_CODE_AXI_READ) ||
          (error_stage_o != `APB4_APU__ERROR_STAGE_DMA_READ) ||
          (error_resp_o != 2'd2) || (error_address_o != 32'h1000_0010) ||
          (error_detail_o != 32'd0) || (status_o != 32'd0) || busy_o || valid_o || lock_o) begin
        $fatal(1, "header DMA error diagnostics were not preserved");
      end

      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
      drive_dma(0, 16, 32'h1000_0000, 32'd64);
      terminate_dma_early(16, 4, 32'h1000_0040, 32'd32704, `APB4_APU__ERROR_CODE_DMA_TIMEOUT,
                          `APB4_APU__ERROR_STAGE_DMA_READ, 2'd0, 32'h1000_1050);
      if (!busy_o || done_o || (status_o != 32'd0)) begin
        $fatal(1, "payload DMA terminal state became idle before completion");
      end
      wait (done_o);
      @(negedge clk_i);
      if ((error_code_o != `APB4_APU__ERROR_CODE_DMA_TIMEOUT) ||
          (error_stage_o != `APB4_APU__ERROR_STAGE_DMA_READ) ||
          (error_resp_o != 2'd0) || (error_address_o != 32'h1000_1050) ||
          (error_detail_o != 32'd0) || (status_o != 32'd0) || busy_o || valid_o || lock_o) begin
        $fatal(1, "payload DMA timeout diagnostics were not preserved");
      end

      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
      drive_dma(0, 16, 32'h1000_0000, 32'd64);
      drive_dma(16, 2, 32'h1000_0040, 32'd32704);
      wait (done_o);
      @(negedge clk_i);
      if ((status_o != 32'h0000_0200) || valid_o || lock_o ||
          (error_address_o != 32'h1000_0044)) begin
        $fatal(1, "partial payload did not fail at the first missing word");
      end

      if (!$value$plusargs("APUM_BAD_CRC_HEX=%s", bad_crc_hex)) begin
        $fatal(1, "missing APUM_BAD_CRC_HEX fixture");
      end
      $readmemh(bad_crc_hex, model_words);
      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
      drive_dma(0, 16, 32'h1000_0000, 32'd64);
      drive_dma(16, 8176, 32'h1000_0040, 32'd32704);
      wait (done_o);
      @(negedge clk_i);
      if ((status_o != 32'h0000_0800) ||
          (error_code_o != `APB4_APU__ERROR_CODE_KWS_CRC) || valid_o || lock_o) begin
        $fatal(1, "payload CRC mutation did not fail closed");
      end
      if (actual_crc_o == 32'd0) $fatal(1, "failed full payload did not retain observed CRC");
      soft_reset_i = 1'b1;
      @(negedge clk_i);
      soft_reset_i = 1'b0;
      if ((status_o != 32'd0) || (actual_crc_o != 32'd0) || (error_code_o != 6'd0) ||
          (error_stage_o != 4'd0) || (error_resp_o != 2'd0) ||
          (error_address_o != 32'd0) || (error_detail_o != 32'd0)) begin
        $fatal(1, "soft reset did not clear unlocked loader diagnostics");
      end

      if (!$value$plusargs("APUM_BAD_PROFILE_HEX=%s", bad_profile_hex)) begin
        $fatal(1, "missing APUM_BAD_PROFILE_HEX fixture");
      end
      $readmemh(bad_profile_hex, model_words);
      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
      drive_dma(0, 16, 32'h1000_0000, 32'd64);
      drive_dma(16, 8176, 32'h1000_0040, 32'd32704);
      wait (done_o);
      @(negedge clk_i);
      if ((status_o != 32'h0000_1000) ||
          (error_code_o != `APB4_APU__ERROR_CODE_KWS_MODEL) ||
          (error_address_o != 32'h1000_1000) || valid_o || lock_o) begin
        $fatal(1, "CRC-neutral requantization mutation bypassed profile validation");
      end
      if (config_publish_count != 0) begin
        $fatal(1, "failed model load published KWS_CONFIG");
      end

      $readmemh(apum_hex, model_words);
      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
      drive_dma(0, 16, 32'h1000_0000, 32'd64);
      drive_dma(16, 8176, 32'h1000_0040, 32'd32704);
      abort_i = 1'b1;
      @(negedge clk_i);
      abort_i = 1'b0;
      repeat (2) @(negedge clk_i);
      if (valid_o || lock_o || (status_o != 32'd0) || (config_publish_count != 0)) begin
        $fatal(1, "model load aborted at validation published state");
      end

      writes_before_success = local_write_count;
      size_i                = 32'd32768;
      start_i               = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
      drive_dma(0, 16, 32'h1000_0000, 32'd64);
      address_i      = 32'h2000_0000;
      size_i         = 32'd64;
      expected_crc_i = 32'hdead_beef;
      acl_base_i     = 32'h3000_0000;
      acl_limit_i    = 32'h3000_003f;
      quiesce_i      = 1'b0;
      drive_dma(16, 8176, 32'h1000_0040, 32'd32704);
      wait (done_o);
      @(negedge clk_i);
      if (!valid_o || !lock_o || (status_o != 32'h0000_0006) ||
          (actual_crc_o != 32'hb903_4b22) ||
          (local_write_count - writes_before_success != 8192) ||
          (config_publish_count != 1) || (config_default_o != 16'h0380)) begin
        $fatal(1, "complete APUM did not publish atomically");
      end
      resource_reset_i = 1'b1;
      @(negedge clk_i);
      resource_reset_i = 1'b0;
      soft_reset_i     = 1'b1;
      @(negedge clk_i);
      soft_reset_i = 1'b0;
      abort_i      = 1'b1;
      @(negedge clk_i);
      abort_i = 1'b0;
      if (!valid_o || !lock_o || (actual_crc_o != 32'hb903_4b22)) begin
        $fatal(1, "soft lifecycle reset or abort cleared the hard-reset model lock");
      end
      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
      repeat (3) @(negedge clk_i);
      if (dma_request_valid_o || busy_o) begin
        $fatal(1, "locked model accepted a reload");
      end
      rst_n_i = 1'b0;
      repeat (2) @(negedge clk_i);
      rst_n_i = 1'b1;
      @(negedge clk_i);
      if (valid_o || lock_o || (actual_crc_o != 32'd0)) begin
        $fatal(1, "hard reset did not invalidate the model lock");
      end
    end
    $display("APU-P7 KWS loader admission and abort test passed");
    $finish;
  end
endmodule
