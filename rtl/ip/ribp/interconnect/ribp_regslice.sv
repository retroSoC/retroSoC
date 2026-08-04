// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module ribp_regslice (
    // verilog_format: off
    input logic   clk_i,
    input logic   rst_n_i,
    ribp_if.slave  ribp_slv,
    ribp_if.master ribp_mst
    // verilog_format: on
);

  localparam FSM_IDLE = 2'd0;
  localparam FSM_REQ = 2'd1;
  localparam FSM_RESP = 2'd2;

  logic [1:0] s_fsm_d, s_fsm_q;
  logic s_ribp_mst_valid_d, s_ribp_mst_valid_q;
  logic [31:0] s_ribp_mst_addr_d, s_ribp_mst_addr_q;
  logic [31:0] s_ribp_mst_wdata_d, s_ribp_mst_wdata_q;
  logic [3:0] s_ribp_mst_wstrb_d, s_ribp_mst_wstrb_q;
  logic [31:0] s_ribp_mst_rdata_d, s_ribp_mst_rdata_q;
  logic s_ribp_mst_ready_d, s_ribp_mst_ready_q;
  // ribp mst if
  assign ribp_mst.valid = s_ribp_mst_valid_q;
  assign ribp_mst.addr  = s_ribp_mst_addr_q;
  assign ribp_mst.wdata = s_ribp_mst_wdata_q;
  assign ribp_mst.wstrb = s_ribp_mst_wstrb_q;


  always_comb begin
    s_fsm_d            = s_fsm_q;
    s_ribp_mst_valid_d = s_ribp_mst_valid_q;
    s_ribp_mst_addr_d  = s_ribp_mst_addr_q;
    s_ribp_mst_wdata_d = s_ribp_mst_wdata_q;
    s_ribp_mst_wstrb_d = s_ribp_mst_wstrb_q;
    s_ribp_mst_ready_d = s_ribp_mst_ready_q;
    s_ribp_mst_rdata_d = s_ribp_mst_rdata_q;
    ribp_slv.ready     = '0;
    ribp_slv.rdata     = '0;
    unique case (s_fsm_q)
      FSM_IDLE: begin
        if (ribp_slv.valid) begin
          s_fsm_d            = FSM_REQ;
          s_ribp_mst_valid_d = ribp_slv.valid;
          s_ribp_mst_addr_d  = ribp_slv.addr;
          s_ribp_mst_wdata_d = ribp_slv.wdata;
          s_ribp_mst_wstrb_d = ribp_slv.wstrb;
        end
      end
      FSM_REQ: begin
        if (ribp_mst.ready) begin
          s_fsm_d            = FSM_RESP;
          s_ribp_mst_valid_d = 1'b0;
          s_ribp_mst_ready_d = ribp_mst.ready;
          s_ribp_mst_rdata_d = ribp_mst.rdata;
        end
      end
      FSM_RESP: begin
        s_fsm_d        = FSM_IDLE;
        ribp_slv.ready = s_ribp_mst_ready_q;
        ribp_slv.rdata = s_ribp_mst_rdata_q;
      end
      default: begin
        s_fsm_d            = s_fsm_q;
        s_ribp_mst_valid_d = s_ribp_mst_valid_q;
        s_ribp_mst_addr_d  = s_ribp_mst_addr_q;
        s_ribp_mst_wdata_d = s_ribp_mst_wdata_q;
        s_ribp_mst_wstrb_d = s_ribp_mst_wstrb_q;
        s_ribp_mst_ready_d = s_ribp_mst_ready_q;
        s_ribp_mst_rdata_d = s_ribp_mst_rdata_q;
        ribp_slv.ready     = '0;
        ribp_slv.rdata     = '0;
      end
    endcase
  end
  dffr #(2) u_fsm_dffr (
      clk_i,
      rst_n_i,
      s_fsm_d,
      s_fsm_q
  );

  dffr #(1) u_ribp_mstr_valid_dffr (
      clk_i,
      rst_n_i,
      s_ribp_mst_valid_d,
      s_ribp_mst_valid_q
  );


  dffr #(32) u_ribp_mst_addr_dffr (
      clk_i,
      rst_n_i,
      s_ribp_mst_addr_d,
      s_ribp_mst_addr_q
  );


  dffr #(32) u_ribp_mst_wdata_dffr (
      clk_i,
      rst_n_i,
      s_ribp_mst_wdata_d,
      s_ribp_mst_wdata_q
  );


  dffr #(4) u_ribp_mst_wstrb_dffr (
      clk_i,
      rst_n_i,
      s_ribp_mst_wstrb_d,
      s_ribp_mst_wstrb_q
  );

  dffr #(32) u_ribp_mst_rdata_dffr (
      clk_i,
      rst_n_i,
      s_ribp_mst_rdata_d,
      s_ribp_mst_rdata_q
  );

  dffr #(1) u_ribp_mst_ready_dffr (
      clk_i,
      rst_n_i,
      s_ribp_mst_ready_d,
      s_ribp_mst_ready_q
  );

endmodule
