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

module usb2_reg_tb;
  localparam logic [31:0] UsbBase = 32'h1001_6000;
  logic              s_clk;
  logic              s_rst_n;
  logic [15:0]       s_irq_event;
  logic              s_irq;
  logic              s_enable;
  logic [ 1:0]       s_force_role;
  logic              s_auto_role;
  logic [ 7:0][31:0] s_endpoint_status;
  logic [ 7:0][31:0] s_endpoint_bytes_in;
  logic [ 7:0][31:0] s_endpoint_bytes_out;
  logic [15:0][31:0] s_channel_status;
  logic [15:0][31:0] s_channel_bytes;
  logic [ 7:0][31:0] s_endpoint_cfg;
  logic [ 7:0][31:0] s_endpoint_ram_in;
  logic [ 7:0][31:0] s_endpoint_ram_out;
  logic [ 7:0][31:0] s_endpoint_desc_in;
  logic [ 7:0][31:0] s_endpoint_desc_out;
  logic [ 7:0][31:0] s_endpoint_command;
  logic [31:0]       s_endpoint_complete_clear_in;
  logic [31:0]       s_endpoint_complete_clear_out;
  logic              s_endpoint_clear_seen;
  logic [15:0][31:0] s_channel_cfg;
  logic [15:0][31:0] s_channel_target;
  logic [15:0][31:0] s_channel_interval;
  logic [15:0][31:0] s_channel_ram;
  logic [15:0][31:0] s_channel_desc;
  logic [15:0][31:0] s_channel_command;
  apb4_if u_apb4 (
      .pclk   (s_clk),
      .presetn(s_rst_n)
  );

  usb2_reg u_reg (
      .clk_i                        (s_clk),
      .rst_n_i                      (s_rst_n),
      .global_status_i              (32'd0),
      .role_status_i                (32'd0),
      .phy_status_i                 (32'd0),
      .frame_i                      (32'd0),
      .device_status_i              (32'd0),
      .setup_packet_i               (64'd0),
      .endpoint_pending_in_i        (32'd0),
      .endpoint_pending_out_i       (32'd0),
      .endpoint_complete_in_i       (32'd0),
      .endpoint_complete_out_i      (32'd0),
      .endpoint_status_i            (s_endpoint_status),
      .endpoint_bytes_in_i          (s_endpoint_bytes_in),
      .endpoint_bytes_out_i         (s_endpoint_bytes_out),
      .host_status_i                (32'd0),
      .port_status_i                (32'd0),
      .schedule_status_i            (32'd0),
      .channel_status_i             (s_channel_status),
      .channel_bytes_i              (s_channel_bytes),
      .ram_status_i                 (32'd0),
      .ecc_status_i                 (32'd0),
      .ecc_corrected_count_i        (32'd0),
      .ecc_uncorrectable_count_i    (32'd0),
      .debug_status_i               (32'd0),
      .perf_tx_bytes_i              (32'd0),
      .perf_rx_bytes_i              (32'd0),
      .perf_packets_i               (32'd0),
      .perf_retries_i               (32'd0),
      .perf_axi_stall_i             (32'd0),
      .perf_ram_stall_i             (32'd0),
      .perf_irq_count_i             (32'd0),
      .irq_event_i                  (s_irq_event),
      .error_capture_i              (1'b0),
      .error_status_i               (32'd0),
      .error_code_i                 (32'd0),
      .error_info_i                 (32'd0),
      .error_desc_addr_i            (32'd0),
      .error_buffer_addr_i          (32'd0),
      .viewport_resp_valid_i        (1'b0),
      .viewport_read_data_i         (8'd0),
      .viewport_error_i             (1'b0),
      .enable_o                     (s_enable),
      .soft_reset_o                 (),
      .abort_o                      (),
      .force_role_o                 (s_force_role),
      .auto_role_o                  (s_auto_role),
      .phy_reset_n_o                (),
      .phy_suspend_o                (),
      .remote_wake_o                (),
      .timeout_o                    (),
      .test_ctrl_o                  (),
      .perf_clear_o                 (),
      .device_addr_o                (),
      .device_ctrl_o                (),
      .endpoint_cfg_o               (s_endpoint_cfg),
      .endpoint_ram_in_o            (s_endpoint_ram_in),
      .endpoint_ram_out_o           (s_endpoint_ram_out),
      .endpoint_desc_in_o           (s_endpoint_desc_in),
      .endpoint_desc_out_o          (s_endpoint_desc_out),
      .endpoint_command_o           (s_endpoint_command),
      .endpoint_complete_clear_in_o (s_endpoint_complete_clear_in),
      .endpoint_complete_clear_out_o(s_endpoint_complete_clear_out),
      .host_ctrl_o                  (),
      .port_ctrl_o                  (),
      .schedule_ctrl_o              (),
      .channel_cfg_o                (s_channel_cfg),
      .channel_target_o             (s_channel_target),
      .channel_interval_o           (s_channel_interval),
      .channel_ram_o                (s_channel_ram),
      .channel_desc_o               (s_channel_desc),
      .channel_command_o            (s_channel_command),
      .ram_ctrl_o                   (),
      .ram_bist_start_o             (),
      .viewport_valid_o             (),
      .viewport_write_o             (),
      .viewport_addr_o              (),
      .viewport_write_data_o        (),
      .irq_o                        (s_irq),
      .apb4                         (u_apb4)
  );

  always #5 s_clk = ~s_clk;

  always_ff @(posedge s_clk or negedge s_rst_n) begin
    if (!s_rst_n) begin
      s_endpoint_clear_seen <= 1'b0;
    end else if ((s_endpoint_complete_clear_in == 32'h0000_00A5) &&
                 (s_endpoint_complete_clear_out == 32'd0)) begin
      s_endpoint_clear_seen <= 1'b1;
    end
  end

  task automatic apb_write(input logic [31:0] addr_i, input logic [31:0] data_i,
                           input logic expected_error_i);
    begin
      @(negedge s_clk);
      u_apb4.paddr   = addr_i;
      u_apb4.pwdata  = data_i;
      u_apb4.pstrb   = 4'hF;
      u_apb4.pwrite  = 1'b1;
      u_apb4.psel    = 1'b1;
      u_apb4.penable = 1'b0;
      @(negedge s_clk);
      u_apb4.penable = 1'b1;
      @(posedge s_clk);
      #1;
      if (!u_apb4.pready || (u_apb4.pslverr != expected_error_i)) begin
        $fatal(1, "USB2 APB write failure addr=%h ready=%b error=%b", addr_i, u_apb4.pready,
               u_apb4.pslverr);
      end
      @(negedge s_clk);
      u_apb4.psel    = 1'b0;
      u_apb4.penable = 1'b0;
    end
  endtask

  task automatic apb_read(input logic [31:0] addr_i, output logic [31:0] data_o,
                          input logic expected_error_i);
    begin
      @(negedge s_clk);
      u_apb4.paddr   = addr_i;
      u_apb4.pwdata  = 32'd0;
      u_apb4.pstrb   = 4'd0;
      u_apb4.pwrite  = 1'b0;
      u_apb4.psel    = 1'b1;
      u_apb4.penable = 1'b0;
      @(negedge s_clk);
      u_apb4.penable = 1'b1;
      @(posedge s_clk);
      #1;
      if (!u_apb4.pready || (u_apb4.pslverr != expected_error_i)) begin
        $fatal(1, "USB2 APB read failure addr=%h ready=%b error=%b", addr_i, u_apb4.pready,
               u_apb4.pslverr);
      end
      data_o = u_apb4.prdata;
      @(negedge s_clk);
      u_apb4.psel    = 1'b0;
      u_apb4.penable = 1'b0;
    end
  endtask

  initial begin
    logic [31:0] value;
    s_clk          = 1'b0;
    s_rst_n        = 1'b0;
    s_irq_event    = 16'd0;
    u_apb4.paddr   = 32'd0;
    u_apb4.pprot   = 3'd0;
    u_apb4.psel    = 1'b0;
    u_apb4.penable = 1'b0;
    u_apb4.pwrite  = 1'b0;
    u_apb4.pwdata  = 32'd0;
    u_apb4.pstrb   = 4'd0;
    for (int endpoint = 0; endpoint < 8; endpoint++) begin
      s_endpoint_status[endpoint]    = 32'd0;
      s_endpoint_bytes_in[endpoint]  = 32'd0;
      s_endpoint_bytes_out[endpoint] = 32'd0;
    end
    for (int channel = 0; channel < 16; channel++) begin
      s_channel_status[channel] = 32'd0;
      s_channel_bytes[channel]  = 32'd0;
    end
    repeat (3) @(posedge s_clk);
    s_rst_n = 1'b1;

    apb_read(UsbBase + `APB4_USB2__IP_ID, value, 1'b0);
    if (value != 32'h5553_4232) $fatal(1, "USB2 IP ID mismatch");
    apb_read(UsbBase + `APB4_USB2__CAPABILITY0, value, 1'b0);
    if ((value[19:16] != 4'd7) || (value[27:24] != 4'd15)) begin
      $fatal(1, "USB2 capability scale mismatch: %h", value);
    end
    apb_write(UsbBase + `APB4_USB2__ROLE_CTRL, 32'h0000_0006, 1'b0);
    if ((s_force_role != 2'd2) || !s_auto_role) $fatal(1, "USB2 role control mismatch");
    apb_write(
        UsbBase + `APB4_USB2__ENDPOINT_BASE + `APB4_USB2__ENDPOINT_STRIDE +
              `APB4_USB2__ENDPOINT_CFG,
        32'h0000_020D, 1'b0);
    apb_read(
        UsbBase + `APB4_USB2__ENDPOINT_BASE + `APB4_USB2__ENDPOINT_STRIDE +
             `APB4_USB2__ENDPOINT_CFG,
        value, 1'b0);
    if (value != 32'h0000_020D) $fatal(1, "USB2 endpoint configuration mismatch");
    apb_write(UsbBase + `APB4_USB2__ENDPOINT_COMPLETE_IN, 32'h0000_00A5, 1'b0);
    if (!s_endpoint_clear_seen) $fatal(1, "USB2 endpoint completion W1C mismatch");
    apb_write(UsbBase + `APB4_USB2__IRQ_ENABLE, 32'h0000_0020, 1'b0);
    apb_write(UsbBase + `APB4_USB2__IRQ_TEST, 32'h0000_0020, 1'b0);
    apb_write(UsbBase + `APB4_USB2__GLOBAL_CTRL, 32'h0000_0009, 1'b0);
    if (!s_enable || !s_irq) $fatal(1, "USB2 interrupt test failed");
    apb_write(UsbBase + `APB4_USB2__ROLE_CTRL, 32'h0000_0001, 1'b1);
    apb_read(UsbBase + 32'h0000_0001, value, 1'b1);
    $display("USB2 APB register contract passed");
    $finish;
  end
endmodule
