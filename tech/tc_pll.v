module tc_pll (
    input         fref_i,
    input         rst_n_i,
    input  [ 7:0] refdiv_i,
    input  [11:0] fbdiv_i,
    input  [ 3:0] postdiv1_i,
    input  [ 1:0] postdiv2_i,
    input         bp_i,
    output        pll_lock_o,
    output        pll_clk_o
);

`ifdef RTL_BEHAV
  assign pll_lock_o = 1'b1;
  assign pll_clk_o  = fref_i;
`else

  `define LOCK_CNT_END 20'h1FFFF

  reg [19:0] s_lock_cnt;
  //lock Time Max 0.5ms(500us, 500*1000ns)
  always @(posedge fref_i or negedge rst_n_i) begin
    if (!rst_n_i) s_lock_cnt <= 20'h0;
    else if (s_lock_cnt < `LOCK_CNT_END) s_lock_cnt <= s_lock_cnt + 20'h1;
  end
  assign pll_lock_o = s_lock_cnt == `LOCK_CNT_END;

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
      .RESET    (1'b0),
      .SLEEP12  (1'b0),
      .OD       (postdiv2_i),
      .BP       (bp_i),
      .SELECT   (1'b1),
      .FS       (1'b0),
      .FRAC_N_in(20'h0),
      .LKDT     ()
  );

`endif
endmodule
