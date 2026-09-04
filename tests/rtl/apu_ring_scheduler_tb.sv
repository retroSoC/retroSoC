`timescale 1ns / 1ps

`include "apu_define.svh"

module apu_ring_scheduler_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        soft_reset_i = 1'b0;
  logic        counter_clear_i = 1'b0;
  logic        abort_i = 1'b0;
  logic        quiesce_i = 1'b0;
  logic        start_i = 1'b0;
  logic [31:0] ring_base_i = 32'h0000_1000;
  logic [ 8:0] ring_size_i = 9'd2;
  logic [ 7:0] ring_tail_i = 8'd0;
  logic        ring_enable_i = 1'b0;
  logic        stop_on_error_i = 1'b0;
  logic [ 7:0] coalesce_count_i = 8'd3;
  logic [15:0] coalesce_timeout_i = 16'd4;
  logic dma_request_valid_o, dma_request_ready_i, dma_request_write_o;
  logic [31:0] dma_request_addr_o, dma_request_bytes_o;
  logic        dma_done_i = 1'b0;
  logic        dma_error_i = 1'b0;
  logic [ 5:0] dma_error_code_i = 6'd0;
  logic [ 3:0] dma_error_stage_i = 4'd0;
  logic [ 1:0] dma_error_resp_i = 2'd0;
  logic [31:0] dma_error_addr_i = 32'd0;
  logic backend_job_valid, backend_job_ready;
  logic [1023:0] backend_descriptor;
  logic [   7:0] backend_index;
  logic backend_result_valid, backend_result_ready;
  logic       backend_result_error = 1'b0;
  logic [5:0] backend_result_code = 6'd0;
  logic [3:0] backend_result_stage = 4'd0;
  logic [1:0] backend_result_resp = 2'd0;
  logic       backend_latched_error;
  logic [5:0] backend_latched_code;
  logic [3:0] backend_latched_stage;
  logic [1:0] backend_latched_resp;
  logic [31:0] backend_input_used, backend_output_bytes, backend_frames;
  logic [31:0] backend_source_info, backend_cycles, backend_detail;
  logic        backend_hold = 1'b0;
  logic        hold_dma_request = 1'b0;
  logic        hold_dma_read = 1'b0;
  logic        hold_dma_write = 1'b0;
  logic [31:0] backend_accepted;
  logic [31:0] job_status_o, ring_status_o;
  logic [ 7:0] ring_head_o;
  logic [31:0] ring_completed_o;
  logic ring_event_o, error_event_o, abort_done_o, aborting_o, idle_o;
  logic [ 5:0] error_code_o;
  logic [ 3:0] error_stage_o;
  logic [ 1:0] error_resp_o;
  logic [ 7:0] error_index_o;
  logic [31:0] error_addr_o;
  logic [31:0] memory        [0:63];
  logic dma_active_q, dma_write_q;
  logic [5:0] dma_word_q, dma_last_word_q;
  logic inject_dma_error_q;
  int unsigned ring_events, error_events, abort_events;
  int unsigned events_before_invalid, errors_before_invalid;
  string s_phase;

  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) dma_read_axis (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) dma_write_axis (
      clk_i,
      rst_n_i
  );

  always #5 clk_i = ~clk_i;

  assign dma_request_ready_i   = !dma_active_q && !hold_dma_request;
  assign dma_read_axis.tdata   = memory[((dma_request_addr_o-ring_base_i)>>2)+dma_word_q];
  assign dma_read_axis.tkeep   = 4'hf;
  assign dma_read_axis.tstrb   = 4'hf;
  assign dma_read_axis.tlast   = dma_word_q == dma_last_word_q;
  assign dma_read_axis.tid     = '0;
  assign dma_read_axis.tdest   = '0;
  assign dma_read_axis.tuser   = '0;
  assign dma_read_axis.tvalid  = dma_active_q && !dma_write_q && !hold_dma_read;
  assign dma_write_axis.tready = dma_active_q && dma_write_q && !hold_dma_write;

  apu_ring_scheduler u_dut (
      .clk_i,
      .rst_n_i,
      .soft_reset_i,
      .counter_clear_i,
      .abort_i,
      .quiesce_i,
      .start_i,
      .ring_base_i,
      .ring_size_i,
      .ring_tail_i,
      .ring_enable_i,
      .stop_on_error_i,
      .coalesce_count_i,
      .coalesce_timeout_i,
      .dma_request_valid_o,
      .dma_request_ready_i,
      .dma_request_write_o,
      .dma_request_addr_o,
      .dma_request_bytes_o,
      .dma_read_axis,
      .dma_write_axis,
      .dma_done_i,
      .dma_error_i,
      .dma_error_code_i,
      .dma_error_stage_i,
      .dma_error_resp_i,
      .dma_error_addr_i,
      .backend_job_valid_o   (backend_job_valid),
      .backend_job_ready_i   (backend_job_ready),
      .backend_descriptor_o  (backend_descriptor),
      .backend_index_o       (backend_index),
      .backend_result_valid_i(backend_result_valid),
      .backend_result_ready_o(backend_result_ready),
      .backend_result_error_i(backend_latched_error),
      .backend_result_code_i (backend_latched_code),
      .backend_result_stage_i(backend_latched_stage),
      .backend_result_resp_i (backend_latched_resp),
      .backend_input_used_i  (backend_input_used),
      .backend_output_bytes_i(backend_output_bytes),
      .backend_frames_i      (backend_frames),
      .backend_source_info_i (backend_source_info),
      .backend_cycles_i      (backend_cycles),
      .backend_detail_i      (backend_detail),
      .job_status_o,
      .ring_status_o,
      .ring_head_o,
      .ring_completed_o,
      .ring_event_o,
      .error_event_o,
      .error_code_o,
      .error_stage_o,
      .error_resp_o,
      .error_index_o,
      .error_addr_o,
      .abort_done_o,
      .aborting_o,
      .idle_o
  );

  apu_p2_backend u_backend (
      .clk_i,
      .rst_n_i,
      .abort_i,
      .hold_result_i  (backend_hold),
      .result_error_i (backend_result_error),
      .result_code_i  (backend_result_code),
      .result_stage_i (backend_result_stage),
      .result_resp_i  (backend_result_resp),
      .job_valid_i    (backend_job_valid),
      .job_ready_o    (backend_job_ready),
      .descriptor_i   (backend_descriptor),
      .index_i        (backend_index),
      .result_valid_o (backend_result_valid),
      .result_ready_i (backend_result_ready),
      .result_error_o (backend_latched_error),
      .result_code_o  (backend_latched_code),
      .result_stage_o (backend_latched_stage),
      .result_resp_o  (backend_latched_resp),
      .input_used_o   (backend_input_used),
      .output_bytes_o (backend_output_bytes),
      .frames_o       (backend_frames),
      .source_info_o  (backend_source_info),
      .cycles_o       (backend_cycles),
      .detail_o       (backend_detail),
      .accepted_jobs_o(backend_accepted)
  );

  task automatic pulse_start;
    begin
      @(negedge clk_i);
      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
    end
  endtask

  task automatic pulse_abort;
    begin
      @(negedge clk_i);
      abort_i = 1'b1;
      @(negedge clk_i);
      abort_i = 1'b0;
    end
  endtask

  task automatic hard_reset;
    begin
      rst_n_i = 1'b0;
      repeat (3) @(posedge clk_i);
      @(negedge clk_i);
      rst_n_i = 1'b1;
      repeat (2) @(posedge clk_i);
    end
  endtask

  task automatic wait_completed(input logic [31:0] expected_i);
    int unsigned timeout;
    begin
      timeout = 0;
      while ((ring_completed_o != expected_i) && (timeout < 1000)) begin
        @(posedge clk_i);
        timeout++;
      end
      if (ring_completed_o != expected_i) $fatal(1, "ring completion timeout in %s", s_phase);
    end
  endtask

  task automatic clear_descriptor(input int unsigned descriptor_i);
    for (int unsigned word_index = 0; word_index < 32; word_index++) begin
      memory[(descriptor_i*32)+word_index] = 32'd0;
    end
  endtask

  task automatic make_valid_descriptor(input int unsigned descriptor_i, input logic ioc_i);
    begin
      clear_descriptor(descriptor_i);
      memory[descriptor_i*32] = (32'd1 << `APB4_APU__DESCRIPTOR_CONTROL_OWN) |
          (ioc_i ? (32'd1 << `APB4_APU__DESCRIPTOR_CONTROL_IOC) : 32'd0);
      memory[(descriptor_i*32)+2] = 32'h0000_4000 + (descriptor_i * 32'h100);
      memory[(descriptor_i*32)+3] = 32'd256 + descriptor_i;
      memory[(descriptor_i*32)+4] = 32'h0000_8000 + (descriptor_i * 32'h100);
      memory[(descriptor_i*32)+5] = 32'd512 + descriptor_i;
      memory[(descriptor_i*32)+16] = 32'hc001_0000 + descriptor_i;
      memory[(descriptor_i*32)+17] = 32'hc002_0000 + descriptor_i;
    end
  endtask

  task automatic abort_writeback_state(input logic [3:0] state_i);
    begin
      hard_reset();
      clear_descriptor(0);
      make_valid_descriptor(0, 1'b0);
      ring_size_i      = 9'd2;
      ring_tail_i      = 8'd1;
      ring_enable_i    = 1'b1;
      backend_hold     = 1'b1;
      hold_dma_request = 1'b0;
      hold_dma_write   = 1'b0;
      pulse_start();
      wait (u_dut.s_state_q == 4'd5);
      @(negedge clk_i);
      if (state_i == 4'd6) hold_dma_request = 1'b1;
      if (state_i == 4'd7) hold_dma_write = 1'b1;
      backend_hold = 1'b0;
      if (state_i == 4'd9) begin
        wait (u_dut.s_state_q == 4'd8);
        @(negedge clk_i);
        hold_dma_request = 1'b1;
      end
      if (state_i == 4'd10) begin
        wait (u_dut.s_state_q == 4'd9);
        @(negedge clk_i);
        hold_dma_write = 1'b1;
      end
      wait (u_dut.s_state_q == state_i);
      pulse_abort();
      hold_dma_request = 1'b0;
      hold_dma_write   = 1'b0;
      wait (abort_done_o);
      wait (idle_o);
      if (memory[0][31] || (ring_completed_o != 32'd1)) begin
        $fatal(1, "abort did not retire ordered writeback state %0d", state_i);
      end
    end
  endtask

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      dma_active_q       <= 1'b0;
      dma_write_q        <= 1'b0;
      dma_word_q         <= 6'd0;
      dma_last_word_q    <= 6'd0;
      dma_done_i         <= 1'b0;
      dma_error_i        <= 1'b0;
      inject_dma_error_q <= 1'b0;
      ring_events        <= 0;
      error_events       <= 0;
      abort_events       <= 0;
    end else begin
      dma_done_i  <= 1'b0;
      dma_error_i <= 1'b0;
      if (dma_request_valid_o && dma_request_ready_i) begin
        if ((!dma_request_write_o &&
             ((dma_request_bytes_o != 32'd128) || (dma_request_addr_o[6:0] != 7'd0))) ||
            (dma_request_write_o && (dma_request_bytes_o == 32'd124) &&
             (dma_request_addr_o[6:0] != 7'd4)) ||
            (dma_request_write_o && (dma_request_bytes_o == 32'd4) &&
             (dma_request_addr_o[6:0] != 7'd0)) ||
            (dma_request_write_o && (dma_request_bytes_o != 32'd124) &&
             (dma_request_bytes_o != 32'd4))) begin
          $fatal(1, "malformed descriptor DMA request");
        end
        if (dma_request_write_o && (dma_request_bytes_o == 32'd124) &&
            !memory[((dma_request_addr_o-ring_base_i)>>2)-1][31]) begin
          $fatal(1, "descriptor OWN cleared before result writeback");
        end
        if (dma_request_write_o && (dma_request_bytes_o == 32'd4) &&
            (!memory[((dma_request_addr_o-ring_base_i)>>2)][31] ||
             (memory[((dma_request_addr_o-ring_base_i)>>2)+1] == 32'd0))) begin
          $fatal(1, "descriptor OWN publication preceded result retirement");
        end
        dma_active_q    <= 1'b1;
        dma_write_q     <= dma_request_write_o;
        dma_word_q      <= 6'd0;
        dma_last_word_q <= 6'(((dma_request_bytes_o + 32'd3) >> 2) - 1'b1);
      end
      if (dma_read_axis.tvalid && dma_read_axis.tready) begin
        if (dma_word_q == dma_last_word_q) begin
          dma_active_q       <= 1'b0;
          dma_done_i         <= 1'b1;
          dma_error_i        <= inject_dma_error_q;
          dma_error_code_i   <= inject_dma_error_q ? 6'd15 : 6'd0;
          dma_error_stage_i  <= inject_dma_error_q ? 4'd3 : 4'd0;
          dma_error_resp_i   <= inject_dma_error_q ? 2'd2 : 2'd0;
          dma_error_addr_i   <= dma_request_addr_o;
          inject_dma_error_q <= 1'b0;
        end else begin
          dma_word_q <= dma_word_q + 1'b1;
        end
      end
      if (dma_write_axis.tvalid && dma_write_axis.tready) begin
        memory[((dma_request_addr_o-ring_base_i)>>2)+dma_word_q] <= dma_write_axis.tdata;
        if (dma_word_q == dma_last_word_q) begin
          dma_active_q <= 1'b0;
          dma_done_i   <= 1'b1;
        end else begin
          dma_word_q <= dma_word_q + 1'b1;
        end
      end
      if (ring_event_o) ring_events <= ring_events + 1;
      if (error_event_o) error_events <= error_events + 1;
      if (abort_done_o) abort_events <= abort_events + 1;
    end
  end

  initial begin
    for (int unsigned index = 0; index < 64; index++) memory[index] = 32'd0;
    s_phase = "reset";
    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (2) @(posedge clk_i);
    if (ring_status_o != 32'h0000_0004 || job_status_o != 32'd0) begin
      $fatal(1, "ring/job reset status mismatch");
    end

    s_phase          = "reset timing";
    ring_tail_i      = 8'd1;
    ring_enable_i    = 1'b1;
    hold_dma_request = 1'b1;
    pulse_start();
    @(posedge clk_i);
    #1;
    if (!dma_request_valid_o || idle_o) $fatal(1, "ring reset-timing state was not seeded");
    @(negedge clk_i);
    soft_reset_i = 1'b1;
    ring_tail_i  = 8'd0;
    #1;
    if (!dma_request_valid_o || idle_o) $fatal(1, "ring soft reset acted asynchronously");
    @(posedge clk_i);
    #1;
    if (!idle_o || (ring_status_o != 32'h0000_0004) || (job_status_o != 32'd0)) begin
      $fatal(1, "ring soft reset did not apply on PCLK");
    end
    @(negedge clk_i);
    soft_reset_i     = 1'b0;
    ring_enable_i    = 1'b0;
    hold_dma_request = 1'b0;
    repeat (2) @(posedge clk_i);

    ring_tail_i      = 8'd1;
    ring_enable_i    = 1'b1;
    hold_dma_request = 1'b1;
    pulse_start();
    @(posedge clk_i);
    #1;
    if (!dma_request_valid_o || idle_o) $fatal(1, "ring hard-reset state was not seeded");
    @(negedge clk_i);
    rst_n_i     = 1'b0;
    ring_tail_i = 8'd0;
    #1;
    if (!idle_o || (ring_status_o != 32'h0000_0004) || (job_status_o != 32'd0)) begin
      $fatal(1, "ring hard reset did not apply asynchronously");
    end
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_n_i          = 1'b1;
    ring_enable_i    = 1'b0;
    hold_dma_request = 1'b0;
    repeat (2) @(posedge clk_i);

    ring_size_i = 9'd256;
    force u_dut.s_head_q = 8'd254;
    #1;
    if (u_dut.s_next_head != 8'd255) $fatal(1, "256-entry ring truncated before index 255");
    force u_dut.s_head_q = 8'd255;
    #1;
    if (u_dut.s_next_head != 8'd0) $fatal(1, "256-entry ring did not wrap after index 255");
    release u_dut.s_head_q;

    s_phase       = "stale head validation";
    ring_size_i   = 9'd2;
    ring_tail_i   = 8'd1;
    ring_enable_i = 1'b1;
    force u_dut.s_head_q = 8'd3;
    pulse_start();
    #1;
    if (!error_event_o || (error_code_o != 6'd2) || dma_active_q) begin
      $fatal(1, "stale ring head outside the configured extent was accepted");
    end
    release u_dut.s_head_q;

    soft_reset_i = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    soft_reset_i = 1'b0;
    ring_size_i  = 9'd2;

    s_phase      = "backend request abort exclusion";
    make_valid_descriptor(0, 1'b0);
    ring_tail_i   = 8'd1;
    ring_enable_i = 1'b1;
    pulse_start();
    wait (u_dut.s_state_q == 4'd4);
    @(negedge clk_i);
    abort_i = 1'b1;
    #1;
    if (backend_job_valid || backend_job_ready) begin
      $fatal(1, "backend handshake remained eligible during abort");
    end
    @(negedge clk_i);
    abort_i = 1'b0;
    wait_completed(32'd1);
    if ((backend_accepted != 32'd0) || !memory[1][2]) begin
      $fatal(1, "backend request abort was accepted or not published");
    end

    hard_reset();
    clear_descriptor(0);
    s_phase              = "simultaneous backend error and abort";
    backend_hold         = 1'b1;
    backend_result_error = 1'b1;
    backend_result_code  = 6'd7;
    backend_result_stage = 4'd4;
    make_valid_descriptor(0, 1'b0);
    ring_tail_i   = 8'd1;
    ring_enable_i = 1'b1;
    pulse_start();
    wait (u_dut.s_state_q == 4'd5);
    @(negedge clk_i);
    backend_hold = 1'b0;
    abort_i      = 1'b1;
    @(negedge clk_i);
    abort_i = 1'b0;
    wait_completed(32'd1);
    @(posedge clk_i);
    if (!memory[1][1] || !memory[1][2] || (memory[1][8:3] != 6'd7) ||
        (error_events != 1) || (abort_events != 1)) begin
      $fatal(1, "simultaneous backend error did not outrank and retain abort");
    end

    backend_result_error = 1'b0;
    backend_result_code  = 6'd0;
    backend_result_stage = 4'd0;
    hard_reset();
    clear_descriptor(0);

    s_phase       = "idle-active abort";
    ring_tail_i   = 8'd0;
    ring_enable_i = 1'b1;
    pulse_start();
    wait (ring_status_o[`APB4_APU__RING_STATUS_ACTIVE] && idle_o);
    pulse_abort();
    wait (abort_done_o);

    hard_reset();
    clear_descriptor(0);
    make_valid_descriptor(0, 1'b0);
    s_phase          = "fetch-request abort";
    hold_dma_request = 1'b1;
    ring_tail_i      = 8'd1;
    ring_enable_i    = 1'b1;
    pulse_start();
    wait (u_dut.s_state_q == 4'd1);
    pulse_abort();
    hold_dma_request = 1'b0;
    wait (abort_done_o);
    if (!memory[0][31]) $fatal(1, "FetchRequest abort mutated descriptor ownership");

    hard_reset();
    clear_descriptor(0);
    s_phase       = "stalled-unowned abort";
    ring_tail_i   = 8'd1;
    ring_enable_i = 1'b1;
    pulse_start();
    wait (u_dut.s_state_q == 4'd12);
    pulse_abort();
    wait (abort_done_o);

    hard_reset();
    clear_descriptor(0);

    for (int unsigned writeback_state = 6; writeback_state <= 11; writeback_state++) begin
      s_phase = "writeback abort matrix";
      abort_writeback_state(4'(writeback_state));
    end
    hard_reset();
    clear_descriptor(0);

    s_phase = "timeout coalescing";
    make_valid_descriptor(0, 1'b0);
    ring_enable_i = 1'b1;
    ring_tail_i   = 8'd1;
    pulse_start();
    wait_completed(32'd1);
    if (memory[0][31] || !memory[1][0] || (ring_head_o != 8'd1) || !job_status_o[1] ||
        (memory[16] != 32'hc001_0000) || (memory[17] != 32'hc002_0000) ||
        ({memory[21], memory[20]} < {memory[19], memory[18]}) ||
        (memory[22] != 32'd0) || (memory[23] != 32'd0)) begin
      $fatal(1, "successful descriptor writeback mismatch");
    end
    while (ring_events == 0) @(posedge clk_i);
    if (ring_status_o[5] || (ring_status_o[15:8] != 8'd0)) begin
      $fatal(1, "coalescing timeout did not clear pending state");
    end

    s_phase = "unowned and IOC wrap";
    clear_descriptor(1);
    ring_tail_i = 8'd0;
    repeat (40) @(posedge clk_i);
    if (!ring_status_o[1] || (ring_head_o != 8'd1) || (ring_completed_o != 32'd1)) begin
      $fatal(1, "unowned descriptor was not stalled");
    end
    make_valid_descriptor(1, 1'b1);
    pulse_start();
    wait_completed(32'd2);
    @(posedge clk_i);
    if ((ring_head_o != 8'd0) || !ring_status_o[4] || (ring_events != 2)) begin
      $fatal(1, "IOC/wrap behavior mismatch events=%0d", ring_events);
    end

    s_phase            = "count coalescing";
    coalesce_count_i   = 8'd2;
    coalesce_timeout_i = 16'd100;
    make_valid_descriptor(0, 1'b0);
    ring_tail_i = 8'd1;
    pulse_start();
    wait_completed(32'd3);
    if ((ring_events != 2) || !ring_status_o[5] || (ring_status_o[15:8] != 8'd1)) begin
      $fatal(1, "coalescing count epoch did not retain first completion");
    end
    make_valid_descriptor(1, 1'b0);
    ring_tail_i = 8'd0;
    pulse_start();
    wait_completed(32'd4);
    @(posedge clk_i);
    if ((ring_events != 3) || ring_status_o[5] || (ring_status_o[15:8] != 8'd0)) begin
      $fatal(1, "coalescing count threshold mismatch");
    end

    s_phase            = "deterministic randomized descriptors";
    coalesce_count_i   = 8'd4;
    coalesce_timeout_i = 16'd7;
    for (int unsigned job = 0; job < 8; job++) begin
      automatic int unsigned descriptor = ring_head_o;
      automatic logic        expected_error = ((job * 5 + 1) % 7) == 2;
      make_valid_descriptor(descriptor, ((job * 3 + 1) % 5) == 0);
      memory[(descriptor*32)+3] = 32'd33 + ((job * 29) % 511);
      memory[(descriptor*32)+5] = 32'd65 + ((job * 17) % 1023);
      backend_result_error      = expected_error;
      backend_result_code       = expected_error ? 6'd7 : 6'd0;
      backend_result_stage      = expected_error ? 4'd4 : 4'd0;
      ring_tail_i               = descriptor == 0 ? 8'd1 : 8'd0;
      pulse_start();
      wait_completed(32'(5 + job));
      @(posedge clk_i);
      if (memory[descriptor*32][31] ||
          (memory[(descriptor*32)+1][1] != expected_error) ||
          (memory[(descriptor*32)+1][0] == expected_error)) begin
        $fatal(1, "randomized descriptor result mismatch job=%0d", job);
      end
    end
    backend_result_error  = 1'b0;
    backend_result_code   = 6'd0;
    backend_result_stage  = 4'd0;

    s_phase               = "invalid stop on error";
    events_before_invalid = ring_events;
    errors_before_invalid = error_events;
    ring_enable_i         = 1'b0;
    repeat (2) @(posedge clk_i);
    stop_on_error_i = 1'b1;
    make_valid_descriptor(0, 1'b1);
    memory[0][12] = 1'b1;
    memory[10]    = 32'hdead_beef;
    ring_tail_i   = 8'd1;
    ring_enable_i = 1'b1;
    pulse_start();
    wait_completed(32'd13);
    @(posedge clk_i);
    if (memory[0][31] || !memory[1][1] || (memory[1][8:3] != 6'd2) ||
        (memory[10] != 32'd0) ||
        !ring_status_o[3] || !ring_status_o[7] || ring_status_o[0] ||
        (ring_events != events_before_invalid + 1) ||
        (error_events != errors_before_invalid + 1)) begin
      $fatal(1, "invalid-owned stop-on-error behavior mismatch");
    end

    s_phase         = "abort writeback";
    ring_enable_i   = 1'b0;
    stop_on_error_i = 1'b0;
    repeat (2) @(posedge clk_i);
    make_valid_descriptor(1, 1'b0);
    ring_tail_i   = 8'd0;
    backend_hold  = 1'b1;
    ring_enable_i = 1'b1;
    pulse_start();
    while (!backend_job_valid && !backend_result_ready) @(posedge clk_i);
    repeat (2) @(posedge clk_i);
    pulse_abort();
    if (!aborting_o) $fatal(1, "scheduler live aborting status was not asserted");
    backend_hold = 1'b0;
    wait_completed(32'd14);
    @(posedge clk_i);
    if (memory[32][31] || !memory[33][2] || !job_status_o[3] ||
        (abort_events != 1) || ring_status_o[0]) begin
      $fatal(1, "abort terminal writeback mismatch");
    end
    if (aborting_o) $fatal(1, "scheduler live aborting status remained set after writeback");

    s_phase       = "descriptor DMA error";
    ring_enable_i = 1'b0;
    repeat (2) @(posedge clk_i);
    make_valid_descriptor(0, 1'b0);
    ring_tail_i        = 8'd1;
    inject_dma_error_q = 1'b1;
    ring_enable_i      = 1'b1;
    pulse_start();
    while (!error_event_o) @(posedge clk_i);
    repeat (2) @(posedge clk_i);
    if ((ring_completed_o != 32'd14) || !ring_status_o[3] || ring_status_o[0] ||
        (error_code_o != 6'd15) || (error_stage_o != 4'd3) ||
        (error_resp_o != 2'd2) || (error_index_o != 8'd0) ||
        (error_addr_o != ring_base_i)) begin
      $fatal(1, "descriptor DMA error attribution mismatch");
    end

    if (backend_accepted != 32'd13) $fatal(1, "unexpected backend job count");
    @(negedge clk_i);
    counter_clear_i = 1'b1;
    @(negedge clk_i);
    counter_clear_i = 1'b0;
    #1;
    if (ring_completed_o != 32'd0) $fatal(1, "ring completion counter clear failed");
    $display("APU-P2 ring scheduler/backend tests passed");
    $finish;
  end

  initial begin
    repeat (10000) @(posedge clk_i);
    $fatal(1, "APU-P2 ring scheduler test timed out in %s state=%0d", s_phase, u_dut.s_state_q);
  end
endmodule
