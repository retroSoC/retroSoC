// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "usb2_define.svh"

module usb2_scheduler #(
    parameter int NumEndpoints = 8,
    parameter int NumChannels  = 16
) (
    // verilog_format: off -- preserve register, mailbox, DMA, and status groups
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 enable_i,
    input  logic                 abort_i,
    input  logic                 reinitialize_i,
    input  logic                 perf_clear_i,
    input  logic                 high_speed_i,
    input  logic [13:0]          frame_i,
    input  usb2_pkg::usb2_role_e active_role_i,
    input  logic [NumEndpoints-1:0][31:0] endpoint_cfg_i,
    input  logic [NumEndpoints-1:0][31:0] endpoint_ram_in_i,
    input  logic [NumEndpoints-1:0][31:0] endpoint_ram_out_i,
    input  logic [NumEndpoints-1:0][31:0] endpoint_desc_in_i,
    input  logic [NumEndpoints-1:0][31:0] endpoint_desc_out_i,
    input  logic [NumEndpoints-1:0][31:0] endpoint_command_i,
    input  logic [31:0]          endpoint_complete_clear_in_i,
    input  logic [31:0]          endpoint_complete_clear_out_i,
    input  logic [NumChannels-1:0][31:0] channel_cfg_i,
    input  logic [NumChannels-1:0][31:0] channel_target_i,
    input  logic [NumChannels-1:0][31:0] channel_interval_i,
    input  logic [NumChannels-1:0][31:0] channel_ram_i,
    input  logic [NumChannels-1:0][31:0] channel_desc_i,
    input  logic [NumChannels-1:0][31:0] channel_command_i,
    output logic                 work_valid_o,
    input  logic                 work_ready_i,
    output logic [63:0]          work_data_o,
    input  logic                 result_valid_i,
    output logic                 result_ready_o,
    input  logic [63:0]          result_data_i,
    output logic                 fill_cmd_valid_o,
    input  logic                 fill_cmd_ready_i,
    output logic [26:0]          fill_cmd_data_o,
    output logic                 drain_cmd_valid_o,
    input  logic                 drain_cmd_ready_i,
    output logic [26:0]          drain_cmd_data_o,
    input  logic                 buffer_event_valid_i,
    output logic                 buffer_event_ready_o,
    input  logic [2:0]           buffer_event_data_i,
    output logic                 dma_start_o,
    output logic                 dma_abort_o,
    output logic                 dma_memory_to_packet_o,
    output logic [31:0]          dma_desc_base_o,
    output logic [31:0]          dma_transfer_bytes_o,
    input  logic                 dma_busy_i,
    input  logic                 dma_done_i,
    input  logic                 dma_error_i,
    input  logic [7:0]           dma_error_code_i,
    input  logic [31:0]          dma_current_desc_i,
    input  logic [31:0]          dma_bytes_done_i,
    input  logic                 retry_i,
    output logic [31:0]          endpoint_pending_in_o,
    output logic [31:0]          endpoint_pending_out_o,
    output logic [31:0]          endpoint_complete_in_o,
    output logic [31:0]          endpoint_complete_out_o,
    output logic [NumEndpoints-1:0][31:0] endpoint_status_o,
    output logic [NumEndpoints-1:0][31:0] endpoint_bytes_in_o,
    output logic [NumEndpoints-1:0][31:0] endpoint_bytes_out_o,
    output logic [NumChannels-1:0][31:0] channel_status_o,
    output logic [NumChannels-1:0][31:0] channel_bytes_o,
    output logic [15:0]          irq_event_o,
    output logic                 error_capture_o,
    output logic [31:0]          error_status_o,
    output logic [31:0]          error_code_o,
    output logic [31:0]          error_info_o,
    output logic [31:0]          error_desc_addr_o,
    output logic [31:0]          error_buffer_addr_o,
    output logic [31:0]          perf_tx_bytes_o,
    output logic [31:0]          perf_rx_bytes_o,
    output logic [31:0]          perf_packets_o,
    output logic [31:0]          perf_retries_o,
    output logic [31:0]          perf_irq_count_o,
    output logic                 busy_o
    // verilog_format: on
);
  typedef enum logic [3:0] {
    Idle,
    FillCommand,
    DmaStart,
    TransferWait,
    WorkSend,
    ResultWait,
    DrainCommand,
    DrainDmaStart,
    DrainWait,
    Complete
  } scheduler_state_e;

  scheduler_state_e s_state_d, s_state_q;
  logic [3:0] s_state_bits_q;
  logic [63:0] s_work_d, s_work_q;
  logic [31:0] s_desc_d, s_desc_q;
  logic [11:0] s_ram_base_d, s_ram_base_q;
  logic [14:0] s_len_d, s_len_q;
  logic s_wait_result_d, s_wait_result_q;
  logic s_dma_seen_d, s_dma_seen_q;
  logic s_buffer_seen_d, s_buffer_seen_q;
  logic s_fault_d, s_fault_q;
  logic [7:0] s_fault_code_d, s_fault_code_q;
  logic [3:0] s_completion_code_d, s_completion_code_q;
  logic [31:0] s_pending_in_d, s_pending_in_q;
  logic [31:0] s_pending_out_d, s_pending_out_q;
  logic [31:0] s_complete_in_d, s_complete_in_q;
  logic [31:0] s_complete_out_d, s_complete_out_q;
  logic [NumEndpoints-1:0][31:0] s_endpoint_stat_d, s_endpoint_stat_q;
  logic [NumEndpoints-1:0][31:0] s_endpoint_bytes_in_d, s_endpoint_bytes_in_q;
  logic [NumEndpoints-1:0][31:0] s_endpoint_bytes_out_d, s_endpoint_bytes_out_q;
  logic [NumChannels-1:0][31:0] s_channel_stat_d, s_channel_stat_q;
  logic [NumChannels-1:0][31:0] s_channel_bytes_d, s_channel_bytes_q;
  logic [31:0] s_perf_tx_bytes_d, s_perf_tx_bytes_q;
  logic [31:0] s_perf_rx_bytes_d, s_perf_rx_bytes_q;
  logic [31:0] s_perf_packets_d, s_perf_packets_q;
  logic [31:0] s_perf_retries_d, s_perf_retries_q;
  logic [31:0] s_perf_irq_count_d, s_perf_irq_count_q;
  logic [NumEndpoints-1:0][ 3:0] s_endpoint_cmd_pending_d;
  logic [NumEndpoints-1:0][ 3:0] s_endpoint_cmd_pending_q;
  logic [ NumChannels-1:0][ 3:0] s_channel_cmd_pending_d;
  logic [ NumChannels-1:0][ 3:0] s_channel_cmd_pending_q;
  logic [ NumChannels-1:0][13:0] s_channel_next_frame_d;
  logic [ NumChannels-1:0][13:0] s_channel_next_frame_q;
  logic [NumEndpoints-1:0][ 3:0] s_endpoint_cmd_merged;
  logic [ NumChannels-1:0][ 3:0] s_channel_cmd_merged;
  logic [ NumChannels-1:0]       s_channel_due;
  logic [15:0] s_irq_event_d, s_irq_event_q;
  logic s_err_capture_d, s_err_capture_q;
  logic [31:0] s_err_stat_d, s_err_stat_q;
  logic [31:0] s_err_code_d, s_err_code_q;
  logic [31:0] s_err_info_d, s_err_info_q;
  logic [31:0] s_err_desc_addr_d, s_err_desc_addr_q;
  logic [31:0] s_err_buffer_addr_d, s_err_buffer_addr_q;
  logic s_dma_start_d, s_dma_start_q;

  logic        s_cmd_valid;
  logic        s_cmd_is_channel;
  logic [ 3:0] s_cmd_index;
  logic [ 3:0] s_cmd_value;
  logic [ 1:0] s_result_role;
  logic [ 3:0] s_result_index;
  logic        s_result_direction_in;
  logic [ 3:0] s_result_code;
  logic [14:0] s_result_len;
  logic        s_current_direction_in;
  logic [ 1:0] s_current_role;
  logic [ 3:0] s_current_index;
  logic        s_transfer_fault;
  logic        s_buffer_event_match;

  function automatic logic frame_reached(input logic [13:0] current_i, input logic [13:0] target_i);
    return $signed(current_i - target_i) >= 0;
  endfunction

  for (genvar endpoint = 0; endpoint < NumEndpoints; endpoint++) begin : gen_command_merge
    assign s_endpoint_cmd_merged[endpoint] =
        s_endpoint_cmd_pending_q[endpoint] | endpoint_command_i[endpoint][3:0];
  end
  for (genvar channel = 0; channel < NumChannels; channel++) begin : gen_channel_schedule
    assign s_channel_cmd_merged[channel] =
        s_channel_cmd_pending_q[channel] | channel_command_i[channel][3:0];
    assign s_channel_due[channel] =
        ((channel_cfg_i[channel][3:2] != usb2_pkg::Usb2TransferIsochronous) &&
         (channel_cfg_i[channel][3:2] != usb2_pkg::Usb2TransferInterrupt)) ||
        (channel_interval_i[channel][13:0] == 14'd0) ||
        frame_reached(
        frame_i, s_channel_next_frame_q[channel]
    );
  end

  function automatic logic [63:0] make_work(
      input logic [1:0] role_i, input logic [3:0] index_i, input logic direction_in_i,
      input logic [1:0] type_i, input logic [6:0] address_i, input logic [3:0] endpoint_i,
      input logic [1:0] speed_i, input logic [11:0] ram_base_i, input logic [14:0] length_i,
      input logic setup_i, input logic cancel_i, input logic toggle_i);
    logic [63:0] value;
    begin
      value                                       = '0;
      value[usb2_pkg::USB2_WORK_ROLE_LSB+:2]      = role_i;
      value[usb2_pkg::USB2_WORK_INDEX_LSB+:4]     = index_i;
      value[usb2_pkg::USB2_WORK_DIRECTION_IN]     = direction_in_i;
      value[usb2_pkg::USB2_WORK_TYPE_LSB+:2]      = type_i;
      value[usb2_pkg::USB2_WORK_ADDRESS_LSB+:7]   = address_i;
      value[usb2_pkg::USB2_WORK_ENDPOINT_LSB+:4]  = endpoint_i;
      value[usb2_pkg::USB2_WORK_SPEED_LSB+:2]     = speed_i;
      value[usb2_pkg::USB2_WORK_RAM_BASE_LSB+:12] = ram_base_i;
      value[usb2_pkg::USB2_WORK_LENGTH_LSB+:15]   = length_i;
      value[usb2_pkg::USB2_WORK_SETUP]            = setup_i;
      value[usb2_pkg::USB2_WORK_CANCEL]           = cancel_i;
      value[usb2_pkg::USB2_WORK_TOGGLE]           = toggle_i;
      return value;
    end
  endfunction

  always_comb begin
    s_cmd_valid      = 1'b0;
    s_cmd_is_channel = 1'b0;
    s_cmd_index      = '0;
    s_cmd_value      = '0;
    for (int endpoint = NumEndpoints - 1; endpoint >= 0; endpoint--) begin
      if (s_endpoint_cmd_merged[endpoint] != 4'd0) begin
        s_cmd_valid      = 1'b1;
        s_cmd_is_channel = 1'b0;
        s_cmd_index      = 4'(endpoint);
        s_cmd_value      = s_endpoint_cmd_merged[endpoint];
      end
    end
    for (int channel = NumChannels - 1; channel >= 0; channel--) begin
      if (!s_cmd_valid && (s_channel_cmd_merged[channel] != 4'd0) && s_channel_due[channel]) begin
        s_cmd_valid      = 1'b1;
        s_cmd_is_channel = 1'b1;
        s_cmd_index      = 4'(channel);
        s_cmd_value      = s_channel_cmd_merged[channel];
      end
    end
  end

  assign s_state_q = scheduler_state_e'(s_state_bits_q);
  assign s_result_role = result_data_i[usb2_pkg::USB2_RESULT_ROLE_LSB+:2];
  assign s_result_index = result_data_i[usb2_pkg::USB2_RESULT_INDEX_LSB+:4];
  assign s_result_direction_in = result_data_i[usb2_pkg::USB2_RESULT_DIRECTION_IN];
  assign s_result_code = result_data_i[usb2_pkg::USB2_RESULT_CODE_LSB+:4];
  assign s_result_len = result_data_i[usb2_pkg::USB2_RESULT_LENGTH_LSB+:15];
  assign s_current_role = s_work_q[usb2_pkg::USB2_WORK_ROLE_LSB+:2];
  assign s_current_index = s_work_q[usb2_pkg::USB2_WORK_INDEX_LSB+:4];
  assign s_current_direction_in = s_work_q[usb2_pkg::USB2_WORK_DIRECTION_IN];
  assign s_buffer_event_match = buffer_event_valid_i &&
                                (((s_state_q == TransferWait) &&
                                  (buffer_event_data_i[1:0] == 2'd0)) ||
                                 ((s_state_q == DrainWait) &&
                                  (buffer_event_data_i[1:0] == 2'd1)));
  assign s_transfer_fault = s_fault_q || dma_error_i ||
                            (s_buffer_event_match && buffer_event_data_i[2]);

  assign work_valid_o = s_state_q == WorkSend;
  assign work_data_o = s_work_q;
  assign result_ready_o = (s_state_q == Idle) || (s_state_q == ResultWait);
  assign fill_cmd_valid_o = s_state_q == FillCommand;
  assign fill_cmd_data_o = {s_len_q, s_ram_base_q};
  assign drain_cmd_valid_o = s_state_q == DrainCommand;
  assign drain_cmd_data_o = {s_len_q, s_ram_base_q};
  assign buffer_event_ready_o = s_buffer_event_match;
  assign dma_start_o = s_dma_start_q;
  assign dma_abort_o = abort_i;
  assign dma_memory_to_packet_o = (s_state_q != DrainDmaStart) && (s_state_q != DrainWait);
  assign dma_desc_base_o = s_desc_q;
  assign dma_transfer_bytes_o = {17'd0, s_len_q};
  assign endpoint_pending_in_o = s_pending_in_q;
  assign endpoint_pending_out_o = s_pending_out_q;
  assign endpoint_complete_in_o = s_complete_in_q;
  assign endpoint_complete_out_o = s_complete_out_q;
  assign irq_event_o = s_irq_event_q;
  assign error_capture_o = s_err_capture_q;
  assign error_status_o = s_err_stat_q;
  assign error_code_o = s_err_code_q;
  assign error_info_o = s_err_info_q;
  assign error_desc_addr_o = s_err_desc_addr_q;
  assign error_buffer_addr_o = s_err_buffer_addr_q;
  assign perf_tx_bytes_o = s_perf_tx_bytes_q;
  assign perf_rx_bytes_o = s_perf_rx_bytes_q;
  assign perf_packets_o = s_perf_packets_q;
  assign perf_retries_o = s_perf_retries_q;
  assign perf_irq_count_o = s_perf_irq_count_q;
  assign busy_o = s_state_q != Idle;

  for (genvar endpoint = 0; endpoint < NumEndpoints; endpoint++) begin : gen_endpoint_outputs
    assign endpoint_status_o[endpoint]    = s_endpoint_stat_q[endpoint];
    assign endpoint_bytes_in_o[endpoint]  = s_endpoint_bytes_in_q[endpoint];
    assign endpoint_bytes_out_o[endpoint] = s_endpoint_bytes_out_q[endpoint];
  end
  for (genvar channel = 0; channel < NumChannels; channel++) begin : gen_channel_outputs
    assign channel_status_o[channel] = s_channel_stat_q[channel];
    assign channel_bytes_o[channel]  = s_channel_bytes_q[channel];
  end

  always_comb begin
    s_state_d              = s_state_q;
    s_work_d               = s_work_q;
    s_desc_d               = s_desc_q;
    s_ram_base_d           = s_ram_base_q;
    s_len_d                = s_len_q;
    s_wait_result_d        = s_wait_result_q;
    s_dma_seen_d           = s_dma_seen_q || dma_done_i;
    s_buffer_seen_d        = s_buffer_seen_q || (s_buffer_event_match && buffer_event_ready_o);
    s_fault_d              = s_transfer_fault;
    s_fault_code_d         = dma_error_i ? dma_error_code_i : s_fault_code_q;
    s_completion_code_d    = s_completion_code_q;
    s_pending_in_d         = s_pending_in_q;
    s_pending_out_d        = s_pending_out_q;
    s_complete_in_d        = s_complete_in_q & ~endpoint_complete_clear_in_i;
    s_complete_out_d       = s_complete_out_q & ~endpoint_complete_clear_out_i;
    s_endpoint_stat_d      = s_endpoint_stat_q;
    s_endpoint_bytes_in_d  = s_endpoint_bytes_in_q;
    s_endpoint_bytes_out_d = s_endpoint_bytes_out_q;
    s_channel_stat_d       = s_channel_stat_q;
    s_channel_bytes_d      = s_channel_bytes_q;
    s_perf_tx_bytes_d      = s_perf_tx_bytes_q;
    s_perf_rx_bytes_d      = s_perf_rx_bytes_q;
    s_perf_packets_d       = s_perf_packets_q;
    s_perf_retries_d       = s_perf_retries_q;
    s_perf_irq_count_d     = s_perf_irq_count_q;
    for (int endpoint = 0; endpoint < NumEndpoints; endpoint++) begin
      s_endpoint_cmd_pending_d[endpoint] = s_endpoint_cmd_merged[endpoint];
    end
    for (int channel = 0; channel < NumChannels; channel++) begin
      s_channel_cmd_pending_d[channel] = s_channel_cmd_merged[channel];
      s_channel_next_frame_d[channel]  = s_channel_next_frame_q[channel];
    end
    s_irq_event_d       = '0;
    s_err_capture_d     = 1'b0;
    s_err_stat_d        = '0;
    s_err_code_d        = '0;
    s_err_info_d        = '0;
    s_err_desc_addr_d   = '0;
    s_err_buffer_addr_d = '0;
    s_dma_start_d       = 1'b0;

    if (retry_i && !(&s_perf_retries_q)) begin
      s_perf_retries_d = s_perf_retries_q + 1'b1;
    end
    if (perf_clear_i) begin
      s_perf_tx_bytes_d  = 32'd0;
      s_perf_rx_bytes_d  = 32'd0;
      s_perf_packets_d   = 32'd0;
      s_perf_retries_d   = 32'd0;
      s_perf_irq_count_d = 32'd0;
    end

    unique case (s_state_q)
      Idle: begin
        s_dma_seen_d        = 1'b0;
        s_buffer_seen_d     = 1'b0;
        s_fault_d           = 1'b0;
        s_fault_code_d      = '0;
        s_completion_code_d = usb2_pkg::Usb2ResultSuccess;
        if (result_valid_i && result_ready_o) begin
          s_work_d            = result_data_i;
          s_len_d             = s_result_len;
          s_completion_code_d = s_result_code;
          if (s_result_code != usb2_pkg::Usb2ResultSuccess) begin
            s_fault_d      = 1'b1;
            s_fault_code_d = {4'h8, s_result_code};
          end
          if ((s_result_code == usb2_pkg::Usb2ResultSuccess) &&
              (((s_result_role == usb2_pkg::Usb2RoleDevice) && !s_result_direction_in) ||
               ((s_result_role == usb2_pkg::Usb2RoleHost) && s_result_direction_in))) begin
            if (s_result_role == usb2_pkg::Usb2RoleDevice) begin
              s_ram_base_d = endpoint_ram_out_i[s_result_index][13:2];
              s_desc_d     = endpoint_desc_out_i[s_result_index];
            end else begin
              s_ram_base_d = channel_ram_i[s_result_index][13:2];
              s_desc_d     = channel_desc_i[s_result_index];
            end
            s_state_d = DrainCommand;
          end else begin
            s_state_d = Complete;
          end
        end else if (enable_i && s_cmd_valid &&
                     ((s_cmd_is_channel &&
                       (active_role_i == usb2_pkg::Usb2RoleHost)) ||
                      (!s_cmd_is_channel &&
                       (active_role_i == usb2_pkg::Usb2RoleDevice)))) begin
          if (s_cmd_is_channel) begin
            s_channel_cmd_pending_d[s_cmd_index] = 4'd0;
            if ((channel_cfg_i[s_cmd_index][3:2] ==
                 usb2_pkg::Usb2TransferIsochronous) ||
                (channel_cfg_i[s_cmd_index][3:2] ==
                 usb2_pkg::Usb2TransferInterrupt)) begin
              s_channel_next_frame_d[s_cmd_index] =
                  frame_i + ((channel_interval_i[s_cmd_index][13:0] == 14'd0) ?
                                 14'd1 : channel_interval_i[s_cmd_index][13:0]);
            end
            s_work_d = make_work(
              usb2_pkg::Usb2RoleHost,
              s_cmd_index,
              channel_cfg_i[s_cmd_index][`APB4_USB2__CHANNEL_CFG_DIRECTION_IN],
              channel_cfg_i[s_cmd_index][3:2],
              channel_target_i[s_cmd_index][6:0],
              channel_target_i[s_cmd_index][11:8],
              channel_cfg_i[s_cmd_index][`APB4_USB2__CHANNEL_CFG_LOW_SPEED] ?
                    usb2_pkg::Usb2SpeedLow :
                    (high_speed_i ? usb2_pkg::Usb2SpeedHigh : usb2_pkg::Usb2SpeedFull),
              channel_ram_i[s_cmd_index][13:2],
              channel_ram_i[s_cmd_index][30:16],
              channel_cfg_i[s_cmd_index][`APB4_USB2__CHANNEL_CFG_SETUP],
              s_cmd_value[`APB4_USB2__CHANNEL_COMMAND_CANCEL],
              channel_target_i[s_cmd_index][`APB4_USB2__CHANNEL_TARGET_TOGGLE]
            );
            s_desc_d = channel_desc_i[s_cmd_index];
            s_ram_base_d = channel_ram_i[s_cmd_index][13:2];
            s_len_d = channel_ram_i[s_cmd_index][30:16];
            s_wait_result_d = 1'b1;
            s_channel_stat_d[s_cmd_index] = 32'h0000_0001;
            if (s_cmd_value[`APB4_USB2__CHANNEL_COMMAND_CANCEL] ||
                channel_cfg_i[s_cmd_index][`APB4_USB2__CHANNEL_CFG_DIRECTION_IN]) begin
              s_state_d = WorkSend;
            end else begin
              s_state_d = FillCommand;
            end
          end else begin
            s_endpoint_cmd_pending_d[s_cmd_index] = 4'd0;
            if (s_cmd_value[`APB4_USB2__ENDPOINT_COMMAND_RESET_TOGGLE]) begin
              s_endpoint_stat_d[s_cmd_index][9:8] = 2'b00;
            end
            if (s_cmd_value[`APB4_USB2__ENDPOINT_COMMAND_CANCEL]) begin
              s_work_d = make_work(
                usb2_pkg::Usb2RoleDevice,
                s_cmd_index,
                1'b0,
                endpoint_cfg_i[s_cmd_index][5:4],
                7'd0,
                s_cmd_index,
                high_speed_i ? usb2_pkg::Usb2SpeedHigh : usb2_pkg::Usb2SpeedFull,
                12'd0,
                15'd0,
                1'b0,
                1'b1,
                1'b0
              );
              s_wait_result_d = 1'b0;
              s_pending_in_d[{1'b0, s_cmd_index}] = 1'b0;
              s_pending_out_d[{1'b0, s_cmd_index}] = 1'b0;
              s_state_d = WorkSend;
            end else if (s_cmd_value[`APB4_USB2__ENDPOINT_COMMAND_PRIME_IN]) begin
              s_work_d = make_work(
                usb2_pkg::Usb2RoleDevice,
                s_cmd_index,
                1'b1,
                endpoint_cfg_i[s_cmd_index][5:4],
                7'd0,
                s_cmd_index,
                high_speed_i ? usb2_pkg::Usb2SpeedHigh : usb2_pkg::Usb2SpeedFull,
                endpoint_ram_in_i[s_cmd_index][13:2],
                endpoint_ram_in_i[s_cmd_index][30:16],
                1'b0,
                1'b0,
                s_endpoint_stat_q[s_cmd_index][8]
              );
              s_desc_d = endpoint_desc_in_i[s_cmd_index];
              s_ram_base_d = endpoint_ram_in_i[s_cmd_index][13:2];
              s_len_d = endpoint_ram_in_i[s_cmd_index][30:16];
              s_wait_result_d = 1'b0;
              s_pending_in_d[{1'b0, s_cmd_index}] = 1'b1;
              s_complete_in_d[{1'b0, s_cmd_index}] = 1'b0;
              s_endpoint_stat_d[s_cmd_index] = 32'h0000_0001;
              s_state_d = FillCommand;
            end else if (s_cmd_value[`APB4_USB2__ENDPOINT_COMMAND_ARM_OUT]) begin
              s_work_d = make_work(
                usb2_pkg::Usb2RoleDevice,
                s_cmd_index,
                1'b0,
                endpoint_cfg_i[s_cmd_index][5:4],
                7'd0,
                s_cmd_index,
                high_speed_i ? usb2_pkg::Usb2SpeedHigh : usb2_pkg::Usb2SpeedFull,
                endpoint_ram_out_i[s_cmd_index][13:2],
                endpoint_ram_out_i[s_cmd_index][30:16],
                1'b0,
                1'b0,
                s_endpoint_stat_q[s_cmd_index][9]
              );
              s_wait_result_d = 1'b0;
              s_pending_out_d[{1'b0, s_cmd_index}] = 1'b1;
              s_complete_out_d[{1'b0, s_cmd_index}] = 1'b0;
              s_endpoint_stat_d[s_cmd_index] = 32'h0000_0001;
              s_state_d = WorkSend;
            end
          end
        end
      end
      FillCommand: begin
        if (fill_cmd_valid_o && fill_cmd_ready_i) begin
          s_state_d = DmaStart;
        end
      end
      DmaStart: begin
        if (!dma_busy_i) begin
          s_dma_start_d   = 1'b1;
          s_dma_seen_d    = 1'b0;
          s_buffer_seen_d = 1'b0;
          s_state_d       = TransferWait;
        end
      end
      TransferWait: begin
        if (s_transfer_fault) begin
          s_state_d = Complete;
        end else if ((s_dma_seen_d || dma_done_i) &&
                     (s_buffer_seen_d || s_buffer_event_match)) begin
          s_perf_tx_bytes_d = s_perf_tx_bytes_q + dma_bytes_done_i;
          s_state_d         = WorkSend;
        end
      end
      WorkSend: begin
        if (work_valid_o && work_ready_i) begin
          if (s_wait_result_q) begin
            s_state_d = ResultWait;
          end else begin
            s_state_d = Idle;
          end
        end
      end
      ResultWait: begin
        if (result_valid_i && result_ready_o) begin
          s_work_d            = result_data_i;
          s_len_d             = s_result_len;
          s_completion_code_d = s_result_code;
          if (s_result_code != usb2_pkg::Usb2ResultSuccess) begin
            s_fault_d      = 1'b1;
            s_fault_code_d = {4'h8, s_result_code};
          end
          if ((s_result_code == usb2_pkg::Usb2ResultSuccess) && s_result_direction_in) begin
            s_ram_base_d = channel_ram_i[s_result_index][13:2];
            s_desc_d     = channel_desc_i[s_result_index];
            s_state_d    = DrainCommand;
          end else begin
            s_state_d = Complete;
          end
        end
      end
      DrainCommand: begin
        if (drain_cmd_valid_o && drain_cmd_ready_i) begin
          s_state_d = DrainDmaStart;
        end
      end
      DrainDmaStart: begin
        if (!dma_busy_i) begin
          s_dma_start_d   = 1'b1;
          s_dma_seen_d    = 1'b0;
          s_buffer_seen_d = 1'b0;
          s_state_d       = DrainWait;
        end
      end
      DrainWait: begin
        if (s_transfer_fault) begin
          s_state_d = Complete;
        end else if ((s_dma_seen_d || dma_done_i) &&
                     (s_buffer_seen_d || s_buffer_event_match)) begin
          s_perf_rx_bytes_d = s_perf_rx_bytes_q + dma_bytes_done_i;
          s_state_d         = Complete;
        end
      end
      Complete: begin
        if (s_current_role == usb2_pkg::Usb2RoleDevice) begin
          if (s_current_direction_in) begin
            s_pending_in_d[{1'b0, s_current_index}] = 1'b0;
            s_complete_in_d[{1'b0, s_current_index}] = 1'b1;
            s_endpoint_bytes_in_d[s_current_index] = s_endpoint_bytes_in_q[s_current_index] +
                                                      {17'd0, s_len_q};
            s_endpoint_stat_d[s_current_index] = 32'd0;
            s_endpoint_stat_d[s_current_index][1] = 1'b1;
            s_endpoint_stat_d[s_current_index][2] = s_fault_q;
            s_endpoint_stat_d[s_current_index][7:4] =
                s_fault_q ? s_fault_code_q[3:0] : s_completion_code_q;
            s_endpoint_stat_d[s_current_index][8] = !s_endpoint_stat_q[s_current_index][8];
          end else begin
            s_pending_out_d[{1'b0, s_current_index}] = 1'b0;
            s_complete_out_d[{1'b0, s_current_index}] = 1'b1;
            s_endpoint_bytes_out_d[s_current_index] = s_endpoint_bytes_out_q[s_current_index] +
                                                       {17'd0, s_len_q};
            s_endpoint_stat_d[s_current_index] = 32'd0;
            s_endpoint_stat_d[s_current_index][1] = 1'b1;
            s_endpoint_stat_d[s_current_index][2] = s_fault_q;
            s_endpoint_stat_d[s_current_index][7:4] =
                s_fault_q ? s_fault_code_q[3:0] : s_completion_code_q;
            s_endpoint_stat_d[s_current_index][9] = !s_endpoint_stat_q[s_current_index][9];
          end
          s_irq_event_d[`APB4_USB2__IRQ_ENDPOINT] = 1'b1;
        end else begin
          s_channel_bytes_d[s_current_index] = s_channel_bytes_q[s_current_index] +
                                                {17'd0, s_len_q};
          s_channel_stat_d[s_current_index] = 32'd0;
          s_channel_stat_d[s_current_index][1] = 1'b1;
          s_channel_stat_d[s_current_index][2] = s_fault_q;
          s_channel_stat_d[s_current_index][7:4] =
              s_fault_q ? s_fault_code_q[3:0] : s_completion_code_q;
          s_irq_event_d[`APB4_USB2__IRQ_CHANNEL] = 1'b1;
        end
        s_irq_event_d[s_fault_q?`APB4_USB2__IRQ_DMA_ERROR : `APB4_USB2__IRQ_DMA_DONE] = 1'b1;
        s_perf_packets_d = s_perf_packets_q + 1'b1;
        s_perf_irq_count_d = s_perf_irq_count_q + 1'b1;
        if (s_fault_q) begin
          s_err_capture_d = 1'b1;
          s_err_stat_d = 32'h0000_0001;
          s_err_code_d = {24'd0, s_fault_code_q};
          s_err_info_d = {16'd0, s_current_role, 9'd0, s_current_direction_in, s_current_index};
          s_err_desc_addr_d = dma_current_desc_i;
          s_err_buffer_addr_d = {20'd0, s_ram_base_q} << 2;
        end
        s_state_d = Idle;
      end
      default: s_state_d = Idle;
    endcase

    if (abort_i) begin
      s_fault_d      = 1'b1;
      s_fault_code_d = 8'h06;
      if (s_state_q != Idle) begin
        s_state_d = Complete;
      end
    end
    if (reinitialize_i) begin
      s_state_d         = Idle;
      s_pending_in_d    = 32'd0;
      s_pending_out_d   = 32'd0;
      s_complete_in_d   = 32'd0;
      s_complete_out_d  = 32'd0;
      s_endpoint_stat_d = '0;
      s_channel_stat_d  = '0;
      for (int endpoint = 0; endpoint < NumEndpoints; endpoint++) begin
        s_endpoint_cmd_pending_d[endpoint] = 4'd0;
      end
      for (int channel = 0; channel < NumChannels; channel++) begin
        s_channel_cmd_pending_d[channel] = 4'd0;
        s_channel_next_frame_d[channel]  = 14'd0;
      end
    end
  end

  dffr #(
      .DATA_WIDTH(4)
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_work_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_work_d),
      .dat_o  (s_work_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_desc_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_desc_d),
      .dat_o  (s_desc_q)
  );
  dffr #(
      .DATA_WIDTH(12)
  ) u_ram_base_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ram_base_d),
      .dat_o  (s_ram_base_q)
  );
  dffr #(
      .DATA_WIDTH(15)
  ) u_length_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_len_d),
      .dat_o  (s_len_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_wait_result_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_wait_result_d),
      .dat_o  (s_wait_result_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_dma_seen_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dma_seen_d),
      .dat_o  (s_dma_seen_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_buffer_seen_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_buffer_seen_d),
      .dat_o  (s_buffer_seen_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_fault_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_d),
      .dat_o  (s_fault_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_fault_code_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_code_d),
      .dat_o  (s_fault_code_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_completion_code_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_completion_code_d),
      .dat_o  (s_completion_code_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_pending_in_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pending_in_d),
      .dat_o  (s_pending_in_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_pending_out_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pending_out_d),
      .dat_o  (s_pending_out_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_complete_in_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_complete_in_d),
      .dat_o  (s_complete_in_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_complete_out_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_complete_out_d),
      .dat_o  (s_complete_out_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_tx_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_tx_bytes_d),
      .dat_o  (s_perf_tx_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_rx_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_rx_bytes_d),
      .dat_o  (s_perf_rx_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_packets_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_packets_d),
      .dat_o  (s_perf_packets_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_retries_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_retries_d),
      .dat_o  (s_perf_retries_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_irq_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_irq_count_d),
      .dat_o  (s_perf_irq_count_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_irq_event_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_irq_event_d),
      .dat_o  (s_irq_event_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_error_capture_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_capture_d),
      .dat_o  (s_err_capture_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_error_status_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_stat_d),
      .dat_o  (s_err_stat_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_error_code_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_code_d),
      .dat_o  (s_err_code_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_error_info_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_info_d),
      .dat_o  (s_err_info_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_error_desc_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_desc_addr_d),
      .dat_o  (s_err_desc_addr_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_error_buffer_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_buffer_addr_d),
      .dat_o  (s_err_buffer_addr_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_dma_start_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dma_start_d),
      .dat_o  (s_dma_start_q)
  );

  for (genvar endpoint = 0; endpoint < NumEndpoints; endpoint++) begin : gen_endpoint_state
    dffr #(
        .DATA_WIDTH(4)
    ) u_command_pending_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_endpoint_cmd_pending_d[endpoint]),
        .dat_o  (s_endpoint_cmd_pending_q[endpoint])
    );
    dffr #(
        .DATA_WIDTH(32)
    ) u_status_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_endpoint_stat_d[endpoint]),
        .dat_o  (s_endpoint_stat_q[endpoint])
    );
    dffr #(
        .DATA_WIDTH(32)
    ) u_bytes_in_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_endpoint_bytes_in_d[endpoint]),
        .dat_o  (s_endpoint_bytes_in_q[endpoint])
    );
    dffr #(
        .DATA_WIDTH(32)
    ) u_bytes_out_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_endpoint_bytes_out_d[endpoint]),
        .dat_o  (s_endpoint_bytes_out_q[endpoint])
    );
  end
  for (genvar channel = 0; channel < NumChannels; channel++) begin : gen_channel_state
    dffr #(
        .DATA_WIDTH(4)
    ) u_command_pending_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_cmd_pending_d[channel]),
        .dat_o  (s_channel_cmd_pending_q[channel])
    );
    dffr #(
        .DATA_WIDTH(14)
    ) u_next_frame_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_next_frame_d[channel]),
        .dat_o  (s_channel_next_frame_q[channel])
    );
    dffr #(
        .DATA_WIDTH(32)
    ) u_status_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_stat_d[channel]),
        .dat_o  (s_channel_stat_q[channel])
    );
    dffr #(
        .DATA_WIDTH(32)
    ) u_bytes_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_bytes_d[channel]),
        .dat_o  (s_channel_bytes_q[channel])
    );
  end

`ifndef SYNTHESIS
  initial begin
    if ((NumEndpoints != 8) || (NumChannels != 16)) begin
      $fatal(1, "usb2_scheduler: delivered configuration requires 8 endpoints and 16 channels");
    end
  end
`endif
endmodule
