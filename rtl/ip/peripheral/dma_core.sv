// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"
`include "axi4_define.svh"

module dma_core #(
    parameter int AddrWidth         = 32,
    parameter int DataWidth         = 32,
    parameter int NumChannels       = 4,
    parameter int ChannelIndexWidth = (NumChannels > 1) ? $clog2(NumChannels) : 1,
    parameter int MaxBurstBeats     = 16,
    parameter int FifoDepth         = 16
) (
    // verilog_format: off -- channel vectors are kept aligned with the register-bank ABI.
    input  logic                           clk_i,
    input  logic                           rst_n_i,
    input  logic                           global_reset_i,
    input  logic                           global_error_clear_i,
    input  logic [NumChannels*32-1:0]      ch_cfg_i,
    input  logic [NumChannels*32-1:0]      src_addr_i,
    input  logic [NumChannels*32-1:0]      dst_addr_i,
    input  logic [NumChannels*32-1:0]      byte_count_i,
    input  logic [NumChannels*32-1:0]      request_sel_i,
    input  logic [NumChannels*32-1:0]      burst_cfg_i,
    input  logic [NumChannels-1:0]         start_i,
    input  logic [NumChannels-1:0]         suspend_i,
    input  logic [NumChannels-1:0]         resume_i,
    input  logic [NumChannels-1:0]         abort_i,
    input  logic [NumChannels-1:0]         channel_reset_i,
    input  logic [NumChannels*3-1:0]       event_clear_i,
    output logic [NumChannels-1:0]         busy_o,
    output logic [NumChannels-1:0]         suspended_o,
    output logic [NumChannels-1:0]         done_o,
    output logic [NumChannels-1:0]         aborted_o,
    output logic [NumChannels-1:0]         error_o,
    output logic [NumChannels-1:0]         stream_last_o,
    output logic [NumChannels*3-1:0]       event_status_o,
    output logic [NumChannels*32-1:0]      error_status_o,
    output logic [NumChannels*32-1:0]      error_addr_o,
    output logic [NumChannels*32-1:0]      current_src_o,
    output logic [NumChannels*32-1:0]      current_dst_o,
    output logic [NumChannels*32-1:0]      remaining_o,
    output logic [NumChannels*32-1:0]      bytes_done_o,
    output logic [NumChannels*32-1:0]      stall_cycles_lo_o,
    output logic [NumChannels*32-1:0]      stall_cycles_hi_o,
    output logic                           first_error_valid_o,
    output logic [ChannelIndexWidth-1:0]   first_error_channel_o,
    output logic [8:0]                     first_error_status_o,
    output logic [15:0]                    first_error_addr_hi_o,
    output logic [15:0]                    request_status_o,
    output logic                           xpi_xfer_done_o,
    dma_req_if.dut                         req,
    axi4_if.master                         axi4,
    axi4_stream_if.source                  i2s_tx_axis,
    axi4_stream_if.sink                    i2s_rx_axis,
    axi4_stream_if.sink                    dvp_rx_axis,
    axi4_stream_if.source                  crypto_in_axis,
    axi4_stream_if.sink                    crypto_out_axis
    // verilog_format: on
);
  import dma_pkg::*;

  localparam int FifoCountWidth = $clog2(FifoDepth) + 1;
  localparam logic [31:0] WordBytes = 32'd4;

  logic [      NumChannels-1:0][               2:0] s_cfg_kind;
  logic [      NumChannels-1:0][               1:0] s_cfg_width;
  logic [      NumChannels-1:0]                     s_cfg_src_increment;
  logic [      NumChannels-1:0]                     s_cfg_dst_increment;
  logic [      NumChannels-1:0][               1:0] s_cfg_priority;
  logic [      NumChannels-1:0][              31:0] s_cfg_src_addr;
  logic [      NumChannels-1:0][              31:0] s_cfg_dst_addr;
  logic [      NumChannels-1:0][              31:0] s_cfg_byte_count;
  logic [      NumChannels-1:0][               3:0] s_cfg_request;
  logic [      NumChannels-1:0][               4:0] s_cfg_burst;

  logic [      NumChannels-1:0]                     s_busy_q;
  logic [      NumChannels-1:0]                     s_suspended_q;
  logic [      NumChannels-1:0]                     s_done_q;
  logic [      NumChannels-1:0]                     s_aborted_q;
  logic [      NumChannels-1:0]                     s_err_q;
  logic [      NumChannels-1:0]                     s_stream_last_q;
  logic [      NumChannels-1:0]                     s_abort_q;
  logic [      NumChannels-1:0]                     s_suspend_req_q;
  logic [      NumChannels-1:0]                     s_stream_tx_stop_q;
  logic [      NumChannels-1:0]                     s_half_seen_q;
  logic [      NumChannels-1:0]                     s_evt_done_q;
  logic [      NumChannels-1:0]                     s_evt_half_q;
  logic [      NumChannels-1:0]                     s_evt_err_q;
  logic [      NumChannels-1:0][               2:0] s_kind_q;
  logic [      NumChannels-1:0][               3:0] s_req_q;
  logic [      NumChannels-1:0][               1:0] s_priority_q;
  logic [      NumChannels-1:0][               4:0] s_burst_q;
  logic [      NumChannels-1:0]                     s_src_increment_q;
  logic [      NumChannels-1:0]                     s_dst_increment_q;
  logic [      NumChannels-1:0][              31:0] s_src_base_q;
  logic [      NumChannels-1:0][              31:0] s_dst_base_q;
  logic [      NumChannels-1:0][              31:0] s_len_q;
  logic [      NumChannels-1:0][              31:0] s_read_issued_q;
  logic [      NumChannels-1:0][              31:0] s_write_issued_q;
  logic [      NumChannels-1:0][              31:0] s_stream_accepted_q;
  logic [      NumChannels-1:0][              31:0] s_bytes_done_q;
  logic [      NumChannels-1:0][              63:0] s_stall_cycles_q;
  logic [      NumChannels-1:0][               3:0] s_err_code_q;
  logic [      NumChannels-1:0][               1:0] s_err_resp_q;
  logic [      NumChannels-1:0]                     s_err_read_q;
  logic [      NumChannels-1:0][              31:0] s_err_addr_q;

  logic [      NumChannels-1:0]                     s_fifo_flush;
  logic [      NumChannels-1:0]                     s_fifo_push;
  logic [      NumChannels-1:0]                     s_fifo_pop;
  logic [      NumChannels-1:0]                     s_fifo_full;
  logic [      NumChannels-1:0]                     s_fifo_empty;
  logic [      NumChannels-1:0][FifoCountWidth-1:0] s_fifo_count;
  logic [      NumChannels-1:0][              31:0] s_fifo_wdata;
  logic [      NumChannels-1:0][              31:0] s_fifo_rdata;

  logic [                 15:0]                     s_req_ready;
  logic [      NumChannels-1:0]                     s_start_valid;
  logic [      NumChannels-1:0][               3:0] s_start_err_code;

  logic [      NumChannels-1:0]                     s_read_candidate;
  logic [      NumChannels-1:0][               4:0] s_read_candidate_beats;
  logic [      NumChannels-1:0]                     s_write_candidate;
  logic [      NumChannels-1:0][               4:0] s_write_candidate_beats;
  logic [      NumChannels-1:0]                     s_read_rr_request;
  logic [      NumChannels-1:0]                     s_write_rr_request;
  logic [      NumChannels-1:0]                     s_read_rr_grant;
  logic [      NumChannels-1:0]                     s_write_rr_grant;
  logic [ChannelIndexWidth-1:0]                     s_read_rr_selected;
  logic [ChannelIndexWidth-1:0]                     s_write_rr_selected;
  logic                                             s_read_rr_valid;
  logic                                             s_write_rr_valid;
  logic [                  1:0]                     s_read_highest_priority;
  logic [                  1:0]                     s_write_highest_priority;

  logic                                             s_axi_read_start_valid;
  logic                                             s_axi_read_start_ready;
  logic [                 31:0]                     s_axi_read_start_addr;
  logic [                  4:0]                     s_axi_read_start_beats;
  logic                                             s_axi_read_start_fixed;
  logic                                             s_axi_read_busy;
  logic                                             s_axi_read_beat_valid;
  logic                                             s_axi_read_beat_ready;
  logic [                 31:0]                     s_axi_read_data;
  logic [                  1:0]                     s_axi_read_resp;
  logic                                             s_axi_read_last;
  logic                                             s_axi_read_expected_last;
  logic                                             s_axi_read_id_error;
  logic                                             s_axi_read_done;

  logic                                             s_axi_write_start_valid;
  logic                                             s_axi_write_start_ready;
  logic [                 31:0]                     s_axi_write_start_addr;
  logic [                  4:0]                     s_axi_write_start_beats;
  logic                                             s_axi_write_start_fixed;
  logic                                             s_axi_write_busy;
  logic                                             s_axi_write_data_valid;
  logic                                             s_axi_write_data_ready;
  logic [                 31:0]                     s_axi_write_data;
  logic [                  3:0]                     s_axi_write_strb;
  logic                                             s_axi_write_done;
  logic [                  1:0]                     s_axi_write_resp;
  logic                                             s_axi_write_id_error;

  logic                                             s_read_owner_valid_q;
  logic [ChannelIndexWidth-1:0]                     s_read_owner_q;
  logic [                  4:0]                     s_read_beats_q;
  logic [                  4:0]                     s_read_seen_q;
  logic                                             s_read_err_q;
  logic                                             s_write_owner_valid_q;
  logic [ChannelIndexWidth-1:0]                     s_write_owner_q;
  logic [                 31:0]                     s_write_bytes_q;

  logic                                             s_i2s_tx_channel_valid;
  logic [ChannelIndexWidth-1:0]                     s_i2s_tx_channel;
  logic                                             s_i2s_rx_channel_valid;
  logic [ChannelIndexWidth-1:0]                     s_i2s_rx_channel;
  logic                                             s_dvp_rx_channel_valid;
  logic [ChannelIndexWidth-1:0]                     s_dvp_rx_channel;
  logic                                             s_crypto_in_channel_valid;
  logic [ChannelIndexWidth-1:0]                     s_crypto_in_channel;
  logic                                             s_crypto_out_channel_valid;
  logic [ChannelIndexWidth-1:0]                     s_crypto_out_channel;
  logic                                             s_i2s_tx_fire;
  logic                                             s_i2s_rx_fire;
  logic                                             s_dvp_rx_fire;
  logic                                             s_crypto_in_fire;
  logic                                             s_crypto_out_fire;
  logic                                             s_stream_rx_keep_err;
  logic [ChannelIndexWidth-1:0]                     s_stream_rx_err_channel;
  logic [      NumChannels-1:0]                     s_progress;
  logic [      NumChannels-1:0]                     s_read_owns_channel;
  logic [      NumChannels-1:0]                     s_write_owns_channel;
  logic [      NumChannels-1:0]                     s_stream_tx_valid;

  logic                                             s_first_err_valid_q;
  logic [ChannelIndexWidth-1:0]                     s_first_err_channel_q;
  logic [                  8:0]                     s_first_err_stat_q;
  logic [                 15:0]                     s_first_err_addr_hi_q;

  function automatic logic is_apb_address(input logic [31:0] addr_i);
    is_apb_address = `SOC_ADDR_IS_APB4_PERIPH(addr_i) || `SOC_ADDR_IS_APB4_SYSTEM(addr_i);
  endfunction

  function automatic int unsigned min_unsigned(input int unsigned left_i,
                                               input int unsigned right_i);
    min_unsigned = (left_i < right_i) ? left_i : right_i;
  endfunction

  function automatic logic [8:0] channel_error_status(
      input logic [3:0] error_code_i, input logic [1:0] response_i, input logic error_read_i,
      input logic stream_last_i);
    channel_error_status = {stream_last_i, 1'b0, error_read_i, response_i, error_code_i};
  endfunction

`ifndef SYNTHESIS
  initial begin
    if ((AddrWidth != 32) || (DataWidth != 32) || (NumChannels < 2) ||
        (MaxBurstBeats < 1) || (MaxBurstBeats > 16) || (FifoDepth < MaxBurstBeats) ||
        ((FifoDepth & (FifoDepth - 1)) != 0)) begin
      $fatal(1, "dma_core: MVP requires 32-bit AXI4, 2+ channels, and a power-of-two FIFO");
    end
  end
