`timescale 1ns / 1ps

module usb2_transaction_engine_tb;
  logic                              clk_i = 1'b0;
  logic                              rst_n_i = 1'b0;
  usb2_pkg::usb2_role_e              active_role_i = usb2_pkg::Usb2RoleHost;
  logic                 [ 7:0][31:0] endpoint_cfg_i = '0;
  logic                              work_valid_i = 1'b0;
  logic                              work_ready_o;
  logic                 [63:0]       work_data_i = '0;
  logic                              result_valid_o;
  logic                 [63:0]       result_data_o;
  logic                              setup_valid_o;
  logic                 [63:0]       setup_data_o;
  logic                              tx_request_valid_o;
  logic                              tx_request_ready_i = 1'b1;
  logic                 [ 3:0]       tx_request_pid_o;
  logic                 [10:0]       tx_request_token_o;
  logic                 [10:0]       tx_request_length_o;
  logic                              tx_payload_valid_o;
  logic                              tx_payload_ready_i = 1'b1;
  logic                 [ 7:0]       tx_payload_data_o;
  logic                              tx_done_i = 1'b0;
  logic                              tx_error_i = 1'b0;
  logic                              rx_payload_valid_i = 1'b0;
  logic                 [ 7:0]       rx_payload_data_i = '0;
  logic                              rx_packet_done_i = 1'b0;
  logic                              rx_packet_good_i = 1'b0;
  logic                 [ 3:0]       rx_packet_pid_i = '0;
  logic                              store_rx_start_valid;
  logic                              store_rx_start_ready;
  logic                 [11:0]       store_rx_base;
  logic                 [14:0]       store_rx_limit;
  logic                              store_rx_valid;
  logic                              store_rx_ready;
  logic                 [ 7:0]       store_rx_data;
  logic                              store_rx_commit;
  logic                              store_rx_cancel;
  logic                              store_rx_done;
  logic                 [14:0]       store_rx_bytes;
  logic                              store_rx_overflow;
  logic                              store_tx_start_valid;
  logic                              store_tx_start_ready;
  logic                 [11:0]       store_tx_base;
  logic                 [14:0]       store_tx_bytes;
  logic                              store_tx_valid;
  logic                              store_tx_ready;
  logic                 [ 7:0]       store_tx_data;
  logic                              store_tx_done;
  logic                              fill_start_valid_i = 1'b0;
  logic                              fill_start_ready_o;
  logic                              fill_valid_i = 1'b0;
  logic                              fill_ready_o;
  logic                 [31:0]       fill_data_i = '0;
  logic                 [ 3:0]       fill_strb_i = '0;
  logic                              fill_last_i = 1'b0;
  logic                              fill_done_o;
  logic                              fill_error_o;
  logic                              busy_o;
  logic                              retry_o;
  logic                              protocol_error_o;
  logic                              pending_tx_q = 1'b0;
  logic                              pending_data_q = 1'b0;
  logic                              data_consumed_q = 1'b0;
  integer                            pid_count;
  logic                 [ 3:0]       observed_pid                           [0:3];

  always #5 clk_i = ~clk_i;

  always_ff @(posedge clk_i) begin
    tx_done_i        <= 1'b0;
    rx_packet_done_i <= 1'b0;
    rx_packet_good_i <= 1'b0;
    if (!rst_n_i) begin
      pending_tx_q    <= 1'b0;
      pending_data_q  <= 1'b0;
      data_consumed_q <= 1'b0;
      pid_count       <= 0;
    end else begin
      if (tx_request_valid_o && tx_request_ready_i) begin
        observed_pid[pid_count] <= tx_request_pid_o;
        pid_count               <= pid_count + 1;
        if (usb2_pkg::usb2_pid_is_data(tx_request_pid_o)) begin
          pending_data_q <= 1'b1;
        end else begin
          pending_tx_q <= 1'b1;
        end
      end
      if (pending_tx_q) begin
        tx_done_i    <= 1'b1;
        pending_tx_q <= 1'b0;
      end
      if (pending_data_q && tx_payload_valid_o && tx_payload_ready_i &&
          (tx_payload_data_o == 8'h55)) begin
        data_consumed_q <= 1'b1;
      end
      if (pending_data_q && data_consumed_q) begin
        tx_done_i       <= 1'b1;
        pending_data_q  <= 1'b0;
        data_consumed_q <= 1'b0;
      end
      if ((pid_count == 2) && !pending_data_q && !pending_tx_q && tx_done_i) begin
        rx_packet_pid_i  <= usb2_pkg::Usb2PidAck;
        rx_packet_done_i <= 1'b1;
        rx_packet_good_i <= 1'b1;
      end
    end
  end

  usb2_transaction_engine u_engine (
      .clk_i                 (clk_i),
      .rst_n_i               (rst_n_i),
      .active_role_i         (active_role_i),
      .device_addr_i         (7'd0),
      .endpoint_cfg_i        (endpoint_cfg_i),
      .timeout_i             (32'd1000),
      .work_valid_i          (work_valid_i),
      .work_ready_o          (work_ready_o),
      .work_data_i           (work_data_i),
      .result_valid_o        (result_valid_o),
      .result_ready_i        (1'b1),
      .result_data_o         (result_data_o),
      .setup_valid_o         (setup_valid_o),
      .setup_ready_i         (1'b1),
      .setup_data_o          (setup_data_o),
      .tx_request_valid_o    (tx_request_valid_o),
      .tx_request_ready_i    (tx_request_ready_i),
      .tx_request_pid_o      (tx_request_pid_o),
      .tx_request_token_o    (tx_request_token_o),
      .tx_request_length_o   (tx_request_length_o),
      .tx_payload_valid_o    (tx_payload_valid_o),
      .tx_payload_ready_i    (tx_payload_ready_i),
      .tx_payload_data_o     (tx_payload_data_o),
      .tx_done_i             (tx_done_i),
      .tx_error_i            (tx_error_i),
      .rx_payload_valid_i    (rx_payload_valid_i),
      .rx_payload_data_i     (rx_payload_data_i),
      .rx_packet_done_i      (rx_packet_done_i),
      .rx_packet_good_i      (rx_packet_good_i),
      .rx_packet_pid_i       (rx_packet_pid_i),
      .rx_token_addr_i       (7'd0),
      .rx_token_endpoint_i   (4'd0),
      .rx_payload_length_i   (11'd0),
      .store_rx_start_valid_o(store_rx_start_valid),
      .store_rx_start_ready_i(store_rx_start_ready),
      .store_rx_base_o       (store_rx_base),
      .store_rx_limit_o      (store_rx_limit),
      .store_rx_valid_o      (store_rx_valid),
      .store_rx_ready_i      (store_rx_ready),
      .store_rx_data_o       (store_rx_data),
      .store_rx_commit_o     (store_rx_commit),
      .store_rx_cancel_o     (store_rx_cancel),
      .store_rx_done_i       (store_rx_done),
      .store_rx_bytes_i      (store_rx_bytes),
      .store_rx_overflow_i   (store_rx_overflow),
      .store_tx_start_valid_o(store_tx_start_valid),
      .store_tx_start_ready_i(store_tx_start_ready),
      .store_tx_base_o       (store_tx_base),
      .store_tx_bytes_o      (store_tx_bytes),
      .store_tx_valid_i      (store_tx_valid),
      .store_tx_ready_o      (store_tx_ready),
      .store_tx_data_i       (store_tx_data),
      .store_tx_done_i       (store_tx_done),
      .busy_o                (busy_o),
      .retry_o               (retry_o),
      .protocol_error_o      (protocol_error_o)
  );

  usb2_packet_store u_store (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .fill_start_valid_i (fill_start_valid_i),
      .fill_start_ready_o (fill_start_ready_o),
      .fill_base_i        (12'd4),
      .fill_bytes_i       (15'd5),
      .fill_valid_i       (fill_valid_i),
      .fill_ready_o       (fill_ready_o),
      .fill_data_i        (fill_data_i),
      .fill_strb_i        (fill_strb_i),
      .fill_last_i        (fill_last_i),
      .fill_done_o        (fill_done_o),
      .fill_error_o       (fill_error_o),
      .drain_start_valid_i(1'b0),
      .drain_start_ready_o(),
      .drain_base_i       ('0),
      .drain_bytes_i      ('0),
      .drain_valid_o      (),
      .drain_ready_i      (1'b0),
      .drain_data_o       (),
      .drain_strb_o       (),
      .drain_last_o       (),
      .drain_done_o       (),
      .rx_start_valid_i   (store_rx_start_valid),
      .rx_start_ready_o   (store_rx_start_ready),
      .rx_base_i          (store_rx_base),
      .rx_limit_i         (store_rx_limit),
      .rx_valid_i         (store_rx_valid),
      .rx_ready_o         (store_rx_ready),
      .rx_data_i          (store_rx_data),
      .rx_commit_i        (store_rx_commit),
      .rx_cancel_i        (store_rx_cancel),
      .rx_done_o          (store_rx_done),
      .rx_bytes_o         (store_rx_bytes),
      .rx_overflow_o      (store_rx_overflow),
      .tx_start_valid_i   (store_tx_start_valid),
      .tx_start_ready_o   (store_tx_start_ready),
      .tx_base_i          (store_tx_base),
      .tx_bytes_i         (store_tx_bytes),
      .tx_valid_o         (store_tx_valid),
      .tx_ready_i         (store_tx_ready),
      .tx_data_o          (store_tx_data),
      .tx_done_o          (store_tx_done),
      .busy_o             (),
      .ecc_corrected_o    (),
      .ecc_uncorrectable_o()
  );

  initial begin
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    fill_start_valid_i = 1'b1;
    @(negedge clk_i);
    fill_start_valid_i = 1'b0;
    @(negedge clk_i);
    fill_data_i  = 32'h4433_2211;
    fill_strb_i  = 4'hF;
    fill_last_i  = 1'b0;
    fill_valid_i = 1'b1;
    @(negedge clk_i);
    fill_data_i = 32'h0000_0055;
    fill_strb_i = 4'h1;
    fill_last_i = 1'b1;
    @(negedge clk_i);
    fill_valid_i = 1'b0;
    wait (fill_done_o);
    if (fill_error_o) $fatal(1, "protocol test prefill failed");

    work_data_i                                       = '0;
    work_data_i[usb2_pkg::USB2_WORK_ROLE_LSB+:2]      = usb2_pkg::Usb2RoleHost;
    work_data_i[usb2_pkg::USB2_WORK_INDEX_LSB+:4]     = 4'd3;
    work_data_i[usb2_pkg::USB2_WORK_DIRECTION_IN]     = 1'b0;
    work_data_i[usb2_pkg::USB2_WORK_TYPE_LSB+:2]      = usb2_pkg::Usb2TransferBulk;
    work_data_i[usb2_pkg::USB2_WORK_ADDRESS_LSB+:7]   = 7'd5;
    work_data_i[usb2_pkg::USB2_WORK_ENDPOINT_LSB+:4]  = 4'd2;
    work_data_i[usb2_pkg::USB2_WORK_RAM_BASE_LSB+:12] = 12'd4;
    work_data_i[usb2_pkg::USB2_WORK_LENGTH_LSB+:15]   = 15'd5;
    @(negedge clk_i);
    work_valid_i = 1'b1;
    @(negedge clk_i);
    work_valid_i = 1'b0;
    wait (result_valid_o);
    if ((result_data_o[usb2_pkg::USB2_RESULT_CODE_LSB+:4] != usb2_pkg::Usb2ResultSuccess) ||
        (result_data_o[usb2_pkg::USB2_RESULT_INDEX_LSB+:4] != 4'd3) || (pid_count != 2) ||
        (observed_pid[0] != usb2_pkg::Usb2PidOut) ||
        (observed_pid[1] != usb2_pkg::Usb2PidData0) || retry_o || protocol_error_o) begin
      $fatal(1, "host OUT transaction failed result=%h pids=%h,%h", result_data_o, observed_pid[0],
             observed_pid[1]);
    end
    wait (work_ready_o);
    work_data_i[usb2_pkg::USB2_WORK_INDEX_LSB+:4] = 4'd4;
    work_data_i[usb2_pkg::USB2_WORK_TYPE_LSB+:2]  = usb2_pkg::Usb2TransferIsochronous;
    @(negedge clk_i);
    work_valid_i = 1'b1;
    @(negedge clk_i);
    work_valid_i = 1'b0;
    wait (result_valid_o);
    if ((result_data_o[usb2_pkg::USB2_RESULT_CODE_LSB+:4] != usb2_pkg::Usb2ResultSuccess) ||
        (result_data_o[usb2_pkg::USB2_RESULT_INDEX_LSB+:4] != 4'd4) || (pid_count != 4) ||
        (observed_pid[2] != usb2_pkg::Usb2PidOut) ||
        (observed_pid[3] != usb2_pkg::Usb2PidData0) || retry_o || protocol_error_o) begin
      $fatal(1, "host ISO OUT transaction waited for a handshake result=%h", result_data_o);
    end
    $display("USB2 transaction engine host OUT passed");
    $finish;
  end
endmodule
