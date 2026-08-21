// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module usb2_sie_tb;
  logic        s_clk;
  logic        s_rst_n;
  logic        s_rx_start;
  logic        s_rx_valid;
  logic [ 7:0] s_rx_data;
  logic        s_rx_end;
  logic        s_rx_error;
  logic        s_payload_valid;
  logic [ 7:0] s_payload_data;
  logic        s_packet_done;
  logic        s_packet_good;
  logic [ 3:0] s_packet_pid;
  logic [ 6:0] s_token_addr;
  logic [ 3:0] s_token_endpoint;
  logic [10:0] s_payload_length;
  logic        s_crc_error;

  logic        s_request_valid;
  logic        s_request_ready;
  logic [ 3:0] s_request_pid;
  logic [10:0] s_request_token;
  logic [10:0] s_request_length;
  logic        s_link_start_valid;
  logic        s_link_start_ready;
  logic [ 3:0] s_link_pid;
  logic        s_link_has_data;
  logic        s_link_data_valid;
  logic        s_link_data_ready;
  logic [ 7:0] s_link_data;
  logic        s_link_data_last;
  logic        s_link_done;
  logic        s_tx_done;
  logic [ 7:0] s_payload_seen       [0:1];
  logic [ 1:0] s_payload_seen_count;
  logic [ 7:0] s_tx_seen            [0:1];
  logic [ 1:0] s_tx_seen_count;

  usb2_sie_rx u_rx (
      .clk_i           (s_clk),
      .rst_n_i         (s_rst_n),
      .rx_start_i      (s_rx_start),
      .rx_valid_i      (s_rx_valid),
      .rx_data_i       (s_rx_data),
      .rx_end_i        (s_rx_end),
      .rx_error_i      (s_rx_error),
      .payload_valid_o (s_payload_valid),
      .payload_data_o  (s_payload_data),
      .packet_done_o   (s_packet_done),
      .packet_good_o   (s_packet_good),
      .packet_pid_o    (s_packet_pid),
      .token_addr_o    (s_token_addr),
      .token_endpoint_o(s_token_endpoint),
      .frame_number_o  (),
      .payload_length_o(s_payload_length),
      .pid_error_o     (),
      .crc_error_o     (s_crc_error),
      .framing_error_o ()
  );

  usb2_sie_tx u_tx (
      .clk_i             (s_clk),
      .rst_n_i           (s_rst_n),
      .request_valid_i   (s_request_valid),
      .request_ready_o   (s_request_ready),
      .request_pid_i     (s_request_pid),
      .request_token_i   (s_request_token),
      .request_length_i  (s_request_length),
      .payload_valid_i   (1'b0),
      .payload_ready_o   (),
      .payload_data_i    (8'd0),
      .link_start_valid_o(s_link_start_valid),
      .link_start_ready_i(s_link_start_ready),
      .link_pid_o        (s_link_pid),
      .link_has_data_o   (s_link_has_data),
      .link_data_valid_o (s_link_data_valid),
      .link_data_ready_i (s_link_data_ready),
      .link_data_o       (s_link_data),
      .link_data_last_o  (s_link_data_last),
      .link_done_i       (s_link_done),
      .link_error_i      (1'b0),
      .busy_o            (),
      .done_o            (s_tx_done),
      .error_o           ()
  );

  always #5 s_clk = ~s_clk;

  always_ff @(posedge s_clk) begin
    if (s_payload_valid) begin
      s_payload_seen[s_payload_seen_count] <= s_payload_data;
      s_payload_seen_count                 <= s_payload_seen_count + 1'b1;
    end
    if (s_link_data_valid && s_link_data_ready) begin
      s_tx_seen[s_tx_seen_count] <= s_link_data;
      s_tx_seen_count            <= s_tx_seen_count + 1'b1;
    end
  end

  task automatic rx_begin;
    begin
      @(negedge s_clk);
      s_rx_start = 1'b1;
      @(negedge s_clk);
      s_rx_start = 1'b0;
    end
  endtask

  task automatic rx_byte(input logic [7:0] data_i);
    begin
      s_rx_data  = data_i;
      s_rx_valid = 1'b1;
      @(negedge s_clk);
      s_rx_valid = 1'b0;
      @(negedge s_clk);
    end
  endtask

  task automatic rx_finish;
    begin
      s_rx_end = 1'b1;
      @(posedge s_clk);
      #1;
      s_rx_end = 1'b0;
    end
  endtask

  initial begin
    logic [15:0] data_crc;
    s_clk                = 1'b0;
    s_rst_n              = 1'b0;
    s_rx_start           = 1'b0;
    s_rx_valid           = 1'b0;
    s_rx_data            = 8'd0;
    s_rx_end             = 1'b0;
    s_rx_error           = 1'b0;
    s_request_valid      = 1'b0;
    s_request_pid        = usb2_pkg::Usb2PidOut;
    s_request_token      = 11'd0;
    s_request_length     = 11'd0;
    s_link_start_ready   = 1'b1;
    s_link_data_ready    = 1'b1;
    s_link_done          = 1'b0;
    s_payload_seen_count = '0;
    s_tx_seen_count      = '0;
    repeat (2) @(negedge s_clk);
    s_rst_n = 1'b1;

    rx_begin();
    rx_byte(usb2_pkg::usb2_pid_byte(usb2_pkg::Usb2PidOut));
    rx_byte(8'h01);
    rx_byte(8'hE8);
    rx_finish();
    if (!s_packet_done || !s_packet_good || (s_packet_pid != usb2_pkg::Usb2PidOut) ||
        (s_token_addr != 7'd1) || (s_token_endpoint != 4'd0)) begin
      $fatal(1, "USB2 token packet decode failed");
    end

    data_crc = usb2_pkg::usb2_crc16_byte(16'hFFFF, 8'h41);
    data_crc = usb2_pkg::usb2_crc16_byte(data_crc, 8'h42);
    data_crc = usb2_pkg::usb2_crc16_finish(data_crc);
    rx_begin();
    rx_byte(usb2_pkg::usb2_pid_byte(usb2_pkg::Usb2PidData0));
    rx_byte(8'h41);
    rx_byte(8'h42);
    rx_byte(data_crc[7:0]);
    rx_byte(data_crc[15:8]);
    rx_finish();
    if (!s_packet_done || !s_packet_good || (s_payload_length != 11'd2) ||
        (s_payload_seen_count != 2'd2) || (s_payload_seen[0] != 8'h41) ||
        (s_payload_seen[1] != 8'h42)) begin
      $fatal(1, "USB2 data packet decode failed");
    end

    rx_begin();
    rx_byte(usb2_pkg::usb2_pid_byte(usb2_pkg::Usb2PidData0));
    rx_byte(8'h01);
    rx_byte(8'h00);
    rx_finish();
    if (!s_packet_done || s_packet_good || !s_crc_error) begin
      $fatal(1, "USB2 bad data CRC accepted");
    end

    @(negedge s_clk);
    s_request_pid   = usb2_pkg::Usb2PidOut;
    s_request_token = 11'd1;
    s_request_valid = 1'b1;
    @(negedge s_clk);
    s_request_valid = 1'b0;
    wait (s_link_data_last);
    @(negedge s_clk);
    s_link_done = 1'b1;
    @(posedge s_clk);
    @(posedge s_clk);
    #1;
    s_link_done = 1'b0;
    if (!s_tx_done || (s_link_pid != usb2_pkg::Usb2PidOut) || !s_link_has_data ||
        (s_tx_seen_count != 2'd2) || (s_tx_seen[0] != 8'h01) || (s_tx_seen[1] != 8'hE8)) begin
      $fatal(1, "USB2 token packet encode failed");
    end

    $display("USB2 SIE packet encode/decode passed");
    $finish;
  end
endmodule
