// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`timescale 1ns / 1ps

module sdio_data #(
    parameter int TimeoutWidth = 32
) (
    input  logic                                              clk_i,
    input  logic                                              rst_n_i,
    input  logic                                              launch_tick_i,
    input  logic                                              sample_tick_i,
    input  logic                                              start_i,
    input  logic                                              abort_i,
    input  sdio_pkg::sdio_data_direction_e                    direction_i,
    input  logic                           [             1:0] bus_width_i,
    input  logic                           [            15:0] block_size_i,
    input  logic                           [            15:0] block_count_i,
    input  logic                           [TimeoutWidth-1:0] timeout_cycles_i,
    input  logic                           [TimeoutWidth-1:0] busy_timeout_cycles_i,
    input  logic                           [             3:0] dat_di_i,
    input  logic                                              dat0_i,
    output logic                           [             3:0] dat_oe_o,
    output logic                           [             3:0] dat_do_o,
    input  logic                                              tx_valid_i,
    output logic                                              tx_ready_o,
    output logic                                              tx_wait_o,
    input  logic                           [            31:0] tx_data_i,
    input  logic                           [             3:0] tx_strb_i,
    input  logic                                              tx_last_i,
    output logic                                              rx_valid_o,
    input  logic                                              rx_ready_i,
    output logic                           [            31:0] rx_data_o,
    output logic                           [             3:0] rx_strb_o,
    output logic                                              rx_last_o,
    output logic                                              busy_o,
    output logic                                              done_o,
    output logic                                              error_o,
    output logic                                              timeout_o,
    output logic                                              crc_error_o,
    output logic                                              busy_timeout_o
);
  typedef enum logic [3:0] {
    Idle,
    WriteWaitWord,
    WriteNextWord,
    WriteToken,
    WritePayload,
    WriteCrc,
    WriteResponse,
    WriteBusy,
    ReadToken,
    ReadPayload,
    ReadEmit,
    ReadCrc
  } data_state_e;

  data_state_e s_state_d, s_state_q;
  logic s_width4_d, s_width4_q;
  logic [31:0] s_target_bytes_d, s_target_bytes_q;
  logic [31:0] s_tx_total_d, s_tx_total_q;
  logic [31:0] s_rx_total_d, s_rx_total_q;
  logic [31:0] s_tx_word_d, s_tx_word_q;
  logic [3:0] s_tx_strb_d, s_tx_strb_q;
  logic [2:0] s_tx_active_bytes_d, s_tx_active_bytes_q;
  logic [2:0] s_tx_byte_d, s_tx_byte_q;
  logic [3:0] s_tx_bit_d, s_tx_bit_q;
  logic [15:0] s_tx_crc_d, s_tx_crc_q;
  logic [63:0] s_tx_crc_lanes_d, s_tx_crc_lanes_q;
  logic s_tx_token_launched_d, s_tx_token_launched_q;
  logic [4:0] s_crc_bit_d, s_crc_bit_q;
  logic s_tx_crc_final_hold_d, s_tx_crc_final_hold_q;
  logic [31:0] s_rx_word_d, s_rx_word_q;
  logic [7:0] s_rx_byte_d, s_rx_byte_q;
  logic [2:0] s_rx_active_bytes_d, s_rx_active_bytes_q;
  logic [2:0] s_rx_byte_didx_d, s_rx_byte_didx_q;
  logic [3:0] s_rx_bit_d, s_rx_bit_q;
  logic [15:0] s_rx_crc_d, s_rx_crc_q;
  logic [63:0] s_rx_crc_lanes_d, s_rx_crc_lanes_q;
  logic [15:0] s_rx_crc_received_d, s_rx_crc_received_q;
  logic [63:0] s_rx_crc_received_lanes_d, s_rx_crc_received_lanes_q;
  logic [31:0] s_rx_pending_data_d, s_rx_pending_data_q;
  logic [3:0] s_rx_pending_strb_d, s_rx_pending_strb_q;
  logic s_rx_pending_last_d, s_rx_pending_last_q;
  logic [4:0] s_resp_token_d, s_resp_token_q;
  logic [2:0] s_resp_bit_d, s_resp_bit_q;
  logic [TimeoutWidth-1:0] s_timeout_count_d, s_timeout_count_q;
  logic s_done_d, s_done_q;
  logic s_err_d, s_err_q;
  logic s_timeout_d, s_timeout_q;
  logic s_crc_err_d, s_crc_err_q;
  logic s_busy_timeout_d, s_busy_timeout_q;

  logic [            31:0] s_target_bytes_calc;
  logic [             7:0] s_rx_byte_next;
  logic [            31:0] s_rx_remaining;
  logic [TimeoutWidth-1:0] s_phase_timeout;
  logic                    s_timeout_expired;
  logic                    s_tx_word_final;

  function automatic logic [2:0] count_strobe(input logic [3:0] strb_i);
    logic [2:0] count;
    begin
      count = 3'd0;
      for (int index = 0; index < 4; index++) begin
        if (strb_i[index]) begin
          count = count + 1'b1;
        end
      end
      return count;
    end
  endfunction

  function automatic logic strobe_valid(input logic [3:0] strb_i);
    return (strb_i != 4'd0) && ((strb_i & (strb_i + 4'd1)) == 4'd0);
  endfunction

  function automatic logic [63:0] update_lane_crc(
      input logic [63:0] crc_i, input logic [3:0] bits_i, input logic [2:0] lane_count_i);
    logic [63:0] crc;
    begin
      crc = crc_i;
      for (int lane = 0; lane < 4; lane++) begin
        if (lane < lane_count_i) begin
          crc[lane*16+:16] = sdio_pkg::sdio_crc16_next(crc_i[lane*16+:16], bits_i[lane]);
        end
      end
      return crc;
    end
  endfunction

  function automatic logic [3:0] tx_lane_bits(input logic [31:0] word_i, input logic [3:0] bit_i);
    logic [3:0] bits;
    begin
      bits = 4'b0000;
      for (int lane = 0; lane < 4; lane++) begin
        bits[lane] = word_i[lane*8+(int'(7)-int'(bit_i))];
      end
      return bits;
    end
  endfunction

  assign s_target_bytes_calc = {16'd0, block_size_i} * {16'd0, block_count_i};
  assign s_rx_remaining = s_target_bytes_q - s_rx_total_q;
  assign s_rx_byte_next = {s_rx_byte_q[6:0], dat_di_i[0]};
  assign s_phase_timeout = (s_state_q == WriteBusy) ? busy_timeout_cycles_i : timeout_cycles_i;
  assign s_timeout_expired = (s_phase_timeout == '0) || (s_timeout_count_q >= s_phase_timeout);

  assign s_tx_word_final = s_width4_q
                            ? (s_tx_bit_q == 4'd7)
                            : ((s_tx_bit_q == 4'd7) &&
                               (s_tx_byte_q + 1'b1 >= s_tx_active_bytes_q));
  assign tx_ready_o = (s_state_q == WriteWaitWord) || (s_state_q == WriteNextWord) ||
                      ((s_state_q == WritePayload) && launch_tick_i && s_tx_word_final &&
                       (s_tx_total_q < s_target_bytes_q));
  assign tx_wait_o = (s_state_q == WriteWaitWord) || (s_state_q == WriteNextWord);
  assign rx_valid_o = (s_state_q == ReadEmit);
  assign rx_data_o = s_rx_pending_data_q;
  assign rx_strb_o = s_rx_pending_strb_q;
  assign rx_last_o = s_rx_pending_last_q;
  assign busy_o = s_state_q != Idle;
  assign done_o = s_done_q;
  assign error_o = s_err_q;
  assign timeout_o = s_timeout_q;
  assign crc_error_o = s_crc_err_q;
  assign busy_timeout_o = s_busy_timeout_q;

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (tx_valid_i && tx_ready_o && tx_last_i) begin
      assert (s_tx_total_q + {29'd0, count_strobe(tx_strb_i)} >= s_target_bytes_q)
      else $error("sdio_data: tx_last asserted before the target byte count");
    end
  end
`endif

  always_comb begin
    dat_oe_o = 4'b0000;
    dat_do_o = 4'b1111;
    if ((s_state_q == WriteToken) || (s_state_q == WritePayload) ||
        (s_state_q == WriteCrc) || s_tx_crc_final_hold_q) begin
      if (s_width4_q) begin
        dat_oe_o = (s_tx_active_bytes_q >= 3'd4)
                       ? 4'b1111
                       : ((4'b0001 << s_tx_active_bytes_q) - 1'b1);
      end else begin
        dat_oe_o = 4'b0001;
      end
    end
    if (s_state_q == WriteToken) begin
      dat_do_o = 4'b0000;
    end else if ((s_state_q == WritePayload) && s_width4_q) begin
      dat_do_o = 4'b1111;
      for (int lane = 0; lane < 4; lane++) begin
        if (lane < s_tx_active_bytes_q) begin
          dat_do_o[lane] = s_tx_word_q[lane*8+(int'(7)-int'(s_tx_bit_q))];
        end
      end
    end else if (s_state_q == WritePayload) begin
      dat_do_o[0] = s_tx_word_q[s_tx_byte_q*8+(int'(7)-int'(s_tx_bit_q))];
    end else if ((s_state_q == WriteCrc) || s_tx_crc_final_hold_q) begin
      if (s_width4_q) begin
        dat_do_o = 4'b1111;
        for (int lane = 0; lane < 4; lane++) begin
          if (lane < s_tx_active_bytes_q) begin
            dat_do_o[lane] = s_tx_crc_lanes_q[lane*16+(int'(15)-int'(s_crc_bit_q))];
          end
        end
      end else begin
        dat_do_o[0] = s_tx_crc_q[int'(15)-int'(s_crc_bit_q)];
      end
    end
  end

  always_comb begin
    s_state_d                 = s_state_q;
    s_width4_d                = s_width4_q;
    s_target_bytes_d          = s_target_bytes_q;
    s_tx_total_d              = s_tx_total_q;
    s_rx_total_d              = s_rx_total_q;
    s_tx_word_d               = s_tx_word_q;
    s_tx_strb_d               = s_tx_strb_q;
    s_tx_active_bytes_d       = s_tx_active_bytes_q;
    s_tx_byte_d               = s_tx_byte_q;
    s_tx_bit_d                = s_tx_bit_q;
    s_tx_crc_d                = s_tx_crc_q;
    s_tx_crc_lanes_d          = s_tx_crc_lanes_q;
    s_tx_token_launched_d     = s_tx_token_launched_q;
    s_crc_bit_d               = s_crc_bit_q;
    s_tx_crc_final_hold_d     = s_tx_crc_final_hold_q;
    s_rx_word_d               = s_rx_word_q;
    s_rx_byte_d               = s_rx_byte_q;
    s_rx_active_bytes_d       = s_rx_active_bytes_q;
    s_rx_byte_didx_d          = s_rx_byte_didx_q;
    s_rx_bit_d                = s_rx_bit_q;
    s_rx_crc_d                = s_rx_crc_q;
    s_rx_crc_lanes_d          = s_rx_crc_lanes_q;
    s_rx_crc_received_d       = s_rx_crc_received_q;
    s_rx_crc_received_lanes_d = s_rx_crc_received_lanes_q;
    s_rx_pending_data_d       = s_rx_pending_data_q;
    s_rx_pending_strb_d       = s_rx_pending_strb_q;
    s_rx_pending_last_d       = s_rx_pending_last_q;
    s_resp_token_d            = s_resp_token_q;
    s_resp_bit_d              = s_resp_bit_q;
    s_timeout_count_d         = s_timeout_count_q;
    s_done_d                  = 1'b0;
    s_err_d                   = s_err_q;
    s_timeout_d               = s_timeout_q;
    s_crc_err_d               = s_crc_err_q;
    s_busy_timeout_d          = s_busy_timeout_q;

    if (s_tx_crc_final_hold_q && sample_tick_i) begin
      s_tx_crc_final_hold_d = 1'b0;
    end

    if ((s_state_q != Idle) && s_timeout_expired) begin
      s_state_d             = Idle;
      s_done_d              = 1'b1;
      s_err_d               = 1'b1;
      s_timeout_d           = 1'b1;
      s_busy_timeout_d      = (s_state_q == WriteBusy);
      s_tx_crc_final_hold_d = 1'b0;
    end else if (s_state_q != Idle) begin
      s_timeout_count_d = s_timeout_count_q + 1'b1;
    end

    if (abort_i && (s_state_q != Idle)) begin
      s_state_d             = Idle;
      s_done_d              = 1'b1;
      s_err_d               = 1'b1;
      s_tx_crc_final_hold_d = 1'b0;
    end else if (s_state_q == Idle) begin
      if (start_i) begin
        s_width4_d = bus_width_i == 2'd1;
        s_target_bytes_d = s_target_bytes_calc;
        s_tx_total_d = '0;
        s_rx_total_d = '0;
        s_tx_word_d = '0;
        s_tx_strb_d = '0;
        s_tx_active_bytes_d = '0;
        s_tx_byte_d = '0;
        s_tx_bit_d = '0;
        s_tx_crc_d = '0;
        s_tx_crc_lanes_d = '0;
        s_tx_token_launched_d = 1'b0;
        s_crc_bit_d = '0;
        s_tx_crc_final_hold_d = 1'b0;
        s_rx_word_d = '0;
        s_rx_byte_d = '0;
        s_rx_active_bytes_d = (s_target_bytes_calc >= 32'd4) ? 3'd4 : s_target_bytes_calc[2:0];
        s_rx_byte_didx_d = '0;
        s_rx_bit_d = '0;
        s_rx_crc_d = '0;
        s_rx_crc_lanes_d = '0;
        s_rx_crc_received_d = '0;
        s_rx_crc_received_lanes_d = '0;
        s_rx_pending_data_d = '0;
        s_rx_pending_strb_d = '0;
        s_rx_pending_last_d = 1'b0;
        s_resp_token_d = '0;
        s_resp_bit_d = '0;
        s_timeout_count_d = '0;
        s_err_d = s_target_bytes_calc == 32'd0;
        s_timeout_d = 1'b0;
        s_crc_err_d = 1'b0;
        s_busy_timeout_d = 1'b0;
        if (s_target_bytes_calc == 32'd0) begin
          s_state_d = Idle;
          s_done_d  = 1'b1;
        end else if (direction_i == sdio_pkg::SdioDataToCard) begin
          s_state_d = WriteWaitWord;
        end else begin
          s_state_d = ReadToken;
        end
      end
    end else begin
      unique case (s_state_q)
        WriteWaitWord, WriteNextWord: begin
          if (tx_valid_i && tx_ready_o) begin
            s_tx_active_bytes_d = count_strobe(tx_strb_i);
            s_tx_word_d         = tx_data_i;
            s_tx_strb_d         = tx_strb_i;
            s_tx_byte_d         = '0;
            s_tx_bit_d          = '0;
            if (s_state_q == WriteWaitWord) begin
              s_tx_crc_d       = '0;
              s_tx_crc_lanes_d = '0;
            end
            s_tx_token_launched_d = 1'b0;
            s_tx_total_d          = s_tx_total_q + {29'd0, count_strobe(tx_strb_i)};
            s_tx_crc_final_hold_d = 1'b0;
            s_timeout_count_d     = '0;
            if (!strobe_valid(
                    tx_strb_i
                ) || (s_tx_total_q + {29'd0, count_strobe(
                    tx_strb_i
                )} > s_target_bytes_q)) begin
              s_state_d = Idle;
              s_done_d  = 1'b1;
              s_err_d   = 1'b1;
            end else begin
              s_state_d = (s_state_q == WriteWaitWord) ? WriteToken : WritePayload;
            end
          end
        end
        WriteToken: begin
          if (sample_tick_i) begin
            s_tx_token_launched_d = 1'b1;
          end
          if (launch_tick_i && s_tx_token_launched_q) begin
            s_state_d             = WritePayload;
            s_tx_byte_d           = '0;
            s_tx_bit_d            = '0;
            s_timeout_count_d     = '0;
            s_tx_token_launched_d = 1'b0;
          end
        end
        WritePayload: begin
          if (launch_tick_i) begin
            if (s_width4_q) begin
              s_tx_crc_lanes_d = update_lane_crc(
                  s_tx_crc_lanes_q, tx_lane_bits(s_tx_word_q, s_tx_bit_q), s_tx_active_bytes_q);
              if (s_tx_bit_q == 4'd7) begin
                if (s_tx_total_q >= s_target_bytes_q) begin
                  s_state_d   = WriteCrc;
                  s_crc_bit_d = '0;
                end else if (tx_valid_i && tx_ready_o) begin
                  s_tx_word_d         = tx_data_i;
                  s_tx_strb_d         = tx_strb_i;
                  s_tx_active_bytes_d = count_strobe(tx_strb_i);
                  s_tx_total_d        = s_tx_total_q + {29'd0, count_strobe(tx_strb_i)};
                  s_tx_byte_d         = '0;
                  s_tx_bit_d          = '0;
                end else begin
                  s_state_d = WriteNextWord;
                end
              end else begin
                s_tx_bit_d = s_tx_bit_q + 1'b1;
              end
            end else if (s_tx_bit_q == 4'd7) begin
              s_tx_crc_d = sdio_pkg::sdio_crc16_byte(s_tx_crc_q, s_tx_word_q[s_tx_byte_q*8+:8]);
              if (s_tx_byte_q + 1'b1 >= s_tx_active_bytes_q) begin
                if (s_tx_total_q >= s_target_bytes_q) begin
                  s_state_d   = WriteCrc;
                  s_crc_bit_d = '0;
                end else if (tx_valid_i && tx_ready_o) begin
                  s_tx_word_d         = tx_data_i;
                  s_tx_strb_d         = tx_strb_i;
                  s_tx_active_bytes_d = count_strobe(tx_strb_i);
                  s_tx_total_d        = s_tx_total_q + {29'd0, count_strobe(tx_strb_i)};
                  s_tx_byte_d         = '0;
                  s_tx_bit_d          = '0;
                end else begin
                  s_state_d = WriteNextWord;
                end
              end else begin
                s_tx_byte_d = s_tx_byte_q + 1'b1;
                s_tx_bit_d  = '0;
              end
            end else begin
              s_tx_bit_d = s_tx_bit_q + 1'b1;
            end
          end
        end
        WriteCrc: begin
          if (launch_tick_i) begin
            if (s_crc_bit_q == 5'd15) begin
              s_tx_crc_final_hold_d = 1'b1;
              s_state_d             = WriteResponse;
              s_resp_token_d        = '0;
              s_resp_bit_d          = '0;
              s_timeout_count_d     = '0;
            end else begin
              s_crc_bit_d = s_crc_bit_q + 1'b1;
            end
          end
        end
        WriteResponse: begin
          if (launch_tick_i && !s_tx_crc_final_hold_q) begin
            s_resp_token_d = {s_resp_token_q[3:0], dat0_i};
            if (s_resp_bit_q == 3'd4) begin
              if ({s_resp_token_q[3:0], dat0_i} == 5'b00101) begin
                s_state_d         = WriteBusy;
                s_timeout_count_d = '0;
              end else begin
                s_state_d = Idle;
                s_done_d  = 1'b1;
                s_err_d   = 1'b1;
                if ({s_resp_token_q[3:0], dat0_i} == 5'b01011) begin
                  s_crc_err_d = 1'b1;
                end
              end
            end else begin
              s_resp_bit_d = s_resp_bit_q + 1'b1;
            end
          end
        end
        WriteBusy: begin
          if (sample_tick_i && dat0_i) begin
            if (s_tx_total_q >= s_target_bytes_q) begin
              s_state_d = Idle;
              s_done_d  = 1'b1;
            end else begin
              s_state_d         = WriteWaitWord;
              s_timeout_count_d = '0;
            end
          end
        end
        ReadToken: begin
          if (sample_tick_i && (dat_di_i == 4'b0000)) begin
            s_state_d         = ReadPayload;
            s_rx_word_d       = '0;
            s_rx_byte_d       = '0;
            s_rx_byte_didx_d  = '0;
            s_rx_bit_d        = '0;
            s_rx_crc_d        = '0;
            s_rx_crc_lanes_d  = '0;
            s_timeout_count_d = '0;
          end
        end
        ReadPayload: begin
          if (sample_tick_i) begin
            if (s_width4_q) begin
              for (int lane = 0; lane < 4; lane++) begin
                if (lane < s_rx_active_bytes_q) begin
                  s_rx_word_d[lane*8+(int'(7)-int'(s_rx_bit_q))] = dat_di_i[lane];
                  s_rx_crc_lanes_d[lane*16+:16] =
                      sdio_pkg::sdio_crc16_next(s_rx_crc_lanes_q[lane*16+:16], dat_di_i[lane]);
                end
              end
              if (s_rx_bit_q == 4'd7) begin
                s_rx_pending_data_d = s_rx_word_d;
                s_rx_pending_strb_d = (4'b0001 << s_rx_active_bytes_q) - 1'b1;
                s_rx_pending_last_d =
                    s_rx_total_q + {29'd0, s_rx_active_bytes_q} >= s_target_bytes_q;
                s_rx_total_d = s_rx_total_q + {29'd0, s_rx_active_bytes_q};
                s_state_d = ReadEmit;
              end else begin
                s_rx_bit_d = s_rx_bit_q + 1'b1;
              end
            end else begin
              s_rx_byte_d = s_rx_byte_next;
              if (s_rx_bit_q == 4'd7) begin
                s_rx_word_d[s_rx_byte_didx_q*8+:8] = s_rx_byte_next;
                s_rx_byte_d                        = '0;
                if (s_rx_byte_didx_q + 1'b1 >= s_rx_active_bytes_q) begin
                  s_rx_pending_data_d = s_rx_word_d;
                  s_rx_pending_strb_d = (4'b0001 << s_rx_active_bytes_q) - 1'b1;
                  s_rx_pending_last_d =
                      s_rx_total_q + {29'd0, s_rx_active_bytes_q} >= s_target_bytes_q;
                  s_rx_total_d = s_rx_total_q + {29'd0, s_rx_active_bytes_q};
                  s_state_d = ReadEmit;
                end else begin
                  s_rx_byte_didx_d = s_rx_byte_didx_q + 1'b1;
                  s_rx_bit_d       = '0;
                end
                s_rx_crc_d = sdio_pkg::sdio_crc16_byte(s_rx_crc_q, s_rx_byte_next);
              end else begin
                s_rx_bit_d = s_rx_bit_q + 1'b1;
              end
            end
          end
        end
        ReadEmit: begin
          if (rx_valid_o && rx_ready_i) begin
            if (s_rx_pending_last_q) begin
              s_crc_bit_d = '0;
              s_state_d   = ReadCrc;
            end else begin
              s_rx_word_d         = '0;
              s_rx_byte_d         = '0;
              s_rx_active_bytes_d = (s_rx_remaining >= 32'd4) ? 3'd4 : s_rx_remaining[2:0];
              s_rx_byte_didx_d    = '0;
              s_rx_bit_d          = '0;
              s_state_d           = ReadPayload;
              s_timeout_count_d   = '0;
            end
          end
        end
        ReadCrc: begin
          if (sample_tick_i) begin
            if (s_width4_q) begin
              for (int lane = 0; lane < 4; lane++) begin
                if (lane < s_rx_active_bytes_q) begin
                  s_rx_crc_received_lanes_d[lane*16+:16] = {
                    s_rx_crc_received_lanes_q[lane*16+14-:15], dat_di_i[lane]
                  };
                end
              end
              if (s_crc_bit_q == 5'd15) begin
                for (int lane = 0; lane < 4; lane++) begin
                  if ((lane < s_rx_active_bytes_q) &&
                      (s_rx_crc_received_lanes_d[lane*16+:16] !=
                       s_rx_crc_lanes_q[lane*16+:16])) begin
                    s_err_d     = 1'b1;
                    s_crc_err_d = 1'b1;
                  end
                end
                s_state_d = Idle;
                s_done_d  = 1'b1;
              end else begin
                s_crc_bit_d = s_crc_bit_q + 1'b1;
              end
            end else begin
              s_rx_crc_received_d = {s_rx_crc_received_q[14:0], dat_di_i[0]};
              if (s_crc_bit_q == 5'd15) begin
                if ({s_rx_crc_received_q[14:0], dat_di_i[0]} != s_rx_crc_q) begin
                  s_err_d     = 1'b1;
                  s_crc_err_d = 1'b1;
                end
                s_state_d = Idle;
                s_done_d  = 1'b1;
              end else begin
                s_crc_bit_d = s_crc_bit_q + 1'b1;
              end
            end
          end
        end
        default: begin
          s_state_d = Idle;
          s_err_d   = 1'b1;
        end
      endcase
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q                 <= Idle;
      s_width4_q                <= 1'b0;
      s_target_bytes_q          <= '0;
      s_tx_total_q              <= '0;
      s_rx_total_q              <= '0;
      s_tx_word_q               <= '0;
      s_tx_strb_q               <= '0;
      s_tx_active_bytes_q       <= '0;
      s_tx_byte_q               <= '0;
      s_tx_bit_q                <= '0;
      s_tx_crc_q                <= '0;
      s_tx_crc_lanes_q          <= '0;
      s_tx_token_launched_q     <= 1'b0;
      s_crc_bit_q               <= '0;
      s_tx_crc_final_hold_q     <= 1'b0;
      s_rx_word_q               <= '0;
      s_rx_byte_q               <= '0;
      s_rx_active_bytes_q       <= '0;
      s_rx_byte_didx_q          <= '0;
      s_rx_bit_q                <= '0;
      s_rx_crc_q                <= '0;
      s_rx_crc_lanes_q          <= '0;
      s_rx_crc_received_q       <= '0;
      s_rx_crc_received_lanes_q <= '0;
      s_rx_pending_data_q       <= '0;
      s_rx_pending_strb_q       <= '0;
      s_rx_pending_last_q       <= 1'b0;
      s_resp_token_q            <= '0;
      s_resp_bit_q              <= '0;
      s_timeout_count_q         <= '0;
      s_done_q                  <= 1'b0;
      s_err_q                   <= 1'b0;
      s_timeout_q               <= 1'b0;
      s_crc_err_q               <= 1'b0;
      s_busy_timeout_q          <= 1'b0;
    end else begin
      s_state_q                 <= s_state_d;
      s_width4_q                <= s_width4_d;
      s_target_bytes_q          <= s_target_bytes_d;
      s_tx_total_q              <= s_tx_total_d;
      s_rx_total_q              <= s_rx_total_d;
      s_tx_word_q               <= s_tx_word_d;
      s_tx_strb_q               <= s_tx_strb_d;
      s_tx_active_bytes_q       <= s_tx_active_bytes_d;
      s_tx_byte_q               <= s_tx_byte_d;
      s_tx_bit_q                <= s_tx_bit_d;
      s_tx_crc_q                <= s_tx_crc_d;
      s_tx_crc_lanes_q          <= s_tx_crc_lanes_d;
      s_tx_token_launched_q     <= s_tx_token_launched_d;
      s_crc_bit_q               <= s_crc_bit_d;
      s_tx_crc_final_hold_q     <= s_tx_crc_final_hold_d;
      s_rx_word_q               <= s_rx_word_d;
      s_rx_byte_q               <= s_rx_byte_d;
      s_rx_active_bytes_q       <= s_rx_active_bytes_d;
      s_rx_byte_didx_q          <= s_rx_byte_didx_d;
      s_rx_bit_q                <= s_rx_bit_d;
      s_rx_crc_q                <= s_rx_crc_d;
      s_rx_crc_lanes_q          <= s_rx_crc_lanes_d;
      s_rx_crc_received_q       <= s_rx_crc_received_d;
      s_rx_crc_received_lanes_q <= s_rx_crc_received_lanes_d;
      s_rx_pending_data_q       <= s_rx_pending_data_d;
      s_rx_pending_strb_q       <= s_rx_pending_strb_d;
      s_rx_pending_last_q       <= s_rx_pending_last_d;
      s_resp_token_q            <= s_resp_token_d;
      s_resp_bit_q              <= s_resp_bit_d;
      s_timeout_count_q         <= s_timeout_count_d;
      s_done_q                  <= s_done_d;
      s_err_q                   <= s_err_d;
      s_timeout_q               <= s_timeout_d;
      s_crc_err_q               <= s_crc_err_d;
      s_busy_timeout_q          <= s_busy_timeout_d;
    end
  end

`ifndef SYNTHESIS
  initial begin
    if (TimeoutWidth < 1) begin
      $fatal(1, "sdio_data: TimeoutWidth must be positive");
    end
  end
`endif
endmodule
