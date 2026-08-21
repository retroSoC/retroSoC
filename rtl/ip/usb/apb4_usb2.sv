// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "usb2_define.svh"

module apb4_usb2 #(
    parameter int NumEndpoints = 8,
    parameter int NumChannels  = 16
) (
    // verilog_format: off -- preserve clock, bus, interrupt, and ULPI groups
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       clk_ulpi_i,
    apb4_if.slave      apb4,
    axi4_if.master     dma_axi4,
    output logic       irq_o,
    usb2_ulpi_if.dut   ulpi
    // verilog_format: on
);
  logic                          s_en;
  logic                          s_soft_reset;
  logic                          s_abort;
  logic [             1:0]       s_force_role;
  logic                          s_auto_role;
  logic                          s_phy_reset_n_cfg;
  logic                          s_phy_suspend;
  logic                          s_remote_wake;
  logic [            31:0]       s_timeout;
  logic [             7:0]       s_test_ctrl;
  logic                          s_perf_clear;
  logic [             6:0]       s_device_addr;
  logic [            15:0]       s_device_ctrl;
  logic [NumEndpoints-1:0][31:0] s_endpoint_cfg;
  logic [NumEndpoints-1:0][31:0] s_endpoint_ram_in;
  logic [NumEndpoints-1:0][31:0] s_endpoint_ram_out;
  logic [NumEndpoints-1:0][31:0] s_endpoint_desc_in;
  logic [NumEndpoints-1:0][31:0] s_endpoint_desc_out;
  logic [NumEndpoints-1:0][31:0] s_endpoint_cmd;
  logic [            31:0]       s_endpoint_complete_clear_in;
  logic [            31:0]       s_endpoint_complete_clear_out;
  logic [            15:0]       s_host_ctrl;
  logic                          s_port_ctrl;
  logic                          s_schedule_ctrl;
  logic [ NumChannels-1:0][31:0] s_channel_cfg;
  logic [ NumChannels-1:0][31:0] s_channel_target;
  logic [ NumChannels-1:0][31:0] s_channel_interval;
  logic [ NumChannels-1:0][31:0] s_channel_ram;
  logic [ NumChannels-1:0][31:0] s_channel_desc;
  logic [ NumChannels-1:0][31:0] s_channel_cmd;
  logic [            15:0]       s_ram_ctrl;
  logic                          s_ram_bist_start;
  logic                          s_viewport_valid;
  logic                          s_viewport_write;
  logic [             5:0]       s_viewport_addr;
  logic [             7:0]       s_viewport_write_data;
  logic                          s_viewport_resp_valid_sys;
  logic [             8:0]       s_viewport_resp_data_sys;

  logic [            31:0]       s_global_stat;
  logic [            31:0]       s_role_stat;
  logic [            31:0]       s_phy_stat;
  logic [            31:0]       s_frame_stat;
  logic [            31:0]       s_device_stat;
  logic [63:0] s_setup_packet_d, s_setup_packet_q;
  logic                 [            31:0]       s_endpoint_pending_in;
  logic                 [            31:0]       s_endpoint_pending_out;
  logic                 [            31:0]       s_endpoint_complete_in;
  logic                 [            31:0]       s_endpoint_complete_out;
  logic                 [NumEndpoints-1:0][31:0] s_endpoint_stat;
  logic                 [NumEndpoints-1:0][31:0] s_endpoint_bytes_in;
  logic                 [NumEndpoints-1:0][31:0] s_endpoint_bytes_out;
  logic                 [            31:0]       s_host_stat;
  logic                 [            31:0]       s_port_stat;
  logic                 [            31:0]       s_schedule_stat;
  logic                 [ NumChannels-1:0][31:0] s_channel_stat;
  logic                 [ NumChannels-1:0][31:0] s_channel_bytes;
  logic                 [            31:0]       s_ram_stat;
  logic                 [            31:0]       s_ecc_stat;
  logic                 [            31:0]       s_ecc_corrected_count_sys;
  logic                 [            31:0]       s_ecc_uncorrectable_count_sys;
  logic                 [            31:0]       s_debug_stat;
  logic                 [            31:0]       s_perf_tx_bytes;
  logic                 [            31:0]       s_perf_rx_bytes;
  logic                 [            31:0]       s_perf_packets;
  logic                 [            31:0]       s_perf_retries;
  logic                 [            31:0]       s_perf_axi_stall_d;
  logic                 [            31:0]       s_perf_axi_stall_q;
  logic                 [            31:0]       s_perf_ram_stall_d;
  logic                 [            31:0]       s_perf_ram_stall_q;
  logic                 [            31:0]       s_perf_irq_count;
  logic                 [            15:0]       s_scheduler_irq_event;
  logic                 [            15:0]       s_irq_event;
  logic                                          s_err_capture;
  logic                 [            31:0]       s_err_stat;
  logic                 [            31:0]       s_err_code;
  logic                 [            31:0]       s_err_info;
  logic                 [            31:0]       s_err_desc_addr;
  logic                 [            31:0]       s_err_buffer_addr;

  usb2_pkg::usb2_role_e                          s_active_role_sys;
  usb2_pkg::usb2_role_e                          s_active_role_ulpi;
  logic                 [             1:0]       s_active_role_ulpi_bits;
  logic                                          s_role_change;
  logic                                          s_role_reset;
  logic                                          s_role_reset_ulpi;
  logic                                          s_role_switch_pending;
  logic                                          s_transaction_busy_ulpi;
  logic                                          s_transaction_busy_sys;
  logic                                          s_scheduler_busy;
  logic                                          s_link_ready_ulpi;
  logic                                          s_link_ready_sys;
  logic                 [             1:0]       s_line_state_ulpi;
  logic                 [             1:0]       s_line_state_sys;
  logic                 [             1:0]       s_vbus_state_ulpi;
  logic                 [             1:0]       s_vbus_state_sys;
  logic                                          s_id_ground_ulpi;
  logic                                          s_id_ground_sys;
  logic                 [            13:0]       s_frame_ulpi;
  logic                 [            13:0]       s_frame_sys;
  logic                                          s_ulpi_rst_n;
  logic                                          s_link_rst_n;
  logic                 [             6:0]       s_device_addr_ulpi;
  logic                 [NumEndpoints-1:0][31:0] s_endpoint_cfg_ulpi;
  logic                 [            31:0]       s_timeout_ulpi;
  logic                                          s_high_speed_ulpi;
  logic                                          s_en_ulpi;
  logic                                          s_phy_reset_n_ulpi;

  logic                                          s_work_valid_sys;
  logic                                          s_work_ready_sys;
  logic                 [            63:0]       s_work_data_sys;
  logic                                          s_work_valid_ulpi;
  logic                                          s_work_ready_ulpi;
  logic                 [            63:0]       s_work_data_ulpi;
  logic                                          s_result_valid_ulpi;
  logic                                          s_result_ready_ulpi;
  logic                 [            63:0]       s_result_data_ulpi;
  logic                                          s_result_valid_sys;
  logic                                          s_result_ready_sys;
  logic                 [            63:0]       s_result_data_sys;
  logic                                          s_setup_valid_ulpi;
  logic                                          s_setup_ready_ulpi;
  logic                 [            63:0]       s_setup_data_ulpi;
  logic                                          s_setup_valid_sys;
  logic                 [            63:0]       s_setup_data_sys;

  logic                                          s_fill_cmd_valid_sys;
  logic                                          s_fill_cmd_ready_sys;
  logic                 [            26:0]       s_fill_cmd_data_sys;
  logic                                          s_fill_cmd_valid_ulpi;
  logic                                          s_fill_cmd_ready_ulpi;
  logic                 [            26:0]       s_fill_cmd_data_ulpi;
  logic                                          s_drain_cmd_valid_sys;
  logic                                          s_drain_cmd_ready_sys;
  logic                 [            26:0]       s_drain_cmd_data_sys;
  logic                                          s_drain_cmd_valid_ulpi;
  logic                                          s_drain_cmd_ready_ulpi;
  logic                 [            26:0]       s_drain_cmd_data_ulpi;
  logic                                          s_buffer_event_valid_ulpi;
  logic                                          s_buffer_event_ready_ulpi;
  logic                 [             2:0]       s_buffer_event_data_ulpi;
  logic                                          s_buffer_event_valid_sys;
  logic                                          s_buffer_event_ready_sys;
  logic                 [             2:0]       s_buffer_event_data_sys;

  logic                                          s_view_req_valid_sys;
  logic                                          s_view_req_ready_sys;
  logic                 [            14:0]       s_view_req_data_sys;
  logic                                          s_view_req_valid_ulpi;
  logic                                          s_view_req_ready_ulpi;
  logic                 [            14:0]       s_view_req_data_ulpi;
  logic                                          s_view_resp_valid_ulpi;
  logic                                          s_view_resp_ready_ulpi;
  logic                 [             8:0]       s_view_resp_data_ulpi;

  logic                                          s_fill_stream_valid_sys;
  logic                                          s_fill_stream_ready_sys;
  logic                 [            36:0]       s_fill_stream_data_sys;
  logic                                          s_fill_stream_valid_ulpi;
  logic                                          s_fill_stream_ready_ulpi;
  logic                 [            36:0]       s_fill_stream_data_ulpi;
  logic                                          s_drain_stream_valid_ulpi;
  logic                                          s_drain_stream_ready_ulpi;
  logic                 [            36:0]       s_drain_stream_data_ulpi;
  logic                                          s_drain_fifo_valid_ulpi;
  logic                                          s_drain_fifo_ready_ulpi;
  logic                 [            36:0]       s_drain_fifo_data_ulpi;
  logic                                          s_drain_stream_valid_sys;
  logic                                          s_drain_stream_ready_sys;
  logic                 [            36:0]       s_drain_stream_data_sys;

  logic                                          s_dma_start;
  logic                                          s_dma_abort;
  logic                                          s_dma_memory_to_packet;
  logic                 [            31:0]       s_dma_desc_base;
  logic                 [            31:0]       s_dma_transfer_bytes;
  logic                                          s_dma_busy;
  logic                                          s_dma_done;
  logic                                          s_dma_err;
  logic                 [             7:0]       s_dma_err_code;
  logic                 [            31:0]       s_dma_current_desc;
  // Retained for waveform and future debug CSR use.
  /* verilator lint_off UNUSEDSIGNAL */
  logic                 [            31:0]       s_dma_next_desc;
  logic                 [            31:0]       s_dma_frame;
  /* verilator lint_on UNUSEDSIGNAL */
  logic                 [            31:0]       s_dma_bytes_done;
  logic                                          s_dma_descriptor_irq;
  logic                                          s_dma_abort_done;

  logic                                          s_retry_ulpi;
  logic                                          s_protocol_err_ulpi;
  logic s_retry_toggle_d, s_retry_toggle_q;
  logic s_protocol_toggle_d, s_protocol_toggle_q;
  logic s_retry_event_sys;
  logic s_protocol_event_sys;
  logic s_ecc_corrected_event;
  logic s_ecc_uncorrectable_event;
  logic s_retry_re_sys, s_retry_fe_sys;
  logic s_protocol_re_sys, s_protocol_fe_sys;
  // edge_det levels are intentionally not consumed.
  /* verilator lint_off UNUSEDSIGNAL */
  logic s_retry_toggle_level_sys;
  logic s_protocol_toggle_level_sys;
  /* verilator lint_on UNUSEDSIGNAL */
  logic s_view_pending_d, s_view_pending_q;
  logic [14:0] s_view_data_d, s_view_data_q;
  logic [31:0] s_ecc_corrected_previous_d, s_ecc_corrected_previous_q;
  logic [31:0] s_ecc_uncorrectable_previous_d, s_ecc_uncorrectable_previous_q;
  logic [31:0] s_ecc_corrected_count_ulpi;
  logic [31:0] s_ecc_uncorrectable_count_ulpi;

  assign s_link_rst_n = s_ulpi_rst_n && !s_role_reset_ulpi;
  assign s_active_role_ulpi = usb2_pkg::usb2_role_e'(s_active_role_ulpi_bits);
  assign s_retry_toggle_d = s_retry_toggle_q ^ s_retry_ulpi;
  assign s_protocol_toggle_d = s_protocol_toggle_q ^ s_protocol_err_ulpi;
  assign s_view_req_valid_sys = s_view_pending_q;
  assign s_view_req_data_sys = s_view_data_q;
  assign s_setup_packet_d = s_setup_valid_sys ? s_setup_data_sys : s_setup_packet_q;
  assign s_ecc_corrected_event = s_ecc_corrected_count_sys != s_ecc_corrected_previous_q;
  assign s_ecc_uncorrectable_event =
      s_ecc_uncorrectable_count_sys != s_ecc_uncorrectable_previous_q;
  assign s_ecc_corrected_previous_d = s_ecc_corrected_count_sys;
  assign s_ecc_uncorrectable_previous_d = s_ecc_uncorrectable_count_sys;

  rst_sync #(
      .STAGE(2)
  ) u_ulpi_rst_sync (
      .clk_i  (clk_ulpi_i),
      .rst_n_i(rst_n_i),
      .rst_n_o(s_ulpi_rst_n)
  );
  assign s_retry_event_sys    = s_retry_re_sys || s_retry_fe_sys;
  assign s_protocol_event_sys = s_protocol_re_sys || s_protocol_fe_sys;

  always_comb begin
    s_perf_axi_stall_d = s_perf_axi_stall_q;
    s_perf_ram_stall_d = s_perf_ram_stall_q;
    if (s_perf_clear) begin
      s_perf_axi_stall_d = 32'd0;
      s_perf_ram_stall_d = 32'd0;
    end else begin
      if (((dma_axi4.awvalid && !dma_axi4.awready) ||
           (dma_axi4.wvalid && !dma_axi4.wready) ||
           (dma_axi4.bvalid && !dma_axi4.bready) ||
           (dma_axi4.arvalid && !dma_axi4.arready) ||
           (dma_axi4.rvalid && !dma_axi4.rready)) && !(&s_perf_axi_stall_q)) begin
        s_perf_axi_stall_d = s_perf_axi_stall_q + 1'b1;
      end
      if (((s_fill_stream_valid_sys && !s_fill_stream_ready_sys) ||
           (s_drain_stream_valid_sys && !s_drain_stream_ready_sys)) && !(&s_perf_ram_stall_q)) begin
        s_perf_ram_stall_d = s_perf_ram_stall_q + 1'b1;
      end
    end
  end

  always_comb begin
    s_view_pending_d = s_view_pending_q;
    s_view_data_d    = s_view_data_q;
    if (s_viewport_valid && !s_view_pending_q) begin
      s_view_pending_d = 1'b1;
      s_view_data_d    = {s_viewport_write, s_viewport_addr, s_viewport_write_data};
    end
    if (s_view_pending_q && s_view_req_ready_sys) begin
      s_view_pending_d = 1'b0;
    end
  end

  always_comb begin
    s_global_stat        = 32'd0;
    s_global_stat[0]     = s_en;
    s_global_stat[1]     = s_scheduler_busy || s_dma_busy || s_transaction_busy_sys;
    s_global_stat[3:2]   = s_active_role_sys;
    s_global_stat[4]     = s_link_ready_sys;
    s_global_stat[5]     = s_dma_busy;
    s_role_stat          = 32'd0;
    s_role_stat[1:0]     = s_active_role_sys;
    s_role_stat[2]       = s_role_switch_pending;
    s_role_stat[3]       = s_id_ground_sys;
    s_role_stat[5:4]     = s_vbus_state_sys;
    s_phy_stat           = 32'd0;
    s_phy_stat[1:0]      = s_line_state_sys;
    s_phy_stat[3:2]      = s_vbus_state_sys;
    s_phy_stat[4]        = s_id_ground_sys;
    s_phy_stat[5]        = s_link_ready_sys;
    s_frame_stat         = {18'd0, s_frame_sys};
    s_device_stat        = 32'd0;
    s_device_stat[0]     = s_active_role_sys == usb2_pkg::Usb2RoleDevice;
    s_device_stat[1]     = s_phy_suspend;
    s_device_stat[2]     = s_remote_wake;
    s_device_stat[31:16] = s_device_ctrl;
    s_host_stat          = 32'd0;
    s_host_stat[0]       = s_active_role_sys == usb2_pkg::Usb2RoleHost;
    s_host_stat[1]       = s_transaction_busy_sys;
    s_host_stat[31:16]   = s_host_ctrl;
    s_port_stat          = s_phy_stat;
    s_schedule_stat      = {18'd0, s_frame_sys};
    s_schedule_stat[31]  = s_schedule_ctrl;
    s_ram_stat           = 32'h4000_0000;
    s_ram_stat[0]        = s_transaction_busy_sys;
    s_ecc_stat           = 32'd0;
    s_ecc_stat[0]        = s_ecc_corrected_event;
    s_ecc_stat[1]        = s_ecc_uncorrectable_event;
    s_debug_stat         = 32'd0;
    s_debug_stat[0]      = s_scheduler_busy;
    s_debug_stat[1]      = s_dma_busy;
    s_debug_stat[2]      = s_transaction_busy_sys;
    s_debug_stat[3]      = s_role_reset;
    s_debug_stat[4]      = s_dma_descriptor_irq;
    s_debug_stat[5]      = s_dma_abort_done;
    s_debug_stat[6]      = s_ram_bist_start;
    s_debug_stat[7]      = 1'b0;
    s_debug_stat[15:8]   = s_test_ctrl;
    s_debug_stat[31:16]  = s_ram_ctrl;
    s_irq_event          = s_scheduler_irq_event;
    s_irq_event[`APB4_USB2__IRQ_ROLE_CHANGE] |= s_role_change;
    s_irq_event[`APB4_USB2__IRQ_SETUP] |= s_setup_valid_sys;
    s_irq_event[`APB4_USB2__IRQ_ULPI_ERROR] |= s_protocol_event_sys;
    s_irq_event[`APB4_USB2__IRQ_ECC_CORRECTED] |= s_ecc_corrected_event;
    s_irq_event[`APB4_USB2__IRQ_ECC_UNCORRECTABLE] |= s_ecc_uncorrectable_event;
  end

  usb2_reg #(
      .NumEndpoints(NumEndpoints),
      .NumChannels (NumChannels)
  ) u_reg (
      .clk_i                        (clk_i),
      .rst_n_i                      (rst_n_i),
      .apb4                         (apb4),
      .global_status_i              (s_global_stat),
      .role_status_i                (s_role_stat),
      .phy_status_i                 (s_phy_stat),
      .frame_i                      (s_frame_stat),
      .device_status_i              (s_device_stat),
      .setup_packet_i               (s_setup_packet_q),
      .endpoint_pending_in_i        (s_endpoint_pending_in),
      .endpoint_pending_out_i       (s_endpoint_pending_out),
      .endpoint_complete_in_i       (s_endpoint_complete_in),
      .endpoint_complete_out_i      (s_endpoint_complete_out),
      .endpoint_status_i            (s_endpoint_stat),
      .endpoint_bytes_in_i          (s_endpoint_bytes_in),
      .endpoint_bytes_out_i         (s_endpoint_bytes_out),
      .host_status_i                (s_host_stat),
      .port_status_i                (s_port_stat),
      .schedule_status_i            (s_schedule_stat),
      .channel_status_i             (s_channel_stat),
      .channel_bytes_i              (s_channel_bytes),
      .ram_status_i                 (s_ram_stat),
      .ecc_status_i                 (s_ecc_stat),
      .ecc_corrected_count_i        (s_ecc_corrected_count_sys),
      .ecc_uncorrectable_count_i    (s_ecc_uncorrectable_count_sys),
      .debug_status_i               (s_debug_stat),
      .perf_tx_bytes_i              (s_perf_tx_bytes),
      .perf_rx_bytes_i              (s_perf_rx_bytes),
      .perf_packets_i               (s_perf_packets),
      .perf_retries_i               (s_perf_retries),
      .perf_axi_stall_i             (s_perf_axi_stall_q),
      .perf_ram_stall_i             (s_perf_ram_stall_q),
      .perf_irq_count_i             (s_perf_irq_count),
      .irq_event_i                  (s_irq_event),
      .error_capture_i              (s_err_capture),
      .error_status_i               (s_err_stat),
      .error_code_i                 (s_err_code),
      .error_info_i                 (s_err_info),
      .error_desc_addr_i            (s_err_desc_addr),
      .error_buffer_addr_i          (s_err_buffer_addr),
      .viewport_resp_valid_i        (s_viewport_resp_valid_sys),
      .viewport_read_data_i         (s_viewport_resp_data_sys[7:0]),
      .viewport_error_i             (s_viewport_resp_data_sys[8]),
      .enable_o                     (s_en),
      .soft_reset_o                 (s_soft_reset),
      .abort_o                      (s_abort),
      .force_role_o                 (s_force_role),
      .auto_role_o                  (s_auto_role),
      .phy_reset_n_o                (s_phy_reset_n_cfg),
      .phy_suspend_o                (s_phy_suspend),
      .remote_wake_o                (s_remote_wake),
      .timeout_o                    (s_timeout),
      .test_ctrl_o                  (s_test_ctrl),
      .perf_clear_o                 (s_perf_clear),
      .device_addr_o                (s_device_addr),
      .device_ctrl_o                (s_device_ctrl),
      .endpoint_cfg_o               (s_endpoint_cfg),
      .endpoint_ram_in_o            (s_endpoint_ram_in),
      .endpoint_ram_out_o           (s_endpoint_ram_out),
      .endpoint_desc_in_o           (s_endpoint_desc_in),
      .endpoint_desc_out_o          (s_endpoint_desc_out),
      .endpoint_command_o           (s_endpoint_cmd),
      .endpoint_complete_clear_in_o (s_endpoint_complete_clear_in),
      .endpoint_complete_clear_out_o(s_endpoint_complete_clear_out),
      .host_ctrl_o                  (s_host_ctrl),
      .port_ctrl_o                  (s_port_ctrl),
      .schedule_ctrl_o              (s_schedule_ctrl),
      .channel_cfg_o                (s_channel_cfg),
      .channel_target_o             (s_channel_target),
      .channel_interval_o           (s_channel_interval),
      .channel_ram_o                (s_channel_ram),
      .channel_desc_o               (s_channel_desc),
      .channel_command_o            (s_channel_cmd),
      .ram_ctrl_o                   (s_ram_ctrl),
      .ram_bist_start_o             (s_ram_bist_start),
      .viewport_valid_o             (s_viewport_valid),
      .viewport_write_o             (s_viewport_write),
      .viewport_addr_o              (s_viewport_addr),
      .viewport_write_data_o        (s_viewport_write_data),
      .irq_o                        (irq_o)
  );

  usb2_role_controller u_role_controller (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .enable_i          (s_en),
      .soft_reset_i      (s_soft_reset),
      .auto_role_i       (s_auto_role),
      .force_role_i      (s_force_role),
      .id_ground_i       (s_id_ground_sys),
      .vbus_valid_i      (s_vbus_state_sys == 2'b11),
      .transaction_busy_i(s_scheduler_busy || s_dma_busy || s_transaction_busy_sys),
      .active_role_o     (s_active_role_sys),
      .role_change_o     (s_role_change),
      .role_reset_o      (s_role_reset),
      .switch_pending_o  (s_role_switch_pending)
  );

  usb2_scheduler #(
      .NumEndpoints(NumEndpoints),
      .NumChannels (NumChannels)
  ) u_scheduler (
      .clk_i                        (clk_i),
      .rst_n_i                      (rst_n_i),
      .enable_i                     (s_en),
      .abort_i                      (s_abort),
      .reinitialize_i               (s_soft_reset || s_role_reset),
      .perf_clear_i                 (s_perf_clear),
      .high_speed_i                 (!s_port_ctrl),
      .frame_i                      (s_frame_sys),
      .active_role_i                (s_active_role_sys),
      .endpoint_cfg_i               (s_endpoint_cfg),
      .endpoint_ram_in_i            (s_endpoint_ram_in),
      .endpoint_ram_out_i           (s_endpoint_ram_out),
      .endpoint_desc_in_i           (s_endpoint_desc_in),
      .endpoint_desc_out_i          (s_endpoint_desc_out),
      .endpoint_command_i           (s_endpoint_cmd),
      .endpoint_complete_clear_in_i (s_endpoint_complete_clear_in),
      .endpoint_complete_clear_out_i(s_endpoint_complete_clear_out),
      .channel_cfg_i                (s_channel_cfg),
      .channel_target_i             (s_channel_target),
      .channel_interval_i           (s_channel_interval),
      .channel_ram_i                (s_channel_ram),
      .channel_desc_i               (s_channel_desc),
      .channel_command_i            (s_channel_cmd),
      .work_valid_o                 (s_work_valid_sys),
      .work_ready_i                 (s_work_ready_sys),
      .work_data_o                  (s_work_data_sys),
      .result_valid_i               (s_result_valid_sys),
      .result_ready_o               (s_result_ready_sys),
      .result_data_i                (s_result_data_sys),
      .fill_cmd_valid_o             (s_fill_cmd_valid_sys),
      .fill_cmd_ready_i             (s_fill_cmd_ready_sys),
      .fill_cmd_data_o              (s_fill_cmd_data_sys),
      .drain_cmd_valid_o            (s_drain_cmd_valid_sys),
      .drain_cmd_ready_i            (s_drain_cmd_ready_sys),
      .drain_cmd_data_o             (s_drain_cmd_data_sys),
      .buffer_event_valid_i         (s_buffer_event_valid_sys),
      .buffer_event_ready_o         (s_buffer_event_ready_sys),
      .buffer_event_data_i          (s_buffer_event_data_sys),
      .dma_start_o                  (s_dma_start),
      .dma_abort_o                  (s_dma_abort),
      .dma_memory_to_packet_o       (s_dma_memory_to_packet),
      .dma_desc_base_o              (s_dma_desc_base),
      .dma_transfer_bytes_o         (s_dma_transfer_bytes),
      .dma_busy_i                   (s_dma_busy),
      .dma_done_i                   (s_dma_done),
      .dma_error_i                  (s_dma_err),
      .dma_error_code_i             (s_dma_err_code),
      .dma_current_desc_i           (s_dma_current_desc),
      .dma_bytes_done_i             (s_dma_bytes_done),
      .retry_i                      (s_retry_event_sys),
      .endpoint_pending_in_o        (s_endpoint_pending_in),
      .endpoint_pending_out_o       (s_endpoint_pending_out),
      .endpoint_complete_in_o       (s_endpoint_complete_in),
      .endpoint_complete_out_o      (s_endpoint_complete_out),
      .endpoint_status_o            (s_endpoint_stat),
      .endpoint_bytes_in_o          (s_endpoint_bytes_in),
      .endpoint_bytes_out_o         (s_endpoint_bytes_out),
      .channel_status_o             (s_channel_stat),
      .channel_bytes_o              (s_channel_bytes),
      .irq_event_o                  (s_scheduler_irq_event),
      .error_capture_o              (s_err_capture),
      .error_status_o               (s_err_stat),
      .error_code_o                 (s_err_code),
      .error_info_o                 (s_err_info),
      .error_desc_addr_o            (s_err_desc_addr),
      .error_buffer_addr_o          (s_err_buffer_addr),
      .perf_tx_bytes_o              (s_perf_tx_bytes),
      .perf_rx_bytes_o              (s_perf_rx_bytes),
      .perf_packets_o               (s_perf_packets),
      .perf_retries_o               (s_perf_retries),
      .perf_irq_count_o             (s_perf_irq_count),
      .busy_o                       (s_scheduler_busy)
  );

  usb2_dma u_dma (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .start_i           (s_dma_start),
      .abort_i           (s_dma_abort),
      .memory_to_packet_i(s_dma_memory_to_packet),
      .allow_short_i     (1'b1),
      .desc_base_i       (s_dma_desc_base),
      .desc_limit_i      (16'd256),
      .transfer_bytes_i  (s_dma_transfer_bytes),
      .packet_in_valid_i (s_drain_stream_valid_sys),
      .packet_in_ready_o (s_drain_stream_ready_sys),
      .packet_in_data_i  (s_drain_stream_data_sys[31:0]),
      .packet_in_strb_i  (s_drain_stream_data_sys[35:32]),
      .packet_in_last_i  (s_drain_stream_data_sys[36]),
      .packet_out_valid_o(s_fill_stream_valid_sys),
      .packet_out_ready_i(s_fill_stream_ready_sys),
      .packet_out_data_o (s_fill_stream_data_sys[31:0]),
      .packet_out_strb_o (s_fill_stream_data_sys[35:32]),
      .packet_out_last_o (s_fill_stream_data_sys[36]),
      .busy_o            (s_dma_busy),
      .done_o            (s_dma_done),
      .error_o           (s_dma_err),
      .error_code_o      (s_dma_err_code),
      .current_desc_o    (s_dma_current_desc),
      .next_desc_o       (s_dma_next_desc),
      .bytes_done_o      (s_dma_bytes_done),
      .frame_o           (s_dma_frame),
      .descriptor_irq_o  (s_dma_descriptor_irq),
      .abort_done_o      (s_dma_abort_done),
      .dma_axi4          (dma_axi4)
  );

  async_reqack #(
      .DATA_WIDTH(64)
  ) u_work_cdc (
      .src_clk_i  (clk_i),
      .src_rst_n_i(rst_n_i),
      .src_valid_i(s_work_valid_sys),
      .src_ready_o(s_work_ready_sys),
      .src_data_i (s_work_data_sys),
      .dst_clk_i  (clk_ulpi_i),
      .dst_rst_n_i(s_link_rst_n),
      .dst_valid_o(s_work_valid_ulpi),
      .dst_ready_i(s_work_ready_ulpi),
      .dst_data_o (s_work_data_ulpi)
  );
  async_reqack #(
      .DATA_WIDTH(64)
  ) u_result_cdc (
      .src_clk_i  (clk_ulpi_i),
      .src_rst_n_i(s_link_rst_n),
      .src_valid_i(s_result_valid_ulpi),
      .src_ready_o(s_result_ready_ulpi),
      .src_data_i (s_result_data_ulpi),
      .dst_clk_i  (clk_i),
      .dst_rst_n_i(rst_n_i),
      .dst_valid_o(s_result_valid_sys),
      .dst_ready_i(s_result_ready_sys),
      .dst_data_o (s_result_data_sys)
  );
  async_reqack #(
      .DATA_WIDTH(64)
  ) u_setup_cdc (
      .src_clk_i  (clk_ulpi_i),
      .src_rst_n_i(s_link_rst_n),
      .src_valid_i(s_setup_valid_ulpi),
      .src_ready_o(s_setup_ready_ulpi),
      .src_data_i (s_setup_data_ulpi),
      .dst_clk_i  (clk_i),
      .dst_rst_n_i(rst_n_i),
      .dst_valid_o(s_setup_valid_sys),
      .dst_ready_i(1'b1),
      .dst_data_o (s_setup_data_sys)
  );
  async_reqack #(
      .DATA_WIDTH(27)
  ) u_fill_command_cdc (
      .src_clk_i  (clk_i),
      .src_rst_n_i(rst_n_i),
      .src_valid_i(s_fill_cmd_valid_sys),
      .src_ready_o(s_fill_cmd_ready_sys),
      .src_data_i (s_fill_cmd_data_sys),
      .dst_clk_i  (clk_ulpi_i),
      .dst_rst_n_i(s_link_rst_n),
      .dst_valid_o(s_fill_cmd_valid_ulpi),
      .dst_ready_i(s_fill_cmd_ready_ulpi),
      .dst_data_o (s_fill_cmd_data_ulpi)
  );
  async_reqack #(
      .DATA_WIDTH(27)
  ) u_drain_command_cdc (
      .src_clk_i  (clk_i),
      .src_rst_n_i(rst_n_i),
      .src_valid_i(s_drain_cmd_valid_sys),
      .src_ready_o(s_drain_cmd_ready_sys),
      .src_data_i (s_drain_cmd_data_sys),
      .dst_clk_i  (clk_ulpi_i),
      .dst_rst_n_i(s_link_rst_n),
      .dst_valid_o(s_drain_cmd_valid_ulpi),
      .dst_ready_i(s_drain_cmd_ready_ulpi),
      .dst_data_o (s_drain_cmd_data_ulpi)
  );
  async_reqack #(
      .DATA_WIDTH(3)
  ) u_buffer_event_cdc (
      .src_clk_i  (clk_ulpi_i),
      .src_rst_n_i(s_link_rst_n),
      .src_valid_i(s_buffer_event_valid_ulpi),
      .src_ready_o(s_buffer_event_ready_ulpi),
      .src_data_i (s_buffer_event_data_ulpi),
      .dst_clk_i  (clk_i),
      .dst_rst_n_i(rst_n_i),
      .dst_valid_o(s_buffer_event_valid_sys),
      .dst_ready_i(s_buffer_event_ready_sys),
      .dst_data_o (s_buffer_event_data_sys)
  );
  async_reqack #(
      .DATA_WIDTH(15)
  ) u_view_request_cdc (
      .src_clk_i  (clk_i),
      .src_rst_n_i(rst_n_i),
      .src_valid_i(s_view_req_valid_sys),
      .src_ready_o(s_view_req_ready_sys),
      .src_data_i (s_view_req_data_sys),
      .dst_clk_i  (clk_ulpi_i),
      .dst_rst_n_i(s_link_rst_n),
      .dst_valid_o(s_view_req_valid_ulpi),
      .dst_ready_i(s_view_req_ready_ulpi),
      .dst_data_o (s_view_req_data_ulpi)
  );
  async_reqack #(
      .DATA_WIDTH(9)
  ) u_view_response_cdc (
      .src_clk_i  (clk_ulpi_i),
      .src_rst_n_i(s_link_rst_n),
      .src_valid_i(s_view_resp_valid_ulpi),
      .src_ready_o(s_view_resp_ready_ulpi),
      .src_data_i (s_view_resp_data_ulpi),
      .dst_clk_i  (clk_i),
      .dst_rst_n_i(rst_n_i),
      .dst_valid_o(s_viewport_resp_valid_sys),
      .dst_ready_i(1'b1),
      .dst_data_o (s_viewport_resp_data_sys)
  );
  cdc_fifo #(
      .DATA_WIDTH  (37),
      .BUFFER_DEPTH(8)
  ) u_fill_stream_cdc (
      .src_clk_i  (clk_i),
      .src_rst_n_i(rst_n_i),
      .src_data_i (s_fill_stream_data_sys),
      .src_valid_i(s_fill_stream_valid_sys),
      .src_ready_o(s_fill_stream_ready_sys),
      .dst_clk_i  (clk_ulpi_i),
      .dst_rst_n_i(s_link_rst_n),
      .dst_data_o (s_fill_stream_data_ulpi),
      .dst_valid_o(s_fill_stream_valid_ulpi),
      .dst_ready_i(s_fill_stream_ready_ulpi)
  );
  cdc_fifo #(
      .DATA_WIDTH  (37),
      .BUFFER_DEPTH(8)
  ) u_drain_stream_cdc (
      .src_clk_i  (clk_ulpi_i),
      .src_rst_n_i(s_link_rst_n),
      .src_data_i (s_drain_fifo_data_ulpi),
      .src_valid_i(s_drain_fifo_valid_ulpi),
      .src_ready_o(s_drain_fifo_ready_ulpi),
      .dst_clk_i  (clk_i),
      .dst_rst_n_i(rst_n_i),
      .dst_data_o (s_drain_stream_data_sys),
      .dst_valid_o(s_drain_stream_valid_sys),
      .dst_ready_i(s_drain_stream_ready_sys)
  );

  spill_register #(
      .DATA_WIDTH(37)
  ) u_drain_stream_spill (
      .clk_i  (clk_ulpi_i),
      .rst_n_i(s_link_rst_n),
      .flush_i(1'b0),
      .valid_i(s_drain_stream_valid_ulpi),
      .ready_o(s_drain_stream_ready_ulpi),
      .data_i (s_drain_stream_data_ulpi),
      .valid_o(s_drain_fifo_valid_ulpi),
      .ready_i(s_drain_fifo_ready_ulpi),
      .data_o (s_drain_fifo_data_ulpi)
  );

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(2)
  ) u_role_sync (
      .clk_i  (clk_ulpi_i),
      .rst_n_i(s_link_rst_n),
      .dat_i  (s_active_role_sys),
      .dat_o  (s_active_role_ulpi_bits)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_role_reset_sync (
      .clk_i  (clk_ulpi_i),
      .rst_n_i(s_ulpi_rst_n),
      .dat_i  (s_role_reset),
      .dat_o  (s_role_reset_ulpi)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_phy_reset_sync (
      .clk_i  (clk_ulpi_i),
      .rst_n_i(s_link_rst_n),
      .dat_i  (s_phy_reset_n_cfg && !s_role_reset),
      .dat_o  (s_phy_reset_n_ulpi)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_high_speed_sync (
      .clk_i  (clk_ulpi_i),
      .rst_n_i(s_link_rst_n),
      .dat_i  (!s_port_ctrl),
      .dat_o  (s_high_speed_ulpi)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_enable_sync (
      .clk_i  (clk_ulpi_i),
      .rst_n_i(s_link_rst_n),
      .dat_i  (s_en),
      .dat_o  (s_en_ulpi)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(7)
  ) u_device_addr_sync (
      .clk_i  (clk_ulpi_i),
      .rst_n_i(s_link_rst_n),
      .dat_i  (s_device_addr),
      .dat_o  (s_device_addr_ulpi)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(NumEndpoints * 32)
  ) u_endpoint_cfg_sync (
      .clk_i  (clk_ulpi_i),
      .rst_n_i(s_link_rst_n),
      .dat_i  (s_endpoint_cfg),
      .dat_o  (s_endpoint_cfg_ulpi)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(32)
  ) u_timeout_sync (
      .clk_i  (clk_ulpi_i),
      .rst_n_i(s_link_rst_n),
      .dat_i  (s_timeout),
      .dat_o  (s_timeout_ulpi)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(6)
  ) u_phy_status_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  ({s_id_ground_ulpi, s_vbus_state_ulpi, s_line_state_ulpi, s_link_ready_ulpi}),
      .dat_o  ({s_id_ground_sys, s_vbus_state_sys, s_line_state_sys, s_link_ready_sys})
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_transaction_busy_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_transaction_busy_ulpi),
      .dat_o  (s_transaction_busy_sys)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(14)
  ) u_frame_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_frame_ulpi),
      .dat_o  (s_frame_sys)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(64)
  ) u_ecc_counts_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  ({s_ecc_uncorrectable_count_ulpi, s_ecc_corrected_count_ulpi}),
      .dat_o  ({s_ecc_uncorrectable_count_sys, s_ecc_corrected_count_sys})
  );

  edge_det #(
      .STAGE(2)
  ) u_retry_event_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_retry_toggle_q),
      .dat_o  (s_retry_toggle_level_sys),
      .re_o   (s_retry_re_sys),
      .fe_o   (s_retry_fe_sys)
  );
  edge_det #(
      .STAGE(2)
  ) u_protocol_event_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_protocol_toggle_q),
      .dat_o  (s_protocol_toggle_level_sys),
      .re_o   (s_protocol_re_sys),
      .fe_o   (s_protocol_fe_sys)
  );

  usb2_link_domain #(
      .NumEndpoints(NumEndpoints)
  ) u_link_domain (
      .clk_i                    (clk_ulpi_i),
      .rst_n_i                  (s_link_rst_n),
      .enable_i                 (s_en_ulpi),
      .phy_reset_n_i            (s_phy_reset_n_ulpi),
      .high_speed_i             (s_high_speed_ulpi),
      .active_role_i            (s_active_role_ulpi),
      .device_addr_i            (s_device_addr_ulpi),
      .endpoint_cfg_i           (s_endpoint_cfg_ulpi),
      .timeout_i                (s_timeout_ulpi),
      .work_valid_i             (s_work_valid_ulpi),
      .work_ready_o             (s_work_ready_ulpi),
      .work_data_i              (s_work_data_ulpi),
      .result_valid_o           (s_result_valid_ulpi),
      .result_ready_i           (s_result_ready_ulpi),
      .result_data_o            (s_result_data_ulpi),
      .setup_valid_o            (s_setup_valid_ulpi),
      .setup_ready_i            (s_setup_ready_ulpi),
      .setup_data_o             (s_setup_data_ulpi),
      .fill_cmd_valid_i         (s_fill_cmd_valid_ulpi),
      .fill_cmd_ready_o         (s_fill_cmd_ready_ulpi),
      .fill_cmd_data_i          (s_fill_cmd_data_ulpi),
      .fill_stream_valid_i      (s_fill_stream_valid_ulpi),
      .fill_stream_ready_o      (s_fill_stream_ready_ulpi),
      .fill_stream_data_i       (s_fill_stream_data_ulpi),
      .drain_cmd_valid_i        (s_drain_cmd_valid_ulpi),
      .drain_cmd_ready_o        (s_drain_cmd_ready_ulpi),
      .drain_cmd_data_i         (s_drain_cmd_data_ulpi),
      .drain_stream_valid_o     (s_drain_stream_valid_ulpi),
      .drain_stream_ready_i     (s_drain_stream_ready_ulpi),
      .drain_stream_data_o      (s_drain_stream_data_ulpi),
      .buffer_event_valid_o     (s_buffer_event_valid_ulpi),
      .buffer_event_ready_i     (s_buffer_event_ready_ulpi),
      .buffer_event_data_o      (s_buffer_event_data_ulpi),
      .viewport_valid_i         (s_view_req_valid_ulpi),
      .viewport_ready_o         (s_view_req_ready_ulpi),
      .viewport_data_i          (s_view_req_data_ulpi),
      .viewport_resp_valid_o    (s_view_resp_valid_ulpi),
      .viewport_resp_ready_i    (s_view_resp_ready_ulpi),
      .viewport_resp_data_o     (s_view_resp_data_ulpi),
      .line_state_o             (s_line_state_ulpi),
      .vbus_state_o             (s_vbus_state_ulpi),
      .id_ground_o              (s_id_ground_ulpi),
      .link_ready_o             (s_link_ready_ulpi),
      .frame_o                  (s_frame_ulpi),
      .transaction_busy_o       (s_transaction_busy_ulpi),
      .retry_o                  (s_retry_ulpi),
      .protocol_error_o         (s_protocol_err_ulpi),
      .ecc_corrected_count_o    (s_ecc_corrected_count_ulpi),
      .ecc_uncorrectable_count_o(s_ecc_uncorrectable_count_ulpi),
      .ulpi                     (ulpi)
  );

  dffr #(
      .DATA_WIDTH(64)
  ) u_setup_packet_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_setup_packet_d),
      .dat_o  (s_setup_packet_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_retry_toggle_dffr (
      .clk_i  (clk_ulpi_i),
      .rst_n_i(s_link_rst_n),
      .dat_i  (s_retry_toggle_d),
      .dat_o  (s_retry_toggle_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_protocol_toggle_dffr (
      .clk_i  (clk_ulpi_i),
      .rst_n_i(s_link_rst_n),
      .dat_i  (s_protocol_toggle_d),
      .dat_o  (s_protocol_toggle_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_ecc_corrected_previous_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ecc_corrected_previous_d),
      .dat_o  (s_ecc_corrected_previous_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_ecc_uncorrectable_previous_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ecc_uncorrectable_previous_d),
      .dat_o  (s_ecc_uncorrectable_previous_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_view_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_view_pending_d),
      .dat_o  (s_view_pending_q)
  );
  dffr #(
      .DATA_WIDTH(15)
  ) u_view_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_view_data_d),
      .dat_o  (s_view_data_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_axi_stall_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_axi_stall_d),
      .dat_o  (s_perf_axi_stall_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_ram_stall_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_ram_stall_d),
      .dat_o  (s_perf_ram_stall_q)
  );
endmodule
