// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "i2s_define.svh"

module i2s_clkgen (
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic [1:0] format_i,
    output logic       sclk_pos_o,
    output logic       sclk_fall_o,
    output logic       sclk_o,
    output logic       lrck_o
);

  logic [2:0] s_sclk_div_num;
  logic [2:0] s_sclk_div_cnt_d, s_sclk_div_cnt_q;
  logic s_sclk_d, s_sclk_q;
  logic [4:0] s_lrck_div_num;
  logic [4:0] s_lrck_div_cnt_d, s_lrck_div_cnt_q;
  logic s_lrck_d, s_lrck_q;


  assign sclk_pos_o  = (~s_sclk_q) && (s_sclk_div_cnt_q == s_sclk_div_num);
  assign sclk_fall_o = s_sclk_q && (s_sclk_div_cnt_q == s_sclk_div_num);
  assign sclk_o      = s_sclk_q;
  assign lrck_o      = s_lrck_q;


  always_comb begin
    s_sclk_div_num = 3'd5;
    unique case (format_i)
      `I2S_16b_48K: s_sclk_div_num = 3'd5;
      `I2S_16b_96K: s_sclk_div_num = 3'd2;
      `I2S_24b_48K: s_sclk_div_num = 3'd3;
      `I2S_24b_96K: s_sclk_div_num = 3'd1;
    endcase
  end


  always_comb begin
    s_sclk_d = s_sclk_q;
    if (s_sclk_div_cnt_q == s_sclk_div_num) begin
      s_sclk_div_cnt_d = '0;
      s_sclk_d         = ~s_sclk_q;
    end else begin
      s_sclk_div_cnt_d = s_sclk_div_cnt_q + 3'd1;
    end
  end
  dffr #(3) u_sclk_div_cnt_dffr (
      clk_i,
      rst_n_i,
      s_sclk_div_cnt_d,
      s_sclk_div_cnt_q
  );
  dffr #(1) u_sclk_dffr (
      clk_i,
      rst_n_i,
      s_sclk_d,
      s_sclk_q
  );


  always_comb begin
    s_lrck_div_num = 5'd15;
    unique case (format_i)
      `I2S_16b_48K: s_lrck_div_num = 5'd15;
      `I2S_16b_96K: s_lrck_div_num = 5'd15;
      `I2S_24b_48K: s_lrck_div_num = 5'd23;
      `I2S_24b_96K: s_lrck_div_num = 5'd23;
    endcase
  end


  always_comb begin
    s_lrck_d = s_lrck_q;
    if (s_lrck_div_cnt_q == s_lrck_div_num) begin
      s_lrck_div_cnt_d = '0;
      s_lrck_d         = ~s_lrck_q;
    end else begin
      s_lrck_div_cnt_d = s_lrck_div_cnt_q + 5'd1;
    end
  end
  dffer #(5) u_lrck_div_cnt_dffer (
      clk_i,
      rst_n_i,
      sclk_fall_o,
      s_lrck_div_cnt_d,
      s_lrck_div_cnt_q
  );
  dffer #(1) u_lrck_dffer (
      clk_i,
      rst_n_i,
      sclk_fall_o,
      s_lrck_d,
      s_lrck_q
  );


endmodule


