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

module axi4_error_slave #(
    parameter logic [1:0] Response = `AXI4_RESP_DECODE_ERROR
) (
    input logic         clk_i,
    input logic         rst_n_i,
          axi4_if.slave axi4
);
  localparam logic [1:0] FSM_IDLE = 2'd0;
  localparam logic [1:0] FSM_WRITE = 2'd1;
  localparam logic [1:0] FSM_WRITE_RESP = 2'd2;
  localparam logic [1:0] FSM_READ_RESP = 2'd3;

  logic [1:0] s_fsm_d, s_fsm_q;
  logic s_id_d, s_id_q;
  logic [7:0] s_len_d, s_len_q;
  logic [7:0] s_beat_d, s_beat_q;

  assign axi4.awready = (s_fsm_q == FSM_IDLE) && !axi4.arvalid;
  assign axi4.arready = (s_fsm_q == FSM_IDLE);
  assign axi4.wready  = (s_fsm_q == FSM_WRITE);
  assign axi4.bid     = s_id_q;
  assign axi4.bresp   = Response;
  assign axi4.buser   = '0;
  assign axi4.bvalid  = (s_fsm_q == FSM_WRITE_RESP);
  assign axi4.rid     = s_id_q;
  assign axi4.rdata   = '0;
  assign axi4.rresp   = Response;
  assign axi4.rlast   = (s_beat_q == s_len_q);
  assign axi4.ruser   = '0;
  assign axi4.rvalid  = (s_fsm_q == FSM_READ_RESP);

  always_comb begin
    s_fsm_d  = s_fsm_q;
    s_id_d   = s_id_q;
    s_len_d  = s_len_q;
    s_beat_d = s_beat_q;
    unique case (s_fsm_q)
      FSM_IDLE: begin
        s_beat_d = '0;
        if (axi4.arvalid && axi4.arready) begin
          s_id_d  = axi4.arid;
          s_len_d = axi4.arlen;
          s_fsm_d = FSM_READ_RESP;
        end else if (axi4.awvalid && axi4.awready) begin
          s_id_d  = axi4.awid;
          s_len_d = axi4.awlen;
          s_fsm_d = FSM_WRITE;
        end
      end
      FSM_WRITE: begin
        if (axi4.wvalid && axi4.wready) begin
          if ((s_beat_q == s_len_q) || axi4.wlast) begin
            s_fsm_d = FSM_WRITE_RESP;
          end else begin
            s_beat_d = s_beat_q + 1'b1;
          end
        end
      end
      FSM_WRITE_RESP: begin
        if (axi4.bvalid && axi4.bready) s_fsm_d = FSM_IDLE;
      end
      FSM_READ_RESP: begin
        if (axi4.rvalid && axi4.rready) begin
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
      .DATA_WIDTH(2)
  ) u_fsm_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fsm_d),
      .dat_o  (s_fsm_q)
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
endmodule
