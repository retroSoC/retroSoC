// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module dma_core (
    // verilog_format: off
    input logic        clk_i,
    input logic        rst_n_i,
    input logic [1:0]  mode_i,
    input logic [31:0] srcaddr_i,
    input logic        srcincr_i,
    input logic [31:0] dstaddr_i,
    input logic        dstincr_i,
    input logic [31:0] xferlen_i,
    input logic        start_i,
    input logic        stop_i,
    input logic        reset_i,
    output logic       done_o,
    output logic [1:0] fsm_o,
    dma_hw_trg_if.dut  hw_trg,
    nmi_if.master      nmi
    // verilog_format: on
);

  localparam FSM_IDLE = 2'd0;
  localparam FSM_XFER = 2'd1;
  localparam FSM_DONE = 2'd2;

  logic [1:0] s_fsm_d, s_fsm_q;
  logic [31:0] s_xfer_cnt_d, s_xfer_cnt_q;
  logic [31:0] s_src_addr_d, s_src_addr_q;
  logic [31:0] s_dst_addr_d, s_dst_addr_q;
  logic [31:0] s_rd_data_d, s_rd_data_q;
  logic s_xfer_type_d, s_xfer_type_q;  // 0: rd 1: wr
  logic s_xfer_done_d, s_xfer_done_q;
  logic s_ctrl_stop_d, s_ctrl_stop_q;

  assign fsm_o = s_fsm_q;
  always_comb begin
    s_fsm_d       = s_fsm_q;
    s_src_addr_d  = s_src_addr_q;
    s_dst_addr_d  = s_dst_addr_q;
    s_rd_data_d   = s_rd_data_q;
    s_xfer_cnt_d  = s_xfer_cnt_q;
    s_xfer_type_d = s_xfer_type_q;
    s_xfer_done_d = s_xfer_done_q;
    // nmi if
    nmi.valid     = '0;
    nmi.addr      = '0;
    nmi.wdata     = '0;
    nmi.wstrb     = '0;
    // common
    done_o        = '0;
    unique case (s_fsm_q)
      FSM_IDLE: begin
        if (start_i) begin
          s_fsm_d       = FSM_XFER;
          s_src_addr_d  = srcaddr_i;
          s_dst_addr_d  = dstaddr_i;
          s_xfer_cnt_d  = '0;
          s_xfer_type_d = 1'b0;
          s_xfer_done_d = 1'b1;
        end
      end
      FSM_XFER: begin
        if (~s_ctrl_stop_q) begin
          if (~s_xfer_type_q) begin
            unique case (mode_i)
              2'd2: begin
                if (~hw_trg.i2s_rx_proc && s_xfer_done_q) nmi.valid = 1'b0;
                else nmi.valid = 1'b1;
              end
              default: nmi.valid = 1'b1;
            endcase
            nmi.addr = s_src_addr_q;
            if (nmi.ready) begin
              s_xfer_type_d = 1'b1;
              s_xfer_done_d = 1'b1;
              s_rd_data_d   = nmi.rdata;
            end else if (nmi.valid) begin
              s_xfer_done_d = 1'b0;
            end
          end else begin
            unique case (mode_i)
              2'd1: begin
                if (~hw_trg.i2s_tx_proc && s_xfer_done_q) nmi.valid = 1'b0;
                else nmi.valid = 1'b1;
              end
              default: nmi.valid = 1'b1;
            endcase
            nmi.addr  = s_dst_addr_q;
            nmi.wdata = s_rd_data_q;
            nmi.wstrb = '1;
            if (nmi.ready) begin
              s_xfer_type_d = 1'b0;
              s_xfer_done_d = 1'b1;
              // when src rd+wr xfer done
              if (s_xfer_cnt_q == xferlen_i) begin
                s_xfer_cnt_d = '0;
                s_fsm_d      = FSM_DONE;
              end else begin
                s_xfer_cnt_d = s_xfer_cnt_q + 1'b1;
                if (srcincr_i) s_src_addr_d = s_src_addr_q + 3'd4;
                if (dstincr_i) s_dst_addr_d = s_dst_addr_q + 3'd4;
              end
            end else if (nmi.valid) s_xfer_done_d = 1'b0;
          end
        end else begin
          if (reset_i) s_fsm_d = FSM_IDLE;
        end
      end
      FSM_DONE: begin
        done_o  = 1'b1;
        s_fsm_d = FSM_IDLE;
      end
      default: begin
        s_fsm_d       = s_fsm_q;
        s_src_addr_d  = s_src_addr_q;
        s_dst_addr_d  = s_dst_addr_q;
        s_rd_data_d   = s_rd_data_q;
        s_xfer_cnt_d  = s_xfer_cnt_q;
        s_xfer_type_d = s_xfer_type_q;
        s_xfer_done_d = s_xfer_done_q;
        // nmi if
        nmi.valid     = '0;
        nmi.addr      = '0;
        nmi.wdata     = '0;
        nmi.wstrb     = '0;
        // common
        done_o        = '0;
      end
    endcase
  end
  dffr #(2) u_fsm_dffr (
      clk_i,
      rst_n_i,
      s_fsm_d,
      s_fsm_q
  );

  dffr #(32) u_xfer_cnt_dffr (
      clk_i,
      rst_n_i,
      s_xfer_cnt_d,
      s_xfer_cnt_q
  );

  dffr #(32) u_src_addr_dffr (
      clk_i,
      rst_n_i,
      s_src_addr_d,
      s_src_addr_q
  );

  dffr #(32) u_dst_addr_dffr (
      clk_i,
      rst_n_i,
      s_dst_addr_d,
      s_dst_addr_q
  );

  dffr #(32) u_rd_data_dffr (
      clk_i,
      rst_n_i,
      s_rd_data_d,
      s_rd_data_q
  );

  dffr #(1) u_xfer_type_dffr (
      clk_i,
      rst_n_i,
      s_xfer_type_d,
      s_xfer_type_q
  );

  dffr #(1) u_xfer_done_dffr (
      clk_i,
      rst_n_i,
      s_xfer_done_d,
      s_xfer_done_q
  );

  // control the xfer
  always_comb begin
    s_ctrl_stop_d = s_ctrl_stop_q;
    if (stop_i) s_ctrl_stop_d = ~s_ctrl_stop_q;
  end
  dffr #(1) u_ctrl_stop_dffr (
      clk_i,
      rst_n_i,
      s_ctrl_stop_d,
      s_ctrl_stop_q
  );

endmodule
