// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module apb4_dma #(
    parameter int AddrWidth     = 32,
    parameter int DataWidth     = 32,
    parameter int NumChannels   = 4,
    parameter int MaxBurstBeats = 16,
    parameter int FifoDepth     = 16
) (
    // verilog_format: off -- integration ports retain established peripheral endpoint names.
    input  logic          clk_i,
    input  logic          rst_n_i,
    output logic          dma_xfer_done_o,
    output logic          irq_o,
    dma_req_if.dut        hw_trg,
    apb4_if.slave         apb4,
    axi4_if.master        axi4,
    axi4_stream_if.source i2s_tx_axis,
    axi4_stream_if.sink   i2s_rx_axis,
    axi4_stream_if.sink   dvp_rx_axis
    // verilog_format: on
);
  logic [     NumChannels*32-1:0] s_ch_cfg;
  logic [     NumChannels*32-1:0] s_src_addr;
  logic [     NumChannels*32-1:0] s_dst_addr;
  logic [     NumChannels*32-1:0] s_byte_count;
  logic [     NumChannels*32-1:0] s_req_sel;
  logic [     NumChannels*32-1:0] s_burst_cfg;
  logic [        NumChannels-1:0] s_start;
  logic [        NumChannels-1:0] s_suspend;
  logic [        NumChannels-1:0] s_resume;
  logic [        NumChannels-1:0] s_abort;
  logic [        NumChannels-1:0] s_channel_reset;
  logic [      NumChannels*3-1:0] s_event_clear;
  logic                           s_global_reset;
  logic                           s_global_err_clear;
  logic [        NumChannels-1:0] s_busy;
  logic [        NumChannels-1:0] s_suspended;
  logic [        NumChannels-1:0] s_done;
  logic [        NumChannels-1:0] s_aborted;
  logic [        NumChannels-1:0] s_error;
  logic [        NumChannels-1:0] s_stream_last;
  logic [      NumChannels*3-1:0] s_evt_stat;
  logic [     NumChannels*32-1:0] s_err_stat;
  logic [     NumChannels*32-1:0] s_err_addr;
  logic [     NumChannels*32-1:0] s_current_src;
  logic [     NumChannels*32-1:0] s_current_dst;
  logic [     NumChannels*32-1:0] s_remaining;
  logic [     NumChannels*32-1:0] s_bytes_done;
  logic [     NumChannels*32-1:0] s_stall_cycles_lo;
  logic [     NumChannels*32-1:0] s_stall_cycles_hi;
  logic                           s_first_err_valid;
  logic [$clog2(NumChannels)-1:0] s_first_err_channel;
  logic [                   31:0] s_first_err_stat;
  logic [                   31:0] s_first_err_addr;
  logic [                   15:0] s_req_stat;

  dma_reg #(
      .NumChannels  (NumChannels),
      .DataWidth    (DataWidth),
      .MaxBurstBeats(MaxBurstBeats)
  ) u_dma_reg (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .apb4                 (apb4),
      .ch_cfg_o             (s_ch_cfg),
      .src_addr_o           (s_src_addr),
      .dst_addr_o           (s_dst_addr),
      .byte_count_o         (s_byte_count),
      .request_sel_o        (s_req_sel),
      .burst_cfg_o          (s_burst_cfg),
      .start_o              (s_start),
      .suspend_o            (s_suspend),
      .resume_o             (s_resume),
      .abort_o              (s_abort),
      .channel_reset_o      (s_channel_reset),
      .event_clear_o        (s_event_clear),
      .global_reset_o       (s_global_reset),
      .global_error_clear_o (s_global_err_clear),
      .busy_i               (s_busy),
      .suspended_i          (s_suspended),
      .done_i               (s_done),
      .aborted_i            (s_aborted),
      .error_i              (s_error),
      .stream_last_i        (s_stream_last),
      .event_status_i       (s_evt_stat),
      .error_status_i       (s_err_stat),
      .error_addr_i         (s_err_addr),
      .current_src_i        (s_current_src),
      .current_dst_i        (s_current_dst),
      .remaining_i          (s_remaining),
      .bytes_done_i         (s_bytes_done),
      .stall_cycles_lo_i    (s_stall_cycles_lo),
      .stall_cycles_hi_i    (s_stall_cycles_hi),
      .first_error_valid_i  (s_first_err_valid),
      .first_error_channel_i(s_first_err_channel),
      .first_error_status_i (s_first_err_stat[8:0]),
      .first_error_addr_hi_i(s_first_err_addr[31:16]),
      .request_status_i     (s_req_stat),
      .irq_o                (irq_o)
  );

  dma_core #(
      .AddrWidth    (AddrWidth),
      .DataWidth    (DataWidth),
      .NumChannels  (NumChannels),
      .MaxBurstBeats(MaxBurstBeats),
      .FifoDepth    (FifoDepth)
  ) u_dma_core (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .global_reset_i       (s_global_reset),
      .global_error_clear_i (s_global_err_clear),
      .ch_cfg_i             (s_ch_cfg),
      .src_addr_i           (s_src_addr),
      .dst_addr_i           (s_dst_addr),
      .byte_count_i         (s_byte_count),
      .request_sel_i        (s_req_sel),
      .burst_cfg_i          (s_burst_cfg),
      .start_i              (s_start),
      .suspend_i            (s_suspend),
      .resume_i             (s_resume),
      .abort_i              (s_abort),
      .channel_reset_i      (s_channel_reset),
      .event_clear_i        (s_event_clear),
      .busy_o               (s_busy),
      .suspended_o          (s_suspended),
      .done_o               (s_done),
      .aborted_o            (s_aborted),
      .error_o              (s_error),
      .stream_last_o        (s_stream_last),
      .event_status_o       (s_evt_stat),
      .error_status_o       (s_err_stat),
      .error_addr_o         (s_err_addr),
      .current_src_o        (s_current_src),
      .current_dst_o        (s_current_dst),
      .remaining_o          (s_remaining),
      .bytes_done_o         (s_bytes_done),
      .stall_cycles_lo_o    (s_stall_cycles_lo),
      .stall_cycles_hi_o    (s_stall_cycles_hi),
      .first_error_valid_o  (s_first_err_valid),
      .first_error_channel_o(s_first_err_channel),
      .first_error_status_o (s_first_err_stat),
      .first_error_addr_o   (s_first_err_addr),
      .request_status_o     (s_req_stat),
      .xpi_xfer_done_o      (dma_xfer_done_o),
      .req                  (hw_trg),
      .axi4                 (axi4),
      .i2s_tx_axis          (i2s_tx_axis),
      .i2s_rx_axis          (i2s_rx_axis),
      .dvp_rx_axis          (dvp_rx_axis)
  );
endmodule
