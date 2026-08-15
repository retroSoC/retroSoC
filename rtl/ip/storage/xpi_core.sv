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

module xpi_core (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic                     clk_i,
    input  logic                     rst_n_i,
    input  logic                     mode_i,
    input  logic [`XPI_LNS_NUM-1:0]  nss_i,
    input  logic [              7:0] clkdiv_i,
    input  logic                     rdwr_i,
    input  logic                     revdat_i,
    input  logic [              1:0] cmdtyp_i,
    input  logic [              2:0] cmdlen_i,
    input  logic [             31:0] cmddat_i,
    input  logic [              1:0] adrtyp_i,
    input  logic [              2:0] adrlen_i,
    input  logic [             31:0] adrdat_i,
    input  logic [              7:0] tdulen_i,
    input  logic [              7:0] rdulen_i,
    input  logic [              1:0] dattyp_i,
    input  logic [              7:0] datlen_i,
    input  logic [              2:0] datbit_i,
    input  logic [              7:0] hlvlen_i,
    // tx fifo
    output logic                     tx_data_req_o,
    input  logic                     tx_data_rdy_i,
    input  logic [             31:0] tx_data_i,
    // rx fifo
    output logic                     rx_data_req_o,
    input  logic                     rx_data_rdy_i,
    output logic [             31:0] rx_data_o,
    // common
    input  logic                     start_i,
    output logic                     done_o,
    input  logic [              7:0] tx_elem_num_i,
    input  logic                     dma_xfer_done_i,
    xpi_if.dut                       xpi
);
  // verilog_format: on

  // One XPI transfer is active at a time. start_i or DMA flow control begins a
  // transfer; done_o marks completion, while FIFO ready inputs provide pacing.
  typedef enum logic [2:0] {
    Idle      = 3'd0,
    Command   = 3'd1,
    Address   = 3'd2,
    Dummy     = 3'd3,
    TxData    = 3'd4,
    RxData    = 3'd5,
    Done      = 3'd6,
    HoldValid = 3'd7
  } xpi_state_e;

  // sclk
  logic s_sclk, s_sclk_en_d, s_sclk_en_q;
  logic s_nss_d, s_nss_q;
  logic s_fir_clk_edge, s_sec_clk_edge;
  // xfer
  logic [31:0] s_xfer_data_d, s_xfer_data_q;
  logic [7:0] s_dumlen;
  // [1-32]bits
  logic [7:0] s_xfer_bit_cnt_d, s_xfer_bit_cnt_q;
  logic [7:0] s_xfer_byte_cnt_d, s_xfer_byte_cnt_q;
  logic [7:0] s_xfer_datlen;
  logic s_tx_data_req_d, s_tx_data_req_q;
  logic s_rx_data_req_d, s_rx_data_req_q;
  // common
  xpi_state_e s_fsm_d, s_fsm_q;
  logic [2:0] s_fsm_bits_q;
  logic s_xfer_condi, s_xfer_sta_trg, s_xfer_end_trg;
  logic s_dma_xfer_start, s_dma_xfer_trg;
  logic [7:0] s_dma_xfer_datlen;
  logic [3:0] s_xpi_io_oe, s_xpi_io_do;


  assign xpi.sck_o = s_sclk;
  assign s_fsm_q   = xpi_state_e'(s_fsm_bits_q);
  always_comb begin
    xpi.nss_o        = 4'b1111;
    xpi.nss_o[nss_i] = s_nss_q;
  end
  assign xpi.irq_o     = '0;
  assign xpi.io_oe_o   = s_xpi_io_oe;
  assign xpi.io_do_o   = s_xpi_io_do;
  assign tx_data_req_o = s_tx_data_req_q;
  assign rx_data_req_o = s_rx_data_req_q;


  // dma hw flow ctrl
  always_comb begin
    s_dma_xfer_trg = 1'b0;
    if (tx_elem_num_i >= datlen_i) s_dma_xfer_trg = 1'b1;
    else if (dma_xfer_done_i && (|tx_elem_num_i) && (tx_elem_num_i < datlen_i))
      s_dma_xfer_trg = 1'b1;
  end


  assign s_xfer_datlen = mode_i ? s_dma_xfer_datlen : datlen_i;
  always_comb begin
    if (dma_xfer_done_i && (tx_elem_num_i < datlen_i)) s_dma_xfer_datlen = tx_elem_num_i;
    else s_dma_xfer_datlen = datlen_i;
  end


  assign s_xfer_condi   = (~mode_i && start_i) || (mode_i && s_dma_xfer_trg);
  assign s_xfer_sta_trg = s_fsm_q == Idle && s_xfer_condi;
  assign s_xfer_end_trg = s_fsm_q == Done || s_fsm_q == HoldValid;
  assign s_dumlen       = rdwr_i ? rdulen_i : tdulen_i;


  xpi_clkgen u_xpi_clkgen (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .div_i         (clkdiv_i),
      .en_i          (s_sclk_en_q),
      .clk_o         (s_sclk),
      .fir_clk_edge_o(s_fir_clk_edge),
      .sec_clk_edge_o(s_sec_clk_edge)
  );


  // Keep pad drive independent from the receive-data path. This preserves the
  // bidirectional pad readback model without creating an input-to-output loop.
  always_comb begin
    s_xpi_io_oe    = '0;
    s_xpi_io_oe[0] = 1'b1;
    s_xpi_io_do    = '0;
    unique case (s_fsm_q)
      Command: begin
        unique case (cmdtyp_i)
          `XPI_TYPE_SNGL: begin
            s_xpi_io_oe[0] = 1'b1;
            s_xpi_io_do[0] = s_xfer_data_q[31];
          end
          `XPI_TYPE_DUAL: begin
            s_xpi_io_oe[1:0] = 2'b11;
            s_xpi_io_do[1:0] = s_xfer_data_q[31:30];
          end
          `XPI_TYPE_QUAD: begin
            s_xpi_io_oe[3:0] = 4'b1111;
            s_xpi_io_do[3:0] = s_xfer_data_q[31:28];
          end
          default: begin
            s_xpi_io_oe[0] = 1'b1;
            s_xpi_io_do[0] = s_xfer_data_q[31];
          end
        endcase
      end
      Address: begin
        unique case (adrtyp_i)
          `XPI_TYPE_SNGL: begin
            s_xpi_io_oe[0] = 1'b1;
            s_xpi_io_do[0] = s_xfer_data_q[31];
          end
          `XPI_TYPE_DUAL: begin
            s_xpi_io_oe[1:0] = 2'b11;
            s_xpi_io_do[1:0] = s_xfer_data_q[31:30];
          end
          `XPI_TYPE_QUAD: begin
            s_xpi_io_oe[3:0] = 4'b1111;
            s_xpi_io_do[3:0] = s_xfer_data_q[31:28];
          end
          default: begin
            s_xpi_io_oe[0] = 1'b1;
            s_xpi_io_do[0] = s_xfer_data_q[31];
          end
        endcase
      end
      Dummy, RxData: begin
        s_xpi_io_oe = '0;
      end
      TxData: begin
        unique case (dattyp_i)
          `XPI_TYPE_SNGL: begin
            s_xpi_io_oe[0] = 1'b1;
            s_xpi_io_do[0] = s_xfer_data_q[31];
          end
          `XPI_TYPE_DUAL: begin
            s_xpi_io_oe[1:0] = 2'b11;
            s_xpi_io_do[1:0] = s_xfer_data_q[31:30];
          end
          `XPI_TYPE_QUAD: begin
            s_xpi_io_oe[3:0] = 4'b1111;
            s_xpi_io_do[3:0] = s_xfer_data_q[31:28];
          end
          default: begin
            s_xpi_io_oe[0] = 1'b1;
            s_xpi_io_do[0] = s_xfer_data_q[31];
          end
        endcase
      end
      default: begin
      end
    endcase
  end


  always_comb begin
    s_fsm_d           = s_fsm_q;
    s_nss_d           = s_nss_q;
    s_sclk_en_d       = s_sclk_en_q;
    s_xfer_bit_cnt_d  = s_xfer_bit_cnt_q;
    s_xfer_byte_cnt_d = s_xfer_byte_cnt_q;
    s_xfer_data_d     = s_xfer_data_q;
    s_tx_data_req_d   = '0;
    s_rx_data_req_d   = '0;
    // system
    rx_data_o         = '0;
    done_o            = 1'b0;
    unique case (s_fsm_q)
      Idle: begin
        if (s_xfer_condi) begin
          s_nss_d     = 1'b0;
          s_sclk_en_d = 1'b1;
          if (cmdtyp_i != `XPI_TYPE_NONE) begin
            s_fsm_d          = Command;
            s_xfer_bit_cnt_d = {2'd0, cmdlen_i, 3'd0};
            s_xfer_data_d    = cmddat_i;
          end else if (adrtyp_i != `XPI_TYPE_NONE) begin
            s_fsm_d          = Address;
            s_xfer_bit_cnt_d = {2'd0, adrlen_i, 3'd0};
            s_xfer_data_d    = adrdat_i;
          end else if (s_dumlen != '0) begin
            s_fsm_d          = Dummy;
            s_xfer_bit_cnt_d = s_dumlen;
            s_xfer_data_d    = '0;
          end else if (dattyp_i != `XPI_TYPE_NONE) begin
            if (rdwr_i) s_fsm_d = RxData;
            else s_fsm_d = TxData;
            s_xfer_bit_cnt_d  = {2'd0, datbit_i, 3'd0};
            s_xfer_byte_cnt_d = s_xfer_datlen;
            if (tx_data_rdy_i) begin
              if (revdat_i) s_xfer_data_d = {tx_data_i[15:0], tx_data_i[31:16]};
              else s_xfer_data_d = tx_data_i;
              s_tx_data_req_d = 1'b1;
            end else s_xfer_data_d = '0;
          end else begin
            s_fsm_d     = Done;
            s_sclk_en_d = 1'b0;
          end
        end
      end
      Command: begin
        unique case (cmdtyp_i)
          `XPI_TYPE_SNGL: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd1;
            s_xfer_data_d    = {s_xfer_data_q[30:0], 1'd0};
          end
          `XPI_TYPE_DUAL: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd2;
            s_xfer_data_d    = {s_xfer_data_q[29:0], 2'd0};
          end
          `XPI_TYPE_QUAD: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd4;
            s_xfer_data_d    = {s_xfer_data_q[27:0], 4'd0};
          end
          default: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd1;
            s_xfer_data_d    = {s_xfer_data_q[30:0], 1'd0};
          end
        endcase

        if ((cmdtyp_i == `XPI_TYPE_SNGL && s_xfer_bit_cnt_q == 8'd1) ||
            (cmdtyp_i == `XPI_TYPE_DUAL && s_xfer_bit_cnt_q == 8'd2) ||
            (cmdtyp_i == `XPI_TYPE_QUAD && s_xfer_bit_cnt_q == 8'd4)) begin
          if (adrtyp_i != `XPI_TYPE_NONE) begin
            s_fsm_d          = Address;
            s_xfer_bit_cnt_d = {2'd0, adrlen_i, 3'd0};
            s_xfer_data_d    = adrdat_i;
          end else if (s_dumlen != '0) begin
            s_fsm_d          = Dummy;
            s_xfer_bit_cnt_d = s_dumlen;
            s_xfer_data_d    = '0;
          end else if (dattyp_i != `XPI_TYPE_NONE) begin
            if (rdwr_i) s_fsm_d = RxData;
            else s_fsm_d = TxData;
            s_xfer_bit_cnt_d  = {2'd0, datbit_i, 3'd0};
            s_xfer_byte_cnt_d = s_xfer_datlen;
            if (tx_data_rdy_i) begin
              if (revdat_i) s_xfer_data_d = {tx_data_i[15:0], tx_data_i[31:16]};
              else s_xfer_data_d = tx_data_i;
              s_tx_data_req_d = 1'b1;
            end else s_xfer_data_d = '0;
          end else begin
            s_fsm_d     = Done;
            s_sclk_en_d = 1'b0;
          end
        end
      end
      Address: begin
        unique case (adrtyp_i)
          `XPI_TYPE_SNGL: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd1;
            s_xfer_data_d    = {s_xfer_data_q[30:0], 1'd0};
          end
          `XPI_TYPE_DUAL: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd2;
            s_xfer_data_d    = {s_xfer_data_q[29:0], 2'd0};
          end
          `XPI_TYPE_QUAD: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd4;
            s_xfer_data_d    = {s_xfer_data_q[27:0], 4'd0};
          end
          default: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd1;
            s_xfer_data_d    = {s_xfer_data_q[30:0], 1'd0};
          end
        endcase

        if ((adrtyp_i == `XPI_TYPE_SNGL && s_xfer_bit_cnt_q == 8'd1) ||
            (adrtyp_i == `XPI_TYPE_DUAL && s_xfer_bit_cnt_q == 8'd2) ||
            (adrtyp_i == `XPI_TYPE_QUAD && s_xfer_bit_cnt_q == 8'd4)) begin
          if (s_dumlen != '0) begin
            s_fsm_d          = Dummy;
            s_xfer_bit_cnt_d = s_dumlen;
            s_xfer_data_d    = '0;
          end else if (dattyp_i != `XPI_TYPE_NONE) begin
            if (rdwr_i) s_fsm_d = RxData;
            else s_fsm_d = TxData;
            s_xfer_bit_cnt_d  = {2'd0, datbit_i, 3'd0};
            s_xfer_byte_cnt_d = s_xfer_datlen;
            if (tx_data_rdy_i) begin
              if (revdat_i) s_xfer_data_d = {tx_data_i[15:0], tx_data_i[31:16]};
              else s_xfer_data_d = tx_data_i;
              s_tx_data_req_d = 1'b1;
            end else s_xfer_data_d = '0;
          end else begin
            s_fsm_d     = Done;
            s_sclk_en_d = 1'b0;
          end
        end
      end
      Dummy: begin
        s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd1;

        if (s_xfer_bit_cnt_q == 8'd1) begin
          if (dattyp_i != `XPI_TYPE_NONE) begin
            if (rdwr_i) s_fsm_d = RxData;
            else s_fsm_d = TxData;
            s_xfer_bit_cnt_d  = {2'd0, datbit_i, 3'd0};
            s_xfer_byte_cnt_d = s_xfer_datlen;
            if (tx_data_rdy_i) begin
              if (revdat_i) s_xfer_data_d = {tx_data_i[15:0], tx_data_i[31:16]};
              else s_xfer_data_d = tx_data_i;
              s_tx_data_req_d = 1'b1;
            end else s_xfer_data_d = '0;
          end else begin
            s_fsm_d     = Done;
            s_sclk_en_d = 1'b0;
          end
        end
      end
      TxData: begin
        unique case (dattyp_i)
          `XPI_TYPE_SNGL: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd1;
            s_xfer_data_d    = {s_xfer_data_q[30:0], 1'd0};
          end
          `XPI_TYPE_DUAL: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd2;
            s_xfer_data_d    = {s_xfer_data_q[29:0], 2'd0};
          end
          `XPI_TYPE_QUAD: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd4;
            s_xfer_data_d    = {s_xfer_data_q[27:0], 4'd0};
          end
          default: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd1;
            s_xfer_data_d    = {s_xfer_data_q[30:0], 1'd0};
          end
        endcase

        if ((dattyp_i == `XPI_TYPE_SNGL && s_xfer_bit_cnt_q == 8'd1) ||
            (dattyp_i == `XPI_TYPE_DUAL && s_xfer_bit_cnt_q == 8'd2) ||
            (dattyp_i == `XPI_TYPE_QUAD && s_xfer_bit_cnt_q == 8'd4)) begin
          if (s_xfer_byte_cnt_q == 8'd1) begin
            s_fsm_d          = Done;
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
      RxData: begin
        unique case (dattyp_i)
          `XPI_TYPE_SNGL: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd1;
            s_xfer_data_d    = {s_xfer_data_q[30:0], xpi.io_di_i[1]};
          end
          `XPI_TYPE_DUAL: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd2;
            s_xfer_data_d    = {s_xfer_data_q[29:0], xpi.io_di_i[1:0]};
          end
          `XPI_TYPE_QUAD: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd4;
            s_xfer_data_d    = {s_xfer_data_q[27:0], xpi.io_di_i[3:0]};
          end
          default: begin
            s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 8'd1;
            s_xfer_data_d    = {s_xfer_data_q[30:0], xpi.io_di_i[1]};
          end
        endcase

        if ((dattyp_i == `XPI_TYPE_SNGL && s_xfer_bit_cnt_q == 8'd1) ||
            (dattyp_i == `XPI_TYPE_DUAL && s_xfer_bit_cnt_q == 8'd2) ||
            (dattyp_i == `XPI_TYPE_QUAD && s_xfer_bit_cnt_q == 8'd4)) begin
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
                3'd1: rx_data_o = {24'd0, s_xfer_data_q[7:0]};
                3'd2: rx_data_o = {16'd0, s_xfer_data_q[15:0]};
                3'd3: rx_data_o = {8'd0, s_xfer_data_q[23:0]};
                3'd4:
                rx_data_o = {
                  s_xfer_data_q[7:0],
                  s_xfer_data_q[15:8],
                  s_xfer_data_q[23:16],
                  s_xfer_data_q[31:24]
                };  // HACK:
                default:
                rx_data_o = {
                  s_xfer_data_q[7:0],
                  s_xfer_data_q[15:8],
                  s_xfer_data_q[23:16],
                  s_xfer_data_q[31:24]
                };  // HACK:
              endcase
            end
          end
          // xfer done
          if (s_xfer_byte_cnt_q == 8'd1) begin
            s_fsm_d          = Done;
            s_sclk_en_d      = 1'b0;
            s_xfer_bit_cnt_d = 8'd2;  // TODO: can config
          end else begin
            s_xfer_bit_cnt_d  = {2'd0, datbit_i, 3'd0};
            s_xfer_byte_cnt_d = s_xfer_byte_cnt_q - 1'b1;
          end
        end
      end
      Done: begin
        if (s_xfer_bit_cnt_q == '0) begin
          s_fsm_d          = HoldValid;
          s_nss_d          = 1'b1;
          s_xfer_bit_cnt_d = hlvlen_i;
          s_xfer_data_d    = '0;
        end else begin
          s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 1'b1;
        end
      end
      HoldValid: begin
        if (s_xfer_bit_cnt_q == '0) begin
          s_fsm_d = Idle;
          done_o  = 1'b1;
        end else begin
          s_xfer_bit_cnt_d = s_xfer_bit_cnt_q - 1'b1;
        end
      end
      default: begin
        s_fsm_d           = s_fsm_q;
        s_nss_d           = s_nss_q;
        s_sclk_en_d       = s_sclk_en_q;
        s_xfer_bit_cnt_d  = s_xfer_bit_cnt_q;
        s_xfer_byte_cnt_d = s_xfer_byte_cnt_q;
        s_xfer_data_d     = s_xfer_data_q;
        s_tx_data_req_d   = '0;
        s_rx_data_req_d   = '0;
        // system
        rx_data_o         = '0;
        done_o            = 1'b0;
      end
    endcase
  end
  dffer #(
      .DATA_WIDTH(3)
  ) u_fsm_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_xfer_sta_trg | s_sec_clk_edge | s_xfer_end_trg),
      .dat_i  (s_fsm_d),
      .dat_o  (s_fsm_bits_q)
  );

  dfferh #(
      .DATA_WIDTH(1)
  ) u_nss_dfferh (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_xfer_sta_trg | s_sec_clk_edge | s_xfer_end_trg),
      .dat_i  (s_nss_d),
      .dat_o  (s_nss_q)
  );

  dffer #(
      .DATA_WIDTH(1)
  ) u_sclk_en_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_xfer_sta_trg | s_sec_clk_edge | s_xfer_end_trg),
      .dat_i  (s_sclk_en_d),
      .dat_o  (s_sclk_en_q)
  );

  dffer #(
      .DATA_WIDTH(8)
  ) u_xfer_bit_cnt_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_xfer_sta_trg | s_sec_clk_edge | s_xfer_end_trg),
      .dat_i  (s_xfer_bit_cnt_d),
      .dat_o  (s_xfer_bit_cnt_q)
  );


  dffer #(
      .DATA_WIDTH(8)
  ) u_xfer_byte_cnt_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_xfer_sta_trg | s_sec_clk_edge | s_xfer_end_trg),
      .dat_i  (s_xfer_byte_cnt_d),
      .dat_o  (s_xfer_byte_cnt_q)
  );

  dffer #(
      .DATA_WIDTH(32)
  ) u_xfer_data_dffer (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .en_i(s_xfer_sta_trg |
      (s_fsm_q != RxData && s_sec_clk_edge) |
      (s_fsm_q == RxData && s_fir_clk_edge) |
      s_xfer_end_trg),
      .dat_i(s_xfer_data_d),
      .dat_o(s_xfer_data_q)
  );

  dffer #(
      .DATA_WIDTH(1)
  ) u_tx_data_req_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_xfer_sta_trg | s_sec_clk_edge | s_tx_data_req_q),
      .dat_i  (s_tx_data_req_d),
      .dat_o  (s_tx_data_req_q)
  );


  dffer #(
      .DATA_WIDTH(1)
  ) u_rx_data_req_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   ((s_fsm_q == RxData && s_fir_clk_edge) | s_rx_data_req_q),
      .dat_i  (s_rx_data_req_d),
      .dat_o  (s_rx_data_req_q)
  );

`ifndef SV_ASSRT_DISABLE
`ifndef SYNTHESIS
  a_xpi_read_pad_released :
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      (s_fsm_q == Dummy || s_fsm_q == RxData) |-> s_xpi_io_oe == '0);
`endif
`endif

endmodule
