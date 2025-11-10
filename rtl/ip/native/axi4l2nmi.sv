// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module axi4l2nmi (
    // verilog_format: off
    input  logic        aclk_i,
    input  logic        aresetn_i,
    input  logic [31:0] awaddr_i,
    input  logic        awvalid_i,
    output logic        awready_o,
    input  logic [31:0] wdata_i,
    input  logic [ 3:0] wstrb_i,
    input  logic        wvalid_i,
    output logic        wready_o,
    output logic [ 1:0] bresp_o,
    output logic        bvalid_o,
    input  logic        bready_i,
    input  logic [31:0] araddr_i,
    input  logic        arvalid_i,
    output logic        arready_o,
    output logic [31:0] rdata_o,
    output logic [ 1:0] rresp_o,
    output logic        rvalid_o,
    input  logic        rready_i,
    nmi_if.master       nmi
    // verilog_format: on
);

  localparam [1:0] RD_IDLE = 2'd0;
  localparam [1:0] RD_DATA = 2'd1;
  localparam [1:0] RD_WAIT = 2'd2;

  localparam [1:0] WR_IDLE = 2'd0;
  localparam [1:0] WR_DATA = 2'd1;
  localparam [1:0] WR_WAIT = 2'd2;
  localparam [1:0] WR_RESP = 2'd3;

  logic [1:0] s_rd_fsm_d, s_rd_fsm_q;
  logic [1:0] s_wr_fsm_d, s_wr_fsm_q;

  logic [31:0] s_addr_d, s_addr_q;
  logic [31:0] s_rdata_d, s_rdata_q;
  logic [31:0] s_wdata_d, s_wdata_q;
  logic [3:0] s_wstrb_d, s_wstrb_q;
  logic s_rd_req, s_wr_req;

  always_comb begin
    s_rd_fsm_d = s_rd_fsm_q;
    case (s_rd_fsm_q)
      RD_IDLE: begin
        if (arvalid_i) s_rd_fsm_d = RD_DATA;
      end
      RD_DATA: begin
        if (nmi.ready) s_rd_fsm_d = RD_WAIT;
      end
      RD_WAIT: begin
        if (rready_i) s_rd_fsm_d = RD_IDLE;
      end
      default: s_rd_fsm_d = RD_IDLE;
    endcase
  end
  dffr #(2) u_rd_fsm_dffr (
      aclk_i,
      aresetn_i,
      s_rd_fsm_d,
      s_rd_fsm_q
  );

  always_comb begin
    s_wr_fsm_d = s_wr_fsm_q;
    case (s_wr_fsm_q)
      WR_IDLE: begin
        if (awvalid_i) s_wr_fsm_d = WR_DATA;
      end
      WR_DATA: begin
        if (wvalid_i) s_wr_fsm_d = WR_WAIT;
      end
      WR_WAIT: begin
        if (nmi.ready) s_wr_fsm_d = WR_RESP;
      end
      WR_RESP: begin
        if (bready_i) s_wr_fsm_d = WR_IDLE;
      end
      default: s_wr_fsm_d = WR_IDLE;
    endcase
  end
  dffr #(2) u_wr_fsm_dffr (
      aclk_i,
      aresetn_i,
      s_wr_fsm_d,
      s_wr_fsm_q
  );

  always_comb begin
    nmi.addr = s_addr_q;
    if (s_rd_fsm_q == RD_IDLE && arvalid_i) begin
      nmi.addr = araddr_i;
      s_addr_d = araddr_i;
    end else if (s_wr_fsm_q == WR_IDLE && awvalid_i) begin
      nmi.addr = awaddr_i;
      s_addr_d = awaddr_i;
    end
  end
  dffer #(32) u_addr_dffer (
      aclk_i,
      aresetn_i,
      (s_rd_fsm_q == RD_IDLE && arvalid_i) || (s_wr_fsm_q == WR_IDLE && awvalid_i),
      s_addr_d,
      s_addr_q
  );

  assign s_rdata_d = nmi.rdata;
  dffer #(32) u_rdata_dffer (
      aclk_i,
      aresetn_i,
      s_rd_fsm_q == RD_DATA && nmi.ready,
      s_rdata_d,
      s_rdata_q
  );

  assign s_wdata_d = wdata_i;
  dffer #(32) u_wdata_dffer (
      aclk_i,
      aresetn_i,
      s_wr_fsm_q == WR_DATA && wvalid_i,
      s_wdata_d,
      s_wdata_q
  );

  assign s_wstrb_d = wstrb_i;
  dffer #(4) u_wstrb_dffer (
      aclk_i,
      aresetn_i,
      s_wr_fsm_q == WR_DATA && wvalid_i,
      s_wstrb_d,
      s_wstrb_q
  );

  // axil
  assign arready_o = s_rd_fsm_q == RD_IDLE && arvalid_i;
  assign rvalid_o  = s_rd_fsm_q == RD_WAIT;
  assign rresp_o   = '0;
  assign rdata_o   = s_rdata_q;

  assign awready_o = s_wr_fsm_q == WR_IDLE && awvalid_i;
  assign wready_o  = s_wr_fsm_q == WR_DATA && wvalid_i;
  assign bvalid_o  = s_wr_fsm_q == WR_RESP;
  assign bresp_o   = '0;

  assign s_rd_req  = (s_rd_fsm_q == RD_DATA || s_rd_fsm_q == RD_WAIT);
  assign s_wr_req  = s_wr_fsm_q == WR_WAIT;
  assign nmi.valid = s_rd_req || s_wr_req;
  assign nmi.wdata = s_wdata_q;
  assign nmi.wstrb = (s_wr_fsm_q == WR_WAIT) ? s_wstrb_q : '0;
endmodule
