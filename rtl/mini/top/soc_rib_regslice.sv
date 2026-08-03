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

module soc_rib_regslice (
    // verilog_format: off
    input logic       clk_i,
    input logic       rst_n_i,
    soc_rib_if.slave  rib_slv,
    soc_rib_if.master rib_mst
    // verilog_format: on
);

  localparam logic [1:0] FSM_IDLE = 2'd0;
  localparam logic [1:0] FSM_REQ = 2'd1;
  localparam logic [1:0] FSM_RESP = 2'd2;

  logic [1:0] s_fsm_d, s_fsm_q;
  logic s_rib_mst_valid_d, s_rib_mst_valid_q;
  logic [31:0] s_rib_mst_addr_d, s_rib_mst_addr_q;
  logic [31:0] s_rib_mst_wdata_d, s_rib_mst_wdata_q;
  logic [3:0] s_rib_mst_wstrb_d, s_rib_mst_wstrb_q;
  logic [31:0] s_rib_mst_rdata_d, s_rib_mst_rdata_q;
  logic s_rib_mst_ready_d, s_rib_mst_ready_q;
  logic s_rib_mst_resp_err_d, s_rib_mst_resp_err_q;

  assign rib_mst.valid = s_rib_mst_valid_q;
  assign rib_mst.addr  = s_rib_mst_addr_q;
  assign rib_mst.wdata = s_rib_mst_wdata_q;
  assign rib_mst.wstrb = s_rib_mst_wstrb_q;

  always_comb begin
    s_fsm_d              = s_fsm_q;
    s_rib_mst_valid_d    = s_rib_mst_valid_q;
    s_rib_mst_addr_d     = s_rib_mst_addr_q;
    s_rib_mst_wdata_d    = s_rib_mst_wdata_q;
    s_rib_mst_wstrb_d    = s_rib_mst_wstrb_q;
    s_rib_mst_ready_d    = s_rib_mst_ready_q;
    s_rib_mst_rdata_d    = s_rib_mst_rdata_q;
    s_rib_mst_resp_err_d = s_rib_mst_resp_err_q;
    rib_slv.ready        = 1'b0;
    rib_slv.rdata        = '0;
    rib_slv.resp_err     = 1'b0;
    unique case (s_fsm_q)
      FSM_IDLE: begin
        if (rib_slv.valid) begin
          s_fsm_d           = FSM_REQ;
          s_rib_mst_valid_d = 1'b1;
          s_rib_mst_addr_d  = rib_slv.addr;
          s_rib_mst_wdata_d = rib_slv.wdata;
          s_rib_mst_wstrb_d = rib_slv.wstrb;
        end
      end
      FSM_REQ: begin
        if (rib_mst.ready) begin
          s_fsm_d              = FSM_RESP;
          s_rib_mst_valid_d    = 1'b0;
          s_rib_mst_ready_d    = 1'b1;
          s_rib_mst_rdata_d    = rib_mst.rdata;
          s_rib_mst_resp_err_d = rib_mst.resp_err;
        end
      end
      FSM_RESP: begin
        s_fsm_d          = FSM_IDLE;
        rib_slv.ready    = s_rib_mst_ready_q;
        rib_slv.rdata    = s_rib_mst_rdata_q;
        rib_slv.resp_err = s_rib_mst_resp_err_q;
      end
      default: s_fsm_d = FSM_IDLE;
    endcase
  end

  dffr #(2) u_fsm_dffr (
      clk_i,
      rst_n_i,
      s_fsm_d,
      s_fsm_q
  );
  dffr #(1) u_rib_mstr_valid_dffr (
      clk_i,
      rst_n_i,
      s_rib_mst_valid_d,
      s_rib_mst_valid_q
  );
  dffr #(32) u_rib_mst_addr_dffr (
      clk_i,
      rst_n_i,
      s_rib_mst_addr_d,
      s_rib_mst_addr_q
  );
  dffr #(32) u_rib_mst_wdata_dffr (
      clk_i,
      rst_n_i,
      s_rib_mst_wdata_d,
      s_rib_mst_wdata_q
  );
  dffr #(4) u_rib_mst_wstrb_dffr (
      clk_i,
      rst_n_i,
      s_rib_mst_wstrb_d,
      s_rib_mst_wstrb_q
  );
  dffr #(32) u_rib_mst_rdata_dffr (
      clk_i,
      rst_n_i,
      s_rib_mst_rdata_d,
      s_rib_mst_rdata_q
  );
  dffr #(1) u_rib_mst_ready_dffr (
      clk_i,
      rst_n_i,
      s_rib_mst_ready_d,
      s_rib_mst_ready_q
  );
  dffr #(1) u_rib_mst_resp_err_dffr (
      clk_i,
      rst_n_i,
      s_rib_mst_resp_err_d,
      s_rib_mst_resp_err_q
  );

endmodule
