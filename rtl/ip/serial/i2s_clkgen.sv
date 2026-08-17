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

module i2s_clkgen (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       enable_i,
    input  logic       clk_prog_i,
    input  logic [1:0] format_i,
    input  logic [7:0] sclk_div_i,
    input  logic [7:0] lrck_div_i,
    output logic       sclk_pos_o,
    output logic       sclk_fall_o,
    output logic       sclk_o,
    output logic       lrck_o
    // verilog_format: on
);
  import i2s_pkg::i2s_preset_sclk_div;
  import i2s_pkg::i2s_preset_lrck_div;

  logic [7:0] s_sclk_div_num;
  logic [7:0] s_sclk_div_cnt_d, s_sclk_div_cnt_q;
  logic s_sclk_tc;
  logic s_sclk_d, s_sclk_q;
  logic [7:0] s_lrck_div_num;
  logic [7:0] s_lrck_div_cnt_d, s_lrck_div_cnt_q;
  logic s_lrck_d, s_lrck_q;
  logic s_lrck_tc;
  logic s_sclk_pos, s_sclk_fall;

  assign s_sclk_div_num = clk_prog_i ? sclk_div_i : i2s_preset_sclk_div(format_i);
  assign s_lrck_div_num = clk_prog_i ? lrck_div_i : i2s_preset_lrck_div(format_i);
  assign s_sclk_tc      = enable_i && (s_sclk_div_cnt_q == s_sclk_div_num);
  assign s_sclk_pos     = enable_i && (~s_sclk_q) && s_sclk_tc;
  assign s_sclk_fall    = enable_i && s_sclk_q && s_sclk_tc;
  assign sclk_pos_o     = s_sclk_pos;
  assign sclk_fall_o    = s_sclk_fall;
  assign sclk_o         = s_sclk_q;
  assign lrck_o         = s_lrck_q;

  always_comb begin
    s_sclk_d         = s_sclk_q;
    s_sclk_div_cnt_d = s_sclk_div_cnt_q;
    if (!enable_i) begin
      s_sclk_d         = 1'b0;
      s_sclk_div_cnt_d = '0;
    end else if (s_sclk_tc) begin
      s_sclk_div_cnt_d = '0;
      s_sclk_d         = ~s_sclk_q;
    end else begin
      s_sclk_div_cnt_d = s_sclk_div_cnt_q + 8'd1;
    end
  end
  dffr #(
      .DATA_WIDTH(8)
  ) u_sclk_div_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sclk_div_cnt_d),
      .dat_o  (s_sclk_div_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_sclk_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sclk_d),
      .dat_o  (s_sclk_q)
  );

  always_comb begin
    s_lrck_d         = s_lrck_q;
    s_lrck_tc        = s_lrck_div_cnt_q == s_lrck_div_num;
    s_lrck_div_cnt_d = s_lrck_div_cnt_q;
    if (!enable_i) begin
      s_lrck_d         = 1'b0;
      s_lrck_div_cnt_d = '0;
    end else if (s_lrck_tc) begin
      s_lrck_div_cnt_d = '0;
      s_lrck_d         = ~s_lrck_q;
    end else begin
      s_lrck_div_cnt_d = s_lrck_div_cnt_q + 8'd1;
    end
  end
  dffer #(
      .DATA_WIDTH(8)
  ) u_lrck_div_cnt_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   ((!enable_i) || s_sclk_fall),
      .dat_i  (s_lrck_div_cnt_d),
      .dat_o  (s_lrck_div_cnt_q)
  );
  dffer #(
      .DATA_WIDTH(1)
  ) u_lrck_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   ((!enable_i) || s_sclk_fall),
      .dat_i  (s_lrck_d),
      .dat_o  (s_lrck_q)
  );
endmodule
