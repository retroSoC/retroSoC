// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

package xpi_pkg;

  localparam logic [31:0] XPI_ID_VALUE = 32'h5850_4932;
  localparam logic [31:0] XPI_VERSION_VALUE = 32'h0002_0000;
  localparam logic [31:0] XPI_CAPABILITY_VALUE = 32'h0404_1010;

  localparam logic [31:0] XPI_WINDOW_BASE = 32'h5000_0000;
  localparam logic [31:0] XPI_WINDOW_SIZE = 32'h1000_0000;
  localparam logic [31:0] XPI_SLOT_SIZE = 32'h0400_0000;
  localparam logic [31:0] XPI_BOOT_SIZE = 32'h0100_0000;

  typedef enum logic [3:0] {
    XpiInstrStop     = 4'h0,
    XpiInstrCommand  = 4'h1,
    XpiInstrAddress  = 4'h2,
    XpiInstrMode     = 4'h3,
    XpiInstrDummy    = 4'h4,
    XpiInstrTransmit = 4'h5,
    XpiInstrReceive  = 4'h6,
    XpiInstrJumpOnCs = 4'h7
  } xpi_instr_opcode_e;

  typedef enum logic [3:0] {
    XpiErrorNone     = 4'd0,
    XpiErrorIllegal  = 4'd1,
    XpiErrorDisabled = 4'd2,
    XpiErrorRange    = 4'd3,
    XpiErrorSequence = 4'd4,
    XpiErrorTimeout  = 4'd5,
    XpiErrorAborted  = 4'd6,
    XpiErrorFifo     = 4'd7,
    XpiErrorDma      = 4'd8
  } xpi_error_e;

  function automatic logic [15:0] xpi_instr(input xpi_instr_opcode_e opcode, input logic [1:0] pads,
                                            input logic [7:0] operand);
    return {opcode, pads, 2'b00, operand};
  endfunction

  function automatic logic [2:0] xpi_pad_count(input logic [1:0] pads);
    unique case (pads)
      2'd0:    return 3'd1;
      2'd1:    return 3'd2;
      2'd2:    return 3'd4;
      default: return 3'd0;
    endcase
  endfunction

endpackage
