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
    input logic        rdwr_i,
    input logic        revdat_i,
    input logic [1:0]  cmdtyp_i,
    input logic [2:0]  cmdlen_i,
    input logic [31:0] cmddat_i,
    input logic [1:0]  adrtyp_i,
    input logic [2:0]  adrlen_i,
    input logic [31:0] adrdat_i,
    input logic [7:0]  dumlen_i,
    input logic [1:0]  dattyp_i,
    input logic [7:0]  datlen_i,
    input logic [2:0]  datbit_i,
    input logic [7:0]  hlvlen_i,
    // tx fifo
    output logic       tx_data_req_o,
    input logic        tx_data_rdy_i,
    input logic [31:0] tx_data_i,
    // rx fifo
    output logic        rx_data_req_o,
    input logic         rx_data_rdy_i,
    output logic [31:0] rx_data_o,
    // common
    input logic        start_i,
    output logic       done_o,
    input logic [7:0]  tx_elem_num_i,
    input logic        dma_xfer_done_i,
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
  // [1-32]bits
  logic [7:0] s_xfer_bit_cnt_d, s_xfer_bit_cnt_q;
  logic [7:0] s_xfer_byte_cnt_d, s_xfer_byte_cnt_q;
  logic [7:0] s_xfer_datlen;
  logic s_tx_data_req_d, s_tx_data_req_q;
  logic s_rx_data_req_d, s_rx_data_req_q;
  // common
  logic [2:0] s_fsm_d, s_fsm_q;
  logic s_xfer_condi, s_xfer_sta_trg, s_xfer_end_trg;
  logic s_dma_xfer_start, s_dma_xfer_trg;
  logic [7:0] s_dma_xfer_datlen;

  assign qspi.spi_sck_o = s_sclk;
  always_comb begin
    qspi.spi_nss_o = 4'b1111;
    if (nss_i[0]) qspi.spi_nss_o[0] = s_nss_q;
    if (nss_i[1]) qspi.spi_nss_o[1] = s_nss_q;
    if (nss_i[2]) qspi.spi_nss_o[2] = s_nss_q;
    if (nss_i[3]) qspi.spi_nss_o[3] = s_nss_q;
  end
  assign qspi.irq_o    = '0;
  assign tx_data_req_o = s_tx_data_req_q;
  assign rx_data_req_o = s_rx_data_req_q;

  // dma hw flow ctrl
  always_comb begin
    s_dma_xfer_trg = 1'b0;
    if (tx_elem_num_i >= datlen_i) s_dma_xfer_trg = 1'b1;
    else if (dma_xfer_done_i && (|tx_elem_num_i) && (tx_elem_num_i < datlen_i)) s_dma_xfer_trg = 1'b1;
  end

  assign s_xfer_datlen = mode_i ? s_dma_xfer_datlen : datlen_i;
  always_comb begin
    if (dma_xfer_done_i && (tx_elem_num_i < datlen_i)) s_dma_xfer_datlen = tx_elem_num_i;
    else s_dma_xfer_datlen = datlen_i;
  end

  assign s_xfer_condi   = (~mode_i && start_i) || (mode_i && s_dma_xfer_trg);
  assign s_xfer_sta_trg = s_fsm_q == FSM_IDLE && s_xfer_condi;
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
    s_xfer_bit_cnt_d    = s_xfer_bit_cnt_q;
    s_xfer_byte_cnt_d   = s_xfer_byte_cnt_q;
    s_xfer_data_d       = s_xfer_data_q;
    s_tx_data_req_d     = '0;
    s_rx_data_req_d     = '0;
    // system
    rx_data_o           = '0;
    done_o              = 1'b0;
    // qspi if
    qspi.spi_io_en_o    = '0;
    qspi.spi_io_en_o[0] = 1'b1;
    qspi.spi_io_out_o   = '0;
    unique case (s_fsm_q)
      FSM_IDLE: begin
        if (s_xfer_condi) begin
          s_nss_d     = 1'b0;
          s_sclk_en_d = 1'b1;
          if (cmdtyp_i != `QSPI_TYPE_NONE) begin
            s_fsm_d          = FSM_CMD;
            s_xfer_bit_cnt_d = {2'd0, cmdlen_i, 3'd0};
            s_xfer_data_d    = cmddat_i;
          end else if (adrtyp_i != `QSPI_TYPE_NONE) begin
            s_fsm_d          = FSM_ADDR;
            s_xfer_bit_cnt_d = {2'd0, adrlen_i, 3'd0};
            s_xfer_data_d    = adrdat_i;
          end else if (dumlen_i != '0) begin
            s_fsm_d          = FSM_DUM;
            s_xfer_bit_cnt_d = dumlen_i;
            s_xfer_data_d    = '0;
          end else if (dattyp_i != `QSPI_TYPE_NONE) begin
            if (rdwr_i) s_fsm_d = FSM_RXDATA;
            else s_fsm_d = FSM_TXDATA;
            s_xfer_bit_cnt_d  = {2'd0, datbit_i, 3'd0};
            s_xfer_byte_cnt_d = s_xfer_datlen;
            if (tx_data_rdy_i) begin
              if (revdat_i) s_xfer_data_d = {tx_data_i[15:0], tx_data_i[31:16]};
              else s_xfer_data_d = tx_data_i;
              s_tx_data_req_d = 1'b1;
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
            s_xfer_bit_cnt_d     = s_xfer_bit_cnt_q - 8'd1;
            s_xfer_data_d        = {s_xfer_data_q[30:0], 1'd0};
            qspi.spi_io_en_o[0]  = 1'b1;
            qspi.spi_io_out_o[0] = s_xfer_data_q[31];
          end
          `QSPI_TYPE_DUAL: begin
            s_xfer_bit_cnt_d       = s_xfer_bit_cnt_q - 8'd2;
            s_xfer_data_d          = {s_xfer_data_q[29:0], 2'd0};
            qspi.spi_io_en_o[1:0]  = 2'b11;
            qspi.spi_io_out_o[1:0] = s_xfer_data_q[31:30];
          end
          `QSPI_TYPE_QUAD: begin
            s_xfer_bit_cnt_d       = s_xfer_bit_cnt_q - 8'd4;
            s_xfer_data_d          = {s_xfer_data_q[27:0], 4'd0};
            qspi.spi_io_en_o[3:0]  = 4'b1111;
            qspi.spi_io_out_o[3:0] = s_xfer_data_q[31:28];
          end
          default: begin
            s_xfer_bit_cnt_d     = s_xfer_bit_cnt_q - 8'd1;
            s_xfer_data_d        = {s_xfer_data_q[30:0], 1'd0};
            qspi.spi_io_en_o[0]  = 1'b1;
            qspi.spi_io_out_o[0] = s_xfer_data_q[31];
          end
        endcase

        if ((cmdtyp_i == `QSPI_TYPE_SNGL && s_xfer_bit_cnt_q == 8'd1) ||
            (cmdtyp_i == `QSPI_TYPE_DUAL && s_xfer_bit_cnt_q == 8'd2) ||
            (cmdtyp_i == `QSPI_TYPE_QUAD && s_xfer_bit_cnt_q == 8'd4)) begin
          if (adrtyp_i != `QSPI_TYPE_NONE) begin
            s_fsm_d          = FSM_ADDR;
            s_xfer_bit_cnt_d = {2'd0, adrlen_i, 3'd0};
            s_xfer_data_d    = adrdat_i;
          end else if (dumlen_i != '0) begin
            s_fsm_d          = FSM_DUM;
            s_xfer_bit_cnt_d = dumlen_i;
            s_xfer_data_d    = '0;
          end else if (dattyp_i != `QSPI_TYPE_NONE) begin
            if (rdwr_i) s_fsm_d = FSM_RXDATA;
            else s_fsm_d = FSM_TXDATA;
            s_xfer_bit_cnt_d  = {2'd0, datbit_i, 3'd0};
            s_xfer_byte_cnt_d = s_xfer_datlen;
            if (tx_data_rdy_i) begin
              if (revdat_i) s_xfer_data_d = {tx_data_i[15:0], tx_data_i[31:16]};
              else s_xfer_data_d = tx_data_i;
              s_tx_data_req_d = 1'b1;
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
            s_xfer_bit_cnt_d     = s_xfer_bit_cnt_q - 8'd1;
            s_xfer_data_d        = {s_xfer_data_q[30:0], 1'd0};
            qspi.spi_io_en_o[0]  = 1'b1;
            qspi.spi_io_out_o[0] = s_xfer_data_q[31];
          end
          `QSPI_TYPE_DUAL: begin
            s_xfer_bit_cnt_d       = s_xfer_bit_cnt_q - 8'd2;
            s_xfer_data_d          = {s_xfer_data_q[29:0], 2'd0};
            qspi.spi_io_en_o[1:0]  = 2'b11;
            qspi.spi_io_out_o[1:0] = s_xfer_data_q[31:30];
          end
          `QSPI_TYPE_QUAD: begin
            s_xfer_bit_cnt_d       = s_xfer_bit_cnt_q - 8'd4;
            s_xfer_data_d          = {s_xfer_data_q[27:0], 4'd0};
            qspi.spi_io_en_o[3:0]  = 4'b1111;
            qspi.spi_io_out_o[3:0] = s_xfer_data_q[31:28];
          end
          default: begin
            s_xfer_bit_cnt_d     = s_xfer_bit_cnt_q - 8'd1;
            s_xfer_data_d        = {s_xfer_data_q[30:0], 1'd0};
            qspi.spi_io_en_o[0]  = 1'b1;
            qspi.spi_io_out_o[0] = s_xfer_data_q[31];
          end
        endcase

        if ((adrtyp_i == `QSPI_TYPE_SNGL && s_xfer_bit_cnt_q == 8'd1) ||
            (adrtyp_i == `QSPI_TYPE_DUAL && s_xfer_bit_cnt_q == 8'd2) ||
            (adrtyp_i == `QSPI_TYPE_QUAD && s_xfer_bit_cnt_q == 8'd4)) begin
          if (dumlen_i != '0) begin
            s_fsm_d          = FSM_DUM;
            s_xfer_bit_cnt_d = dumlen_i;
            s_xfer_data_d    = '0;
          end else if (dattyp_i != `QSPI_TYPE_NONE) begin
            if (rdwr_i) s_fsm_d = FSM_RXDATA;
            else s_fsm_d = FSM_TXDATA;
            s_xfer_bit_cnt_d  = {2'd0, datbit_i, 3'd0};
            s_xfer_byte_cnt_d = s_xfer_datlen;
            if (tx_data_rdy_i) begin
              if (revdat_i) s_xfer_data_d = {tx_data_i[15:0], tx_data_i[31:16]};
              else s_xfer_data_d = tx_data_i;
              s_tx_data_req_d = 1'b1;
            end else s_xfer_data_d = '0;
          end else begin
            s_fsm_d     = FSM_DONE;
            s_sclk_en_d = 1'b0;
          end
        end
      end
      FSM_DUM: begin
        qspi.spi_io_en_o = '0;
        s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd1;

        if (s_xfer_bit_cnt_q == 8'd1) begin
          if (dattyp_i != `QSPI_TYPE_NONE) begin
            if (rdwr_i) s_fsm_d = FSM_RXDATA;
            else s_fsm_d = FSM_TXDATA;
            s_xfer_bit_cnt_d  = {2'd0, datbit_i, 3'd0};
            s_xfer_byte_cnt_d = s_xfer_datlen;
            if (tx_data_rdy_i) begin
              if (revdat_i) s_xfer_data_d = {tx_data_i[15:0], tx_data_i[31:16]};
              else s_xfer_data_d = tx_data_i;
              s_tx_data_req_d = 1'b1;
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
            s_xfer_bit_cnt_d     = s_xfer_bit_cnt_q - 8'd1;
            s_xfer_data_d        = {s_xfer_data_q[30:0], 1'd0};
            qspi.spi_io_en_o[0]  = 1'b1;
            qspi.spi_io_out_o[0] = s_xfer_data_q[31];
          end
          `QSPI_TYPE_DUAL: begin
            s_xfer_bit_cnt_d       = s_xfer_bit_cnt_q - 8'd2;
            s_xfer_data_d          = {s_xfer_data_q[29:0], 2'd0};
            qspi.spi_io_en_o[1:0]  = 2'b11;
            qspi.spi_io_out_o[1:0] = s_xfer_data_q[31:30];
          end
          `QSPI_TYPE_QUAD: begin
            s_xfer_bit_cnt_d       = s_xfer_bit_cnt_q - 8'd4;
            s_xfer_data_d          = {s_xfer_data_q[27:0], 4'd0};
            qspi.spi_io_en_o[3:0]  = 4'b1111;
            qspi.spi_io_out_o[3:0] = s_xfer_data_q[31:28];
          end
          default: begin
            s_xfer_bit_cnt_d     = s_xfer_bit_cnt_q - 8'd1;
            s_xfer_data_d        = {s_xfer_data_q[30:0], 1'd0};
            qspi.spi_io_en_o[0]  = 1'b1;
            qspi.spi_io_out_o[0] = s_xfer_data_q[31];
          end
        endcase

        if ((dattyp_i == `QSPI_TYPE_SNGL && s_xfer_bit_cnt_q == 8'd1) ||
            (dattyp_i == `QSPI_TYPE_DUAL && s_xfer_bit_cnt_q == 8'd2) ||
            (dattyp_i == `QSPI_TYPE_QUAD && s_xfer_bit_cnt_q == 8'd4)) begin
          if (s_xfer_byte_cnt_q == 8'd1) begin
            s_fsm_d          = FSM_DONE;
            s_sclk_en_d      = 1'b0;
            s_xfer_bit_cnt_d = 8'd2;  // TODO: can config
          end else begin
            s_xfer_bit_cnt_d  = {2'd0, datbit_i, 3'd0};
            s_xfer_byte_cnt_d = s_xfer_byte_cnt_q - 1'b1;
            if (tx_data_rdy_i) begin
              if (revdat_i) s_xfer_data_d = {tx_data_i[15:0], tx_data_i[31:16]};
              else s_xfer_data_d = tx_data_i;
              s_tx_data_req_d = 1'b1;
            end else s_xfer_data_d = '0;
          end
        end
      end
      FSM_RXDATA: begin
        unique case (dattyp_i)
          `QSPI_TYPE_SNGL: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd1;
            s_xfer_data_d    = {s_xfer_data_q[30:0], qspi.spi_io_in_i[1]};
            qspi.spi_io_en_o = '0;
          end
          `QSPI_TYPE_DUAL: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd2;
            s_xfer_data_d    = {s_xfer_data_q[29:0], qspi.spi_io_in_i[1:0]};
            qspi.spi_io_en_o = '0;
          end
          `QSPI_TYPE_QUAD: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd4;
            s_xfer_data_d    = {s_xfer_data_q[27:0], qspi.spi_io_in_i[3:0]};
            qspi.spi_io_en_o = '0;
          end
          default: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd1;
            s_xfer_data_d    = {s_xfer_data_q[30:0], qspi.spi_io_in_i[1]};
            qspi.spi_io_en_o = '0;
          end
        endcase

        if ((dattyp_i == `QSPI_TYPE_SNGL && s_xfer_bit_cnt_q == 8'd1) ||
            (dattyp_i == `QSPI_TYPE_DUAL && s_xfer_bit_cnt_q == 8'd2) ||
            (dattyp_i == `QSPI_TYPE_QUAD && s_xfer_bit_cnt_q == 8'd4)) begin
          if (rx_data_rdy_i) begin
            if (~s_rx_data_req_q) s_rx_data_req_d = 1'b1;
            else s_rx_data_req_d = 1'b0;

            if (revdat_i) begin
              rx_data_o = {s_xfer_data_q[15:0], s_xfer_data_q[31:16]};
              unique case (datbit_i)
                3'd1:    rx_data_o = {24'd0, s_xfer_data_q[23:16]};
                3'd2:    rx_data_o = {16'd0, s_xfer_data_q[31:16]};
                3'd3:    rx_data_o = {8'd0, s_xfer_data_q[7:0], s_xfer_data_q[31:16]};
                3'd4:    rx_data_o = {s_xfer_data_q[15:0], s_xfer_data_q[31:16]};
                default: rx_data_o = {s_xfer_data_q[15:0], s_xfer_data_q[31:16]};
              endcase
            end else begin
              rx_data_o = s_xfer_data_q;
              unique case (datbit_i)
                3'd1:    rx_data_o = {24'd0, s_xfer_data_q[7:0]};
                3'd2:    rx_data_o = {16'd0, s_xfer_data_q[15:0]};
                3'd3:    rx_data_o = {8'd0, s_xfer_data_q[23:0]};
                3'd4:    rx_data_o = s_xfer_data_q;
                default: rx_data_o = s_xfer_data_q;
              endcase
            end
          end
          // xfer done
          if (s_xfer_byte_cnt_q == 8'd1) begin
            s_fsm_d          = FSM_DONE;
            s_sclk_en_d      = 1'b0;
            s_xfer_bit_cnt_d = 8'd2;  // TODO: can config
          end else begin
            s_xfer_bit_cnt_d  = {2'd0, datbit_i, 3'd0};
            s_xfer_byte_cnt_d = s_xfer_byte_cnt_q - 1'b1;
          end
        end
      end
      FSM_DONE: begin
        if (s_xfer_bit_cnt_q == '0) begin
          s_fsm_d          = FSM_HLVD;
          s_nss_d          = 1'b1;
          s_xfer_bit_cnt_d = hlvlen_i;
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
        s_xfer_bit_cnt_d    = s_xfer_bit_cnt_q;
        s_xfer_byte_cnt_d   = s_xfer_byte_cnt_q;
        s_xfer_data_d       = s_xfer_data_q;
        s_tx_data_req_d     = '0;
        s_rx_data_req_d     = '0;
        // system
        rx_data_o           = '0;
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
      s_xfer_sta_trg | s_sec_clk_edge | s_xfer_end_trg,
      s_nss_d,
      s_nss_q
  );

  dffer #(1) u_sclk_en_dffer (
      clk_i,
      rst_n_i,
      s_xfer_sta_trg | s_sec_clk_edge | s_xfer_end_trg,
      s_sclk_en_d,
      s_sclk_en_q
  );

  dffer #(8) u_xfer_bit_cnt_dffer (
      clk_i,
      rst_n_i,
      s_xfer_sta_trg | s_sec_clk_edge | s_xfer_end_trg,
      s_xfer_bit_cnt_d,
      s_xfer_bit_cnt_q
  );


  dffer #(8) u_xfer_byte_cnt_dffer (
      clk_i,
      rst_n_i,
      s_xfer_sta_trg | s_sec_clk_edge | s_xfer_end_trg,
      s_xfer_byte_cnt_d,
      s_xfer_byte_cnt_q
  );

  dffer #(32) u_xfer_data_dffer (
      clk_i,
      rst_n_i,
      s_xfer_sta_trg | 
      (s_fsm_q != FSM_RXDATA && s_sec_clk_edge) |
      (s_fsm_q == FSM_RXDATA && s_fir_clk_edge) |
      s_xfer_end_trg,
      s_xfer_data_d,
      s_xfer_data_q
  );

  dffer #(1) u_tx_data_req_dffer (
      clk_i,
      rst_n_i,
      s_xfer_sta_trg | s_sec_clk_edge | s_tx_data_req_q,
      s_tx_data_req_d,
      s_tx_data_req_q
  );


  dffer #(1) u_rx_data_req_dffer (
      clk_i,
      rst_n_i,
      (s_fsm_q == FSM_RXDATA && s_fir_clk_edge) | s_rx_data_req_q,
      s_rx_data_req_d,
      s_rx_data_req_q
  );

endmodule
