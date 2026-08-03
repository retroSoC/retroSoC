// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "soc_rib_defs.svh"

module soc_rib_legacy_to_burst #(
    parameter bit SYNC_RESET = 1'b0
) (
    input logic                   clk_i,
    input logic                   rst_n_i,
          soc_rib_if.slave        legacy,
          soc_rib_burst_if.master burst
);

  localparam logic [1:0] FSM_CMD = 2'd0;
  localparam logic [1:0] FSM_WDATA = 2'd1;
  localparam logic [1:0] FSM_RESP = 2'd2;

  logic [1:0] s_fsm_d, s_fsm_q;
  logic [31:0] s_wdata_q;
  logic [ 3:0] s_wstrb_q;
  logic        s_cmd_hdshk;

  assign s_cmd_hdshk     = burst.cmd_valid && burst.cmd_ready;

  assign burst.cmd_valid = s_fsm_q == FSM_CMD && legacy.valid;
  assign burst.cmd_addr  = legacy.addr;
  assign burst.cmd_write = |legacy.wstrb;
  assign burst.cmd_len   = `SOC_RIB_BURST_INCR1;
  assign burst.w_valid   = s_fsm_q == FSM_WDATA;
  assign burst.wdata     = s_wdata_q;
  assign burst.wstrb     = s_wstrb_q;
  assign burst.wlast     = 1'b1;
  assign burst.rsp_ready = s_fsm_q == FSM_RESP;

  assign legacy.ready    = s_fsm_q == FSM_RESP && burst.rsp_valid;
  assign legacy.rdata    = burst.rdata;
  assign legacy.resp_err = legacy.ready && burst.resp_err;

  always_comb begin
    s_fsm_d = s_fsm_q;
    unique case (s_fsm_q)
      FSM_CMD: begin
        if (s_cmd_hdshk) begin
          s_fsm_d = burst.cmd_write ? FSM_WDATA : FSM_RESP;
        end
      end
      FSM_WDATA: begin
        if (burst.w_valid && burst.w_ready) begin
          s_fsm_d = FSM_RESP;
        end
      end
      FSM_RESP: begin
        if (burst.rsp_valid) begin
          s_fsm_d = FSM_CMD;
        end
      end
      default: s_fsm_d = FSM_CMD;
    endcase
  end

  if (SYNC_RESET) begin : GEN_SYNC_RESET
    dffsr #(2) u_fsm_dffsr (
        clk_i,
        rst_n_i,
        s_fsm_d,
        s_fsm_q
    );
    dffesr #(32) u_wdata_dffesr (
        clk_i,
        rst_n_i,
        s_cmd_hdshk,
        legacy.wdata,
        s_wdata_q
    );
    dffesr #(4) u_wstrb_dffesr (
        clk_i,
        rst_n_i,
        s_cmd_hdshk,
        legacy.wstrb,
        s_wstrb_q
    );
  end else begin : GEN_ASYNC_RESET
    dffr #(2) u_fsm_dffr (
        clk_i,
        rst_n_i,
        s_fsm_d,
        s_fsm_q
    );
    dffer #(32) u_wdata_dffer (
        clk_i,
        rst_n_i,
        s_cmd_hdshk,
        legacy.wdata,
        s_wdata_q
    );
    dffer #(4) u_wstrb_dffer (
        clk_i,
        rst_n_i,
        s_cmd_hdshk,
        legacy.wstrb,
        s_wstrb_q
    );
  end

endmodule
