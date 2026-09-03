// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apb4_apu (
    // verilog_format: off -- preserve APB, lifecycle, DMA, and stream columns
    input  logic                   clk_i,
    input  logic                   rst_n_i,
    input  logic [1:0]             owner_i,
    input  logic                   owner_lock_i,
    input  logic                   quiesce_i,
    input  logic                   resource_reset_i,
    input  logic [7:0]             bridge_epoch_i,
    input  logic                   i2s_tx_underrun_i,
    input  logic                   i2s_rx_overrun_i,
    apb4_if.slave                  apb4,
    axi4_if.master                 axi4,
    axi4_stream_if.sink            dma_tx_axis,
    axi4_stream_if.source          dma_rx_axis,
    axi4_stream_if.source          i2s_tx_axis,
    axi4_stream_if.sink            i2s_rx_axis,
    output logic                   idle_o,
    output logic                   irq_o
    // verilog_format: on
);
  logic s_soft_reset, s_abort, s_cnt_clear, s_xrun_clear, s_perf_enable;
  logic [ 3:0] s_stream_route;
  logic [15:0] s_stream_watermark;
  logic [31:0] s_read_base, s_read_limit, s_write_base, s_write_limit;
  logic [31:0] s_dma_timeout, s_ring_base, s_ring_coalesce;
  logic [8:0] s_ring_size;
  logic [7:0] s_ring_tail, s_ring_head;
  logic [1:0] s_ring_control;
  logic [31:0] s_stream_stat, s_job_stat, s_ring_stat, s_ring_completed;
  logic [10:0] s_irq_set;
  logic s_input_watermark_evt, s_output_watermark_evt, s_xrun_evt;
  logic s_ring_event, s_ring_err, s_abort_done;
  logic [ 5:0] s_ring_err_code;
  logic [ 3:0] s_ring_err_stage;
  logic [ 1:0] s_ring_err_resp;
  logic [ 7:0] s_ring_err_index;
  logic [31:0] s_ring_err_addr;
  logic        s_fault_valid;
  logic [ 5:0] s_fault_code;
  logic [ 3:0] s_fault_stage;
  logic [ 1:0] s_fault_resp;
  logic [ 7:0] s_fault_index;
  logic [31:0] s_fault_addr;
  logic s_dma_req_valid, s_dma_req_ready, s_dma_req_write;
  logic [31:0] s_dma_req_addr, s_dma_req_bytes;
  logic s_dma_busy, s_dma_done, s_dma_err, s_dma_aborted, s_dma_aborting;
  logic        s_dma_abort;
  logic [ 5:0] s_dma_err_code;
  logic [ 3:0] s_dma_err_stage;
  logic [ 1:0] s_dma_err_resp;
  logic [31:0] s_dma_err_addr;
  logic s_dma_input_pending, s_dma_output_pending;
  logic [63:0] s_dma_read_bytes, s_dma_write_bytes;
  logic [63:0] s_dma_read_stalls, s_dma_write_stalls;
  logic s_scheduler_idle, s_scheduler_aborting, s_stream_idle;
  logic s_dma_admission_block;
  logic s_transport_idle, s_resource_reset_request, s_resource_reset_apply_q;
  logic s_resource_reset_pending_q, s_resource_reset_seen_q;
  logic s_tx_route_apu, s_rx_route_apu;
  logic s_reg_idle_unused, s_backend_job_valid_unused, s_backend_resp_ready_unused;
  logic [1023:0] s_backend_descriptor_unused;
  logic [   7:0] s_backend_index_unused;
  logic [63:0] s_active_cycles_q, s_stream_stalls_q, s_faults_q;

  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_dma_read_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_dma_write_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_apu_tx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_apu_rx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  assign u_apu_tx_axis.tdata = 32'd0;
  assign u_apu_tx_axis.tkeep = 4'hf;
  assign u_apu_tx_axis.tstrb = 4'hf;
  assign u_apu_tx_axis.tlast = 1'b0;
  assign u_apu_tx_axis.tid = '0;
  assign u_apu_tx_axis.tdest = '0;
  assign u_apu_tx_axis.tuser = '0;
  assign u_apu_tx_axis.tvalid = 1'b0;
  assign u_apu_rx_axis.tready = 1'b0;
  assign s_irq_set = {
    1'b0,
    s_xrun_evt,
    s_fault_valid,
    s_output_watermark_evt,
    s_input_watermark_evt,
    s_abort_done,
    3'b000,
    s_ring_event,
    1'b0
  };
  assign s_tx_route_apu = s_stream_route[1:0] == 2'd1;
  assign s_rx_route_apu = s_stream_route[3:2] == 2'd1;
  assign s_transport_idle = s_scheduler_idle && !s_dma_busy && s_stream_idle;
  assign idle_o = s_transport_idle;
  assign s_resource_reset_request = s_resource_reset_pending_q ||
      (resource_reset_i && !s_resource_reset_seen_q);
  assign s_dma_abort = (s_abort || s_resource_reset_request) &&
      !s_ring_stat[`APB4_APU__RING_STATUS_WRITEBACK_PENDING];
  assign s_dma_admission_block = (quiesce_i || s_resource_reset_request) &&
      !s_job_stat[`APB4_APU__JOB_STATUS_BUSY] &&
      !s_ring_stat[`APB4_APU__RING_STATUS_WRITEBACK_PENDING];

  always_comb begin
    s_fault_valid = s_ring_err;
    s_fault_code  = s_ring_err_code;
    s_fault_stage = s_ring_err_stage;
    s_fault_resp  = s_ring_err_resp;
    s_fault_index = s_ring_err_index;
    s_fault_addr  = s_ring_err_addr;
    if (!s_ring_err && s_rx_route_apu && i2s_rx_overrun_i) begin
      s_fault_valid = 1'b1;
      s_fault_code  = `APB4_APU__ERROR_CODE_STREAM_OVERRUN;
      s_fault_stage = `APB4_APU__ERROR_STAGE_KWS_FRONTEND;
      s_fault_resp  = 2'd0;
      s_fault_index = 8'd0;
      s_fault_addr  = 32'd0;
    end else if (!s_ring_err && s_tx_route_apu && i2s_tx_underrun_i) begin
      s_fault_valid = 1'b1;
      s_fault_code  = `APB4_APU__ERROR_CODE_STREAM_UNDERRUN;
      s_fault_stage = `APB4_APU__ERROR_STAGE_DMA_WRITE;
      s_fault_resp  = 2'd0;
      s_fault_index = 8'd0;
      s_fault_addr  = 32'd0;
    end
  end

  apu_reg u_apu_reg (
      .clk_i                  (clk_i),
      .rst_n_i                (rst_n_i),
      .owner_i                (owner_i),
      .owner_lock_i           (owner_lock_i),
      .quiesce_i              (quiesce_i),
      .resource_reset_i       (resource_reset_i),
      .resource_reset_apply_i (s_resource_reset_apply_q),
      .core_idle_i            (idle_o),
      .core_busy_i            (!idle_o),
      .core_aborting_i        (s_dma_aborting || s_scheduler_aborting || s_resource_reset_request),
      .stream_status_i        (s_stream_stat),
      .job_status_i           (s_job_stat),
      .job_input_used_i       (32'd0),
      .job_output_bytes_i     (32'd0),
      .job_frames_i           (32'd0),
      .job_source_info_i      (32'd0),
      .job_cycles_i           (32'd0),
      .job_detail_i           (32'd0),
      .ring_status_i          (s_ring_stat),
      .ring_head_i            (s_ring_head),
      .ring_completed_i       (s_ring_completed),
      .irq_set_i              (s_irq_set),
      .fault_valid_i          (s_fault_valid),
      .fault_code_i           (s_fault_code),
      .fault_stage_i          (s_fault_stage),
      .fault_resp_i           (s_fault_resp),
      .fault_index_i          (s_fault_index),
      .fault_addr_i           (s_fault_addr),
      .fault_detail_i         (32'd0),
      .perf_active_cycles_i   (s_active_cycles_q),
      .perf_input_bytes_i     (s_dma_read_bytes),
      .perf_output_bytes_i    (s_dma_write_bytes),
      .perf_dma_read_stalls_i (s_dma_read_stalls),
      .perf_dma_write_stalls_i(s_dma_write_stalls),
      .perf_stream_stalls_i   (s_stream_stalls_q),
      .perf_faults_i          (s_faults_q),
      .apb4                   (apb4),
      .soft_reset_o           (s_soft_reset),
      .abort_o                (s_abort),
      .counter_clear_o        (s_cnt_clear),
      .perf_enable_o          (s_perf_enable),
      .xrun_clear_o           (s_xrun_clear),
      .stream_route_o         (s_stream_route),
      .stream_watermark_o     (s_stream_watermark),
      .read_base_o            (s_read_base),
      .read_limit_o           (s_read_limit),
      .write_base_o           (s_write_base),
      .write_limit_o          (s_write_limit),
      .dma_timeout_o          (s_dma_timeout),
      .ring_base_o            (s_ring_base),
      .ring_size_o            (s_ring_size),
      .ring_tail_o            (s_ring_tail),
      .ring_control_o         (s_ring_control),
      .ring_coalesce_o        (s_ring_coalesce),
      .idle_o                 (s_reg_idle_unused),
      .irq_o                  (irq_o)
  );

  apu_dma u_apu_dma (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .abort_i         (s_dma_abort),
      .quiesce_i       (s_dma_admission_block),
      .bridge_epoch_i  (bridge_epoch_i),
      .perf_enable_i   (s_perf_enable),
      .counter_clear_i (s_cnt_clear),
      .request_valid_i (s_dma_req_valid),
      .request_ready_o (s_dma_req_ready),
      .request_write_i (s_dma_req_write),
      .request_addr_i  (s_dma_req_addr),
      .request_bytes_i (s_dma_req_bytes),
      .read_base_i     (s_read_base),
      .read_limit_i    (s_read_limit),
      .write_base_i    (s_write_base),
      .write_limit_i   (s_write_limit),
      .timeout_i       (s_dma_timeout),
      .read_axis       (u_dma_read_axis),
      .write_axis      (u_dma_write_axis),
      .busy_o          (s_dma_busy),
      .done_o          (s_dma_done),
      .error_o         (s_dma_err),
      .aborted_o       (s_dma_aborted),
      .aborting_o      (s_dma_aborting),
      .error_code_o    (s_dma_err_code),
      .error_stage_o   (s_dma_err_stage),
      .error_resp_o    (s_dma_err_resp),
      .error_addr_o    (s_dma_err_addr),
      .input_pending_o (s_dma_input_pending),
      .output_pending_o(s_dma_output_pending),
      .read_bytes_o    (s_dma_read_bytes),
      .write_bytes_o   (s_dma_write_bytes),
      .read_stalls_o   (s_dma_read_stalls),
      .write_stalls_o  (s_dma_write_stalls),
      .axi4            (axi4)
  );

  apu_ring_scheduler u_ring_scheduler (
      .clk_i                 (clk_i),
      .rst_n_i               (rst_n_i),
      .soft_reset_i          (s_soft_reset || s_resource_reset_apply_q),
      .counter_clear_i       (s_cnt_clear),
      .abort_i               (s_abort || s_resource_reset_request),
      .quiesce_i             (quiesce_i || s_resource_reset_request),
      .start_i               (1'b0),
      .ring_base_i           (s_ring_base),
      .ring_size_i           (s_ring_size),
      .ring_tail_i           (s_ring_tail),
      .ring_enable_i         (s_ring_control[0]),
      .stop_on_error_i       (s_ring_control[1]),
      .coalesce_count_i      (s_ring_coalesce[7:0]),
      .coalesce_timeout_i    (s_ring_coalesce[31:16]),
      .dma_request_valid_o   (s_dma_req_valid),
      .dma_request_ready_i   (s_dma_req_ready),
      .dma_request_write_o   (s_dma_req_write),
      .dma_request_addr_o    (s_dma_req_addr),
      .dma_request_bytes_o   (s_dma_req_bytes),
      .dma_read_axis         (u_dma_read_axis),
      .dma_write_axis        (u_dma_write_axis),
      .dma_done_i            (s_dma_done),
      .dma_error_i           (s_dma_err),
      .dma_error_code_i      (s_dma_err_code),
      .dma_error_stage_i     (s_dma_err_stage),
      .dma_error_resp_i      (s_dma_err_resp),
      .dma_error_addr_i      (s_dma_err_addr),
      .backend_job_valid_o   (s_backend_job_valid_unused),
      .backend_job_ready_i   (1'b0),
      .backend_descriptor_o  (s_backend_descriptor_unused),
      .backend_index_o       (s_backend_index_unused),
      .backend_result_valid_i(1'b0),
      .backend_result_ready_o(s_backend_resp_ready_unused),
      .backend_result_error_i(1'b0),
      .backend_result_code_i (6'd0),
      .backend_result_stage_i(4'd0),
      .backend_result_resp_i (2'd0),
      .backend_input_used_i  (32'd0),
      .backend_output_bytes_i(32'd0),
      .backend_frames_i      (32'd0),
      .backend_source_info_i (32'd0),
      .backend_cycles_i      (32'd0),
      .backend_detail_i      (32'd0),
      .job_status_o          (s_job_stat),
      .ring_status_o         (s_ring_stat),
      .ring_head_o           (s_ring_head),
      .ring_completed_o      (s_ring_completed),
      .ring_event_o          (s_ring_event),
      .error_event_o         (s_ring_err),
      .error_code_o          (s_ring_err_code),
      .error_stage_o         (s_ring_err_stage),
      .error_resp_o          (s_ring_err_resp),
      .error_index_o         (s_ring_err_index),
      .error_addr_o          (s_ring_err_addr),
      .abort_done_o          (s_abort_done),
      .aborting_o            (s_scheduler_aborting),
      .idle_o                (s_scheduler_idle)
  );

  apu_stream_router u_stream_router (
      .clk_i                 (clk_i),
      .rst_n_i               (rst_n_i),
      .flush_i               (s_soft_reset || s_resource_reset_apply_q),
      .counter_clear_i       (s_cnt_clear),
      .xrun_clear_i          (s_xrun_clear),
      .tx_route_apu_i        (s_tx_route_apu),
      .rx_route_apu_i        (s_rx_route_apu),
      .tx_session_active_i   (1'b0),
      .rx_session_active_i   (1'b0),
      .rx_high_watermark_i   (s_stream_watermark[7:0]),
      .tx_low_watermark_i    (s_stream_watermark[15:8]),
      .tx_underrun_i         (i2s_tx_underrun_i),
      .rx_overrun_i          (i2s_rx_overrun_i),
      .dma_tx_axis           (dma_tx_axis),
      .dma_rx_axis           (dma_rx_axis),
      .i2s_tx_axis           (i2s_tx_axis),
      .i2s_rx_axis           (i2s_rx_axis),
      .apu_tx_axis           (u_apu_tx_axis),
      .apu_rx_axis           (u_apu_rx_axis),
      .status_o              (s_stream_stat),
      .input_watermark_evt_o (s_input_watermark_evt),
      .output_watermark_evt_o(s_output_watermark_evt),
      .stream_xrun_evt_o     (s_xrun_evt),
      .idle_o                (s_stream_idle)
  );

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_resource_reset_pending_q <= 1'b0;
      s_resource_reset_seen_q    <= 1'b0;
      s_resource_reset_apply_q   <= 1'b0;
    end else begin
      s_resource_reset_apply_q <= 1'b0;
      if (resource_reset_i && !s_resource_reset_seen_q) begin
        s_resource_reset_pending_q <= 1'b1;
        s_resource_reset_seen_q    <= 1'b1;
      end
      if (s_resource_reset_request && s_transport_idle) begin
        s_resource_reset_pending_q <= 1'b0;
        s_resource_reset_apply_q   <= 1'b1;
      end
      if (!resource_reset_i && !s_resource_reset_pending_q) begin
        s_resource_reset_seen_q <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i || s_soft_reset || s_resource_reset_apply_q || s_cnt_clear) begin
      s_active_cycles_q <= 64'd0;
      s_stream_stalls_q <= 64'd0;
      s_faults_q        <= 64'd0;
    end else begin
      if (s_perf_enable && !idle_o && !(&s_active_cycles_q)) begin
        s_active_cycles_q <= s_active_cycles_q + 1'b1;
      end
      if (s_perf_enable && ((i2s_tx_axis.tvalid && !i2s_tx_axis.tready) ||
           (i2s_rx_axis.tvalid && !i2s_rx_axis.tready)) && !(&s_stream_stalls_q)) begin
        s_stream_stalls_q <= s_stream_stalls_q + 1'b1;
      end
      if (s_perf_enable && s_fault_valid && !(&s_faults_q)) begin
        s_faults_q <= s_faults_q + 1'b1;
      end
    end
  end

  logic s_unused_pending;
  assign s_unused_pending = s_dma_input_pending ^ s_dma_output_pending ^ s_dma_aborted ^
      s_reg_idle_unused ^ s_backend_job_valid_unused ^ s_backend_resp_ready_unused ^
      ^s_backend_descriptor_unused ^ ^s_backend_index_unused ^ ^s_ring_coalesce[15:8];
endmodule
