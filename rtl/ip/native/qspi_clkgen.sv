// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module qspi_clkgen (
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic [7:0] div_i,
    input  logic       en_i,
    output logic       clk_o,
    output logic       fir_clk_edge_o,
    output logic       sec_clk_edge_o
);

  logic [7:0] s_clkdiv_cnt_d, s_clkdiv_cnt_q;
  logic s_sclk_d, s_sclk_q;

  // mode 0
  assign clk_o          = s_sclk_q;
  assign fir_clk_edge_o = (~s_sclk_q) && (s_clkdiv_cnt_q == div_i);
  assign sec_clk_edge_o = s_sclk_q && (s_clkdiv_cnt_q == div_i);

  always_comb begin
    s_clkdiv_cnt_d = s_clkdiv_cnt_q;
    s_sclk_d       = s_sclk_q;
    if (en_i) begin
      if (s_clkdiv_cnt_q == div_i) begin
        s_clkdiv_cnt_d = '0;
        s_sclk_d       = ~s_sclk_q;
      end else begin
        s_clkdiv_cnt_d = s_clkdiv_cnt_q + 1'b1;
      end
    end else begin
      s_clkdiv_cnt_d = '0;
      s_sclk_d       = '0;
    end
  end
  dffr #(8) u_clkdiv_cnt_dffr (
      clk_i,
      rst_n_i,
      s_clkdiv_cnt_d,
      s_clkdiv_cnt_q
  );

  dffr #(1) u_sclk_dffr (
      clk_i,
      rst_n_i,
      s_sclk_d,
      s_sclk_q
  );



endmodule
