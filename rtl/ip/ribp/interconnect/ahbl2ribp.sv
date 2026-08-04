// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.


module ahbl2ribp (
    ahbl_if.slave  ahbl,
    ribp_if.master ribp
);

  localparam AHBL_TRANS_IDLE = 2'b00;
  localparam AHBL_TRANS_BUSY = 2'b01;
  localparam AHBL_TRANS_NSEQ = 2'b10;
  localparam AHBL_TRANS_SEQ = 2'b11;

  localparam AHBL_SIZE_BYTE = 3'b000;
  localparam AHBL_SIZE_HWRD = 3'b001;
  localparam AHBL_SIZE_WORD = 3'b010;

  localparam AHBL_RESP_OKAY = 1'b0;
  localparam AHBL_RESP_EROR = 1'b1;

  localparam STATE_IDLE = 2'b00;
  localparam STATE_DATA = 2'b01;
  localparam STATE_WAIT = 2'b10;


  logic [1:0] s_fsm_d, s_fsm_q;
  // req
  logic [31:0] s_haddr_d, s_haddr_q;
  logic s_hwrite_d, s_hwrite_q;
  logic [2:0] s_hsize_d, s_hsize_q;

  // ahbl if
  // NOTE: need to gurantee `ahbl.hready` and `ahbl.hrdata` sampled in same cycle
  assign ahbl.hready = (s_fsm_q == STATE_IDLE) || ribp.ready;
  assign ahbl.hresp  = AHBL_RESP_OKAY;
  assign ahbl.hrdata = ribp.rdata;

  // ribp if
  assign ribp.valid  = s_fsm_q != STATE_IDLE;
  assign ribp.addr   = {s_haddr_q[31:2], 2'b00};
  always_comb begin
    ribp.wstrb = '0;
    ribp.wdata = '0;
    if (s_hwrite_q) begin
      unique case (s_hsize_q)
        AHBL_SIZE_BYTE: begin
          unique case (s_haddr_q[1:0])
            2'b00: begin
              ribp.wstrb = 4'b0001;
              ribp.wdata = {24'b0, ahbl.hwdata[7:0]};
            end
            2'b01: begin
              ribp.wstrb = 4'b0010;
              ribp.wdata = {16'b0, ahbl.hwdata[7:0], 8'b0};
            end
            2'b10: begin
              ribp.wstrb = 4'b0100;
              ribp.wdata = {8'b0, ahbl.hwdata[7:0], 16'b0};
            end
            2'b11: begin
              ribp.wstrb = 4'b1000;
              ribp.wdata = {ahbl.hwdata[7:0], 24'b0};
            end
            default: begin
              ribp.wstrb = 4'b0001;
              ribp.wdata = {24'b0, ahbl.hwdata[7:0]};
            end
          endcase
        end
        AHBL_SIZE_HWRD: begin
          unique case (s_haddr_q[1])
            1'b0: begin
              ribp.wstrb = 4'b0011;
              ribp.wdata = {16'b0, ahbl.hwdata[15:0]};
            end
            1'b1: begin
              ribp.wstrb = 4'b1100;
              ribp.wdata = {ahbl.hwdata[15:0], 16'd0};
            end
          endcase
        end
        AHBL_SIZE_WORD: begin
          ribp.wstrb = 4'b1111;
          ribp.wdata = ahbl.hwdata;
        end
        default: begin
          ribp.wstrb = 4'b1111;
          ribp.wdata = ahbl.hwdata;
        end
      endcase
    end
  end


  // ahb.hready,
  always_comb begin
    s_fsm_d    = s_fsm_q;
    s_haddr_d  = s_haddr_q;
    s_hwrite_d = s_hwrite_q;
    s_hsize_d  = s_hsize_q;
    unique case (s_fsm_q)
      STATE_IDLE: begin
        // just for no-burst ahbl
        if (ahbl.htrans == AHBL_TRANS_NSEQ && ahbl.hready) begin
          s_fsm_d    = STATE_DATA;
          s_haddr_d  = ahbl.haddr;
          s_hwrite_d = ahbl.hwrite;
          s_hsize_d  = ahbl.hsize;
        end
      end
      STATE_DATA: begin
        if (~ribp.ready) s_fsm_d = STATE_WAIT;
        // ribp.ready == 1'b1
        else if (ahbl.htrans == AHBL_TRANS_NSEQ) begin
          s_fsm_d    = STATE_DATA;
          s_haddr_d  = ahbl.haddr;
          s_hwrite_d = ahbl.hwrite;
          s_hsize_d  = ahbl.hsize;
        end else s_fsm_d = STATE_IDLE;
      end
      STATE_WAIT: begin
        if (ribp.ready) begin
          if (ahbl.htrans == AHBL_TRANS_NSEQ) begin
            s_fsm_d    = STATE_DATA;
            s_haddr_d  = ahbl.haddr;
            s_hwrite_d = ahbl.hwrite;
            s_hsize_d  = ahbl.hsize;
          end else s_fsm_d = STATE_IDLE;
        end
      end
      default: begin
        s_fsm_d = STATE_IDLE;
      end
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
