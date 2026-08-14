// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

`include "axi4_define.svh"

module axi42ribp (
    input logic          clk_i,
    input logic          rst_n_i,
          axi4_if.slave  axi4,
          ribp_if.master ribp
);
  localparam logic [3:0] FSM_IDLE = 4'd0;
  localparam logic [3:0] FSM_WR_DATA = 4'd1;
  localparam logic [3:0] FSM_WR_REQ = 4'd2;
  localparam logic [3:0] FSM_WR_RESP = 4'd3;
  localparam logic [3:0] FSM_RD_REQ = 4'd4;
  localparam logic [3:0] FSM_RD_RESP = 4'd5;
  localparam logic [3:0] FSM_ERR_WR_DATA = 4'd6;
  localparam logic [3:0] FSM_ERR_WR_RESP = 4'd7;
  localparam logic [3:0] FSM_ERR_RD_RESP = 4'd8;

  logic [3:0] s_fsm_d, s_fsm_q;
  logic [31:0] s_addr_d, s_addr_q;
  logic [31:0] s_wdata_d, s_wdata_q;
  logic [3:0] s_wstrb_d, s_wstrb_q;
  logic s_id_d, s_id_q;
  logic [7:0] s_len_d, s_len_q;
  logic [7:0] s_beat_d, s_beat_q;
  logic [31:0] s_rdata_d, s_rdata_q;
  logic [1:0] s_resp_d, s_resp_q;
  logic s_write_legal, s_read_legal;
  logic s_aw_hdshk, s_w_hdshk, s_b_hdshk, s_ar_hdshk, s_r_hdshk;

  assign s_write_legal = (axi4.awlen == 8'd0) &&
                         (axi4.awburst == `AXI4_BURST_TYPE_INCR) && !axi4.awlock &&
                         (axi4.awsize <= `AXI4_BURST_SIZE_4BYTES) &&
                         ((axi4.awaddr & ((32'd1 << axi4.awsize) - 1'b1)) == '0);
  assign s_read_legal = (axi4.arlen == 8'd0) &&
                        (axi4.arburst == `AXI4_BURST_TYPE_INCR) && !axi4.arlock &&
                        (axi4.arsize <= `AXI4_BURST_SIZE_4BYTES) &&
                        ((axi4.araddr & ((32'd1 << axi4.arsize) - 1'b1)) == '0);

  assign axi4.awready = (s_fsm_q == FSM_IDLE) && !axi4.arvalid;
  assign axi4.arready = (s_fsm_q == FSM_IDLE);
  assign axi4.wready = (s_fsm_q == FSM_WR_DATA) || (s_fsm_q == FSM_ERR_WR_DATA);
  assign axi4.bid = s_id_q;
  assign axi4.bresp = s_resp_q;
  assign axi4.buser = '0;
  assign axi4.bvalid = (s_fsm_q == FSM_WR_RESP) || (s_fsm_q == FSM_ERR_WR_RESP);
  assign axi4.rid = s_id_q;
  assign axi4.rdata = (s_fsm_q == FSM_RD_RESP) ? s_rdata_q : '0;
  assign axi4.rresp = s_resp_q;
  assign axi4.rlast = (s_fsm_q == FSM_RD_RESP) ||
                      ((s_fsm_q == FSM_ERR_RD_RESP) && (s_beat_q == s_len_q));
  assign axi4.ruser = '0;
  assign axi4.rvalid = (s_fsm_q == FSM_RD_RESP) || (s_fsm_q == FSM_ERR_RD_RESP);

  assign s_aw_hdshk = axi4.awvalid && axi4.awready;
  assign s_w_hdshk = axi4.wvalid && axi4.wready;
  assign s_b_hdshk = axi4.bvalid && axi4.bready;
  assign s_ar_hdshk = axi4.arvalid && axi4.arready;
  assign s_r_hdshk = axi4.rvalid && axi4.rready;

  assign ribp.valid = (s_fsm_q == FSM_WR_REQ) || (s_fsm_q == FSM_RD_REQ);
  assign ribp.addr = {s_addr_q[31:2], 2'b00};
  assign ribp.wdata = s_wdata_q;
  assign ribp.wstrb = (s_fsm_q == FSM_WR_REQ) ? s_wstrb_q : '0;

  always_comb begin
    s_fsm_d   = s_fsm_q;
    s_addr_d  = s_addr_q;
    s_wdata_d = s_wdata_q;
    s_wstrb_d = s_wstrb_q;
    s_id_d    = s_id_q;
    s_len_d   = s_len_q;
    s_beat_d  = s_beat_q;
    s_rdata_d = s_rdata_q;
    s_resp_d  = s_resp_q;

    unique case (s_fsm_q)
      FSM_IDLE: begin
        s_beat_d = '0;
        s_resp_d = `AXI4_RESP_OKAY;
        if (s_ar_hdshk) begin
          s_addr_d = axi4.araddr;
          s_id_d   = axi4.arid;
          s_len_d  = axi4.arlen;
          s_fsm_d  = s_read_legal ? FSM_RD_REQ : FSM_ERR_RD_RESP;
          if (!s_read_legal) s_resp_d = `AXI4_RESP_SLAVE_ERROR;
        end else if (s_aw_hdshk) begin
          s_addr_d = axi4.awaddr;
          s_id_d   = axi4.awid;
          s_len_d  = axi4.awlen;
          s_fsm_d  = s_write_legal ? FSM_WR_DATA : FSM_ERR_WR_DATA;
          if (!s_write_legal) s_resp_d = `AXI4_RESP_SLAVE_ERROR;
        end
      end
      FSM_WR_DATA: begin
        if (s_w_hdshk) begin
          s_wdata_d = axi4.wdata;
          s_wstrb_d = axi4.wstrb;
          if (axi4.wlast) begin
            s_fsm_d = FSM_WR_REQ;
          end else begin
            s_resp_d = `AXI4_RESP_SLAVE_ERROR;
            s_fsm_d  = FSM_ERR_WR_DATA;
          end
        end
      end
      FSM_WR_REQ: begin
        if (ribp.ready) begin
          s_resp_d = ribp.resp_err ? `AXI4_RESP_SLAVE_ERROR : `AXI4_RESP_OKAY;
          s_fsm_d  = FSM_WR_RESP;
        end
      end
      FSM_WR_RESP: begin
        if (s_b_hdshk) s_fsm_d = FSM_IDLE;
      end
      FSM_RD_REQ: begin
        if (ribp.ready) begin
          s_rdata_d = ribp.rdata;
          s_resp_d  = ribp.resp_err ? `AXI4_RESP_SLAVE_ERROR : `AXI4_RESP_OKAY;
          s_fsm_d   = FSM_RD_RESP;
        end
      end
      FSM_RD_RESP: begin
        if (s_r_hdshk) s_fsm_d = FSM_IDLE;
      end
      FSM_ERR_WR_DATA: begin
        if (s_w_hdshk) begin
          if ((s_beat_q == s_len_q) || axi4.wlast) begin
            s_fsm_d = FSM_ERR_WR_RESP;
          end else begin
            s_beat_d = s_beat_q + 1'b1;
          end
        end
      end
      FSM_ERR_WR_RESP: begin
        if (s_b_hdshk) s_fsm_d = FSM_IDLE;
      end
      FSM_ERR_RD_RESP: begin
        if (s_r_hdshk) begin
          if (s_beat_q == s_len_q) begin
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
      .DATA_WIDTH(4)
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
  ) u_id_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_id_d),
      .dat_o  (s_id_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_len_d),
      .dat_o  (s_len_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_beat_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_beat_d),
      .dat_o  (s_beat_q)
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
      .DATA_WIDTH(2)
  ) u_resp_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_resp_d),
      .dat_o  (s_resp_q)
  );
endmodule
