// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`timescale 1ns / 1ps

package sdio_pkg;

  typedef enum logic [3:0] {
    SdioRespNone = 4'd0,
    SdioRespR1   = 4'd1,
    SdioRespR1b  = 4'd2,
    SdioRespR2   = 4'd3,
    SdioRespR3   = 4'd4,
    SdioRespR4   = 4'd5,
    SdioRespR5   = 4'd6,
    SdioRespR6   = 4'd7,
    SdioRespR7   = 4'd8
  } sdio_resp_type_e;

  typedef enum logic {
    SdioDataFromCard = 1'b0,
    SdioDataToCard   = 1'b1
  } sdio_data_direction_e;

  typedef enum logic [2:0] {
    SdioClockStopped = 3'd0,
    SdioClock400k    = 3'd1,
    SdioClock25m     = 3'd2,
    SdioClock50m     = 3'd3
  } sdio_clock_profile_e;

  localparam logic [4:0] SDIO_DESC_OWN = 5'd0;
  localparam logic [4:0] SDIO_DESC_CHAIN = 5'd1;
  localparam logic [4:0] SDIO_DESC_END = 5'd2;
  localparam logic [4:0] SDIO_DESC_IRQ = 5'd3;
  localparam logic [4:0] SDIO_DESC_DONE = 5'd16;
  localparam logic [4:0] SDIO_DESC_ERROR = 5'd17;

  function automatic logic [6:0] sdio_crc7_next(input logic [6:0] crc_i, input logic data_i);
    logic feedback;
    begin
      feedback       = data_i ^ crc_i[6];
      sdio_crc7_next = {crc_i[5:0], 1'b0};
      if (feedback) begin
        sdio_crc7_next = sdio_crc7_next ^ 7'h09;
      end
    end
  endfunction

  function automatic logic [6:0] sdio_crc7_calc(input logic [39:0] data_i);
    logic [6:0] crc;
    begin
      crc = 7'd0;
      for (int index = 39; index >= 0; index--) begin
        crc = sdio_crc7_next(crc, data_i[index]);
      end
      return crc;
    end
  endfunction

  function automatic logic [6:0] sdio_crc7_vector(input logic [135:0] data_i,
                                                  input int unsigned bit_count_i);
    logic [6:0] crc;
    begin
      crc = 7'd0;
      if ((bit_count_i >= 1) && (bit_count_i <= 136)) begin
        for (int index = bit_count_i - 1; index >= 0; index--) begin
          crc = sdio_crc7_next(crc, data_i[index]);
        end
      end
      return crc;
    end
  endfunction

  function automatic logic [6:0] sdio_crc7_response(input logic [135:0] data_i, input logic r2_i);
    logic [6:0] crc;
    begin
      crc = 7'd0;
      if (r2_i) begin
        for (int index = 135; index >= 8; index--) begin
          crc = sdio_crc7_next(crc, data_i[index]);
        end
      end else begin
        for (int index = 47; index >= 8; index--) begin
          crc = sdio_crc7_next(crc, data_i[index]);
        end
      end
      return crc;
    end
  endfunction

  function automatic logic [15:0] sdio_crc16_next(input logic [15:0] crc_i, input logic data_i);
    logic feedback;
    begin
      feedback        = data_i ^ crc_i[15];
      sdio_crc16_next = {crc_i[14:0], 1'b0};
      if (feedback) begin
        sdio_crc16_next = sdio_crc16_next ^ 16'h1021;
      end
    end
  endfunction

  function automatic logic [15:0] sdio_crc16_byte(input logic [15:0] crc_i,
                                                  input logic [7:0] data_i);
    logic [15:0] crc;
    begin
      crc = crc_i;
      for (int index = 7; index >= 0; index--) begin
        crc = sdio_crc16_next(crc, data_i[index]);
      end
      return crc;
    end
  endfunction

  function automatic logic sdio_response_has_crc(input sdio_resp_type_e response_type_i);
    return (response_type_i == SdioRespR1) || (response_type_i == SdioRespR1b) ||
           (response_type_i == SdioRespR2) || (response_type_i == SdioRespR5) ||
           (response_type_i == SdioRespR6) || (response_type_i == SdioRespR7);
  endfunction

  function automatic logic sdio_response_has_index(input sdio_resp_type_e response_type_i);
    return (response_type_i != SdioRespNone) && (response_type_i != SdioRespR2) &&
           (response_type_i != SdioRespR3) && (response_type_i != SdioRespR4);
  endfunction

endpackage
