// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "qspi_define.svh"

module qspi_mm (
    // verilog_format: off
    input  logic                     clk_i,
    input  logic                     rst_n_i,
    input  logic [             31:0] qspi_mmstad_i  [0:`QSPI_NSS_NUM-1],
    input  logic [             31:0] qspi_mmoffst_i [0:`QSPI_NSS_NUM-1],
    output logic [`QSPI_LNS_NUM-1:0] nss_o,
    output logic                     rd_st_o,
    output logic                     wr_st_o,
    output logic                     rdwr_o,
    output logic [             31:0] addr_o,
    output logic [              2:0] xfer_byte_o,
    // tx fifo
    output logic                     tx_push_valid_o,
    output logic [             31:0] tx_push_data_o,
    input  logic                     tx_push_ready_i,
    // rx fifo
    output logic                     rx_pop_valid_o,
    input  logic [             31:0] rx_pop_data_i,
    input  logic                     rx_pop_ready_i,
    // ctrl
    input  logic                     xfer_done_i,
    nmi_if.slave                     nmi
    // verilog_format: on
);
  // verilog_format: off
  localparam FSM_IDLE  = 3'd0;
  localparam FSM_WE_ST = 3'd1;
  localparam FSM_WE    = 3'd2;
  localparam FSM_RD_ST = 3'd3;
  localparam FSM_RD    = 3'd4;
  // verilog_format: on

  // nmi
  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;
  // ctrl
  logic        r_rd_st;
  logic        r_wr_st;
  logic        r_rdwr;
  logic [ 2:0] r_fsm_state;
  logic [31:0] r_addr;
  logic [31:0] r_wr_data;
  logic [ 2:0] r_xfer_byte_cnt;
  logic [ 1:0] s_disp_addr_ofst;
  logic [ 2:0] s_disp_byte_cnt;
  logic [31:0] s_disp_wdata;
  logic        s_mem_valid_re;
  logic [`QSPI_LNS_NUM-1:0] s_nss_d, s_nss_q;

  // nmi
  assign s_nmi_wr_hdshk = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready      = s_nmi_ready_q;
  assign nmi.rdata      = s_nmi_rdata_q;
  // nmi rd
  always_comb begin
    if (s_nmi_rd_hdshk) s_nmi_ready_d = rx_pop_ready_i;
    else if (s_nmi_wr_hdshk) s_nmi_ready_d = xfer_done_i;
    else s_nmi_ready_d = 1'b0;
  end
  dffr #(1) u_nmi_ready_dffr (
      clk_i,
      rst_n_i,
      s_nmi_ready_d,
      s_nmi_ready_q
  );


  assign rx_pop_valid_o = s_nmi_rd_hdshk;
  assign s_nmi_rdata_en = s_nmi_rd_hdshk;
  assign s_nmi_rdata_d  = (nmi.valid && rx_pop_ready_i) ? rx_pop_data_i : s_nmi_rdata_q;
  dffer #(32) u_nmi_rdata_dffer (
      clk_i,
      rst_n_i,
      s_nmi_rdata_en,
      s_nmi_rdata_d,
      s_nmi_rdata_q
  );


  // ctrl
  assign nss_o           = s_nss_q;
  assign rd_st_o         = r_rd_st;
  assign wr_st_o         = r_wr_st;
  assign rdwr_o          = r_rdwr;
  assign addr_o          = r_addr;
  assign xfer_byte_o     = r_xfer_byte_cnt;
  // tx fifo
  assign tx_push_valid_o = r_fsm_state == FSM_WE_ST && tx_push_ready_i;
  assign tx_push_data_o  = r_wr_data;


  // HACK:
  always_comb begin
    s_nss_d = s_nss_q;
    for (int i = 0; i < `QSPI_NSS_NUM; i++) begin
      if (qspi_mmstad_i[i] <= nmi.addr && nmi.addr <= qspi_mmstad_i[i] + qspi_mmoffst_i[i]) begin
        s_nss_d = `QSPI_LNS_NUM'(i);
        break;
      end
    end
  end
  dffer #(`QSPI_LNS_NUM) u_accid_dffer (
      clk_i,
      rst_n_i,
      s_mem_valid_re,
      s_nss_d,
      s_nss_q
  );


  // memory-mapped mode
  edge_det_sync_re #(1) u_mem_valid_edge_det_sync_re (
      clk_i,
      rst_n_i,
      nmi.valid,
      s_mem_valid_re
  );

  always_ff @(posedge clk_i, negedge rst_n_i) begin
    if (~rst_n_i) begin
      r_fsm_state     <= FSM_IDLE;
      r_rd_st         <= '0;
      r_wr_st         <= '0;
      r_rdwr          <= 1'b1;
      r_addr          <= '0;
      r_wr_data       <= '0;
      r_xfer_byte_cnt <= '0;
    end else begin
      unique case (r_fsm_state)
        FSM_IDLE: begin
          if (s_mem_valid_re) begin
            if (|nmi.wstrb) begin
              r_fsm_state     <= FSM_WE_ST;
              r_addr          <= {4'd0, nmi.addr[27:0]} + {30'd0, s_disp_addr_ofst};
              r_wr_data       <= s_disp_wdata;
              r_xfer_byte_cnt <= s_disp_byte_cnt;
            end else begin
              r_fsm_state     <= FSM_RD_ST;
              r_addr          <= {4'd0, nmi.addr[27:0]};
              r_wr_data       <= nmi.wdata;  // NOTE: no used
              r_xfer_byte_cnt <= 3'd4;
            end
          end
        end
        FSM_WE_ST: begin
          if (tx_push_ready_i) begin
            r_wr_st     <= 1'b1;
            r_rdwr      <= 1'b0;
            r_fsm_state <= FSM_WE;
          end
        end
        FSM_WE: begin
          r_wr_st <= 1'b0;
          if (xfer_done_i) r_fsm_state <= FSM_IDLE;
        end
        FSM_RD_ST: begin
          r_rd_st     <= 1'b1;
          r_rdwr      <= 1'b1;
          r_fsm_state <= FSM_RD;
        end
        FSM_RD: begin
          r_rd_st <= 1'b0;
          if (rx_pop_ready_i) r_fsm_state <= FSM_IDLE;
        end
        default: begin
          r_fsm_state     <= FSM_IDLE;
          r_rd_st         <= '0;
          r_wr_st         <= '0;
          r_rdwr          <= 1'b1;
          r_addr          <= '0;
          r_wr_data       <= '0;
          r_xfer_byte_cnt <= '0;
        end
      endcase
    end
  end

  xfer_dispatcher u_xfer_dispatcher (
      .wstrb_i        (nmi.wstrb),
      .wdata_i        (nmi.wdata),
      .addr_ofst_o    (s_disp_addr_ofst),
      .xfer_byte_cnt_o(s_disp_byte_cnt),
      .wdata_o        (s_disp_wdata)
  );

endmodule


module xfer_dispatcher (
    input  logic [ 3:0] wstrb_i,
    input  logic [31:0] wdata_i,
    output logic [ 1:0] addr_ofst_o,
    output logic [ 2:0] xfer_byte_cnt_o,
    output logic [31:0] wdata_o
);
  always_comb begin
    addr_ofst_o     = 2'd0;
    xfer_byte_cnt_o = 3'd4;
    wdata_o         = {wdata_i[7:0], wdata_i[15:8], wdata_i[23:16], wdata_i[31:24]};
    case (wstrb_i)
      4'b0001: begin
        addr_ofst_o     = 2'd0;
        xfer_byte_cnt_o = 3'd1;
        wdata_o         = {wdata_i[7:0], 24'd0};
      end
      4'b0010: begin
        addr_ofst_o     = 2'd1;
        xfer_byte_cnt_o = 3'd1;
        wdata_o         = {wdata_i[15:8], 24'd0};
      end
      4'b0100: begin
        addr_ofst_o     = 2'd2;
        xfer_byte_cnt_o = 3'd1;
        wdata_o         = {wdata_i[23:16], 24'd0};
      end
      4'b1000: begin
        addr_ofst_o     = 2'd3;
        xfer_byte_cnt_o = 3'd1;
        wdata_o         = {wdata_i[31:24], 24'd0};
      end
      4'b0011: begin
        addr_ofst_o     = 2'd0;
        xfer_byte_cnt_o = 3'd2;
        wdata_o         = {wdata_i[7:0], wdata_i[15:8], 16'd0};
      end
      4'b1100: begin
        addr_ofst_o     = 2'd2;
        xfer_byte_cnt_o = 3'd2;
        wdata_o         = {wdata_i[23:16], wdata_i[31:24], 16'd0};
      end
      4'b1111: begin
        addr_ofst_o     = 2'd0;
        xfer_byte_cnt_o = 3'd4;
        wdata_o         = {wdata_i[7:0], wdata_i[15:8], wdata_i[23:16], wdata_i[31:24]};
      end
      default: begin
        addr_ofst_o     = 2'd0;
        xfer_byte_cnt_o = 3'd4;
        wdata_o         = {wdata_i[7:0], wdata_i[15:8], wdata_i[23:16], wdata_i[31:24]};
      end
    endcase
  end
endmodule
