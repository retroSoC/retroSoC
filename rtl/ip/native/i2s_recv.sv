// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module i2s_recv (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        sclk_pos_i,
    input  logic        lrck_i,
    input  logic        bitmode_i,
    input  logic        adcdat_i,
    output logic [23:0] data_o,
    output logic        done_o

);

  logic s_lrck_dely_d, s_lrck_dely_q;
  logic s_lrck_trg;
  logic [4:0] s_bit_cnt_d, s_bit_cnt_q;
  logic [4:0] s_bit_num;
  logic [23:0] s_recv_data_d, s_recv_data_q;
  logic [23:0] s_data_d, s_data_q;


  assign s_bit_num     = bitmode_i ? 5'd23 : 5'd15;
  assign data_o        = s_data_q;
  assign done_o        = s_bit_cnt_q == s_bit_num;
  assign s_lrck_trg    = lrck_i ^ s_lrck_dely_q;


  assign s_lrck_dely_d = lrck_i;
  dffer #(1) u_lrck_dely_dffer (
      clk_i,
      rst_n_i,
      sclk_pos_i,
      s_lrck_dely_d,
      s_lrck_dely_q
  );


  always_comb begin
    s_bit_cnt_d = s_bit_cnt_q;
    if (s_lrck_trg) s_bit_cnt_d = '0;
    else if (s_bit_cnt_q < s_bit_num) begin
      s_bit_cnt_d = s_bit_cnt_q + 1'b1;
    end
  end
  dffer #(5) u_bit_cnt_dffer (
      clk_i,
      rst_n_i,
      sclk_pos_i,
      s_bit_cnt_d,
      s_bit_cnt_q
  );


  always_comb begin
    s_recv_data_d = s_recv_data_q;
    if (s_bit_cnt_q <= s_bit_num) begin
      if (bitmode_i) s_recv_data_d[5'd23-s_bit_cnt_q] = adcdat_i;
      else s_recv_data_d[5'd15-s_bit_cnt_q] = adcdat_i;
    end
  end
  dffer #(24) u_recv_data_dffer (
      clk_i,
      rst_n_i,
      sclk_pos_i,
      s_recv_data_d,
      s_recv_data_q
  );


  assign s_data_d = s_bit_cnt_q == s_bit_num ? s_recv_data_d : s_data_q;
  dffer #(24) u_data_dffer (
      clk_i,
      rst_n_i,
      sclk_pos_i,
      s_data_d,
      s_data_q
  );

endmodule
