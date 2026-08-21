// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// See LICENSE for the complete license text.

`timescale 1ns / 1ps

module spisd_command #(
    parameter int TimeoutWidth = 32
) (
    // verilog_format: off -- preserve the reviewed protocol/status port alignment
    input  logic                           clk_i,
    input  logic                           rst_n_i,
    input  logic                           rise_tick_i,
    input  logic                           fall_tick_i,
    input  logic                           start_i,
    input  logic                           abort_i,
    input  logic [5:0]                     cmd_index_i,
    input  logic [31:0]                    cmd_arg_i,
    input  spisd_pkg::spisd_resp_type_e    resp_type_i,
    input  logic                           stuff_byte_i,
    input  logic [TimeoutWidth-1:0]        timeout_cycles_i,
    input  logic [TimeoutWidth-1:0]        busy_timeout_cycles_i,
    input  logic                           miso_i,
    output logic                           mosi_o,
    output logic                           busy_o,
    output logic                           done_o,
    output logic                           error_o,
    output logic                           timeout_o,
    output logic                           busy_timeout_o,
    output logic [7:0]                     error_code_o,
    output logic [39:0]                    response_o,
    output logic [5:0]                     last_cmd_index_o
    // verilog_format: on
);
  typedef enum logic [2:0] {
    Idle,
    Send,
    DiscardStuff,
    WaitResponse,
    CaptureResponse,
    WaitBusy,
    Complete
  } command_state_e;

  command_state_e s_state_d, s_state_q;
  logic [2:0] s_state_bits_q;
  logic [47:0] s_tx_shift_d, s_tx_shift_q;
  logic [39:0] s_resp_shift_d, s_resp_shift_q;
  logic [5:0] s_tx_bit_cnt_d, s_tx_bit_cnt_q;
  logic [5:0] s_rx_bit_cnt_d, s_rx_bit_cnt_q;
  logic [3:0] s_stuff_bit_cnt_d, s_stuff_bit_cnt_q;
  logic [5:0] s_resp_bits_d, s_resp_bits_q;
  logic [5:0] s_cmd_index_d, s_cmd_index_q;
  logic s_resp_busy_d, s_resp_busy_q;
  logic [TimeoutWidth-1:0] s_timeout_cnt_d, s_timeout_cnt_q;
  logic s_done_d, s_done_q;
  logic s_err_d, s_err_q;
  logic s_timeout_d, s_timeout_q;
  logic s_busy_timeout_d, s_busy_timeout_q;
  logic [7:0] s_err_code_d, s_err_code_q;
  logic [            39:0] s_resp_shift_next;
  logic [TimeoutWidth-1:0] s_timeout_limit;
  logic                    s_timeout_expired;

  assign s_resp_shift_next = {s_resp_shift_q[38:0], miso_i};
  assign s_state_q         = command_state_e'(s_state_bits_q);
  assign s_timeout_limit   = (s_state_q == WaitBusy) ? busy_timeout_cycles_i : timeout_cycles_i;
  assign s_timeout_expired = (s_timeout_limit == '0) || (s_timeout_cnt_q >= s_timeout_limit);
  assign mosi_o            = (s_state_q == Send) ? s_tx_shift_q[47] : 1'b1;
  assign busy_o            = (s_state_q != Idle) && (s_state_q != Complete);
  assign done_o            = s_done_q;
  assign error_o           = s_err_q;
  assign timeout_o         = s_timeout_q;
  assign busy_timeout_o    = s_busy_timeout_q;
  assign error_code_o      = s_err_code_q;
  assign response_o        = s_resp_shift_q;
  assign last_cmd_index_o  = s_cmd_index_q;

  always_comb begin
    s_state_d         = s_state_q;
    s_tx_shift_d      = s_tx_shift_q;
    s_resp_shift_d    = s_resp_shift_q;
    s_tx_bit_cnt_d    = s_tx_bit_cnt_q;
    s_rx_bit_cnt_d    = s_rx_bit_cnt_q;
    s_stuff_bit_cnt_d = s_stuff_bit_cnt_q;
    s_resp_bits_d     = s_resp_bits_q;
    s_cmd_index_d     = s_cmd_index_q;
    s_resp_busy_d     = s_resp_busy_q;
    s_timeout_cnt_d   = s_timeout_cnt_q;
    s_done_d          = 1'b0;
    s_err_d           = s_err_q;
    s_timeout_d       = s_timeout_q;
    s_busy_timeout_d  = s_busy_timeout_q;
    s_err_code_d      = s_err_code_q;

    if ((s_state_q != Idle) && (s_state_q != Complete)) begin
      if (abort_i) begin
        s_state_d    = Complete;
        s_done_d     = 1'b1;
        s_err_d      = 1'b1;
        s_err_code_d = spisd_pkg::SpisdErrAborted;
      end else if ((s_state_q != Send) && s_timeout_expired) begin
        s_state_d = Complete;
        s_done_d = 1'b1;
        s_err_d = 1'b1;
        s_timeout_d = 1'b1;
        s_err_code_d = (s_state_q == WaitBusy) ? spisd_pkg::SpisdErrBusyTimeout :
                                                  spisd_pkg::SpisdErrCmdTimeout;
        if (s_state_q == WaitBusy) s_busy_timeout_d = 1'b1;
      end else if (s_state_q != Send) begin
        s_timeout_cnt_d = s_timeout_cnt_q + 1'b1;
      end
    end

    unique case (s_state_q)
      Idle: begin
        if (start_i) begin
          s_state_d = Send;
          s_tx_shift_d = {
            2'b01,
            cmd_index_i,
            cmd_arg_i,
            spisd_pkg::spisd_crc7_calc({2'b01, cmd_index_i, cmd_arg_i}),
            1'b1
          };
          s_resp_shift_d = '0;
          s_tx_bit_cnt_d = '0;
          s_rx_bit_cnt_d = '0;
          s_stuff_bit_cnt_d = '0;
          s_resp_bits_d = spisd_pkg::spisd_response_bits(resp_type_i);
          s_cmd_index_d = cmd_index_i;
          s_resp_busy_d = resp_type_i == spisd_pkg::SpisdRespR1b;
          s_timeout_cnt_d = '0;
          s_err_d = 1'b0;
          s_timeout_d = 1'b0;
          s_busy_timeout_d = 1'b0;
          s_err_code_d = spisd_pkg::SpisdErrNone;
        end
      end
      Send: begin
        if (fall_tick_i) begin
          if (s_tx_bit_cnt_q == 6'd47) begin
            s_timeout_cnt_d = '0;
            if (s_resp_bits_q == 6'd0) begin
              s_state_d = Complete;
              s_done_d  = 1'b1;
            end else if (stuff_byte_i) begin
              s_state_d         = DiscardStuff;
              s_stuff_bit_cnt_d = '0;
            end else begin
              s_state_d = WaitResponse;
            end
          end else begin
            s_tx_shift_d   = {s_tx_shift_q[46:0], 1'b1};
            s_tx_bit_cnt_d = s_tx_bit_cnt_q + 1'b1;
          end
        end
      end
      DiscardStuff: begin
        if (rise_tick_i) begin
          if (s_stuff_bit_cnt_q == 4'd7) begin
            s_state_d       = WaitResponse;
            s_timeout_cnt_d = '0;
          end else begin
            s_stuff_bit_cnt_d = s_stuff_bit_cnt_q + 1'b1;
          end
        end
      end
      WaitResponse: begin
        if (rise_tick_i && !miso_i) begin
          s_resp_shift_d[0] = 1'b0;
          s_rx_bit_cnt_d    = 6'd1;
          s_timeout_cnt_d   = '0;
          s_state_d         = CaptureResponse;
        end
      end
      CaptureResponse: begin
        if (rise_tick_i) begin
          s_resp_shift_d = s_resp_shift_next;
          if (s_rx_bit_cnt_q == (s_resp_bits_q - 1'b1)) begin
            s_timeout_cnt_d = '0;
            if (s_resp_busy_q) begin
              s_state_d = WaitBusy;
            end else begin
              s_state_d = Complete;
              s_done_d  = 1'b1;
            end
          end else begin
            s_rx_bit_cnt_d = s_rx_bit_cnt_q + 1'b1;
          end
        end
      end
      WaitBusy: begin
        if (rise_tick_i && miso_i) begin
          s_state_d = Complete;
          s_done_d  = 1'b1;
        end
      end
      Complete: s_state_d = Idle;
      default: begin
        s_state_d    = Complete;
        s_done_d     = 1'b1;
        s_err_d      = 1'b1;
        s_err_code_d = spisd_pkg::SpisdErrConfiguration;
      end
    endcase
  end

  dffr #(
      .DATA_WIDTH($bits(command_state_e))
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(48)
  ) u_tx_shift_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_shift_d),
      .dat_o  (s_tx_shift_q)
  );
  dffr #(
      .DATA_WIDTH(40)
  ) u_resp_shift_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_resp_shift_d),
      .dat_o  (s_resp_shift_q)
  );
  dffr #(
      .DATA_WIDTH(6)
  ) u_tx_bit_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_bit_cnt_d),
      .dat_o  (s_tx_bit_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(6)
  ) u_rx_bit_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_bit_cnt_d),
      .dat_o  (s_rx_bit_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_stuff_bit_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_stuff_bit_cnt_d),
      .dat_o  (s_stuff_bit_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(6)
  ) u_resp_bits_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_resp_bits_d),
      .dat_o  (s_resp_bits_q)
  );
  dffr #(
      .DATA_WIDTH(6)
  ) u_cmd_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cmd_index_d),
      .dat_o  (s_cmd_index_q)
  );
  dffr u_resp_busy_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_resp_busy_d),
      .dat_o  (s_resp_busy_q)
  );
  dffr #(
      .DATA_WIDTH(TimeoutWidth)
  ) u_timeout_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timeout_cnt_d),
      .dat_o  (s_timeout_cnt_q)
  );
  dffr u_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_done_d),
      .dat_o  (s_done_q)
  );
  dffr u_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
  dffr u_timeout_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timeout_d),
      .dat_o  (s_timeout_q)
  );
  dffr u_busy_timeout_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_busy_timeout_d),
      .dat_o  (s_busy_timeout_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_error_code_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_code_d),
      .dat_o  (s_err_code_q)
  );
endmodule
