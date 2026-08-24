`timescale 1ns / 1ps

module usb2_scheduler_tb;
  logic                s_clk = 1'b0;
  logic                s_rst_n = 1'b0;
  logic                s_reinitialize = 1'b0;
  logic   [13:0]       s_frame = 14'd0;
  logic   [ 7:0][31:0] s_endpoint_cfg = '0;
  logic   [ 7:0][31:0] s_endpoint_ram_in = '0;
  logic   [ 7:0][31:0] s_endpoint_ram_out = '0;
  logic   [ 7:0][31:0] s_endpoint_desc_in = '0;
  logic   [ 7:0][31:0] s_endpoint_desc_out = '0;
  logic   [ 7:0][31:0] s_endpoint_command = '0;
  logic   [15:0][31:0] s_channel_cfg = '0;
  logic   [15:0][31:0] s_channel_target = '0;
  logic   [15:0][31:0] s_channel_interval = '0;
  logic   [15:0][31:0] s_channel_ram = '0;
  logic   [15:0][31:0] s_channel_desc = '0;
  logic   [15:0][31:0] s_channel_command = '0;
  logic                s_work_valid;
  logic   [63:0]       s_work_data;
  logic                s_result_valid = 1'b0;
  logic   [63:0]       s_result_data = '0;
  logic                s_fill_ready = 1'b0;
  logic                s_dma_start;
  logic                s_dma_done = 1'b0;
  logic                s_buffer_event_valid = 1'b0;
  logic   [ 2:0]       s_buffer_event_data = 3'd0;
  logic                s_busy;
  logic   [ 3:0]       s_seen_index                [0:3];
  integer              s_work_count = 0;

  always #5 s_clk = ~s_clk;

  always_ff @(posedge s_clk) begin
    s_dma_done           <= 1'b0;
    s_buffer_event_valid <= 1'b0;
    s_result_valid       <= 1'b0;
    if (s_dma_start) begin
      s_dma_done           <= 1'b1;
      s_buffer_event_valid <= 1'b1;
    end
    if (s_work_valid) begin
      s_seen_index[s_work_count] <= s_work_data[usb2_pkg::USB2_WORK_INDEX_LSB+:4];
      s_work_count <= s_work_count + 1;
      s_result_data <= 64'd0;
      s_result_data[usb2_pkg::USB2_RESULT_ROLE_LSB+:2] <= usb2_pkg::Usb2RoleHost;
      s_result_data[usb2_pkg::USB2_RESULT_INDEX_LSB+:4] <=
          s_work_data[usb2_pkg::USB2_WORK_INDEX_LSB+:4];
      s_result_data[usb2_pkg::USB2_RESULT_LENGTH_LSB+:15] <= 15'd4;
      s_result_valid <= 1'b1;
    end
  end

  usb2_scheduler u_scheduler (
      .clk_i                        (s_clk),
      .rst_n_i                      (s_rst_n),
      .enable_i                     (1'b1),
      .abort_i                      (1'b0),
      .reinitialize_i               (s_reinitialize),
      .perf_clear_i                 (1'b0),
      .high_speed_i                 (1'b1),
      .frame_i                      (s_frame),
      .active_role_i                (usb2_pkg::Usb2RoleHost),
      .endpoint_cfg_i               (s_endpoint_cfg),
      .endpoint_ram_in_i            (s_endpoint_ram_in),
      .endpoint_ram_out_i           (s_endpoint_ram_out),
      .endpoint_desc_in_i           (s_endpoint_desc_in),
      .endpoint_desc_out_i          (s_endpoint_desc_out),
      .endpoint_command_i           (s_endpoint_command),
      .endpoint_complete_clear_in_i (32'd0),
      .endpoint_complete_clear_out_i(32'd0),
      .channel_cfg_i                (s_channel_cfg),
      .channel_target_i             (s_channel_target),
      .channel_interval_i           (s_channel_interval),
      .channel_ram_i                (s_channel_ram),
      .channel_desc_i               (s_channel_desc),
      .channel_command_i            (s_channel_command),
      .work_valid_o                 (s_work_valid),
      .work_ready_i                 (1'b1),
      .work_data_o                  (s_work_data),
      .result_valid_i               (s_result_valid),
      .result_ready_o               (),
      .result_data_i                (s_result_data),
      .fill_cmd_valid_o             (),
      .fill_cmd_ready_i             (s_fill_ready),
      .fill_cmd_data_o              (),
      .drain_cmd_valid_o            (),
      .drain_cmd_ready_i            (1'b1),
      .drain_cmd_data_o             (),
      .buffer_event_valid_i         (s_buffer_event_valid),
      .buffer_event_ready_o         (),
      .buffer_event_data_i          (s_buffer_event_data),
      .dma_start_o                  (s_dma_start),
      .dma_abort_o                  (),
      .dma_memory_to_packet_o       (),
      .dma_desc_base_o              (),
      .dma_transfer_bytes_o         (),
      .dma_busy_i                   (1'b0),
      .dma_done_i                   (s_dma_done),
      .dma_error_i                  (1'b0),
      .dma_error_code_i             (8'd0),
      .dma_current_desc_i           (32'd0),
      .dma_bytes_done_i             (32'd4),
      .retry_i                      (1'b0),
      .endpoint_pending_in_o        (),
      .endpoint_pending_out_o       (),
      .endpoint_complete_in_o       (),
      .endpoint_complete_out_o      (),
      .endpoint_status_o            (),
      .endpoint_bytes_in_o          (),
      .endpoint_bytes_out_o         (),
      .channel_status_o             (),
      .channel_bytes_o              (),
      .irq_event_o                  (),
      .error_capture_o              (),
      .error_status_o               (),
      .error_code_o                 (),
      .error_info_o                 (),
      .error_desc_addr_o            (),
      .error_buffer_addr_o          (),
      .perf_tx_bytes_o              (),
      .perf_rx_bytes_o              (),
      .perf_packets_o               (),
      .perf_retries_o               (),
      .perf_irq_count_o             (),
      .busy_o                       (s_busy)
  );

  task automatic issue_channel(input int channel_i);
    begin
      @(negedge s_clk);
      s_channel_command[channel_i] = 32'd1;
      @(negedge s_clk);
      s_channel_command[channel_i] = 32'd0;
    end
  endtask

  initial begin
    for (int channel = 0; channel < 16; channel++) begin
      s_channel_cfg[channel]  = 32'h0040_0009;
      s_channel_ram[channel]  = 32'h0004_0000;
      s_channel_desc[channel] = 32'h4000_0000 + (32'(channel) << 5);
    end
    s_channel_cfg[3][3:2] = usb2_pkg::Usb2TransferInterrupt;
    s_channel_interval[3] = 32'd8;

    repeat (4) @(posedge s_clk);
    s_rst_n = 1'b1;

    issue_channel(1);
    wait (s_busy);
    issue_channel(2);
    repeat (2) @(posedge s_clk);
    s_fill_ready = 1'b1;
    wait (s_work_count == 2);
    wait (!s_busy);
    if ((s_seen_index[0] != 4'd1) || (s_seen_index[1] != 4'd2)) begin
      $fatal(1, "USB2 busy command queue dropped or reordered work");
    end

    issue_channel(3);
    wait (s_work_count == 3);
    wait (!s_busy);
    s_frame = 14'd1;
    issue_channel(3);
    repeat (8) @(posedge s_clk);
    if (s_work_count != 3) $fatal(1, "USB2 periodic command ran before its interval");
    s_frame = 14'd8;
    wait (s_work_count == 4);
    if (s_seen_index[3] != 4'd3) $fatal(1, "USB2 periodic command was not retained");

    @(negedge s_clk);
    s_reinitialize = 1'b1;
    @(negedge s_clk);
    s_reinitialize = 1'b0;
    $display("USB2 scheduler queue and interval passed");
    $finish;
  end
endmodule
