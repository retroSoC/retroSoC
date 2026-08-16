// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "xpi_define.svh"

module xpi_mm (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic                     clk_i,
    input  logic                     rst_n_i,
    input  logic [             31:0] xpi_mmstad_i  [0:`XPI_NSS_NUM-1],
    input  logic [             31:0] xpi_mmoffst_i [0:`XPI_NSS_NUM-1],
    output logic [`XPI_LNS_NUM-1:0]  nss_o,
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
    input  logic                     req_valid_i,
    output logic                     req_ready_o,
    input  logic [             31:0] req_addr_i,
    input  logic [             31:0] req_wdata_i,
    input  logic [              3:0] req_wstrb_i,
    output logic [             31:0] req_rdata_o,
    output logic                     req_resp_err_o
    // verilog_format: on
);
  typedef enum logic [2:0] {
    Idle       = 3'd0,
    WriteStart = 3'd1,
    Write      = 3'd2,
    ReadStart  = 3'd3,
    Read       = 3'd4
  } xpi_mm_state_e;

  // apb4
  logic s_apb4_wr_hdshk, s_apb4_rd_hdshk;
  logic s_apb4_ready_d, s_apb4_ready_q;
  logic s_apb4_rdata_en;
  logic [31:0] s_apb4_rdata_d, s_apb4_rdata_q;
  // ctrl
  logic                 s_rd_st;
  logic                 s_wr_st;
  logic                 s_rdwr;
  xpi_mm_state_e        s_fsm_state;
  logic          [31:0] s_addr;
  logic          [31:0] s_wr_data;
  logic          [ 2:0] s_xfer_byte_cnt;
  logic          [ 1:0] s_disp_addr_ofst;
  logic          [ 2:0] s_disp_byte_cnt;
  logic          [31:0] s_disp_wdata;
  logic                 s_mem_valid_re;
  logic [`XPI_LNS_NUM-1:0] s_nss_d, s_nss_q;

  // apb4
  assign s_apb4_wr_hdshk = req_valid_i && (~s_apb4_ready_q) && (|req_wstrb_i);
  assign s_apb4_rd_hdshk = req_valid_i && (~s_apb4_ready_q) && (~(|req_wstrb_i));
  assign req_ready_o     = s_apb4_ready_q;
  assign req_resp_err_o  = 1'b0;
  assign req_rdata_o     = s_apb4_rdata_q;
  // apb4 rd
  always_comb begin
    if (s_apb4_rd_hdshk) s_apb4_ready_d = rx_pop_ready_i;
    else if (s_apb4_wr_hdshk) s_apb4_ready_d = xfer_done_i;
    else s_apb4_ready_d = 1'b0;
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_apb4_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_ready_d),
      .dat_o  (s_apb4_ready_q)
  );


  assign rx_pop_valid_o  = s_apb4_rd_hdshk;
  assign s_apb4_rdata_en = s_apb4_rd_hdshk;
  assign s_apb4_rdata_d  = (req_valid_i && rx_pop_ready_i) ? rx_pop_data_i : s_apb4_rdata_q;
  dffer #(
      .DATA_WIDTH(32)
  ) u_apb4_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_apb4_rdata_en),
      .dat_i  (s_apb4_rdata_d),
      .dat_o  (s_apb4_rdata_q)
  );


  // ctrl
  assign nss_o           = s_nss_q;
  assign rd_st_o         = s_rd_st;
  assign wr_st_o         = s_wr_st;
  assign rdwr_o          = s_rdwr;
  assign addr_o          = s_addr;
  assign xfer_byte_o     = s_xfer_byte_cnt;
  // tx fifo
  assign tx_push_valid_o = s_fsm_state == WriteStart && tx_push_ready_i;
  assign tx_push_data_o  = s_wr_data;


  // HACK:
  always_comb begin
    s_nss_d = s_nss_q;
    for (int i = 0; i < `XPI_NSS_NUM; i++) begin
      if (xpi_mmstad_i[i] <= req_addr_i && req_addr_i <= xpi_mmstad_i[i] + xpi_mmoffst_i[i]) begin
        s_nss_d = `XPI_LNS_NUM'(i);
        break;
      end
    end
  end
  dffer #(
      .DATA_WIDTH(`XPI_LNS_NUM)
  ) u_accid_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_mem_valid_re),
      .dat_i  (s_nss_d),
      .dat_o  (s_nss_q)
  );


  // memory-mapped mode
  edge_det_sync_re #(
      .DATA_WIDTH(1)
  ) u_mem_valid_edge_det_sync_re (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (req_valid_i),
      .re_o   (s_mem_valid_re)
  );

  // The transfer state has ordered request/reset updates in one process; retain
  // it to preserve the current request-to-command cycle behavior exactly.
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) begin
      s_fsm_state     <= Idle;
      s_rd_st         <= '0;
      s_wr_st         <= '0;
      s_rdwr          <= 1'b1;
      s_addr          <= '0;
      s_wr_data       <= '0;
      s_xfer_byte_cnt <= '0;
    end else begin
      unique case (s_fsm_state)
        Idle: begin
          if (s_mem_valid_re) begin
            if (|req_wstrb_i) begin
              s_fsm_state     <= WriteStart;
              s_addr          <= {4'd0, req_addr_i[27:0]} + {30'd0, s_disp_addr_ofst};
              s_wr_data       <= s_disp_wdata;
              s_xfer_byte_cnt <= s_disp_byte_cnt;
            end else begin
              s_fsm_state     <= ReadStart;
              s_addr          <= {4'd0, req_addr_i[27:0]};
              s_wr_data       <= req_wdata_i;  // NOTE: no used
              s_xfer_byte_cnt <= 3'd4;
            end
          end
        end
        WriteStart: begin
          if (tx_push_ready_i) begin
            s_wr_st     <= 1'b1;
            s_rdwr      <= 1'b0;
            s_fsm_state <= Write;
          end
        end
        Write: begin
          s_wr_st <= 1'b0;
          if (xfer_done_i) s_fsm_state <= Idle;
        end
        ReadStart: begin
          s_rd_st     <= 1'b1;
          s_rdwr      <= 1'b1;
          s_fsm_state <= Read;
        end
        Read: begin
          s_rd_st <= 1'b0;
          if (rx_pop_ready_i) s_fsm_state <= Idle;
        end
        default: begin
          s_fsm_state     <= Idle;
          s_rd_st         <= '0;
          s_wr_st         <= '0;
          s_rdwr          <= 1'b1;
          s_addr          <= '0;
          s_wr_data       <= '0;
          s_xfer_byte_cnt <= '0;
        end
      endcase
    end
  end

  xfer_dispatcher u_xfer_dispatcher (
      .wstrb_i        (req_wstrb_i),
      .wdata_i        (req_wdata_i),
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
