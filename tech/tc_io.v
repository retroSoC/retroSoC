module ihp_io_xtl_pad (
    input  xi_pad,
    output xo_pad,
    input  en,
    output clk
);

  assign clk    = en ? xi_pad : 1'b0;
  assign xo_pad = xi_pad;
endmodule

module ihp_io_tri_pad (
    inout  pad,
    input  c2p,
    input  c2p_en,
    output p2c
);

  (* keep *) (* dont_touch = "true" *)
  sg13g2_IOPadInOut4mA u_sg13g2_IOPadInOut4mA (
      .pad   (pad),
      .c2p   (c2p),
      .c2p_en(c2p_en),
      .p2c   (p2c)
  );

endmodule
