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

/* verilator lint_off DECLFILENAME */
interface i2s_if ();
  logic mclk_o;
  logic sclk_o;
  logic lrck_o;
  logic dacdat_o;
  logic adcdat_i;
  logic irq_o;

  modport dut(
      output mclk_o,
      output sclk_o,
      output lrck_o,
      output dacdat_o,
      input adcdat_i,
      output irq_o
  );
endinterface
/* verilator lint_on DECLFILENAME */

module apb4_i2s (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic          clk_i,
    input  logic          rst_n_i,
    input  logic          clk_aud_i,
    input  logic          rst_aud_n_i,
    output logic          dma_tx_stall_o,
    output logic          dma_rx_stall_o,
    apb4_if.slave         apb4,
    axi4_stream_if.sink   tx_axis,
    axi4_stream_if.source rx_axis,
    i2s_if.dut            i2s
    // verilog_format: on
);
  logic [31:0] s_cfg_sys;
  logic [31:0] s_cfg_aud;
  logic        s_cfg_aud_v;
  logic [31:0] s_cfg_aud_q;
  logic [ 1:0] s_cmd_sys;
  logic        s_cmd_v_sys;
  logic        s_cmd_rdy_sys;
  logic [ 1:0] s_cmd_aud;
  logic        s_cmd_v_aud;
  logic        s_cmd_tx_flush;
  logic        s_cmd_rx_flush;
  logic        s_irq;

  logic        s_stream_tx_en;
  logic        s_stream_rx_en;
  logic        s_tx_pio_push;
  logic [31:0] s_tx_pio_data;
  logic        s_rx_pio_pop;
  logic [31:0] s_rx_pop_data;

  logic        s_tx_src_valid;
  logic        s_tx_src_ready;
  logic [31:0] s_tx_src_data;
  logic        s_tx_dst_valid;
  logic        s_tx_dst_ready;
  logic [31:0] s_tx_dst_data;
  logic        s_tx_src_clear;
  logic        s_tx_src_clear_busy;
  logic        s_tx_dst_clear_busy;
  logic        s_tx_dst_busy_sys;

  logic        s_rx_src_valid;
  logic        s_rx_src_ready;
  logic [31:0] s_rx_src_data;
  logic        s_rx_dst_valid;
  logic        s_rx_dst_ready;
  logic [31:0] s_rx_dst_data;
  logic        s_rx_src_clear;
  logic        s_rx_src_clear_busy;
  logic        s_rx_dst_clear_busy;
  logic        s_rx_src_busy_sys;

  logic [7:0] s_tx_push_cnt_d, s_tx_push_cnt_q;
  logic [7:0] s_rx_pop_cnt_d, s_rx_pop_cnt_q;
  logic [7:0] s_tx_pop_cnt_aud_d, s_tx_pop_cnt_aud_q;
  logic [7:0] s_rx_push_cnt_aud_d, s_rx_push_cnt_aud_q;
  logic [ 7:0] s_tx_pop_cnt_sys;
  logic        s_tx_pop_cnt_sys_v;
  logic [ 7:0] s_rx_push_cnt_sys;
  logic        s_rx_push_cnt_sys_v;
  logic [ 7:0] s_tx_pop_cnt_sys_q;
  logic [ 7:0] s_rx_push_cnt_sys_q;
  logic [ 7:0] s_tx_level;
  logic [ 7:0] s_rx_level;
  logic        s_tx_push;
  logic        s_rx_pop;
  logic        s_tx_flush_busy;
  logic        s_rx_flush_busy;

  logic        s_core_tx_valid;
  logic        s_core_rx_valid;
  logic [31:0] s_core_rx_data;
  logic        s_tx_underrun_aud;
  logic        s_rx_overrun_aud;
  logic s_tx_underrun_tgl_d, s_tx_underrun_tgl_q;
  logic s_rx_overrun_tgl_d, s_rx_overrun_tgl_q;
  logic s_tx_underrun_re;
  logic s_tx_underrun_fe;
  logic s_rx_overrun_re;
  logic s_rx_overrun_fe;
  logic s_tx_underrun_sys;
  logic s_rx_overrun_sys;
  logic s_tx_flush_sent_q;

  assign s_cmd_sys = {s_cmd_rx_flush, s_cmd_tx_flush};
  assign s_tx_src_clear = s_cmd_tx_flush && !s_tx_flush_sent_q && !s_tx_src_clear_busy;
  assign s_rx_src_clear    = s_cmd_v_aud && s_cmd_aud[`APB4_I2S__COMMAND_RX_FLUSH] &&
                             !s_rx_src_clear_busy;
  assign s_tx_flush_busy = s_cmd_tx_flush || s_tx_src_clear_busy || s_tx_dst_busy_sys;
  assign s_rx_flush_busy = s_cmd_rx_flush || s_rx_dst_clear_busy || s_rx_src_busy_sys;
  assign s_tx_underrun_sys = s_tx_underrun_re || s_tx_underrun_fe;
  assign s_rx_overrun_sys = s_rx_overrun_re || s_rx_overrun_fe;
  assign s_tx_push = s_tx_src_valid && s_tx_src_ready;
  assign s_rx_pop = s_rx_dst_valid && s_rx_dst_ready;
  assign s_tx_level = s_tx_flush_busy ? 8'd0 : (s_tx_push_cnt_q - s_tx_pop_cnt_sys_q);
  assign s_rx_level = s_rx_flush_busy ? 8'd0 : (s_rx_push_cnt_sys_q - s_rx_pop_cnt_q);
  assign s_tx_src_data = s_stream_tx_en ? tx_axis.tdata : s_tx_pio_data;
  assign s_tx_src_valid = !s_tx_flush_busy && (s_stream_tx_en ? tx_axis.tvalid : s_tx_pio_push);
  assign tx_axis.tready = s_stream_tx_en && s_tx_src_ready && !s_tx_flush_busy;
  assign s_tx_dst_ready = s_core_tx_valid;
  assign s_rx_src_valid = s_core_rx_valid;
  assign s_rx_src_data = s_core_rx_data;
  assign s_rx_dst_ready = !s_rx_flush_busy && (s_stream_rx_en ? rx_axis.tready : s_rx_pio_pop);
  assign s_rx_pop_data = s_rx_dst_data;
  assign rx_axis.tdata = s_rx_dst_data;
  assign rx_axis.tkeep = '1;
  assign rx_axis.tstrb = '1;
  assign rx_axis.tlast = 1'b0;
  assign rx_axis.tid = '0;
  assign rx_axis.tdest = '0;
  assign rx_axis.tuser = '0;
  assign rx_axis.tvalid = s_stream_rx_en && s_rx_dst_valid && !s_rx_flush_busy;

  i2s_reg u_i2s_reg (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .apb4              (apb4),
      .tx_full_i         (!s_tx_src_ready),
      .tx_empty_i        (s_tx_level == 8'd0),
      .tx_level_i        (s_tx_level),
      .rx_full_i         (s_rx_src_busy_sys),
      .rx_empty_i        (!s_rx_dst_valid),
      .rx_level_i        (s_rx_level),
      .tx_flush_busy_i   (s_tx_flush_busy),
      .rx_flush_busy_i   (s_rx_flush_busy),
      .tx_underrun_i     (s_tx_underrun_sys),
      .rx_overrun_i      (s_rx_overrun_sys),
      .tx_push_valid_o   (s_tx_pio_push),
      .tx_push_data_o    (s_tx_pio_data),
      .rx_pop_valid_o    (s_rx_pio_pop),
      .rx_pop_data_i     (s_rx_pop_data),
      .cfg_o             (s_cfg_sys),
      .cmd_tx_flush_o    (s_cmd_tx_flush),
      .cmd_rx_flush_o    (s_cmd_rx_flush),
      .cmd_valid_o       (s_cmd_v_sys),
      .cmd_ready_i       (s_cmd_rdy_sys),
      .stream_tx_enable_o(s_stream_tx_en),
      .stream_rx_enable_o(s_stream_rx_en),
      .dma_tx_stall_o    (dma_tx_stall_o),
      .dma_rx_stall_o    (dma_rx_stall_o),
      .irq_o             (s_irq)
  );

  /* verilator lint_off PINCONNECTEMPTY */
  cdc_2phase #(
      .DATA_WIDTH(32)
  ) u_i2s_cfg_cdc (
      .src_clk_i  (clk_i),
      .src_rst_n_i(rst_n_i),
      .src_data_i (s_cfg_sys),
      .src_valid_i(1'b1),
      .src_ready_o(),
      .dst_clk_i  (clk_aud_i),
      .dst_rst_n_i(rst_aud_n_i),
      .dst_data_o (s_cfg_aud),
      .dst_valid_o(s_cfg_aud_v),
      .dst_ready_i(1'b1)
  );
  always_ff @(posedge clk_aud_i or negedge rst_aud_n_i) begin
    if (!rst_aud_n_i) s_cfg_aud_q <= '0;
    else if (s_cfg_aud_v) s_cfg_aud_q <= s_cfg_aud;
  end

  cdc_2phase #(
      .DATA_WIDTH(2)
  ) u_i2s_cmd_cdc (
      .src_clk_i  (clk_i),
      .src_rst_n_i(rst_n_i),
      .src_data_i (s_cmd_sys),
      .src_valid_i(s_cmd_v_sys),
      .src_ready_o(s_cmd_rdy_sys),
      .dst_clk_i  (clk_aud_i),
      .dst_rst_n_i(rst_aud_n_i),
      .dst_data_o (s_cmd_aud),
      .dst_valid_o(s_cmd_v_aud),
      .dst_ready_i(!s_rx_src_clear_busy)
  );

  /* verilator lint_on PINCONNECTEMPTY */

  cdc_fifo_warm_flush #(
      .DATA_WIDTH  (32),
      .BUFFER_DEPTH(128)
  ) u_tx_cdc_fifo (
      .src_clk_i       (clk_i),
      .src_rst_n_i     (rst_n_i),
      .src_clear_i     (s_tx_src_clear),
      .src_clear_busy_o(s_tx_src_clear_busy),
      .src_data_i      (s_tx_src_data),
      .src_valid_i     (s_tx_src_valid),
      .src_ready_o     (s_tx_src_ready),
      .dst_clk_i       (clk_aud_i),
      .dst_rst_n_i     (rst_aud_n_i),
      .dst_clear_busy_o(s_tx_dst_clear_busy),
      .dst_data_o      (s_tx_dst_data),
      .dst_valid_o     (s_tx_dst_valid),
      .dst_ready_i     (s_tx_dst_ready)
  );

  cdc_fifo_warm_flush #(
      .DATA_WIDTH  (32),
      .BUFFER_DEPTH(128)
  ) u_rx_cdc_fifo (
      .src_clk_i       (clk_aud_i),
      .src_rst_n_i     (rst_aud_n_i),
      .src_clear_i     (s_rx_src_clear),
      .src_clear_busy_o(s_rx_src_clear_busy),
      .src_data_i      (s_rx_src_data),
      .src_valid_i     (s_rx_src_valid),
      .src_ready_o     (s_rx_src_ready),
      .dst_clk_i       (clk_i),
      .dst_rst_n_i     (rst_n_i),
      .dst_clear_busy_o(s_rx_dst_clear_busy),
      .dst_data_o      (s_rx_dst_data),
      .dst_valid_o     (s_rx_dst_valid),
      .dst_ready_i     (s_rx_dst_ready)
  );

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_tx_dst_busy_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_dst_clear_busy),
      .dat_o  (s_tx_dst_busy_sys)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_rx_src_busy_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (!s_rx_src_ready || s_rx_src_clear_busy),
      .dat_o  (s_rx_src_busy_sys)
  );

  always_comb begin
    s_tx_push_cnt_d = s_tx_push_cnt_q;
    if (s_tx_flush_busy) s_tx_push_cnt_d = '0;
    else if (s_tx_push) s_tx_push_cnt_d = s_tx_push_cnt_q + 8'd1;
  end
  always_comb begin
    s_rx_pop_cnt_d = s_rx_pop_cnt_q;
    if (s_rx_flush_busy) s_rx_pop_cnt_d = '0;
    else if (s_rx_pop) s_rx_pop_cnt_d = s_rx_pop_cnt_q + 8'd1;
  end
  dffr #(
      .DATA_WIDTH(8)
  ) u_tx_push_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_push_cnt_d),
      .dat_o  (s_tx_push_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_rx_pop_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_pop_cnt_d),
      .dat_o  (s_rx_pop_cnt_q)
  );

  always_comb begin
    s_tx_pop_cnt_aud_d = s_tx_pop_cnt_aud_q;
    if (s_cmd_v_aud && s_cmd_aud[`APB4_I2S__COMMAND_TX_FLUSH]) s_tx_pop_cnt_aud_d = '0;
    else if (s_tx_dst_valid && s_tx_dst_ready) s_tx_pop_cnt_aud_d = s_tx_pop_cnt_aud_q + 8'd1;
  end
  always_comb begin
    s_rx_push_cnt_aud_d = s_rx_push_cnt_aud_q;
    if (s_cmd_v_aud && s_cmd_aud[`APB4_I2S__COMMAND_RX_FLUSH]) s_rx_push_cnt_aud_d = '0;
    else if (s_rx_src_valid && s_rx_src_ready) s_rx_push_cnt_aud_d = s_rx_push_cnt_aud_q + 8'd1;
  end
  dffr #(
      .DATA_WIDTH(8)
  ) u_tx_pop_cnt_aud_dffr (
      .clk_i  (clk_aud_i),
      .rst_n_i(rst_aud_n_i),
      .dat_i  (s_tx_pop_cnt_aud_d),
      .dat_o  (s_tx_pop_cnt_aud_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_rx_push_cnt_aud_dffr (
      .clk_i  (clk_aud_i),
      .rst_n_i(rst_aud_n_i),
      .dat_i  (s_rx_push_cnt_aud_d),
      .dat_o  (s_rx_push_cnt_aud_q)
  );

  /* verilator lint_off PINCONNECTEMPTY */
  cdc_2phase #(
      .DATA_WIDTH(8)
  ) u_tx_pop_cnt_cdc (
      .src_clk_i  (clk_aud_i),
      .src_rst_n_i(rst_aud_n_i),
      .src_data_i (s_tx_pop_cnt_aud_q),
      .src_valid_i(1'b1),
      .src_ready_o(),
      .dst_clk_i  (clk_i),
      .dst_rst_n_i(rst_n_i),
      .dst_data_o (s_tx_pop_cnt_sys),
      .dst_valid_o(s_tx_pop_cnt_sys_v),
      .dst_ready_i(1'b1)
  );
  cdc_2phase #(
      .DATA_WIDTH(8)
  ) u_rx_push_cnt_cdc (
      .src_clk_i  (clk_aud_i),
      .src_rst_n_i(rst_aud_n_i),
      .src_data_i (s_rx_push_cnt_aud_q),
      .src_valid_i(1'b1),
      .src_ready_o(),
      .dst_clk_i  (clk_i),
      .dst_rst_n_i(rst_n_i),
      .dst_data_o (s_rx_push_cnt_sys),
      .dst_valid_o(s_rx_push_cnt_sys_v),
      .dst_ready_i(1'b1)
  );
  /* verilator lint_on PINCONNECTEMPTY */

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) s_tx_flush_sent_q <= 1'b0;
    else if (!s_cmd_tx_flush) s_tx_flush_sent_q <= 1'b0;
    else if (s_tx_src_clear) s_tx_flush_sent_q <= 1'b1;
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_tx_pop_cnt_sys_q  <= '0;
      s_rx_push_cnt_sys_q <= '0;
    end else begin
      if (s_tx_flush_busy) s_tx_pop_cnt_sys_q <= '0;
      else if (s_tx_pop_cnt_sys_v) s_tx_pop_cnt_sys_q <= s_tx_pop_cnt_sys;
      if (s_rx_flush_busy) s_rx_push_cnt_sys_q <= '0;
      else if (s_rx_push_cnt_sys_v) s_rx_push_cnt_sys_q <= s_rx_push_cnt_sys;
    end
  end

  assign s_tx_underrun_tgl_d = s_tx_underrun_aud ? ~s_tx_underrun_tgl_q : s_tx_underrun_tgl_q;
  assign s_rx_overrun_tgl_d  = s_rx_overrun_aud ? ~s_rx_overrun_tgl_q : s_rx_overrun_tgl_q;
  dffr #(
      .DATA_WIDTH(1)
  ) u_tx_underrun_tgl_dffr (
      .clk_i  (clk_aud_i),
      .rst_n_i(rst_aud_n_i),
      .dat_i  (s_tx_underrun_tgl_d),
      .dat_o  (s_tx_underrun_tgl_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rx_overrun_tgl_dffr (
      .clk_i  (clk_aud_i),
      .rst_n_i(rst_aud_n_i),
      .dat_i  (s_rx_overrun_tgl_d),
      .dat_o  (s_rx_overrun_tgl_q)
  );

  /* verilator lint_off PINCONNECTEMPTY */
  edge_det #(
      .STAGE(2)
  ) u_tx_underrun_event (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_underrun_tgl_q),
      .dat_o  (),
      .re_o   (s_tx_underrun_re),
      .fe_o   (s_tx_underrun_fe)
  );
  edge_det #(
      .STAGE(2)
  ) u_rx_overrun_event (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_overrun_tgl_q),
      .dat_o  (),
      .re_o   (s_rx_overrun_re),
      .fe_o   (s_rx_overrun_fe)
  );
  /* verilator lint_on PINCONNECTEMPTY */

  i2s_core u_i2s_core (
      .clk_i        (clk_aud_i),
      .rst_n_i      (rst_aud_n_i),
      .enable_i     (s_cfg_aud_q[`APB4_I2S__CFG_ENABLE]),
      .tx_enable_i  (s_cfg_aud_q[`APB4_I2S__CFG_TX_ENABLE]),
      .rx_enable_i  (s_cfg_aud_q[`APB4_I2S__CFG_RX_ENABLE]),
      .loopback_i   (s_cfg_aud_q[`APB4_I2S__CFG_LOOPBACK]),
      .clk_prog_i   (s_cfg_aud_q[`APB4_I2S__CFG_CLK_PROG]),
      .format_i     (s_cfg_aud_q[`APB4_I2S__CFG_FORMAT]),
      .bitmode_i    (s_cfg_aud_q[`APB4_I2S__CFG_BITMODE]),
      .sclk_div_i   (s_cfg_aud_q[`APB4_I2S__CFG_SCLK_LSB+:8]),
      .lrck_div_i   (s_cfg_aud_q[`APB4_I2S__CFG_LRCK_LSB+:8]),
      .mclk_div_i   (s_cfg_aud_q[`APB4_I2S__CFG_MCLK_LSB+:8]),
      .irq_i        (s_irq),
      .tx_valid_o   (s_core_tx_valid),
      .tx_data_i    (s_tx_dst_data),
      .tx_empty_i   (!s_tx_dst_valid),
      .rx_valid_o   (s_core_rx_valid),
      .rx_data_o    (s_core_rx_data),
      .rx_full_i    (!s_rx_src_ready),
      .tx_underrun_o(s_tx_underrun_aud),
      .rx_overrun_o (s_rx_overrun_aud),
      .i2s          (i2s)
  );
endmodule
