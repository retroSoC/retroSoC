// Copyright 2019 EmbedFire http://www.embedfire.com
// https://github.com/Embedfire-altera <embedfire@embedfire.com>
//
// The first version of this code was derived from EmbedFire sd_ctrl.v. The
// original code is open source on Gitee, but it doesn't specify an open-source
// license. I'm re-releasing it here under the most compatible license(PSL License).
// If anyone knows what the original license is, please contact <miaoyuchi@ict.ac.cn>.
//
// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2023-2025 Miao Yuchi <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module spisd_core (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [ 1:0] cfg_clkdiv_i,
    output logic        fir_clk_edge_o,
    output logic        init_done_o,
    input  logic [31:0] sec_addr_i,
    input  logic        rd_req_i,
    output logic        rd_data_vld_o,
    output logic [ 7:0] rd_data_o,
    output logic        rd_busy_o,
    input  logic        wr_req_i,
    output logic        wr_data_req_o,
    input  logic [ 7:0] wr_data_i,
    output logic        wr_busy_o,
    output logic        spisd_clk_o,
    output logic        spisd_cs_o,
    output logic        spisd_mosi_o,
    input  logic        spisd_miso_i
);

  logic s_init_sd_clk;
  logic s_init_sd_cs;
  logic s_init_sd_mosi;
  logic s_wr_sd_cs;
  logic s_wr_sd_mosi;
  logic s_rd_sd_cs;
  logic s_rd_sd_mosi;
  logic [1:0] s_nor_clkdiv_cnt_d, s_nor_clkdiv_cnt_q;
  logic s_nor_clk_d, s_nor_clk_q;
  logic s_fir_clk_edge;
  logic s_sec_clk_edge;
  logic s_wr_busy, s_rd_busy;

  assign rd_busy_o      = s_rd_busy;
  assign wr_busy_o      = s_wr_busy;
  assign s_fir_clk_edge = s_nor_clk_q && (s_nor_clkdiv_cnt_q == cfg_clkdiv_i);
  assign s_sec_clk_edge = (~s_nor_clk_q) && (s_nor_clkdiv_cnt_q == cfg_clkdiv_i);
  assign fir_clk_edge_o = s_fir_clk_edge;


  always_comb begin
    s_nor_clk_d        = s_nor_clk_q;
    s_nor_clkdiv_cnt_d = s_nor_clkdiv_cnt_q;
    if (s_nor_clkdiv_cnt_q == cfg_clkdiv_i) begin
      s_nor_clkdiv_cnt_d = '0;
      s_nor_clk_d        = ~s_nor_clk_q;
    end else begin
      s_nor_clkdiv_cnt_d = s_nor_clkdiv_cnt_q + 1'b1;
    end
  end
  dffr #(2) u_nor_clkdiv_dffr (
      clk_i,
      rst_n_i,
      s_nor_clkdiv_cnt_d,
      s_nor_clkdiv_cnt_q
  );

  dffrh #(1) u_nor_clk_dffrh (
      clk_i,
      rst_n_i,
      s_nor_clk_d,
      s_nor_clk_q
  );


  assign spisd_clk_o = (init_done_o == 1'b0) ? s_init_sd_clk : s_nor_clk_q;

  always_comb begin
    if (init_done_o == 1'b0) begin
      spisd_cs_o   = s_init_sd_cs;
      spisd_mosi_o = s_init_sd_mosi;
    end else begin
      if (s_wr_busy) begin
        spisd_cs_o   = s_wr_sd_cs;
        spisd_mosi_o = s_wr_sd_mosi;
      end else if (s_rd_busy) begin
        spisd_cs_o   = s_rd_sd_cs;
        spisd_mosi_o = s_rd_sd_mosi;
      end else begin
        spisd_cs_o   = 1'b1;
        spisd_mosi_o = 1'b1;
      end
    end
  end

  spisd_init u_spisd_init (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .init_done_o (init_done_o),
      .spisd_clk_o (s_init_sd_clk),
      .spisd_cs_o  (s_init_sd_cs),
      .spisd_mosi_o(s_init_sd_mosi),
      .spisd_miso_i(spisd_miso_i)
  );

  spisd_write u_spisd_write (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .fir_clk_edge_i(s_fir_clk_edge),
      .sec_clk_edge_i(s_sec_clk_edge),
      .wr_req_i      (wr_req_i & init_done_o & ~s_rd_busy),
      .wr_sec_addr_i (sec_addr_i),
      .wr_data_req_o (wr_data_req_o),
      .wr_data_i     (wr_data_i),
      .wr_busy_o     (s_wr_busy),
      .spisd_cs_o    (s_wr_sd_cs),
      .spisd_mosi_o  (s_wr_sd_mosi),
      .spisd_miso_i  (spisd_miso_i)
  );

  spisd_read u_spisd_read (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .fir_clk_edge_i(s_fir_clk_edge),
      .sec_clk_edge_i(s_sec_clk_edge),
      .rd_req_i      (rd_req_i & init_done_o & ~s_wr_busy),
      .rd_sec_addr_i (sec_addr_i),
      .rd_data_vld_o (rd_data_vld_o),
      .rd_data_o     (rd_data_o),
      .rd_busy_o     (s_rd_busy),
      .spisd_cs_o    (s_rd_sd_cs),
      .spisd_mosi_o  (s_rd_sd_mosi),
      .spisd_miso_i  (spisd_miso_i)
  );

endmodule
