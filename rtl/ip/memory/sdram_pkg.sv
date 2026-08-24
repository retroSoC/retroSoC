// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

package sdram_pkg;
  // verilog_format: off -- preserve reviewed column alignment
  typedef enum logic [3:0] {
    SdramErrNone        = 4'd0,
    SdramErrAxiDecode   = 4'd1,
    SdramErrAxiIllegal  = 4'd2,
    SdramErrInitFail    = 4'd3,
    SdramErrTiming      = 4'd4,
    SdramErrCommandBusy = 4'd5
  } sdram_error_e;

  typedef enum logic [3:0] {
    SdramCmdMrs   = 4'b0000,
    SdramCmdAct   = 4'b0011,
    SdramCmdRead  = 4'b0101,
    SdramCmdWrite = 4'b0100,
    SdramCmdBst   = 4'b0110,
    SdramCmdPre   = 4'b0010,
    SdramCmdRef   = 4'b0001,
    SdramCmdNop   = 4'b0111
  } sdram_cmd_e;

  typedef enum logic [1:0] {
    SdramBankIdle        = 2'd0,
    SdramBankActivating  = 2'd1,
    SdramBankOpen        = 2'd2,
    SdramBankPrecharging = 2'd3
  } sdram_bank_state_e;
  // verilog_format: on

  function automatic logic [7:0] sdram_min_cycles(input logic [7:0] value);
    return (value == 8'd0) ? 8'd1 : value;
  endfunction

  function automatic logic [15:0] sdram_min_cycles16(input logic [15:0] value);
    return (value == 16'd0) ? 16'd1 : value;
  endfunction
endpackage
