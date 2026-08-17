// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "i2s_define.svh"

module i2s_reg (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic        clk_i,
    input  logic        rst_n_i,
    apb4_if.slave       apb4,
    input  logic        tx_full_i,
    input  logic        tx_empty_i,
    input  logic [ 7:0] tx_level_i,
    input  logic        rx_full_i,
    input  logic        rx_empty_i,
    input  logic [ 7:0] rx_level_i,
    input  logic        tx_flush_busy_i,
    input  logic        rx_flush_busy_i,
    input  logic        tx_underrun_i,
    input  logic        rx_overrun_i,
    output logic        tx_push_valid_o,
    output logic [31:0] tx_push_data_o,
    output logic        rx_pop_valid_o,
    input  logic [31:0] rx_pop_data_i,
    output logic [31:0] cfg_o,
    output logic        cmd_tx_flush_o,
    output logic        cmd_rx_flush_o,
    output logic        cmd_valid_o,
    input  logic        cmd_ready_i,
    output logic        stream_tx_enable_o,
    output logic        stream_rx_enable_o,
    output logic        dma_tx_stall_o,
    output logic        dma_rx_stall_o,
    output logic        irq_o
    // verilog_format: on
);
  localparam logic [31:0] CtrlMask = 32'h0000_001F;
  localparam logic [31:0] StreamMask = 32'h0000_0003;
  localparam logic [31:0] FormatMask = 32'h0000_0007;
  localparam logic [31:0] ClkDivMask = 32'h00FF_FFFF;
  localparam logic [31:0] FifoThMask = 32'h0000_FFFF;
  localparam logic [31:0] FifoThReset = 32'h0000_00FF;

  logic        s_req;
  logic        s_write;
  logic        s_accept;
  logic [11:0] s_offset;
  logic        s_aligned;
  logic        s_access_err;
  logic        s_ready_q;
  logic s_resp_err_d, s_resp_err_q;
  logic [31:0] s_rdata_d, s_rdata_q;
  logic [31:0] s_ctrl_d, s_ctrl_q;
  logic [31:0] s_stream_d, s_stream_q;
  logic [31:0] s_format_d, s_format_q;
  logic [31:0] s_clk_d, s_clk_q;
  logic [31:0] s_fifo_th_d, s_fifo_th_q;
  logic [3:0] s_intr_stat_q;
  logic [3:0] s_intr_en_q;
  logic [1:0] s_cmd_q;
  logic s_tx_stall_d, s_tx_stall_q;
  logic s_rx_stall_d, s_rx_stall_q;
  logic [ 7:0] s_upbound;
  logic [ 7:0] s_lowbound;
  logic [31:0] s_ctrl_merged;
  logic        s_tx_low_evt;
  logic        s_rx_high_evt;

  function automatic logic [31:0] merge_wstrb(
      input logic [31:0] current_i, input logic [31:0] value_i, input logic [3:0] strobe_i);
    logic [31:0] merged;
    begin
      merged = current_i;
      for (int index = 0; index < 4; index++) begin
        if (strobe_i[index]) merged[index*8+:8] = value_i[index*8+:8];
      end
      return merged;
    end
  endfunction

  assign s_req = apb4.psel && apb4.penable && !s_ready_q;
  assign s_write = |apb4.pstrb;
  assign s_accept = s_req;
  assign s_offset = apb4.paddr[11:0];
  assign s_aligned = apb4.paddr[1:0] == 2'b00;
  assign apb4.pready = s_ready_q;
  assign apb4.prdata = s_rdata_q;
  assign apb4.pslverr = s_resp_err_q;
  assign stream_tx_enable_o = s_stream_q[`APB4_I2S__STREAM_TX];
  assign stream_rx_enable_o = s_stream_q[`APB4_I2S__STREAM_RX];
  assign dma_tx_stall_o = s_tx_stall_q;
  assign dma_rx_stall_o = s_rx_stall_q;
  assign irq_o = |(s_intr_stat_q & s_intr_en_q);
  assign s_upbound = s_fifo_th_q[`APB4_I2S__FIFO_UPBOUND_LSB+:8];
  assign s_lowbound = s_fifo_th_q[`APB4_I2S__FIFO_LOWBOUND_LSB+:8];
  assign s_ctrl_merged = merge_wstrb(s_ctrl_q, apb4.pwdata, apb4.pstrb) & CtrlMask;
  assign tx_push_valid_o = s_accept && s_write && !s_access_err && (s_offset == `APB4_I2S_TXDATA);
  assign tx_push_data_o = apb4.pwdata;
  assign rx_pop_valid_o = s_accept && !s_write && !s_access_err && (s_offset == `APB4_I2S_RXDATA);
  assign cmd_valid_o = |s_cmd_q;
  assign cmd_tx_flush_o = s_cmd_q[`APB4_I2S__COMMAND_TX_FLUSH];
  assign cmd_rx_flush_o = s_cmd_q[`APB4_I2S__COMMAND_RX_FLUSH];
  assign s_tx_low_evt        = s_ctrl_q[`APB4_I2S__CTRL_ENABLE] &&
                               s_ctrl_q[`APB4_I2S__CTRL_TX_ENABLE] && (tx_level_i < s_lowbound);
  assign s_rx_high_evt       = s_ctrl_q[`APB4_I2S__CTRL_ENABLE] &&
                               s_ctrl_q[`APB4_I2S__CTRL_RX_ENABLE] && (rx_level_i > s_upbound);

  always_comb begin
    cfg_o                             = '0;
    cfg_o[`APB4_I2S__CFG_ENABLE]      = s_ctrl_q[`APB4_I2S__CTRL_ENABLE];
    cfg_o[`APB4_I2S__CFG_TX_ENABLE]   = s_ctrl_q[`APB4_I2S__CTRL_TX_ENABLE];
    cfg_o[`APB4_I2S__CFG_RX_ENABLE]   = s_ctrl_q[`APB4_I2S__CTRL_RX_ENABLE];
    cfg_o[`APB4_I2S__CFG_LOOPBACK]    = s_ctrl_q[`APB4_I2S__CTRL_LOOPBACK];
    cfg_o[`APB4_I2S__CFG_CLK_PROG]    = s_ctrl_q[`APB4_I2S__CTRL_CLK_PROG];
    cfg_o[`APB4_I2S__CFG_FORMAT]      = s_format_q[`APB4_I2S__FORMAT_PRESET];
    cfg_o[`APB4_I2S__CFG_BITMODE]     = s_format_q[`APB4_I2S__FORMAT_BITMODE];
    cfg_o[`APB4_I2S__CFG_SCLK_LSB+:8] = s_clk_q[`APB4_I2S__CLK_SCLK_LSB+:8];
    cfg_o[`APB4_I2S__CFG_LRCK_LSB+:8] = s_clk_q[`APB4_I2S__CLK_LRCK_LSB+:8];
    cfg_o[`APB4_I2S__CFG_MCLK_LSB+:8] = s_clk_q[`APB4_I2S__CLK_MCLK_LSB+:8];
  end

  always_comb begin
    s_access_err = !s_aligned;
    s_rdata_d    = 32'd0;
    if (s_aligned) begin
      unique case (s_offset)
        `APB4_I2S_CTRL:        s_rdata_d = s_ctrl_q;
        `APB4_I2S_COMMAND:     s_access_err = !s_write;
        `APB4_I2S_STATUS: begin
          s_rdata_d = {
            6'd0,
            rx_flush_busy_i,
            tx_flush_busy_i,
            rx_level_i,
            tx_level_i,
            tx_flush_busy_i || rx_flush_busy_i || s_ctrl_q[`APB4_I2S__CTRL_ENABLE],
            s_ctrl_q[`APB4_I2S__CTRL_ENABLE],
            s_rx_stall_q,
            s_tx_stall_q,
            rx_empty_i,
            rx_full_i,
            tx_empty_i,
            tx_full_i
          };
          s_access_err = s_write;
        end
        `APB4_I2S_STREAM_CTRL: s_rdata_d = s_stream_q;
        `APB4_I2S_FORMAT:      s_rdata_d = s_format_q;
        `APB4_I2S_CLK_DIV:     s_rdata_d = s_clk_q;
        `APB4_I2S_FIFO_TH:     s_rdata_d = s_fifo_th_q;
        `APB4_I2S_TXDATA:      s_access_err = !s_write;
        `APB4_I2S_RXDATA: begin
          s_rdata_d    = rx_pop_data_i;
          s_access_err = s_write;
        end
        `APB4_I2S_INTR_STATE:  s_rdata_d = {28'd0, s_intr_stat_q};
        `APB4_I2S_INTR_ENABLE: s_rdata_d = {28'd0, s_intr_en_q};
        `APB4_I2S_INTR_STATUS: begin
          s_rdata_d    = {28'd0, s_intr_stat_q & s_intr_en_q};
          s_access_err = s_write;
        end
        `APB4_I2S_INTR_TEST:   s_access_err = !s_write;
        `APB4_I2S_IP_VERSION: begin
          s_rdata_d    = `I2S_IP_VERSION_VALUE;
          s_access_err = s_write;
        end
        `APB4_I2S_CAPABILITY: begin
          s_rdata_d    = `I2S_CAPABILITY_VALUE;
          s_access_err = s_write;
        end
        default:               s_access_err = 1'b1;
      endcase
    end
    if (s_accept && s_write && (s_offset == `APB4_I2S_FORMAT) &&
        s_ctrl_q[`APB4_I2S__CTRL_ENABLE]) begin
      s_access_err = 1'b1;
    end
    if (s_accept && s_write && (s_offset == `APB4_I2S_CLK_DIV) &&
        s_ctrl_q[`APB4_I2S__CTRL_ENABLE]) begin
      s_access_err = 1'b1;
    end
    if (s_accept && s_write && (s_offset == `APB4_I2S_CTRL) && s_ctrl_q[`APB4_I2S__CTRL_ENABLE] &&
        s_ctrl_merged[`APB4_I2S__CTRL_ENABLE] &&
        (s_ctrl_merged[`APB4_I2S__CTRL_CLK_PROG] != s_ctrl_q[`APB4_I2S__CTRL_CLK_PROG])) begin
      s_access_err = 1'b1;
    end
    if (s_accept && s_write && (s_offset == `APB4_I2S_TXDATA) &&
        ((apb4.pstrb != 4'hF) || stream_tx_enable_o || tx_full_i)) begin
      s_access_err = 1'b1;
    end
    if (s_accept && !s_write && (s_offset == `APB4_I2S_RXDATA) &&
        (stream_rx_enable_o || rx_empty_i)) begin
      s_access_err = 1'b1;
    end
    if (s_accept && s_write && (s_offset == `APB4_I2S_COMMAND)) begin
      if (!apb4.pstrb[0]) s_access_err = 1'b1;
      if (apb4.pwdata[`APB4_I2S__COMMAND_TX_FLUSH] && tx_flush_busy_i) s_access_err = 1'b1;
      if (apb4.pwdata[`APB4_I2S__COMMAND_RX_FLUSH] && rx_flush_busy_i) s_access_err = 1'b1;
    end
    s_resp_err_d = s_accept && s_access_err;
  end

  always_comb begin
    s_ctrl_d    = s_ctrl_q;
    s_stream_d  = s_stream_q;
    s_format_d  = s_format_q;
    s_clk_d     = s_clk_q;
    s_fifo_th_d = s_fifo_th_q;
    if (s_accept && s_write && !s_access_err) begin
      unique case (s_offset)
        `APB4_I2S_CTRL: s_ctrl_d = s_ctrl_merged;
        `APB4_I2S_STREAM_CTRL:
        s_stream_d = merge_wstrb(s_stream_q, apb4.pwdata, apb4.pstrb) & StreamMask;
        `APB4_I2S_FORMAT:
        s_format_d = merge_wstrb(s_format_q, apb4.pwdata, apb4.pstrb) & FormatMask;
        `APB4_I2S_CLK_DIV: s_clk_d = merge_wstrb(s_clk_q, apb4.pwdata, apb4.pstrb) & ClkDivMask;
        `APB4_I2S_FIFO_TH:
        s_fifo_th_d = merge_wstrb(s_fifo_th_q, apb4.pwdata, apb4.pstrb) & FifoThMask;
        default: ;
      endcase
    end
  end

  dffr #(
      .DATA_WIDTH(32)
  ) u_ctrl_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ctrl_d),
      .dat_o  (s_ctrl_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_stream_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_stream_d),
      .dat_o  (s_stream_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_format_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_format_d),
      .dat_o  (s_format_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_clk_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_clk_d),
      .dat_o  (s_clk_q)
  );
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) s_fifo_th_q <= FifoThReset;
    else s_fifo_th_q <= s_fifo_th_d;
  end

  always_comb begin
    s_tx_stall_d = s_tx_stall_q;
    if (!s_tx_stall_q && (tx_level_i > s_upbound)) s_tx_stall_d = 1'b1;
    else if (s_tx_stall_q && (tx_level_i < s_lowbound)) s_tx_stall_d = 1'b0;
  end
  always_comb begin
    s_rx_stall_d = s_rx_stall_q;
    if (!s_rx_stall_q && (rx_level_i < s_lowbound)) s_rx_stall_d = 1'b1;
    else if (s_rx_stall_q && (rx_level_i > s_upbound)) s_rx_stall_d = 1'b0;
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_tx_stall_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_stall_d),
      .dat_o  (s_tx_stall_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rx_stall_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_stall_d),
      .dat_o  (s_rx_stall_q)
  );

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_cmd_q       <= '0;
      s_intr_stat_q <= '0;
      s_intr_en_q   <= '0;
    end else begin
      if (cmd_valid_o && cmd_ready_i) s_cmd_q <= '0;
      if (s_accept && s_write && !s_access_err && (s_offset == `APB4_I2S_COMMAND)) begin
        s_cmd_q <= s_cmd_q | apb4.pwdata[1:0];
      end
      if (s_accept && s_write && !s_access_err && (s_offset == `APB4_I2S_INTR_STATE)) begin
        s_intr_stat_q <= s_intr_stat_q & ~apb4.pwdata[3:0];
      end
      if (s_tx_low_evt) s_intr_stat_q[`APB4_I2S__INTR_TX_LOW] <= 1'b1;
      if (s_rx_high_evt) s_intr_stat_q[`APB4_I2S__INTR_RX_HIGH] <= 1'b1;
      if (tx_underrun_i) s_intr_stat_q[`APB4_I2S__INTR_TX_UNDERRUN] <= 1'b1;
      if (rx_overrun_i) s_intr_stat_q[`APB4_I2S__INTR_RX_OVERRUN] <= 1'b1;
      if (s_accept && s_write && !s_access_err && (s_offset == `APB4_I2S_INTR_ENABLE)) begin
        s_intr_en_q <= apb4.pwdata[3:0];
      end
      if (s_accept && s_write && !s_access_err && (s_offset == `APB4_I2S_INTR_TEST)) begin
        s_intr_stat_q <= s_intr_stat_q | apb4.pwdata[3:0];
      end
    end
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (apb4.psel && apb4.penable && !s_ready_q),
      .dat_o  (s_ready_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_accept && !s_write),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );
  dffer #(
      .DATA_WIDTH(1)
  ) u_resp_err_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_accept),
      .dat_i  (s_resp_err_d),
      .dat_o  (s_resp_err_q)
  );
endmodule
