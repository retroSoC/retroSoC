// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module axi4l2ribp (
    // verilog_format: off -- preserve reviewed column alignment
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
    ribp_if.master      ribp
    // verilog_format: on
);

  // AXI-Lite requests are accepted only in each channel's idle state; one read
  // and one write may be outstanding. RIBP errors map to SLVERR responses.
  typedef enum logic [1:0] {
    RdIdle = 2'd0,
    RdData = 2'd1,
    RdWait = 2'd2
  } rd_state_e;
  typedef enum logic [1:0] {
    WrIdle = 2'd0,
    WrData = 2'd1,
    WrWait = 2'd2,
    WrResp = 2'd3
  } wr_state_e;
  localparam logic [1:0] AxiRespOkay = 2'b00;
  localparam logic [1:0] AxiRespSlvErr = 2'b10;

  rd_state_e s_rd_fsm_d, s_rd_fsm_q;
  wr_state_e s_wr_fsm_d, s_wr_fsm_q;

  logic [31:0] s_addr_d, s_addr_q;
  logic [31:0] s_rdata_d, s_rdata_q;
  logic [31:0] s_wdata_d, s_wdata_q;
  logic [3:0] s_wstrb_d, s_wstrb_q;
  logic [1:0] s_rresp_d, s_rresp_q;
  logic [1:0] s_bresp_d, s_bresp_q;
  logic s_rd_req, s_wr_req;

  always_comb begin
    s_rd_fsm_d = s_rd_fsm_q;
    case (s_rd_fsm_q)
      RdIdle: begin
        if (arvalid_i) s_rd_fsm_d = RdData;
      end
      RdData: begin
        if (ribp.ready) s_rd_fsm_d = RdWait;
      end
      RdWait: begin
        if (rready_i) s_rd_fsm_d = RdIdle;
      end
      default: s_rd_fsm_d = RdIdle;
    endcase
  end
  dffr #(
      .DATA_WIDTH(2)
  ) u_rd_fsm_dffr (
      .clk_i  (aclk_i),
      .rst_n_i(aresetn_i),
      .dat_i  (s_rd_fsm_d),
      .dat_o  (s_rd_fsm_q)
  );

  always_comb begin
    s_wr_fsm_d = s_wr_fsm_q;
    case (s_wr_fsm_q)
      WrIdle: begin
        if (awvalid_i) s_wr_fsm_d = WrData;
      end
      WrData: begin
        if (wvalid_i) s_wr_fsm_d = WrWait;
      end
      WrWait: begin
        if (ribp.ready) s_wr_fsm_d = WrResp;
      end
      WrResp: begin
        if (bready_i) s_wr_fsm_d = WrIdle;
      end
      default: s_wr_fsm_d = WrIdle;
    endcase
  end
  dffr #(
      .DATA_WIDTH(2)
  ) u_wr_fsm_dffr (
      .clk_i  (aclk_i),
      .rst_n_i(aresetn_i),
      .dat_i  (s_wr_fsm_d),
      .dat_o  (s_wr_fsm_q)
  );

  always_comb begin
    ribp.addr = s_addr_q;
    if (s_rd_fsm_q == RdIdle && arvalid_i) begin
      ribp.addr = araddr_i;
      s_addr_d  = araddr_i;
    end else if (s_wr_fsm_q == WrIdle && awvalid_i) begin
      ribp.addr = awaddr_i;
      s_addr_d  = awaddr_i;
    end
  end
  dffer #(
      .DATA_WIDTH(32)
  ) u_addr_dffer (
      .clk_i  (aclk_i),
      .rst_n_i(aresetn_i),
      .en_i   ((s_rd_fsm_q == RdIdle && arvalid_i) || (s_wr_fsm_q == WrIdle && awvalid_i)),
      .dat_i  (s_addr_d),
      .dat_o  (s_addr_q)
  );

  assign s_rdata_d = ribp.rdata;
  dffer #(
      .DATA_WIDTH(32)
  ) u_rdata_dffer (
      .clk_i  (aclk_i),
      .rst_n_i(aresetn_i),
      .en_i   (s_rd_fsm_q == RdData && ribp.ready),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );

  assign s_rresp_d = ribp.resp_err ? AxiRespSlvErr : AxiRespOkay;
  dffer #(
      .DATA_WIDTH(2)
  ) u_rresp_dffer (
      .clk_i  (aclk_i),
      .rst_n_i(aresetn_i),
      .en_i   (s_rd_fsm_q == RdData && ribp.ready),
      .dat_i  (s_rresp_d),
      .dat_o  (s_rresp_q)
  );

  assign s_wdata_d = wdata_i;
  dffer #(
      .DATA_WIDTH(32)
  ) u_wdata_dffer (
      .clk_i  (aclk_i),
      .rst_n_i(aresetn_i),
      .en_i   (s_wr_fsm_q == WrData && wvalid_i),
      .dat_i  (s_wdata_d),
      .dat_o  (s_wdata_q)
  );

  assign s_wstrb_d = wstrb_i;
  dffer #(
      .DATA_WIDTH(4)
  ) u_wstrb_dffer (
      .clk_i  (aclk_i),
      .rst_n_i(aresetn_i),
      .en_i   (s_wr_fsm_q == WrData && wvalid_i),
      .dat_i  (s_wstrb_d),
      .dat_o  (s_wstrb_q)
  );

  assign s_bresp_d = ribp.resp_err ? AxiRespSlvErr : AxiRespOkay;
  dffer #(
      .DATA_WIDTH(2)
  ) u_bresp_dffer (
      .clk_i  (aclk_i),
      .rst_n_i(aresetn_i),
      .en_i   (s_wr_fsm_q == WrWait && ribp.ready),
      .dat_i  (s_bresp_d),
      .dat_o  (s_bresp_q)
  );

  // axil
  assign arready_o  = s_rd_fsm_q == RdIdle && arvalid_i;
  assign rvalid_o   = s_rd_fsm_q == RdWait;
  assign rresp_o    = s_rresp_q;
  assign rdata_o    = s_rdata_q;

  assign awready_o  = s_wr_fsm_q == WrIdle && awvalid_i;
  assign wready_o   = s_wr_fsm_q == WrData && wvalid_i;
  assign bvalid_o   = s_wr_fsm_q == WrResp;
  assign bresp_o    = s_bresp_q;

  assign s_rd_req   = (s_rd_fsm_q == RdData || s_rd_fsm_q == RdWait);
  assign s_wr_req   = s_wr_fsm_q == WrWait;
  assign ribp.valid = s_rd_req || s_wr_req;
  assign ribp.wdata = s_wdata_q;
  assign ribp.wstrb = (s_wr_fsm_q == WrWait) ? s_wstrb_q : '0;
endmodule
