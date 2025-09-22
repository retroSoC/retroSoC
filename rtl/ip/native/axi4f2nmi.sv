// Copyright (c) 2023-2025 Miao Yuchi <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module axi4f2nmi (
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

    output logic        mem_valid_o,
    output logic        mem_instr_o,
    output logic [31:0] mem_addr_o,
    output logic [31:0] mem_wdata_o,
    output logic [ 3:0] mem_wstrb_o,
    input  logic        mem_ready_i,
    input  logic [31:0] mem_rdata_i
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

  logic [31:0] s_raddr_d, s_raddr_q;
  logic [31:0] s_waddr_d, s_waddr_q;
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
        if (mem_ready_i) s_rd_fsm_d = RD_WAIT;
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
        if (mem_ready_i) s_wr_fsm_d = WR_RESP;
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


  assign s_raddr_d = araddr_i;
  dffer #(32) u_raddr_dffer (
      aclk_i,
      aresetn_i,
      s_rd_fsm_q == RD_IDLE && arvalid_i,
      s_raddr_d,
      s_raddr_q
  );

  assign s_rdata_d = mem_rdata_i;
  dffer #(32) u_rdata_dffer (
      aclk_i,
      aresetn_i,
      s_rd_fsm_q == RD_DATA && mem_ready_i,
      s_rdata_d,
      s_rdata_q
  );


  assign s_waddr_d = awaddr_i;
  dffer #(32) u_waddr_dffer (
      aclk_i,
      aresetn_i,
      s_wr_fsm_q == WR_IDLE && awvalid_i,
      s_waddr_d,
      s_waddr_q
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
  assign arready_o   = s_rd_fsm_q == RD_IDLE && arvalid_i;
  assign rvalid_o    = s_rd_fsm_q == RD_WAIT;
  assign rresp_o     = '0;
  assign rdata_o     = s_rdata_q;

  assign awready_o   = s_wr_fsm_q == WR_IDLE && awvalid_i;
  assign wready_o    = s_wr_fsm_q == WR_DATA && wvalid_i;
  assign bvalid_o    = s_wr_fsm_q == WR_RESP;
  assign bresp_o     = '0;

  assign s_rd_req    = (s_rd_fsm_q == RD_DATA || s_rd_fsm_q == RD_WAIT);
  assign s_wr_req    = (s_wr_fsm_q == WR_WAIT || s_wr_fsm_q == WR_RESP);
  assign mem_valid_o = s_rd_req || s_wr_req;
  assign mem_instr_o = '0;
  assign mem_wdata_o = s_wdata_q;
  assign mem_wstrb_o = (s_wr_fsm_q == WR_WAIT) ? s_wstrb_q : '0;

  always_comb begin
    mem_addr_o = '0;
    if (s_rd_fsm_q == RD_IDLE && arvalid_i) begin
      mem_addr_o = araddr_i;
    end else if (s_rd_fsm_q == RD_DATA || s_rd_fsm_q == RD_WAIT) begin
      mem_addr_o = s_raddr_q;
    end else if (s_wr_fsm_q == WR_IDLE && awvalid_i) begin
      mem_addr_o = awaddr_i;
    end else if (s_wr_fsm_q == WR_DATA || s_wr_fsm_q == WR_WAIT || s_wr_fsm_q == WR_RESP) begin
      mem_addr_o = s_waddr_q;
    end
  end

endmodule
