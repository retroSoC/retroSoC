// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module usb2_sie_rx (
    // verilog_format: off -- preserve link input and decoded packet groups
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       rx_start_i,
    input  logic       rx_valid_i,
    input  logic [7:0] rx_data_i,
    input  logic       rx_end_i,
    input  logic       rx_error_i,
    output logic       payload_valid_o,
    output logic [7:0] payload_data_o,
    output logic       packet_done_o,
    output logic       packet_good_o,
    output logic [3:0] packet_pid_o,
    output logic [6:0] token_addr_o,
    output logic [3:0] token_endpoint_o,
    output logic [10:0] frame_number_o,
    output logic [10:0] payload_length_o,
    output logic       pid_error_o,
    output logic       crc_error_o,
    output logic       framing_error_o
    // verilog_format: on
);
  typedef enum logic [1:0] {
    Idle,
    Header,
    Body
  } rx_state_e;

  rx_state_e s_state_d, s_state_q;
  logic [1:0] s_state_bits_q;
  logic [3:0] s_pid_d, s_pid_q;
  logic [7:0] s_token_low_d, s_token_low_q;
  logic [7:0] s_token_high_d, s_token_high_q;
  logic [1:0] s_token_count_d, s_token_count_q;
  logic [7:0] s_tail_first_d, s_tail_first_q;
  logic [7:0] s_tail_second_d, s_tail_second_q;
  logic [1:0] s_tail_count_d, s_tail_count_q;
  logic [15:0] s_crc16_d, s_crc16_q;
  logic [10:0] s_payload_len_d, s_payload_len_q;
  logic s_link_err_d, s_link_err_q;
  logic s_payload_valid_d, s_payload_valid_q;
  logic [7:0] s_payload_data_d, s_payload_data_q;
  logic s_packet_done_d, s_packet_done_q;
  logic s_packet_good_d, s_packet_good_q;
  logic s_pid_err_d, s_pid_err_q;
  logic s_crc_err_d, s_crc_err_q;
  logic s_framing_err_d, s_framing_err_q;
  logic [10:0] s_token_value;
  logic [ 4:0] s_token_crc;
  logic        s_is_token;
  logic        s_is_data;
  logic        s_is_handshake;

  assign s_state_q        = rx_state_e'(s_state_bits_q);
  assign s_token_value    = {s_token_high_q[2:0], s_token_low_q};
  assign s_token_crc      = s_token_high_q[7:3];
  assign s_is_token       = usb2_pkg::usb2_pid_is_token(s_pid_q);
  assign s_is_data        = usb2_pkg::usb2_pid_is_data(s_pid_q);
  assign s_is_handshake   = usb2_pkg::usb2_pid_is_handshake(s_pid_q);

  assign payload_valid_o  = s_payload_valid_q;
  assign payload_data_o   = s_payload_data_q;
  assign packet_done_o    = s_packet_done_q;
  assign packet_good_o    = s_packet_good_q;
  assign packet_pid_o     = s_pid_q;
  assign token_addr_o     = s_token_value[6:0];
  assign token_endpoint_o = s_token_value[10:7];
  assign frame_number_o   = s_token_value;
  assign payload_length_o = s_payload_len_q;
  assign pid_error_o      = s_pid_err_q;
  assign crc_error_o      = s_crc_err_q;
  assign framing_error_o  = s_framing_err_q;

  always_comb begin
    s_state_d         = s_state_q;
    s_pid_d           = s_pid_q;
    s_token_low_d     = s_token_low_q;
    s_token_high_d    = s_token_high_q;
    s_token_count_d   = s_token_count_q;
    s_tail_first_d    = s_tail_first_q;
    s_tail_second_d   = s_tail_second_q;
    s_tail_count_d    = s_tail_count_q;
    s_crc16_d         = s_crc16_q;
    s_payload_len_d   = s_payload_len_q;
    s_link_err_d      = s_link_err_q || rx_error_i;
    s_payload_valid_d = 1'b0;
    s_payload_data_d  = s_payload_data_q;
    s_packet_done_d   = 1'b0;
    s_packet_good_d   = 1'b0;
    s_pid_err_d       = 1'b0;
    s_crc_err_d       = 1'b0;
    s_framing_err_d   = 1'b0;

    if (rx_start_i) begin
      s_state_d       = Header;
      s_token_count_d = '0;
      s_tail_count_d  = '0;
      s_crc16_d       = 16'hFFFF;
      s_payload_len_d = '0;
      s_link_err_d    = rx_error_i;
    end

    if (rx_valid_i) begin
      unique case (s_state_q)
        Header: begin
          if (usb2_pkg::usb2_pid_valid(rx_data_i)) begin
            s_pid_d   = rx_data_i[3:0];
            s_state_d = Body;
          end else begin
            s_pid_d      = rx_data_i[3:0];
            s_pid_err_d  = 1'b1;
            s_link_err_d = 1'b1;
            s_state_d    = Body;
          end
        end
        Body: begin
          if (s_is_token) begin
            if (s_token_count_q == 2'd0) begin
              s_token_low_d   = rx_data_i;
              s_token_count_d = 2'd1;
            end else if (s_token_count_q == 2'd1) begin
              s_token_high_d  = rx_data_i;
              s_token_count_d = 2'd2;
            end else begin
              s_link_err_d = 1'b1;
            end
          end else if (s_is_data) begin
            if (s_tail_count_q == 2'd0) begin
              s_tail_first_d = rx_data_i;
              s_tail_count_d = 2'd1;
            end else if (s_tail_count_q == 2'd1) begin
              s_tail_second_d = rx_data_i;
              s_tail_count_d  = 2'd2;
            end else begin
              s_payload_valid_d = 1'b1;
              s_payload_data_d  = s_tail_first_q;
              s_payload_len_d   = s_payload_len_q + 1'b1;
              s_crc16_d         = usb2_pkg::usb2_crc16_byte(s_crc16_q, s_tail_first_q);
              s_tail_first_d    = s_tail_second_q;
              s_tail_second_d   = rx_data_i;
            end
          end else if (!s_is_handshake) begin
            s_link_err_d = 1'b1;
          end
        end
        default: begin
          s_link_err_d = 1'b1;
        end
      endcase
    end

    if (rx_end_i && (s_state_q != Idle)) begin
      s_packet_done_d = 1'b1;
      s_state_d       = Idle;
      if (s_is_token) begin
        if ((s_token_count_q == 2'd2) && (usb2_pkg::usb2_token_crc5(
                s_token_value
            ) == s_token_crc) && !s_link_err_q) begin
          s_packet_good_d = 1'b1;
        end else begin
          s_crc_err_d     = s_token_count_q == 2'd2;
          s_framing_err_d = s_token_count_q != 2'd2;
        end
      end else if (s_is_data) begin
        if ((s_tail_count_q == 2'd2) &&
            ({s_tail_second_q, s_tail_first_q} == usb2_pkg::usb2_crc16_finish(
                s_crc16_q
            )) && !s_link_err_q) begin
          s_packet_good_d = 1'b1;
        end else begin
          s_crc_err_d     = s_tail_count_q == 2'd2;
          s_framing_err_d = s_tail_count_q != 2'd2;
        end
      end else if (s_is_handshake && !s_link_err_q && (s_token_count_q == 2'd0) &&
                   (s_tail_count_q == 2'd0)) begin
        s_packet_good_d = 1'b1;
      end else begin
        s_framing_err_d = 1'b1;
      end
    end
  end

  dffr #(
      .DATA_WIDTH(2)
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_pid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pid_d),
      .dat_o  (s_pid_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_token_low_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_token_low_d),
      .dat_o  (s_token_low_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_token_high_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_token_high_d),
      .dat_o  (s_token_high_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_token_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_token_count_d),
      .dat_o  (s_token_count_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_tail_first_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tail_first_d),
      .dat_o  (s_tail_first_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_tail_second_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tail_second_d),
      .dat_o  (s_tail_second_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_tail_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tail_count_d),
      .dat_o  (s_tail_count_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_crc16_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_crc16_d),
      .dat_o  (s_crc16_q)
  );
  dffr #(
      .DATA_WIDTH(11)
  ) u_payload_length_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_payload_len_d),
      .dat_o  (s_payload_len_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_link_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_link_err_d),
      .dat_o  (s_link_err_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_payload_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_payload_valid_d),
      .dat_o  (s_payload_valid_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_payload_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_payload_data_d),
      .dat_o  (s_payload_data_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_packet_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_packet_done_d),
      .dat_o  (s_packet_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_packet_good_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_packet_good_d),
      .dat_o  (s_packet_good_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_pid_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pid_err_d),
      .dat_o  (s_pid_err_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_crc_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_crc_err_d),
      .dat_o  (s_crc_err_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_framing_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_framing_err_d),
      .dat_o  (s_framing_err_q)
  );
endmodule
