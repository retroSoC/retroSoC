// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

package psram_pkg;

  localparam logic [7:0] PSRAM_OPCODE_READ = 8'h03;
  localparam logic [7:0] PSRAM_OPCODE_FAST_READ = 8'h0B;
  localparam logic [7:0] PSRAM_OPCODE_QUAD_READ = 8'hEB;
  localparam logic [7:0] PSRAM_OPCODE_WRITE = 8'h02;
  localparam logic [7:0] PSRAM_OPCODE_QUAD_WRITE = 8'h38;
  localparam logic [7:0] PSRAM_OPCODE_ENTER_QPI = 8'h35;
  localparam logic [7:0] PSRAM_OPCODE_EXIT_QPI = 8'hF5;
  localparam logic [7:0] PSRAM_OPCODE_RESET_ENABLE = 8'h66;
  localparam logic [7:0] PSRAM_OPCODE_RESET = 8'h99;
  localparam logic [7:0] PSRAM_OPCODE_TOGGLE_WRAP = 8'hC0;
  localparam logic [7:0] PSRAM_OPCODE_READ_ID = 8'h9F;

  localparam logic [7:0] PSRAM_KGD_PASS = 8'h5D;
  localparam logic [7:0] PSRAM_DENSITY_64MBIT = 8'h26;

  typedef enum logic [3:0] {
    PsramCmdRead        = 4'd0,
    PsramCmdFastRead    = 4'd1,
    PsramCmdQuadRead    = 4'd2,
    PsramCmdWrite       = 4'd3,
    PsramCmdQuadWrite   = 4'd4,
    PsramCmdEnterQpi    = 4'd5,
    PsramCmdExitQpi     = 4'd6,
    PsramCmdResetEnable = 4'd7,
    PsramCmdReset       = 4'd8,
    PsramCmdToggleWrap  = 4'd9,
    PsramCmdReadId      = 4'd10
  } psram_cmd_e;

  typedef enum logic [3:0] {
    PsramErrorNone        = 4'd0,
    PsramErrorIllegal     = 4'd1,
    PsramErrorUnavailable = 4'd2,
    PsramErrorTimeout     = 4'd3,
    PsramErrorId          = 4'd4,
    PsramErrorAborted     = 4'd5,
    PsramErrorPhy         = 4'd6,
    PsramErrorProtocol    = 4'd7
  } psram_error_e;

  function automatic logic [7:0] psram_opcode(input psram_cmd_e command);
    unique case (command)
      PsramCmdRead:        return PSRAM_OPCODE_READ;
      PsramCmdFastRead:    return PSRAM_OPCODE_FAST_READ;
      PsramCmdQuadRead:    return PSRAM_OPCODE_QUAD_READ;
      PsramCmdWrite:       return PSRAM_OPCODE_WRITE;
      PsramCmdQuadWrite:   return PSRAM_OPCODE_QUAD_WRITE;
      PsramCmdEnterQpi:    return PSRAM_OPCODE_ENTER_QPI;
      PsramCmdExitQpi:     return PSRAM_OPCODE_EXIT_QPI;
      PsramCmdResetEnable: return PSRAM_OPCODE_RESET_ENABLE;
      PsramCmdReset:       return PSRAM_OPCODE_RESET;
      PsramCmdToggleWrap:  return PSRAM_OPCODE_TOGGLE_WRAP;
      PsramCmdReadId:      return PSRAM_OPCODE_READ_ID;
      default:             return 8'h00;
    endcase
  endfunction

  function automatic logic psram_command_has_address(input psram_cmd_e command);
    return (command == PsramCmdRead) || (command == PsramCmdFastRead) ||
           (command == PsramCmdQuadRead) || (command == PsramCmdWrite) ||
           (command == PsramCmdQuadWrite) || (command == PsramCmdReadId);
  endfunction

  function automatic logic psram_command_is_read(input psram_cmd_e command);
    return (command == PsramCmdRead) || (command == PsramCmdFastRead) ||
           (command == PsramCmdQuadRead) || (command == PsramCmdReadId);
  endfunction

  function automatic logic psram_command_is_write(input psram_cmd_e command);
    return (command == PsramCmdWrite) || (command == PsramCmdQuadWrite);
  endfunction

endpackage
