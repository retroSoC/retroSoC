// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// spisd is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
//

module spisd_core (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        rd_req_i,
    output logic        rd_vld_o,
    output logic [ 7:0] rd_data_o,
    input  logic        wr_req_i,
    output logic        wr_byte_done_o,
    input  logic [ 7:0] wr_data_i,
    input  logic [22:0] addr_i,
    output logic        init_done_o,
    output logic        spisd_sclk_o,
    output logic        spisd_cs_o,
    output logic        spisd_mosi_o,
    input  logic        spisd_miso_i
);

  localparam CMD0 = 8'h40;  // GO_IDLE_STATE
  localparam CMD8 = 8'h48;  // SEND_IF_COND
  localparam CMD17 = 8'h51;  // READ_SINGLE_BLOCK
  localparam CMD24 = 8'h58;  // WRITE_BLOCK
  localparam CMD55 = 8'h77;  // APP_CMD
  localparam CMD58 = 8'h7A;  // READ_OCR
  localparam ACMD41 = 8'h69;  // SD_SEND_OP_COND

  localparam FSM_RST = 5'd0;
  localparam FSM_RST2CMD0 = 5'd1;
  localparam FSM_CMD0 = 5'd2;
  localparam FSM_CMD8 = 5'd3;
  localparam FSM_CMD55 = 5'd4;
  localparam FSM_ACMD41 = 5'd5;
  localparam FSM_CHECK_INIT = 5'd6;
  localparam FSM_CMD58 = 5'd7;
  localparam FSM_IDLE = 5'd8;

  localparam FSM_SEND_CMD = 5'd9;
  localparam FSM_RESP_WAIT = 5'd10;
  localparam FSM_RESP_DATA = 5'd11;

  localparam FSM_READ_CMD = 5'd12;
  localparam FSM_READ_WAIT = 5'd13;
  localparam FSM_READ_DATA = 5'd14;
  localparam FSM_READ_CRC = 5'd15;

  localparam FSM_WRITE_CMD = 5'd16;
  localparam FSM_WRITE_INIT = 5'd17;
  localparam FSM_WRITE_DATA = 5'd18;
  localparam FSM_WRITE_BYTE = 5'd19;
  localparam FSM_WRITE_WAIT = 5'd20;

  logic [4:0] s_fsm_d, s_fsm_q;

  assign rd_vld_o       = '0;
  assign rd_data_o      = '0;
  assign wr_byte_done_o = '0;
  assign init_done_o    = '0;

  assign spisd_sclk_o   = '0;
  assign spisd_cs_o     = '1;
  assign spisd_mosi_o   = '0;

  dffr #(5) u_fsm_dffr (
      clk_i,
      rst_n_i,
      s_fsm_d,
      s_fsm_q
  );
endmodule
