// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
// See LICENSE for the complete license text.

`include "axi4_define.svh"
`include "rib_defs.svh"

module rib2axi4 (
    input logic          clk_i,
    input logic          rst_n_i,
          rib_if.slave   rib,
          axi4_if.master axi4
);
  localparam logic [2:0] FSM_IDLE = 3'd0;
  localparam logic [2:0] FSM_WR_ADDR = 3'd1;
  localparam logic [2:0] FSM_WR_DATA = 3'd2;
  localparam logic [2:0] FSM_WR_RESP = 3'd3;
  localparam logic [2:0] FSM_RD_ADDR = 3'd4;
  localparam logic [2:0] FSM_RD_RESP = 3'd5;

  logic [2:0] s_fsm_d, s_fsm_q;
  logic [31:0] s_addr_d, s_addr_q;
  logic [1:0] s_len_d, s_len_q;
  logic [1:0] s_beat_d, s_beat_q;
  logic s_aw_done_d, s_aw_done_q;

  assign rib.cmd_ready = s_fsm_q == FSM_IDLE;
  assign rib.w_ready = (s_fsm_q == FSM_WR_DATA) && axi4.wready;
  assign rib.rsp_valid = ((s_fsm_q == FSM_WR_RESP) && axi4.bvalid) ||
                         ((s_fsm_q == FSM_RD_RESP) && axi4.rvalid);
  assign rib.rdata = axi4.rdata;
  assign rib.resp_err = (s_fsm_q == FSM_WR_RESP) ?
                        (axi4.bresp != `AXI4_RESP_OKAY) :
                        (axi4.rresp != `AXI4_RESP_OKAY);
  assign rib.resp_code = !rib.resp_err ? `RIB_RESP_OK :
                         ((s_fsm_q == FSM_WR_RESP) ? axi4.bresp : axi4.rresp) ==
                                 `AXI4_RESP_DECODE_ERROR ?
                             `RIB_RESP_DECERR :
                             `RIB_RESP_SLVERR;
  assign rib.rsp_beat = s_beat_q;
  assign rib.rsp_last = (s_fsm_q == FSM_WR_RESP) || axi4.rlast;

  assign axi4.awid = '0;
  assign axi4.awaddr = s_addr_q;
  assign axi4.awlen = {6'd0, s_len_q};
  assign axi4.awsize = `AXI4_BURST_SIZE_4BYTES;
  assign axi4.awburst = `AXI4_BURST_TYPE_INCR;
  assign axi4.awlock = `AXI4_LOCK_NORM;
  assign axi4.awcache = `AXI4_CACHE_NO_BUF;
  assign axi4.awprot = `AXI4_PROT_DATA;
  assign axi4.awqos = `AXI4_QOS_NORMAL;
  assign axi4.awregion = `AXI4_REGION_NORMAL;
  assign axi4.awuser = '0;
  assign axi4.awvalid = (s_fsm_q == FSM_WR_ADDR) && !s_aw_done_q;
  assign axi4.wdata = rib.wdata;
  assign axi4.wstrb = rib.wstrb;
  assign axi4.wlast = s_beat_q == s_len_q;
  assign axi4.wuser = '0;
  assign axi4.wvalid = (s_fsm_q == FSM_WR_DATA) && rib.w_valid;
  assign axi4.bready = (s_fsm_q == FSM_WR_RESP) && rib.rsp_ready;

  assign axi4.arid = '0;
  assign axi4.araddr = s_addr_q;
  assign axi4.arlen = {6'd0, s_len_q};
  assign axi4.arsize = `AXI4_BURST_SIZE_4BYTES;
  assign axi4.arburst = `AXI4_BURST_TYPE_INCR;
  assign axi4.arlock = `AXI4_LOCK_NORM;
  assign axi4.arcache = `AXI4_CACHE_NO_BUF;
  assign axi4.arprot = `AXI4_PROT_DATA;
  assign axi4.arqos = `AXI4_QOS_NORMAL;
  assign axi4.arregion = `AXI4_REGION_NORMAL;
  assign axi4.aruser = '0;
  assign axi4.arvalid = s_fsm_q == FSM_RD_ADDR;
  assign axi4.rready = (s_fsm_q == FSM_RD_RESP) && rib.rsp_ready;

  always_comb begin
    s_fsm_d     = s_fsm_q;
    s_addr_d    = s_addr_q;
    s_len_d     = s_len_q;
    s_beat_d    = s_beat_q;
    s_aw_done_d = s_aw_done_q;

    unique case (s_fsm_q)
      FSM_IDLE: begin
        s_beat_d    = '0;
        s_aw_done_d = 1'b0;
        if (rib.cmd_valid && rib.cmd_ready) begin
          s_addr_d = rib.cmd_addr;
          s_len_d  = rib.cmd_len;
          s_fsm_d  = rib.cmd_write ? FSM_WR_ADDR : FSM_RD_ADDR;
        end
      end
      FSM_WR_ADDR: begin
        if (axi4.awvalid && axi4.awready) begin
          s_aw_done_d = 1'b1;
          s_fsm_d     = FSM_WR_DATA;
        end
      end
      FSM_WR_DATA: begin
        if (axi4.wvalid && axi4.wready) begin
          if (s_beat_q == s_len_q) begin
            s_fsm_d = FSM_WR_RESP;
          end else begin
            s_beat_d = s_beat_q + 1'b1;
          end
        end
      end
      FSM_WR_RESP: begin
        if (axi4.bvalid && rib.rsp_ready) s_fsm_d = FSM_IDLE;
      end
      FSM_RD_ADDR: begin
        if (axi4.arvalid && axi4.arready) s_fsm_d = FSM_RD_RESP;
      end
      FSM_RD_RESP: begin
        if (axi4.rvalid && rib.rsp_ready) begin
          if (axi4.rlast) begin
            s_fsm_d = FSM_IDLE;
          end else begin
            s_beat_d = s_beat_q + 1'b1;
          end
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
      .DATA_WIDTH(2)
  ) u_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_len_d),
      .dat_o  (s_len_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_beat_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_beat_d),
      .dat_o  (s_beat_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_aw_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_aw_done_d),
      .dat_o  (s_aw_done_q)
  );
endmodule
