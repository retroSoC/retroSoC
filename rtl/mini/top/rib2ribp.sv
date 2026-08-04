// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "rib_defs.svh"

module rib2ribp (
    input logic                  clk_i,
    input logic                  rst_n_i,
          rib_if.slave           rib,
          ribp_if.master         ribp
);

  localparam logic [2:0] FSM_CMD = 3'd0;
  localparam logic [2:0] FSM_WDATA = 3'd1;
  localparam logic [2:0] FSM_RIBP = 3'd2;
  localparam logic [2:0] FSM_RESP = 3'd3;
  localparam logic [2:0] FSM_DROP_WDATA = 3'd4;

  logic [2:0] s_fsm_d, s_fsm_q;
  logic [31:0] s_addr_d, s_addr_q;
  logic [31:0] s_wdata_q;
  logic [ 3:0] s_wstrb_q;
  logic [1:0] s_len_d, s_len_q;
  logic [1:0] s_beat_d, s_beat_q;
  logic s_write_d, s_write_q;
  logic [31:0] s_rdata_q;
  logic s_error_d, s_error_q;
  logic [2:0] s_error_code_d, s_error_code_q;
  logic s_cmd_legal;
  logic s_cmd_hdshk, s_w_hdshk, s_ribp_hdshk, s_rsp_hdshk;

  assign s_cmd_legal = (rib.cmd_len == `RIB_LEN_INCR1) ||
                       ((rib.cmd_len == `RIB_LEN_INCR4) &&
                        (rib.cmd_addr[3:0] == 4'b0000));
  assign s_cmd_hdshk = rib.cmd_valid && rib.cmd_ready;
  assign s_w_hdshk = rib.w_valid && rib.w_ready;
  assign s_ribp_hdshk = ribp.valid && ribp.ready;
  assign s_rsp_hdshk = rib.rsp_valid && rib.rsp_ready;

  assign rib.cmd_ready = s_fsm_q == FSM_CMD;
  assign rib.w_ready = (s_fsm_q == FSM_WDATA) || (s_fsm_q == FSM_DROP_WDATA);
  assign rib.rsp_valid = s_fsm_q == FSM_RESP;
  assign rib.rdata = s_rdata_q;
  assign rib.resp_err = s_error_q;
  assign rib.resp_code = s_error_q ? s_error_code_q : `RIB_RESP_OK;
  assign rib.rsp_beat = s_beat_q;
  assign rib.rsp_last = s_write_q || (s_beat_q == s_len_q) || s_error_q;

  assign ribp.valid = s_fsm_q == FSM_RIBP;
  assign ribp.addr = s_addr_q;
  assign ribp.wdata = s_wdata_q;
  assign ribp.wstrb = s_write_q ? s_wstrb_q : '0;

  always_comb begin
    s_fsm_d        = s_fsm_q;
    s_addr_d       = s_addr_q;
    s_len_d        = s_len_q;
    s_beat_d       = s_beat_q;
    s_write_d      = s_write_q;
    s_error_d      = s_error_q;
    s_error_code_d = s_error_code_q;
    unique case (s_fsm_q)
      FSM_CMD: begin
        if (s_cmd_hdshk) begin
          s_addr_d       = rib.cmd_addr;
          s_len_d        = rib.cmd_len;
          s_beat_d       = '0;
          s_write_d      = rib.cmd_write;
          s_error_d      = ~s_cmd_legal;
          s_error_code_d = s_cmd_legal ? `RIB_RESP_OK : `RIB_RESP_BURSTERR;
          if (~s_cmd_legal) begin
            s_fsm_d = rib.cmd_write ? FSM_DROP_WDATA : FSM_RESP;
          end else begin
            s_fsm_d = rib.cmd_write ? FSM_WDATA : FSM_RIBP;
          end
        end
      end
      FSM_WDATA: begin
        if (s_w_hdshk) begin
          if (rib.wlast != (s_beat_q == s_len_q)) begin
            s_error_d      = 1'b1;
            s_error_code_d = `RIB_RESP_BURSTERR;
            s_fsm_d        = FSM_RESP;
          end else begin
            s_fsm_d = FSM_RIBP;
          end
        end
      end
      FSM_RIBP: begin
        if (s_ribp_hdshk) begin
          if (ribp.resp_err) begin
            s_error_d      = 1'b1;
            s_error_code_d = `RIB_RESP_SLVERR;
            s_fsm_d        = FSM_RESP;
          end else if (s_write_q) begin
            if (s_beat_q == s_len_q) begin
              s_fsm_d = FSM_RESP;
            end else begin
              s_addr_d = s_addr_q + 32'd4;
              s_beat_d = s_beat_q + 1'b1;
              s_fsm_d  = FSM_WDATA;
            end
          end else begin
            s_fsm_d = FSM_RESP;
          end
        end
      end
      FSM_RESP: begin
        if (s_rsp_hdshk) begin
          if (~s_write_q && ~s_error_q && (s_beat_q != s_len_q)) begin
            s_addr_d = s_addr_q + 32'd4;
            s_beat_d = s_beat_q + 1'b1;
            s_fsm_d  = FSM_RIBP;
          end else begin
            s_fsm_d = FSM_CMD;
          end
        end
      end
      FSM_DROP_WDATA: begin
        if (s_w_hdshk) begin
          if (rib.wlast || (s_beat_q == s_len_q)) begin
            s_fsm_d = FSM_RESP;
          end else begin
            s_beat_d = s_beat_q + 1'b1;
          end
        end
      end
      default: s_fsm_d = FSM_CMD;
    endcase
  end

  dffr #(3) u_fsm_dffr (
      clk_i,
      rst_n_i,
      s_fsm_d,
      s_fsm_q
  );
  dffr #(32) u_addr_dffr (
      clk_i,
      rst_n_i,
      s_addr_d,
      s_addr_q
  );
  dffr #(2) u_len_dffr (
      clk_i,
      rst_n_i,
      s_len_d,
      s_len_q
  );
  dffr #(2) u_beat_dffr (
      clk_i,
      rst_n_i,
      s_beat_d,
      s_beat_q
  );
  dffr #(1) u_write_dffr (
      clk_i,
      rst_n_i,
      s_write_d,
      s_write_q
  );
  dffer #(32) u_wdata_dffer (
      clk_i,
      rst_n_i,
      s_w_hdshk && s_fsm_q == FSM_WDATA,
      rib.wdata,
      s_wdata_q
  );
  dffer #(4) u_wstrb_dffer (
      clk_i,
      rst_n_i,
      s_w_hdshk && s_fsm_q == FSM_WDATA,
      rib.wstrb,
      s_wstrb_q
  );
  dffer #(32) u_rdata_dffer (
      clk_i,
      rst_n_i,
      s_ribp_hdshk && ~s_write_q,
      ribp.rdata,
      s_rdata_q
  );
  dffr #(1) u_error_dffr (
      clk_i,
      rst_n_i,
      s_error_d,
      s_error_q
  );
  dffr #(3) u_error_code_dffr (
      clk_i,
      rst_n_i,
      s_error_code_d,
      s_error_code_q
  );

endmodule
