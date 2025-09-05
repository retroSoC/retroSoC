// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// spisd is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
//

module spisd_core (
    input  logic        clk_i,
    input  logic        rst_n_i,
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
  logic [1:0] s_nor_clk_div_d, s_nor_clk_div_q;
  logic s_nor_clk_d, s_nor_clk_q;
  logic s_fir_clk_edge;
  logic s_sec_clk_edge;

  assign s_fir_clk_edge = s_nor_clk_q && (s_nor_clk_div_q == '0);
  assign s_sec_clk_edge = (s_nor_clk_q == '0) && (s_nor_clk_div_q == '0);
  assign fir_clk_edge_o = s_fir_clk_edge;
  // 72 / 6 = 12M
  always_comb begin
    s_nor_clk_d     = s_nor_clk_q;
    s_nor_clk_div_d = s_nor_clk_q;
    if (s_nor_clk_div_q == '0) begin
      s_nor_clk_div_d = '1;
      s_nor_clk_d     = ~s_nor_clk_q;
    end else begin
      s_nor_clk_div_d = s_nor_clk_div_q - 1'b1;
    end
  end


  dffrh #(2) u_nor_clk_div_dffrh (
      clk_i,
      rst_n_i,
      s_nor_clk_div_d,
      s_nor_clk_div_q
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
      if (wr_busy_o) begin
        spisd_cs_o   = s_wr_sd_cs;
        spisd_mosi_o = s_wr_sd_mosi;
      end else if (rd_busy_o) begin
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
      .wr_req_i      (wr_req_i & init_done_o),
      .wr_sec_addr_i (sec_addr_i),
      .wr_data_req_o (wr_data_req_o),
      .wr_data_i     (wr_data_i),
      .wr_busy_o     (wr_busy_o),
      .spisd_cs_o    (s_wr_sd_cs),
      .spisd_mosi_o  (s_wr_sd_mosi),
      .spisd_miso_i  (spisd_miso_i)
  );

  spisd_read u_spisd_read (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .fir_clk_edge_i(s_fir_clk_edge),
      .sec_clk_edge_i(s_sec_clk_edge),
      .rd_req_i      (rd_req_i & init_done_o),
      .rd_sec_addr_i (sec_addr_i),
      .rd_data_vld_o (rd_data_vld_o),
      .rd_data_o     (rd_data_o),
      .rd_busy_o     (rd_busy_o),
      .spisd_cs_o    (s_rd_sd_cs),
      .spisd_mosi_o  (s_rd_sd_mosi),
      .spisd_miso_i  (spisd_miso_i)
  );

endmodule
