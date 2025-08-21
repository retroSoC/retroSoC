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
// memory-map rd/wr for first 512MB range of TF card
module spisd (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        mem_valid_i,
    output logic        mem_ready_o,
    input  logic [23:0] mem_addr_i,
    input  logic [31:0] mem_wdata_i,
    input  logic [ 3:0] mem_wstrb_i,
    output logic [31:0] mem_rdata_o,
    output logic        spisd_sclk_o,
    output logic        spisd_cs_o,
    output logic        spisd_mosi_o,
    input  logic        spisd_miso_i
);

  assign mem_ready_o = '0;
  assign mem_rdata_o = '0;

  spisd_core u_spisd_core (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .rd_st_i     ('0),
      .rd_vld_o    (),
      .rd_data_o   (),
      .wr_st_i     ('0),
      .wr_data_i   ('0),
      .addr_i      ('0),
      .idle_o      (),
      .spisd_sclk_o(spisd_sclk_o),
      .spisd_cs_o  (spisd_cs_o),
      .spisd_mosi_o(spisd_mosi_o),
      .spisd_miso_i(spisd_miso_i)
  );

endmodule