`endif

  for (genvar channel = 0; channel < NumChannels; channel++) begin : gen_channel_fifo
    fifo #(
        .DATA_WIDTH  (32),
        .BUFFER_DEPTH(FifoDepth)
    ) u_data_fifo (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .flush_i(s_fifo_flush[channel]),
        .push_i (s_fifo_push[channel]),
        .full_o (s_fifo_full[channel]),
        .dat_i  (s_fifo_wdata[channel]),
        .pop_i  (s_fifo_pop[channel]),
        .empty_o(s_fifo_empty[channel]),
        .dat_o  (s_fifo_rdata[channel]),
        .cnt_o  (s_fifo_count[channel])
    );
  end

  round_robin_arbiter #(
      .CLIENTS(NumChannels)
  ) u_read_round_robin_arbiter (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .advance_i (s_axi_read_start_valid && s_axi_read_start_ready),
      .request_i (s_read_rr_request),
      .grant_o   (s_read_rr_grant),
      .selected_o(s_read_rr_selected),
      .valid_o   (s_read_rr_valid)
  );

  round_robin_arbiter #(
      .CLIENTS(NumChannels)
  ) u_write_round_robin_arbiter (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .advance_i (s_axi_write_start_valid && s_axi_write_start_ready),
      .request_i (s_write_rr_request),
      .grant_o   (s_write_rr_grant),
      .selected_o(s_write_rr_selected),
      .valid_o   (s_write_rr_valid)
  );

  dma_axi4_master #(
      .AddrWidth    (AddrWidth),
      .DataWidth    (DataWidth),
      .MaxBurstBeats(MaxBurstBeats)
  ) u_dma_axi4_master (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .read_start_valid_i  (s_axi_read_start_valid),
      .read_start_ready_o  (s_axi_read_start_ready),
      .read_addr_i         (s_axi_read_start_addr),
      .read_beats_i        (s_axi_read_start_beats),
      .read_fixed_i        (s_axi_read_start_fixed),
      .read_busy_o         (s_axi_read_busy),
      .read_beat_valid_o   (s_axi_read_beat_valid),
      .read_beat_ready_i   (s_axi_read_beat_ready),
      .read_data_o         (s_axi_read_data),
      .read_resp_o         (s_axi_read_resp),
      .read_last_o         (s_axi_read_last),
      .read_expected_last_o(s_axi_read_expected_last),
      .read_id_error_o     (s_axi_read_id_error),
      .read_done_o         (s_axi_read_done),
      .write_start_valid_i (s_axi_write_start_valid),
      .write_start_ready_o (s_axi_write_start_ready),
      .write_addr_i        (s_axi_write_start_addr),
      .write_beats_i       (s_axi_write_start_beats),
      .write_fixed_i       (s_axi_write_start_fixed),
      .write_busy_o        (s_axi_write_busy),
      .write_data_valid_i  (s_axi_write_data_valid),
      .write_data_ready_o  (s_axi_write_data_ready),
      .write_data_i        (s_axi_write_data),
      .write_strb_i        (s_axi_write_strb),
      .write_done_o        (s_axi_write_done),
      .write_resp_o        (s_axi_write_resp),
      .write_id_error_o    (s_axi_write_id_error),
      .axi4                (axi4)
  );

  always_comb begin
    s_req_ready                         = '0;
    s_req_ready[DMA_REQUEST_SOFTWARE]   = 1'b1;
    s_req_ready[DMA_REQUEST_I2S_TX]     = req.i2s_tx_proc;
    s_req_ready[DMA_REQUEST_I2S_RX]     = req.i2s_rx_proc;
    s_req_ready[DMA_REQUEST_QSPI_TX]    = req.qspi_tx_proc;
    s_req_ready[DMA_REQUEST_QSPI_RX]    = req.qspi_rx_proc;
    s_req_ready[DMA_REQUEST_UART_TX]    = req.uart_tx_proc;
    s_req_ready[DMA_REQUEST_UART_RX]    = req.uart_rx_proc;
    s_req_ready[DMA_REQUEST_I2C0_TX]    = req.i2c0_tx_proc;
    s_req_ready[DMA_REQUEST_I2C0_RX]    = req.i2c0_rx_proc;
    s_req_ready[DMA_REQUEST_I2C1_TX]    = req.i2c1_tx_proc;
    s_req_ready[DMA_REQUEST_I2C1_RX]    = req.i2c1_rx_proc;
    s_req_ready[DMA_REQUEST_DVP_RX]     = 1'b1;
    s_req_ready[DMA_REQUEST_CRYPTO_IN]  = req.crypto_in_proc;
    s_req_ready[DMA_REQUEST_CRYPTO_OUT] = req.crypto_out_proc;
  end
  assign request_status_o = s_req_ready;

  always_comb begin
    for (int unsigned channel = 0; channel < NumChannels; channel++) begin
      s_cfg_kind[channel]          = ch_cfg_i[(channel*32)+:3];
      s_cfg_width[channel]         = ch_cfg_i[(channel*32)+4+:2];
      s_cfg_src_increment[channel] = ch_cfg_i[(channel*32)+6];
      s_cfg_dst_increment[channel] = ch_cfg_i[(channel*32)+7];
      s_cfg_priority[channel]      = ch_cfg_i[(channel*32)+8+:2];
      s_cfg_src_addr[channel]      = src_addr_i[(channel*32)+:32];
      s_cfg_dst_addr[channel]      = dst_addr_i[(channel*32)+:32];
      s_cfg_byte_count[channel]    = byte_count_i[(channel*32)+:32];
      s_cfg_request[channel]       = request_sel_i[(channel*32)+:4];
      s_cfg_burst[channel]         = burst_cfg_i[(channel*32)+:5];
    end
  end

  always_comb begin
    for (int unsigned channel = 0; channel < NumChannels; channel++) begin
      logic endpoint_busy;

      endpoint_busy = 1'b0;
      for (int unsigned other = 0; other < NumChannels; other++) begin
        if ((other != channel) && s_busy_q[other]) begin
          if ((s_cfg_kind[channel] == DMA_KIND_MM_TO_STREAM) &&
              (s_kind_q[other] == DMA_KIND_MM_TO_STREAM) &&
              (s_req_q[other] == s_cfg_request[channel]) &&
              ((s_cfg_request[channel] == DMA_REQUEST_I2S_TX) ||
               (s_cfg_request[channel] == DMA_REQUEST_CRYPTO_IN))) begin
            endpoint_busy = 1'b1;
          end
          if ((s_cfg_kind[channel] == DMA_KIND_STREAM_TO_MM) &&
              (s_kind_q[other] == DMA_KIND_STREAM_TO_MM) &&
              (s_req_q[other] == s_cfg_request[channel])) begin
            endpoint_busy = 1'b1;
          end
        end
      end

      s_start_valid[channel]    = 1'b1;
      s_start_err_code[channel] = DMA_ERROR_CONFIG;
      if ((s_cfg_width[channel] != DMA_WIDTH_32) || (s_cfg_byte_count[channel] == 32'd0) ||
          (s_cfg_byte_count[channel][1:0] != 2'b00) ||
          (s_cfg_burst[channel] == 5'd0) ||
          (s_cfg_burst[channel] > 5'(MaxBurstBeats))) begin
        s_start_valid[channel] = 1'b0;
        s_start_err_code[channel] = (s_cfg_byte_count[channel][1:0] != 2'b00)
                                          ? DMA_ERROR_ALIGNMENT
                                          : DMA_ERROR_CONFIG;
      end else begin
        unique case (s_cfg_kind[channel])
          DMA_KIND_MM_TO_MM: begin
            if ((s_cfg_src_addr[channel] == 32'd0) || (s_cfg_dst_addr[channel] == 32'd0) ||
                (s_cfg_src_addr[channel][1:0] != 2'b00) ||
                (s_cfg_dst_addr[channel][1:0] != 2'b00) ||
                (s_cfg_request[channel] == DMA_REQUEST_I2S_TX) ||
                (s_cfg_request[channel] == DMA_REQUEST_I2S_RX) ||
                (s_cfg_request[channel] == DMA_REQUEST_DVP_RX) ||
                (s_cfg_request[channel] == DMA_REQUEST_CRYPTO_IN) ||
                (s_cfg_request[channel] == DMA_REQUEST_CRYPTO_OUT)) begin
              s_start_valid[channel] = 1'b0;
              s_start_err_code[channel] =
                  ((s_cfg_src_addr[channel][1:0] != 2'b00) ||
                   (s_cfg_dst_addr[channel][1:0] != 2'b00))
                      ? DMA_ERROR_ALIGNMENT
                      : DMA_ERROR_CONFIG;
            end
          end
          DMA_KIND_MM_TO_STREAM: begin
            if ((s_cfg_src_addr[channel] == 32'd0) ||
                (s_cfg_src_addr[channel][1:0] != 2'b00) ||
                !s_cfg_src_increment[channel] ||
                ((s_cfg_request[channel] != DMA_REQUEST_I2S_TX) &&
                 (s_cfg_request[channel] != DMA_REQUEST_CRYPTO_IN)) || endpoint_busy) begin
              s_start_valid[channel] = 1'b0;
              s_start_err_code[channel] = (s_cfg_src_addr[channel][1:0] != 2'b00)
                                                ? DMA_ERROR_ALIGNMENT
                                                : DMA_ERROR_CONFIG;
            end
          end
          DMA_KIND_STREAM_TO_MM: begin
            if ((s_cfg_dst_addr[channel] == 32'd0) ||
                (s_cfg_dst_addr[channel][1:0] != 2'b00) ||
                !s_cfg_dst_increment[channel] ||
                ((s_cfg_request[channel] != DMA_REQUEST_I2S_RX) &&
                 (s_cfg_request[channel] != DMA_REQUEST_DVP_RX) &&
                 (s_cfg_request[channel] != DMA_REQUEST_CRYPTO_OUT)) ||
                endpoint_busy) begin
              s_start_valid[channel] = 1'b0;
              s_start_err_code[channel] = (s_cfg_dst_addr[channel][1:0] != 2'b00)
                                                ? DMA_ERROR_ALIGNMENT
                                                : DMA_ERROR_CONFIG;
            end
          end
          default: begin
            s_start_valid[channel]    = 1'b0;
            s_start_err_code[channel] = DMA_ERROR_CONFIG;
          end
        endcase
      end
      if (s_start_valid[channel] && s_cfg_src_increment[channel] &&
          (s_cfg_kind[channel] != DMA_KIND_STREAM_TO_MM)) begin
        if (({1'b0, s_cfg_src_addr[channel]} + {1'b0, s_cfg_byte_count[channel]} - 33'd4) >
            33'h0_FFFF_FFFF) begin
          s_start_valid[channel]    = 1'b0;
          s_start_err_code[channel] = DMA_ERROR_CONFIG;
        end
      end
      if (s_start_valid[channel] && s_cfg_dst_increment[channel] &&
          (s_cfg_kind[channel] != DMA_KIND_MM_TO_STREAM)) begin
        if (({1'b0, s_cfg_dst_addr[channel]} + {1'b0, s_cfg_byte_count[channel]} - 33'd4) >
            33'h0_FFFF_FFFF) begin
          s_start_valid[channel]    = 1'b0;
          s_start_err_code[channel] = DMA_ERROR_CONFIG;
        end
      end
    end
  end

  always_comb begin
    s_read_candidate        = '0;
    s_read_candidate_beats  = '0;
    s_read_highest_priority = '0;
    for (int unsigned channel = 0; channel < NumChannels; channel++) begin
      int unsigned        remaining_beats;
      int unsigned        available_beats;
      int unsigned        page_beats;
      int unsigned        candidate_beats;
      logic               force_single;
      logic        [11:0] current_page_offset;

      remaining_beats = 0;
      available_beats = 0;
      page_beats = 1;
      candidate_beats = 0;
      force_single = 1'b1;
      current_page_offset = s_src_base_q[channel][11:0] +
                            (s_src_increment_q[channel] ? s_read_issued_q[channel][11:0]
                                                         : 12'd0);
      if (s_busy_q[channel] && !s_suspended_q[channel] && !s_abort_q[channel] &&
          !s_err_q[channel] &&
          ((s_kind_q[channel] == DMA_KIND_MM_TO_MM) ||
           (s_kind_q[channel] == DMA_KIND_MM_TO_STREAM)) &&
          (s_read_issued_q[channel] < s_len_q[channel]) && !s_fifo_full[channel]) begin
        remaining_beats = (s_len_q[channel] - s_read_issued_q[channel]) >> 2;
        available_beats = FifoDepth - {{(32 - FifoCountWidth) {1'b0}}, s_fifo_count[channel]};
        page_beats = (32'd4096 - {19'd0, 1'b0, current_page_offset}) >> 2;
        force_single = !s_src_increment_q[channel] ||
                       ((s_kind_q[channel] == DMA_KIND_MM_TO_MM) &&
                        !s_dst_increment_q[channel]) ||
                       is_apb_address(s_src_base_q[channel]) ||
            ((s_kind_q[channel] == DMA_KIND_MM_TO_MM) && is_apb_address(s_dst_base_q[channel]));
        candidate_beats = min_unsigned(remaining_beats, {27'd0, s_burst_q[channel]});
        candidate_beats = min_unsigned(candidate_beats, MaxBurstBeats);
        candidate_beats = min_unsigned(candidate_beats, page_beats);
        if (force_single) begin
          candidate_beats = min_unsigned(candidate_beats, 1);
        end
        if (((s_kind_q[channel] != DMA_KIND_MM_TO_MM) || s_src_increment_q[channel] ||
             s_req_ready[s_req_q[channel]]) &&
            (candidate_beats != 0) && (available_beats >= candidate_beats)) begin
          s_read_candidate[channel]       = 1'b1;
          s_read_candidate_beats[channel] = 5'(candidate_beats);
          if (s_priority_q[channel] > s_read_highest_priority) begin
            s_read_highest_priority = s_priority_q[channel];
          end
        end
      end
    end
    s_read_rr_request = '0;
    for (int unsigned channel = 0; channel < NumChannels; channel++) begin
      if (s_read_candidate[channel] && (s_priority_q[channel] == s_read_highest_priority)) begin
        s_read_rr_request[channel] = 1'b1;
      end
    end
  end

  always_comb begin
    s_write_candidate        = '0;
    s_write_candidate_beats  = '0;
    s_write_highest_priority = '0;
    for (int unsigned channel = 0; channel < NumChannels; channel++) begin
      int unsigned        remaining_beats;
      int unsigned        buffered_beats;
      int unsigned        page_beats;
      int unsigned        candidate_beats;
      logic               force_single;
      logic               read_owns_channel;
      logic        [11:0] current_page_offset;

      remaining_beats = 0;
      buffered_beats = 0;
      page_beats = 1;
      candidate_beats = 0;
      force_single = 1'b1;
      read_owns_channel = s_read_owner_valid_q && (s_read_owner_q == ChannelIndexWidth'(channel));
      current_page_offset = s_dst_base_q[channel][11:0] +
                            (s_dst_increment_q[channel] ? s_write_issued_q[channel][11:0]
                                                         : 12'd0);
      if (s_busy_q[channel] && !s_suspended_q[channel] && !s_abort_q[channel] &&
          !s_err_q[channel] && !read_owns_channel &&
          ((s_kind_q[channel] == DMA_KIND_MM_TO_MM) ||
           (s_kind_q[channel] == DMA_KIND_STREAM_TO_MM)) &&
          (s_write_issued_q[channel] < s_len_q[channel]) && !s_fifo_empty[channel]) begin
        remaining_beats = (s_len_q[channel] - s_write_issued_q[channel]) >> 2;
        buffered_beats = {{(32 - FifoCountWidth) {1'b0}}, s_fifo_count[channel]};
        page_beats = (32'd4096 - {19'd0, 1'b0, current_page_offset}) >> 2;
        force_single = !s_dst_increment_q[channel] ||
                       ((s_kind_q[channel] == DMA_KIND_MM_TO_MM) &&
                        !s_src_increment_q[channel]) ||
                       is_apb_address(s_dst_base_q[channel]) ||
            ((s_kind_q[channel] == DMA_KIND_MM_TO_MM) && is_apb_address(s_src_base_q[channel]));
        candidate_beats = min_unsigned(remaining_beats, {27'd0, s_burst_q[channel]});
        candidate_beats = min_unsigned(candidate_beats, MaxBurstBeats);
        candidate_beats = min_unsigned(candidate_beats, page_beats);
        if (force_single) begin
          candidate_beats = min_unsigned(candidate_beats, 1);
        end
        if ((s_kind_q[channel] == DMA_KIND_MM_TO_MM) &&
            (s_read_issued_q[channel] < s_len_q[channel]) &&
            (buffered_beats < candidate_beats)) begin
          // A source-page tail can be smaller than the destination burst.
          // Drain that complete read burst before reserving the next one.
          candidate_beats = buffered_beats;
        end
        if (((s_kind_q[channel] != DMA_KIND_MM_TO_MM) || s_dst_increment_q[channel] ||
             s_req_ready[s_req_q[channel]]) &&
            (candidate_beats != 0) && (buffered_beats >= candidate_beats)) begin
          s_write_candidate[channel]       = 1'b1;
          s_write_candidate_beats[channel] = 5'(candidate_beats);
          if (s_priority_q[channel] > s_write_highest_priority) begin
            s_write_highest_priority = s_priority_q[channel];
          end
        end
      end
    end
    s_write_rr_request = '0;
    for (int unsigned channel = 0; channel < NumChannels; channel++) begin
      if (s_write_candidate[channel] && (s_priority_q[channel] == s_write_highest_priority)) begin
        s_write_rr_request[channel] = 1'b1;
      end
    end
  end

  always_comb begin
    s_axi_read_start_valid = s_read_rr_valid && (|s_read_rr_grant) && !s_axi_read_busy;
    s_axi_read_start_addr  = '0;
    s_axi_read_start_beats = 5'd1;
    s_axi_read_start_fixed = 1'b0;
    if (s_read_rr_valid) begin
      s_axi_read_start_addr = s_src_base_q[s_read_rr_selected] +
                              (s_src_increment_q[s_read_rr_selected]
                                   ? s_read_issued_q[s_read_rr_selected]
                                   : 32'd0);
      s_axi_read_start_beats = s_read_candidate_beats[s_read_rr_selected];
      s_axi_read_start_fixed = !s_src_increment_q[s_read_rr_selected];
    end

    s_axi_write_start_valid = s_write_rr_valid && (|s_write_rr_grant) && !s_axi_write_busy;
    s_axi_write_start_addr  = '0;
    s_axi_write_start_beats = 5'd1;
    s_axi_write_start_fixed = 1'b0;
    if (s_write_rr_valid) begin
      s_axi_write_start_addr = s_dst_base_q[s_write_rr_selected] +
                               (s_dst_increment_q[s_write_rr_selected]
                                    ? s_write_issued_q[s_write_rr_selected]
                                    : 32'd0);
      s_axi_write_start_beats = s_write_candidate_beats[s_write_rr_selected];
      s_axi_write_start_fixed = !s_dst_increment_q[s_write_rr_selected];
    end
  end

  always_comb begin
    s_i2s_tx_channel_valid     = 1'b0;
    s_i2s_tx_channel           = '0;
    s_i2s_rx_channel_valid     = 1'b0;
    s_i2s_rx_channel           = '0;
    s_dvp_rx_channel_valid     = 1'b0;
    s_dvp_rx_channel           = '0;
    s_crypto_in_channel_valid  = 1'b0;
    s_crypto_in_channel        = '0;
    s_crypto_out_channel_valid = 1'b0;
    s_crypto_out_channel       = '0;
    for (int unsigned channel = 0; channel < NumChannels; channel++) begin
      if (s_busy_q[channel] && (s_kind_q[channel] == DMA_KIND_MM_TO_STREAM) &&
          (s_req_q[channel] == DMA_REQUEST_I2S_TX)) begin
        s_i2s_tx_channel_valid = 1'b1;
        s_i2s_tx_channel       = ChannelIndexWidth'(channel);
      end
      if (s_busy_q[channel] && (s_kind_q[channel] == DMA_KIND_STREAM_TO_MM) &&
          (s_req_q[channel] == DMA_REQUEST_I2S_RX)) begin
        s_i2s_rx_channel_valid = 1'b1;
        s_i2s_rx_channel       = ChannelIndexWidth'(channel);
      end
      if (s_busy_q[channel] && (s_kind_q[channel] == DMA_KIND_STREAM_TO_MM) &&
          (s_req_q[channel] == DMA_REQUEST_DVP_RX)) begin
        s_dvp_rx_channel_valid = 1'b1;
        s_dvp_rx_channel       = ChannelIndexWidth'(channel);
      end
      if (s_busy_q[channel] && (s_kind_q[channel] == DMA_KIND_MM_TO_STREAM) &&
          (s_req_q[channel] == DMA_REQUEST_CRYPTO_IN)) begin
        s_crypto_in_channel_valid = 1'b1;
        s_crypto_in_channel       = ChannelIndexWidth'(channel);
      end
      if (s_busy_q[channel] && (s_kind_q[channel] == DMA_KIND_STREAM_TO_MM) &&
          (s_req_q[channel] == DMA_REQUEST_CRYPTO_OUT)) begin
        s_crypto_out_channel_valid = 1'b1;
        s_crypto_out_channel       = ChannelIndexWidth'(channel);
      end
    end
  end

  always_comb begin
    i2s_tx_axis.tdata  = '0;
    i2s_tx_axis.tkeep  = 4'hF;
    i2s_tx_axis.tstrb  = 4'hF;
    i2s_tx_axis.tlast  = 1'b0;
    i2s_tx_axis.tid    = '0;
    i2s_tx_axis.tdest  = '0;
    i2s_tx_axis.tuser  = '0;
    i2s_tx_axis.tvalid = 1'b0;
    if (s_i2s_tx_channel_valid && !s_suspended_q[s_i2s_tx_channel] &&
        !s_stream_tx_stop_q[s_i2s_tx_channel] &&
        !s_fifo_empty[s_i2s_tx_channel]) begin
      i2s_tx_axis.tdata = s_fifo_rdata[s_i2s_tx_channel];
      i2s_tx_axis.tlast = (s_bytes_done_q[s_i2s_tx_channel] + WordBytes) >=
                           s_len_q[s_i2s_tx_channel];
      i2s_tx_axis.tvalid = 1'b1;
    end

    i2s_rx_axis.tready = s_i2s_rx_channel_valid &&
                         !s_suspended_q[s_i2s_rx_channel] &&
                         !s_abort_q[s_i2s_rx_channel] &&
                         !s_err_q[s_i2s_rx_channel] &&
                         !s_fifo_full[s_i2s_rx_channel] &&
                         (s_stream_accepted_q[s_i2s_rx_channel] <
                          s_len_q[s_i2s_rx_channel]);
    dvp_rx_axis.tready = s_dvp_rx_channel_valid &&
                         !s_suspended_q[s_dvp_rx_channel] &&
                         !s_abort_q[s_dvp_rx_channel] &&
                         !s_err_q[s_dvp_rx_channel] &&
                         !s_fifo_full[s_dvp_rx_channel] &&
                         (s_stream_accepted_q[s_dvp_rx_channel] <
                          s_len_q[s_dvp_rx_channel]);

    crypto_in_axis.tdata = '0;
    crypto_in_axis.tkeep = 4'hF;
    crypto_in_axis.tstrb = 4'hF;
    crypto_in_axis.tlast = 1'b0;
    crypto_in_axis.tid = '0;
    crypto_in_axis.tdest = '0;
    crypto_in_axis.tuser = '0;
    crypto_in_axis.tvalid = 1'b0;
    if (s_crypto_in_channel_valid && !s_suspended_q[s_crypto_in_channel] &&
        !s_stream_tx_stop_q[s_crypto_in_channel] && !s_fifo_empty[s_crypto_in_channel]) begin
      crypto_in_axis.tdata = s_fifo_rdata[s_crypto_in_channel];
      crypto_in_axis.tlast = (s_bytes_done_q[s_crypto_in_channel] + WordBytes) >=
                             s_len_q[s_crypto_in_channel];
      crypto_in_axis.tvalid = 1'b1;
    end

    crypto_out_axis.tready = s_crypto_out_channel_valid &&
                             !s_suspended_q[s_crypto_out_channel] &&
                             !s_abort_q[s_crypto_out_channel] &&
                             !s_err_q[s_crypto_out_channel] &&
                             !s_fifo_full[s_crypto_out_channel] &&
                             (s_stream_accepted_q[s_crypto_out_channel] <
                              s_len_q[s_crypto_out_channel]);
  end

  assign s_i2s_tx_fire = i2s_tx_axis.tvalid && i2s_tx_axis.tready;
  assign s_i2s_rx_fire = i2s_rx_axis.tvalid && i2s_rx_axis.tready;
  assign s_dvp_rx_fire = dvp_rx_axis.tvalid && dvp_rx_axis.tready;
  assign s_crypto_in_fire = crypto_in_axis.tvalid && crypto_in_axis.tready;
  assign s_crypto_out_fire = crypto_out_axis.tvalid && crypto_out_axis.tready;
  assign s_stream_rx_keep_err =
      (s_i2s_rx_fire && (i2s_rx_axis.tkeep != 4'hF)) ||
      (s_dvp_rx_fire && (dvp_rx_axis.tkeep != 4'hF)) ||
      (s_crypto_out_fire && (crypto_out_axis.tkeep != 4'hF));
  assign s_stream_rx_err_channel = s_i2s_rx_fire ? s_i2s_rx_channel :
                                   (s_dvp_rx_fire ? s_dvp_rx_channel : s_crypto_out_channel);
  assign s_axi_read_beat_ready = 1'b1;
  assign s_axi_write_data_valid = s_write_owner_valid_q && !s_fifo_empty[s_write_owner_q];
  assign s_axi_write_data = s_write_owner_valid_q ? s_fifo_rdata[s_write_owner_q] : 32'd0;
  assign s_axi_write_strb = 4'hF;

  always_comb begin
    s_fifo_flush = '0;
    s_fifo_push  = '0;
    s_fifo_pop   = '0;
    s_fifo_wdata = '0;
    for (int unsigned channel = 0; channel < NumChannels; channel++) begin
      if (global_reset_i || channel_reset_i[channel]) begin
        s_fifo_flush[channel] = 1'b1;
      end
      if ((s_abort_q[channel] || s_err_q[channel]) &&
          !s_read_owns_channel[channel] && !s_write_owns_channel[channel] &&
          ((s_kind_q[channel] != DMA_KIND_MM_TO_STREAM) ||
           s_stream_tx_stop_q[channel] || !s_stream_tx_valid[channel])) begin
        s_fifo_flush[channel] = 1'b1;
      end
    end

    if (s_axi_read_beat_valid && s_read_owner_valid_q &&
        (s_read_seen_q < s_read_beats_q) && !s_read_err_q &&
        !s_abort_q[s_read_owner_q] && (s_axi_read_resp == `AXI4_RESP_OKAY) &&
        !s_axi_read_id_error &&
        (s_axi_read_last == s_axi_read_expected_last)) begin
      s_fifo_push[s_read_owner_q]  = 1'b1;
      s_fifo_wdata[s_read_owner_q] = s_axi_read_data;
    end
    if (s_axi_read_done && s_read_owner_valid_q &&
        (s_read_err_q || (s_axi_read_resp != `AXI4_RESP_OKAY) ||
         s_axi_read_id_error || (s_axi_read_last != s_axi_read_expected_last) ||
         s_abort_q[s_read_owner_q])) begin
      if ((s_kind_q[s_read_owner_q] != DMA_KIND_MM_TO_STREAM) ||
          s_stream_tx_stop_q[s_read_owner_q] ||
          !s_stream_tx_valid[s_read_owner_q]) begin
        if (!s_write_owns_channel[s_read_owner_q]) begin
          s_fifo_flush[s_read_owner_q] = 1'b1;
        end
      end
    end

    if (s_i2s_rx_fire && !s_stream_rx_keep_err) begin
      s_fifo_push[s_i2s_rx_channel]  = 1'b1;
      s_fifo_wdata[s_i2s_rx_channel] = i2s_rx_axis.tdata;
    end
    if (s_dvp_rx_fire && !s_stream_rx_keep_err) begin
      s_fifo_push[s_dvp_rx_channel]  = 1'b1;
      s_fifo_wdata[s_dvp_rx_channel] = dvp_rx_axis.tdata;
    end
    if (s_crypto_out_fire && !s_stream_rx_keep_err) begin
      s_fifo_push[s_crypto_out_channel]  = 1'b1;
      s_fifo_wdata[s_crypto_out_channel] = crypto_out_axis.tdata;
    end
    if (s_axi_write_data_valid && s_axi_write_data_ready && s_write_owner_valid_q) begin
      s_fifo_pop[s_write_owner_q] = 1'b1;
    end
    if (s_i2s_tx_fire && s_i2s_tx_channel_valid) begin
      s_fifo_pop[s_i2s_tx_channel] = 1'b1;
    end
    if (s_crypto_in_fire && s_crypto_in_channel_valid) begin
      s_fifo_pop[s_crypto_in_channel] = 1'b1;
    end
    if (s_axi_write_done && s_write_owner_valid_q &&
        ((s_axi_write_resp != `AXI4_RESP_OKAY) || s_axi_write_id_error ||
         s_abort_q[s_write_owner_q] || s_err_q[s_write_owner_q])) begin
      s_fifo_flush[s_write_owner_q] = 1'b1;
    end
  end

  always_comb begin
    s_progress = '0;
    if (s_axi_read_start_valid && s_axi_read_start_ready) begin
      s_progress[s_read_rr_selected] = 1'b1;
    end
    if (s_axi_read_beat_valid && s_read_owner_valid_q) begin
      s_progress[s_read_owner_q] = 1'b1;
    end
    if (s_axi_write_start_valid && s_axi_write_start_ready) begin
      s_progress[s_write_rr_selected] = 1'b1;
    end
    if (s_axi_write_data_valid && s_axi_write_data_ready && s_write_owner_valid_q) begin
      s_progress[s_write_owner_q] = 1'b1;
    end
    if (s_axi_write_done && s_write_owner_valid_q) begin
      s_progress[s_write_owner_q] = 1'b1;
    end
    if (s_i2s_tx_fire && s_i2s_tx_channel_valid) begin
      s_progress[s_i2s_tx_channel] = 1'b1;
    end
    if (s_i2s_rx_fire && s_i2s_rx_channel_valid) begin
      s_progress[s_i2s_rx_channel] = 1'b1;
    end
    if (s_dvp_rx_fire && s_dvp_rx_channel_valid) begin
      s_progress[s_dvp_rx_channel] = 1'b1;
    end
    if (s_crypto_in_fire && s_crypto_in_channel_valid) begin
      s_progress[s_crypto_in_channel] = 1'b1;
    end
    if (s_crypto_out_fire && s_crypto_out_channel_valid) begin
      s_progress[s_crypto_out_channel] = 1'b1;
    end
  end

  always_comb begin
    s_read_owns_channel  = '0;
    s_write_owns_channel = '0;
    s_stream_tx_valid    = '0;
    for (int unsigned channel = 0; channel < NumChannels; channel++) begin
      s_read_owns_channel[channel] = s_read_owner_valid_q &&
                                     (s_read_owner_q == ChannelIndexWidth'(channel));
      s_write_owns_channel[channel] = s_write_owner_valid_q &&
                                      (s_write_owner_q == ChannelIndexWidth'(channel));
      s_stream_tx_valid[channel] = s_i2s_tx_channel_valid &&
                                   (s_i2s_tx_channel == ChannelIndexWidth'(channel)) &&
                                   i2s_tx_axis.tvalid;
      s_stream_tx_valid[channel] |= s_crypto_in_channel_valid &&
                                    (s_crypto_in_channel == ChannelIndexWidth'(channel)) &&
                                    crypto_in_axis.tvalid;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_busy_q              <= '0;
      s_suspended_q         <= '0;
      s_done_q              <= '0;
      s_aborted_q           <= '0;
      s_err_q               <= '0;
      s_stream_last_q       <= '0;
      s_abort_q             <= '0;
      s_suspend_req_q       <= '0;
      s_stream_tx_stop_q    <= '0;
      s_half_seen_q         <= '0;
      s_evt_done_q          <= '0;
      s_evt_half_q          <= '0;
      s_evt_err_q           <= '0;
      s_kind_q              <= '0;
      s_req_q               <= '0;
      s_priority_q          <= '0;
      s_burst_q             <= '0;
      s_src_increment_q     <= '0;
      s_dst_increment_q     <= '0;
      s_src_base_q          <= '0;
      s_dst_base_q          <= '0;
      s_len_q               <= '0;
      s_read_issued_q       <= '0;
      s_write_issued_q      <= '0;
      s_stream_accepted_q   <= '0;
      s_bytes_done_q        <= '0;
      s_stall_cycles_q      <= '0;
      s_err_code_q          <= '0;
      s_err_resp_q          <= '0;
      s_err_read_q          <= '0;
      s_err_addr_q          <= '0;
      s_read_owner_valid_q  <= 1'b0;
      s_read_owner_q        <= '0;
      s_read_beats_q        <= '0;
      s_read_seen_q         <= '0;
      s_read_err_q          <= 1'b0;
      s_write_owner_valid_q <= 1'b0;
      s_write_owner_q       <= '0;
      s_write_bytes_q       <= '0;
      s_first_err_valid_q   <= 1'b0;
      s_first_err_channel_q <= '0;
      s_first_err_stat_q    <= '0;
      s_first_err_addr_hi_q <= '0;
      xpi_xfer_done_o       <= 1'b0;
    end else begin
      xpi_xfer_done_o <= 1'b0;
      if (global_reset_i) begin
        s_busy_q              <= '0;
        s_suspended_q         <= '0;
        s_done_q              <= '0;
        s_aborted_q           <= '0;
        s_err_q               <= '0;
        s_stream_last_q       <= '0;
        s_abort_q             <= '0;
        s_suspend_req_q       <= '0;
        s_stream_tx_stop_q    <= '0;
        s_half_seen_q         <= '0;
        s_evt_done_q          <= '0;
        s_evt_half_q          <= '0;
        s_evt_err_q           <= '0;
        s_read_issued_q       <= '0;
        s_write_issued_q      <= '0;
        s_stream_accepted_q   <= '0;
        s_bytes_done_q        <= '0;
        s_stall_cycles_q      <= '0;
        s_err_code_q          <= '0;
        s_err_resp_q          <= '0;
        s_err_read_q          <= '0;
        s_err_addr_q          <= '0;
        s_read_owner_valid_q  <= 1'b0;
        s_read_err_q          <= 1'b0;
        s_write_owner_valid_q <= 1'b0;
        s_first_err_valid_q   <= 1'b0;
        s_first_err_channel_q <= '0;
        s_first_err_stat_q    <= '0;
        s_first_err_addr_hi_q <= '0;
      end else begin
        if (global_error_clear_i) begin
          s_first_err_valid_q   <= 1'b0;
          s_first_err_channel_q <= '0;
          s_first_err_stat_q    <= '0;
          s_first_err_addr_hi_q <= '0;
        end

        for (int unsigned channel = 0; channel < NumChannels; channel++) begin
          if (event_clear_i[channel*3]) begin
            s_evt_done_q[channel] <= 1'b0;
          end
          if (event_clear_i[(channel*3)+1]) begin
            s_evt_half_q[channel] <= 1'b0;
          end
          if (event_clear_i[(channel*3)+2]) begin
            s_evt_err_q[channel] <= 1'b0;
          end
          if (channel_reset_i[channel]) begin
            s_busy_q[channel]            <= 1'b0;
            s_suspended_q[channel]       <= 1'b0;
            s_done_q[channel]            <= 1'b0;
            s_aborted_q[channel]         <= 1'b0;
            s_err_q[channel]             <= 1'b0;
            s_stream_last_q[channel]     <= 1'b0;
            s_abort_q[channel]           <= 1'b0;
            s_suspend_req_q[channel]     <= 1'b0;
            s_stream_tx_stop_q[channel]  <= 1'b0;
            s_half_seen_q[channel]       <= 1'b0;
            s_evt_done_q[channel]        <= 1'b0;
            s_evt_half_q[channel]        <= 1'b0;
            s_evt_err_q[channel]         <= 1'b0;
            s_read_issued_q[channel]     <= '0;
            s_write_issued_q[channel]    <= '0;
            s_stream_accepted_q[channel] <= '0;
            s_bytes_done_q[channel]      <= '0;
            s_stall_cycles_q[channel]    <= '0;
            s_err_code_q[channel]        <= DMA_ERROR_NONE;
            s_err_resp_q[channel]        <= '0;
            s_err_read_q[channel]        <= 1'b0;
            s_err_addr_q[channel]        <= '0;
          end else begin
            if (start_i[channel] && !s_busy_q[channel]) begin
              s_done_q[channel]            <= 1'b0;
              s_aborted_q[channel]         <= 1'b0;
              s_err_q[channel]             <= 1'b0;
              s_stream_last_q[channel]     <= 1'b0;
              s_abort_q[channel]           <= 1'b0;
              s_suspend_req_q[channel]     <= 1'b0;
              s_stream_tx_stop_q[channel]  <= 1'b0;
              s_half_seen_q[channel]       <= 1'b0;
              s_evt_done_q[channel]        <= 1'b0;
              s_evt_half_q[channel]        <= 1'b0;
              s_evt_err_q[channel]         <= 1'b0;
              s_read_issued_q[channel]     <= '0;
              s_write_issued_q[channel]    <= '0;
              s_stream_accepted_q[channel] <= '0;
              s_bytes_done_q[channel]      <= '0;
              s_stall_cycles_q[channel]    <= '0;
              s_err_resp_q[channel]        <= '0;
              s_err_read_q[channel]        <= 1'b0;
              if (s_start_valid[channel]) begin
                s_busy_q[channel]          <= 1'b1;
                s_kind_q[channel]          <= s_cfg_kind[channel];
                s_req_q[channel]           <= s_cfg_request[channel];
                s_priority_q[channel]      <= s_cfg_priority[channel];
                s_burst_q[channel]         <= s_cfg_burst[channel];
                s_src_increment_q[channel] <= s_cfg_src_increment[channel];
                s_dst_increment_q[channel] <= s_cfg_dst_increment[channel];
                s_src_base_q[channel]      <= s_cfg_src_addr[channel];
                s_dst_base_q[channel]      <= s_cfg_dst_addr[channel];
                s_len_q[channel]           <= s_cfg_byte_count[channel];
                s_err_code_q[channel]      <= DMA_ERROR_NONE;
                s_err_addr_q[channel]      <= '0;
              end else begin
                s_busy_q[channel]     <= 1'b0;
                s_err_q[channel]      <= 1'b1;
                s_evt_err_q[channel]  <= 1'b1;
                s_err_code_q[channel] <= s_start_err_code[channel];
                s_err_addr_q[channel] <= s_cfg_src_addr[channel];
                if (!s_first_err_valid_q) begin
                  s_first_err_valid_q <= 1'b1;
                  s_first_err_channel_q <= ChannelIndexWidth'(channel);
                  s_first_err_stat_q <= channel_error_status(
                      s_start_err_code[channel], 2'b00, 1'b0, 1'b0
                  );
                  s_first_err_addr_hi_q <= s_cfg_src_addr[channel][31:16];
                end
              end
            end
            if (suspend_i[channel] && s_busy_q[channel] && !s_abort_q[channel]) begin
              s_suspend_req_q[channel] <= 1'b1;
            end
            if (resume_i[channel] && s_busy_q[channel] && !s_abort_q[channel]) begin
              s_suspended_q[channel]      <= 1'b0;
              s_suspend_req_q[channel]    <= 1'b0;
              s_stream_tx_stop_q[channel] <= 1'b0;
            end
            if (abort_i[channel] && s_busy_q[channel]) begin
              s_abort_q[channel]       <= 1'b1;
              s_suspended_q[channel]   <= 1'b0;
              s_suspend_req_q[channel] <= 1'b0;
              if ((s_kind_q[channel] == DMA_KIND_MM_TO_STREAM) &&
                  (!s_stream_tx_valid[channel] ||
                   ((s_i2s_tx_channel == ChannelIndexWidth'(channel)) &&
                    s_i2s_tx_fire) ||
                   ((s_crypto_in_channel == ChannelIndexWidth'(channel)) &&
                    s_crypto_in_fire))) begin
                s_stream_tx_stop_q[channel] <= 1'b1;
              end
            end
            if (s_busy_q[channel] && !s_suspended_q[channel] && !s_progress[channel]) begin
              s_stall_cycles_q[channel] <= s_stall_cycles_q[channel] + 1'b1;
            end
          end
        end

        if (s_axi_read_start_valid && s_axi_read_start_ready) begin
          s_read_owner_valid_q <= 1'b1;
          s_read_owner_q <= s_read_rr_selected;
          s_read_beats_q <= s_read_candidate_beats[s_read_rr_selected];
          s_read_seen_q <= '0;
          s_read_err_q <= 1'b0;
          s_read_issued_q[s_read_rr_selected] <=
              s_read_issued_q[s_read_rr_selected] +
              ({27'd0, s_read_candidate_beats[s_read_rr_selected]} << 2);
        end

        if (s_axi_read_beat_valid && s_read_owner_valid_q) begin
          s_read_seen_q <= s_read_seen_q + 1'b1;
          if ((s_axi_read_resp != `AXI4_RESP_OKAY) || s_axi_read_id_error ||
              (s_axi_read_last != s_axi_read_expected_last)) begin
            s_read_err_q <= 1'b1;
            s_err_q[s_read_owner_q] <= 1'b1;
            s_evt_err_q[s_read_owner_q] <= 1'b1;
            s_err_code_q[s_read_owner_q] <=
                ((s_axi_read_resp != `AXI4_RESP_OKAY) ? DMA_ERROR_AXI_READ
                                                       : DMA_ERROR_AXI_PROTOCOL);
            s_err_resp_q[s_read_owner_q] <= s_axi_read_resp;
            s_err_read_q[s_read_owner_q] <= 1'b1;
            s_err_addr_q[s_read_owner_q] <= s_src_base_q[s_read_owner_q] +
                                              (s_src_increment_q[s_read_owner_q]
                                                   ? ({27'd0, s_read_seen_q} << 2)
                                                   : 32'd0);
            if (!s_first_err_valid_q) begin
              s_first_err_valid_q <= 1'b1;
              s_first_err_channel_q <= s_read_owner_q;
              s_first_err_stat_q <= channel_error_status(
                  ((s_axi_read_resp != `AXI4_RESP_OKAY) ? DMA_ERROR_AXI_READ
                                                         : DMA_ERROR_AXI_PROTOCOL),
                  s_axi_read_resp,
                  1'b1,
                  1'b0
              );
              s_first_err_addr_hi_q <= 16'((s_src_base_q[s_read_owner_q] +
                                             (s_src_increment_q[s_read_owner_q]
                                                  ? ({27'd0, s_read_seen_q} << 2)
                                                  : 32'd0)) >>
                                            16);
            end
          end
        end

        if (s_axi_read_done && s_read_owner_valid_q) begin
          if (s_read_err_q || (s_axi_read_resp != `AXI4_RESP_OKAY) ||
              s_axi_read_id_error || (s_axi_read_last != s_axi_read_expected_last)) begin
            s_suspend_req_q[s_read_owner_q] <= 1'b0;
            s_abort_q[s_read_owner_q]       <= 1'b0;
            if ((s_kind_q[s_read_owner_q] == DMA_KIND_MM_TO_STREAM) &&
                (!s_stream_tx_valid[s_read_owner_q] ||
                 ((s_i2s_tx_channel == s_read_owner_q) && s_i2s_tx_fire) ||
                 ((s_crypto_in_channel == s_read_owner_q) && s_crypto_in_fire))) begin
              s_stream_tx_stop_q[s_read_owner_q] <= 1'b1;
            end
          end else if (s_abort_q[s_read_owner_q]) begin
            s_suspend_req_q[s_read_owner_q] <= 1'b0;
          end
          s_read_owner_valid_q <= 1'b0;
        end

        if (s_axi_write_start_valid && s_axi_write_start_ready) begin
          s_write_owner_valid_q <= 1'b1;
          s_write_owner_q <= s_write_rr_selected;
          s_write_bytes_q <= {27'd0, s_write_candidate_beats[s_write_rr_selected]} << 2;
          s_write_issued_q[s_write_rr_selected] <=
              s_write_issued_q[s_write_rr_selected] +
              ({27'd0, s_write_candidate_beats[s_write_rr_selected]} << 2);
        end

        if (s_axi_write_done && s_write_owner_valid_q) begin
          s_write_owner_valid_q <= 1'b0;
          if ((s_axi_write_resp != `AXI4_RESP_OKAY) || s_axi_write_id_error) begin
            s_err_q[s_write_owner_q] <= 1'b1;
            s_evt_err_q[s_write_owner_q] <= 1'b1;
            s_err_code_q[s_write_owner_q] <=
                ((s_axi_write_resp != `AXI4_RESP_OKAY) ? DMA_ERROR_AXI_WRITE
                                                        : DMA_ERROR_AXI_PROTOCOL);
            s_err_resp_q[s_write_owner_q] <= s_axi_write_resp;
            s_err_read_q[s_write_owner_q] <= 1'b0;
            s_err_addr_q[s_write_owner_q] <= s_dst_base_q[s_write_owner_q] +
                                               (s_dst_increment_q[s_write_owner_q]
                                                    ? (s_write_issued_q[s_write_owner_q] -
                                                       s_write_bytes_q)
                                                    : 32'd0);
            if (!s_first_err_valid_q) begin
              s_first_err_valid_q <= 1'b1;
              s_first_err_channel_q <= s_write_owner_q;
              s_first_err_stat_q <= channel_error_status(
                  ((s_axi_write_resp != `AXI4_RESP_OKAY) ? DMA_ERROR_AXI_WRITE
                                                          : DMA_ERROR_AXI_PROTOCOL),
                  s_axi_write_resp,
                  1'b0,
                  1'b0
              );
              s_first_err_addr_hi_q <= 16'((s_dst_base_q[s_write_owner_q] +
                                             (s_dst_increment_q[s_write_owner_q]
                                                  ? (s_write_issued_q[s_write_owner_q] -
                                                     s_write_bytes_q)
                                                  : 32'd0)) >>
                                            16);
            end
          end else if (s_err_q[s_write_owner_q]) begin
            s_suspend_req_q[s_write_owner_q] <= 1'b0;
          end else if (s_abort_q[s_write_owner_q]) begin
            s_suspend_req_q[s_write_owner_q] <= 1'b0;
          end else begin
            s_bytes_done_q[s_write_owner_q] <= s_bytes_done_q[s_write_owner_q] + s_write_bytes_q;
            if (!s_half_seen_q[s_write_owner_q] &&
                ((s_bytes_done_q[s_write_owner_q] + s_write_bytes_q) >=
                 (s_len_q[s_write_owner_q] >> 1))) begin
              s_half_seen_q[s_write_owner_q] <= 1'b1;
              s_evt_half_q[s_write_owner_q]  <= 1'b1;
            end
            if ((s_bytes_done_q[s_write_owner_q] + s_write_bytes_q) >=
                s_len_q[s_write_owner_q]) begin
              s_busy_q[s_write_owner_q]     <= 1'b0;
              s_done_q[s_write_owner_q]     <= 1'b1;
              s_evt_done_q[s_write_owner_q] <= 1'b1;
              if ((s_req_q[s_write_owner_q] == DMA_REQUEST_QSPI_TX) ||
                  (s_req_q[s_write_owner_q] == DMA_REQUEST_QSPI_RX)) begin
                xpi_xfer_done_o <= 1'b1;
              end
            end
          end
        end

        if (s_stream_rx_keep_err) begin
          s_err_q[s_stream_rx_err_channel]      <= 1'b1;
          s_evt_err_q[s_stream_rx_err_channel]  <= 1'b1;
          s_err_code_q[s_stream_rx_err_channel] <= DMA_ERROR_STREAM;
          s_err_resp_q[s_stream_rx_err_channel] <= '0;
          s_err_read_q[s_stream_rx_err_channel] <= 1'b1;
          s_err_addr_q[s_stream_rx_err_channel] <= s_dst_base_q[s_stream_rx_err_channel];
          if (!s_first_err_valid_q) begin
            s_first_err_valid_q   <= 1'b1;
            s_first_err_channel_q <= s_stream_rx_err_channel;
            s_first_err_stat_q    <= channel_error_status(DMA_ERROR_STREAM, 2'b00, 1'b1, 1'b0);
            s_first_err_addr_hi_q <= s_dst_base_q[s_stream_rx_err_channel][31:16];
          end
        end else begin
          if (s_i2s_rx_fire) begin
            s_stream_accepted_q[s_i2s_rx_channel] <=
                s_stream_accepted_q[s_i2s_rx_channel] + WordBytes;
            if (i2s_rx_axis.tlast) begin
              s_stream_last_q[s_i2s_rx_channel] <= 1'b1;
            end
          end
          if (s_dvp_rx_fire) begin
            s_stream_accepted_q[s_dvp_rx_channel] <=
                s_stream_accepted_q[s_dvp_rx_channel] + WordBytes;
            if (dvp_rx_axis.tlast) begin
              s_stream_last_q[s_dvp_rx_channel] <= 1'b1;
            end
          end
          if (s_crypto_out_fire) begin
            s_stream_accepted_q[s_crypto_out_channel] <=
                s_stream_accepted_q[s_crypto_out_channel] + WordBytes;
            if (crypto_out_axis.tlast) begin
              s_stream_last_q[s_crypto_out_channel] <= 1'b1;
            end
          end
        end

        if (s_i2s_tx_fire && s_i2s_tx_channel_valid) begin
          if (s_abort_q[s_i2s_tx_channel] || s_err_q[s_i2s_tx_channel] ||
              s_suspend_req_q[s_i2s_tx_channel]) begin
            s_stream_tx_stop_q[s_i2s_tx_channel] <= 1'b1;
            if (s_suspend_req_q[s_i2s_tx_channel] && !s_abort_q[s_i2s_tx_channel] &&
                !s_err_q[s_i2s_tx_channel]) begin
              s_suspended_q[s_i2s_tx_channel]   <= 1'b1;
              s_suspend_req_q[s_i2s_tx_channel] <= 1'b0;
            end
          end else begin
            s_bytes_done_q[s_i2s_tx_channel] <= s_bytes_done_q[s_i2s_tx_channel] + WordBytes;
            if (!s_half_seen_q[s_i2s_tx_channel] &&
                ((s_bytes_done_q[s_i2s_tx_channel] + WordBytes) >=
                 (s_len_q[s_i2s_tx_channel] >> 1))) begin
              s_half_seen_q[s_i2s_tx_channel] <= 1'b1;
              s_evt_half_q[s_i2s_tx_channel]  <= 1'b1;
            end
            if ((s_bytes_done_q[s_i2s_tx_channel] + WordBytes) >= s_len_q[s_i2s_tx_channel]) begin
              s_busy_q[s_i2s_tx_channel]           <= 1'b0;
              s_done_q[s_i2s_tx_channel]           <= 1'b1;
              s_evt_done_q[s_i2s_tx_channel]       <= 1'b1;
              s_stream_tx_stop_q[s_i2s_tx_channel] <= 1'b1;
            end
          end
        end

        if (s_crypto_in_fire && s_crypto_in_channel_valid) begin
          if (s_abort_q[s_crypto_in_channel] || s_err_q[s_crypto_in_channel] ||
              s_suspend_req_q[s_crypto_in_channel]) begin
            s_stream_tx_stop_q[s_crypto_in_channel] <= 1'b1;
            if (s_suspend_req_q[s_crypto_in_channel] && !s_abort_q[s_crypto_in_channel] &&
                !s_err_q[s_crypto_in_channel]) begin
              s_suspended_q[s_crypto_in_channel]   <= 1'b1;
              s_suspend_req_q[s_crypto_in_channel] <= 1'b0;
            end
          end else begin
            s_bytes_done_q[s_crypto_in_channel] <= s_bytes_done_q[s_crypto_in_channel] + WordBytes;
            if (!s_half_seen_q[s_crypto_in_channel] &&
                ((s_bytes_done_q[s_crypto_in_channel] + WordBytes) >=
                 (s_len_q[s_crypto_in_channel] >> 1))) begin
              s_half_seen_q[s_crypto_in_channel] <= 1'b1;
              s_evt_half_q[s_crypto_in_channel]  <= 1'b1;
            end
            if ((s_bytes_done_q[s_crypto_in_channel] + WordBytes) >=
                s_len_q[s_crypto_in_channel]) begin
              s_busy_q[s_crypto_in_channel]           <= 1'b0;
              s_done_q[s_crypto_in_channel]           <= 1'b1;
              s_evt_done_q[s_crypto_in_channel]       <= 1'b1;
              s_stream_tx_stop_q[s_crypto_in_channel] <= 1'b1;
            end
          end
        end

        for (int unsigned channel = 0; channel < NumChannels; channel++) begin
          if (s_busy_q[channel] && s_suspend_req_q[channel] && !s_abort_q[channel] &&
              !s_read_owns_channel[channel] && !s_write_owns_channel[channel] &&
              (!s_stream_tx_valid[channel] || s_stream_tx_stop_q[channel])) begin
            s_suspended_q[channel]   <= 1'b1;
            s_suspend_req_q[channel] <= 1'b0;
            if (s_kind_q[channel] == DMA_KIND_MM_TO_STREAM) begin
              s_stream_tx_stop_q[channel] <= 1'b1;
            end
          end
          if (s_busy_q[channel] && s_abort_q[channel] && !s_read_owns_channel[channel] &&
              !s_write_owns_channel[channel]) begin
            if ((s_kind_q[channel] != DMA_KIND_MM_TO_STREAM) ||
                s_stream_tx_stop_q[channel] || !s_stream_tx_valid[channel]) begin
              s_busy_q[channel]           <= 1'b0;
              s_aborted_q[channel]        <= 1'b1;
              s_abort_q[channel]          <= 1'b0;
              s_suspend_req_q[channel]    <= 1'b0;
              s_stream_tx_stop_q[channel] <= 1'b1;
              s_err_code_q[channel]       <= DMA_ERROR_ABORT;
            end
          end
          if (s_busy_q[channel] && s_err_q[channel] && !s_read_owns_channel[channel] &&
              !s_write_owns_channel[channel] &&
              ((s_kind_q[channel] != DMA_KIND_MM_TO_STREAM) ||
               s_stream_tx_stop_q[channel] || !s_stream_tx_valid[channel])) begin
            s_busy_q[channel]           <= 1'b0;
            s_abort_q[channel]          <= 1'b0;
            s_suspend_req_q[channel]    <= 1'b0;
            s_stream_tx_stop_q[channel] <= 1'b1;
          end
        end
      end
    end
  end

  always_comb begin
    busy_o            = s_busy_q;
    suspended_o       = s_suspended_q;
    done_o            = s_done_q;
    aborted_o         = s_aborted_q;
    error_o           = s_err_q;
    stream_last_o     = s_stream_last_q;
    event_status_o    = '0;
    error_status_o    = '0;
    error_addr_o      = '0;
    current_src_o     = '0;
    current_dst_o     = '0;
    remaining_o       = '0;
    bytes_done_o      = '0;
    stall_cycles_lo_o = '0;
    stall_cycles_hi_o = '0;
    for (int unsigned channel = 0; channel < NumChannels; channel++) begin
      event_status_o[(channel*3)+:3] = {
        s_evt_err_q[channel], s_evt_half_q[channel], s_evt_done_q[channel]
      };
      error_status_o[(channel*32)+:32] = {
        23'd0,
        channel_error_status(
          s_err_code_q[channel],
          s_err_resp_q[channel],
          s_err_read_q[channel],
          s_stream_last_q[channel]
        )
      };
      error_addr_o[(channel*32)+:32] = s_err_addr_q[channel];
      current_src_o[(channel * 32) +: 32] = s_src_base_q[channel] +
                                             (s_src_increment_q[channel]
                                                  ? s_read_issued_q[channel]
                                                  : 32'd0);
      current_dst_o[(channel * 32) +: 32] = s_dst_base_q[channel] +
                                             (s_dst_increment_q[channel]
                                                  ? s_write_issued_q[channel]
                                                  : 32'd0);
      remaining_o[(channel*32)+:32] = s_len_q[channel] - s_bytes_done_q[channel];
      bytes_done_o[(channel*32)+:32] = s_bytes_done_q[channel];
      stall_cycles_lo_o[(channel*32)+:32] = s_stall_cycles_q[channel][31:0];
      stall_cycles_hi_o[(channel*32)+:32] = s_stall_cycles_q[channel][63:32];
    end
  end

  assign first_error_valid_o   = s_first_err_valid_q;
  assign first_error_channel_o = s_first_err_channel_q;
  assign first_error_status_o  = s_first_err_stat_q;
  assign first_error_addr_hi_o = s_first_err_addr_hi_q;
endmodule
