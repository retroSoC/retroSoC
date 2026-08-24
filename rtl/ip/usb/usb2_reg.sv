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

module usb2_reg #(
    parameter int NumEndpoints = 8,
    parameter int NumChannels  = 16
) (
    // verilog_format: off -- preserve APB, status, and configuration port groups
    input  logic        clk_i,
    input  logic        rst_n_i,
    apb4_if.slave       apb4,
    input  logic [31:0] global_status_i,
    input  logic [31:0] role_status_i,
    input  logic [31:0] phy_status_i,
    input  logic [31:0] frame_i,
    input  logic [31:0] device_status_i,
    input  logic [63:0] setup_packet_i,
    input  logic [31:0] endpoint_pending_in_i,
    input  logic [31:0] endpoint_pending_out_i,
    input  logic [31:0] endpoint_complete_in_i,
    input  logic [31:0] endpoint_complete_out_i,
    input  logic [NumEndpoints-1:0][31:0] endpoint_status_i,
    input  logic [NumEndpoints-1:0][31:0] endpoint_bytes_in_i,
    input  logic [NumEndpoints-1:0][31:0] endpoint_bytes_out_i,
    input  logic [31:0] host_status_i,
    input  logic [31:0] port_status_i,
    input  logic [31:0] schedule_status_i,
    input  logic [NumChannels-1:0][31:0] channel_status_i,
    input  logic [NumChannels-1:0][31:0] channel_bytes_i,
    input  logic [31:0] ram_status_i,
    input  logic [31:0] ecc_status_i,
    input  logic [31:0] ecc_corrected_count_i,
    input  logic [31:0] ecc_uncorrectable_count_i,
    input  logic [31:0] debug_status_i,
    input  logic [31:0] perf_tx_bytes_i,
    input  logic [31:0] perf_rx_bytes_i,
    input  logic [31:0] perf_packets_i,
    input  logic [31:0] perf_retries_i,
    input  logic [31:0] perf_axi_stall_i,
    input  logic [31:0] perf_ram_stall_i,
    input  logic [31:0] perf_irq_count_i,
    input  logic [15:0] irq_event_i,
    input  logic        error_capture_i,
    input  logic [31:0] error_status_i,
    input  logic [31:0] error_code_i,
    input  logic [31:0] error_info_i,
    input  logic [31:0] error_desc_addr_i,
    input  logic [31:0] error_buffer_addr_i,
    input  logic        viewport_resp_valid_i,
    input  logic [7:0]  viewport_read_data_i,
    input  logic        viewport_error_i,
    output logic        enable_o,
    output logic        soft_reset_o,
    output logic        abort_o,
    output logic [1:0]  force_role_o,
    output logic        auto_role_o,
    output logic        phy_reset_n_o,
    output logic        phy_suspend_o,
    output logic        remote_wake_o,
    output logic [31:0] timeout_o,
    output logic [7:0]  test_ctrl_o,
    output logic        perf_clear_o,
    output logic [6:0]  device_addr_o,
    output logic [15:0] device_ctrl_o,
    output logic [NumEndpoints-1:0][31:0] endpoint_cfg_o,
    output logic [NumEndpoints-1:0][31:0] endpoint_ram_in_o,
    output logic [NumEndpoints-1:0][31:0] endpoint_ram_out_o,
    output logic [NumEndpoints-1:0][31:0] endpoint_desc_in_o,
    output logic [NumEndpoints-1:0][31:0] endpoint_desc_out_o,
    output logic [NumEndpoints-1:0][31:0] endpoint_command_o,
    output logic [31:0] endpoint_complete_clear_in_o,
    output logic [31:0] endpoint_complete_clear_out_o,
    output logic [15:0] host_ctrl_o,
    output logic        port_ctrl_o,
    output logic        schedule_ctrl_o,
    output logic [NumChannels-1:0][31:0] channel_cfg_o,
    output logic [NumChannels-1:0][31:0] channel_target_o,
    output logic [NumChannels-1:0][31:0] channel_interval_o,
    output logic [NumChannels-1:0][31:0] channel_ram_o,
    output logic [NumChannels-1:0][31:0] channel_desc_o,
    output logic [NumChannels-1:0][31:0] channel_command_o,
    output logic [15:0] ram_ctrl_o,
    output logic        ram_bist_start_o,
    output logic        viewport_valid_o,
    output logic        viewport_write_o,
    output logic [5:0]  viewport_addr_o,
    output logic [7:0]  viewport_write_data_o,
    output logic        irq_o
    // verilog_format: on
);
  localparam logic [31:0] IpId = 32'h5553_4232;
  localparam logic [31:0] IpVersion = 32'h0001_0000;
  localparam logic [31:0] Capability0 =
      (32'd1 << 0) | (32'd1 << 1) | (32'd1 << 2) | (32'd1 << 3) |
      (32'd1 << 4) | (32'd1 << 5) | (32'd1 << 6) | (32'd1 << 7) |
      (32'd1 << 8) | (32'd1 << 9) | (32'd1 << 10) | (32'd1 << 11) |
      (32'd1 << 12) | (32'(NumEndpoints - 1) << 16) |
      (32'(NumChannels - 1) << 24);
  localparam logic [31:0] Capability1 = 32'h0010_4000;

  logic s_apb4_ready_d, s_apb4_ready_q;
  logic [31:0] s_apb4_rdata_d, s_apb4_rdata_q;
  logic s_apb4_resp_err_d, s_apb4_resp_err_q;
  logic                            s_req_accept;
  logic                            s_write_access;
  logic                            s_read_err;
  logic                            s_write_err;
  logic [                    31:0] s_read_data;
  logic [                    11:0] s_offset;
  logic                            s_endpoint_window;
  logic                            s_channel_window;
  logic [$clog2(NumEndpoints)-1:0] s_endpoint_index;
  logic [ $clog2(NumChannels)-1:0] s_channel_index;
  logic [                     8:0] s_endpoint_delta;
  logic [                     9:0] s_channel_delta;
  logic [                    11:0] s_endpoint_offset;
  logic [                    11:0] s_channel_offset;
  logic [                    15:0] s_irq_en_merged;

  logic [3:0] s_global_ctrl_d, s_global_ctrl_q;
  logic [2:0] s_role_ctrl_d, s_role_ctrl_q;
  logic [2:0] s_phy_ctrl_d, s_phy_ctrl_q;
  logic [31:0] s_timeout_d, s_timeout_q;
  logic [31:0] s_test_ctrl_d, s_test_ctrl_q;
  logic [31:0] s_device_ctrl_d, s_device_ctrl_q;
  logic [6:0] s_device_addr_d, s_device_addr_q;
  logic [31:0] s_host_ctrl_d, s_host_ctrl_q;
  logic [31:0] s_port_ctrl_d, s_port_ctrl_q;
  logic [31:0] s_schedule_ctrl_d, s_schedule_ctrl_q;
  logic [31:0] s_ram_ctrl_d, s_ram_ctrl_q;
  logic [15:0] s_irq_stat_d, s_irq_stat_q;
  logic [15:0] s_irq_en_d, s_irq_en_q;
  logic [31:0] s_err_stat_d, s_err_stat_q;
  logic [31:0] s_err_code_d, s_err_code_q;
  logic [31:0] s_err_info_d, s_err_info_q;
  logic [31:0] s_err_desc_addr_d, s_err_desc_addr_q;
  logic [31:0] s_err_buffer_addr_d, s_err_buffer_addr_q;
  logic [NumEndpoints-1:0][31:0] s_endpoint_cfg_d, s_endpoint_cfg_q;
  logic [NumEndpoints-1:0][31:0] s_endpoint_ram_in_d, s_endpoint_ram_in_q;
  logic [NumEndpoints-1:0][31:0] s_endpoint_ram_out_d, s_endpoint_ram_out_q;
  logic [NumEndpoints-1:0][31:0] s_endpoint_desc_in_d, s_endpoint_desc_in_q;
  logic [NumEndpoints-1:0][31:0] s_endpoint_desc_out_d, s_endpoint_desc_out_q;
  logic [NumEndpoints-1:0][31:0] s_endpoint_cmd_d, s_endpoint_cmd_q;
  logic [NumChannels-1:0][31:0] s_channel_cfg_d, s_channel_cfg_q;
  logic [NumChannels-1:0][31:0] s_channel_target_d, s_channel_target_q;
  logic [NumChannels-1:0][31:0] s_channel_interval_d, s_channel_interval_q;
  logic [NumChannels-1:0][31:0] s_channel_ram_d, s_channel_ram_q;
  logic [NumChannels-1:0][31:0] s_channel_desc_d, s_channel_desc_q;
  logic [NumChannels-1:0][31:0] s_channel_cmd_d, s_channel_cmd_q;
  logic s_soft_reset_d, s_soft_reset_q;
  logic s_abort_d, s_abort_q;
  logic s_perf_clear_d, s_perf_clear_q;
  logic s_ram_bist_start_d, s_ram_bist_start_q;
  logic s_viewport_valid_d, s_viewport_valid_q;
  logic s_viewport_write_d, s_viewport_write_q;
  logic [5:0] s_viewport_addr_d, s_viewport_addr_q;
  logic [7:0] s_viewport_write_data_d, s_viewport_write_data_q;
  logic [7:0] s_viewport_read_data_d, s_viewport_read_data_q;
  logic s_viewport_busy_d, s_viewport_busy_q;
  logic s_viewport_err_d, s_viewport_err_q;

  function automatic logic [31:0] apply_wstrb(input logic [31:0] prior_i, input logic [31:0] data_i,
                                              input logic [3:0] strb_i);
    logic [31:0] value;
    begin
      value = prior_i;
      for (int unsigned byte_index = 0; byte_index < 4; byte_index++) begin
        if (strb_i[byte_index]) begin
          value[(byte_index*8)+:8] = data_i[(byte_index*8)+:8];
        end
      end
      return value;
    end
  endfunction

  assign s_offset = apb4.paddr[11:0];
  assign s_endpoint_window = (s_offset >= `APB4_USB2__ENDPOINT_BASE) && (s_offset < 12'h400);
  assign s_channel_window = (s_offset >= `APB4_USB2__CHANNEL_BASE) && (s_offset < 12'h900);
  assign s_endpoint_delta = 9'(s_offset - `APB4_USB2__ENDPOINT_BASE);
  assign s_channel_delta = 10'(s_offset - `APB4_USB2__CHANNEL_BASE);
  assign s_endpoint_index = s_endpoint_delta[8:6];
  assign s_channel_index = s_channel_delta[9:6];
  assign s_endpoint_offset = {6'd0, s_endpoint_delta[5:0]};
  assign s_channel_offset = {6'd0, s_channel_delta[5:0]};
  assign s_irq_en_merged = 16'(apply_wstrb({16'd0, s_irq_en_q}, apb4.pwdata, apb4.pstrb));
  assign s_req_accept = apb4.psel && apb4.penable && !s_apb4_ready_q;
  assign s_write_access = s_req_accept && apb4.pwrite;
  assign apb4.pready = s_apb4_ready_q;
  assign apb4.prdata = s_apb4_rdata_q;
  assign apb4.pslverr = s_apb4_resp_err_q;

  assign enable_o = s_global_ctrl_q[`APB4_USB2__GLOBAL_CTRL_ENABLE];
  assign soft_reset_o = s_soft_reset_q;
  assign abort_o = s_abort_q;
  assign force_role_o = s_role_ctrl_q[1:0];
  assign auto_role_o = s_role_ctrl_q[`APB4_USB2__ROLE_CTRL_AUTO];
  assign phy_reset_n_o = s_phy_ctrl_q[`APB4_USB2__PHY_CTRL_RESET_N];
  assign phy_suspend_o = s_phy_ctrl_q[`APB4_USB2__PHY_CTRL_SUSPEND];
  assign remote_wake_o = s_phy_ctrl_q[`APB4_USB2__PHY_CTRL_REMOTE_WAKE];
  assign timeout_o = s_timeout_q;
  assign test_ctrl_o = s_test_ctrl_q[7:0];
  assign perf_clear_o = s_perf_clear_q;
  assign device_addr_o = s_device_addr_q;
  assign device_ctrl_o = s_device_ctrl_q[15:0];
  assign host_ctrl_o = s_host_ctrl_q[15:0];
  assign port_ctrl_o = s_port_ctrl_q[0];
  assign schedule_ctrl_o = s_schedule_ctrl_q[0];
  assign ram_ctrl_o = s_ram_ctrl_q[15:0];
  assign ram_bist_start_o = s_ram_bist_start_q;
  assign viewport_valid_o = s_viewport_valid_q;
  assign viewport_write_o = s_viewport_write_q;
  assign viewport_addr_o = s_viewport_addr_q;
  assign viewport_write_data_o = s_viewport_write_data_q;
  assign endpoint_complete_clear_in_o =
      (s_write_access && !s_write_err &&
       (s_offset == `APB4_USB2__ENDPOINT_COMPLETE_IN)) ?
          apply_wstrb(
      32'd0, apb4.pwdata, apb4.pstrb
  ) : 32'd0;
  assign endpoint_complete_clear_out_o =
      (s_write_access && !s_write_err &&
       (s_offset == `APB4_USB2__ENDPOINT_COMPLETE_OUT)) ?
          apply_wstrb(
      32'd0, apb4.pwdata, apb4.pstrb
  ) : 32'd0;
  assign irq_o = s_global_ctrl_q[`APB4_USB2__GLOBAL_CTRL_IRQ_ENABLE] &&
                 ((s_irq_stat_q & s_irq_en_q) != 16'd0);

  for (genvar endpoint = 0; endpoint < NumEndpoints; endpoint++) begin : gen_endpoint_outputs
    assign endpoint_cfg_o[endpoint]      = s_endpoint_cfg_q[endpoint];
    assign endpoint_ram_in_o[endpoint]   = s_endpoint_ram_in_q[endpoint];
    assign endpoint_ram_out_o[endpoint]  = s_endpoint_ram_out_q[endpoint];
    assign endpoint_desc_in_o[endpoint]  = s_endpoint_desc_in_q[endpoint];
    assign endpoint_desc_out_o[endpoint] = s_endpoint_desc_out_q[endpoint];
    assign endpoint_command_o[endpoint]  = s_endpoint_cmd_q[endpoint];
  end

  for (genvar channel = 0; channel < NumChannels; channel++) begin : gen_channel_outputs
    assign channel_cfg_o[channel]      = s_channel_cfg_q[channel];
    assign channel_target_o[channel]   = s_channel_target_q[channel];
    assign channel_interval_o[channel] = s_channel_interval_q[channel];
    assign channel_ram_o[channel]      = s_channel_ram_q[channel];
    assign channel_desc_o[channel]     = s_channel_desc_q[channel];
    assign channel_command_o[channel]  = s_channel_cmd_q[channel];
  end

  always_comb begin
    s_read_data = 32'd0;
    s_read_err  = s_offset[1:0] != 2'b00;
    if (!s_read_err) begin
      if (s_endpoint_window) begin
        unique case (s_endpoint_offset)
          `APB4_USB2__ENDPOINT_CFG:       s_read_data = s_endpoint_cfg_q[s_endpoint_index];
          `APB4_USB2__ENDPOINT_RAM_IN:    s_read_data = s_endpoint_ram_in_q[s_endpoint_index];
          `APB4_USB2__ENDPOINT_RAM_OUT:   s_read_data = s_endpoint_ram_out_q[s_endpoint_index];
          `APB4_USB2__ENDPOINT_DESC_IN:   s_read_data = s_endpoint_desc_in_q[s_endpoint_index];
          `APB4_USB2__ENDPOINT_DESC_OUT:  s_read_data = s_endpoint_desc_out_q[s_endpoint_index];
          `APB4_USB2__ENDPOINT_COMMAND:   s_read_data = 32'd0;
          `APB4_USB2__ENDPOINT_STATUS:    s_read_data = endpoint_status_i[s_endpoint_index];
          `APB4_USB2__ENDPOINT_BYTES_IN:  s_read_data = endpoint_bytes_in_i[s_endpoint_index];
          `APB4_USB2__ENDPOINT_BYTES_OUT: s_read_data = endpoint_bytes_out_i[s_endpoint_index];
          default:                        s_read_err = 1'b1;
        endcase
      end else if (s_channel_window) begin
        unique case (s_channel_offset)
          `APB4_USB2__CHANNEL_CFG:      s_read_data = s_channel_cfg_q[s_channel_index];
          `APB4_USB2__CHANNEL_TARGET:   s_read_data = s_channel_target_q[s_channel_index];
          `APB4_USB2__CHANNEL_INTERVAL: s_read_data = s_channel_interval_q[s_channel_index];
          `APB4_USB2__CHANNEL_RAM:      s_read_data = s_channel_ram_q[s_channel_index];
          `APB4_USB2__CHANNEL_DESC:     s_read_data = s_channel_desc_q[s_channel_index];
          `APB4_USB2__CHANNEL_COMMAND:  s_read_data = 32'd0;
          `APB4_USB2__CHANNEL_STATUS:   s_read_data = channel_status_i[s_channel_index];
          `APB4_USB2__CHANNEL_BYTES:    s_read_data = channel_bytes_i[s_channel_index];
          default:                      s_read_err = 1'b1;
        endcase
      end else begin
        unique case (s_offset)
          `APB4_USB2__IP_ID: s_read_data = IpId;
          `APB4_USB2__IP_VERSION: s_read_data = IpVersion;
          `APB4_USB2__CAPABILITY0: s_read_data = Capability0;
          `APB4_USB2__CAPABILITY1: s_read_data = Capability1;
          `APB4_USB2__GLOBAL_CTRL: s_read_data = {28'd0, s_global_ctrl_q};
          `APB4_USB2__GLOBAL_STATUS: s_read_data = global_status_i;
          `APB4_USB2__ROLE_CTRL: s_read_data = {29'd0, s_role_ctrl_q};
          `APB4_USB2__ROLE_STATUS: s_read_data = role_status_i;
          `APB4_USB2__PHY_CTRL: s_read_data = {29'd0, s_phy_ctrl_q};
          `APB4_USB2__PHY_STATUS: s_read_data = phy_status_i;
          `APB4_USB2__ULPI_VIEWPORT:
          s_read_data = {
            s_viewport_busy_q, 1'b0, s_viewport_addr_q, 16'd0, s_viewport_write_data_q
          };
          `APB4_USB2__ULPI_VIEWPORT_DATA:
          s_read_data = {23'd0, s_viewport_err_q, s_viewport_read_data_q};
          `APB4_USB2__TIMEOUT: s_read_data = s_timeout_q;
          `APB4_USB2__FRAME: s_read_data = frame_i;
          `APB4_USB2__TEST_CTRL: s_read_data = s_test_ctrl_q;
          `APB4_USB2__PIO_DATA: begin
            s_read_data = 32'd0;
            s_read_err  = 1'b1;
          end
          `APB4_USB2__IRQ_STATUS: s_read_data = {16'd0, s_irq_stat_q};
          `APB4_USB2__IRQ_ENABLE: s_read_data = {16'd0, s_irq_en_q};
          `APB4_USB2__IRQ_TEST: s_read_data = 32'd0;
          `APB4_USB2__ERROR_STATUS: s_read_data = s_err_stat_q;
          `APB4_USB2__ERROR_CODE: s_read_data = s_err_code_q;
          `APB4_USB2__ERROR_INFO: s_read_data = s_err_info_q;
          `APB4_USB2__ERROR_DESC_ADDR: s_read_data = s_err_desc_addr_q;
          `APB4_USB2__ERROR_BUFFER_ADDR: s_read_data = s_err_buffer_addr_q;
          `APB4_USB2__PERF_TX_BYTES: s_read_data = perf_tx_bytes_i;
          `APB4_USB2__PERF_RX_BYTES: s_read_data = perf_rx_bytes_i;
          `APB4_USB2__PERF_PACKETS: s_read_data = perf_packets_i;
          `APB4_USB2__PERF_RETRIES: s_read_data = perf_retries_i;
          `APB4_USB2__PERF_AXI_STALL: s_read_data = perf_axi_stall_i;
          `APB4_USB2__PERF_RAM_STALL: s_read_data = perf_ram_stall_i;
          `APB4_USB2__PERF_IRQ_COUNT: s_read_data = perf_irq_count_i;
          `APB4_USB2__PERF_CTRL: s_read_data = 32'd0;
          `APB4_USB2__DEVICE_CTRL: s_read_data = s_device_ctrl_q;
          `APB4_USB2__DEVICE_ADDR: s_read_data = {25'd0, s_device_addr_q};
          `APB4_USB2__DEVICE_STATUS: s_read_data = device_status_i;
          `APB4_USB2__SETUP0: s_read_data = setup_packet_i[31:0];
          `APB4_USB2__SETUP1: s_read_data = setup_packet_i[63:32];
          `APB4_USB2__ENDPOINT_PENDING_IN: s_read_data = endpoint_pending_in_i;
          `APB4_USB2__ENDPOINT_PENDING_OUT: s_read_data = endpoint_pending_out_i;
          `APB4_USB2__ENDPOINT_COMPLETE_IN: s_read_data = endpoint_complete_in_i;
          `APB4_USB2__ENDPOINT_COMPLETE_OUT: s_read_data = endpoint_complete_out_i;
          `APB4_USB2__HOST_CTRL: s_read_data = s_host_ctrl_q;
          `APB4_USB2__HOST_STATUS: s_read_data = host_status_i;
          `APB4_USB2__PORT_CTRL: s_read_data = s_port_ctrl_q;
          `APB4_USB2__PORT_STATUS: s_read_data = port_status_i;
          `APB4_USB2__SCHEDULE_CTRL: s_read_data = s_schedule_ctrl_q;
          `APB4_USB2__SCHEDULE_STATUS: s_read_data = schedule_status_i;
          `APB4_USB2__RAM_CTRL: s_read_data = s_ram_ctrl_q;
          `APB4_USB2__RAM_STATUS: s_read_data = ram_status_i;
          `APB4_USB2__ECC_STATUS: s_read_data = ecc_status_i;
          `APB4_USB2__ECC_CORRECTED_COUNT: s_read_data = ecc_corrected_count_i;
          `APB4_USB2__ECC_UNCORRECTABLE_COUNT: s_read_data = ecc_uncorrectable_count_i;
          `APB4_USB2__RAM_BIST: s_read_data = 32'd0;
          `APB4_USB2__DEBUG_STATUS: s_read_data = debug_status_i;
          default: s_read_err = 1'b1;
        endcase
      end
    end
  end

  always_comb begin
    s_write_err = s_offset[1:0] != 2'b00;
    if (!s_write_err) begin
      if (s_endpoint_window) begin
        unique case (s_endpoint_offset)
          `APB4_USB2__ENDPOINT_CFG,
          `APB4_USB2__ENDPOINT_RAM_IN,
          `APB4_USB2__ENDPOINT_RAM_OUT,
          `APB4_USB2__ENDPOINT_DESC_IN,
          `APB4_USB2__ENDPOINT_DESC_OUT:
          s_write_err = enable_o;
          `APB4_USB2__ENDPOINT_COMMAND: s_write_err = apb4.pstrb != 4'b1111;
          default: s_write_err = 1'b1;
        endcase
      end else if (s_channel_window) begin
        unique case (s_channel_offset)
          `APB4_USB2__CHANNEL_CFG,
          `APB4_USB2__CHANNEL_TARGET,
          `APB4_USB2__CHANNEL_INTERVAL,
          `APB4_USB2__CHANNEL_RAM,
          `APB4_USB2__CHANNEL_DESC:
          s_write_err = enable_o;
          `APB4_USB2__CHANNEL_COMMAND: s_write_err = apb4.pstrb != 4'b1111;
          default: s_write_err = 1'b1;
        endcase
      end else begin
        unique case (s_offset)
          `APB4_USB2__GLOBAL_CTRL,
          `APB4_USB2__IRQ_STATUS,
          `APB4_USB2__IRQ_ENABLE,
          `APB4_USB2__IRQ_TEST,
          `APB4_USB2__ERROR_STATUS,
          `APB4_USB2__PERF_CTRL,
          `APB4_USB2__DEVICE_CTRL,
          `APB4_USB2__DEVICE_ADDR,
          `APB4_USB2__ENDPOINT_COMPLETE_IN,
          `APB4_USB2__ENDPOINT_COMPLETE_OUT,
          `APB4_USB2__HOST_CTRL,
          `APB4_USB2__PORT_CTRL,
          `APB4_USB2__SCHEDULE_CTRL,
          `APB4_USB2__RAM_CTRL,
          `APB4_USB2__RAM_BIST: begin
          end
          `APB4_USB2__ROLE_CTRL, `APB4_USB2__PHY_CTRL, `APB4_USB2__TIMEOUT, `APB4_USB2__TEST_CTRL:
          s_write_err = enable_o;
          `APB4_USB2__ULPI_VIEWPORT: begin
            s_write_err = s_viewport_busy_q || !apb4.pwdata[31] ||
                            (apb4.pwdata[29:22] != 8'd0) || (apb4.pwdata[15:8] != 8'd0) ||
                            (apb4.pstrb != 4'b1111);
          end
          `APB4_USB2__PIO_DATA: s_write_err = 1'b1;
          default: s_write_err = 1'b1;
        endcase
      end
    end
  end

  always_comb begin
    s_apb4_ready_d    = s_req_accept;
    s_apb4_rdata_d    = s_apb4_rdata_q;
    s_apb4_resp_err_d = 1'b0;
    if (s_req_accept) begin
      if (apb4.pwrite) begin
        s_apb4_rdata_d    = 32'd0;
        s_apb4_resp_err_d = s_write_err;
      end else begin
        s_apb4_rdata_d    = s_read_data;
        s_apb4_resp_err_d = s_read_err;
      end
    end
  end

  always_comb begin
    s_global_ctrl_d         = s_global_ctrl_q;
    s_role_ctrl_d           = s_role_ctrl_q;
    s_phy_ctrl_d            = s_phy_ctrl_q;
    s_timeout_d             = s_timeout_q;
    s_test_ctrl_d           = s_test_ctrl_q;
    s_device_ctrl_d         = s_device_ctrl_q;
    s_device_addr_d         = s_device_addr_q;
    s_host_ctrl_d           = s_host_ctrl_q;
    s_port_ctrl_d           = s_port_ctrl_q;
    s_schedule_ctrl_d       = s_schedule_ctrl_q;
    s_ram_ctrl_d            = s_ram_ctrl_q;
    s_irq_stat_d            = s_irq_stat_q | irq_event_i;
    s_irq_en_d              = s_irq_en_q;
    s_err_stat_d            = s_err_stat_q | error_status_i;
    s_err_code_d            = s_err_code_q;
    s_err_info_d            = s_err_info_q;
    s_err_desc_addr_d       = s_err_desc_addr_q;
    s_err_buffer_addr_d     = s_err_buffer_addr_q;
    s_soft_reset_d          = 1'b0;
    s_abort_d               = 1'b0;
    s_perf_clear_d          = 1'b0;
    s_ram_bist_start_d      = 1'b0;
    s_viewport_valid_d      = 1'b0;
    s_viewport_write_d      = s_viewport_write_q;
    s_viewport_addr_d       = s_viewport_addr_q;
    s_viewport_write_data_d = s_viewport_write_data_q;
    s_viewport_read_data_d  = s_viewport_read_data_q;
    s_viewport_busy_d       = s_viewport_busy_q;
    s_viewport_err_d        = s_viewport_err_q;
    for (int endpoint = 0; endpoint < NumEndpoints; endpoint++) begin
      s_endpoint_cfg_d[endpoint]      = s_endpoint_cfg_q[endpoint];
      s_endpoint_ram_in_d[endpoint]   = s_endpoint_ram_in_q[endpoint];
      s_endpoint_ram_out_d[endpoint]  = s_endpoint_ram_out_q[endpoint];
      s_endpoint_desc_in_d[endpoint]  = s_endpoint_desc_in_q[endpoint];
      s_endpoint_desc_out_d[endpoint] = s_endpoint_desc_out_q[endpoint];
      s_endpoint_cmd_d[endpoint]      = 32'd0;
    end
    for (int channel = 0; channel < NumChannels; channel++) begin
      s_channel_cfg_d[channel]      = s_channel_cfg_q[channel];
      s_channel_target_d[channel]   = s_channel_target_q[channel];
      s_channel_interval_d[channel] = s_channel_interval_q[channel];
      s_channel_ram_d[channel]      = s_channel_ram_q[channel];
      s_channel_desc_d[channel]     = s_channel_desc_q[channel];
      s_channel_cmd_d[channel]      = 32'd0;
    end

    if (viewport_resp_valid_i) begin
      s_viewport_busy_d      = 1'b0;
      s_viewport_read_data_d = viewport_read_data_i;
      s_viewport_err_d       = viewport_error_i;
    end
    if (error_capture_i && (s_err_stat_q == 32'd0)) begin
      s_err_code_d        = error_code_i;
      s_err_info_d        = error_info_i;
      s_err_desc_addr_d   = error_desc_addr_i;
      s_err_buffer_addr_d = error_buffer_addr_i;
    end

    if (s_write_access && !s_write_err) begin
      if (s_endpoint_window) begin
        unique case (s_endpoint_offset)
          `APB4_USB2__ENDPOINT_CFG:
          s_endpoint_cfg_d[s_endpoint_index] =
              apply_wstrb(s_endpoint_cfg_q[s_endpoint_index], apb4.pwdata, apb4.pstrb);
          `APB4_USB2__ENDPOINT_RAM_IN:
          s_endpoint_ram_in_d[s_endpoint_index] =
              apply_wstrb(s_endpoint_ram_in_q[s_endpoint_index], apb4.pwdata, apb4.pstrb);
          `APB4_USB2__ENDPOINT_RAM_OUT:
          s_endpoint_ram_out_d[s_endpoint_index] =
              apply_wstrb(s_endpoint_ram_out_q[s_endpoint_index], apb4.pwdata, apb4.pstrb);
          `APB4_USB2__ENDPOINT_DESC_IN:
          s_endpoint_desc_in_d[s_endpoint_index] =
              apply_wstrb(s_endpoint_desc_in_q[s_endpoint_index], apb4.pwdata, apb4.pstrb);
          `APB4_USB2__ENDPOINT_DESC_OUT:
          s_endpoint_desc_out_d[s_endpoint_index] =
              apply_wstrb(s_endpoint_desc_out_q[s_endpoint_index], apb4.pwdata, apb4.pstrb);
          `APB4_USB2__ENDPOINT_COMMAND: s_endpoint_cmd_d[s_endpoint_index] = apb4.pwdata;
          default: begin
          end
        endcase
      end else if (s_channel_window) begin
        unique case (s_channel_offset)
          `APB4_USB2__CHANNEL_CFG:
          s_channel_cfg_d[s_channel_index] =
              apply_wstrb(s_channel_cfg_q[s_channel_index], apb4.pwdata, apb4.pstrb);
          `APB4_USB2__CHANNEL_TARGET:
          s_channel_target_d[s_channel_index] =
              apply_wstrb(s_channel_target_q[s_channel_index], apb4.pwdata, apb4.pstrb);
          `APB4_USB2__CHANNEL_INTERVAL:
          s_channel_interval_d[s_channel_index] =
              apply_wstrb(s_channel_interval_q[s_channel_index], apb4.pwdata, apb4.pstrb);
          `APB4_USB2__CHANNEL_RAM:
          s_channel_ram_d[s_channel_index] =
              apply_wstrb(s_channel_ram_q[s_channel_index], apb4.pwdata, apb4.pstrb);
          `APB4_USB2__CHANNEL_DESC:
          s_channel_desc_d[s_channel_index] =
              apply_wstrb(s_channel_desc_q[s_channel_index], apb4.pwdata, apb4.pstrb);
          `APB4_USB2__CHANNEL_COMMAND: s_channel_cmd_d[s_channel_index] = apb4.pwdata;
          default: begin
          end
        endcase
      end else begin
        unique case (s_offset)
          `APB4_USB2__GLOBAL_CTRL: begin
            if (apb4.pstrb[0]) begin
              s_global_ctrl_d[3:0] = apb4.pwdata[3:0];
              s_soft_reset_d = apb4.pwdata[`APB4_USB2__GLOBAL_CTRL_SOFT_RESET];
              s_abort_d = apb4.pwdata[`APB4_USB2__GLOBAL_CTRL_ABORT];
              s_global_ctrl_d[`APB4_USB2__GLOBAL_CTRL_SOFT_RESET] = 1'b0;
              s_global_ctrl_d[`APB4_USB2__GLOBAL_CTRL_ABORT] = 1'b0;
            end
          end
          `APB4_USB2__ROLE_CTRL: if (apb4.pstrb[0]) s_role_ctrl_d = apb4.pwdata[2:0];
          `APB4_USB2__PHY_CTRL: if (apb4.pstrb[0]) s_phy_ctrl_d = apb4.pwdata[2:0];
          `APB4_USB2__ULPI_VIEWPORT: begin
            s_viewport_valid_d      = 1'b1;
            s_viewport_busy_d       = 1'b1;
            s_viewport_err_d        = 1'b0;
            s_viewport_write_d      = apb4.pwdata[30];
            s_viewport_addr_d       = apb4.pwdata[21:16];
            s_viewport_write_data_d = apb4.pwdata[7:0];
          end
          `APB4_USB2__TIMEOUT: s_timeout_d = apply_wstrb(s_timeout_q, apb4.pwdata, apb4.pstrb);
          `APB4_USB2__TEST_CTRL:
          s_test_ctrl_d = apply_wstrb(s_test_ctrl_q, apb4.pwdata, apb4.pstrb);
          `APB4_USB2__IRQ_STATUS: s_irq_stat_d = (s_irq_stat_q & ~apb4.pwdata[15:0]) | irq_event_i;
          `APB4_USB2__IRQ_ENABLE: s_irq_en_d = s_irq_en_merged[15:0];
          `APB4_USB2__IRQ_TEST: s_irq_stat_d = s_irq_stat_q | apb4.pwdata[15:0] | irq_event_i;
          `APB4_USB2__ERROR_STATUS: begin
            s_err_stat_d = (s_err_stat_q & ~apb4.pwdata) | error_status_i;
            if ((s_err_stat_q & ~apb4.pwdata) == 32'd0) begin
              s_err_code_d        = 32'd0;
              s_err_info_d        = 32'd0;
              s_err_desc_addr_d   = 32'd0;
              s_err_buffer_addr_d = 32'd0;
            end
          end
          `APB4_USB2__PERF_CTRL: s_perf_clear_d = apb4.pwdata[0];
          `APB4_USB2__DEVICE_CTRL:
          s_device_ctrl_d = apply_wstrb(s_device_ctrl_q, apb4.pwdata, apb4.pstrb);
          `APB4_USB2__DEVICE_ADDR: if (apb4.pstrb[0]) s_device_addr_d = apb4.pwdata[6:0];
          `APB4_USB2__HOST_CTRL:
          s_host_ctrl_d = apply_wstrb(s_host_ctrl_q, apb4.pwdata, apb4.pstrb);
          `APB4_USB2__PORT_CTRL:
          s_port_ctrl_d = apply_wstrb(s_port_ctrl_q, apb4.pwdata, apb4.pstrb);
          `APB4_USB2__SCHEDULE_CTRL:
          s_schedule_ctrl_d = apply_wstrb(s_schedule_ctrl_q, apb4.pwdata, apb4.pstrb);
          `APB4_USB2__RAM_CTRL: s_ram_ctrl_d = apply_wstrb(s_ram_ctrl_q, apb4.pwdata, apb4.pstrb);
          `APB4_USB2__RAM_BIST: s_ram_bist_start_d = apb4.pwdata[0];
          default: begin
          end
        endcase
      end
    end

  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_apb4_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_ready_d),
      .dat_o  (s_apb4_ready_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_apb4_rdata_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_rdata_d),
      .dat_o  (s_apb4_rdata_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_apb4_resp_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_resp_err_d),
      .dat_o  (s_apb4_resp_err_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_global_ctrl_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_global_ctrl_d),
      .dat_o  (s_global_ctrl_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_role_ctrl_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_role_ctrl_d),
      .dat_o  (s_role_ctrl_q)
  );
  dffrc #(
      .DATA_WIDTH(3),
      .RESET_VAL (3'b001)
  ) u_phy_ctrl_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_phy_ctrl_d),
      .dat_o  (s_phy_ctrl_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd720000)
  ) u_timeout_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timeout_d),
      .dat_o  (s_timeout_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_test_ctrl_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_test_ctrl_d),
      .dat_o  (s_test_ctrl_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_device_ctrl_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_device_ctrl_d),
      .dat_o  (s_device_ctrl_q)
  );
  dffr #(
      .DATA_WIDTH(7)
  ) u_device_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_device_addr_d),
      .dat_o  (s_device_addr_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_host_ctrl_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_host_ctrl_d),
      .dat_o  (s_host_ctrl_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_port_ctrl_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_port_ctrl_d),
      .dat_o  (s_port_ctrl_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_schedule_ctrl_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_schedule_ctrl_d),
      .dat_o  (s_schedule_ctrl_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_ram_ctrl_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ram_ctrl_d),
      .dat_o  (s_ram_ctrl_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_irq_status_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_irq_stat_d),
      .dat_o  (s_irq_stat_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_irq_enable_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_irq_en_d),
      .dat_o  (s_irq_en_q)
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
  ) u_soft_reset_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_soft_reset_d),
      .dat_o  (s_soft_reset_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_abort_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_abort_d),
      .dat_o  (s_abort_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_perf_clear_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_clear_d),
      .dat_o  (s_perf_clear_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_ram_bist_start_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ram_bist_start_d),
      .dat_o  (s_ram_bist_start_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_viewport_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_viewport_valid_d),
      .dat_o  (s_viewport_valid_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_viewport_write_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_viewport_write_d),
      .dat_o  (s_viewport_write_q)
  );
  dffr #(
      .DATA_WIDTH(6)
  ) u_viewport_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_viewport_addr_d),
      .dat_o  (s_viewport_addr_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_viewport_write_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_viewport_write_data_d),
      .dat_o  (s_viewport_write_data_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_viewport_read_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_viewport_read_data_d),
      .dat_o  (s_viewport_read_data_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_viewport_busy_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_viewport_busy_d),
      .dat_o  (s_viewport_busy_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_viewport_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_viewport_err_d),
      .dat_o  (s_viewport_err_q)
  );
  for (genvar endpoint = 0; endpoint < NumEndpoints; endpoint++) begin : gen_endpoint_registers
    dffr #(
        .DATA_WIDTH(32)
    ) u_cfg_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_endpoint_cfg_d[endpoint]),
        .dat_o  (s_endpoint_cfg_q[endpoint])
    );
    dffr #(
        .DATA_WIDTH(32)
    ) u_ram_in_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_endpoint_ram_in_d[endpoint]),
        .dat_o  (s_endpoint_ram_in_q[endpoint])
    );
    dffr #(
        .DATA_WIDTH(32)
    ) u_ram_out_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_endpoint_ram_out_d[endpoint]),
        .dat_o  (s_endpoint_ram_out_q[endpoint])
    );
    dffr #(
        .DATA_WIDTH(32)
    ) u_desc_in_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_endpoint_desc_in_d[endpoint]),
        .dat_o  (s_endpoint_desc_in_q[endpoint])
    );
    dffr #(
        .DATA_WIDTH(32)
    ) u_desc_out_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_endpoint_desc_out_d[endpoint]),
        .dat_o  (s_endpoint_desc_out_q[endpoint])
    );
    dffr #(
        .DATA_WIDTH(32)
    ) u_command_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_endpoint_cmd_d[endpoint]),
        .dat_o  (s_endpoint_cmd_q[endpoint])
    );
  end

  for (genvar channel = 0; channel < NumChannels; channel++) begin : gen_channel_registers
    dffr #(
        .DATA_WIDTH(32)
    ) u_cfg_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_cfg_d[channel]),
        .dat_o  (s_channel_cfg_q[channel])
    );
    dffr #(
        .DATA_WIDTH(32)
    ) u_target_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_target_d[channel]),
        .dat_o  (s_channel_target_q[channel])
    );
    dffr #(
        .DATA_WIDTH(32)
    ) u_interval_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_interval_d[channel]),
        .dat_o  (s_channel_interval_q[channel])
    );
    dffr #(
        .DATA_WIDTH(32)
    ) u_ram_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_ram_d[channel]),
        .dat_o  (s_channel_ram_q[channel])
    );
    dffr #(
        .DATA_WIDTH(32)
    ) u_desc_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_desc_d[channel]),
        .dat_o  (s_channel_desc_q[channel])
    );
    dffr #(
        .DATA_WIDTH(32)
    ) u_command_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_channel_cmd_d[channel]),
        .dat_o  (s_channel_cmd_q[channel])
    );
  end

`ifndef SYNTHESIS
  initial begin
    if ((NumEndpoints != 8) || (NumChannels != 16)) begin
      $fatal(1, "usb2_reg: delivered ABI requires 8 endpoints and 16 channels");
    end
  end
`endif
endmodule
