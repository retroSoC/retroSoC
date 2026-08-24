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

package spisd_pkg;

  typedef enum logic [2:0] {
    SpisdRespNone = 3'd0,
    SpisdRespR1   = 3'd1,
    SpisdRespR1b  = 3'd2,
    SpisdRespR2   = 3'd3,
    SpisdRespR3   = 3'd4,
    SpisdRespR7   = 3'd5
  } spisd_resp_type_e;

  typedef enum logic {
    SpisdDataFromCard = 1'b0,
    SpisdDataToCard   = 1'b1
  } spisd_data_direction_e;

  typedef enum logic [7:0] {
    SpisdErrNone          = 8'h00,
    SpisdErrCmdTimeout    = 8'h01,
    SpisdErrBusyTimeout   = 8'h02,
    SpisdErrDataTimeout   = 8'h03,
    SpisdErrDataToken     = 8'h04,
    SpisdErrDataCrc       = 8'h05,
    SpisdErrWriteReject   = 8'h06,
    SpisdErrStream        = 8'h07,
    SpisdErrAborted       = 8'h08,
    SpisdErrConfiguration = 8'h09
  } spisd_error_e;

  function automatic logic [6:0] spisd_crc7_next(input logic [6:0] crc_i, input logic data_i);
    logic feedback;
    begin
      feedback        = data_i ^ crc_i[6];
      spisd_crc7_next = {crc_i[5:0], 1'b0};
      if (feedback) spisd_crc7_next = spisd_crc7_next ^ 7'h09;
    end
  endfunction

  function automatic logic [6:0] spisd_crc7_calc(input logic [39:0] data_i);
    logic [6:0] crc;
    begin
      crc = 7'd0;
      for (int index = 39; index >= 0; index--) begin
        crc = spisd_crc7_next(crc, data_i[index]);
      end
      return crc;
    end
  endfunction

  function automatic logic [15:0] spisd_crc16_next(input logic [15:0] crc_i, input logic data_i);
    logic feedback;
    begin
      feedback         = data_i ^ crc_i[15];
      spisd_crc16_next = {crc_i[14:0], 1'b0};
      if (feedback) spisd_crc16_next = spisd_crc16_next ^ 16'h1021;
    end
  endfunction

  function automatic logic [15:0] spisd_crc16_byte(input logic [15:0] crc_i,
                                                   input logic [7:0] data_i);
    logic [15:0] crc;
    begin
      crc = crc_i;
      for (int index = 7; index >= 0; index--) begin
        crc = spisd_crc16_next(crc, data_i[index]);
      end
      return crc;
    end
  endfunction

  function automatic logic [5:0] spisd_response_bits(input spisd_resp_type_e response_type_i);
    unique case (response_type_i)
      SpisdRespR1, SpisdRespR1b: return 6'd8;
      SpisdRespR2:               return 6'd16;
      SpisdRespR3, SpisdRespR7:  return 6'd40;
      default:                   return 6'd0;
    endcase
  endfunction

endpackage
