// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module i2s_core (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        mode_i,
    input  logic [1:0]  format_i,
    output logic        tx_valid_o,
    input  logic [31:0] tx_data_i,
    input  logic        tx_empty_i,
    output logic        rx_valid_o,
    output logic [31:0] rx_data_o,
    input  logic        rx_full_i,
    nv_i2s_if.dut       i2s
    // verilog_format: on
);

  // i2s clk
  logic s_sclk_pos, s_sclk_fall;
  logic s_sclk, s_lrck;
  // common
  logic [23:0] s_loopback_data;
  logic [23:0] s_recv_data, s_send_data;
  logic [23:0] s_recv_data_d, s_recv_data_q;
  logic [31:0] s_send_data_d, s_send_data_q;
  logic s_recv_done, s_send_done;
  logic s_recv_done_re, s_send_done_re;
  logic s_recv_cnt_d, s_recv_cnt_q;
  logic s_send_cnt_d, s_send_cnt_q;

  // i2s
  assign i2s.mclk_o = clk_i;
  assign i2s.sclk_o = s_sclk;
  assign i2s.lrck_o = s_lrck;
  assign i2s.irq_o  = '0;


  edge_det_sync_re u_recv_done_edge_det_sync_re (
      clk_i,
      rst_n_i,
      s_recv_done,
      s_recv_done_re
  );

  edge_det_sync_re u_send_done_edge_det_sync_re (
      clk_i,
      rst_n_i,
      s_send_done,
      s_send_done_re
  );

  always_comb begin
    rx_valid_o      = '0;
    rx_data_o       = '0;
    s_loopback_data = '0;
    s_recv_cnt_d    = s_recv_cnt_q;
    s_recv_data_d   = s_recv_data_q;
    if (!mode_i) s_loopback_data = s_recv_data;
    else begin
      if (s_recv_done_re) begin
        if (format_i[1]) begin
          s_recv_cnt_d = '0;
          if (~rx_full_i) begin
            rx_valid_o = 1'b1;
            rx_data_o  = {8'd0, s_recv_data};
          end
        end else begin
          if (~rx_full_i && s_recv_cnt_q == 1'b1) begin
            s_recv_cnt_d = '0;
            rx_valid_o   = 1'b1;
            rx_data_o    = {s_recv_data[15:0], s_recv_data_q[15:0]};
          end else begin
            s_recv_cnt_d        = s_recv_cnt_q + 1'b1;
            s_recv_data_d[15:0] = s_recv_data[15:0];
          end
        end
      end
    end
  end
  dffr #(1) u_recv_cnt_dffr (
      clk_i,
      rst_n_i,
      s_recv_cnt_d,
      s_recv_cnt_q
  );
  dffr #(24) u_recv_data_dffr (
      clk_i,
      rst_n_i,
      s_recv_data_d,
      s_recv_data_q
  );


  always_comb begin
    tx_valid_o    = '0;
    s_send_cnt_d  = s_send_cnt_q;
    s_send_data_d = s_send_data_q;
    if (!mode_i) s_send_data = s_loopback_data;
    else begin
      if (format_i[1]) begin
        s_send_data  = s_send_data_q[23:0];
        s_send_cnt_d = '0;
        if (s_send_done_re && (~tx_empty_i)) begin  // NOTE:
          tx_valid_o    = 1'b1;
          s_send_cnt_d  = s_send_cnt_q + 1'b1;
          s_send_data_d = tx_data_i;
        end
      end else begin
        s_send_data[15:0] = s_send_data_q[15:0];
        if (s_send_done_re) begin
          if (s_send_cnt_q == 1'b1) begin
            s_send_cnt_d  = '0;
            s_send_data_d = {16'd0, s_send_data_q[31:16]};
          end else if (~tx_empty_i) begin  // NOTE:
            tx_valid_o    = 1'b1;
            s_send_cnt_d  = s_send_cnt_q + 1'b1;
            s_send_data_d = tx_data_i;
          end
        end
      end
    end
  end
  dffr #(1) u_send_cnt_dffr (
      clk_i,
      rst_n_i,
      s_send_cnt_d,
      s_send_cnt_q
  );
  dffr #(32) u_send_data_dffr (
      clk_i,
      rst_n_i,
      s_send_data_d,
      s_send_data_q
  );


  i2s_clkgen u_i2s_clkgen (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .format_i   (format_i),
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
      .bitmode_i (format_i[1]),
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
      .bitmode_i  (format_i[1]),
      .data_i     (s_send_data),
      .dacdat_o   (i2s.dacdat_o),
      .done_o     (s_send_done)
  );

endmodule
