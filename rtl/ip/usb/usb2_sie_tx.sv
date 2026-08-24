// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module usb2_sie_tx (
    // verilog_format: off -- preserve request, source stream, and ULPI link groups
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       request_valid_i,
    output logic       request_ready_o,
    input  logic [3:0] request_pid_i,
    input  logic [10:0] request_token_i,
    input  logic [10:0] request_length_i,
    input  logic       payload_valid_i,
    output logic       payload_ready_o,
    input  logic [7:0] payload_data_i,
    output logic       link_start_valid_o,
    input  logic       link_start_ready_i,
    output logic [3:0] link_pid_o,
    output logic       link_has_data_o,
    output logic       link_data_valid_o,
    input  logic       link_data_ready_i,
    output logic [7:0] link_data_o,
    output logic       link_data_last_o,
    input  logic       link_done_i,
    input  logic       link_error_i,
    output logic       busy_o,
    output logic       done_o,
    output logic       error_o
    // verilog_format: on
);
  typedef enum logic [3:0] {
    Idle,
    Start,
    TokenLow,
    TokenHigh,
    Payload,
    CrcLow,
    CrcHigh,
    WaitDone
  } tx_state_e;

  tx_state_e s_state_d, s_state_q;
  logic [3:0] s_state_bits_q;
  logic [3:0] s_pid_d, s_pid_q;
  logic [10:0] s_token_d, s_token_q;
  logic [10:0] s_len_d, s_len_q;
  logic [10:0] s_count_d, s_count_q;
  logic [15:0] s_crc_d, s_crc_q;
  logic [15:0] s_crc_finished;
  logic [ 4:0] s_token_crc;
  logic        s_is_token;
  logic        s_is_data;
  logic        s_is_handshake;
  logic s_done_d, s_done_q;
  logic s_err_d, s_err_q;

  assign s_state_q          = tx_state_e'(s_state_bits_q);
  assign s_is_token         = usb2_pkg::usb2_pid_is_token(s_pid_q);
  assign s_is_data          = usb2_pkg::usb2_pid_is_data(s_pid_q);
  assign s_is_handshake     = usb2_pkg::usb2_pid_is_handshake(s_pid_q);
  assign s_token_crc        = usb2_pkg::usb2_token_crc5(s_token_q);
  assign s_crc_finished     = usb2_pkg::usb2_crc16_finish(s_crc_q);
  assign request_ready_o    = s_state_q == Idle;
  assign payload_ready_o    = (s_state_q == Payload) && link_data_ready_i;
  assign link_start_valid_o = s_state_q == Start;
  assign link_pid_o         = s_pid_q;
  assign link_has_data_o    = !s_is_handshake;
  assign busy_o             = s_state_q != Idle;
  assign done_o             = s_done_q;
  assign error_o            = s_err_q;

  always_comb begin
    link_data_valid_o = 1'b0;
    link_data_o       = 8'd0;
    link_data_last_o  = 1'b0;
    unique case (s_state_q)
      TokenLow: begin
        link_data_valid_o = 1'b1;
        link_data_o       = s_token_q[7:0];
      end
      TokenHigh: begin
        link_data_valid_o = 1'b1;
        link_data_o       = {s_token_crc, s_token_q[10:8]};
        link_data_last_o  = 1'b1;
      end
      Payload: begin
        link_data_valid_o = payload_valid_i;
        link_data_o       = payload_data_i;
      end
      CrcLow: begin
        link_data_valid_o = 1'b1;
        link_data_o       = s_crc_finished[7:0];
      end
      CrcHigh: begin
        link_data_valid_o = 1'b1;
        link_data_o       = s_crc_finished[15:8];
        link_data_last_o  = 1'b1;
      end
      default: begin
      end
    endcase
  end

  always_comb begin
    s_state_d = s_state_q;
    s_pid_d   = s_pid_q;
    s_token_d = s_token_q;
    s_len_d   = s_len_q;
    s_count_d = s_count_q;
    s_crc_d   = s_crc_q;
    s_done_d  = 1'b0;
    s_err_d   = 1'b0;

    unique case (s_state_q)
      Idle: begin
        if (request_valid_i) begin
          s_pid_d   = request_pid_i;
          s_token_d = request_token_i;
          s_len_d   = request_length_i;
          s_count_d = '0;
          s_crc_d   = 16'hFFFF;
          s_state_d = Start;
        end
      end
      Start: begin
        if (link_start_ready_i) begin
          if (s_is_token) begin
            s_state_d = TokenLow;
          end else if (s_is_data) begin
            if (s_len_q == 11'd0) begin
              s_state_d = CrcLow;
            end else begin
              s_state_d = Payload;
            end
          end else if (s_is_handshake) begin
            s_state_d = WaitDone;
          end else begin
            s_state_d = Idle;
            s_err_d   = 1'b1;
          end
        end
      end
      TokenLow: begin
        if (link_data_valid_o && link_data_ready_i) begin
          s_state_d = TokenHigh;
        end
      end
      TokenHigh: begin
        if (link_data_valid_o && link_data_ready_i) begin
          s_state_d = WaitDone;
        end
      end
      Payload: begin
        if (payload_valid_i && payload_ready_o) begin
          s_crc_d   = usb2_pkg::usb2_crc16_byte(s_crc_q, payload_data_i);
          s_count_d = s_count_q + 1'b1;
          if ((s_count_q + 1'b1) == s_len_q) begin
            s_state_d = CrcLow;
          end
        end
      end
      CrcLow: begin
        if (link_data_valid_o && link_data_ready_i) begin
          s_state_d = CrcHigh;
        end
      end
      CrcHigh: begin
        if (link_data_valid_o && link_data_ready_i) begin
          s_state_d = WaitDone;
        end
      end
      WaitDone: begin
        if (link_error_i) begin
          s_state_d = Idle;
          s_err_d   = 1'b1;
        end else if (link_done_i) begin
          s_state_d = Idle;
          s_done_d  = 1'b1;
        end
      end
      default: begin
        s_state_d = Idle;
        s_err_d   = 1'b1;
      end
    endcase
  end

  dffr #(
      .DATA_WIDTH(4)
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
      .DATA_WIDTH(11)
  ) u_token_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_token_d),
      .dat_o  (s_token_q)
  );
  dffr #(
      .DATA_WIDTH(11)
  ) u_length_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_len_d),
      .dat_o  (s_len_q)
  );
  dffr #(
      .DATA_WIDTH(11)
  ) u_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_count_d),
      .dat_o  (s_count_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_crc_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_crc_d),
      .dat_o  (s_crc_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_done_d),
      .dat_o  (s_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );

`ifndef SV_ASSRT_DISABLE
  property p_payload_stable_when_stalled;
    @(posedge clk_i) disable iff (!rst_n_i)
      (payload_valid_i && !payload_ready_o && s_state_q == Payload) |=>
          $stable(
        payload_data_i
    );
  endproperty
  assert property (p_payload_stable_when_stalled);
`endif
endmodule
