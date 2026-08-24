// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module usb2_transaction_engine #(
    parameter int NumEndpoints = 8,
    parameter int MaxRetries   = 3
) (
    // verilog_format: off -- preserve work/result, SIE, and packet-store groups
    input  logic                 clk_i,
    input  logic                 rst_n_i,
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
    output logic                 tx_request_valid_o,
    input  logic                 tx_request_ready_i,
    output logic [3:0]           tx_request_pid_o,
    output logic [10:0]          tx_request_token_o,
    output logic [10:0]          tx_request_length_o,
    output logic                 tx_payload_valid_o,
    input  logic                 tx_payload_ready_i,
    output logic [7:0]           tx_payload_data_o,
    input  logic                 tx_done_i,
    input  logic                 tx_error_i,
    input  logic                 rx_payload_valid_i,
    input  logic [7:0]           rx_payload_data_i,
    input  logic                 rx_packet_done_i,
    input  logic                 rx_packet_good_i,
    input  logic [3:0]           rx_packet_pid_i,
    input  logic [6:0]           rx_token_addr_i,
    input  logic [3:0]           rx_token_endpoint_i,
    input  logic [10:0]          rx_payload_length_i,
    output logic                 store_rx_start_valid_o,
    input  logic                 store_rx_start_ready_i,
    output logic [11:0]          store_rx_base_o,
    output logic [14:0]          store_rx_limit_o,
    output logic                 store_rx_valid_o,
    input  logic                 store_rx_ready_i,
    output logic [7:0]           store_rx_data_o,
    output logic                 store_rx_commit_o,
    output logic                 store_rx_cancel_o,
    input  logic                 store_rx_done_i,
    input  logic [14:0]          store_rx_bytes_i,
    input  logic                 store_rx_overflow_i,
    output logic                 store_tx_start_valid_o,
    input  logic                 store_tx_start_ready_i,
    output logic [11:0]          store_tx_base_o,
    output logic [14:0]          store_tx_bytes_o,
    input  logic                 store_tx_valid_i,
    output logic                 store_tx_ready_o,
    input  logic [7:0]           store_tx_data_i,
    input  logic                 store_tx_done_i,
    output logic                 busy_o,
    output logic                 retry_o,
    output logic                 protocol_error_o
    // verilog_format: on
);
  typedef enum logic [4:0] {
    Idle,
    HostTokenRequest,
    HostTokenWait,
    ReceiveArm,
    ReceiveWait,
    ReceiveCommit,
    ReceiveCancel,
    ReceiveDiscard,
    TransmitArm,
    TransmitRequest,
    TransmitWait,
    HandshakeRequest,
    HandshakeWait,
    ResultWait
  } transaction_state_e;

  transaction_state_e s_state_d, s_state_q;
  logic [4:0] s_state_bits_q;
  logic [63:0] s_work_d, s_work_q;
  logic [NumEndpoints-1:0] s_device_in_ready_d, s_device_in_ready_q;
  logic [NumEndpoints-1:0] s_device_out_armed_d, s_device_out_armed_q;
  logic [NumEndpoints-1:0] s_device_in_toggle_d, s_device_in_toggle_q;
  logic [NumEndpoints-1:0] s_device_out_toggle_d, s_device_out_toggle_q;
  logic [NumEndpoints-1:0][11:0] s_device_in_base_d, s_device_in_base_q;
  logic [NumEndpoints-1:0][11:0] s_device_out_base_d, s_device_out_base_q;
  logic [NumEndpoints-1:0][14:0] s_device_in_len_d, s_device_in_len_q;
  logic [NumEndpoints-1:0][14:0] s_device_out_limit_d, s_device_out_limit_q;
  logic [3:0] s_selected_index_d, s_selected_index_q;
  logic s_context_host_d, s_context_host_q;
  logic s_direction_in_d, s_direction_in_q;
  logic [1:0] s_transfer_type_d, s_transfer_type_q;
  logic s_setup_d, s_setup_q;
  logic [3:0] s_handshake_pid_d, s_handshake_pid_q;
  logic [3:0] s_retry_count_d, s_retry_count_q;
  logic [31:0] s_timeout_count_d, s_timeout_count_q;
  logic [14:0] s_rx_len_d, s_rx_len_q;
  logic [63:0] s_result_data_d, s_result_data_q;
  logic s_result_valid_d, s_result_valid_q;
  logic [63:0] s_setup_data_d, s_setup_data_q;
  logic [3:0] s_setup_count_d, s_setup_count_q;
  logic s_setup_valid_d, s_setup_valid_q;
  logic s_retry_d, s_retry_q;
  logic s_protocol_err_d, s_protocol_err_q;
  logic s_store_tx_complete_d, s_store_tx_complete_q;
  logic        s_store_rx_commit;
  logic        s_store_rx_cancel;

  logic [ 1:0] s_work_role;
  logic [ 3:0] s_work_index;
  logic        s_work_direction_in;
  logic [ 1:0] s_work_type;
  logic [11:0] s_work_ram_base;
  logic [14:0] s_work_len;
  logic        s_work_setup;
  logic        s_work_cancel;
  logic        s_work_toggle;
  logic [ 3:0] s_active_index;
  logic [ 6:0] s_active_addr;
  logic [ 3:0] s_active_endpoint;
  logic [11:0] s_active_base;
  logic [14:0] s_active_len;
  logic        s_active_toggle;
  logic        s_timeout_expired;
  logic        s_device_token_match;
  logic        s_device_endpoint_valid;
  localparam int EndpointIndexWidth = $clog2(NumEndpoints);

  assign s_state_q = transaction_state_e'(s_state_bits_q);
  assign s_work_role = work_data_i[usb2_pkg::USB2_WORK_ROLE_LSB+:2];
  assign s_work_index = work_data_i[usb2_pkg::USB2_WORK_INDEX_LSB+:4];
  assign s_work_direction_in = work_data_i[usb2_pkg::USB2_WORK_DIRECTION_IN];
  assign s_work_type = work_data_i[usb2_pkg::USB2_WORK_TYPE_LSB+:2];
  assign s_work_ram_base = work_data_i[usb2_pkg::USB2_WORK_RAM_BASE_LSB+:12];
  assign s_work_len = work_data_i[usb2_pkg::USB2_WORK_LENGTH_LSB+:15];
  assign s_work_setup = work_data_i[usb2_pkg::USB2_WORK_SETUP];
  assign s_work_cancel = work_data_i[usb2_pkg::USB2_WORK_CANCEL];
  assign s_work_toggle = work_data_i[usb2_pkg::USB2_WORK_TOGGLE];

  assign s_active_index = s_work_q[usb2_pkg::USB2_WORK_INDEX_LSB+:4];
  assign s_active_addr = s_work_q[usb2_pkg::USB2_WORK_ADDRESS_LSB+:7];
  assign s_active_endpoint = s_work_q[usb2_pkg::USB2_WORK_ENDPOINT_LSB+:4];
  assign s_active_base = s_work_q[usb2_pkg::USB2_WORK_RAM_BASE_LSB+:12];
  assign s_active_len = s_work_q[usb2_pkg::USB2_WORK_LENGTH_LSB+:15];
  assign s_active_toggle = s_work_q[usb2_pkg::USB2_WORK_TOGGLE];
  assign s_timeout_expired = s_timeout_count_q >= timeout_i;
  assign s_device_token_match = (rx_token_addr_i == device_addr_i) &&
                                (rx_token_endpoint_i < 4'(NumEndpoints));
  assign s_device_endpoint_valid = s_selected_index_q < 4'(NumEndpoints);

  assign work_ready_o = (s_state_q == Idle) && !s_result_valid_q;
  assign result_valid_o = s_result_valid_q;
  assign result_data_o = s_result_data_q;
  assign setup_valid_o = s_setup_valid_q;
  assign setup_data_o = s_setup_data_q;
  assign busy_o = (s_state_q != Idle) || s_result_valid_q;
  assign retry_o = s_retry_q;
  assign protocol_error_o = s_protocol_err_q;

  always_comb begin
    tx_request_valid_o     = 1'b0;
    tx_request_pid_o       = usb2_pkg::Usb2PidAck;
    tx_request_token_o     = {s_active_endpoint, s_active_addr};
    tx_request_length_o    = 11'(s_active_len);
    tx_payload_valid_o     = 1'b0;
    tx_payload_data_o      = store_tx_data_i;
    store_tx_ready_o       = 1'b0;
    store_rx_start_valid_o = s_state_q == ReceiveArm;
    store_rx_base_o        = s_active_base;
    store_rx_limit_o       = s_active_len;
    if (!s_context_host_q && s_device_endpoint_valid) begin
      store_rx_base_o  = s_device_out_base_q[s_selected_index_q];
      store_rx_limit_o = s_device_out_limit_q[s_selected_index_q];
    end
    store_rx_valid_o       = (s_state_q == ReceiveWait) && rx_payload_valid_i;
    store_rx_data_o        = rx_payload_data_i;
    store_rx_commit_o      = s_store_rx_commit;
    store_rx_cancel_o      = s_store_rx_cancel;
    store_tx_start_valid_o = s_state_q == TransmitArm;
    store_tx_base_o        = s_active_base;
    store_tx_bytes_o       = s_active_len;
    if (!s_context_host_q && s_device_endpoint_valid) begin
      store_tx_base_o  = s_device_in_base_q[s_selected_index_q];
      store_tx_bytes_o = s_device_in_len_q[s_selected_index_q];
    end

    unique case (s_state_q)
      HostTokenRequest: begin
        tx_request_valid_o = 1'b1;
        if (s_setup_q) begin
          tx_request_pid_o = usb2_pkg::Usb2PidSetup;
        end else if (s_direction_in_q) begin
          tx_request_pid_o = usb2_pkg::Usb2PidIn;
        end else begin
          tx_request_pid_o = usb2_pkg::Usb2PidOut;
        end
        tx_request_length_o = 11'd0;
      end
      TransmitRequest: begin
        tx_request_valid_o = 1'b1;
        tx_request_pid_o = (s_context_host_q ? s_active_toggle :
                            s_device_in_toggle_q[s_selected_index_q[EndpointIndexWidth-1:0]]) ?
                               usb2_pkg::Usb2PidData1 : usb2_pkg::Usb2PidData0;
        tx_request_length_o = 11'(store_tx_bytes_o);
      end
      TransmitWait: begin
        tx_payload_valid_o = store_tx_valid_i;
        store_tx_ready_o   = tx_payload_ready_i;
      end
      HandshakeRequest: begin
        tx_request_valid_o  = 1'b1;
        tx_request_pid_o    = s_handshake_pid_q;
        tx_request_length_o = 11'd0;
      end
      default: begin
      end
    endcase
  end

  always_comb begin
    s_state_d             = s_state_q;
    s_work_d              = s_work_q;
    s_device_in_ready_d   = s_device_in_ready_q;
    s_device_out_armed_d  = s_device_out_armed_q;
    s_device_in_toggle_d  = s_device_in_toggle_q;
    s_device_out_toggle_d = s_device_out_toggle_q;
    s_device_in_base_d    = s_device_in_base_q;
    s_device_out_base_d   = s_device_out_base_q;
    s_device_in_len_d     = s_device_in_len_q;
    s_device_out_limit_d  = s_device_out_limit_q;
    s_selected_index_d    = s_selected_index_q;
    s_context_host_d      = s_context_host_q;
    s_direction_in_d      = s_direction_in_q;
    s_transfer_type_d     = s_transfer_type_q;
    s_setup_d             = s_setup_q;
    s_handshake_pid_d     = s_handshake_pid_q;
    s_retry_count_d       = s_retry_count_q;
    s_timeout_count_d     = s_timeout_count_q;
    s_rx_len_d            = s_rx_len_q;
    s_result_data_d       = s_result_data_q;
    s_result_valid_d      = s_result_valid_q && !result_ready_i;
    s_setup_data_d        = s_setup_data_q;
    s_setup_count_d       = s_setup_count_q;
    s_setup_valid_d       = s_setup_valid_q && !setup_ready_i;
    s_retry_d             = 1'b0;
    s_protocol_err_d      = 1'b0;
    s_store_tx_complete_d = s_store_tx_complete_q || store_tx_done_i;
    s_store_rx_commit     = 1'b0;
    s_store_rx_cancel     = 1'b0;

    if (s_state_q != Idle) begin
      if (!s_timeout_expired) begin
        s_timeout_count_d = s_timeout_count_q + 1'b1;
      end
    end else begin
      s_timeout_count_d = 32'd0;
    end

    if ((s_state_q == ReceiveWait) && rx_payload_valid_i && s_setup_q &&
        (s_setup_count_q < 4'd8)) begin
      s_setup_data_d[(s_setup_count_q*8)+:8] = rx_payload_data_i;
      s_setup_count_d                        = s_setup_count_q + 1'b1;
    end

    unique case (s_state_q)
      Idle: begin
        if (work_valid_i && work_ready_o) begin
          if (s_work_role == usb2_pkg::Usb2RoleDevice) begin
            if (s_work_index < 4'(NumEndpoints)) begin
              if (s_work_cancel) begin
                s_device_in_ready_d[s_work_index[EndpointIndexWidth-1:0]]  = 1'b0;
                s_device_out_armed_d[s_work_index[EndpointIndexWidth-1:0]] = 1'b0;
              end else if (s_work_direction_in) begin
                s_device_in_ready_d[s_work_index[EndpointIndexWidth-1:0]]  = 1'b1;
                s_device_in_base_d[s_work_index[EndpointIndexWidth-1:0]]   = s_work_ram_base;
                s_device_in_len_d[s_work_index[EndpointIndexWidth-1:0]]    = s_work_len;
                s_device_in_toggle_d[s_work_index[EndpointIndexWidth-1:0]] = s_work_toggle;
              end else begin
                s_device_out_armed_d[s_work_index[EndpointIndexWidth-1:0]]  = 1'b1;
                s_device_out_base_d[s_work_index[EndpointIndexWidth-1:0]]   = s_work_ram_base;
                s_device_out_limit_d[s_work_index[EndpointIndexWidth-1:0]]  = s_work_len;
                s_device_out_toggle_d[s_work_index[EndpointIndexWidth-1:0]] = s_work_toggle;
              end
            end
          end else if (s_work_role == usb2_pkg::Usb2RoleHost) begin
            s_work_d           = work_data_i;
            s_selected_index_d = s_work_index;
            s_context_host_d   = 1'b1;
            s_direction_in_d   = s_work_direction_in;
            s_transfer_type_d  = s_work_type;
            s_setup_d          = s_work_setup;
            s_retry_count_d    = '0;
            if (s_work_cancel) begin
              s_result_data_d                                     = '0;
              s_result_data_d[usb2_pkg::USB2_RESULT_ROLE_LSB+:2]  = usb2_pkg::Usb2RoleHost;
              s_result_data_d[usb2_pkg::USB2_RESULT_INDEX_LSB+:4] = s_work_index;
              s_result_data_d[usb2_pkg::USB2_RESULT_CODE_LSB+:4]  = usb2_pkg::Usb2ResultCanceled;
              s_result_valid_d                                    = 1'b1;
            end else begin
              s_state_d = HostTokenRequest;
            end
          end
        end else if ((active_role_i == usb2_pkg::Usb2RoleDevice) && rx_packet_done_i &&
                     rx_packet_good_i && s_device_token_match &&
                     ((rx_packet_pid_i == usb2_pkg::Usb2PidOut) ||
                      (rx_packet_pid_i == usb2_pkg::Usb2PidSetup) ||
                      (rx_packet_pid_i == usb2_pkg::Usb2PidIn))) begin
          s_selected_index_d = rx_token_endpoint_i;
          s_context_host_d   = 1'b0;
          s_direction_in_d   = rx_packet_pid_i == usb2_pkg::Usb2PidIn;
          s_transfer_type_d  = endpoint_cfg_i[rx_token_endpoint_i][5:4];
          s_setup_d          = rx_packet_pid_i == usb2_pkg::Usb2PidSetup;
          s_setup_count_d    = '0;
          s_setup_data_d     = '0;
          if (rx_packet_pid_i == usb2_pkg::Usb2PidIn) begin
            if (endpoint_cfg_i[rx_token_endpoint_i][2]) begin
              s_handshake_pid_d = usb2_pkg::Usb2PidStall;
              s_state_d         = HandshakeRequest;
            end else if (s_device_in_ready_q[rx_token_endpoint_i[EndpointIndexWidth-1:0]]) begin
              s_state_d = TransmitArm;
            end else begin
              s_handshake_pid_d = usb2_pkg::Usb2PidNak;
              s_state_d         = HandshakeRequest;
            end
          end else if (endpoint_cfg_i[rx_token_endpoint_i][3] ||
                       !s_device_out_armed_q[rx_token_endpoint_i[EndpointIndexWidth-1:0]]) begin
            s_handshake_pid_d = endpoint_cfg_i[rx_token_endpoint_i][3] ?
                                    usb2_pkg::Usb2PidStall : usb2_pkg::Usb2PidNak;
            s_state_d = ReceiveDiscard;
          end else begin
            s_state_d = ReceiveArm;
          end
        end
      end
      HostTokenRequest: begin
        if (tx_request_valid_o && tx_request_ready_i) begin
          s_timeout_count_d = 32'd0;
          s_state_d         = HostTokenWait;
        end
      end
      HostTokenWait: begin
        if (tx_error_i || s_timeout_expired) begin
          s_result_data_d = '0;
          s_result_data_d[usb2_pkg::USB2_RESULT_ROLE_LSB+:2] = usb2_pkg::Usb2RoleHost;
          s_result_data_d[usb2_pkg::USB2_RESULT_INDEX_LSB+:4] = s_active_index;
          s_result_data_d[usb2_pkg::USB2_RESULT_DIRECTION_IN] = s_direction_in_q;
          s_result_data_d[usb2_pkg::USB2_RESULT_CODE_LSB+:4] =
              s_timeout_expired ? usb2_pkg::Usb2ResultTimeout : usb2_pkg::Usb2ResultProtocol;
          s_result_valid_d = 1'b1;
          s_state_d = ResultWait;
        end else if (tx_done_i) begin
          s_timeout_count_d = 32'd0;
          s_state_d         = s_direction_in_q ? ReceiveArm : TransmitArm;
        end
      end
      ReceiveArm: begin
        if (store_rx_start_valid_o && store_rx_start_ready_i) begin
          s_timeout_count_d = 32'd0;
          s_state_d         = ReceiveWait;
        end
      end
      ReceiveWait: begin
        if (rx_payload_valid_i && !store_rx_ready_i) begin
          s_store_rx_cancel = 1'b1;
          s_protocol_err_d  = 1'b1;
          s_state_d         = ReceiveCancel;
        end else if (rx_packet_done_i) begin
          if (rx_packet_good_i && usb2_pkg::usb2_pid_is_data(rx_packet_pid_i)) begin
            s_rx_len_d        = {4'd0, rx_payload_length_i};
            s_store_rx_commit = 1'b1;
            s_state_d         = ReceiveCommit;
          end else if (rx_packet_good_i && s_context_host_q && usb2_pkg::usb2_pid_is_handshake(
                  rx_packet_pid_i
              )) begin
            s_store_rx_cancel = 1'b1;
            s_handshake_pid_d = rx_packet_pid_i;
            s_state_d         = ReceiveCancel;
          end else begin
            s_store_rx_cancel = 1'b1;
            s_protocol_err_d  = 1'b1;
            s_state_d         = ReceiveCancel;
          end
        end else if (s_timeout_expired) begin
          s_store_rx_cancel = 1'b1;
          s_handshake_pid_d = usb2_pkg::Usb2PidNak;
          s_state_d         = ReceiveCancel;
        end
      end
      ReceiveCommit: begin
        if (store_rx_done_i) begin
          s_rx_len_d = store_rx_bytes_i;
          if (store_rx_overflow_i) begin
            s_result_data_d = '0;
            s_result_data_d[usb2_pkg::USB2_RESULT_ROLE_LSB+:2] =
                s_context_host_q ? usb2_pkg::Usb2RoleHost : usb2_pkg::Usb2RoleDevice;
            s_result_data_d[usb2_pkg::USB2_RESULT_INDEX_LSB+:4] = s_selected_index_q;
            s_result_data_d[usb2_pkg::USB2_RESULT_CODE_LSB+:4] = usb2_pkg::Usb2ResultOverflow;
            s_result_valid_d = 1'b1;
            s_state_d = ResultWait;
          end else if (s_transfer_type_q == usb2_pkg::Usb2TransferIsochronous) begin
            s_handshake_pid_d = usb2_pkg::Usb2PidAck;
            s_state_d         = HandshakeWait;
          end else begin
            s_handshake_pid_d = usb2_pkg::Usb2PidAck;
            s_state_d         = HandshakeRequest;
          end
        end
      end
      ReceiveCancel: begin
        if (store_rx_done_i) begin
          if (s_context_host_q &&
              ((s_handshake_pid_q == usb2_pkg::Usb2PidNak) ||
               (s_handshake_pid_q == usb2_pkg::Usb2PidNyet)) &&
              (s_retry_count_q < 4'(MaxRetries))) begin
            s_retry_count_d   = s_retry_count_q + 1'b1;
            s_retry_d         = 1'b1;
            s_timeout_count_d = 32'd0;
            s_state_d         = HostTokenRequest;
          end else if (s_context_host_q) begin
            s_result_data_d = '0;
            s_result_data_d[usb2_pkg::USB2_RESULT_ROLE_LSB+:2] = usb2_pkg::Usb2RoleHost;
            s_result_data_d[usb2_pkg::USB2_RESULT_INDEX_LSB+:4] = s_selected_index_q;
            s_result_data_d[usb2_pkg::USB2_RESULT_DIRECTION_IN] = 1'b1;
            s_result_data_d[usb2_pkg::USB2_RESULT_CODE_LSB+:4] =
                (s_handshake_pid_q == usb2_pkg::Usb2PidStall) ?
                    usb2_pkg::Usb2ResultStall :
                (s_timeout_expired ? usb2_pkg::Usb2ResultTimeout : usb2_pkg::Usb2ResultCrc);
            s_result_valid_d = 1'b1;
            s_state_d = ResultWait;
          end else begin
            s_state_d = Idle;
          end
        end
      end
      ReceiveDiscard: begin
        if (rx_packet_done_i) begin
          if (rx_packet_good_i && usb2_pkg::usb2_pid_is_data(rx_packet_pid_i)) begin
            s_state_d = HandshakeRequest;
          end else begin
            s_state_d = Idle;
          end
        end
      end
      TransmitArm: begin
        s_store_tx_complete_d = 1'b0;
        if (store_tx_start_valid_o && store_tx_start_ready_i) begin
          s_state_d = TransmitRequest;
        end
      end
      TransmitRequest: begin
        if (tx_request_valid_o && tx_request_ready_i) begin
          s_timeout_count_d = 32'd0;
          s_state_d         = TransmitWait;
        end
      end
      TransmitWait: begin
        if (tx_error_i || s_timeout_expired) begin
          s_protocol_err_d = 1'b1;
          s_result_data_d = '0;
          s_result_data_d[usb2_pkg::USB2_RESULT_ROLE_LSB+:2] =
              s_context_host_q ? usb2_pkg::Usb2RoleHost : usb2_pkg::Usb2RoleDevice;
          s_result_data_d[usb2_pkg::USB2_RESULT_INDEX_LSB+:4] = s_selected_index_q;
          s_result_data_d[usb2_pkg::USB2_RESULT_DIRECTION_IN] = !s_context_host_q;
          s_result_data_d[usb2_pkg::USB2_RESULT_CODE_LSB+:4] =
              s_timeout_expired ? usb2_pkg::Usb2ResultTimeout : usb2_pkg::Usb2ResultProtocol;
          s_result_valid_d = 1'b1;
          s_state_d = ResultWait;
        end else if (tx_done_i && s_store_tx_complete_q) begin
          if (s_transfer_type_q == usb2_pkg::Usb2TransferIsochronous) begin
            if (!s_context_host_q && s_device_endpoint_valid) begin
              s_device_in_ready_d[s_selected_index_q[EndpointIndexWidth-1:0]] = 1'b0;
            end
            s_result_data_d = '0;
            s_result_data_d[usb2_pkg::USB2_RESULT_ROLE_LSB+:2] =
                s_context_host_q ? usb2_pkg::Usb2RoleHost : usb2_pkg::Usb2RoleDevice;
            s_result_data_d[usb2_pkg::USB2_RESULT_INDEX_LSB+:4] = s_selected_index_q;
            s_result_data_d[usb2_pkg::USB2_RESULT_DIRECTION_IN] = !s_context_host_q;
            s_result_data_d[usb2_pkg::USB2_RESULT_CODE_LSB+:4] = usb2_pkg::Usb2ResultSuccess;
            s_result_data_d[usb2_pkg::USB2_RESULT_LENGTH_LSB+:15] = s_active_len;
            s_result_valid_d = 1'b1;
            s_state_d = ResultWait;
          end else begin
            s_timeout_count_d = 32'd0;
            s_state_d         = HandshakeWait;
          end
        end
      end
      HandshakeRequest: begin
        if (tx_request_valid_o && tx_request_ready_i) begin
          s_timeout_count_d = 32'd0;
          s_state_d         = HandshakeWait;
        end
      end
      HandshakeWait: begin
        if (!s_context_host_q && !s_direction_in_q) begin
          if (tx_done_i || (s_transfer_type_q == usb2_pkg::Usb2TransferIsochronous)) begin
            s_device_out_armed_d[s_selected_index_q[EndpointIndexWidth-1:0]] = 1'b0;
            s_device_out_toggle_d[s_selected_index_q[EndpointIndexWidth-1:0]] =
                !s_device_out_toggle_q[s_selected_index_q[EndpointIndexWidth-1:0]];
            if (s_setup_q && (s_setup_count_q == 4'd8)) begin
              s_setup_valid_d = 1'b1;
            end
            s_result_data_d                                       = '0;
            s_result_data_d[usb2_pkg::USB2_RESULT_ROLE_LSB+:2]    = usb2_pkg::Usb2RoleDevice;
            s_result_data_d[usb2_pkg::USB2_RESULT_INDEX_LSB+:4]   = s_selected_index_q;
            s_result_data_d[usb2_pkg::USB2_RESULT_CODE_LSB+:4]    = usb2_pkg::Usb2ResultSuccess;
            s_result_data_d[usb2_pkg::USB2_RESULT_LENGTH_LSB+:15] = s_rx_len_q;
            s_result_valid_d                                      = 1'b1;
            s_state_d                                             = ResultWait;
          end
        end else if (s_context_host_q && s_direction_in_q) begin
          if (tx_done_i || (s_transfer_type_q == usb2_pkg::Usb2TransferIsochronous)) begin
            s_result_data_d                                       = '0;
            s_result_data_d[usb2_pkg::USB2_RESULT_ROLE_LSB+:2]    = usb2_pkg::Usb2RoleHost;
            s_result_data_d[usb2_pkg::USB2_RESULT_INDEX_LSB+:4]   = s_selected_index_q;
            s_result_data_d[usb2_pkg::USB2_RESULT_DIRECTION_IN]   = 1'b1;
            s_result_data_d[usb2_pkg::USB2_RESULT_CODE_LSB+:4]    = usb2_pkg::Usb2ResultSuccess;
            s_result_data_d[usb2_pkg::USB2_RESULT_LENGTH_LSB+:15] = s_rx_len_q;
            s_result_valid_d                                      = 1'b1;
            s_state_d                                             = ResultWait;
          end
        end else if (rx_packet_done_i && rx_packet_good_i && usb2_pkg::usb2_pid_is_handshake(
                rx_packet_pid_i
            )) begin
          if (rx_packet_pid_i == usb2_pkg::Usb2PidAck) begin
            if (s_context_host_q) begin
              s_result_data_d                                       = '0;
              s_result_data_d[usb2_pkg::USB2_RESULT_ROLE_LSB+:2]    = usb2_pkg::Usb2RoleHost;
              s_result_data_d[usb2_pkg::USB2_RESULT_INDEX_LSB+:4]   = s_selected_index_q;
              s_result_data_d[usb2_pkg::USB2_RESULT_CODE_LSB+:4]    = usb2_pkg::Usb2ResultSuccess;
              s_result_data_d[usb2_pkg::USB2_RESULT_LENGTH_LSB+:15] = s_active_len;
              s_result_valid_d                                      = 1'b1;
            end else begin
              s_device_in_ready_d[s_selected_index_q[EndpointIndexWidth-1:0]] = 1'b0;
              s_device_in_toggle_d[s_selected_index_q[EndpointIndexWidth-1:0]] =
                  !s_device_in_toggle_q[s_selected_index_q[EndpointIndexWidth-1:0]];
              s_result_data_d = '0;
              s_result_data_d[usb2_pkg::USB2_RESULT_ROLE_LSB+:2] = usb2_pkg::Usb2RoleDevice;
              s_result_data_d[usb2_pkg::USB2_RESULT_INDEX_LSB+:4] = s_selected_index_q;
              s_result_data_d[usb2_pkg::USB2_RESULT_DIRECTION_IN] = 1'b1;
              s_result_data_d[usb2_pkg::USB2_RESULT_CODE_LSB+:4] = usb2_pkg::Usb2ResultSuccess;
              s_result_data_d[usb2_pkg::USB2_RESULT_LENGTH_LSB+:15] =
                  s_device_in_len_q[s_selected_index_q];
              s_result_valid_d = 1'b1;
            end
            s_state_d = ResultWait;
          end else if (s_context_host_q &&
                       ((rx_packet_pid_i == usb2_pkg::Usb2PidNak) ||
                        (rx_packet_pid_i == usb2_pkg::Usb2PidNyet)) &&
                       (s_retry_count_q < 4'(MaxRetries))) begin
            s_retry_count_d = s_retry_count_q + 1'b1;
            s_retry_d       = 1'b1;
            s_state_d       = HostTokenRequest;
          end else if (rx_packet_pid_i == usb2_pkg::Usb2PidStall) begin
            s_result_data_d = '0;
            s_result_data_d[usb2_pkg::USB2_RESULT_ROLE_LSB+:2] =
                s_context_host_q ? usb2_pkg::Usb2RoleHost : usb2_pkg::Usb2RoleDevice;
            s_result_data_d[usb2_pkg::USB2_RESULT_INDEX_LSB+:4] = s_selected_index_q;
            s_result_data_d[usb2_pkg::USB2_RESULT_CODE_LSB+:4] = usb2_pkg::Usb2ResultStall;
            s_result_valid_d = 1'b1;
            s_state_d = ResultWait;
          end else if (!s_context_host_q) begin
            s_state_d = Idle;
          end
        end else if (s_timeout_expired) begin
          if (s_context_host_q) begin
            s_result_data_d                                     = '0;
            s_result_data_d[usb2_pkg::USB2_RESULT_ROLE_LSB+:2]  = usb2_pkg::Usb2RoleHost;
            s_result_data_d[usb2_pkg::USB2_RESULT_INDEX_LSB+:4] = s_selected_index_q;
            s_result_data_d[usb2_pkg::USB2_RESULT_CODE_LSB+:4]  = usb2_pkg::Usb2ResultTimeout;
            s_result_valid_d                                    = 1'b1;
            s_state_d                                           = ResultWait;
          end else begin
            s_state_d = Idle;
          end
        end
      end
      ResultWait: begin
        if (!s_result_valid_d) begin
          s_state_d = Idle;
        end
      end
      default: begin
        s_protocol_err_d = 1'b1;
        s_state_d        = Idle;
      end
    endcase

    if (active_role_i == usb2_pkg::Usb2RoleIdle) begin
      s_state_d = Idle;
    end
  end

  dffr #(
      .DATA_WIDTH(5)
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
      .DATA_WIDTH(NumEndpoints)
  ) u_device_in_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_device_in_ready_d),
      .dat_o  (s_device_in_ready_q)
  );
  dffr #(
      .DATA_WIDTH(NumEndpoints)
  ) u_device_out_armed_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_device_out_armed_d),
      .dat_o  (s_device_out_armed_q)
  );
  dffr #(
      .DATA_WIDTH(NumEndpoints)
  ) u_device_in_toggle_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_device_in_toggle_d),
      .dat_o  (s_device_in_toggle_q)
  );
  dffr #(
      .DATA_WIDTH(NumEndpoints)
  ) u_device_out_toggle_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_device_out_toggle_d),
      .dat_o  (s_device_out_toggle_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_selected_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_selected_index_d),
      .dat_o  (s_selected_index_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_context_host_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_context_host_d),
      .dat_o  (s_context_host_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_direction_in_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_direction_in_d),
      .dat_o  (s_direction_in_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_transfer_type_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_transfer_type_d),
      .dat_o  (s_transfer_type_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_setup_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_setup_d),
      .dat_o  (s_setup_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_handshake_pid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_handshake_pid_d),
      .dat_o  (s_handshake_pid_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_retry_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_retry_count_d),
      .dat_o  (s_retry_count_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_timeout_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timeout_count_d),
      .dat_o  (s_timeout_count_q)
  );
  dffr #(
      .DATA_WIDTH(15)
  ) u_rx_length_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_len_d),
      .dat_o  (s_rx_len_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_result_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_result_data_d),
      .dat_o  (s_result_data_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_result_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_result_valid_d),
      .dat_o  (s_result_valid_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_setup_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_setup_data_d),
      .dat_o  (s_setup_data_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_setup_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_setup_count_d),
      .dat_o  (s_setup_count_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_setup_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_setup_valid_d),
      .dat_o  (s_setup_valid_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_retry_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_retry_d),
      .dat_o  (s_retry_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_protocol_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_protocol_err_d),
      .dat_o  (s_protocol_err_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_store_tx_complete_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_store_tx_complete_d),
      .dat_o  (s_store_tx_complete_q)
  );

  for (genvar endpoint = 0; endpoint < NumEndpoints; endpoint++) begin : gen_device_context
    dffr #(
        .DATA_WIDTH(12)
    ) u_in_base_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_device_in_base_d[endpoint]),
        .dat_o  (s_device_in_base_q[endpoint])
    );
    dffr #(
        .DATA_WIDTH(12)
    ) u_out_base_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_device_out_base_d[endpoint]),
        .dat_o  (s_device_out_base_q[endpoint])
    );
    dffr #(
        .DATA_WIDTH(15)
    ) u_in_length_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_device_in_len_d[endpoint]),
        .dat_o  (s_device_in_len_q[endpoint])
    );
    dffr #(
        .DATA_WIDTH(15)
    ) u_out_limit_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_device_out_limit_d[endpoint]),
        .dat_o  (s_device_out_limit_q[endpoint])
    );
  end

`ifndef SYNTHESIS
  initial begin
    if ((NumEndpoints != 8) || (MaxRetries < 0) || (MaxRetries > 15)) begin
      $fatal(1, "usb2_transaction_engine: unsupported endpoint or retry configuration");
    end
  end
`endif
endmodule
