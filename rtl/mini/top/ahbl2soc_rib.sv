// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "soc_rib_defs.svh"

// Management-core AHB-Lite to SoC RIB bridge. It is intentionally separate
// from the managed-compatible ahbl2rib used by externally supplied user cores.
module ahbl2soc_rib (
    ahbl_if.slave     ahbl,
    soc_rib_if.master rib
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

  assign ahbl.hready = s_fsm_q == STATE_IDLE || rib.ready;
  assign ahbl.hresp  = rib.ready && rib.resp_err ? AHBL_RESP_ERROR : AHBL_RESP_OKAY;
  assign ahbl.hrdata = rib.rdata;
  assign rib.valid   = s_fsm_q != STATE_IDLE;
  assign rib.addr    = {s_haddr_q[31:2], 2'b00};

  always_comb begin
    rib.wstrb = '0;
    rib.wdata = '0;
    if (s_hwrite_q) begin
      unique case (s_hsize_q)
        AHBL_SIZE_BYTE: begin
          unique case (s_haddr_q[1:0])
            2'd0: begin
              rib.wstrb = 4'b0001;
              rib.wdata = {24'd0, ahbl.hwdata[7:0]};
            end
            2'd1: begin
              rib.wstrb = 4'b0010;
              rib.wdata = {16'd0, ahbl.hwdata[7:0], 8'd0};
            end
            2'd2: begin
              rib.wstrb = 4'b0100;
              rib.wdata = {8'd0, ahbl.hwdata[7:0], 16'd0};
            end
            default: begin
              rib.wstrb = 4'b1000;
              rib.wdata = {ahbl.hwdata[7:0], 24'd0};
            end
          endcase
        end
        AHBL_SIZE_HWRD: begin
          if (s_haddr_q[1]) begin
            rib.wstrb = 4'b1100;
            rib.wdata = {ahbl.hwdata[15:0], 16'd0};
          end else begin
            rib.wstrb = 4'b0011;
            rib.wdata = {16'd0, ahbl.hwdata[15:0]};
          end
        end
        default: begin
          rib.wstrb = 4'b1111;
          rib.wdata = ahbl.hwdata;
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
        if (!rib.ready) begin
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
        if (rib.ready) begin
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
      ahbl.hclk,
      ahbl.hresetn,
      s_fsm_d,
      s_fsm_q
  );
  dffr #(32) u_haddr_dffr (
      ahbl.hclk,
      ahbl.hresetn,
      s_haddr_d,
      s_haddr_q
  );
  dffr #(1) u_hwrite_dffr (
      ahbl.hclk,
      ahbl.hresetn,
      s_hwrite_d,
      s_hwrite_q
  );
  dffr #(3) u_hsize_dffr (
      ahbl.hclk,
      ahbl.hresetn,
      s_hsize_d,
      s_hsize_q
  );

endmodule
