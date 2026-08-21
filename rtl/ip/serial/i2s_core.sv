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

module i2s_core (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        enable_i,
    input  logic        tx_enable_i,
    input  logic        rx_enable_i,
    input  logic        loopback_i,
    input  logic        clk_prog_i,
    input  logic [ 1:0] format_i,
    input  logic        bitmode_i,
    input  logic [ 7:0] sclk_div_i,
    input  logic [ 7:0] lrck_div_i,
    input  logic [ 7:0] mclk_div_i,
    input  logic        irq_i,
    output logic        tx_valid_o,
    input  logic [31:0] tx_data_i,
    input  logic        tx_empty_i,
    output logic        rx_valid_o,
    output logic [31:0] rx_data_o,
    input  logic        rx_full_i,
    output logic        tx_underrun_o,
    output logic        rx_overrun_o,
    i2s_if.dut          i2s
    // verilog_format: on
);
  import i2s_pkg::i2s_preset_bitmode;

  logic s_sclk_pos, s_sclk_fall;
  logic s_sclk, s_lrck;
  logic        s_bitmode;
  logic [23:0] s_loopback_data;
  logic [23:0] s_recv_data, s_send_data;
  logic [23:0] s_recv_data_d, s_recv_data_q;
  logic [31:0] s_send_data_d, s_send_data_q;
  logic s_recv_done, s_send_done;
  logic s_recv_done_re, s_send_done_re;
  logic s_recv_cnt_d, s_recv_cnt_q;
  logic s_send_cnt_d, s_send_cnt_q;
  logic [7:0] s_mclk_cnt_d, s_mclk_cnt_q;
  logic s_mclk_d, s_mclk_q;
  logic s_mclk_sel;
  logic s_fifo_mode;

  assign s_bitmode   = clk_prog_i ? bitmode_i : i2s_preset_bitmode(format_i);
  assign s_fifo_mode = enable_i && !loopback_i;
  assign i2s.sclk_o  = s_sclk;
  assign i2s.lrck_o  = s_lrck;
  assign i2s.irq_o   = irq_i;

  // NOTE: for jitter control
  tc_clk_mux2 u_mclk_clk_mux (
      .clk0_i   (clk_i),
      .clk1_i   (s_mclk_q),
      .clk_sel_i(|mclk_div_i),
      .clk_o    (s_mclk_sel)
  );
  tc_clk_buf u_mclk_clk_buf (
      .clk_i(s_mclk_sel),
      .clk_o(i2s.mclk_o)
  );

  always_comb begin
    s_mclk_d     = s_mclk_q;
    s_mclk_cnt_d = s_mclk_cnt_q;
    if (mclk_div_i == 8'd0) begin
      s_mclk_d     = 1'b0;
      s_mclk_cnt_d = '0;
    end else if (s_mclk_cnt_q == mclk_div_i) begin
      s_mclk_cnt_d = '0;
      s_mclk_d     = ~s_mclk_q;
    end else begin
      s_mclk_cnt_d = s_mclk_cnt_q + 8'd1;
    end
  end
  dffr #(
      .DATA_WIDTH(8)
  ) u_mclk_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mclk_cnt_d),
      .dat_o  (s_mclk_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_mclk_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_mclk_d),
      .dat_o  (s_mclk_q)
  );

  edge_det_sync_re u_recv_done_edge_det_sync_re (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_recv_done),
      .re_o   (s_recv_done_re)
  );
  edge_det_sync_re u_send_done_edge_det_sync_re (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_send_done),
      .re_o   (s_send_done_re)
  );

  always_comb begin
    rx_valid_o      = 1'b0;
    rx_data_o       = '0;
    rx_overrun_o    = 1'b0;
    s_loopback_data = '0;
    s_recv_cnt_d    = s_recv_cnt_q;
    s_recv_data_d   = s_recv_data_q;
    if (loopback_i) begin
      s_loopback_data = s_recv_data;
    end else if (s_fifo_mode && rx_enable_i && s_recv_done_re) begin
      if (s_bitmode) begin
        s_recv_cnt_d = 1'b0;
        if (~rx_full_i) begin
          rx_valid_o = 1'b1;
          rx_data_o  = {8'd0, s_recv_data};
        end else begin
          rx_overrun_o = 1'b1;
        end
      end else if (~rx_full_i && (s_recv_cnt_q == 1'b1)) begin
        s_recv_cnt_d = 1'b0;
        rx_valid_o   = 1'b1;
        rx_data_o    = {s_recv_data[15:0], s_recv_data_q[15:0]};
      end else if (s_recv_cnt_q == 1'b1) begin
        s_recv_cnt_d = 1'b0;
        rx_overrun_o = 1'b1;
      end else begin
        s_recv_cnt_d        = s_recv_cnt_q + 1'b1;
        s_recv_data_d[15:0] = s_recv_data[15:0];
      end
    end
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_recv_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_recv_cnt_d),
      .dat_o  (s_recv_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(24)
  ) u_recv_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_recv_data_d),
      .dat_o  (s_recv_data_q)
  );

  always_comb begin
    tx_valid_o    = 1'b0;
    tx_underrun_o = 1'b0;
    s_send_data   = '0;
    s_send_cnt_d  = s_send_cnt_q;
    s_send_data_d = s_send_data_q;
    if (loopback_i) begin
      s_send_data = s_loopback_data;
    end else if (s_fifo_mode && tx_enable_i) begin
      if (s_bitmode) begin
        s_send_data  = s_send_data_q[23:0];
        s_send_cnt_d = 1'b0;
        if (s_send_done_re) begin
          if (~tx_empty_i) begin
            tx_valid_o    = 1'b1;
            s_send_data_d = tx_data_i;
          end else begin
            tx_underrun_o = 1'b1;
            s_send_data_d = '0;
          end
        end
      end else begin
        s_send_data[15:0] = s_send_data_q[15:0];
        if (s_send_done_re) begin
          if (s_send_cnt_q == 1'b1) begin
            s_send_cnt_d  = 1'b0;
            s_send_data_d = {16'd0, s_send_data_q[31:16]};
          end else if (~tx_empty_i) begin
            tx_valid_o    = 1'b1;
            s_send_cnt_d  = s_send_cnt_q + 1'b1;
            s_send_data_d = tx_data_i;
          end else begin
            tx_underrun_o = 1'b1;
            s_send_cnt_d  = 1'b0;
            s_send_data_d = '0;
          end
        end
      end
    end
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_send_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_send_cnt_d),
      .dat_o  (s_send_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_send_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_send_data_d),
      .dat_o  (s_send_data_q)
  );

  i2s_clkgen u_i2s_clkgen (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .enable_i   (enable_i),
      .clk_prog_i (clk_prog_i),
      .format_i   (format_i),
      .sclk_div_i (sclk_div_i),
      .lrck_div_i (lrck_div_i),
      .sclk_pos_o (s_sclk_pos),
      .sclk_fall_o(s_sclk_fall),
      .sclk_o     (s_sclk),
      .lrck_o     (s_lrck)
  );

  i2s_recv u_i2s_recv (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .sclk_pos_i(s_sclk_pos),
      .lrck_i    (s_lrck),
      .bitmode_i (s_bitmode),
      .adcdat_i  (i2s.adcdat_i),
      .data_o    (s_recv_data),
      .done_o    (s_recv_done)
  );

  i2s_send u_i2s_send (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .sclk_pos_i (s_sclk_pos),
      .sclk_fall_i(s_sclk_fall),
      .lrck_i     (s_lrck),
      .bitmode_i  (s_bitmode),
      .data_i     (s_send_data),
      .dacdat_o   (i2s.dacdat_o),
      .done_o     (s_send_done)
  );
endmodule
