// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module usb2_link_domain #(
    parameter int NumEndpoints = 8
) (
    // verilog_format: off -- preserve control, CDC mailbox, stream, and status groups
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 enable_i,
    input  logic                 phy_reset_n_i,
    input  logic                 high_speed_i,
    input  usb2_pkg::usb2_role_e active_role_i,
    input  logic [6:0]           device_addr_i,
    input  logic [NumEndpoints-1:0][31:0] endpoint_cfg_i,
    input  logic [31:0]          timeout_i,
    input  logic                 work_valid_i,
    output logic                 work_ready_o,
    input  logic [63:0]          work_data_i,
    output logic                 result_valid_o,
    input  logic                 result_ready_i,
    output logic [63:0]          result_data_o,
    output logic                 setup_valid_o,
    input  logic                 setup_ready_i,
    output logic [63:0]          setup_data_o,
    input  logic                 fill_cmd_valid_i,
    output logic                 fill_cmd_ready_o,
    input  logic [26:0]          fill_cmd_data_i,
    input  logic                 fill_stream_valid_i,
    output logic                 fill_stream_ready_o,
    input  logic [36:0]          fill_stream_data_i,
    input  logic                 drain_cmd_valid_i,
    output logic                 drain_cmd_ready_o,
    input  logic [26:0]          drain_cmd_data_i,
    output logic                 drain_stream_valid_o,
    input  logic                 drain_stream_ready_i,
    output logic [36:0]          drain_stream_data_o,
    output logic                 buffer_event_valid_o,
    input  logic                 buffer_event_ready_i,
    output logic [2:0]           buffer_event_data_o,
    input  logic                 viewport_valid_i,
    output logic                 viewport_ready_o,
    input  logic [14:0]          viewport_data_i,
    output logic                 viewport_resp_valid_o,
    input  logic                 viewport_resp_ready_i,
    output logic [8:0]           viewport_resp_data_o,
    output logic [1:0]           line_state_o,
    output logic [1:0]           vbus_state_o,
    output logic                 id_ground_o,
    output logic                 link_ready_o,
    output logic [13:0]          frame_o,
    output logic                 transaction_busy_o,
    output logic                 retry_o,
    output logic                 protocol_error_o,
    output logic [31:0]          ecc_corrected_count_o,
    output logic [31:0]          ecc_uncorrectable_count_o,
    usb2_ulpi_if.dut             ulpi
    // verilog_format: on
);
  localparam logic [15:0] HighSpeedMicroframeCycles = 16'd7500;
  localparam logic [15:0] FullSpeedFrameCycles = 16'd60000;

  logic        s_link_rx_start;
  logic        s_link_rx_valid;
  logic [ 7:0] s_link_rx_data;
  logic        s_link_rx_end;
  logic        s_link_rx_err;
  logic        s_link_tx_start_valid;
  logic        s_link_tx_start_ready;
  logic [ 3:0] s_link_tx_pid;
  logic        s_link_tx_has_data;
  logic        s_link_tx_data_valid;
  logic        s_link_tx_data_ready;
  logic [ 7:0] s_link_tx_data;
  logic        s_link_tx_data_last;
  logic        s_link_tx_done;
  logic        s_link_tx_err;

  logic        s_rx_payload_valid;
  logic [ 7:0] s_rx_payload_data;
  logic        s_rx_packet_done;
  logic        s_rx_packet_good;
  logic [ 3:0] s_rx_packet_pid;
  logic [ 6:0] s_rx_token_addr;
  logic [ 3:0] s_rx_token_endpoint;
  logic [10:0] s_rx_frame_number;
  logic [10:0] s_rx_payload_len;
  logic        s_rx_pid_err;
  logic        s_rx_crc_err;
  logic        s_rx_framing_err;

  logic        s_engine_tx_req_valid;
  logic        s_engine_tx_req_ready;
  logic [ 3:0] s_engine_tx_req_pid;
  logic [10:0] s_engine_tx_req_token;
  logic [10:0] s_engine_tx_req_len;
  logic        s_engine_tx_payload_valid;
  logic        s_engine_tx_payload_ready;
  logic        s_sie_tx_payload_ready;
  logic [ 7:0] s_engine_tx_payload_data;
  logic        s_engine_tx_done;
  logic        s_engine_tx_err;
  logic        s_sie_tx_req_valid;
  logic        s_sie_tx_req_ready;
  logic [ 3:0] s_sie_tx_req_pid;
  logic [10:0] s_sie_tx_req_token;
  logic [10:0] s_sie_tx_req_len;
  logic        s_sie_tx_busy;
  logic        s_sie_tx_done;
  logic        s_sie_tx_err;
  logic        s_transaction_busy;
  logic        s_engine_protocol_err;

  logic        s_store_rx_start_valid;
  logic        s_store_rx_start_ready;
  logic [11:0] s_store_rx_base;
  logic [14:0] s_store_rx_limit;
  logic        s_store_rx_valid;
  logic        s_store_rx_ready;
  logic [ 7:0] s_store_rx_data;
  logic        s_store_rx_commit;
  logic        s_store_rx_cancel;
  logic        s_store_rx_done;
  logic [14:0] s_store_rx_bytes;
  logic        s_store_rx_overflow;
  logic        s_store_tx_start_valid;
  logic        s_store_tx_start_ready;
  logic [11:0] s_store_tx_base;
  logic [14:0] s_store_tx_bytes;
  logic        s_store_tx_valid;
  logic        s_store_tx_ready;
  logic [ 7:0] s_store_tx_data;
  logic        s_store_tx_done;
  logic        s_store_busy;
  logic        s_store_clients_enabled;
  logic        s_store_fill_start_ready;
  logic        s_store_drain_start_ready;
  logic        s_store_rx_start_ready_raw;
  logic        s_store_tx_start_ready_raw;
  logic        s_fill_done;
  logic        s_fill_err;
  logic        s_drain_done;
  logic        s_ecc_corrected;
  logic        s_ecc_uncorrectable;

  logic [15:0] s_frame_count_d, s_frame_count_q;
  logic [13:0] s_frame_d, s_frame_q;
  logic s_sof_pending_d, s_sof_pending_q;
  logic s_tx_owner_engine_d, s_tx_owner_engine_q;
  logic s_buffer_event_valid_d, s_buffer_event_valid_q;
  logic [2:0] s_buffer_event_data_d, s_buffer_event_data_q;
  logic s_view_resp_valid_d, s_view_resp_valid_q;
  logic [8:0] s_view_resp_data_d, s_view_resp_data_q;
  logic [31:0] s_ecc_corrected_count_d, s_ecc_corrected_count_q;
  logic [31:0] s_ecc_uncorrectable_count_d, s_ecc_uncorrectable_count_q;
  logic [15:0] s_frame_period;
  logic        s_frame_tick;
  logic        s_sof_selected;
  logic        s_link_view_resp_valid;
  logic [ 7:0] s_link_view_read_data;
  logic        s_link_view_err;

  assign s_frame_period = high_speed_i ? HighSpeedMicroframeCycles : FullSpeedFrameCycles;
  assign s_frame_tick = s_frame_count_q == (s_frame_period - 1'b1);
  assign s_sof_selected = s_sof_pending_q && !transaction_busy_o && !s_engine_tx_req_valid;
  assign s_sie_tx_req_valid = s_engine_tx_req_valid || s_sof_selected;
  assign s_sie_tx_req_pid = s_sof_selected ? usb2_pkg::Usb2PidSof : s_engine_tx_req_pid;
  assign s_sie_tx_req_token = s_sof_selected ? s_frame_q[13:3] : s_engine_tx_req_token;
  assign s_sie_tx_req_len = s_sof_selected ? 11'd0 : s_engine_tx_req_len;
  assign s_engine_tx_req_ready = s_sie_tx_req_ready && !s_sof_selected;
  assign s_engine_tx_payload_ready = s_tx_owner_engine_q && s_sie_tx_payload_ready;
  assign s_engine_tx_done = s_sie_tx_done && s_tx_owner_engine_q;
  assign s_engine_tx_err = s_sie_tx_err && s_tx_owner_engine_q;
  assign s_store_clients_enabled = enable_i && phy_reset_n_i;
  assign fill_cmd_ready_o = s_store_clients_enabled && s_store_fill_start_ready;
  assign drain_cmd_ready_o = s_store_clients_enabled && s_store_drain_start_ready;
  assign s_store_rx_start_ready = s_store_clients_enabled && s_store_rx_start_ready_raw;
  assign s_store_tx_start_ready = s_store_clients_enabled && s_store_tx_start_ready_raw;

  assign buffer_event_valid_o = s_buffer_event_valid_q;
  assign buffer_event_data_o = s_buffer_event_data_q;
  assign viewport_resp_valid_o = s_view_resp_valid_q;
  assign viewport_resp_data_o = s_view_resp_data_q;
  assign frame_o = s_frame_q;
  assign transaction_busy_o = s_transaction_busy || s_store_busy || s_sie_tx_busy;
  assign protocol_error_o = s_engine_protocol_err || s_rx_pid_err || s_rx_crc_err ||
                            s_rx_framing_err;
  assign ecc_corrected_count_o = s_ecc_corrected_count_q;
  assign ecc_uncorrectable_count_o = s_ecc_uncorrectable_count_q;

  always_comb begin
    s_frame_count_d             = s_frame_count_q;
    s_frame_d                   = s_frame_q;
    s_sof_pending_d             = s_sof_pending_q;
    s_tx_owner_engine_d         = s_tx_owner_engine_q;
    s_buffer_event_valid_d      = s_buffer_event_valid_q && !buffer_event_ready_i;
    s_buffer_event_data_d       = s_buffer_event_data_q;
    s_view_resp_valid_d         = s_view_resp_valid_q && !viewport_resp_ready_i;
    s_view_resp_data_d          = s_view_resp_data_q;
    s_ecc_corrected_count_d     = s_ecc_corrected_count_q;
    s_ecc_uncorrectable_count_d = s_ecc_uncorrectable_count_q;

    if ((active_role_i == usb2_pkg::Usb2RoleHost) && enable_i && phy_reset_n_i) begin
      if (s_frame_tick) begin
        s_frame_count_d = 16'd0;
        if (high_speed_i) begin
          s_frame_d = s_frame_q + 1'b1;
        end else begin
          s_frame_d = {s_frame_q[10:0] + 1'b1, 3'd0};
        end
        s_sof_pending_d = 1'b1;
      end else begin
        s_frame_count_d = s_frame_count_q + 1'b1;
      end
    end else if ((active_role_i == usb2_pkg::Usb2RoleDevice) && enable_i && phy_reset_n_i) begin
      s_frame_count_d = 16'd0;
      s_sof_pending_d = 1'b0;
      if (s_rx_packet_done && s_rx_packet_good && (s_rx_packet_pid == usb2_pkg::Usb2PidSof)) begin
        s_frame_d = {s_rx_frame_number, 3'd0};
      end
    end else begin
      s_frame_count_d = 16'd0;
      s_frame_d       = 14'd0;
      s_sof_pending_d = 1'b0;
    end

    if (s_sie_tx_req_valid && s_sie_tx_req_ready) begin
      s_tx_owner_engine_d = !s_sof_selected;
      if (s_sof_selected) begin
        s_sof_pending_d = 1'b0;
      end
    end
    if (s_sie_tx_done || s_sie_tx_err) begin
      s_tx_owner_engine_d = 1'b0;
    end

    if (s_fill_done) begin
      s_buffer_event_valid_d = 1'b1;
      s_buffer_event_data_d  = {s_fill_err, 2'd0};
    end else if (s_drain_done) begin
      s_buffer_event_valid_d = 1'b1;
      s_buffer_event_data_d  = 3'b001;
    end
    if (s_link_view_resp_valid) begin
      s_view_resp_valid_d = 1'b1;
      s_view_resp_data_d  = {s_link_view_err, s_link_view_read_data};
    end
    if (s_ecc_corrected && !(&s_ecc_corrected_count_q)) begin
      s_ecc_corrected_count_d = s_ecc_corrected_count_q + 1'b1;
    end
    if (s_ecc_uncorrectable && !(&s_ecc_uncorrectable_count_q)) begin
      s_ecc_uncorrectable_count_d = s_ecc_uncorrectable_count_q + 1'b1;
    end
  end

  usb2_ulpi_link u_ulpi_link (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .enable_i             (enable_i),
      .phy_reset_n_i        (phy_reset_n_i),
      .tx_start_valid_i     (s_link_tx_start_valid),
      .tx_start_ready_o     (s_link_tx_start_ready),
      .tx_pid_i             (s_link_tx_pid),
      .tx_has_data_i        (s_link_tx_has_data),
      .tx_data_valid_i      (s_link_tx_data_valid),
      .tx_data_ready_o      (s_link_tx_data_ready),
      .tx_data_i            (s_link_tx_data),
      .tx_data_last_i       (s_link_tx_data_last),
      .tx_done_o            (s_link_tx_done),
      .tx_error_o           (s_link_tx_err),
      .rx_start_o           (s_link_rx_start),
      .rx_valid_o           (s_link_rx_valid),
      .rx_data_o            (s_link_rx_data),
      .rx_end_o             (s_link_rx_end),
      .rx_error_o           (s_link_rx_err),
      .line_state_o         (line_state_o),
      .vbus_state_o         (vbus_state_o),
      .id_ground_o          (id_ground_o),
      .viewport_valid_i     (viewport_valid_i),
      .viewport_ready_o     (viewport_ready_o),
      .viewport_write_i     (viewport_data_i[14]),
      .viewport_addr_i      (viewport_data_i[13:8]),
      .viewport_write_data_i(viewport_data_i[7:0]),
      .viewport_resp_valid_o(s_link_view_resp_valid),
      .viewport_read_data_o (s_link_view_read_data),
      .viewport_error_o     (s_link_view_err),
      .link_ready_o         (link_ready_o),
      .ulpi                 (ulpi)
  );

  usb2_sie_rx u_sie_rx (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .rx_start_i      (s_link_rx_start),
      .rx_valid_i      (s_link_rx_valid),
      .rx_data_i       (s_link_rx_data),
      .rx_end_i        (s_link_rx_end),
      .rx_error_i      (s_link_rx_err),
      .payload_valid_o (s_rx_payload_valid),
      .payload_data_o  (s_rx_payload_data),
      .packet_done_o   (s_rx_packet_done),
      .packet_good_o   (s_rx_packet_good),
      .packet_pid_o    (s_rx_packet_pid),
      .token_addr_o    (s_rx_token_addr),
      .token_endpoint_o(s_rx_token_endpoint),
      .frame_number_o  (s_rx_frame_number),
      .payload_length_o(s_rx_payload_len),
      .pid_error_o     (s_rx_pid_err),
      .crc_error_o     (s_rx_crc_err),
      .framing_error_o (s_rx_framing_err)
  );

  usb2_sie_tx u_sie_tx (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .request_valid_i   (s_sie_tx_req_valid),
      .request_ready_o   (s_sie_tx_req_ready),
      .request_pid_i     (s_sie_tx_req_pid),
      .request_token_i   (s_sie_tx_req_token),
      .request_length_i  (s_sie_tx_req_len),
      .payload_valid_i   (s_engine_tx_payload_valid),
      .payload_ready_o   (s_sie_tx_payload_ready),
      .payload_data_i    (s_engine_tx_payload_data),
      .link_start_valid_o(s_link_tx_start_valid),
      .link_start_ready_i(s_link_tx_start_ready),
      .link_pid_o        (s_link_tx_pid),
      .link_has_data_o   (s_link_tx_has_data),
      .link_data_valid_o (s_link_tx_data_valid),
      .link_data_ready_i (s_link_tx_data_ready),
      .link_data_o       (s_link_tx_data),
      .link_data_last_o  (s_link_tx_data_last),
      .link_done_i       (s_link_tx_done),
      .link_error_i      (s_link_tx_err),
      .busy_o            (s_sie_tx_busy),
      .done_o            (s_sie_tx_done),
      .error_o           (s_sie_tx_err)
  );

  usb2_transaction_engine #(
      .NumEndpoints(NumEndpoints)
  ) u_transaction_engine (
      .clk_i                 (clk_i),
      .rst_n_i               (rst_n_i),
      .active_role_i         (active_role_i),
      .device_addr_i         (device_addr_i),
      .endpoint_cfg_i        (endpoint_cfg_i),
      .timeout_i             (timeout_i),
      .work_valid_i          (work_valid_i),
      .work_ready_o          (work_ready_o),
      .work_data_i           (work_data_i),
      .result_valid_o        (result_valid_o),
      .result_ready_i        (result_ready_i),
      .result_data_o         (result_data_o),
      .setup_valid_o         (setup_valid_o),
      .setup_ready_i         (setup_ready_i),
      .setup_data_o          (setup_data_o),
      .tx_request_valid_o    (s_engine_tx_req_valid),
      .tx_request_ready_i    (s_engine_tx_req_ready),
      .tx_request_pid_o      (s_engine_tx_req_pid),
      .tx_request_token_o    (s_engine_tx_req_token),
      .tx_request_length_o   (s_engine_tx_req_len),
      .tx_payload_valid_o    (s_engine_tx_payload_valid),
      .tx_payload_ready_i    (s_engine_tx_payload_ready),
      .tx_payload_data_o     (s_engine_tx_payload_data),
      .tx_done_i             (s_engine_tx_done),
      .tx_error_i            (s_engine_tx_err),
      .rx_payload_valid_i    (s_rx_payload_valid),
      .rx_payload_data_i     (s_rx_payload_data),
      .rx_packet_done_i      (s_rx_packet_done),
      .rx_packet_good_i      (s_rx_packet_good),
      .rx_packet_pid_i       (s_rx_packet_pid),
      .rx_token_addr_i       (s_rx_token_addr),
      .rx_token_endpoint_i   (s_rx_token_endpoint),
      .rx_payload_length_i   (s_rx_payload_len),
      .store_rx_start_valid_o(s_store_rx_start_valid),
      .store_rx_start_ready_i(s_store_rx_start_ready),
      .store_rx_base_o       (s_store_rx_base),
      .store_rx_limit_o      (s_store_rx_limit),
      .store_rx_valid_o      (s_store_rx_valid),
      .store_rx_ready_i      (s_store_rx_ready),
      .store_rx_data_o       (s_store_rx_data),
      .store_rx_commit_o     (s_store_rx_commit),
      .store_rx_cancel_o     (s_store_rx_cancel),
      .store_rx_done_i       (s_store_rx_done),
      .store_rx_bytes_i      (s_store_rx_bytes),
      .store_rx_overflow_i   (s_store_rx_overflow),
      .store_tx_start_valid_o(s_store_tx_start_valid),
      .store_tx_start_ready_i(s_store_tx_start_ready),
      .store_tx_base_o       (s_store_tx_base),
      .store_tx_bytes_o      (s_store_tx_bytes),
      .store_tx_valid_i      (s_store_tx_valid),
      .store_tx_ready_o      (s_store_tx_ready),
      .store_tx_data_i       (s_store_tx_data),
      .store_tx_done_i       (s_store_tx_done),
      .busy_o                (s_transaction_busy),
      .retry_o               (retry_o),
      .protocol_error_o      (s_engine_protocol_err)
  );

  usb2_packet_store u_packet_store (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .fill_start_valid_i (fill_cmd_valid_i && s_store_clients_enabled),
      .fill_start_ready_o (s_store_fill_start_ready),
      .fill_base_i        (fill_cmd_data_i[11:0]),
      .fill_bytes_i       (fill_cmd_data_i[26:12]),
      .fill_valid_i       (fill_stream_valid_i),
      .fill_ready_o       (fill_stream_ready_o),
      .fill_data_i        (fill_stream_data_i[31:0]),
      .fill_strb_i        (fill_stream_data_i[35:32]),
      .fill_last_i        (fill_stream_data_i[36]),
      .fill_done_o        (s_fill_done),
      .fill_error_o       (s_fill_err),
      .drain_start_valid_i(drain_cmd_valid_i && s_store_clients_enabled),
      .drain_start_ready_o(s_store_drain_start_ready),
      .drain_base_i       (drain_cmd_data_i[11:0]),
      .drain_bytes_i      (drain_cmd_data_i[26:12]),
      .drain_valid_o      (drain_stream_valid_o),
      .drain_ready_i      (drain_stream_ready_i),
      .drain_data_o       (drain_stream_data_o[31:0]),
      .drain_strb_o       (drain_stream_data_o[35:32]),
      .drain_last_o       (drain_stream_data_o[36]),
      .drain_done_o       (s_drain_done),
      .rx_start_valid_i   (s_store_rx_start_valid && s_store_clients_enabled),
      .rx_start_ready_o   (s_store_rx_start_ready_raw),
      .rx_base_i          (s_store_rx_base),
      .rx_limit_i         (s_store_rx_limit),
      .rx_valid_i         (s_store_rx_valid),
      .rx_ready_o         (s_store_rx_ready),
      .rx_data_i          (s_store_rx_data),
      .rx_commit_i        (s_store_rx_commit),
      .rx_cancel_i        (s_store_rx_cancel),
      .rx_done_o          (s_store_rx_done),
      .rx_bytes_o         (s_store_rx_bytes),
      .rx_overflow_o      (s_store_rx_overflow),
      .tx_start_valid_i   (s_store_tx_start_valid && s_store_clients_enabled),
      .tx_start_ready_o   (s_store_tx_start_ready_raw),
      .tx_base_i          (s_store_tx_base),
      .tx_bytes_i         (s_store_tx_bytes),
      .tx_valid_o         (s_store_tx_valid),
      .tx_ready_i         (s_store_tx_ready),
      .tx_data_o          (s_store_tx_data),
      .tx_done_o          (s_store_tx_done),
      .busy_o             (s_store_busy),
      .ecc_corrected_o    (s_ecc_corrected),
      .ecc_uncorrectable_o(s_ecc_uncorrectable)
  );

  dffr #(
      .DATA_WIDTH(16)
  ) u_frame_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_frame_count_d),
      .dat_o  (s_frame_count_q)
  );
  dffr #(
      .DATA_WIDTH(14)
  ) u_frame_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_frame_d),
      .dat_o  (s_frame_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_sof_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sof_pending_d),
      .dat_o  (s_sof_pending_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_tx_owner_engine_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_owner_engine_d),
      .dat_o  (s_tx_owner_engine_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_buffer_event_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_buffer_event_valid_d),
      .dat_o  (s_buffer_event_valid_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_buffer_event_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_buffer_event_data_d),
      .dat_o  (s_buffer_event_data_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_view_resp_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_view_resp_valid_d),
      .dat_o  (s_view_resp_valid_q)
  );
  dffr #(
      .DATA_WIDTH(9)
  ) u_view_resp_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_view_resp_data_d),
      .dat_o  (s_view_resp_data_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_ecc_corrected_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ecc_corrected_count_d),
      .dat_o  (s_ecc_corrected_count_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_ecc_uncorrectable_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ecc_uncorrectable_count_d),
      .dat_o  (s_ecc_uncorrectable_count_q)
  );
endmodule
