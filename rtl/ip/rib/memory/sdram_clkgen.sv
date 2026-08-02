// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module sdram_clkgen (
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic [1:0] div_i,
    output logic       clk_o,
    output logic       fir_edge_o,
    output logic       sec_edge_o
);

  logic [1:0] s_div_cnt_d, s_div_cnt_q;
  logic s_div_clk_d, s_div_clk_q;


  assign clk_o       = s_div_clk_q;
  assign fir_edge_o  = (~s_div_clk_q) & (s_div_cnt_q == div_i);
  assign sec_edge_o  = s_div_clk_q & (s_div_cnt_q == div_i);

  assign s_div_cnt_d = s_div_cnt_q == div_i ? '0 : s_div_cnt_q + 2'd1;
  dffr #(2) u_div_cnt_dffr (
      clk_i,
      rst_n_i,
      s_div_cnt_d,
      s_div_cnt_q
  );


  assign s_div_clk_d = s_div_cnt_q == div_i ? ~s_div_clk_q : s_div_clk_q;
  dffr #(1) u_div_clk_dffr (
      clk_i,
      rst_n_i,
      s_div_clk_d,
      s_div_clk_q
  );

endmodule
