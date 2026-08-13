// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"
`include "rib_defs.svh"

module dma_core (
    // verilog_format: off
    input  logic                  clk_i,
    input  logic                  rst_n_i,
    input  logic [3:0]            mode_i,
    input  logic [31:0]           srcaddr_i,
    input  logic                  srcincr_i,
    input  logic [31:0]           dstaddr_i,
    input  logic                  dstincr_i,
    input  logic [31:0]           xferlen_i,
    input  logic                  start_i,
    input  logic                  stop_i,
    input  logic                  reset_i,
    output logic                  done_o,
    output logic                  error_o,
    output logic [2:0]            error_code_o,
    output logic [31:0]           error_addr_o,
    output logic [1:0]            fsm_o,
    dma_hw_trg_if.dut             hw_trg,
    rib_if.master                 rib,
    axi4_stream_if.source         i2s_tx_axis,
    axi4_stream_if.sink           i2s_rx_axis,
    axi4_stream_if.sink           dvp_rx_axis
    // verilog_format: on
);

  localparam logic [3:0] SFT_TRG = 4'd0;
  localparam logic [3:0] HWT_I2S_TX_TRG = 4'd1;
  localparam logic [3:0] HWT_I2S_RX_TRG = 4'd2;
  localparam logic [3:0] HWT_QSPI_TX_TRG = 4'd3;
  localparam logic [3:0] HWT_QSPI_RX_TRG = 4'd4;
  localparam logic [3:0] HWT_UART_TX_TRG = 4'd5;
  localparam logic [3:0] HWT_UART_RX_TRG = 4'd6;
  localparam logic [3:0] HWT_I2C0_TX_TRG = 4'd7;
  localparam logic [3:0] HWT_I2C0_RX_TRG = 4'd8;
  localparam logic [3:0] HWT_I2C1_TX_TRG = 4'd9;
  localparam logic [3:0] HWT_I2C1_RX_TRG = 4'd10;
  localparam logic [3:0] HWT_DVP_RX_TRG = 4'd11;

  localparam logic [2:0] FSM_IDLE = 3'd0;
  localparam logic [2:0] FSM_RD_CMD = 3'd1;
  localparam logic [2:0] FSM_RD_RESP = 3'd2;
  localparam logic [2:0] FSM_WR_CMD = 3'd3;
  localparam logic [2:0] FSM_WR_DATA = 3'd4;
  localparam logic [2:0] FSM_WR_RESP = 3'd5;
  localparam logic [2:0] FSM_DONE = 3'd6;

  logic [2:0] s_fsm_d, s_fsm_q;
  logic [31:0] s_xfer_cnt_d, s_xfer_cnt_q;
  logic [31:0] s_src_addr_d, s_src_addr_q;
  logic [31:0] s_dst_addr_d, s_dst_addr_q;
  logic [1:0] s_wr_beat_d, s_wr_beat_q;
  logic s_ctrl_stop_d, s_ctrl_stop_q;
  logic        s_use_burst;
  logic [ 1:0] s_chunk_len;
  logic [31:0] s_chunk_words;
  logic [31:0] s_remaining_words;
  logic        s_read_trigger;
  logic        s_write_trigger;
  logic s_cmd_hdshk, s_rsp_hdshk, s_w_hdshk;
  logic s_fifo_flush, s_fifo_push, s_fifo_pop;
  logic s_fifo_full, s_fifo_empty;
  logic [ 2:0] s_fifo_count;
  logic [35:0] s_fifo_rdata;
  logic        s_rsp_err;
  logic        s_i2s_tx_stream;
  logic        s_i2s_rx_stream;
  logic        s_dvp_rx_stream;
  logic        s_stream_rx_hdshk;
  logic        s_stream_tx_hdshk;

  assign s_remaining_words = xferlen_i - s_xfer_cnt_q;
  // verilog_format: off
  assign s_use_burst =
      (mode_i == SFT_TRG) && srcincr_i && dstincr_i &&
      (s_remaining_words >= 32'd4) &&
      (s_src_addr_q[3:0] == 4'b0000) && (s_dst_addr_q[3:0] == 4'b0000) &&
      `SOC_ADDR_SUPPORTS_INCR4(s_src_addr_q) &&
      `SOC_ADDR_SUPPORTS_INCR4(s_src_addr_q + 32'd12) &&
      `SOC_ADDR_SUPPORTS_INCR4(s_dst_addr_q) &&
      `SOC_ADDR_SUPPORTS_INCR4(s_dst_addr_q + 32'd12);
  // verilog_format: on
  assign s_chunk_len = s_use_burst ? `RIB_LEN_INCR4 : `RIB_LEN_INCR1;
  assign s_chunk_words = s_use_burst ? 32'd4 : 32'd1;
  assign s_i2s_tx_stream = mode_i == HWT_I2S_TX_TRG;
  assign s_i2s_rx_stream = mode_i == HWT_I2S_RX_TRG;
  assign s_dvp_rx_stream = mode_i == HWT_DVP_RX_TRG;

  assign i2s_tx_axis.tdata = s_fifo_rdata[31:0];
  assign i2s_tx_axis.tkeep = '1;
  assign i2s_tx_axis.tstrb = '1;
  assign i2s_tx_axis.tlast = (s_xfer_cnt_q + 1'b1) >= xferlen_i;
  assign i2s_tx_axis.tid = '0;
  assign i2s_tx_axis.tdest = '0;
  assign i2s_tx_axis.tuser = '0;
  assign i2s_tx_axis.tvalid = (s_fsm_q == FSM_WR_DATA) && s_i2s_tx_stream &&
                              !s_fifo_empty;
  assign i2s_rx_axis.tready = (s_fsm_q == FSM_RD_RESP) && s_i2s_rx_stream &&
                              !s_fifo_full;
  assign dvp_rx_axis.tready = (s_fsm_q == FSM_RD_RESP) && s_dvp_rx_stream &&
                             !s_fifo_full;
  assign s_stream_tx_hdshk = i2s_tx_axis.tvalid && i2s_tx_axis.tready;
  assign s_stream_rx_hdshk = (i2s_rx_axis.tvalid && i2s_rx_axis.tready) ||
                             (dvp_rx_axis.tvalid && dvp_rx_axis.tready);

  always_comb begin
    s_read_trigger = 1'b1;
    unique case (mode_i)
      HWT_I2S_RX_TRG:  s_read_trigger = hw_trg.i2s_rx_proc;
      HWT_QSPI_RX_TRG: s_read_trigger = hw_trg.qspi_rx_proc;
      HWT_UART_RX_TRG: s_read_trigger = hw_trg.uart_rx_proc;
      HWT_I2C0_RX_TRG: s_read_trigger = hw_trg.i2c0_rx_proc;
      HWT_I2C1_RX_TRG: s_read_trigger = hw_trg.i2c1_rx_proc;
      default:         s_read_trigger = 1'b1;
    endcase
  end

  always_comb begin
    s_write_trigger = 1'b1;
    unique case (mode_i)
      HWT_I2S_TX_TRG:  s_write_trigger = hw_trg.i2s_tx_proc;
      HWT_QSPI_TX_TRG: s_write_trigger = hw_trg.qspi_tx_proc;
      HWT_UART_TX_TRG: s_write_trigger = hw_trg.uart_tx_proc;
      HWT_I2C0_TX_TRG: s_write_trigger = hw_trg.i2c0_tx_proc;
      HWT_I2C1_TX_TRG: s_write_trigger = hw_trg.i2c1_tx_proc;
      default:         s_write_trigger = 1'b1;
    endcase
  end

  assign rib.cmd_valid = ~s_ctrl_stop_q &&
                         (((s_fsm_q == FSM_RD_CMD) && s_read_trigger) ||
                          ((s_fsm_q == FSM_WR_CMD) && s_write_trigger));
  assign rib.cmd_addr = s_fsm_q == FSM_WR_CMD ? s_dst_addr_q : s_src_addr_q;
  assign rib.cmd_write = s_fsm_q == FSM_WR_CMD;
  assign rib.cmd_len = s_chunk_len;
  assign rib.w_valid = (s_fsm_q == FSM_WR_DATA) && !s_i2s_tx_stream &&
                       ~s_fifo_empty && (s_fifo_count != 3'd0);
  assign rib.wdata = s_fifo_rdata[31:0];
  assign rib.wstrb = s_dvp_rx_stream ? s_fifo_rdata[35:32] : '1;
  assign rib.wlast = s_wr_beat_q == s_chunk_len;
  assign rib.rsp_ready = (s_fsm_q == FSM_RD_RESP) && !(s_i2s_rx_stream || s_dvp_rx_stream) ?
                         (~s_fifo_full && (s_fifo_count != 3'd4)) :
                         (s_fsm_q == FSM_WR_RESP);

  assign s_cmd_hdshk = rib.cmd_valid && rib.cmd_ready;
  assign s_rsp_hdshk = rib.rsp_valid && rib.rsp_ready;
  assign s_w_hdshk = rib.w_valid && rib.w_ready;
  assign s_rsp_err = s_rsp_hdshk && rib.resp_err;

  assign s_fifo_flush = reset_i || start_i || s_rsp_err;
  assign s_fifo_push = (s_i2s_rx_stream || s_dvp_rx_stream) ? s_stream_rx_hdshk :
                       ((s_fsm_q == FSM_RD_RESP) && s_rsp_hdshk && ~rib.resp_err);
  assign s_fifo_pop = s_i2s_tx_stream ? s_stream_tx_hdshk : ((s_fsm_q == FSM_WR_DATA) && s_w_hdshk);

  fifo #(
      .DATA_WIDTH  (36),
      .BUFFER_DEPTH(4)
  ) u_data_fifo (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_fifo_flush),
      .push_i(s_fifo_push),
      .full_o(s_fifo_full),
      .dat_i(s_i2s_rx_stream ? {4'b1111, i2s_rx_axis.tdata} :
             s_dvp_rx_stream ? {dvp_rx_axis.tkeep, dvp_rx_axis.tdata} :
             {4'b1111, rib.rdata}),
      .pop_i(s_fifo_pop),
      .empty_o(s_fifo_empty),
      .dat_o(s_fifo_rdata),
      .cnt_o(s_fifo_count)
  );

  assign fsm_o = s_fsm_q == FSM_IDLE ? 2'd0 : s_fsm_q == FSM_DONE ? 2'd2 : 2'd1;

  always_comb begin
    s_fsm_d      = s_fsm_q;
    s_xfer_cnt_d = s_xfer_cnt_q;
    s_src_addr_d = s_src_addr_q;
    s_dst_addr_d = s_dst_addr_q;
    s_wr_beat_d  = s_wr_beat_q;
    done_o       = 1'b0;
    error_o      = 1'b0;
    error_code_o = `RIB_RESP_OK;
    error_addr_o = s_src_addr_q;

    if (reset_i) begin
      s_fsm_d      = FSM_IDLE;
      s_xfer_cnt_d = '0;
      s_wr_beat_d  = '0;
    end else begin
      unique case (s_fsm_q)
        FSM_IDLE: begin
          if (start_i) begin
            s_src_addr_d = srcaddr_i;
            s_dst_addr_d = dstaddr_i;
            s_xfer_cnt_d = '0;
            s_wr_beat_d = '0;
            s_fsm_d      = xferlen_i == 32'd0 ? FSM_DONE :
                           (s_i2s_rx_stream || s_dvp_rx_stream) ? FSM_RD_RESP : FSM_RD_CMD;
          end
        end
        FSM_RD_CMD: begin
          if (s_cmd_hdshk) begin
            s_fsm_d = FSM_RD_RESP;
          end
        end
        FSM_RD_RESP: begin
          if ((s_i2s_rx_stream || s_dvp_rx_stream) && s_stream_rx_hdshk) begin
            s_wr_beat_d = '0;
            s_fsm_d     = FSM_WR_CMD;
          end else if (s_rsp_hdshk) begin
            if (rib.resp_err) begin
              s_fsm_d      = FSM_IDLE;
              error_o      = 1'b1;
              error_code_o = rib.resp_code;
              error_addr_o = s_src_addr_q + {28'd0, rib.rsp_beat, 2'b00};
            end else if (rib.rsp_last) begin
              s_wr_beat_d = '0;
              s_fsm_d     = s_i2s_tx_stream ? FSM_WR_DATA : FSM_WR_CMD;
            end
          end
        end
        FSM_WR_CMD: begin
          if (s_cmd_hdshk) begin
            s_fsm_d = FSM_WR_DATA;
          end
        end
        FSM_WR_DATA: begin
          if (s_i2s_tx_stream && s_stream_tx_hdshk) begin
            s_xfer_cnt_d = s_xfer_cnt_q + 1'b1;
            if (srcincr_i) s_src_addr_d = s_src_addr_q + 32'd4;
            if ((s_xfer_cnt_q + 1'b1) >= xferlen_i) begin
              s_fsm_d = FSM_DONE;
            end else begin
              s_fsm_d = FSM_RD_CMD;
            end
          end else if (s_w_hdshk) begin
            if (rib.wlast) begin
              s_fsm_d = FSM_WR_RESP;
            end else begin
              s_wr_beat_d = s_wr_beat_q + 1'b1;
            end
          end
        end
        FSM_WR_RESP: begin
          if (s_rsp_hdshk) begin
            if (rib.resp_err) begin
              s_fsm_d      = FSM_IDLE;
              error_o      = 1'b1;
              error_code_o = rib.resp_code;
              error_addr_o = s_dst_addr_q + {28'd0, rib.rsp_beat, 2'b00};
            end else begin
              s_xfer_cnt_d = s_xfer_cnt_q + s_chunk_words;
              if (srcincr_i) s_src_addr_d = s_src_addr_q + (s_chunk_words << 2);
              if (dstincr_i) s_dst_addr_d = s_dst_addr_q + (s_chunk_words << 2);
              if ((s_xfer_cnt_q + s_chunk_words) >= xferlen_i) begin
                s_fsm_d = FSM_DONE;
              end else begin
                s_fsm_d = (s_i2s_rx_stream || s_dvp_rx_stream) ? FSM_RD_RESP : FSM_RD_CMD;
              end
            end
          end
        end
        FSM_DONE: begin
          done_o  = 1'b1;
          s_fsm_d = FSM_IDLE;
        end
        default: s_fsm_d = FSM_IDLE;
      endcase
    end
  end

  dffr #(
      .DATA_WIDTH(3)
  ) u_fsm_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fsm_d),
      .dat_o  (s_fsm_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_xfer_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_xfer_cnt_d),
      .dat_o  (s_xfer_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_src_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_src_addr_d),
      .dat_o  (s_src_addr_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_dst_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dst_addr_d),
      .dat_o  (s_dst_addr_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_wr_beat_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_wr_beat_d),
      .dat_o  (s_wr_beat_q)
  );

  always_comb begin
    s_ctrl_stop_d = s_ctrl_stop_q;
    if (stop_i) s_ctrl_stop_d = ~s_ctrl_stop_q;
    if (reset_i) s_ctrl_stop_d = 1'b0;
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_ctrl_stop_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ctrl_stop_d),
      .dat_o  (s_ctrl_stop_q)
  );

endmodule
