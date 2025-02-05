module tc_pll (
    input         fref_i,
    input  [ 5:0] refdiv_i,
    input  [11:0] fbdiv_i,
    input  [ 2:0] postdiv1_i,
    input  [ 2:0] postdiv2_i,
    output        pll_lock_o,
    output        pll_clk_o
);

`ifdef RTL_BEHV
  assign pll_lock_o = 1'b1;
  assign pll_clk_o  = fref_i;
`else
  assign pll_lock_o = 1'b1;
  assign pll_clk_o  = fref_i;
`endif
endmodule
