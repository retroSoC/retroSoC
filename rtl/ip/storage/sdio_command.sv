// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`timescale 1ns / 1ps

module sdio_command #(
    parameter int TimeoutWidth = 32
) (
    input  logic                                         clk_i,
    input  logic                                         rst_n_i,
    input  logic                                         launch_tick_i,
    input  logic                                         sample_tick_i,
    input  logic                                         start_i,
    input  logic                                         abort_i,
    input  logic                      [             5:0] cmd_index_i,
    input  logic                      [            31:0] cmd_arg_i,
    input  sdio_pkg::sdio_resp_type_e                    resp_type_i,
    input  logic                                         crc_check_i,
    input  logic                                         index_check_i,
    input  logic                      [TimeoutWidth-1:0] timeout_cycles_i,
    input  logic                      [TimeoutWidth-1:0] busy_timeout_cycles_i,
    input  logic                                         cmd_di_i,
    input  logic                                         dat0_i,
    output logic                                         cmd_oe_o,
    output logic                                         cmd_do_o,
    output logic                                         busy_o,
    output logic                                         done_o,
    output logic                                         error_o,
    output logic                                         timeout_o,
    output logic                                         crc_error_o,
    output logic                                         index_error_o,
    output logic                                         busy_timeout_o,
    output logic                      [           135:0] response_o,
    output logic                      [             5:0] last_cmd_index_o
);
  typedef enum logic [2:0] {
    Idle,
    Send,
    WaitResponse,
    CaptureResponse,
    WaitBusy,
    Complete
  } command_state_e;

  command_state_e s_state_d, s_state_q;
  logic [47:0] s_tx_shift_d, s_tx_shift_q;
  logic [135:0] s_resp_d, s_resp_q;
  logic [5:0] s_cmd_index_d, s_cmd_index_q;
  logic [3:0] s_resp_type_bits_d, s_resp_type_bits_q;
  sdio_pkg::sdio_resp_type_e s_resp_type_q;
  logic [7:0] s_resp_len_d, s_resp_len_q;
  logic [7:0] s_bit_count_d, s_bit_count_q;
  logic [5:0] s_tx_count_d, s_tx_count_q;
  logic s_tx_started_d, s_tx_started_q;
  logic [TimeoutWidth-1:0] s_timeout_count_d, s_timeout_count_q;
  logic s_crc_check_d, s_crc_check_q;
  logic s_index_check_d, s_index_check_q;
  logic s_done_d, s_done_q;
  logic s_err_d, s_err_q;
  logic s_timeout_d, s_timeout_q;
  logic s_crc_err_d, s_crc_err_q;
  logic s_index_err_d, s_index_err_q;
  logic s_busy_timeout_d, s_busy_timeout_q;
  logic s_tx_final_hold_d, s_tx_final_hold_q;

  logic [           135:0] s_resp_shift_next;
  logic                    s_timeout_expired;
  logic                    s_frame_end_error;
  logic                    s_frame_crc_error;
  logic                    s_frame_index_error;
  logic [             6:0] s_frame_crc;
  logic [TimeoutWidth-1:0] s_phase_timeout;

  assign s_resp_shift_next = {s_resp_q[134:0], cmd_di_i};
  assign s_phase_timeout = (s_state_q == WaitBusy) ? busy_timeout_cycles_i : timeout_cycles_i;
  assign s_timeout_expired = (s_phase_timeout == '0) || (s_timeout_count_q >= s_phase_timeout);
  assign s_frame_end_error = s_resp_shift_next[0] != 1'b1;
  assign s_frame_crc = sdio_pkg::sdio_crc7_response(
      s_resp_shift_next, s_resp_type_q == sdio_pkg::SdioRespR2
  );
  assign s_frame_crc_error = s_frame_crc != s_resp_shift_next[7:1];
  assign s_frame_index_error = s_resp_shift_next[45:40] != s_cmd_index_q;

  assign cmd_oe_o = (s_state_q == Send) || (s_tx_final_hold_q && !sample_tick_i);
  assign cmd_do_o = ((s_state_q == Send) || s_tx_final_hold_q) ? s_tx_shift_q[47] : 1'b1;
  assign busy_o = (s_state_q != Idle) && (s_state_q != Complete);
  assign done_o = s_done_q;
  assign error_o = s_err_q;
  assign timeout_o = s_timeout_q;
  assign crc_error_o = s_crc_err_q;
  assign index_error_o = s_index_err_q;
  assign busy_timeout_o = s_busy_timeout_q;
  assign response_o = s_resp_q;
  assign last_cmd_index_o = s_cmd_index_q;

  always_comb begin
    s_state_d          = s_state_q;
    s_tx_shift_d       = s_tx_shift_q;
    s_resp_d           = s_resp_q;
    s_cmd_index_d      = s_cmd_index_q;
    s_resp_type_bits_d = s_resp_type_q;
    s_resp_len_d       = s_resp_len_q;
    s_bit_count_d      = s_bit_count_q;
    s_tx_count_d       = s_tx_count_q;
    s_tx_started_d     = s_tx_started_q;
    s_timeout_count_d  = s_timeout_count_q;
    s_crc_check_d      = s_crc_check_q;
    s_index_check_d    = s_index_check_q;
    s_done_d           = 1'b0;
    s_err_d            = s_err_q;
    s_timeout_d        = s_timeout_q;
    s_crc_err_d        = s_crc_err_q;
    s_index_err_d      = s_index_err_q;
    s_busy_timeout_d   = s_busy_timeout_q;
    s_tx_final_hold_d  = s_tx_final_hold_q;

    if (s_tx_final_hold_q && sample_tick_i) begin
      s_tx_final_hold_d = 1'b0;
    end

    if (s_state_q != Idle && s_state_q != Complete) begin
      if (s_timeout_expired) begin
        s_state_d   = Complete;
        s_done_d    = 1'b1;
        s_err_d     = 1'b1;
        s_timeout_d = 1'b1;
        if (s_state_q == WaitBusy) begin
          s_busy_timeout_d = 1'b1;
        end
      end else begin
        s_timeout_count_d = s_timeout_count_q + 1'b1;
      end
    end

    if ((s_state_q != Idle) && (s_state_q != Complete) && abort_i) begin
      s_state_d         = Complete;
      s_done_d          = 1'b1;
      s_err_d           = 1'b1;
      s_tx_final_hold_d = 1'b0;
    end

    if ((s_state_q == Send) && s_tx_started_q && sample_tick_i && (s_tx_count_q != 6'd47)) begin
      s_tx_shift_d = {s_tx_shift_q[46:0], 1'b0};
      s_tx_count_d = s_tx_count_q + 1'b1;
    end

    unique case (s_state_q)
      Idle: begin
        s_tx_final_hold_d = 1'b0;
        s_tx_started_d    = 1'b0;
        if (start_i) begin
          s_state_d = Send;
          s_tx_shift_d = {
            1'b0,
            1'b1,
            cmd_index_i,
            cmd_arg_i,
            sdio_pkg::sdio_crc7_calc({1'b0, 1'b1, cmd_index_i, cmd_arg_i}),
            1'b1
          };
          s_resp_d = '0;
          s_cmd_index_d = cmd_index_i;
          s_resp_type_bits_d = resp_type_i;
          s_resp_len_d = (resp_type_i == sdio_pkg::SdioRespR2) ? 8'd136 : 8'd48;
          s_bit_count_d = '0;
          s_tx_count_d = '0;
          s_tx_started_d = 1'b0;
          s_timeout_count_d = '0;
          s_crc_check_d = crc_check_i;
          s_index_check_d = index_check_i;
          s_err_d = 1'b0;
          s_timeout_d = 1'b0;
          s_crc_err_d = 1'b0;
          s_index_err_d = 1'b0;
          s_busy_timeout_d = 1'b0;
        end
      end
      Send: begin
        if (launch_tick_i) begin
          s_tx_started_d = 1'b1;
          if (s_tx_count_q == 6'd47) begin
            s_tx_final_hold_d = 1'b1;
            if (s_resp_type_q == sdio_pkg::SdioRespNone) begin
              s_state_d = Complete;
              s_done_d  = 1'b1;
            end else begin
              s_state_d         = WaitResponse;
              s_timeout_count_d = '0;
            end
          end
        end
      end
      WaitResponse: begin
        if (sample_tick_i && (cmd_di_i == 1'b0)) begin
          s_resp_d          = '0;
          s_resp_d[0]       = 1'b0;
          s_bit_count_d     = 8'd1;
          s_timeout_count_d = '0;
          s_state_d         = CaptureResponse;
        end
      end
      CaptureResponse: begin
        if (sample_tick_i) begin
          s_resp_d = s_resp_shift_next;
          if (s_bit_count_q == (s_resp_len_q - 1'b1)) begin
            if (s_frame_end_error) begin
              s_err_d = 1'b1;
            end
            if (s_crc_check_q && sdio_pkg::sdio_response_has_crc(
                    s_resp_type_q
                ) && s_frame_crc_error) begin
              s_err_d     = 1'b1;
              s_crc_err_d = 1'b1;
            end
            if (s_index_check_q && sdio_pkg::sdio_response_has_index(
                    s_resp_type_q
                ) && s_frame_index_error) begin
              s_err_d       = 1'b1;
              s_index_err_d = 1'b1;
            end
            if ((s_resp_type_q == sdio_pkg::SdioRespR1b) && !s_frame_end_error &&
                !(s_crc_check_q && s_frame_crc_error)) begin
              s_state_d         = WaitBusy;
              s_timeout_count_d = '0;
            end else begin
              s_state_d = Complete;
              s_done_d  = 1'b1;
            end
          end else begin
            s_bit_count_d = s_bit_count_q + 1'b1;
          end
        end
      end
      WaitBusy: begin
        if (sample_tick_i && dat0_i) begin
          s_state_d = Complete;
          s_done_d  = 1'b1;
        end
      end
      Complete: begin
        s_tx_final_hold_d = 1'b0;
        s_tx_started_d    = 1'b0;
        s_state_d         = Idle;
      end
      default: begin
        s_state_d = Idle;
        s_err_d   = 1'b1;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q          <= Idle;
      s_tx_shift_q       <= '0;
      s_resp_q           <= '0;
      s_cmd_index_q      <= '0;
      s_resp_type_bits_q <= '0;
      s_resp_len_q       <= 8'd48;
      s_bit_count_q      <= '0;
      s_tx_count_q       <= '0;
      s_tx_started_q     <= 1'b0;
      s_timeout_count_q  <= '0;
      s_crc_check_q      <= 1'b0;
      s_index_check_q    <= 1'b0;
      s_done_q           <= 1'b0;
      s_err_q            <= 1'b0;
      s_timeout_q        <= 1'b0;
      s_crc_err_q        <= 1'b0;
      s_index_err_q      <= 1'b0;
      s_busy_timeout_q   <= 1'b0;
      s_tx_final_hold_q  <= 1'b0;
    end else begin
      s_state_q          <= s_state_d;
      s_tx_shift_q       <= s_tx_shift_d;
      s_resp_q           <= s_resp_d;
      s_cmd_index_q      <= s_cmd_index_d;
      s_resp_type_bits_q <= s_resp_type_bits_d;
      s_resp_len_q       <= s_resp_len_d;
      s_bit_count_q      <= s_bit_count_d;
      s_tx_count_q       <= s_tx_count_d;
      s_tx_started_q     <= s_tx_started_d;
      s_timeout_count_q  <= s_timeout_count_d;
      s_crc_check_q      <= s_crc_check_d;
      s_index_check_q    <= s_index_check_d;
      s_done_q           <= s_done_d;
      s_err_q            <= s_err_d;
      s_timeout_q        <= s_timeout_d;
      s_crc_err_q        <= s_crc_err_d;
      s_index_err_q      <= s_index_err_d;
      s_busy_timeout_q   <= s_busy_timeout_d;
      s_tx_final_hold_q  <= s_tx_final_hold_d;
    end
  end

  always_comb begin
    s_resp_type_q = sdio_pkg::sdio_resp_type_e'(s_resp_type_bits_q);
  end

`ifndef SYNTHESIS
  initial begin
    if (TimeoutWidth < 1) begin
      $fatal(1, "sdio_command: TimeoutWidth must be positive");
    end
  end
`endif
endmodule
