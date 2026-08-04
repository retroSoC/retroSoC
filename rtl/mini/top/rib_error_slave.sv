// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module rib_error_slave (
    input logic              clk_i,
    input logic              rst_n_i,
    input logic        [2:0] error_code_i,
          rib_if.slave       rib
);

  localparam logic [1:0] FSM_CMD = 2'd0;
  localparam logic [1:0] FSM_WDATA = 2'd1;
  localparam logic [1:0] FSM_RESP = 2'd2;

  logic [1:0] s_fsm_d, s_fsm_q;
  logic [1:0] s_len_q;
  logic [1:0] s_beat_d, s_beat_q;
  logic [2:0] s_error_code_q;

  assign rib.cmd_ready = s_fsm_q == FSM_CMD;
  assign rib.w_ready   = s_fsm_q == FSM_WDATA;
  assign rib.rsp_valid = s_fsm_q == FSM_RESP;
  assign rib.rdata     = '0;
  assign rib.resp_err  = 1'b1;
  assign rib.resp_code = s_error_code_q;
  assign rib.rsp_beat  = s_beat_q;
  assign rib.rsp_last  = 1'b1;

  always_comb begin
    s_fsm_d  = s_fsm_q;
    s_beat_d = s_beat_q;
    unique case (s_fsm_q)
      FSM_CMD: begin
        if (rib.cmd_valid) begin
          s_beat_d = '0;
          s_fsm_d  = rib.cmd_write ? FSM_WDATA : FSM_RESP;
        end
      end
      FSM_WDATA: begin
        if (rib.w_valid) begin
          if (rib.wlast || (s_beat_q == s_len_q)) begin
            s_fsm_d = FSM_RESP;
          end else begin
            s_beat_d = s_beat_q + 1'b1;
          end
        end
      end
      FSM_RESP: begin
        if (rib.rsp_ready) begin
          s_fsm_d = FSM_CMD;
        end
      end
      default: s_fsm_d = FSM_CMD;
    endcase
  end

  dffr #(2) u_fsm_dffr (
      clk_i,
      rst_n_i,
      s_fsm_d,
      s_fsm_q
  );
  dffer #(2) u_len_dffer (
      clk_i,
      rst_n_i,
      rib.cmd_valid && rib.cmd_ready,
      rib.cmd_len,
      s_len_q
  );
  dffer #(3) u_error_code_dffer (
      clk_i,
      rst_n_i,
      rib.cmd_valid && rib.cmd_ready,
      error_code_i,
      s_error_code_q
  );
  dffr #(2) u_beat_dffr (
      clk_i,
      rst_n_i,
      s_beat_d,
      s_beat_q
  );

endmodule
