// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

package opipsram_pkg;

  typedef enum logic [3:0] {
    OpipsramErrorNone        = 4'd0,
    OpipsramErrorIllegal     = 4'd1,
    OpipsramErrorUnavailable = 4'd2,
    OpipsramErrorTimeout     = 4'd3,
    OpipsramErrorProfile     = 4'd4,
    OpipsramErrorAborted     = 4'd5,
    OpipsramErrorPhy         = 4'd6,
    OpipsramErrorProtocol    = 4'd7,
    OpipsramErrorBounds      = 4'd8,
    OpipsramErrorTraining    = 4'd9
  } opipsram_error_e;

  typedef struct packed {
    logic        profile_hyper;
    logic        write;
    logic        indirect_register;
    logic [31:0] addr;
    logic [3:0]  len;
    logic [63:0] wdata;
    logic [15:0] opi_cmd;
    logic        opi_width16;
    logic [31:0] opi_timing;
    logic [31:0] hyper_timing;
    logic [31:0] cs_timing;
    logic [31:0] clk_config;
    logic [7:0]  rx_delay;
    logic [31:0] timeout;
  } opipsram_cmd_t;

  typedef struct packed {
    logic        error;
    logic [63:0] rdata;
  } opipsram_rsp_t;

  localparam int OPIPSRAM_CMD_WIDTH = $bits(opipsram_cmd_t);
  localparam int OPIPSRAM_RSP_WIDTH = $bits(opipsram_rsp_t);

endpackage
