`timescale 1ns / 1ps

module usb2_link_domain_tb;
  logic              clk_i = 1'b0;
  logic              rst_n_i = 1'b0;
  logic              enable_i = 1'b0;
  logic              fill_cmd_valid_i = 1'b1;
  logic              drain_cmd_valid_i = 1'b1;
  logic [ 7:0][31:0] endpoint_cfg_i = '0;
  logic              work_ready_o;
  logic              result_valid_o;
  logic [63:0]       result_data_o;
  logic              setup_valid_o;
  logic [63:0]       setup_data_o;
  logic              fill_cmd_ready_o;
  logic              fill_stream_ready_o;
  logic              drain_cmd_ready_o;
  logic              drain_stream_valid_o;
  logic [36:0]       drain_stream_data_o;
  logic              buffer_event_valid_o;
  logic [ 2:0]       buffer_event_data_o;
  logic              viewport_ready_o;
  logic              viewport_resp_valid_o;
  logic [ 8:0]       viewport_resp_data_o;
  logic [ 1:0]       line_state_o;
  logic [ 1:0]       vbus_state_o;
  logic              id_ground_o;
  logic              link_ready_o;
  logic [13:0]       frame_o;
  logic              transaction_busy_o;
  logic              retry_o;
  logic              protocol_error_o;
  logic [31:0]       ecc_corrected_count_o;
  logic [31:0]       ecc_uncorrectable_count_o;

  usb2_ulpi_if ulpi ();

  always #5 clk_i = ~clk_i;
  assign ulpi.data_di_i = 8'd0;
  assign ulpi.dir_i     = 1'b0;
  assign ulpi.nxt_i     = 1'b1;

  usb2_link_domain u_dut (
      .clk_i                    (clk_i),
      .rst_n_i                  (rst_n_i),
      .enable_i                 (enable_i),
      .phy_reset_n_i            (1'b1),
      .high_speed_i             (1'b1),
      .active_role_i            (usb2_pkg::Usb2RoleIdle),
      .device_addr_i            (7'd0),
      .endpoint_cfg_i           (endpoint_cfg_i),
      .timeout_i                (32'd1000),
      .work_valid_i             (1'b0),
      .work_ready_o             (work_ready_o),
      .work_data_i              ('0),
      .result_valid_o           (result_valid_o),
      .result_ready_i           (1'b1),
      .result_data_o            (result_data_o),
      .setup_valid_o            (setup_valid_o),
      .setup_ready_i            (1'b1),
      .setup_data_o             (setup_data_o),
      .fill_cmd_valid_i         (fill_cmd_valid_i),
      .fill_cmd_ready_o         (fill_cmd_ready_o),
      .fill_cmd_data_i          ('0),
      .fill_stream_valid_i      (1'b0),
      .fill_stream_ready_o      (fill_stream_ready_o),
      .fill_stream_data_i       ('0),
      .drain_cmd_valid_i        (drain_cmd_valid_i),
      .drain_cmd_ready_o        (drain_cmd_ready_o),
      .drain_cmd_data_i         ('0),
      .drain_stream_valid_o     (drain_stream_valid_o),
      .drain_stream_ready_i     (1'b1),
      .drain_stream_data_o      (drain_stream_data_o),
      .buffer_event_valid_o     (buffer_event_valid_o),
      .buffer_event_ready_i     (1'b1),
      .buffer_event_data_o      (buffer_event_data_o),
      .viewport_valid_i         (1'b0),
      .viewport_ready_o         (viewport_ready_o),
      .viewport_data_i          ('0),
      .viewport_resp_valid_o    (viewport_resp_valid_o),
      .viewport_resp_ready_i    (1'b1),
      .viewport_resp_data_o     (viewport_resp_data_o),
      .line_state_o             (line_state_o),
      .vbus_state_o             (vbus_state_o),
      .id_ground_o              (id_ground_o),
      .link_ready_o             (link_ready_o),
      .frame_o                  (frame_o),
      .transaction_busy_o       (transaction_busy_o),
      .retry_o                  (retry_o),
      .protocol_error_o         (protocol_error_o),
      .ecc_corrected_count_o    (ecc_corrected_count_o),
      .ecc_uncorrectable_count_o(ecc_uncorrectable_count_o),
      .ulpi                     (ulpi)
  );

  initial begin
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (4) @(posedge clk_i);
    if (fill_cmd_ready_o || drain_cmd_ready_o || transaction_busy_o) begin
      $fatal(1, "USB2 disabled packet-store isolation failed");
    end
    fill_cmd_valid_i  = 1'b0;
    drain_cmd_valid_i = 1'b0;
    enable_i          = 1'b1;
    repeat (8) @(posedge clk_i);
    if (!link_ready_o || !ulpi.reset_n_o || ulpi.data_oe_o || ulpi.stp_o ||
        transaction_busy_o || result_valid_o || setup_valid_o || protocol_error_o ||
        (ecc_corrected_count_o != 32'd0) || (ecc_uncorrectable_count_o != 32'd0)) begin
      $fatal(1, "USB2 link domain idle smoke failed");
    end
    $display("USB2 link domain smoke passed");
    $finish;
  end
endmodule
