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

module ribp2rib #(
    parameter bit SYNC_RESET = 1'b0
) (
    input logic         clk_i,
    input logic         rst_n_i,
          ribp_if.slave ribp,
          rib_if.master rib
);

  localparam logic [1:0] FSM_CMD = 2'd0;
  localparam logic [1:0] FSM_WDATA = 2'd1;
  localparam logic [1:0] FSM_RESP = 2'd2;

  logic [1:0] s_fsm_d, s_fsm_q;
  logic [31:0] s_wdata_q;
  logic [ 3:0] s_wstrb_q;
  logic        s_cmd_hdshk;

  assign s_cmd_hdshk   = rib.cmd_valid && rib.cmd_ready;

  assign rib.cmd_valid = s_fsm_q == FSM_CMD && ribp.valid;
  assign rib.cmd_addr  = ribp.addr;
  assign rib.cmd_write = |ribp.wstrb;
  assign rib.cmd_len   = `RIB_LEN_INCR1;
  assign rib.w_valid   = s_fsm_q == FSM_WDATA;
  assign rib.wdata     = s_wdata_q;
  assign rib.wstrb     = s_wstrb_q;
  assign rib.wlast     = 1'b1;
  assign rib.rsp_ready = s_fsm_q == FSM_RESP;

  assign ribp.ready    = s_fsm_q == FSM_RESP && rib.rsp_valid;
  assign ribp.rdata    = rib.rdata;
  assign ribp.resp_err = ribp.ready && rib.resp_err;

  always_comb begin
    s_fsm_d = s_fsm_q;
    unique case (s_fsm_q)
      FSM_CMD: begin
        if (s_cmd_hdshk) begin
          s_fsm_d = rib.cmd_write ? FSM_WDATA : FSM_RESP;
        end
      end
      FSM_WDATA: begin
        if (rib.w_valid && rib.w_ready) begin
          s_fsm_d = FSM_RESP;
        end
      end
      FSM_RESP: begin
        if (rib.rsp_valid) begin
          s_fsm_d = FSM_CMD;
        end
      end
      default: s_fsm_d = FSM_CMD;
    endcase
  end

  if (SYNC_RESET) begin : GEN_SYNC_RESET
    dffsr #(
        .DATA_WIDTH(2)
    ) u_fsm_dffsr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_fsm_d),
        .dat_o  (s_fsm_q)
    );
    dffesr #(
        .DATA_WIDTH(32)
    ) u_wdata_dffesr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (s_cmd_hdshk),
        .dat_i  (ribp.wdata),
        .dat_o  (s_wdata_q)
    );
    dffesr #(
        .DATA_WIDTH(4)
    ) u_wstrb_dffesr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (s_cmd_hdshk),
        .dat_i  (ribp.wstrb),
        .dat_o  (s_wstrb_q)
    );
  end else begin : GEN_ASYNC_RESET
    dffr #(
        .DATA_WIDTH(2)
    ) u_fsm_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_fsm_d),
        .dat_o  (s_fsm_q)
    );
    dffer #(
        .DATA_WIDTH(32)
    ) u_wdata_dffer (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (s_cmd_hdshk),
        .dat_i  (ribp.wdata),
        .dat_o  (s_wdata_q)
    );
    dffer #(
        .DATA_WIDTH(4)
    ) u_wstrb_dffer (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (s_cmd_hdshk),
        .dat_i  (ribp.wstrb),
        .dat_o  (s_wstrb_q)
    );
  end

endmodule
