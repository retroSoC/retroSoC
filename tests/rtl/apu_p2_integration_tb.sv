`timescale 1ns / 1ps

`include "apu_define.svh"
`include "axi4_define.svh"

module apu_p2_integration_tb;
  localparam logic [31:0] RingBase = 32'h0000_1000;

  logic        clk_i = 1'b0;
  logic        clk_hp_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        rst_hp_n_i = 1'b0;
  logic        soft_reset_i = 1'b0;
  logic        abort_i = 1'b0;
  logic        resource_reset_i = 1'b0;
  logic        resource_reset_pending_q = 1'b0;
  logic        resource_reset_apply_q = 1'b0;
  logic        resource_reset_seen_q = 1'b0;
  logic        bridge_clear_i = 1'b0;
  logic        bridge_clear_busy;
  logic        target_guard_clear_busy;
  logic        target_guard_abort;
  logic        effective_abort;
  logic        effective_quiesce;
  logic        dma_admission_block;
  logic        quiesce_i = 1'b0;
  logic        start_i = 1'b0;
  logic        ring_enable_i = 1'b0;
  logic        stop_on_error_i = 1'b0;
  logic [31:0] ring_base_i = RingBase;
  logic [ 8:0] ring_size_i = 9'd2;
  logic [ 7:0] ring_tail_i = 8'd0;
  logic [ 7:0] bridge_epoch_i;
  logic        fault_read_i = 1'b0;
  logic        fault_payload_read_i = 1'b0;
  logic        fault_payload_write_i = 1'b0;
  logic        fault_result_write_i = 1'b0;
  logic        fault_owner_write_i = 1'b0;
  logic        suppress_read_last_i = 1'b0;
  logic        hold_addresses_i = 1'b0;
  logic        hold_read_data_i = 1'b0;
  logic        hold_write_data_i = 1'b0;
  logic        hold_write_response_i = 1'b0;
  logic        hold_backend_i = 1'b0;
  logic        backend_error_i = 1'b0;
  logic [ 5:0] backend_code_i = 6'd0;
  logic [ 3:0] backend_stage_i = 4'd0;
  logic [ 1:0] backend_resp_i = 2'd0;
  logic        sdio_read_request_i = 1'b0;
  logic        usb_read_request_i = 1'b0;
  logic [31:0] sdio_read_addr_i = 32'd0;
  logic [31:0] usb_read_addr_i = 32'd0;
  logic [ 7:0] missing_last_epoch_q;

  logic        direct_start_i = 1'b0;
  logic [31:0] direct_source_i = 32'h0000_2000;
  logic [31:0] direct_destination_i = 32'h0000_2400;
  logic [31:0] direct_bytes_i = 32'd4;
  logic direct_busy, direct_done, direct_error;
  logic direct_done_seen_q;
  logic direct_request_valid, direct_request_ready, direct_request_write;
  logic [31:0] direct_request_addr, direct_request_bytes;
  logic scheduler_request_valid, scheduler_request_ready, scheduler_request_write;
  logic [31:0] scheduler_request_addr, scheduler_request_bytes;
  logic dma_request_valid, dma_request_ready, dma_request_write;
  logic dma_backend_owner_q;
  logic select_scheduler_request;
  logic [31:0] dma_request_addr, dma_request_bytes;
  logic dma_busy, dma_done, dma_error, dma_aborted, dma_aborting;
  logic [ 5:0] dma_error_code;
  logic [ 3:0] dma_error_stage;
  logic [ 1:0] dma_error_resp;
  logic [31:0] dma_error_addr;
  logic backend_job_valid, backend_job_ready;
  logic [1023:0] backend_descriptor;
  logic [   7:0] backend_index;
  logic backend_result_valid, backend_result_ready;
  logic       backend_result_error;
  logic [5:0] backend_result_code;
  logic [3:0] backend_result_stage;
  logic [1:0] backend_result_resp;
  logic [31:0] backend_input_used, backend_output_bytes, backend_frames;
  logic [31:0] backend_source_info, backend_cycles, backend_detail;
  logic [31:0] backend_accepted;
  logic [31:0] job_status, ring_status, ring_completed;
  logic [7:0] ring_head;
  logic ring_event, error_event, abort_done, scheduler_aborting, scheduler_idle;
  logic [ 5:0] ring_error_code;
  logic [ 3:0] ring_error_stage;
  logic [ 1:0] ring_error_resp;
  logic [ 7:0] ring_error_index;
  logic [31:0] ring_error_addr;

  logic [31:0] memory           [0:4095];
  logic [31:0] read_addr_q, write_addr_q;
  logic [7:0] read_len_q, write_len_q, read_beat_q, write_beat_q;
  logic read_active_q, write_active_q, bvalid_q;
  logic        [ 1:0] bresp_q;
  logic        [15:0] cycle_q;
  logic               result_retired_q;
  logic               owner_write_seen_q;
  int unsigned        aw_count_q;
  string              s_phase;

  function automatic logic is_descriptor_addr(input logic [31:0] addr_i);
    return (addr_i >= RingBase) && (addr_i < (RingBase + 32'd256));
  endfunction

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi4 (
      clk_i,
      rst_n_i
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) gateway_axi4 (
      clk_i,
      rst_n_i
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) guarded_axi4 (
      clk_hp_i,
      rst_hp_n_i
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) memory_axi4 (
      clk_hp_i,
      rst_hp_n_i
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) sdio_axi4 (
      clk_i,
      rst_n_i
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) usb_axi4 (
      clk_i,
      rst_n_i
  );
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
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) scheduler_read_axis (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) scheduler_write_axis (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) direct_read_axis (
      clk_i,
      rst_n_i
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) direct_write_axis (
      clk_i,
      rst_n_i
  );

  always #5 clk_i = ~clk_i;
  always #7 clk_hp_i = ~clk_hp_i;

  assign effective_abort = abort_i || resource_reset_i || resource_reset_pending_q;
  assign effective_quiesce = quiesce_i || resource_reset_i || resource_reset_pending_q;
  assign dma_admission_block = effective_quiesce &&
      !job_status[`APB4_APU__JOB_STATUS_BUSY] &&
      !ring_status[`APB4_APU__RING_STATUS_WRITEBACK_PENDING] && !direct_busy;

  assign select_scheduler_request = scheduler_request_valid;
  assign dma_request_valid = scheduler_request_valid || direct_request_valid;
  assign dma_request_write = select_scheduler_request ? scheduler_request_write : direct_request_write;
  assign dma_request_addr = select_scheduler_request ? scheduler_request_addr : direct_request_addr;
  assign dma_request_bytes = select_scheduler_request ? scheduler_request_bytes : direct_request_bytes;
  assign direct_request_ready = !select_scheduler_request && dma_request_ready;
  assign scheduler_request_ready = select_scheduler_request && dma_request_ready;

  assign scheduler_read_axis.tdata = dma_read_axis.tdata;
  assign scheduler_read_axis.tkeep = dma_read_axis.tkeep;
  assign scheduler_read_axis.tstrb = dma_read_axis.tstrb;
  assign scheduler_read_axis.tlast = dma_read_axis.tlast;
  assign scheduler_read_axis.tid = dma_read_axis.tid;
  assign scheduler_read_axis.tdest = dma_read_axis.tdest;
  assign scheduler_read_axis.tuser = dma_read_axis.tuser;
  assign scheduler_read_axis.tvalid = !dma_backend_owner_q && dma_read_axis.tvalid;
  assign direct_read_axis.tdata = dma_read_axis.tdata;
  assign direct_read_axis.tkeep = dma_read_axis.tkeep;
  assign direct_read_axis.tstrb = dma_read_axis.tstrb;
  assign direct_read_axis.tlast = dma_read_axis.tlast;
  assign direct_read_axis.tid = dma_read_axis.tid;
  assign direct_read_axis.tdest = dma_read_axis.tdest;
  assign direct_read_axis.tuser = dma_read_axis.tuser;
  assign direct_read_axis.tvalid = dma_backend_owner_q && dma_read_axis.tvalid;
  assign dma_read_axis.tready = dma_backend_owner_q ? direct_read_axis.tready :
      scheduler_read_axis.tready;

  assign dma_write_axis.tdata = dma_backend_owner_q ? direct_write_axis.tdata :
      scheduler_write_axis.tdata;
  assign dma_write_axis.tkeep = dma_backend_owner_q ? direct_write_axis.tkeep :
      scheduler_write_axis.tkeep;
  assign dma_write_axis.tstrb = dma_backend_owner_q ? direct_write_axis.tstrb :
      scheduler_write_axis.tstrb;
  assign dma_write_axis.tlast = dma_backend_owner_q ? direct_write_axis.tlast :
      scheduler_write_axis.tlast;
  assign dma_write_axis.tid = dma_backend_owner_q ? direct_write_axis.tid : scheduler_write_axis.tid;
  assign dma_write_axis.tdest = dma_backend_owner_q ? direct_write_axis.tdest :
      scheduler_write_axis.tdest;
  assign dma_write_axis.tuser = dma_backend_owner_q ? direct_write_axis.tuser :
      scheduler_write_axis.tuser;
  assign dma_write_axis.tvalid = dma_backend_owner_q ? direct_write_axis.tvalid :
      scheduler_write_axis.tvalid;
  assign direct_write_axis.tready = dma_backend_owner_q && dma_write_axis.tready;
  assign scheduler_write_axis.tready = !dma_backend_owner_q && dma_write_axis.tready;

  assign sdio_axi4.awid = '0;
  assign sdio_axi4.awaddr = '0;
  assign sdio_axi4.awlen = '0;
  assign sdio_axi4.awsize = 3'd2;
  assign sdio_axi4.awburst = `AXI4_BURST_TYPE_INCR;
  assign sdio_axi4.awlock = 1'b0;
  assign sdio_axi4.awcache = '0;
  assign sdio_axi4.awprot = `AXI4_PROT_DATA;
  assign sdio_axi4.awqos = '0;
  assign sdio_axi4.awregion = '0;
  assign sdio_axi4.awuser = '0;
  assign sdio_axi4.awvalid = 1'b0;
  assign sdio_axi4.wdata = '0;
  assign sdio_axi4.wstrb = '0;
  assign sdio_axi4.wlast = 1'b0;
  assign sdio_axi4.wuser = '0;
  assign sdio_axi4.wvalid = 1'b0;
  assign sdio_axi4.bready = 1'b1;
  assign sdio_axi4.arid = '0;
  assign sdio_axi4.araddr = sdio_read_addr_i;
  assign sdio_axi4.arlen = '0;
  assign sdio_axi4.arsize = 3'd2;
  assign sdio_axi4.arburst = `AXI4_BURST_TYPE_INCR;
  assign sdio_axi4.arlock = 1'b0;
  assign sdio_axi4.arcache = '0;
  assign sdio_axi4.arprot = `AXI4_PROT_DATA;
  assign sdio_axi4.arqos = '0;
  assign sdio_axi4.arregion = '0;
  assign sdio_axi4.aruser = '0;
  assign sdio_axi4.arvalid = sdio_read_request_i;
  assign sdio_axi4.rready = 1'b1;

  assign usb_axi4.awid = '0;
  assign usb_axi4.awaddr = '0;
  assign usb_axi4.awlen = '0;
  assign usb_axi4.awsize = 3'd2;
  assign usb_axi4.awburst = `AXI4_BURST_TYPE_INCR;
  assign usb_axi4.awlock = 1'b0;
  assign usb_axi4.awcache = '0;
  assign usb_axi4.awprot = `AXI4_PROT_DATA;
  assign usb_axi4.awqos = '0;
  assign usb_axi4.awregion = '0;
  assign usb_axi4.awuser = '0;
  assign usb_axi4.awvalid = 1'b0;
  assign usb_axi4.wdata = '0;
  assign usb_axi4.wstrb = '0;
  assign usb_axi4.wlast = 1'b0;
  assign usb_axi4.wuser = '0;
  assign usb_axi4.wvalid = 1'b0;
  assign usb_axi4.bready = 1'b1;
  assign usb_axi4.arid = '0;
  assign usb_axi4.araddr = usb_read_addr_i;
  assign usb_axi4.arlen = '0;
  assign usb_axi4.arsize = 3'd2;
  assign usb_axi4.arburst = `AXI4_BURST_TYPE_INCR;
  assign usb_axi4.arlock = 1'b0;
  assign usb_axi4.arcache = '0;
  assign usb_axi4.arprot = `AXI4_PROT_DATA;
  assign usb_axi4.arqos = '0;
  assign usb_axi4.arregion = '0;
  assign usb_axi4.aruser = '0;
  assign usb_axi4.arvalid = usb_read_request_i;
  assign usb_axi4.rready = 1'b1;

  assign memory_axi4.arready = !hold_addresses_i && !read_active_q && cycle_q[0];
  assign memory_axi4.rid = 1'b0;
  assign memory_axi4.rdata = memory[((read_addr_q-RingBase)>>2)+read_beat_q];
  assign memory_axi4.rresp = ((fault_read_i && is_descriptor_addr(
      read_addr_q
  )) || (fault_payload_read_i && !is_descriptor_addr(
      read_addr_q
  ))) ? `AXI4_RESP_SLAVE_ERROR : `AXI4_RESP_OKAY;
  assign memory_axi4.rlast = !suppress_read_last_i && (read_beat_q == read_len_q);
  assign memory_axi4.ruser = 1'b0;
  assign memory_axi4.rvalid = read_active_q && !hold_read_data_i;
  assign memory_axi4.awready = !hold_addresses_i && !write_active_q && !bvalid_q && cycle_q[0];
  assign memory_axi4.wready = !hold_write_data_i && write_active_q && (cycle_q[1:0] != 2'b00);
  assign memory_axi4.bid = 1'b0;
  assign memory_axi4.bresp = bresp_q;
  assign memory_axi4.buser = 1'b0;
  assign memory_axi4.bvalid = bvalid_q && !hold_write_response_i;

  hp_axi4_mux3 #(
      .RoundRobin       (1'b1),
      .Client0EpochAware(1'b1)
  ) u_gateway_a (
      .clk_i,
      .rst_n_i,
      .epoch_i(bridge_epoch_i),
      .icache (axi4),
      .dcache (sdio_axi4),
      .mmio   (usb_axi4),
      .axi4   (gateway_axi4)
  );

  axi4_async_bridge u_bridge (
      .src_clk_i   (clk_i),
      .src_rst_n_i (rst_n_i),
      .dst_clk_i   (clk_hp_i),
      .dst_rst_n_i (rst_hp_n_i),
      .clear_i     (bridge_clear_i),
      .clear_busy_o(bridge_clear_busy),
      .epoch_o     (bridge_epoch_i),
      .src_axi4    (gateway_axi4),
      .dst_axi4    (guarded_axi4)
  );

  axi4_target_guard #(
      .AddrWidth (32),
      .DataWidth (32),
      .IdWidth   (1),
      .UserWidth (1),
      .ReadDepth (4),
      .WriteDepth(2)
  ) u_target_guard (
      .clk_i          (clk_hp_i),
      .rst_n_i        (rst_hp_n_i),
      .clear_i        (bridge_clear_i),
      .timeout_i      (32'd256),
      .clear_busy_o   (target_guard_clear_busy),
      .abort_o        (target_guard_abort),
      .abort_done_i   (target_guard_abort),
      .timeout_valid_o(),
      .isolated_o     (),
      .timeout_write_o(),
      .timeout_id_o   (),
      .timeout_addr_o (),
      .source         (guarded_axi4),
      .sink           (memory_axi4)
  );

  apu_dma u_dma (
      .clk_i,
      .rst_n_i,
      .abort_i         (effective_abort && !ring_status[`APB4_APU__RING_STATUS_WRITEBACK_PENDING]),
      .quiesce_i       (dma_admission_block),
      .bridge_epoch_i,
      .perf_enable_i   (1'b1),
      .counter_clear_i (1'b0),
      .request_valid_i (dma_request_valid),
      .request_ready_o (dma_request_ready),
      .request_write_i (dma_request_write),
      .request_addr_i  (dma_request_addr),
      .request_bytes_i (dma_request_bytes),
      .read_base_i     (RingBase),
      .read_limit_i    (32'h0000_2fff),
      .write_base_i    (RingBase),
      .write_limit_i   (32'h0000_2fff),
      .timeout_i       (32'd24),
      .read_axis       (dma_read_axis),
      .write_axis      (dma_write_axis),
      .busy_o          (dma_busy),
      .done_o          (dma_done),
      .error_o         (dma_error),
      .aborted_o       (dma_aborted),
      .aborting_o      (dma_aborting),
      .error_code_o    (dma_error_code),
      .error_stage_o   (dma_error_stage),
      .error_resp_o    (dma_error_resp),
      .error_addr_o    (dma_error_addr),
      .input_pending_o (),
      .output_pending_o(),
      .read_bytes_o    (),
      .write_bytes_o   (),
      .read_stalls_o   (),
      .write_stalls_o  (),
      .axi4
  );

  apu_ring_scheduler u_scheduler (
      .clk_i,
      .rst_n_i,
      .soft_reset_i          (soft_reset_i || resource_reset_apply_q),
      .counter_clear_i       (1'b0),
      .abort_i               (effective_abort),
      .quiesce_i             (effective_quiesce),
      .start_i,
      .ring_base_i,
      .ring_size_i,
      .ring_tail_i,
      .ring_enable_i,
      .stop_on_error_i,
      .coalesce_count_i      (8'd2),
      .coalesce_timeout_i    (16'd8),
      .dma_request_valid_o   (scheduler_request_valid),
      .dma_request_ready_i   (scheduler_request_ready),
      .dma_request_write_o   (scheduler_request_write),
      .dma_request_addr_o    (scheduler_request_addr),
      .dma_request_bytes_o   (scheduler_request_bytes),
      .dma_read_axis         (scheduler_read_axis),
      .dma_write_axis        (scheduler_write_axis),
      .dma_done_i            (dma_done),
      .dma_error_i           (dma_error),
      .dma_error_code_i      (dma_error_code),
      .dma_error_stage_i     (dma_error_stage),
      .dma_error_resp_i      (dma_error_resp),
      .dma_error_addr_i      (dma_error_addr),
      .backend_job_valid_o   (backend_job_valid),
      .backend_job_ready_i   (backend_job_ready),
      .backend_descriptor_o  (backend_descriptor),
      .backend_index_o       (backend_index),
      .backend_result_valid_i(backend_result_valid),
      .backend_result_ready_o(backend_result_ready),
      .backend_result_error_i(backend_result_error),
      .backend_result_code_i (backend_result_code),
      .backend_result_stage_i(backend_result_stage),
      .backend_result_resp_i (backend_result_resp),
      .backend_input_used_i  (backend_input_used),
      .backend_output_bytes_i(backend_output_bytes),
      .backend_frames_i      (backend_frames),
      .backend_source_info_i (backend_source_info),
      .backend_cycles_i      (backend_cycles),
      .backend_detail_i      (backend_detail),
      .job_status_o          (job_status),
      .ring_status_o         (ring_status),
      .ring_head_o           (ring_head),
      .ring_completed_o      (ring_completed),
      .ring_event_o          (ring_event),
      .error_event_o         (error_event),
      .error_code_o          (ring_error_code),
      .error_stage_o         (ring_error_stage),
      .error_resp_o          (ring_error_resp),
      .error_index_o         (ring_error_index),
      .error_addr_o          (ring_error_addr),
      .abort_done_o          (abort_done),
      .aborting_o            (scheduler_aborting),
      .idle_o                (scheduler_idle)
  );

  apu_p2_transport_backend u_transport_backend (
      .clk_i,
      .rst_n_i,
      .abort_i              (effective_abort),
      .direct_start_i,
      .direct_source_i,
      .direct_destination_i,
      .direct_bytes_i,
      .job_valid_i          (backend_job_valid),
      .job_ready_o          (backend_job_ready),
      .descriptor_i         (backend_descriptor),
      .index_i              (backend_index),
      .hold_result_i        (hold_backend_i),
      .inject_result_error_i(backend_error_i),
      .inject_result_code_i (backend_code_i),
      .inject_result_stage_i(backend_stage_i),
      .inject_result_resp_i (backend_resp_i),
      .result_valid_o       (backend_result_valid),
      .result_ready_i       (backend_result_ready),
      .result_error_o       (backend_result_error),
      .result_code_o        (backend_result_code),
      .result_stage_o       (backend_result_stage),
      .result_resp_o        (backend_result_resp),
      .input_used_o         (backend_input_used),
      .output_bytes_o       (backend_output_bytes),
      .frames_o             (backend_frames),
      .source_info_o        (backend_source_info),
      .cycles_o             (backend_cycles),
      .detail_o             (backend_detail),
      .accepted_jobs_o      (backend_accepted),
      .request_valid_o      (direct_request_valid),
      .request_ready_i      (direct_request_ready),
      .request_write_o      (direct_request_write),
      .request_addr_o       (direct_request_addr),
      .request_bytes_o      (direct_request_bytes),
      .read_axis            (direct_read_axis),
      .write_axis           (direct_write_axis),
      .dma_done_i           (dma_done),
      .dma_error_i          (dma_error),
      .dma_aborted_i        (dma_aborted),
      .dma_error_code_i     (dma_error_code),
      .dma_error_stage_i    (dma_error_stage),
      .dma_error_resp_i     (dma_error_resp),
      .busy_o               (direct_busy),
      .direct_done_o        (direct_done),
      .direct_error_o       (direct_error)
  );

  task automatic hard_reset;
    begin
      rst_n_i    = 1'b0;
      rst_hp_n_i = 1'b0;
      repeat (3) @(posedge clk_i);
      @(negedge clk_i);
      rst_n_i    = 1'b1;
      rst_hp_n_i = 1'b1;
      repeat (3) @(posedge clk_i);
    end
  endtask

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

  task automatic pulse_direct_start;
    begin
      @(negedge clk_i);
      direct_start_i = 1'b1;
      @(negedge clk_i);
      direct_start_i = 1'b0;
    end
  endtask

  task automatic pulse_bridge_clear;
    begin
      @(negedge clk_i);
      bridge_clear_i = 1'b1;
      wait (bridge_clear_busy);
      @(negedge clk_i);
      bridge_clear_i = 1'b0;
      wait (!bridge_clear_busy);
    end
  endtask

  task automatic pulse_resource_reset;
    begin
      @(negedge clk_i);
      resource_reset_i = 1'b1;
      @(negedge clk_i);
      resource_reset_i = 1'b0;
    end
  endtask

  task automatic clear_memory;
    for (int unsigned word_index = 0; word_index < 4096; word_index++) begin
      memory[word_index] = 32'd0;
    end
  endtask

  task automatic make_descriptor(input int unsigned descriptor_i);
    begin
      for (int unsigned word_index = 0; word_index < 32; word_index++) begin
        memory[(descriptor_i*32)+word_index] = 32'd0;
      end
      memory[descriptor_i*32]      = 32'd1 << `APB4_APU__DESCRIPTOR_CONTROL_OWN;
      memory[(descriptor_i*32)+2]  = 32'h0000_1800;
      memory[(descriptor_i*32)+3]  = 32'd65;
      memory[(descriptor_i*32)+4]  = 32'h0000_1c00;
      memory[(descriptor_i*32)+5]  = 32'd128;
      memory[(descriptor_i*32)+16] = 32'h1234_5678;
      memory[(descriptor_i*32)+17] = 32'h9abc_def0;
      for (int unsigned word_index = 0; word_index < 17; word_index++) begin
        memory[((32'h0000_1800-RingBase)>>2)+word_index] = 32'h5100_0000 + word_index;
        memory[((32'h0000_1c00-RingBase)>>2)+word_index] = 32'hdead_beef;
      end
    end
  endtask

  task automatic wait_idle;
    int unsigned timeout;
    begin
      timeout = 0;
      while ((!scheduler_idle || dma_busy || direct_busy ||
              (u_gateway_a.s_state_q != 3'd0) ||
              (u_target_guard.s_read_state_q != 3'd0) ||
              (u_target_guard.s_write_state_q != 3'd0)) && (timeout < 4000)) begin
        @(posedge clk_i);
        timeout++;
      end
      if (!scheduler_idle || dma_busy || direct_busy || (u_gateway_a.s_state_q != 3'd0) ||
          (u_target_guard.s_read_state_q != 3'd0) ||
          (u_target_guard.s_write_state_q != 3'd0)) begin
        $fatal(1, "integrated APU did not become idle in %s", s_phase);
      end
    end
  endtask

  task automatic issue_peer_read(input logic usb_i, input logic [31:0] addr_i);
    begin
      @(negedge clk_i);
      if (usb_i) begin
        usb_read_addr_i    = addr_i;
        usb_read_request_i = 1'b1;
      end else begin
        sdio_read_addr_i    = addr_i;
        sdio_read_request_i = 1'b1;
      end
      if (usb_i) begin
        do @(posedge clk_i); while (!usb_axi4.arready);
      end else begin
        do @(posedge clk_i); while (!sdio_axi4.arready);
      end
      @(negedge clk_i);
      if (usb_i) usb_read_request_i = 1'b0;
      else sdio_read_request_i = 1'b0;
      if (usb_i) begin
        do @(posedge clk_i); while (!usb_axi4.rvalid);
        if ((usb_axi4.rresp != `AXI4_RESP_OKAY) || !usb_axi4.rlast) begin
          $fatal(1, "USB2 traffic failed after missing RLAST recovery");
        end
      end else begin
        do @(posedge clk_i); while (!sdio_axi4.rvalid);
        if ((sdio_axi4.rresp != `AXI4_RESP_OKAY) || !sdio_axi4.rlast) begin
          $fatal(1, "SDIO0 traffic failed after missing RLAST recovery");
        end
      end
    end
  endtask

  task automatic run_ring_lifecycle_case(input logic resource_reset_case_i,
                                         input logic [3:0] state_i);
    int unsigned timeout;
    begin
      ring_enable_i       = 1'b0;
      quiesce_i           = 1'b0;
      resource_reset_i    = 1'b0;
      hold_addresses_i    = 1'b0;
      hold_read_data_i    = 1'b0;
      hold_write_data_i   = 1'b0;
      hold_write_response_i = 1'b0;
      hold_backend_i      = 1'b0;
      suppress_read_last_i = 1'b0;
      hard_reset();
      clear_memory();
      make_descriptor(0);
      ring_base_i   = RingBase;
      ring_size_i   = 9'd2;
      ring_tail_i   = 8'd1;
      ring_enable_i = 1'b1;
      pulse_start();
      wait (u_scheduler.s_state_q == state_i);
      if (resource_reset_case_i) begin
        s_phase = $sformatf("resource reset drain state %0d", state_i);
      end else begin
        s_phase = $sformatf("ownership quiesce drain state %0d", state_i);
      end
      @(negedge clk_i);
      if (resource_reset_case_i) resource_reset_i = 1'b1;
      else quiesce_i = 1'b1;
      @(negedge clk_i);
      if (resource_reset_case_i) resource_reset_i = 1'b0;

      if (resource_reset_case_i) begin
        timeout = 0;
        while (!resource_reset_apply_q && (timeout < 4000)) begin
          @(posedge clk_i);
          #1;
          timeout++;
          if (resource_reset_apply_q && memory[0][31]) begin
            $fatal(1, "resource reset applied before OWN clear in state %0d", state_i);
          end
        end
        if (!resource_reset_apply_q) begin
          $fatal(1, "resource reset did not drain state %0d", state_i);
        end
      end else begin
        wait_idle();
      end

      if (memory[0][31] || (memory[1] == 32'd0) || !result_retired_q ||
          !owner_write_seen_q) begin
        $fatal(1, "lifecycle drain lost ordered descriptor writeback state %0d reset=%0d",
               state_i, resource_reset_case_i);
      end
      if (!resource_reset_case_i) begin
        @(negedge clk_i);
        quiesce_i = 1'b0;
      end
    end
  endtask

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      dma_backend_owner_q <= 1'b0;
    end else if (dma_request_valid && dma_request_ready) begin
      dma_backend_owner_q <= !select_scheduler_request;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      direct_done_seen_q <= 1'b0;
    end else if (direct_start_i) begin
      direct_done_seen_q <= 1'b0;
    end else if (direct_done) begin
      direct_done_seen_q <= 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      resource_reset_pending_q <= 1'b0;
      resource_reset_apply_q   <= 1'b0;
      resource_reset_seen_q    <= 1'b0;
    end else begin
      resource_reset_apply_q <= 1'b0;
      if (resource_reset_i && !resource_reset_seen_q) begin
        resource_reset_pending_q <= 1'b1;
        resource_reset_seen_q    <= 1'b1;
      end
      if (resource_reset_pending_q && scheduler_idle && !dma_busy && !direct_busy &&
          (u_gateway_a.s_state_q == 3'd0) && (u_target_guard.s_read_state_q == 3'd0) &&
          (u_target_guard.s_write_state_q == 3'd0) && !bridge_clear_busy &&
          !target_guard_clear_busy) begin
        resource_reset_pending_q <= 1'b0;
        resource_reset_apply_q   <= 1'b1;
      end
      if (!resource_reset_i && !resource_reset_pending_q) begin
        resource_reset_seen_q <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_hp_i or negedge rst_hp_n_i) begin
    if (!rst_hp_n_i) begin
      read_addr_q        <= 32'd0;
      write_addr_q       <= 32'd0;
      read_len_q         <= 8'd0;
      write_len_q        <= 8'd0;
      read_beat_q        <= 8'd0;
      write_beat_q       <= 8'd0;
      read_active_q      <= 1'b0;
      write_active_q     <= 1'b0;
      bvalid_q           <= 1'b0;
      bresp_q            <= `AXI4_RESP_OKAY;
      cycle_q            <= 16'd0;
      result_retired_q   <= 1'b0;
      owner_write_seen_q <= 1'b0;
      aw_count_q         <= 0;
    end else if (bridge_clear_i) begin
      read_active_q  <= 1'b0;
      write_active_q <= 1'b0;
      bvalid_q       <= 1'b0;
    end else begin
      cycle_q <= cycle_q + 1'b1;
      if (memory_axi4.arvalid && memory_axi4.arready) begin
        read_addr_q   <= memory_axi4.araddr;
        read_len_q    <= memory_axi4.arlen;
        read_beat_q   <= 8'd0;
        read_active_q <= 1'b1;
        if (is_descriptor_addr(memory_axi4.araddr) && (memory_axi4.araddr[6:0] == 7'd0)) begin
          result_retired_q <= 1'b0;
        end
      end
      if (memory_axi4.rvalid && memory_axi4.rready) begin
        if (memory_axi4.rlast || (read_beat_q == read_len_q)) read_active_q <= 1'b0;
        else read_beat_q <= read_beat_q + 1'b1;
      end
      if (memory_axi4.awvalid && memory_axi4.awready) begin
        write_addr_q   <= memory_axi4.awaddr;
        write_len_q    <= memory_axi4.awlen;
        write_beat_q   <= 8'd0;
        write_active_q <= 1'b1;
        aw_count_q     <= aw_count_q + 1;
        if (is_descriptor_addr(
                memory_axi4.awaddr
            ) && (memory_axi4.awaddr[6:0] == 7'd0) && !result_retired_q) begin
          $fatal(1, "OWN clear address issued before result response retired");
        end
      end
      if (memory_axi4.wvalid && memory_axi4.wready) begin
        for (int unsigned byte_index = 0; byte_index < 4; byte_index++) begin
          if (memory_axi4.wstrb[byte_index]) begin
            memory[((write_addr_q-RingBase)>>2)+write_beat_q][byte_index*8+:8] <=
                memory_axi4.wdata[byte_index*8+:8];
          end
        end
        if (is_descriptor_addr(
                write_addr_q
            ) && (write_addr_q[6:0] == 7'd0) && !result_retired_q) begin
          $fatal(1, "OWN cleared before result response retired");
        end
        if (memory_axi4.wlast) begin
          write_active_q <= 1'b0;
          bvalid_q       <= 1'b1;
          if (fault_owner_write_i && is_descriptor_addr(
                  write_addr_q
              ) && (write_addr_q[6:0] == 7'd0)) begin
            bresp_q <= `AXI4_RESP_SLAVE_ERROR;
          end else if (fault_result_write_i && is_descriptor_addr(
                  write_addr_q
              ) && (write_addr_q[6:0] != 7'd0)) begin
            bresp_q <= `AXI4_RESP_SLAVE_ERROR;
          end else if (fault_payload_write_i && !is_descriptor_addr(write_addr_q)) begin
            bresp_q <= `AXI4_RESP_SLAVE_ERROR;
          end else begin
            bresp_q <= `AXI4_RESP_OKAY;
          end
          if (is_descriptor_addr(write_addr_q) && (write_addr_q[6:0] == 7'd0)) begin
            owner_write_seen_q <= 1'b1;
          end
        end else begin
          write_beat_q <= write_beat_q + 1'b1;
        end
      end
      if (memory_axi4.bvalid && memory_axi4.bready) begin
        bvalid_q <= 1'b0;
        if ((bresp_q == `AXI4_RESP_OKAY) && is_descriptor_addr(
                write_addr_q
            ) && (write_addr_q[6:0] != 7'd0) && ((write_addr_q + (({24'd0, write_len_q} + 1'b1) << 2
                                                  )) == (RingBase + 32'd128))) begin
          result_retired_q <= 1'b1;
        end
      end
    end
  end

  initial begin
    clear_memory();
    s_phase = "direct randomized transport backend";
    hard_reset();
    for (int unsigned transfer = 0; transfer < 12; transfer++) begin
      automatic int unsigned length = ((transfer * 29) % 95) + 1;
      automatic int unsigned words = (length + 3) / 4;
      for (int unsigned word_index = 0; word_index < words; word_index++) begin
        memory[((direct_source_i-RingBase)>>2)+word_index] =
            32'h600d_0000 ^ (transfer << 8) ^ word_index;
        memory[((direct_destination_i-RingBase)>>2)+word_index] = 32'hdead_beef;
      end
      direct_bytes_i = length;
      pulse_direct_start();
      wait (direct_done);
      if (direct_error || direct_busy) $fatal(1, "direct backend transfer failed");
      for (int unsigned byte_index = 0; byte_index < length; byte_index++) begin
        if (memory[((direct_destination_i-RingBase)>>2)+(byte_index/4)]
                  [(byte_index%4)*8+:8] !==
            memory[((direct_source_i-RingBase)>>2)+(byte_index/4)][(byte_index%4)*8+:8]) begin
          $fatal(1, "direct backend copy mismatch transfer=%0d byte=%0d", transfer, byte_index);
        end
      end
    end

    s_phase        = "direct backend abort";
    direct_bytes_i = 32'd16;
    pulse_direct_start();
    wait (dma_busy && read_active_q);
    pulse_abort();
    wait (direct_done);
    if (!direct_error || direct_busy || dma_busy) $fatal(1, "direct backend abort did not retire");

    s_phase = "deferred resource reset drain";
    hard_reset();
    hold_read_data_i = 1'b1;
    direct_bytes_i   = 32'd16;
    pulse_direct_start();
    wait (dma_busy && read_active_q);
    pulse_resource_reset();
    repeat (3) begin
      @(posedge clk_i);
      if (resource_reset_apply_q) $fatal(1, "resource reset applied before DMA drain");
    end
    hold_read_data_i = 1'b0;
    wait (resource_reset_apply_q);
    @(posedge clk_i);
    if (resource_reset_pending_q || dma_busy || direct_busy || !scheduler_idle) begin
      $fatal(1, "resource reset did not retire after transport drain");
    end

    s_phase = "successful ordered writeback";
    hard_reset();
    clear_memory();
    make_descriptor(0);
    ring_tail_i   = 8'd1;
    ring_enable_i = 1'b1;
    pulse_start();
    while (ring_completed != 32'd1) @(posedge clk_i);
    wait_idle();
    if (memory[0][31] || !memory[1][0] || !owner_write_seen_q || !result_retired_q ||
        (memory[10] != 32'd65) || (memory[11] != 32'd65) || (ring_head != 8'd1)) begin
      $fatal(1, "ordered integrated descriptor writeback failed");
    end
    for (int unsigned byte_index = 0; byte_index < 65; byte_index++) begin
      if (memory[((32'h0000_1c00-RingBase)>>2)+(byte_index/4)][(byte_index%4)*8+:8] !==
          memory[((32'h0000_1800-RingBase)>>2)+(byte_index/4)][(byte_index%4)*8+:8]) begin
        $fatal(1, "ring backend payload copy mismatch at byte %0d", byte_index);
      end
    end

    for (int unsigned lifecycle_state = 4; lifecycle_state <= 11; lifecycle_state++) begin
      run_ring_lifecycle_case(1'b1, 4'(lifecycle_state));
      run_ring_lifecycle_case(1'b0, 4'(lifecycle_state));
    end

    s_phase = "randomized ring payload transport";
    for (int unsigned job = 0; job < 8; job++) begin
      automatic int unsigned length = ((job * 37) % 95) + 1;
      automatic int unsigned words = (length + 3) / 4;
      hard_reset();
      clear_memory();
      make_descriptor(0);
      memory[3] = length;
      memory[5] = length + 32'd7;
      for (int unsigned word_index = 0; word_index < words; word_index++) begin
        memory[((32'h0000_1800-RingBase)>>2)+word_index] = 32'h7100_0000 ^ (job << 8) ^ word_index;
      end
      ring_tail_i   = 8'd1;
      ring_enable_i = 1'b1;
      pulse_start();
      wait (ring_completed == 32'd1);
      wait_idle();
      if (memory[0][31] || !memory[1][0] || (memory[10] != length) || (memory[11] != length)) begin
        $fatal(1, "randomized ring result mismatch job=%0d", job);
      end
      for (int unsigned byte_index = 0; byte_index < length; byte_index++) begin
        if (memory[((32'h0000_1c00-RingBase)>>2)+(byte_index/4)][(byte_index%4)*8+:8] !==
            memory[((32'h0000_1800-RingBase)>>2)+(byte_index/4)][(byte_index%4)*8+:8]) begin
          $fatal(1, "randomized ring payload mismatch job=%0d byte=%0d", job, byte_index);
        end
      end
    end

    s_phase     = "unowned abort containment";
    memory[32]  = 32'd0;
    memory[33]  = 32'hfeed_cafe;
    ring_tail_i = 8'd0;
    wait (u_scheduler.s_state_q == 4'd3);
    @(negedge clk_i);
    abort_i = 1'b1;
    @(negedge clk_i);
    abort_i = 1'b0;
    wait (abort_done);
    wait_idle();
    if ((memory[32] != 32'd0) || (memory[33] != 32'hfeed_cafe) || (ring_head != 8'd1)) begin
      $fatal(1, "abort mutated an unowned descriptor");
    end

    s_phase       = "simultaneous fetch completion and abort";
    ring_enable_i = 1'b0;
    hard_reset();
    clear_memory();
    make_descriptor(0);
    ring_enable_i = 1'b1;
    ring_tail_i   = 8'd1;
    pulse_start();
    wait (dma_done && (u_scheduler.s_state_q == 4'd2));
    @(negedge clk_i);
    abort_i = 1'b1;
    @(negedge clk_i);
    abort_i = 1'b0;
    wait (abort_done);
    wait_idle();

    s_phase = "result writeback response fault";
    hard_reset();
    clear_memory();
    make_descriptor(0);
    fault_result_write_i = 1'b1;
    ring_enable_i        = 1'b1;
    ring_tail_i          = 8'd1;
    pulse_start();
    wait (ring_status[`APB4_APU__RING_STATUS_ERROR]);
    wait_idle();
    if (!memory[0][31] || (ring_completed != 32'd0) || (ring_head != 8'd0) ||
        (ring_error_code != 6'd16)) begin
      $fatal(1, "result writeback fault released descriptor ownership");
    end
    fault_result_write_i = 1'b0;

    s_phase              = "owner writeback response fault";
    hard_reset();
    clear_memory();
    make_descriptor(0);
    fault_owner_write_i = 1'b1;
    ring_enable_i       = 1'b1;
    ring_tail_i         = 8'd1;
    pulse_start();
    wait (error_event);
    wait_idle();
    if ((ring_completed != 32'd0) || (ring_head != 8'd0) || (ring_error_code != 6'd16)) begin
      $fatal(1, "owner writeback fault advanced ring state");
    end
    fault_owner_write_i = 1'b0;

    s_phase             = "descriptor read response fault";
    hard_reset();
    clear_memory();
    make_descriptor(0);
    fault_read_i  = 1'b1;
    ring_enable_i = 1'b1;
    ring_tail_i   = 8'd1;
    pulse_start();
    wait (error_event);
    wait_idle();
    if ((ring_error_code != 6'd15) || (ring_error_stage != 4'd3) ||
        (ring_error_resp != `AXI4_RESP_SLAVE_ERROR)) begin
      $fatal(1, "descriptor read response fault attribution failed");
    end
    fault_read_i = 1'b0;

    s_phase      = "payload read response fault";
    hard_reset();
    clear_memory();
    make_descriptor(0);
    fault_payload_read_i = 1'b1;
    ring_enable_i        = 1'b1;
    ring_tail_i          = 8'd1;
    pulse_start();
    wait (error_event);
    wait_idle();
    if (memory[0][31] || !memory[1][1] || (memory[1][8:3] != 6'd15) ||
        (ring_error_code != 6'd15)) begin
      $fatal(1, "payload read fault was not published through descriptor writeback");
    end
    fault_payload_read_i = 1'b0;

    s_phase              = "payload write response fault";
    hard_reset();
    clear_memory();
    make_descriptor(0);
    fault_payload_write_i = 1'b1;
    ring_enable_i         = 1'b1;
    ring_tail_i           = 8'd1;
    pulse_start();
    wait (error_event);
    wait_idle();
    if (memory[0][31] || !memory[1][1] || (memory[1][8:3] != 6'd16) ||
        (ring_error_code != 6'd16)) begin
      $fatal(1, "payload write fault was not published through descriptor writeback");
    end
    fault_payload_write_i = 1'b0;

    s_phase               = "explicit bridge flush recovery";
    hard_reset();
    clear_memory();
    make_descriptor(0);
    ring_enable_i = 1'b1;
    ring_tail_i   = 8'd1;
    pulse_start();
    wait (read_active_q && dma_busy);
    pulse_bridge_clear();
    wait (ring_status[`APB4_APU__RING_STATUS_ERROR]);
    wait_idle();
    if ((ring_error_code != 6'd15) || (ring_error_resp != `AXI4_RESP_DECODE_ERROR)) begin
      $fatal(1, "bridge epoch did not terminate active descriptor DMA");
    end

    s_phase = "unilateral HP reset recovery";
    hard_reset();
    clear_memory();
    direct_bytes_i   = 32'd16;
    hold_read_data_i = 1'b1;
    pulse_direct_start();
    wait (read_active_q && dma_busy);
    @(negedge clk_hp_i);
    rst_hp_n_i = 1'b0;
    repeat (3) @(posedge clk_i);
    @(negedge clk_hp_i);
    rst_hp_n_i       = 1'b1;
    hold_read_data_i = 1'b0;
    wait (direct_done_seen_q);
    if (!direct_error || dma_busy || (u_gateway_a.s_state_q != 2'd0)) begin
      $fatal(1, "unilateral HP reset did not recover the APU Gateway path");
    end
    direct_bytes_i = 32'd4;
    pulse_direct_start();
    wait (direct_done);
    if (direct_error) $fatal(1, "Gateway A did not accept work after HP reset recovery");

    s_phase = "missing terminal RLAST recovery";
    hard_reset();
    missing_last_epoch_q = bridge_epoch_i;
    suppress_read_last_i = 1'b1;
    direct_bytes_i       = 32'd8;
    pulse_direct_start();
    wait (direct_done);
    if (!direct_error || dma_busy) $fatal(1, "missing RLAST did not terminate the DMA");
    suppress_read_last_i = 1'b0;
    wait_idle();
    if (bridge_epoch_i != missing_last_epoch_q) begin
      $fatal(1, "missing RLAST recovery required an external bridge epoch");
    end
    direct_bytes_i = 32'd4;
    pulse_direct_start();
    wait (direct_done);
    if (direct_error) $fatal(1, "APU traffic failed after missing RLAST recovery");
    memory[((32'h0000_2800-RingBase)>>2)] = 32'h5d10_0001;
    memory[((32'h0000_2804-RingBase)>>2)] = 32'h5b20_0001;
    issue_peer_read(1'b0, 32'h0000_2800);
    issue_peer_read(1'b1, 32'h0000_2804);
    wait_idle();

    s_phase = "ring arithmetic validation";
    hard_reset();
    ring_base_i   = 32'hffff_ff80;
    ring_size_i   = 9'd2;
    ring_tail_i   = 8'd1;
    ring_enable_i = 1'b1;
    pulse_start();
    wait (error_event);
    if ((ring_error_code != 6'd2) || dma_busy) $fatal(1, "ring extent overflow was accepted");
    hard_reset();
    ring_base_i   = RingBase;
    ring_size_i   = 9'd2;
    ring_tail_i   = 8'd2;
    ring_enable_i = 1'b1;
    pulse_start();
    wait (error_event);
    if ((ring_error_code != 6'd2) || dma_busy) $fatal(1, "out-of-range ring tail was accepted");
    hard_reset();
    ring_base_i   = RingBase;
    ring_size_i   = 9'd2;
    ring_tail_i   = 8'd1;
    ring_enable_i = 1'b1;
    force u_scheduler.s_head_q = 8'd3;
    pulse_start();
    wait (error_event);
    if ((ring_error_code != 6'd2) || dma_busy)
      $fatal(1, "stale out-of-range ring head was accepted");
    release u_scheduler.s_head_q;

    $display("APU-P2 integrated DMA/ring/backend tests passed");
    $finish;
  end

  initial begin
    repeat (60000) @(posedge clk_i);
    $fatal(1, "APU-P2 integration test timed out in %s scheduler=%0d dma=%0d", s_phase,
           u_scheduler.s_state_q, u_dma.s_state_q);
  end

  logic s_unused_status;
  assign s_unused_status = ring_event ^ scheduler_aborting ^ dma_aborted ^ dma_aborting ^
      ^ring_error_index ^ ^ring_error_addr ^ ^job_status ^ ^backend_accepted ^ ^aw_count_q;
endmodule
