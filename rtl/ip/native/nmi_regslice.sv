// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module nmi_regslice (
    // verilog_format: off
    input logic   clk_i,
    input logic   rst_n_i,
    nmi_if.slave  nmi_slv,
    nmi_if.master nmi_mst
    // verilog_format: on
);

  localparam FSM_IDLE = 2'd0;
  localparam FSM_REQ = 2'd1;
  localparam FSM_RESP = 2'd2;

  logic [1:0] s_fsm_d, s_fsm_q;
  logic s_nmi_mst_valid_d, s_nmi_mst_valid_q;
  logic [31:0] s_nmi_mst_addr_d, s_nmi_mst_addr_q;
  logic [31:0] s_nmi_mst_wdata_d, s_nmi_mst_wdata_q;
  logic [3:0] s_nmi_mst_wstrb_d, s_nmi_mst_wstrb_q;
  logic [31:0] s_nmi_mst_rdata_d, s_nmi_mst_rdata_q;
  logic s_nmi_mst_ready_d, s_nmi_mst_ready_q;
  // nmi mst if
  assign nmi_mst.valid = s_nmi_mst_valid_q;
  assign nmi_mst.addr  = s_nmi_mst_addr_q;
  assign nmi_mst.wdata = s_nmi_mst_wdata_q;
  assign nmi_mst.wstrb = s_nmi_mst_wstrb_q;


  always_comb begin
    s_fsm_d           = s_fsm_q;
    s_nmi_mst_valid_d = s_nmi_mst_valid_q;
    s_nmi_mst_addr_d  = s_nmi_mst_addr_q;
    s_nmi_mst_wdata_d = s_nmi_mst_wdata_q;
    s_nmi_mst_wstrb_d = s_nmi_mst_wstrb_q;
    s_nmi_mst_ready_d = s_nmi_mst_ready_q;
    s_nmi_mst_rdata_d = s_nmi_mst_rdata_q;
    nmi_slv.ready     = '0;
    nmi_slv.rdata     = '0;
    unique case (s_fsm_q)
      FSM_IDLE: begin
        if (nmi_slv.valid) begin
          s_fsm_d           = FSM_REQ;
          s_nmi_mst_valid_d = nmi_slv.valid;
          s_nmi_mst_addr_d  = nmi_slv.addr;
          s_nmi_mst_wdata_d = nmi_slv.wdata;
          s_nmi_mst_wstrb_d = nmi_slv.wstrb;
        end
      end
      FSM_REQ: begin
        if (nmi_mst.ready) begin
          s_fsm_d           = FSM_RESP;
          s_nmi_mst_valid_d = 1'b0;
          s_nmi_mst_ready_d = nmi_mst.ready;
          s_nmi_mst_rdata_d = nmi_mst.rdata;
        end
      end
      FSM_RESP: begin
        s_fsm_d       = FSM_IDLE;
        nmi_slv.ready = s_nmi_mst_ready_q;
        nmi_slv.rdata = s_nmi_mst_rdata_q;
      end
      default: begin
        s_fsm_d           = s_fsm_q;
        s_nmi_mst_valid_d = s_nmi_mst_valid_q;
        s_nmi_mst_addr_d  = s_nmi_mst_addr_q;
        s_nmi_mst_wdata_d = s_nmi_mst_wdata_q;
        s_nmi_mst_wstrb_d = s_nmi_mst_wstrb_q;
        s_nmi_mst_ready_d = s_nmi_mst_ready_q;
        s_nmi_mst_rdata_d = s_nmi_mst_rdata_q;
        nmi_slv.ready     = '0;
        nmi_slv.rdata     = '0;
      end
    endcase
  end
  dffr #(2) u_fsm_dffr (
      clk_i,
      rst_n_i,
      s_fsm_d,
      s_fsm_q
  );

  dffr #(1) u_nmi_mstr_valid_dffr (
      clk_i,
      rst_n_i,
      s_nmi_mst_valid_d,
      s_nmi_mst_valid_q
  );


  dffr #(32) u_nmi_mst_addr_dffr (
      clk_i,
      rst_n_i,
      s_nmi_mst_addr_d,
      s_nmi_mst_addr_q
  );


  dffr #(32) u_nmi_mst_wdata_dffr (
      clk_i,
      rst_n_i,
      s_nmi_mst_wdata_d,
      s_nmi_mst_wdata_q
  );


  dffr #(4) u_nmi_mst_wstrb_dffr (
      clk_i,
      rst_n_i,
      s_nmi_mst_wstrb_d,
      s_nmi_mst_wstrb_q
  );

  dffr #(32) u_nmi_mst_rdata_dffr (
      clk_i,
      rst_n_i,
      s_nmi_mst_rdata_d,
      s_nmi_mst_rdata_q
  );

  dffr #(1) u_nmi_mst_ready_dffr (
      clk_i,
      rst_n_i,
      s_nmi_mst_ready_d,
      s_nmi_mst_ready_q
  );

endmodule
