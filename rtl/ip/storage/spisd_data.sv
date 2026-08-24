// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
// See LICENSE for the complete license text.

`timescale 1ns / 1ps

module spisd_data #(
    parameter int TimeoutWidth = 32
) (
    // verilog_format: off -- preserve the reviewed protocol/stream port alignment
    input  logic                             clk_i,
    input  logic                             rst_n_i,
    input  logic                             rise_tick_i,
    input  logic                             fall_tick_i,
    input  logic                             start_i,
    input  logic                             abort_i,
    input  spisd_pkg::spisd_data_direction_e direction_i,
    input  logic                             multi_block_i,
    input  logic                             crc_check_i,
    input  logic [15:0]                      block_size_i,
    input  logic [15:0]                      block_count_i,
    input  logic [TimeoutWidth-1:0]          timeout_cycles_i,
    input  logic [TimeoutWidth-1:0]          busy_timeout_cycles_i,
    input  logic                             miso_i,
    output logic                             mosi_o,
    output logic                             clock_pause_o,
    input  logic                             tx_valid_i,
    output logic                             tx_ready_o,
    input  logic [31:0]                      tx_data_i,
    input  logic [3:0]                       tx_strb_i,
    input  logic                             tx_last_i,
    output logic                             rx_valid_o,
    input  logic                             rx_ready_i,
    output logic [31:0]                      rx_data_o,
    output logic [3:0]                       rx_strb_o,
    output logic                             rx_last_o,
    output logic                             busy_o,
    output logic                             done_o,
    output logic                             error_o,
    output logic                             timeout_o,
    output logic                             crc_error_o,
    output logic                             busy_timeout_o,
    output logic [7:0]                       error_code_o,
    output logic [15:0]                      blocks_done_o
    // verilog_format: on
);
  typedef enum logic [3:0] {
    Idle,
    ReadWaitToken,
    ReadPayload,
    ReadCrc,
    WriteWaitWord,
    WriteToken,
    WritePayload,
    WriteCrc,
    WriteResponse,
    WriteBusy,
    WriteStopToken,
    Complete
  } data_state_e;

  data_state_e s_state_d, s_state_q;
  logic [3:0] s_state_bits_q;
  logic [7:0] s_serial_shift_d, s_serial_shift_q;
  logic [15:0] s_crc_d, s_crc_q;
  logic [15:0] s_rx_crc_d, s_rx_crc_q;
  logic [4:0] s_bit_cnt_d, s_bit_cnt_q;
  logic [15:0] s_block_byte_cnt_d, s_block_byte_cnt_q;
  logic [15:0] s_block_cnt_d, s_block_cnt_q;
  logic [15:0] s_block_size_d, s_block_size_q;
  logic [15:0] s_block_limit_d, s_block_limit_q;
  logic s_multi_block_d, s_multi_block_q;
  logic s_crc_check_d, s_crc_check_q;
  spisd_pkg::spisd_data_direction_e s_direction_d, s_direction_q;
  logic s_direction_bit_q;
  logic [TimeoutWidth-1:0] s_timeout_cnt_d, s_timeout_cnt_q;

  logic [31:0] s_tx_word_d, s_tx_word_q;
  logic [2:0] s_tx_bytes_d, s_tx_bytes_q;
  logic s_tx_last_d, s_tx_last_q;
  logic s_tx_word_valid_d, s_tx_word_valid_q;
  logic [31:0] s_rx_word_d, s_rx_word_q;
  logic [3:0] s_rx_strb_d, s_rx_strb_q;
  logic s_rx_last_d, s_rx_last_q;
  logic s_rx_valid_d, s_rx_valid_q;

  logic s_done_d, s_done_q;
  logic s_err_d, s_err_q;
  logic s_timeout_d, s_timeout_q;
  logic s_crc_err_d, s_crc_err_q;
  logic s_busy_timeout_d, s_busy_timeout_q;
  logic [7:0] s_err_code_d, s_err_code_q;

  logic [ 7:0] s_serial_shift_next;
  logic [15:0] s_rx_crc_next;
  logic [15:0] s_payload_crc_next;
  logic [31:0] s_rx_word_next;
  logic [ 3:0] s_rx_strb_next;
  logic [ 2:0] s_tx_input_bytes;
  logic        s_tx_strb_valid;
  logic        s_last_block_byte;
  logic        s_last_transfer_byte;
  logic        s_last_block;
  logic        s_timeout_expired;
  logic        s_rx_accept;
  logic        s_tx_accept;

  function automatic logic [2:0] count_strobe(input logic [3:0] strb_i);
    logic [2:0] count;
    begin
      count = 3'd0;
      for (int index = 0; index < 4; index++) begin
        if (strb_i[index]) count = count + 1'b1;
      end
      return count;
    end
  endfunction

  assign s_serial_shift_next = {s_serial_shift_q[6:0], miso_i};
  assign s_state_q = data_state_e'(s_state_bits_q);
  assign s_direction_q = spisd_pkg::spisd_data_direction_e'(s_direction_bit_q);
  assign s_rx_crc_next = {s_rx_crc_q[14:0], miso_i};
  assign s_payload_crc_next = spisd_pkg::spisd_crc16_byte(s_crc_q, s_serial_shift_next);
  assign s_rx_word_next = s_rx_word_q | ({24'd0, s_serial_shift_next} << {count_strobe(
      s_rx_strb_q
  ), 3'b000});
  assign s_rx_strb_next = s_rx_strb_q | (4'b0001 << count_strobe(s_rx_strb_q));
  assign s_tx_input_bytes = count_strobe(tx_strb_i);
  assign s_tx_strb_valid = (tx_strb_i != 4'd0) && ((tx_strb_i & (tx_strb_i + 4'd1)) == 4'd0);
  assign s_last_block_byte = s_block_byte_cnt_q + 1'b1 >= s_block_size_q;
  assign s_last_block = s_block_cnt_q + 1'b1 >= s_block_limit_q;
  assign s_last_transfer_byte = s_last_block_byte && s_last_block;
  assign s_timeout_expired   = (s_state_q == WriteBusy)
                                 ? ((busy_timeout_cycles_i == '0) ||
                                    (s_timeout_cnt_q >= busy_timeout_cycles_i))
                                 : ((timeout_cycles_i == '0) ||
                                    (s_timeout_cnt_q >= timeout_cycles_i));
  assign s_rx_accept = s_rx_valid_q && rx_ready_i;
  assign s_tx_accept = tx_valid_i && tx_ready_o;

  assign tx_ready_o = (s_state_q == WriteWaitWord) && !s_tx_word_valid_q;
  assign rx_valid_o = s_rx_valid_q;
  assign rx_data_o = s_rx_word_q;
  assign rx_strb_o = s_rx_strb_q;
  assign rx_last_o = s_rx_last_q;
  assign busy_o = (s_state_q != Idle) && (s_state_q != Complete);
  assign done_o = s_done_q;
  assign error_o = s_err_q;
  assign timeout_o = s_timeout_q;
  assign crc_error_o = s_crc_err_q;
  assign busy_timeout_o = s_busy_timeout_q;
  assign error_code_o = s_err_code_q;
  assign blocks_done_o = s_block_cnt_q;
  assign clock_pause_o = ((s_state_q == WriteWaitWord) && !s_tx_word_valid_q) || s_rx_valid_q;

  always_comb begin
    unique case (s_state_q)
      WriteToken, WriteStopToken: mosi_o = s_serial_shift_q[7];
      WritePayload:               mosi_o = s_serial_shift_q[7];
      WriteCrc:                   mosi_o = s_crc_q[15];
      default:                    mosi_o = 1'b1;
    endcase
  end

  always_comb begin
    s_state_d          = s_state_q;
    s_serial_shift_d   = s_serial_shift_q;
    s_crc_d            = s_crc_q;
    s_rx_crc_d         = s_rx_crc_q;
    s_bit_cnt_d        = s_bit_cnt_q;
    s_block_byte_cnt_d = s_block_byte_cnt_q;
    s_block_cnt_d      = s_block_cnt_q;
    s_block_size_d     = s_block_size_q;
    s_block_limit_d    = s_block_limit_q;
    s_multi_block_d    = s_multi_block_q;
    s_crc_check_d      = s_crc_check_q;
    s_direction_d      = s_direction_q;
    s_timeout_cnt_d    = s_timeout_cnt_q;
    s_tx_word_d        = s_tx_word_q;
    s_tx_bytes_d       = s_tx_bytes_q;
    s_tx_last_d        = s_tx_last_q;
    s_tx_word_valid_d  = s_tx_word_valid_q;
    s_rx_word_d        = s_rx_word_q;
    s_rx_strb_d        = s_rx_strb_q;
    s_rx_last_d        = s_rx_last_q;
    s_rx_valid_d       = s_rx_valid_q;
    s_done_d           = 1'b0;
    s_err_d            = s_err_q;
    s_timeout_d        = s_timeout_q;
    s_crc_err_d        = s_crc_err_q;
    s_busy_timeout_d   = s_busy_timeout_q;
    s_err_code_d       = s_err_code_q;

    if (s_rx_accept) begin
      s_rx_word_d  = '0;
      s_rx_strb_d  = '0;
      s_rx_last_d  = 1'b0;
      s_rx_valid_d = 1'b0;
    end

    if ((s_state_q != Idle) && (s_state_q != Complete) && abort_i) begin
      s_state_d    = Complete;
      s_done_d     = 1'b1;
      s_err_d      = 1'b1;
      s_err_code_d = spisd_pkg::SpisdErrAborted;
    end

    if (((s_state_q == ReadWaitToken) || (s_state_q == WriteResponse) ||
         (s_state_q == WriteBusy)) && s_timeout_expired) begin
      s_state_d = Complete;
      s_done_d = 1'b1;
      s_err_d = 1'b1;
      s_timeout_d = 1'b1;
      s_err_code_d = (s_state_q == WriteBusy) ? spisd_pkg::SpisdErrBusyTimeout :
                                                  spisd_pkg::SpisdErrDataTimeout;
      if (s_state_q == WriteBusy) s_busy_timeout_d = 1'b1;
    end else if ((s_state_q == ReadWaitToken) || (s_state_q == WriteResponse) ||
                 (s_state_q == WriteBusy)) begin
      s_timeout_cnt_d = s_timeout_cnt_q + 1'b1;
    end

    unique case (s_state_q)
      Idle: begin
        if (start_i) begin
          s_block_size_d     = block_size_i;
          s_block_limit_d    = block_count_i;
          s_multi_block_d    = multi_block_i;
          s_crc_check_d      = crc_check_i;
          s_direction_d      = direction_i;
          s_serial_shift_d   = '1;
          s_crc_d            = '0;
          s_rx_crc_d         = '0;
          s_bit_cnt_d        = '0;
          s_block_byte_cnt_d = '0;
          s_block_cnt_d      = '0;
          s_timeout_cnt_d    = '0;
          s_tx_word_valid_d  = 1'b0;
          s_rx_word_d        = '0;
          s_rx_strb_d        = '0;
          s_rx_valid_d       = 1'b0;
          s_err_d            = 1'b0;
          s_timeout_d        = 1'b0;
          s_crc_err_d        = 1'b0;
          s_busy_timeout_d   = 1'b0;
          s_err_code_d       = spisd_pkg::SpisdErrNone;
          if ((block_size_i == 16'd0) || (block_count_i == 16'd0)) begin
            s_state_d    = Complete;
            s_done_d     = 1'b1;
            s_err_d      = 1'b1;
            s_err_code_d = spisd_pkg::SpisdErrConfiguration;
          end else if (direction_i == spisd_pkg::SpisdDataFromCard) begin
            s_state_d = ReadWaitToken;
          end else begin
            s_state_d = WriteWaitWord;
          end
        end
      end
      ReadWaitToken: begin
        if (rise_tick_i) begin
          s_serial_shift_d = s_serial_shift_next;
          if (s_bit_cnt_q == 5'd7) begin
            s_bit_cnt_d = '0;
            if (s_serial_shift_next == 8'hFE) begin
              s_state_d          = ReadPayload;
              s_serial_shift_d   = '0;
              s_crc_d            = '0;
              s_block_byte_cnt_d = '0;
              s_timeout_cnt_d    = '0;
            end else if ((s_serial_shift_next[7:4] == 4'h0) && (s_serial_shift_next != 8'h00)) begin
              s_state_d    = Complete;
              s_done_d     = 1'b1;
              s_err_d      = 1'b1;
              s_err_code_d = spisd_pkg::SpisdErrDataToken;
            end
          end else begin
            s_bit_cnt_d = s_bit_cnt_q + 1'b1;
          end
        end
      end
      ReadPayload: begin
        if (rise_tick_i && !s_rx_valid_q) begin
          s_serial_shift_d = s_serial_shift_next;
          if (s_bit_cnt_q == 5'd7) begin
            s_bit_cnt_d        = '0;
            s_crc_d            = s_payload_crc_next;
            s_block_byte_cnt_d = s_block_byte_cnt_q + 1'b1;
            s_rx_word_d        = s_rx_word_next;
            s_rx_strb_d        = s_rx_strb_next;
            if ((count_strobe(s_rx_strb_next) == 3'd4) || s_last_transfer_byte) begin
              s_rx_valid_d = 1'b1;
              s_rx_last_d  = s_last_transfer_byte;
            end
            if (s_last_block_byte) begin
              s_state_d   = ReadCrc;
              s_bit_cnt_d = '0;
              s_rx_crc_d  = '0;
            end
          end else begin
            s_bit_cnt_d = s_bit_cnt_q + 1'b1;
          end
        end
      end
      ReadCrc: begin
        if (rise_tick_i && !s_rx_valid_q) begin
          s_rx_crc_d = s_rx_crc_next;
          if (s_bit_cnt_q == 5'd15) begin
            s_bit_cnt_d = '0;
            if (s_crc_check_q && (s_rx_crc_next != s_crc_q)) begin
              s_state_d    = Complete;
              s_done_d     = 1'b1;
              s_err_d      = 1'b1;
              s_crc_err_d  = 1'b1;
              s_err_code_d = spisd_pkg::SpisdErrDataCrc;
            end else begin
              s_block_cnt_d = s_block_cnt_q + 1'b1;
              if (s_last_block) begin
                s_state_d = Complete;
                s_done_d  = 1'b1;
              end else begin
                s_state_d       = ReadWaitToken;
                s_timeout_cnt_d = '0;
              end
            end
          end else begin
            s_bit_cnt_d = s_bit_cnt_q + 1'b1;
          end
        end
      end
      WriteWaitWord: begin
        if (s_tx_accept) begin
          if (!s_tx_strb_valid) begin
            s_state_d    = Complete;
            s_done_d     = 1'b1;
            s_err_d      = 1'b1;
            s_err_code_d = spisd_pkg::SpisdErrStream;
          end else begin
            s_tx_word_d       = tx_data_i;
            s_tx_bytes_d      = s_tx_input_bytes;
            s_tx_last_d       = tx_last_i;
            s_tx_word_valid_d = 1'b1;
            s_bit_cnt_d       = '0;
            if (s_block_byte_cnt_q == 16'd0) begin
              s_serial_shift_d = s_multi_block_q ? 8'hFC : 8'hFE;
              s_state_d        = WriteToken;
            end else begin
              s_serial_shift_d = tx_data_i[7:0];
              s_state_d        = WritePayload;
            end
          end
        end
      end
      WriteToken: begin
        if (fall_tick_i) begin
          if (s_bit_cnt_q == 5'd7) begin
            s_bit_cnt_d      = '0;
            s_crc_d          = '0;
            s_serial_shift_d = s_tx_word_q[7:0];
            s_state_d        = WritePayload;
          end else begin
            s_serial_shift_d = {s_serial_shift_q[6:0], 1'b1};
            s_bit_cnt_d      = s_bit_cnt_q + 1'b1;
          end
        end
      end
      WritePayload: begin
        if (fall_tick_i) begin
          if (s_bit_cnt_q == 5'd0) begin
            s_crc_d = spisd_pkg::spisd_crc16_byte(s_crc_q, s_tx_word_q[7:0]);
          end
          if (s_bit_cnt_q == 5'd7) begin
            s_bit_cnt_d        = '0;
            s_block_byte_cnt_d = s_block_byte_cnt_q + 1'b1;
            s_tx_word_d        = {8'hFF, s_tx_word_q[31:8]};
            s_tx_bytes_d       = s_tx_bytes_q - 1'b1;
            if (s_last_block_byte) begin
              if (s_last_transfer_byte != s_tx_last_q) begin
                s_state_d    = Complete;
                s_done_d     = 1'b1;
                s_err_d      = 1'b1;
                s_err_code_d = spisd_pkg::SpisdErrStream;
              end else begin
                s_tx_word_valid_d = 1'b0;
                s_state_d         = WriteCrc;
              end
            end else if (s_tx_bytes_q == 3'd1) begin
              if (s_tx_last_q) begin
                s_state_d    = Complete;
                s_done_d     = 1'b1;
                s_err_d      = 1'b1;
                s_err_code_d = spisd_pkg::SpisdErrStream;
              end else begin
                s_tx_word_valid_d = 1'b0;
                s_state_d         = WriteWaitWord;
              end
            end else begin
              s_serial_shift_d = s_tx_word_q[15:8];
            end
          end else begin
            s_serial_shift_d = {s_serial_shift_q[6:0], 1'b1};
            s_bit_cnt_d      = s_bit_cnt_q + 1'b1;
          end
        end
      end
      WriteCrc: begin
        if (fall_tick_i) begin
          if (s_bit_cnt_q == 5'd15) begin
            s_bit_cnt_d      = '0;
            s_serial_shift_d = '1;
            s_timeout_cnt_d  = '0;
            s_state_d        = WriteResponse;
          end else begin
            s_crc_d     = {s_crc_q[14:0], 1'b1};
            s_bit_cnt_d = s_bit_cnt_q + 1'b1;
          end
        end
      end
      WriteResponse: begin
        if (rise_tick_i) begin
          if ((s_bit_cnt_q == 5'd0) && !miso_i) begin
            s_serial_shift_d = '0;
            s_bit_cnt_d      = 5'd1;
            s_timeout_cnt_d  = '0;
          end else if (s_bit_cnt_q != 5'd0) begin
            s_serial_shift_d = s_serial_shift_next;
            if (s_bit_cnt_q == 5'd4) begin
              s_bit_cnt_d = '0;
              if (s_serial_shift_next[4:0] == 5'b00101) begin
                s_state_d       = WriteBusy;
                s_timeout_cnt_d = '0;
              end else begin
                s_state_d    = Complete;
                s_done_d     = 1'b1;
                s_err_d      = 1'b1;
                s_err_code_d = spisd_pkg::SpisdErrWriteReject;
              end
            end else begin
              s_bit_cnt_d = s_bit_cnt_q + 1'b1;
            end
          end
        end
      end
      WriteBusy: begin
        if (rise_tick_i && miso_i) begin
          s_timeout_cnt_d = '0;
          if (s_block_cnt_q >= s_block_limit_q) begin
            s_state_d = Complete;
            s_done_d  = 1'b1;
          end else begin
            s_block_cnt_d      = s_block_cnt_q + 1'b1;
            s_block_byte_cnt_d = '0;
            if (s_last_block) begin
              if (s_multi_block_q) begin
                s_serial_shift_d = 8'hFD;
                s_bit_cnt_d      = '0;
                s_state_d        = WriteStopToken;
              end else begin
                s_state_d = Complete;
                s_done_d  = 1'b1;
              end
            end else begin
              s_state_d = WriteWaitWord;
            end
          end
        end
      end
      WriteStopToken: begin
        if (fall_tick_i) begin
          if (s_bit_cnt_q == 5'd7) begin
            s_block_cnt_d   = s_block_limit_q;
            s_timeout_cnt_d = '0;
            s_bit_cnt_d     = '0;
            s_state_d       = WriteBusy;
          end else begin
            s_serial_shift_d = {s_serial_shift_q[6:0], 1'b1};
            s_bit_cnt_d      = s_bit_cnt_q + 1'b1;
          end
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
      .DATA_WIDTH($bits(data_state_e))
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffrc #(
      .DATA_WIDTH(8),
      .RESET_VAL (8'hFF)
  ) u_serial_shift_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_serial_shift_d),
      .dat_o  (s_serial_shift_q)
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
      .DATA_WIDTH(16)
  ) u_rx_crc_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_crc_d),
      .dat_o  (s_rx_crc_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_bit_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_bit_cnt_d),
      .dat_o  (s_bit_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_block_byte_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_block_byte_cnt_d),
      .dat_o  (s_block_byte_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_block_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_block_cnt_d),
      .dat_o  (s_block_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_block_size_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_block_size_d),
      .dat_o  (s_block_size_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_block_limit_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_block_limit_d),
      .dat_o  (s_block_limit_q)
  );
  dffr u_multi_block_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_multi_block_d),
      .dat_o  (s_multi_block_q)
  );
  dffr u_crc_check_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_crc_check_d),
      .dat_o  (s_crc_check_q)
  );
  dffr #(
      .DATA_WIDTH($bits(spisd_pkg::spisd_data_direction_e))
  ) u_direction_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_direction_d),
      .dat_o  (s_direction_bit_q)
  );
  dffr #(
      .DATA_WIDTH(TimeoutWidth)
  ) u_timeout_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timeout_cnt_d),
      .dat_o  (s_timeout_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_tx_word_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_word_d),
      .dat_o  (s_tx_word_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_tx_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_bytes_d),
      .dat_o  (s_tx_bytes_q)
  );
  dffr u_tx_last_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_last_d),
      .dat_o  (s_tx_last_q)
  );
  dffr u_tx_word_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_word_valid_d),
      .dat_o  (s_tx_word_valid_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_rx_word_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_word_d),
      .dat_o  (s_rx_word_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_rx_strb_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_strb_d),
      .dat_o  (s_rx_strb_q)
  );
  dffr u_rx_last_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_last_d),
      .dat_o  (s_rx_last_q)
  );
  dffr u_rx_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_valid_d),
      .dat_o  (s_rx_valid_q)
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
  dffr u_crc_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_crc_err_d),
      .dat_o  (s_crc_err_q)
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
