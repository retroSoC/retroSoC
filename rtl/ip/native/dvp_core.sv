

// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module dvp_core (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        dvp_href_i,
    input  logic        dvp_vsync_i,
    input  logic [ 7:0] dvp_dat_i,
    output logic        wr_en_o,
    output logic [31:0] rgb_dat_o
);

  localparam FRAME_WAIT = 4'd12;


  logic s_dvp_vsync_re;
  logic s_frame_cnt_en;
  logic [3:0] s_frame_cnt_d, s_frame_cnt_q;
  logic s_frame_valid_en;
  logic s_frame_valid_d, s_frame_valid_q;
  logic [1:0] s_pix_cnt_d, s_pix_cnt_q;
  logic s_rgb_flag_d, s_rgb_flag_q;
  logic s_rgb_data_en;
  logic [31:0] s_rgb_data_d, s_rgb_data_q;


  assign wr_en_o   = s_frame_valid_q & s_rgb_flag_q;
  assign rgb_dat_o = s_rgb_data_q;


  edge_det_sync_re #(1) u_dvp_vsync_edge_det_sync_re (
      clk_i,
      rst_n_i,
      dvp_vsync_i,
      s_dvp_vsync_re
  );


  assign s_frame_cnt_en = (s_frame_cnt_q < FRAME_WAIT) && s_dvp_vsync_re;
  assign s_frame_cnt_d  = s_frame_cnt_q + 4'd1;
  dffer #(4) u_frame_cnt_dffer (
      clk_i,
      rst_n_i,
      s_frame_cnt_en,
      s_frame_cnt_d,
      s_frame_cnt_q
  );


  assign s_frame_valid_en = (s_frame_cnt_q == FRAME_WAIT) && s_dvp_vsync_re;
  assign s_frame_valid_d  = 1'b1;
  dffer #(1) u_frame_valid_dffer (
      clk_i,
      rst_n_i,
      s_frame_valid_en,
      s_frame_valid_d,
      s_frame_valid_q
  );


  assign s_pix_cnt_d = dvp_href_i ? s_pix_cnt_q + 2'd1 : '0;
  dffr #(2) u_pix_flag_dffr (
      clk_i,
      rst_n_i,
      s_pix_cnt_d,
      s_pix_cnt_q
  );


  assign s_rgb_flag_d = s_pix_cnt_q == 2'd3;
  dffr #(1) u_rgb_flag_dffr (
      clk_i,
      rst_n_i,
      s_rgb_flag_d,
      s_rgb_flag_q
  );


  assign s_rgb_data_en = dvp_href_i;
  always_comb begin
    s_rgb_data_d = s_rgb_data_q;
    if (s_pix_cnt_q == 2'd0) s_rgb_data_d[15:8] = dvp_dat_i;
    else if (s_pix_cnt_q == 2'd1) s_rgb_data_d[7:0] = dvp_dat_i;
    else if (s_pix_cnt_q == 2'd2) s_rgb_data_d[31:24] = dvp_dat_i;
    else if (s_pix_cnt_q == 2'd3) s_rgb_data_d[23:16] = dvp_dat_i;
  end
  dffer #(32) u_rgb_data_dffer (
      clk_i,
      rst_n_i,
      s_rgb_data_en,
      s_rgb_data_d,
      s_rgb_data_q
  );


endmodule

