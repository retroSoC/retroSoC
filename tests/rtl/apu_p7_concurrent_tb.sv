// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// APU-P7 concurrent qualification: continuous RX KWS running together with
// looped WAV/FLAC decode streamed to I2S TX under the frozen P5 ready-memory
// discipline (64-word prefill, then ready memory without injected stalls).
// The bench fails closed on any codec underrun, I2S RX overrun, KWS overrun,
// missed KWS window schedule, or byte/frame/cycle/stall scoreboard mismatch.

`include "apu_define.svh"

module apu_p7_concurrent_tb;
  localparam logic [31:0] ApuBase = 32'h1001_3000;
  localparam logic [31:0] ImageBase = 32'h3000_0000;
  localparam logic [31:0] ModelBase = 32'h3001_0000;
  localparam logic [31:0] WavBase = 32'h3002_0000;
  localparam logic [31:0] FlacBase = 32'h3003_0000;
  localparam logic [31:0] WriteBase = 32'h3004_0000;

  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        resource_reset_i;
  logic [31:0] image            [0:16383];
  logic [31:0] model            [ 0:8191];
  logic [31:0] wav_image        [ 0:8191];
  logic [31:0] flac_image       [ 0:1023];
  logic [31:0] wav_pcm          [0:16383];
  logic [31:0] flac_pcm         [0:16383];
  logic        read_active_q;
  logic [31:0] read_addr_q;
  logic [7:0] read_len_q, read_beat_q;
  logic [63:0] cycle_q;
  logic [31:0] s_value;

  // Scenario plusarg state.
  string apumc_path, apum_path, wav_path, flac_path, wav_pcm_path, flac_pcm_path;
  logic [31:0] wav_bytes, wav_frames, wav_out_words;
  logic [31:0] flac_bytes, flac_frames, flac_out_words;
  logic [31:0] rate_hz, precision_bits, seconds_ms, seed_value, workload_mask, job_log;
  logic [31:0] wav_source_rate;
  logic [63:0] duration_cycles, max_cycles;
  logic [31:0] output_config, wav_input_config, wav_control, kws_input_config;
  logic [10:0] frame_period;  // PCLK cycles between consumed words at the I2S cadence.
  logic [ 2:0] decimation;
  logic [ 1:0] rx_words_per_frame;

  // I2S TX playback model state (64-word prefill, then periodic consumption).
  // The 1024-word bench FIFO plus the frozen 64-word router FIFO model the
  // product-line playback buffering; the frozen qualification fixes the
  // 64-word prefill and ready memory, not the playback buffer depth.
  logic [10:0] pb_count_q;
  logic [10:0] pb_div_q;
  logic pb_started_q, pb_done_q, pb_xrun_q;
  logic [63:0] pb_first_cycle_q, pb_last_cycle_q, pb_consumed_q;
  logic [31:0] pb_underrun_q;
  logic        drain_q;

  // I2S RX real-time feed state (one word per frame tick, never re-presented).
  logic        rx_feed_q;
  logic        rx_valid_q;
  logic [31:0] rx_data_q, rx_lfsr_q;
  logic [63:0] rx_delivered_q, rx_presented_q;
  logic [63:0] run_start_q, feed_stop_cycle_q;
  logic [31:0] rx_overrun_q;
  logic        rx_overrun_sticky_q;

  // Streamed-output scoreboard state.
  logic run_active_q, perf_count_q;
  logic pat_is_wav, pat_arm_q, pat_arm_seen_q;
  logic [14:0] pat_offset_q;
  logic [63:0] tx_words_q, tx_tlast_q;
  logic [63:0] tx_stall_cycles_q, rx_stall_cycles_q;
  logic [63:0] dma_read_stall_cycles_q, dma_write_stall_cycles_q;

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) dma_tx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) dma_rx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) i2s_tx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) i2s_rx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  // Ready-memory AXI read model: no injected stalls, back-to-back beats.
  assign axi4.arready = !read_active_q;
  assign axi4.rid = 1'b0;
  assign axi4.rdata = (read_addr_q >= FlacBase) ? flac_image[(read_addr_q-FlacBase)>>2] :
      ((read_addr_q >= WavBase) ? wav_image[(read_addr_q-WavBase)>>2] :
       ((read_addr_q >= ModelBase) ? model[(read_addr_q-ModelBase)>>2] :
        image[(read_addr_q-ImageBase)>>2]));
  assign axi4.rresp = 2'd0;
  assign axi4.rlast = read_beat_q == read_len_q;
  assign axi4.ruser = 1'b0;
  assign axi4.rvalid = read_active_q;
  assign axi4.awready = 1'b1;
  assign axi4.wready = 1'b0;
  assign axi4.bid = 1'b0;
  assign axi4.bresp = 2'd0;
  assign axi4.buser = 1'b0;
  assign axi4.bvalid = 1'b0;

  assign dma_tx_axis.tdata = 32'd0;
  assign dma_tx_axis.tkeep = 4'hf;
  assign dma_tx_axis.tstrb = 4'hf;
  assign dma_tx_axis.tlast = 1'b0;
  assign dma_tx_axis.tid = '0;
  assign dma_tx_axis.tdest = '0;
  assign dma_tx_axis.tuser = '0;
  assign dma_tx_axis.tvalid = 1'b0;
  assign dma_rx_axis.tready = 1'b1;

  assign i2s_tx_axis.tready = pb_count_q < 11'd1024;

  assign i2s_rx_axis.tdata = rx_data_q;
  assign i2s_rx_axis.tkeep = 4'hf;
  assign i2s_rx_axis.tstrb = 4'hf;
  assign i2s_rx_axis.tlast = 1'b0;
  assign i2s_rx_axis.tid = '0;
  assign i2s_rx_axis.tdest = '0;
  assign i2s_rx_axis.tuser = '0;
  assign i2s_rx_axis.tvalid = rx_valid_q;

  function automatic logic [31:0] lfsr_step(input logic [31:0] value_i);
    begin
      lfsr_step = {value_i[30:0], value_i[31] ^ value_i[21] ^ value_i[1] ^ value_i[0]};
    end
  endfunction

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      read_active_q            <= 1'b0;
      read_addr_q              <= 32'd0;
      read_len_q               <= 8'd0;
      read_beat_q              <= 8'd0;
      cycle_q                  <= 64'd0;
      pb_count_q               <= 11'd0;
      pb_div_q                 <= 11'd0;
      pb_started_q             <= 1'b0;
      pb_done_q                <= 1'b0;
      pb_xrun_q                <= 1'b0;
      pb_first_cycle_q         <= 64'd0;
      pb_last_cycle_q          <= 64'd0;
      pb_consumed_q            <= 64'd0;
      pb_underrun_q            <= 32'd0;
      rx_valid_q               <= 1'b0;
      rx_data_q                <= 32'd0;
      rx_lfsr_q                <= seed_value | 32'd1;
      rx_delivered_q           <= 64'd0;
      rx_presented_q           <= 64'd0;
      rx_overrun_q             <= 32'd0;
      rx_overrun_sticky_q      <= 1'b0;
      pat_arm_seen_q           <= 1'b0;
      pat_offset_q             <= 15'd0;
      tx_words_q               <= 64'd0;
      tx_tlast_q               <= 64'd0;
      tx_stall_cycles_q        <= 64'd0;
      rx_stall_cycles_q        <= 64'd0;
      dma_read_stall_cycles_q  <= 64'd0;
      dma_write_stall_cycles_q <= 64'd0;
    end else begin
      cycle_q <= cycle_q + 1'b1;

      if (axi4.arvalid && axi4.arready) begin
        read_active_q <= 1'b1;
        read_addr_q   <= axi4.araddr;
        read_len_q    <= axi4.arlen;
        read_beat_q   <= 8'd0;
      end
      if (axi4.rvalid && axi4.rready) begin
        if (axi4.rlast) read_active_q <= 1'b0;
        else begin
          read_addr_q <= read_addr_q + 32'd4;
          read_beat_q <= read_beat_q + 1'b1;
        end
      end
      if (axi4.awvalid && axi4.awready)
        $fatal(1, "P7 concurrent unexpected AXI write %h", axi4.awaddr);

      // Streamed-output scoreboard: byte-exact word pattern and TLAST checks.
      if (pat_arm_q != pat_arm_seen_q) begin
        pat_arm_seen_q <= pat_arm_q;
        pat_offset_q   <= 15'd0;
      end else if (run_active_q && i2s_tx_axis.tvalid && i2s_tx_axis.tready) begin
        if (i2s_tx_axis.tdata !== (pat_is_wav ? wav_pcm[pat_offset_q] : flac_pcm[pat_offset_q]))
          $fatal(
              1,
              "P7 concurrent PCM mismatch job=%0d offset=%0d data=%h expected=%h",
              pat_is_wav,
              pat_offset_q,
              i2s_tx_axis.tdata,
              pat_is_wav ? wav_pcm[pat_offset_q] : flac_pcm[pat_offset_q]
          );
        if (i2s_tx_axis.tlast !=
            (pat_offset_q == (pat_is_wav ? 15'(wav_out_words) : 15'(flac_out_words)) - 15'd1))
          $fatal(
              1,
              "P7 concurrent TLAST mismatch job=%0d offset=%0d tlast=%0d",
              pat_is_wav,
              pat_offset_q,
              i2s_tx_axis.tlast
          );
        pat_offset_q <= pat_offset_q + 1'b1;
        tx_words_q   <= tx_words_q + 1'b1;
        if (i2s_tx_axis.tlast) tx_tlast_q <= tx_tlast_q + 1'b1;
      end

      // I2S TX playback: start after the frozen 64-word prefill, then consume
      // one word per frame tick; an empty FIFO at a tick is an underrun.
      if (!pb_started_q && ((pb_count_q >= 11'd64) || (drain_q && (pb_count_q != 11'd0)))) begin
        pb_started_q <= 1'b1;
        pb_div_q     <= frame_period - 1'b1;
      end else if (pb_started_q && !pb_done_q) begin
        if (pb_div_q + 1'b1 >= frame_period) begin
          pb_div_q <= 11'd0;
          if (pb_count_q == 11'd0) begin
            if (drain_q) begin
              pb_done_q <= 1'b1;
            end else begin
              pb_xrun_q     <= 1'b1;
              pb_underrun_q <= pb_underrun_q + 1'b1;
              if (pb_underrun_q < 32'd16)
                $display(
                    "CONCURRENT_XRUN cycle=%0d dut_fifo=%0d",
                    cycle_q - run_start_q,
                    u_dut.u_stream_router.s_tx_count
                );
            end
          end else begin
            if (pb_consumed_q == 64'd0) pb_first_cycle_q <= cycle_q;
            pb_consumed_q   <= pb_consumed_q + 1'b1;
            pb_last_cycle_q <= cycle_q;
          end
        end else begin
          pb_div_q <= pb_div_q + 1'b1;
        end
      end
      unique case ({
        i2s_tx_axis.tvalid && i2s_tx_axis.tready,
        pb_started_q && !pb_done_q && (pb_div_q + 1'b1 >= frame_period) && (pb_count_q != 11'd0)
      })
        2'b10: pb_count_q <= pb_count_q + 1'b1;
        2'b01: pb_count_q <= pb_count_q - 1'b1;
        default: begin
        end
      endcase

      // I2S RX real-time feed: present each sample for exactly one cycle at the
      // frame cadence; a sample not accepted at that instant is an overrun.
      rx_valid_q <= 1'b0;
      if (rx_feed_q && ((run_start_q + rx_presented_q * {53'd0, frame_period}) <
                        feed_stop_cycle_q) &&
          (cycle_q >= run_start_q + rx_presented_q * {53'd0, frame_period})) begin
        rx_valid_q     <= 1'b1;
        rx_data_q      <= rx_lfsr_q;
        rx_lfsr_q      <= lfsr_step(rx_lfsr_q);
        rx_presented_q <= rx_presented_q + 1'b1;
      end
      if (i2s_rx_axis.tvalid && i2s_rx_axis.tready) begin
        rx_delivered_q <= rx_delivered_q + 1'b1;
      end else if (i2s_rx_axis.tvalid && !i2s_rx_axis.tready) begin
        rx_overrun_q        <= rx_overrun_q + 1'b1;
        rx_overrun_sticky_q <= 1'b1;
      end

      if (perf_count_q) begin
        if (i2s_tx_axis.tvalid && !i2s_tx_axis.tready)
          tx_stall_cycles_q <= tx_stall_cycles_q + 1'b1;
        if (i2s_rx_axis.tvalid && !i2s_rx_axis.tready)
          rx_stall_cycles_q <= rx_stall_cycles_q + 1'b1;
        // Mirror apu_dma's stall accounting: pending request without any AXI
        // handshake progress in the same cycle.
        if (u_dut.u_apu_dma.input_pending_o &&
            !((axi4.awvalid && axi4.awready) || (axi4.wvalid && axi4.wready) ||
              (axi4.bvalid && axi4.bready) || (axi4.arvalid && axi4.arready) ||
              (axi4.rvalid && axi4.rready)))
          dma_read_stall_cycles_q <= dma_read_stall_cycles_q + 1'b1;
        if (u_dut.u_apu_dma.output_pending_o &&
            !((axi4.awvalid && axi4.awready) || (axi4.wvalid && axi4.wready) ||
              (axi4.bvalid && axi4.bready) || (axi4.arvalid && axi4.arready) ||
              (axi4.rvalid && axi4.rready)))
          dma_write_stall_cycles_q <= dma_write_stall_cycles_q + 1'b1;
      end
    end
  end

  apb4_apu #(
      .EnableP7(1'b1)
  ) u_dut (
      .clk_i,
      .rst_n_i,
      .owner_i            (2'd0),
      .owner_lock_i       (1'b0),
      .quiesce_i          (apb4.pprot[0]),
      .resource_reset_i,
      .bridge_epoch_i     (8'd0),
      .i2s_tx_underrun_i  (pb_xrun_q),
      .i2s_rx_overrun_i   (rx_overrun_sticky_q),
      .i2s_rx_flush_busy_i(1'b0),
      .apb4,
      .axi4,
      .dma_tx_axis,
      .dma_rx_axis,
      .i2s_tx_axis,
      .i2s_rx_axis,
      .idle_o             (),
      .irq_o              ()
  );

  task automatic apb_write(input logic [11:0] offset_i, input logic [31:0] value_i);
    begin
      @(negedge clk_i);
      apb4.paddr   = ApuBase + offset_i;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b1;
      apb4.pwdata  = value_i;
      apb4.pstrb   = 4'hf;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr)
        $fatal(
            1,
            "P7 concurrent APB write %h = %h failed codec=%0d kws=%h",
            offset_i,
            value_i,
            u_dut.u_codec_controller.s_state_q,
            u_dut.s_kws_status
        );
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  task automatic apb_read(input logic [11:0] offset_i, output logic [31:0] value_o);
    begin
      @(negedge clk_i);
      apb4.paddr   = ApuBase + offset_i;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = 4'd0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr) $fatal(1, "P7 concurrent APB read failed %h", offset_i);
      value_o = apb4.prdata;
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  task automatic run_job(input logic is_wav_i, output logic [31:0] input_used_o,
                         output logic [31:0] output_bytes_o, output logic [31:0] frames_o,
                         output logic [31:0] cycles_o);
    logic        seen_busy;
    logic [63:0] job_start;
    begin
      pat_is_wav = is_wav_i;
      pat_arm_q  = !pat_arm_q;
      if (is_wav_i) begin
        apb_write(`APB4_APU__JOB_CONTROL, wav_control);
        apb_write(`APB4_APU__JOB_INPUT_ADDRESS, WavBase);
        apb_write(`APB4_APU__JOB_INPUT_LENGTH, wav_bytes);
        apb_write(`APB4_APU__JOB_INPUT_CONFIG, wav_input_config);
      end else begin
        apb_write(`APB4_APU__JOB_CONTROL, 32'h0000_0120);
        apb_write(`APB4_APU__JOB_INPUT_ADDRESS, FlacBase);
        apb_write(`APB4_APU__JOB_INPUT_LENGTH, flac_bytes);
        apb_write(`APB4_APU__JOB_INPUT_CONFIG, 32'd0);
      end
      apb_write(`APB4_APU__JOB_OUTPUT_ADDRESS, 32'd0);
      apb_write(`APB4_APU__JOB_OUTPUT_CAPACITY, 32'd0);
      apb_write(`APB4_APU__JOB_OUTPUT_CONFIG, output_config);
      apb_write(`APB4_APU__JOB_FLAGS, 32'd1);
      job_start = cycle_q;
      apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_START_DIRECT);
      seen_busy = 1'b0;
      for (int poll = 0; poll < 25000000; poll++) begin
        apb_read(`APB4_APU__JOB_STATUS, s_value);
        if (s_value[`APB4_APU__JOB_STATUS_BUSY]) seen_busy = 1'b1;
        if (seen_busy && (s_value[`APB4_APU__JOB_STATUS_DONE] ||
                          s_value[`APB4_APU__JOB_STATUS_ERROR]))
          break;
      end
      if (!s_value[`APB4_APU__JOB_STATUS_DONE]) begin
        $display("P7 concurrent job failed is_wav=%0d status=%h seq=%h retired=%h fault=%h",
                 is_wav_i, s_value, u_dut.s_seq_status, u_dut.s_seq_retired,
                 u_dut.s_seq_fault_detail);
        $display("P7 concurrent codec detail=%h transport=%0d dma_busy=%0d stream_idle=%0d",
                 u_dut.s_codec_detail, u_dut.u_codec_transport.s_state_q, u_dut.s_dma_busy,
                 u_dut.s_stream_idle);
        apb_read(`APB4_APU__ERROR_STATUS, s_value);
        $display("P7 concurrent error status=%h", s_value);
        apb_read(`APB4_APU__ERROR_ADDRESS, s_value);
        $display("P7 concurrent error address=%h", s_value);
        apb_read(`APB4_APU__ERROR_DETAIL, s_value);
        $fatal(1, "P7 concurrent job error detail=%h", s_value);
      end
      apb_read(`APB4_APU__JOB_INPUT_USED, input_used_o);
      if (input_used_o != (is_wav_i ? wav_bytes : flac_bytes))
        $fatal(1, "P7 concurrent input count mismatch is_wav=%0d used=%0d", is_wav_i, input_used_o);
      apb_read(`APB4_APU__JOB_OUTPUT_BYTES, output_bytes_o);
      if (output_bytes_o != (is_wav_i ? (wav_out_words << 2) : (flac_out_words << 2)))
        $fatal(
            1, "P7 concurrent output count mismatch is_wav=%0d bytes=%0d", is_wav_i, output_bytes_o
        );
      apb_read(`APB4_APU__JOB_FRAMES, frames_o);
      if (frames_o != (is_wav_i ? wav_frames : flac_frames))
        $fatal(1, "P7 concurrent frame count mismatch is_wav=%0d frames=%0d", is_wav_i, frames_o);
      apb_read(`APB4_APU__JOB_CYCLES, cycles_o);
      if (cycles_o == 32'd0) $fatal(1, "P7 concurrent stale job cycle count");
      if (job_log)
        $display(
            "CONCURRENT_JOB is_wav=%0d cycles=%0d wall=%0d", is_wav_i, cycles_o, cycle_q - job_start
        );
    end
  endtask

  initial begin
    logic is_wav;
    logic [63:0] job_count, wav_jobs, flac_jobs;
    logic [63:0] codec_input_bytes, codec_output_bytes, codec_frames, codec_cycles;
    logic [63:0] kws_expected_16k, kws_expected_frames, kws_expected_windows;
    logic [63:0] kws_frames_read, kws_windows_read;
    logic [63:0] perf_input_bytes, perf_output_bytes, perf_active_cycles;
    logic [63:0] perf_read_stalls, perf_write_stalls, perf_stream_stalls, perf_faults;
    logic [31:0] kws_overrun_read, kws_status_read;
    logic [31:0] job_iused, job_obytes, job_fcount, job_cyc;
    integer drain_poll;

    wav_bytes       = 32'd0;
    wav_frames      = 32'd0;
    wav_out_words   = 32'd0;
    flac_bytes      = 32'd0;
    flac_frames     = 32'd0;
    flac_out_words  = 32'd0;
    rate_hz         = 32'd0;
    precision_bits  = 32'd0;
    seconds_ms      = 32'd0;
    duration_cycles = 64'd0;
    max_cycles      = 64'd0;
    seed_value      = 32'd0;
    workload_mask   = 32'd0;
    job_log         = 32'd0;
    wav_source_rate = 32'd0;
    if (!$value$plusargs("APUMC_HEX=%s", apumc_path)) $fatal(1, "APUMC_HEX plusarg missing");
    if (!$value$plusargs("APUM_HEX=%s", apum_path)) $fatal(1, "APUM_HEX plusarg missing");
    if (!$value$plusargs("WAV_HEX=%s", wav_path)) $fatal(1, "WAV_HEX plusarg missing");
    if (!$value$plusargs("FLAC_HEX=%s", flac_path)) $fatal(1, "FLAC_HEX plusarg missing");
    if (!$value$plusargs("WAV_PCM_HEX=%s", wav_pcm_path)) $fatal(1, "WAV_PCM_HEX missing");
    if (!$value$plusargs("FLAC_PCM_HEX=%s", flac_pcm_path)) $fatal(1, "FLAC_PCM_HEX missing");
    if (!$value$plusargs("WAV_BYTES=%0d", wav_bytes)) $fatal(1, "WAV_BYTES missing");
    if (!$value$plusargs("WAV_FRAMES=%0d", wav_frames)) $fatal(1, "WAV_FRAMES missing");
    if (!$value$plusargs("WAV_OUT_WORDS=%0d", wav_out_words)) $fatal(1, "WAV_OUT_WORDS missing");
    if (!$value$plusargs("FLAC_BYTES=%0d", flac_bytes)) $fatal(1, "FLAC_BYTES missing");
    if (!$value$plusargs("FLAC_FRAMES=%0d", flac_frames)) $fatal(1, "FLAC_FRAMES missing");
    if (!$value$plusargs("FLAC_OUT_WORDS=%0d", flac_out_words)) $fatal(1, "FLAC_OUT_WORDS missing");
    if (!$value$plusargs("RATE=%0d", rate_hz)) $fatal(1, "RATE missing");
    if (!$value$plusargs("PRECISION=%0d", precision_bits)) $fatal(1, "PRECISION missing");
    if (!$value$plusargs("DURATION_CYCLES=%0d", duration_cycles))
      $fatal(1, "DURATION_CYCLES missing");
    if (!$value$plusargs("SECONDS_MS=%0d", seconds_ms)) $fatal(1, "SECONDS_MS missing");
    if (!$value$plusargs("MAX_CYCLES=%0d", max_cycles)) $fatal(1, "MAX_CYCLES missing");
    if (!$value$plusargs("SEED=%0d", seed_value)) seed_value = 32'd1;
    if (!$value$plusargs("WORKLOAD_MASK=%0d", workload_mask)) workload_mask = 32'd3;
    if (!$value$plusargs("JOB_LOG=%0d", job_log)) job_log = 32'd0;
    if (!$value$plusargs("WAV_SOURCE_RATE=%0d", wav_source_rate)) wav_source_rate = rate_hz;
    if ((rate_hz != 32'd48000) && (rate_hz != 32'd96000)) $fatal(1, "RATE must be 48000/96000");
    if ((precision_bits != 32'd16) && (precision_bits != 32'd24))
      $fatal(1, "PRECISION must be 16/24");
    if ((workload_mask == 32'd0) || (workload_mask > 32'd3)) $fatal(1, "WORKLOAD_MASK invalid");
    if ((wav_out_words > 15'd16384) || (flac_out_words > 15'd16384))
      $fatal(1, "workload output words exceed the pattern storage");

    $readmemh(apumc_path, image);
    $readmemh(apum_path, model);
    $readmemh(wav_path, wav_image);
    $readmemh(flac_path, flac_image);
    $readmemh(wav_pcm_path, wav_pcm);
    $readmemh(flac_pcm_path, flac_pcm);

    output_config = ((precision_bits == 32'd24) ? (32'd1 << 19) : 32'd0) | (32'd2 << 17) | rate_hz;
    wav_input_config = (32'd16 << 20) | (32'd2 << 17) | wav_source_rate;
    wav_control = (wav_source_rate == rate_hz) ? 32'h0000_0100 : 32'h0000_0900;
    kws_input_config = ((precision_bits == 32'd24) ? (32'd24 << 20) : (32'd16 << 20)) |
        (32'd2 << 17) | rate_hz;
    rx_words_per_frame = (precision_bits == 32'd24) ? 2'd2 : 2'd1;
    frame_period = 11'(32'(48000000) / rate_hz / {30'd0, rx_words_per_frame});
    decimation = (rate_hz == 32'd96000) ? 3'd6 : 3'd3;

    apb4.paddr = 32'd0;
    resource_reset_i = 1'b0;
    apb4.pprot = 3'd1;
    apb4.psel = 1'b0;
    apb4.penable = 1'b0;
    apb4.pwrite = 1'b0;
    apb4.pwdata = 32'd0;
    apb4.pstrb = 4'd0;
    drain_q = 1'b0;
    run_active_q = 1'b0;
    perf_count_q = 1'b0;
    rx_feed_q = 1'b0;
    feed_stop_cycle_q = 64'hffff_ffff_ffff_ffff;
    pat_is_wav = 1'b1;
    pat_arm_q = 1'b0;
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (2) @(posedge clk_i);

    apb_write(`APB4_APU__READ_BASE, ImageBase);
    apb_write(`APB4_APU__READ_LIMIT, FlacBase + 32'd4095);
    apb_write(`APB4_APU__WRITE_BASE, WriteBase);
    apb_write(`APB4_APU__WRITE_LIMIT, WriteBase + 32'd255);
    apb_write(`APB4_APU__MC_IMAGE_ADDRESS, ImageBase);
    apb_write(`APB4_APU__MC_IMAGE_SIZE, image[2]);
    apb_write(`APB4_APU__MC_EXPECTED_CRC, image[11]);
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_MICROCODE_LOAD);
    for (int poll = 0; poll < 500000; poll++) begin
      apb_read(`APB4_APU__MC_STATUS, s_value);
      if (s_value[`APB4_APU__MC_STATUS_VALID]) break;
      if (!s_value[`APB4_APU__MC_STATUS_BUSY])
        $fatal(1, "P7 concurrent microcode load failed %h", s_value);
    end
    if (!s_value[`APB4_APU__MC_STATUS_VALID]) $fatal(1, "P7 concurrent microcode load timeout");
    $display("CONCURRENT_SETUP microcode loaded crc=%h", image[11]);

    apb_write(`APB4_APU__KWS_MODEL_ADDRESS, ModelBase);
    apb_write(`APB4_APU__KWS_MODEL_SIZE, 32'd32768);
    apb_write(`APB4_APU__KWS_MODEL_EXPECTED_CRC, `APB4_APU__APUM_PAYLOAD_CRC);
    apb_write(`APB4_APU__COMMAND, 32'd1 << `APB4_APU__COMMAND_MODEL_LOAD);
    // The model load is admitted under quiesce, but its DMA only runs once
    // quiesce deasserts (apu_dma blocks new requests while quiesced and the
    // microcode loader is idle).
    apb4.pprot = 3'd0;
    for (int poll = 0; poll < 500000; poll++) begin
      apb_read(`APB4_APU__KWS_MODEL_STATUS, s_value);
      if (!s_value[0]) break;
    end
    if (s_value != 32'h0000_0006) begin
      apb_read(`APB4_APU__ERROR_STATUS, s_value);
      $display("P7 concurrent model load error status=%h", s_value);
      apb_read(`APB4_APU__ERROR_DETAIL, s_value);
      $fatal(1, "P7 concurrent model load failed detail=%h", s_value);
    end
    $display("CONCURRENT_SETUP model loaded status=%h", s_value);

    apb_write(`APB4_APU__KWS_INPUT_CONFIG, kws_input_config);
    apb_write(`APB4_APU__KWS_CONFIG, 32'h0000_0180);
    apb_write(`APB4_APU__STREAM_ROUTE, 32'd5);
    apb_write(`APB4_APU__PERF_CONTROL, 32'h3);
    perf_count_q = 1'b1;
    apb_write(`APB4_APU__KWS_CONTROL, 32'd1);
    repeat (32) @(posedge clk_i);
    apb_read(`APB4_APU__KWS_STATUS, s_value);
    if (!s_value[`APB4_APU__KWS_STATUS_LISTENING]) $fatal(1, "P7 concurrent KWS not listening");

    run_start_q        = cycle_q;
    feed_stop_cycle_q  = cycle_q + duration_cycles;
    rx_feed_q          = 1'b1;
    run_active_q       = 1'b1;
    job_count          = 64'd0;
    wav_jobs           = 64'd0;
    flac_jobs          = 64'd0;
    codec_input_bytes  = 64'd0;
    codec_output_bytes = 64'd0;
    codec_frames       = 64'd0;
    codec_cycles       = 64'd0;
    while (cycle_q < run_start_q + duration_cycles) begin
      // The constant-FLAC workload is the buffer-filling one: running it
      // first charges the playback buffer before the tighter WAV jobs,
      // exactly the role of the frozen 64-word prefill discipline.
      if (workload_mask == 32'd3) is_wav = (job_count[0] == 1'b1);
      else is_wav = workload_mask[0];
      run_job(is_wav, job_iused, job_obytes, job_fcount, job_cyc);
      codec_input_bytes  = codec_input_bytes + {32'd0, job_iused};
      codec_output_bytes = codec_output_bytes + {32'd0, job_obytes};
      codec_frames       = codec_frames + {32'd0, job_fcount};
      codec_cycles       = codec_cycles + {32'd0, job_cyc};
      if (is_wav) wav_jobs = wav_jobs + 1'b1;
      else flac_jobs = flac_jobs + 1'b1;
      job_count = job_count + 1'b1;
      if ((job_count % 64) == 0)
        $display("CONCURRENT_PROGRESS jobs=%0d cycle=%0d", job_count, cycle_q - run_start_q);
    end
    drain_q    = 1'b1;
    drain_poll = 0;
    while (!pb_done_q && (drain_poll < 100000000)) begin
      @(posedge clk_i);
      drain_poll = drain_poll + 1;
    end
    if (!pb_done_q) $fatal(1, "P7 concurrent playback drain timeout count=%0d", pb_count_q);
    rx_feed_q = 1'b0;

    // KWS schedule scoreboard: derive the exact expected frame/window counts
    // from the delivered uninterrupted sample stream.
    kws_expected_16k = rx_delivered_q / {62'd0, rx_words_per_frame} / {61'd0, decimation};
    kws_expected_frames = (kws_expected_16k >= 64'd480) ?
        ((kws_expected_16k - 64'd480) / 64'd320) + 64'd1 : 64'd0;
    kws_expected_windows = (kws_expected_16k >= 64'd16000) ?
        ((kws_expected_16k - 64'd16000) / 64'd1600) + 64'd1 : 64'd0;
    for (int poll = 0; poll < 100000000; poll++) begin
      apb_read(`APB4_APU__KWS_FRAME_COUNT, s_value);
      kws_frames_read = {32'd0, s_value};
      apb_read(`APB4_APU__KWS_INFERENCE_COUNT, s_value);
      kws_windows_read = {32'd0, s_value};
      if ((kws_frames_read == kws_expected_frames) && (kws_windows_read == kws_expected_windows))
        break;
      if (poll == 99999999) begin
        $display(
            "P7 concurrent KWS schedule timeout frames=%0d/%0d windows=%0d/%0d epoch=%0d front=%0d infer=%0d",
            kws_frames_read, kws_expected_frames, kws_windows_read, kws_expected_windows,
            u_dut.u_kws_engine.s_epoch_samples_q, u_dut.u_kws_engine.s_front_state_q,
            u_dut.u_kws_engine.s_infer_state_q);
        $fatal(1, "P7 concurrent KWS schedule mismatch");
      end
    end

    apb_read(`APB4_APU__KWS_OVERRUN_COUNT, kws_overrun_read);
    apb_read(`APB4_APU__KWS_STATUS, kws_status_read);
    apb_write(`APB4_APU__PERF_CONTROL, 32'h5);
    perf_count_q = 1'b0;
    apb_read(`APB4_APU__PERF_STATUS, s_value);
    if (!s_value[`APB4_APU__PERF_STATUS_SNAPSHOT_VALID]) $fatal(1, "P7 perf snapshot missing");
    apb_read(`APB4_APU__PERF_ACTIVE_CYCLES_LO, s_value);
    perf_active_cycles = {32'd0, s_value};
    apb_read(`APB4_APU__PERF_ACTIVE_CYCLES_HI, s_value);
    perf_active_cycles = perf_active_cycles | ({32'd0, s_value} << 32);
    apb_read(`APB4_APU__PERF_INPUT_BYTES_LO, s_value);
    perf_input_bytes = {32'd0, s_value};
    apb_read(`APB4_APU__PERF_INPUT_BYTES_HI, s_value);
    perf_input_bytes = perf_input_bytes | ({32'd0, s_value} << 32);
    apb_read(`APB4_APU__PERF_OUTPUT_BYTES_LO, s_value);
    perf_output_bytes = {32'd0, s_value};
    apb_read(`APB4_APU__PERF_OUTPUT_BYTES_HI, s_value);
    perf_output_bytes = perf_output_bytes | ({32'd0, s_value} << 32);
    apb_read(`APB4_APU__PERF_DMA_READ_STALLS_LO, s_value);
    perf_read_stalls = {32'd0, s_value};
    apb_read(`APB4_APU__PERF_DMA_READ_STALLS_HI, s_value);
    perf_read_stalls = perf_read_stalls | ({32'd0, s_value} << 32);
    apb_read(`APB4_APU__PERF_DMA_WRITE_STALLS_LO, s_value);
    perf_write_stalls = {32'd0, s_value};
    apb_read(`APB4_APU__PERF_DMA_WRITE_STALLS_HI, s_value);
    perf_write_stalls = perf_write_stalls | ({32'd0, s_value} << 32);
    apb_read(`APB4_APU__PERF_STREAM_STALLS_LO, s_value);
    perf_stream_stalls = {32'd0, s_value};
    apb_read(`APB4_APU__PERF_STREAM_STALLS_HI, s_value);
    perf_stream_stalls = perf_stream_stalls | ({32'd0, s_value} << 32);
    apb_read(`APB4_APU__PERF_FAULTS_LO, s_value);
    perf_faults = {32'd0, s_value};
    apb_read(`APB4_APU__PERF_FAULTS_HI, s_value);
    perf_faults = perf_faults | ({32'd0, s_value} << 32);

    // Frozen zero-xrun gate and byte/frame/cycle/stall scoreboards.
    if (pb_underrun_q != 32'd0) $fatal(1, "P7 concurrent codec underrun count=%0d", pb_underrun_q);
    if (rx_overrun_q != 32'd0) $fatal(1, "P7 concurrent I2S RX overrun count=%0d", rx_overrun_q);
    if (kws_overrun_read != 32'd0 || kws_status_read[`APB4_APU__KWS_STATUS_OVERRUN])
      $fatal(1, "P7 concurrent KWS overrun count=%0d status=%h", kws_overrun_read, kws_status_read);
    if ((kws_frames_read != kws_expected_frames) || (kws_windows_read != kws_expected_windows))
      $fatal(1, "P7 concurrent KWS window schedule mismatch");
    if (tx_words_q != codec_output_bytes >> 2)
      $fatal(
          1,
          "P7 concurrent stream word scoreboard mismatch words=%0d bytes=%0d",
          tx_words_q,
          codec_output_bytes
      );
    if (tx_tlast_q != job_count)
      $fatal(
          1, "P7 concurrent TLAST scoreboard mismatch tlast=%0d jobs=%0d", tx_tlast_q, job_count
      );
    if (pb_consumed_q != tx_words_q)
      $fatal(
          1,
          "P7 concurrent playback consumption mismatch consumed=%0d words=%0d",
          pb_consumed_q,
          tx_words_q
      );
    if ((pb_consumed_q > 64'd1) &&
        (pb_last_cycle_q - pb_first_cycle_q != (pb_consumed_q - 64'd1) * {53'd0, frame_period}))
      $fatal(
          1, "P7 concurrent playback span mismatch span=%0d", pb_last_cycle_q - pb_first_cycle_q
      );
    if ((wav_jobs == 64'd0) && workload_mask[0]) $fatal(1, "P7 concurrent WAV workload absent");
    if ((flac_jobs == 64'd0) && workload_mask[1]) $fatal(1, "P7 concurrent FLAC workload absent");
    if (perf_input_bytes != codec_input_bytes)
      $fatal(
          1,
          "P7 concurrent PERF input byte scoreboard mismatch perf=%0d codec=%0d",
          perf_input_bytes,
          codec_input_bytes
      );
    if (perf_output_bytes != 64'd0)
      $fatal(1, "P7 concurrent PERF output byte scoreboard mismatch %0d", perf_output_bytes);
    if (perf_read_stalls != dma_read_stall_cycles_q)
      $fatal(
          1,
          "P7 concurrent DMA read stall scoreboard mismatch perf=%0d tb=%0d",
          perf_read_stalls,
          dma_read_stall_cycles_q
      );
    if (perf_write_stalls != dma_write_stall_cycles_q)
      $fatal(
          1,
          "P7 concurrent DMA write stall scoreboard mismatch perf=%0d tb=%0d",
          perf_write_stalls,
          dma_write_stall_cycles_q
      );
    if (perf_stream_stalls != tx_stall_cycles_q + rx_stall_cycles_q)
      $fatal(
          1,
          "P7 concurrent stream stall scoreboard mismatch perf=%0d tb=%0d",
          perf_stream_stalls,
          tx_stall_cycles_q + rx_stall_cycles_q
      );
    if (perf_faults != 64'd0) $fatal(1, "P7 concurrent PERF fault scoreboard mismatch");
    if ((perf_active_cycles == 64'd0) || (perf_active_cycles > cycle_q - run_start_q))
      $fatal(1, "P7 concurrent PERF active cycle scoreboard mismatch %0d", perf_active_cycles);
    apb_read(`APB4_APU__ERROR_STATUS, s_value);
    if (s_value != 32'd0) $fatal(1, "P7 concurrent first-error status set %h", s_value);

    $display(
        "CONCURRENT_RESULT rate=%0d precision=%0d seconds_ms=%0d duration_cycles=%0d jobs=%0d wav_jobs=%0d flac_jobs=%0d tx_words=%0d consumed=%0d underrun=%0d rx_overrun=%0d kws_overrun=%0d kws_frames=%0d kws_windows=%0d rx_words=%0d codec_input_bytes=%0d codec_output_bytes=%0d codec_frames=%0d codec_cycles=%0d dma_read_stalls=%0d dma_write_stalls=%0d stream_stalls=%0d active_cycles=%0d elapsed_cycles=%0d scoreboard=match",
        rate_hz, precision_bits, seconds_ms, duration_cycles, job_count, wav_jobs, flac_jobs,
        tx_words_q, pb_consumed_q, pb_underrun_q, rx_overrun_q, kws_overrun_read, kws_frames_read,
        kws_windows_read, rx_delivered_q, codec_input_bytes, codec_output_bytes, codec_frames,
        codec_cycles, perf_read_stalls, perf_write_stalls, perf_stream_stalls, perf_active_cycles,
        cycle_q - run_start_q);
    $display("APU-P7 concurrent scenario passed");
    $finish;
  end

  initial begin
    wait (cycle_q > max_cycles);
    $fatal(1, "P7 concurrent global timeout");
  end

endmodule
