// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "rib_defs.svh"

// Management-core AHB-Lite to scalar RIBP bridge.
module ahbl2ribp (
           ahbl_if.slave  ahbl,
           ribp_if.master ribp,
    output logic          idle_o
);

  localparam logic [1:0] AHBL_TRANS_NSEQ = 2'b10;
  localparam logic [2:0] AHBL_SIZE_BYTE = 3'b000;
  localparam logic [2:0] AHBL_SIZE_HWRD = 3'b001;
  localparam logic AHBL_RESP_OKAY = 1'b0;
  localparam logic AHBL_RESP_ERROR = 1'b1;
  localparam logic [1:0] STATE_IDLE = 2'd0;
  localparam logic [1:0] STATE_DATA = 2'd1;
  localparam logic [1:0] STATE_WAIT = 2'd2;

  logic [1:0] s_fsm_d, s_fsm_q;
  logic [31:0] s_haddr_d, s_haddr_q;
  logic s_hwrite_d, s_hwrite_q;
  logic [2:0] s_hsize_d, s_hsize_q;

  assign ahbl.hready = s_fsm_q == STATE_IDLE || ribp.ready;
  assign ahbl.hresp  = ribp.ready && ribp.resp_err ? AHBL_RESP_ERROR : AHBL_RESP_OKAY;
  assign ahbl.hrdata = ribp.rdata;
  assign ribp.valid  = s_fsm_q != STATE_IDLE;
  assign ribp.addr   = {s_haddr_q[31:2], 2'b00};
  assign idle_o      = s_fsm_q == STATE_IDLE;

  always_comb begin
    ribp.wstrb = '0;
    ribp.wdata = '0;
    if (s_hwrite_q) begin
      unique case (s_hsize_q)
        AHBL_SIZE_BYTE: begin
          unique case (s_haddr_q[1:0])
            2'd0: begin
              ribp.wstrb = 4'b0001;
              ribp.wdata = {24'd0, ahbl.hwdata[7:0]};
            end
            2'd1: begin
              ribp.wstrb = 4'b0010;
              ribp.wdata = {16'd0, ahbl.hwdata[7:0], 8'd0};
            end
            2'd2: begin
              ribp.wstrb = 4'b0100;
              ribp.wdata = {8'd0, ahbl.hwdata[7:0], 16'd0};
            end
            default: begin
              ribp.wstrb = 4'b1000;
              ribp.wdata = {ahbl.hwdata[7:0], 24'd0};
            end
          endcase
        end
        AHBL_SIZE_HWRD: begin
          if (s_haddr_q[1]) begin
            ribp.wstrb = 4'b1100;
            ribp.wdata = {ahbl.hwdata[15:0], 16'd0};
          end else begin
            ribp.wstrb = 4'b0011;
            ribp.wdata = {16'd0, ahbl.hwdata[15:0]};
          end
        end
        default: begin
          ribp.wstrb = 4'b1111;
          ribp.wdata = ahbl.hwdata;
        end
      endcase
    end
  end

  always_comb begin
    s_fsm_d    = s_fsm_q;
    s_haddr_d  = s_haddr_q;
    s_hwrite_d = s_hwrite_q;
    s_hsize_d  = s_hsize_q;
    unique case (s_fsm_q)
      STATE_IDLE: begin
        if (ahbl.htrans == AHBL_TRANS_NSEQ && ahbl.hready) begin
          s_fsm_d    = STATE_DATA;
          s_haddr_d  = ahbl.haddr;
          s_hwrite_d = ahbl.hwrite;
          s_hsize_d  = ahbl.hsize;
        end
      end
      STATE_DATA: begin
        if (!ribp.ready) begin
          s_fsm_d = STATE_WAIT;
        end else if (ahbl.htrans == AHBL_TRANS_NSEQ) begin
          s_haddr_d  = ahbl.haddr;
          s_hwrite_d = ahbl.hwrite;
          s_hsize_d  = ahbl.hsize;
        end else begin
          s_fsm_d = STATE_IDLE;
        end
      end
      STATE_WAIT: begin
        if (ribp.ready) begin
          if (ahbl.htrans == AHBL_TRANS_NSEQ) begin
            s_fsm_d    = STATE_DATA;
            s_haddr_d  = ahbl.haddr;
            s_hwrite_d = ahbl.hwrite;
            s_hsize_d  = ahbl.hsize;
          end else begin
            s_fsm_d = STATE_IDLE;
          end
        end
      end
      default: s_fsm_d = STATE_IDLE;
    endcase
  end

  dffr #(2) u_fsm_dffr (
      .clk_i  (ahbl.hclk),
      .rst_n_i(ahbl.hresetn),
      .dat_i  (s_fsm_d),
      .dat_o  (s_fsm_q)
  );
  dffr #(32) u_haddr_dffr (
      .clk_i  (ahbl.hclk),
      .rst_n_i(ahbl.hresetn),
      .dat_i  (s_haddr_d),
      .dat_o  (s_haddr_q)
  );
  dffr #(1) u_hwrite_dffr (
      .clk_i  (ahbl.hclk),
      .rst_n_i(ahbl.hresetn),
      .dat_i  (s_hwrite_d),
      .dat_o  (s_hwrite_q)
  );
  dffr #(3) u_hsize_dffr (
      .clk_i  (ahbl.hclk),
      .rst_n_i(ahbl.hresetn),
      .dat_i  (s_hsize_d),
      .dat_o  (s_hsize_q)
  );

endmodule
