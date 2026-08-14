// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// See LICENSE for the complete license text.

`include "axi4_define.svh"

module ribp2axi4 (
    input logic          clk_i,
    input logic          rst_n_i,
          ribp_if.slave  ribp,
          axi4_if.master axi4
);
  localparam logic [2:0] FSM_IDLE = 3'd0;
  localparam logic [2:0] FSM_WR_ADDR_DATA = 3'd1;
  localparam logic [2:0] FSM_WR_RESP = 3'd2;
  localparam logic [2:0] FSM_RD_ADDR = 3'd3;
  localparam logic [2:0] FSM_RD_RESP = 3'd4;

  logic [2:0] s_fsm_d, s_fsm_q;
  logic [31:0] s_addr_d, s_addr_q;
  logic [31:0] s_wdata_d, s_wdata_q;
  logic [3:0] s_wstrb_d, s_wstrb_q;
  logic s_aw_done_d, s_aw_done_q;
  logic s_w_done_d, s_w_done_q;
  logic [31:0] s_rdata_d, s_rdata_q;
  logic s_err_d, s_err_q;

  assign ribp.ready = ((s_fsm_q == FSM_WR_RESP) && axi4.bvalid) ||
                      ((s_fsm_q == FSM_RD_RESP) && axi4.rvalid);
  assign ribp.rdata = (s_fsm_q == FSM_RD_RESP) ? axi4.rdata : s_rdata_q;
  assign ribp.resp_err = ((s_fsm_q == FSM_WR_RESP) && axi4.bvalid) ?
                         (axi4.bresp != `AXI4_RESP_OKAY) :
                         ((s_fsm_q == FSM_RD_RESP) && axi4.rvalid) ?
                         (axi4.rresp != `AXI4_RESP_OKAY) : s_err_q;

  assign axi4.awid = '0;
  assign axi4.awaddr = s_addr_q;
  assign axi4.awlen = 8'd0;
  assign axi4.awsize = `AXI4_BURST_SIZE_4BYTES;
  assign axi4.awburst = `AXI4_BURST_TYPE_INCR;
  assign axi4.awlock = `AXI4_LOCK_NORM;
  assign axi4.awcache = `AXI4_CACHE_NO_BUF;
  assign axi4.awprot = `AXI4_PROT_DATA;
  assign axi4.awqos = `AXI4_QOS_NORMAL;
  assign axi4.awregion = `AXI4_REGION_NORMAL;
  assign axi4.awuser = '0;
  assign axi4.awvalid = (s_fsm_q == FSM_WR_ADDR_DATA) && !s_aw_done_q;
  assign axi4.wdata = s_wdata_q;
  assign axi4.wstrb = s_wstrb_q;
  assign axi4.wlast = 1'b1;
  assign axi4.wuser = '0;
  assign axi4.wvalid = (s_fsm_q == FSM_WR_ADDR_DATA) && !s_w_done_q;
  assign axi4.bready = (s_fsm_q == FSM_WR_RESP) && ribp.valid;
  assign axi4.arid = '0;
  assign axi4.araddr = s_addr_q;
  assign axi4.arlen = 8'd0;
  assign axi4.arsize = `AXI4_BURST_SIZE_4BYTES;
  assign axi4.arburst = `AXI4_BURST_TYPE_INCR;
  assign axi4.arlock = `AXI4_LOCK_NORM;
  assign axi4.arcache = `AXI4_CACHE_NO_BUF;
  assign axi4.arprot = `AXI4_PROT_DATA;
  assign axi4.arqos = `AXI4_QOS_NORMAL;
  assign axi4.arregion = `AXI4_REGION_NORMAL;
  assign axi4.aruser = '0;
  assign axi4.arvalid = (s_fsm_q == FSM_RD_ADDR);
  assign axi4.rready = (s_fsm_q == FSM_RD_RESP) && ribp.valid;

  always_comb begin
    s_fsm_d     = s_fsm_q;
    s_addr_d    = s_addr_q;
    s_wdata_d   = s_wdata_q;
    s_wstrb_d   = s_wstrb_q;
    s_aw_done_d = s_aw_done_q;
    s_w_done_d  = s_w_done_q;
    s_rdata_d   = s_rdata_q;
    s_err_d     = s_err_q;
    unique case (s_fsm_q)
      FSM_IDLE: begin
        s_aw_done_d = 1'b0;
        s_w_done_d  = 1'b0;
        s_err_d     = 1'b0;
        if (ribp.valid) begin
          s_addr_d  = {ribp.addr[31:2], 2'b00};
          s_wdata_d = ribp.wdata;
          s_wstrb_d = ribp.wstrb;
          s_fsm_d   = (|ribp.wstrb) ? FSM_WR_ADDR_DATA : FSM_RD_ADDR;
        end
      end
      FSM_WR_ADDR_DATA: begin
        if (axi4.awvalid && axi4.awready) s_aw_done_d = 1'b1;
        if (axi4.wvalid && axi4.wready) s_w_done_d = 1'b1;
        if ((s_aw_done_q || (axi4.awvalid && axi4.awready)) &&
            (s_w_done_q || (axi4.wvalid && axi4.wready))) begin
          s_fsm_d = FSM_WR_RESP;
        end
      end
      FSM_WR_RESP: begin
        if (axi4.bvalid && ribp.valid) begin
          s_err_d = axi4.bresp != `AXI4_RESP_OKAY;
          s_fsm_d = FSM_IDLE;
        end
      end
      FSM_RD_ADDR: begin
        if (axi4.arvalid && axi4.arready) s_fsm_d = FSM_RD_RESP;
      end
      FSM_RD_RESP: begin
        if (axi4.rvalid && ribp.valid) begin
          s_rdata_d = axi4.rdata;
          s_err_d   = axi4.rresp != `AXI4_RESP_OKAY;
          s_fsm_d   = FSM_IDLE;
        end
      end
      default: s_fsm_d = FSM_IDLE;
    endcase
  end

  dffr #(
      .DATA_WIDTH(3)
  ) u_fsm_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fsm_d),
      .dat_o  (s_fsm_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_addr_d),
      .dat_o  (s_addr_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_wdata_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_wdata_d),
      .dat_o  (s_wdata_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_wstrb_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_wstrb_d),
      .dat_o  (s_wstrb_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_aw_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_aw_done_d),
      .dat_o  (s_aw_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_w_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_w_done_d),
      .dat_o  (s_w_done_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_rdata_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
endmodule
