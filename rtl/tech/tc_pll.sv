// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module tc_pll (
    input  logic       fref_i,
    input  logic       rst_n_i,
    input  logic [2:0] cfg_sel_i,
    input  logic       cfg_apply_i,
    output logic       pll_capable_o,
    output logic       pll_lock_o,
    output logic       pll_clk_o
);

`ifdef PDK_BEHAV
  localparam logic [2:0] PLL_LOCK_CYCLES = 3'd4;

  logic [2:0] s_cfg_sel_d, s_cfg_sel_q;
  logic [2:0] s_lock_count_d, s_lock_count_q;
  logic s_lock_d, s_lock_q;
  logic s_apply_seen_d, s_apply_seen_q;
  logic s_cfg_apply;
  logic s_force_lock_fail;
  time  s_last_ref_edge;
  time  s_ref_period;

  function automatic int pll_multiplier(input logic [2:0] cfg_sel);
    case (cfg_sel)
      3'd0:    pll_multiplier = 1;
      3'd1:    pll_multiplier = 2;
      3'd2:    pll_multiplier = 3;
      3'd3:    pll_multiplier = 4;
      3'd4:    pll_multiplier = 5;
      3'd5:    pll_multiplier = 6;
      3'd6:    pll_multiplier = 7;
      default: pll_multiplier = 8;
    endcase
  endfunction

  initial begin
    s_force_lock_fail = $test$plusargs("pll_lock_fail");
    s_last_ref_edge   = 0;
    s_ref_period      = 0;
    pll_clk_o         = 1'b0;
  end

  always @(posedge fref_i) begin
    if (s_last_ref_edge != 0) begin
      s_ref_period = $time - s_last_ref_edge;
    end
    s_last_ref_edge = $time;
  end

  always begin
    @(posedge fref_i);
    wait (pll_lock_o);
    while (pll_lock_o) begin
      #(s_ref_period / (2 * pll_multiplier(s_cfg_sel_q)));
      if (pll_lock_o) begin
        pll_clk_o = ~pll_clk_o;
      end
    end
    pll_clk_o = 1'b0;
  end

  assign pll_capable_o = 1'b1;
  assign pll_lock_o    = s_lock_q;
  assign s_cfg_apply   = cfg_apply_i && !s_apply_seen_q;
  assign s_cfg_sel_d   = cfg_sel_i;
  dffer #(3) u_cfg_sel_dffer (
      fref_i,
      rst_n_i,
      s_cfg_apply,
      s_cfg_sel_d,
      s_cfg_sel_q
  );

  assign s_apply_seen_d = cfg_apply_i;
  dffr #(1) u_apply_seen_dffr (
      fref_i,
      rst_n_i,
      s_apply_seen_d,
      s_apply_seen_q
  );

  always_comb begin
    s_lock_count_d = s_lock_count_q;
    s_lock_d       = s_lock_q;
    if (s_cfg_apply) begin
      s_lock_count_d = '0;
      s_lock_d       = 1'b0;
    end else if (!s_lock_q && !s_force_lock_fail) begin
      if (s_lock_count_q == PLL_LOCK_CYCLES - 1'b1) begin
        s_lock_d = 1'b1;
      end else begin
        s_lock_count_d = s_lock_count_q + 1'b1;
      end
    end
  end
  dffr #(3) u_lock_count_dffr (
      fref_i,
      rst_n_i,
      s_lock_count_d,
      s_lock_count_q
  );
  dffr #(1) u_lock_dffr (
      fref_i,
      rst_n_i,
      s_lock_d,
      s_lock_q
  );
`else
  assign pll_capable_o = 1'b0;
  assign pll_lock_o    = 1'b0;
  assign pll_clk_o     = fref_i;
`endif
endmodule
