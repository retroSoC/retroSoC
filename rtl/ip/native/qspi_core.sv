// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "qspi_define.svh"

module qspi_core (
    // verilog_format: off
    input logic        clk_i,
    input logic        rst_n_i,
    input logic        mode_i,
    input logic [3:0]  nss_i,
    input logic [7:0]  clkdiv_i,
    input logic [1:0]  cmdtyp_i,
    input logic [2:0]  cmdlen_i,
    input logic [31:0] cmddat_i,
    input logic [1:0]  adrtyp_i,
    input logic [2:0]  adrlen_i,
    input logic [31:0] adrdat_i,
    input logic [1:0]  dumtyp_i,
    input logic [7:0]  dumlen_i,
    input logic [31:0] dumdat_i,
    input logic [1:0]  dattyp_i,
    input logic [7:0]  datlen_i,
    input logic [7:0]  hlvlen_i,
    // tx fifo
    output logic       tx_data_req_o,
    input logic        tx_data_rdy_i,
    input logic [31:0] tx_data_i,
    // rx fifo
    input logic        start_i,
    output logic       done_o,
    qspi_if.dut        qspi
    // verilog_format: on
);

  localparam FSM_IDLE = 3'd0;
  localparam FSM_CMD = 3'd1;
  localparam FSM_ADDR = 3'd2;
  localparam FSM_DUM = 3'd3;
  localparam FSM_TXDATA = 3'd4;
  localparam FSM_RXDATA = 3'd5;
  localparam FSM_DONE = 3'd6;
  localparam FSM_HLVD = 3'd7;

  // sclk
  logic s_sclk, s_sclk_en_d, s_sclk_en_q;
  logic s_nss_d, s_nss_q;
  logic s_fir_clk_edge, s_sec_clk_edge;
  // xfer
  logic [31:0] s_xfer_data_d, s_xfer_data_q;
  // 256 x 32
  logic [15:0] s_xfer_bit_len, s_xfer_bit_cnt_d, s_xfer_bit_cnt_q;
  logic [7:0] s_xfer_byte_len, s_xfer_byte_cnt_d, s_xfer_byte_cnt_q;
  // common
  logic [2:0] s_fsm_d, s_fsm_q;
  logic s_xfer_sta_trg, s_xfer_end_trg;


  assign qspi.spi_sck_o = s_sclk;
  assign qspi.spi_nss_o = {4{s_nss_q}} & nss_i;
  assign qspi.irq_o     = '0;

  assign s_xfer_sta_trg = s_fsm_q == FSM_IDLE && start_i;
  assign s_xfer_end_trg = s_fsm_q == FSM_DONE || s_fsm_q == FSM_HLVD;

  qspi_clkgen u_qspi_clkgen (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .div_i         (clkdiv_i),
      .en_i          (s_sclk_en_q),
      .clk_o         (s_sclk),
      .fir_clk_edge_o(s_fir_clk_edge),
      .sec_clk_edge_o(s_sec_clk_edge)
  );

  always_comb begin
    s_fsm_d             = s_fsm_q;
    s_nss_d             = s_nss_q;
    s_sclk_en_d         = s_sclk_en_q;
    s_xfer_bit_len      = '0;
    s_xfer_byte_len     = '0;
    s_xfer_bit_cnt_d    = s_xfer_bit_cnt_q;
    s_xfer_byte_cnt_d   = s_xfer_byte_cnt_q;
    s_xfer_data_d       = s_xfer_data_q;
    // system
    tx_data_req_o       = 1'b0;
    done_o              = 1'b0;
    // qspi if
    qspi.spi_io_en_o    = '0;
    qspi.spi_io_en_o[0] = 1'b1;
    qspi.spi_io_out_o   = '0;
    unique case (s_fsm_q)
      FSM_IDLE: begin
        if (start_i) begin
          s_nss_d           = 1'b0;
          s_sclk_en_d       = 1'b1;
          s_xfer_bit_cnt_d  = s_xfer_bit_len;
          s_xfer_byte_cnt_d = s_xfer_byte_len;
          if (cmdtyp_i != `QSPI_TYPE_NONE) begin
            s_fsm_d        = FSM_CMD;
            s_xfer_bit_len = {10'd0, cmdlen_i, 3'd0};
            s_xfer_data_d  = cmddat_i;
          end else if (adrtyp_i != `QSPI_TYPE_NONE) begin
            s_fsm_d        = FSM_ADDR;
            s_xfer_bit_len = {10'd0, adrlen_i, 3'd0};
            s_xfer_data_d  = adrdat_i;
          end else if (dumtyp_i != `QSPI_TYPE_NONE) begin
            s_fsm_d        = FSM_DUM;
            s_xfer_bit_len = {8'd0, dumlen_i};
            s_xfer_data_d  = dumdat_i;
          end else if (dattyp_i != `QSPI_TYPE_NONE) begin
            s_fsm_d         = FSM_TXDATA;
            s_xfer_bit_len  = 16'd32;
            s_xfer_byte_len = datlen_i;
            if (tx_data_rdy_i) begin
              s_xfer_data_d = tx_data_i;
              tx_data_req_o = 1'b1;
            end else s_xfer_data_d = '0;
          end else begin
            s_fsm_d     = FSM_DONE;
            s_sclk_en_d = 1'b0;
          end
        end
      end
      FSM_CMD: begin
        unique case (cmdtyp_i)
          `QSPI_TYPE_SNGL: begin
            s_xfer_bit_cnt_d     = s_xfer_bit_cnt_q - 3'd1;
            s_xfer_data_d        = {s_xfer_data_q[30:0], 1'd0};
            qspi.spi_io_en_o[0]  = 1'b1;
            qspi.spi_io_out_o[0] = s_xfer_data_q[31];
          end
          `QSPI_TYPE_DUAL: begin
            s_xfer_bit_cnt_d       = s_xfer_bit_cnt_q - 3'd2;
            s_xfer_data_d          = {s_xfer_data_q[29:0], 2'd0};
            qspi.spi_io_en_o[1:0]  = 2'b11;
            qspi.spi_io_out_o[1:0] = s_xfer_data_q[31:30];
          end
          `QSPI_TYPE_QUAD: begin
            s_xfer_bit_cnt_d       = s_xfer_bit_cnt_q - 3'd4;
            s_xfer_data_d          = {s_xfer_data_q[27:0], 4'd0};
            qspi.spi_io_en_o[3:0]  = 4'b1111;
            qspi.spi_io_out_o[3:0] = s_xfer_data_q[31:28];
          end
          default: begin
            s_xfer_bit_cnt_d     = s_xfer_bit_cnt_q - 3'd1;
            s_xfer_data_d        = {s_xfer_data_q[30:0], 1'd0};
            qspi.spi_io_en_o[0]  = 1'b1;
            qspi.spi_io_out_o[0] = s_xfer_data_q[31];
          end
        endcase

        if (s_xfer_bit_cnt_q == '0) begin
          s_xfer_bit_cnt_d  = s_xfer_bit_len;
          s_xfer_byte_cnt_d = s_xfer_byte_len;
          if (adrtyp_i != `QSPI_TYPE_NONE) begin
            s_fsm_d        = FSM_ADDR;
            s_xfer_bit_len = {10'd0, adrlen_i, 3'd0};
            s_xfer_data_d  = adrdat_i;
          end else if (dumtyp_i != `QSPI_TYPE_NONE) begin
            s_fsm_d        = FSM_DUM;
            s_xfer_bit_len = {8'd0, dumlen_i};
            s_xfer_data_d  = dumdat_i;
          end else if (dattyp_i != `QSPI_TYPE_NONE) begin
            s_fsm_d         = FSM_TXDATA;
            s_xfer_bit_len  = 16'd32;
            s_xfer_byte_len = datlen_i;
            if (tx_data_rdy_i) begin
              s_xfer_data_d = tx_data_i;
              tx_data_req_o = 1'b1;
            end else s_xfer_data_d = '0;
          end else begin
            s_fsm_d     = FSM_DONE;
            s_sclk_en_d = 1'b0;
          end
        end
      end
      FSM_ADDR: begin
        unique case (adrtyp_i)
          `QSPI_TYPE_SNGL: begin
            s_xfer_bit_cnt_d     = s_xfer_bit_cnt_q - 3'd1;
            s_xfer_data_d        = {s_xfer_data_q[30:0], 1'd0};
            qspi.spi_io_en_o[0]  = 1'b1;
            qspi.spi_io_out_o[0] = s_xfer_data_q[31];
          end
          `QSPI_TYPE_DUAL: begin
            s_xfer_bit_cnt_d       = s_xfer_bit_cnt_q - 3'd2;
            s_xfer_data_d          = {s_xfer_data_q[29:0], 2'd0};
            qspi.spi_io_en_o[1:0]  = 2'b11;
            qspi.spi_io_out_o[1:0] = s_xfer_data_q[31:30];
          end
          `QSPI_TYPE_QUAD: begin
            s_xfer_bit_cnt_d       = s_xfer_bit_cnt_q - 3'd4;
            s_xfer_data_d          = {s_xfer_data_q[27:0], 4'd0};
            qspi.spi_io_en_o[3:0]  = 4'b1111;
            qspi.spi_io_out_o[3:0] = s_xfer_data_q[31:28];
          end
          default: begin
            s_xfer_bit_cnt_d     = s_xfer_bit_cnt_q - 3'd1;
            s_xfer_data_d        = {s_xfer_data_q[30:0], 1'd0};
            qspi.spi_io_en_o[0]  = 1'b1;
            qspi.spi_io_out_o[0] = s_xfer_data_q[31];
          end
        endcase

        if (s_xfer_bit_cnt_q == '0) begin
          s_xfer_bit_cnt_d  = s_xfer_bit_len;
          s_xfer_byte_cnt_d = s_xfer_byte_len;
          if (dumtyp_i != `QSPI_TYPE_NONE) begin
            s_fsm_d        = FSM_DUM;
            s_xfer_bit_len = {8'd0, dumlen_i};
            s_xfer_data_d  = dumdat_i;
          end else if (dattyp_i != `QSPI_TYPE_NONE) begin
            s_fsm_d         = FSM_TXDATA;
            s_xfer_bit_len  = 16'd32;
            s_xfer_byte_len = datlen_i;
            if (tx_data_rdy_i) begin
              s_xfer_data_d = tx_data_i;
              tx_data_req_o = 1'b1;
            end else s_xfer_data_d = '0;
          end else begin
            s_fsm_d     = FSM_DONE;
            s_sclk_en_d = 1'b0;
          end
        end
      end
      FSM_DUM: begin
        unique case (dumtyp_i)
          `QSPI_TYPE_SNGL: begin
            s_xfer_bit_cnt_d     = s_xfer_bit_cnt_q - 3'd1;
            s_xfer_data_d        = {s_xfer_data_q[30:0], 1'd0};
            qspi.spi_io_en_o[0]  = 1'b1;
            qspi.spi_io_out_o[0] = s_xfer_data_q[31];
          end
          `QSPI_TYPE_DUAL: begin
            s_xfer_bit_cnt_d       = s_xfer_bit_cnt_q - 3'd2;
            s_xfer_data_d          = {s_xfer_data_q[29:0], 2'd0};
            qspi.spi_io_en_o[1:0]  = 2'b11;
            qspi.spi_io_out_o[1:0] = s_xfer_data_q[31:30];
          end
          `QSPI_TYPE_QUAD: begin
            s_xfer_bit_cnt_d       = s_xfer_bit_cnt_q - 3'd4;
            s_xfer_data_d          = {s_xfer_data_q[27:0], 4'd0};
            qspi.spi_io_en_o[3:0]  = 4'b1111;
            qspi.spi_io_out_o[3:0] = s_xfer_data_q[31:28];
          end
          default: begin
            s_xfer_bit_cnt_d     = s_xfer_bit_cnt_q - 3'd1;
            s_xfer_data_d        = {s_xfer_data_q[30:0], 1'd0};
            qspi.spi_io_en_o[0]  = 1'b1;
            qspi.spi_io_out_o[0] = s_xfer_data_q[31];
          end
        endcase

        if (s_xfer_bit_cnt_q == '0) begin
          s_xfer_bit_cnt_d  = s_xfer_bit_len;
          s_xfer_byte_cnt_d = s_xfer_byte_len;
          if (dattyp_i != `QSPI_TYPE_NONE) begin
            s_fsm_d         = FSM_TXDATA;
            s_xfer_bit_len  = 16'd32;
            s_xfer_byte_len = datlen_i;
            if (tx_data_rdy_i) begin
              s_xfer_data_d = tx_data_i;
              tx_data_req_o = 1'b1;
            end else s_xfer_data_d = '0;
          end else begin
            s_fsm_d     = FSM_DONE;
            s_sclk_en_d = 1'b0;
          end
        end
      end
      FSM_TXDATA: begin
        unique case (dattyp_i)
          `QSPI_TYPE_SNGL: begin
            s_xfer_bit_cnt_d     = s_xfer_bit_cnt_q - 3'd1;
            s_xfer_data_d        = {s_xfer_data_q[30:0], 1'd0};
            qspi.spi_io_en_o[0]  = 1'b1;
            qspi.spi_io_out_o[0] = s_xfer_data_q[31];
          end
          `QSPI_TYPE_DUAL: begin
            s_xfer_bit_cnt_d       = s_xfer_bit_cnt_q - 3'd2;
            s_xfer_data_d          = {s_xfer_data_q[29:0], 2'd0};
            qspi.spi_io_en_o[1:0]  = 2'b11;
            qspi.spi_io_out_o[1:0] = s_xfer_data_q[31:30];
          end
          `QSPI_TYPE_QUAD: begin
            s_xfer_bit_cnt_d       = s_xfer_bit_cnt_q - 3'd4;
            s_xfer_data_d          = {s_xfer_data_q[27:0], 4'd0};
            qspi.spi_io_en_o[3:0]  = 4'b1111;
            qspi.spi_io_out_o[3:0] = s_xfer_data_q[31:28];
          end
          default: begin
            s_xfer_bit_cnt_d     = s_xfer_bit_cnt_q - 3'd1;
            s_xfer_data_d        = {s_xfer_data_q[30:0], 1'd0};
            qspi.spi_io_en_o[0]  = 1'b1;
            qspi.spi_io_out_o[0] = s_xfer_data_q[31];
          end
        endcase

        if (s_xfer_bit_cnt_q == '0) begin
          if (s_xfer_byte_cnt_q == '0) begin
            s_fsm_d          = FSM_DONE;
            s_sclk_en_d      = 1'b0;
            s_xfer_bit_cnt_d = 16'd2;
          end else begin
            s_xfer_bit_cnt_d  = 16'd32;
            s_xfer_byte_cnt_d = s_xfer_byte_cnt_q - 1'b1;
            if (tx_data_rdy_i) begin
              s_xfer_data_d = tx_data_i;
              tx_data_req_o = 1'b1;
            end else s_xfer_data_d = '0;
          end
        end
      end
      FSM_RXDATA: begin
      end
      FSM_DONE: begin
        if (s_xfer_bit_cnt_q == '0) begin
          s_fsm_d          = FSM_HLVD;
          s_nss_d          = 1'b1;
          s_xfer_bit_cnt_d = {8'd0, hlvlen_i};
          s_xfer_data_d    = '0;
        end else begin
          s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 1'b1;
        end
      end
      FSM_HLVD: begin
        if (s_xfer_bit_cnt_q == '0) begin
          s_fsm_d = FSM_IDLE;
          done_o  = 1'b1;
        end else begin
          s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 1'b1;
        end
      end
      default: begin
        s_fsm_d             = s_fsm_q;
        s_nss_d             = s_nss_q;
        s_sclk_en_d         = s_sclk_en_q;
        s_xfer_bit_len      = '0;
        s_xfer_byte_len     = '0;
        s_xfer_bit_cnt_d    = s_xfer_bit_cnt_q;
        s_xfer_byte_cnt_d   = s_xfer_byte_cnt_q;
        s_xfer_data_d       = s_xfer_data_q;
        // system
        tx_data_req_o       = 1'b0;
        done_o              = 1'b0;
        // qspi if
        qspi.spi_io_en_o    = '0;
        qspi.spi_io_en_o[0] = 1'b1;
        qspi.spi_io_out_o   = '0;
      end
    endcase
  end
  dffer #(3) u_fsm_dffer (
      clk_i,
      rst_n_i,
      s_xfer_sta_trg | s_sec_clk_edge | s_xfer_end_trg,
      s_fsm_d,
      s_fsm_q
  );

  dfferh #(1) u_nss_dfferh (
      clk_i,
      rst_n_i,
      s_xfer_sta_trg | s_sec_clk_edge,
      s_nss_d,
      s_nss_q
  );

  dffer #(1) u_sclk_en_dffer (
      clk_i,
      rst_n_i,
      s_xfer_sta_trg | s_sec_clk_edge,
      s_sclk_en_d,
      s_sclk_en_q
  );

  dffer #(16) u_xfer_bit_cnt_dffer (
      clk_i,
      rst_n_i,
      s_xfer_sta_trg | s_sec_clk_edge,
      s_xfer_bit_cnt_d,
      s_xfer_bit_cnt_q
  );


  dffer #(8) u_xfer_byte_cnt_dffer (
      clk_i,
      rst_n_i,
      s_xfer_sta_trg | s_sec_clk_edge,
      s_xfer_byte_cnt_d,
      s_xfer_byte_cnt_q
  );

  dffer #(32) u_xfer_data_dffer (
      clk_i,
      rst_n_i,
      s_xfer_sta_trg | s_sec_clk_edge,
      s_xfer_data_d,
      s_xfer_data_q
  );

endmodule
