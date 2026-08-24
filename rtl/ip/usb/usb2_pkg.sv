// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

package usb2_pkg;

  typedef enum logic [1:0] {
    Usb2RoleIdle   = 2'd0,
    Usb2RoleDevice = 2'd1,
    Usb2RoleHost   = 2'd2
  } usb2_role_e;

  typedef enum logic [1:0] {
    Usb2SpeedHigh = 2'd0,
    Usb2SpeedFull = 2'd1,
    Usb2SpeedLow  = 2'd2
  } usb2_speed_e;

  typedef enum logic [1:0] {
    Usb2TransferControl     = 2'd0,
    Usb2TransferIsochronous = 2'd1,
    Usb2TransferBulk        = 2'd2,
    Usb2TransferInterrupt   = 2'd3
  } usb2_transfer_type_e;

  typedef enum logic [3:0] {
    Usb2PidOut   = 4'h1,
    Usb2PidAck   = 4'h2,
    Usb2PidData0 = 4'h3,
    Usb2PidPing  = 4'h4,
    Usb2PidSof   = 4'h5,
    Usb2PidNyet  = 4'h6,
    Usb2PidData2 = 4'h7,
    Usb2PidSplit = 4'h8,
    Usb2PidIn    = 4'h9,
    Usb2PidNak   = 4'hA,
    Usb2PidData1 = 4'hB,
    Usb2PidPre   = 4'hC,
    Usb2PidSetup = 4'hD,
    Usb2PidStall = 4'hE,
    Usb2PidMdata = 4'hF
  } usb2_pid_e;

  typedef enum logic [4:0] {
    Usb2DescOk            = 5'd0,
    Usb2DescNotOwned      = 5'd1,
    Usb2DescReserved      = 5'd2,
    Usb2DescBufferAlign   = 5'd3,
    Usb2DescLength        = 5'd4,
    Usb2DescNextAlign     = 5'd5,
    Usb2DescChain         = 5'd6,
    Usb2DescFrameReserved = 5'd7,
    Usb2DescAddressWrap   = 5'd8
  } usb2_desc_error_e;

  localparam int unsigned USB2_DESC_BUFFER_WORD = 0;
  localparam int unsigned USB2_DESC_LENGTH_WORD = 1;
  localparam int unsigned USB2_DESC_NEXT_WORD = 2;
  localparam int unsigned USB2_DESC_CONTROL_WORD = 3;
  localparam int unsigned USB2_DESC_ACTUAL_WORD = 4;
  localparam int unsigned USB2_DESC_STATUS_WORD = 5;
  localparam int unsigned USB2_DESC_FRAME_WORD = 6;
  localparam int unsigned USB2_DESC_RESERVED_WORD = 7;

  localparam int unsigned USB2_DESC_OWN = 0;
  localparam int unsigned USB2_DESC_CHAIN = 1;
  localparam int unsigned USB2_DESC_END = 2;
  localparam int unsigned USB2_DESC_IRQ = 3;
  localparam int unsigned USB2_DESC_SHORT_OK = 4;
  localparam int unsigned USB2_DESC_ZERO_PACKET = 5;
  localparam int unsigned USB2_DESC_DONE = 16;
  localparam int unsigned USB2_DESC_SHORT = 17;
  // Completion ABI values are consumed by software.
  /* verilator lint_off UNUSEDPARAM */
  localparam int unsigned USB2_DESC_STALL = 18;
  localparam int unsigned USB2_DESC_TIMEOUT = 19;
  localparam int unsigned USB2_DESC_CRC_ERROR = 20;
  /* verilator lint_on UNUSEDPARAM */
  localparam int unsigned USB2_DESC_PROTOCOL_ERROR = 21;
  localparam int unsigned USB2_DESC_AXI_ERROR = 22;
  localparam int unsigned USB2_DESC_ABORTED = 23;

  localparam int unsigned USB2_WORK_ROLE_LSB = 0;
  localparam int unsigned USB2_WORK_INDEX_LSB = 2;
  localparam int unsigned USB2_WORK_DIRECTION_IN = 6;
  localparam int unsigned USB2_WORK_TYPE_LSB = 7;
  localparam int unsigned USB2_WORK_ADDRESS_LSB = 9;
  localparam int unsigned USB2_WORK_ENDPOINT_LSB = 16;
  localparam int unsigned USB2_WORK_SPEED_LSB = 20;
  localparam int unsigned USB2_WORK_RAM_BASE_LSB = 22;
  localparam int unsigned USB2_WORK_LENGTH_LSB = 34;
  localparam int unsigned USB2_WORK_SETUP = 49;
  localparam int unsigned USB2_WORK_CANCEL = 50;
  localparam int unsigned USB2_WORK_TOGGLE = 51;

  localparam int unsigned USB2_RESULT_ROLE_LSB = 0;
  localparam int unsigned USB2_RESULT_INDEX_LSB = 2;
  localparam int unsigned USB2_RESULT_DIRECTION_IN = 6;
  localparam int unsigned USB2_RESULT_CODE_LSB = 7;
  localparam int unsigned USB2_RESULT_LENGTH_LSB = 11;

  typedef enum logic [3:0] {
    Usb2ResultSuccess  = 4'd0,
    Usb2ResultNak      = 4'd1,
    Usb2ResultStall    = 4'd2,
    Usb2ResultTimeout  = 4'd3,
    Usb2ResultCrc      = 4'd4,
    Usb2ResultProtocol = 4'd5,
    Usb2ResultOverflow = 4'd6,
    Usb2ResultCanceled = 4'd7
  } usb2_result_e;

  function automatic logic [7:0] usb2_pid_byte(input usb2_pid_e pid_i);
    return {~4'(pid_i), 4'(pid_i)};
  endfunction

  function automatic logic usb2_pid_valid(input logic [7:0] pid_i);
    return pid_i[7:4] == ~pid_i[3:0];
  endfunction

  function automatic logic usb2_pid_is_token(input logic [3:0] pid_i);
    return (pid_i == Usb2PidOut) || (pid_i == Usb2PidIn) || (pid_i == Usb2PidSof) ||
           (pid_i == Usb2PidSetup) || (pid_i == Usb2PidPing);
  endfunction

  function automatic logic usb2_pid_is_data(input logic [3:0] pid_i);
    return (pid_i == Usb2PidData0) || (pid_i == Usb2PidData1) ||
           (pid_i == Usb2PidData2) || (pid_i == Usb2PidMdata);
  endfunction

  function automatic logic usb2_pid_is_handshake(input logic [3:0] pid_i);
    return (pid_i == Usb2PidAck) || (pid_i == Usb2PidNak) ||
           (pid_i == Usb2PidStall) || (pid_i == Usb2PidNyet);
  endfunction

  function automatic logic [4:0] usb2_crc5_next(input logic [4:0] crc_i, input logic data_i);
    logic feedback;
    begin
      feedback       = crc_i[0] ^ data_i;
      usb2_crc5_next = {feedback, crc_i[4], crc_i[3] ^ feedback, crc_i[2], crc_i[1]};
    end
  endfunction

  function automatic logic [4:0] usb2_token_crc5(input logic [10:0] token_i);
    logic [4:0] crc;
    begin
      crc = 5'h1F;
      for (int unsigned index = 0; index < 11; index++) begin
        crc = usb2_crc5_next(crc, token_i[index]);
      end
      return ~crc;
    end
  endfunction

  function automatic logic [15:0] usb2_crc16_next(input logic [15:0] crc_i, input logic data_i);
    logic feedback;
    begin
      feedback        = crc_i[0] ^ data_i;
      usb2_crc16_next = {1'b0, crc_i[15:1]};
      if (feedback) begin
        usb2_crc16_next = usb2_crc16_next ^ 16'hA001;
      end
    end
  endfunction

  function automatic logic [15:0] usb2_crc16_byte(input logic [15:0] crc_i,
                                                  input logic [7:0] data_i);
    logic [15:0] crc;
    begin
      crc = crc_i;
      for (int unsigned index = 0; index < 8; index++) begin
        crc = usb2_crc16_next(crc, data_i[index]);
      end
      return crc;
    end
  endfunction

  function automatic logic [15:0] usb2_crc16_finish(input logic [15:0] crc_i);
    return ~crc_i;
  endfunction

  function automatic logic usb2_range_wraps(input logic [31:0] addr_i, input logic [31:0] length_i);
    return (length_i != 32'd0) && (addr_i > (32'hFFFF_FFFF - (length_i - 1'b1)));
  endfunction

endpackage
