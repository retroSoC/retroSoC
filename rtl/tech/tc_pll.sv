// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.


module tc_pll (
    input  logic        fref_i,
    input  logic        rst_n_i,
    input  logic [ 7:0] refdiv_i,
    input  logic [11:0] fbdiv_i,
    input  logic [ 3:0] postdiv1_i,
    input  logic [ 1:0] postdiv2_i,
    input  logic        bp_i,
    output logic        pll_lock_o,
    output logic        pll_clk_o
);

`ifdef PDK_BEHAV
  assign pll_lock_o = 1'b1;
  assign pll_clk_o  = fref_i;
`elsif PDK_IHP130
  assign pll_lock_o = 1'b1;
  assign pll_clk_o  = fref_i;
`elsif PDK_ICS55
  assign pll_lock_o = 1'b1;
  assign pll_clk_o  = fref_i;
`elsif PDK_S110

`ifndef HAVE_PLL
  assign pll_lock_o = 1'b1;
  assign pll_clk_o  = fref_i;
`else
  `define LOCK_CNT_END 20'h1FFFF

  logic [19:0] s_lock_cnt_d, s_lock_cnt_q;

  assign pll_lock_o   = s_lock_cnt_q == `LOCK_CNT_END;
  //lock Time Max 0.5ms(500us, 500*1000ns)
  assign s_lock_cnt_d = s_lock_cnt_q + 20'h1;
  dffer #(20) u_lock_cnt_dffer (
      fref_i,
      rst_n_i,
      s_lock_cnt_q < `LOCK_CNT_END,
      s_lock_cnt_d,
      s_lock_cnt_q
  );

  S013PLLFN u0_pll (
      // .A2VDD33  (),
      // .A2VSS33  (),
      // .AVDD33   (),
      // .AVSS33   (),
      // .DVDD12   (),
      // .DVSS12   (),
      .XIN      (fref_i),
      .CLK_OUT  (pll_clk_o),
      .N        (postdiv1_i),
      .M        (refdiv_i),
      .RESET    ('0),
      .SLEEP12  ('0),
      .OD       (postdiv2_i),
      .BP       (bp_i),
      .SELECT   (1'b1),
      .FS       ('0),
      .FRAC_N_in('0),
      .LKDT     ()
  );

`endif
`endif
endmodule
