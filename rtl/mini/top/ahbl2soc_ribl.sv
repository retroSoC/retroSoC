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
// from the managed-compatible ahbl2ribp used by externally supplied user cores.
module ahbl2soc_ribl (
    ahbl_if.slave      ahbl,
    soc_ribl_if.master ribl
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

  assign ahbl.hready = s_fsm_q == STATE_IDLE || ribl.ready;
  assign ahbl.hresp  = ribl.ready && ribl.resp_err ? AHBL_RESP_ERROR : AHBL_RESP_OKAY;
  assign ahbl.hrdata = ribl.rdata;
  assign ribl.valid  = s_fsm_q != STATE_IDLE;
  assign ribl.addr   = {s_haddr_q[31:2], 2'b00};

  always_comb begin
    ribl.wstrb = '0;
    ribl.wdata = '0;
    if (s_hwrite_q) begin
      unique case (s_hsize_q)
        AHBL_SIZE_BYTE: begin
          unique case (s_haddr_q[1:0])
            2'd0: begin
              ribl.wstrb = 4'b0001;
              ribl.wdata = {24'd0, ahbl.hwdata[7:0]};
            end
            2'd1: begin
              ribl.wstrb = 4'b0010;
              ribl.wdata = {16'd0, ahbl.hwdata[7:0], 8'd0};
            end
            2'd2: begin
              ribl.wstrb = 4'b0100;
              ribl.wdata = {8'd0, ahbl.hwdata[7:0], 16'd0};
            end
            default: begin
              ribl.wstrb = 4'b1000;
              ribl.wdata = {ahbl.hwdata[7:0], 24'd0};
            end
          endcase
        end
        AHBL_SIZE_HWRD: begin
          if (s_haddr_q[1]) begin
            ribl.wstrb = 4'b1100;
            ribl.wdata = {ahbl.hwdata[15:0], 16'd0};
          end else begin
            ribl.wstrb = 4'b0011;
            ribl.wdata = {16'd0, ahbl.hwdata[15:0]};
          end
        end
        default: begin
          ribl.wstrb = 4'b1111;
          ribl.wdata = ahbl.hwdata;
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
        if (!ribl.ready) begin
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
        if (ribl.ready) begin
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
