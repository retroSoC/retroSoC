module tc_io_xtl_pad (
    input  xi_pad,
    output xo_pad,
    input  en,
    output clk
);
`ifdef RTL_BEHAV
  assign clk    = en ? xi_pad : 1'b0;
  assign xo_pad = xi_pad;
`else
  (* keep *) (* dont_touch = "true" *)
  // sg13g2_IOPadIn u_sg13g2_IOPadIn (
  //     .pad(pad),
  //     .p2c(p2c)
  // );
  PXWE1W u_PXWE1W (
      .E   (en),
      .XIN (xi_pad),
      .XOUT(xo_pad),
      .XC  (clk)
  );
`endif

endmodule

// module tc_io_in_pad (
//     inout  pad,
//     output p2c
// );

// `ifdef RTL_BEHAV
//   assign p2c = pad;
// `else
//   (* keep *) (* dont_touch = "true" *)
//   sg13g2_IOPadIn u_sg13g2_IOPadIn (
//       .pad(pad),
//       .p2c(p2c)
//   );
// `endif
// endmodule

// module tc_io_out_pad (
//     inout pad,
//     input c2p
// );

// `ifdef RTL_BEHAV
//   assign pad = c2p;
// `else
//   (* keep *) (* dont_touch = "true" *)
//   sg13g2_IOPadOut4mA u_sg13g2_IOPadOut4mA (
//       .pad(pad),
//       .c2p(c2p)
//   );
// `endif
// endmodule

module tc_io_tri_pad (
    inout  pad,
    input  c2p,
    input  c2p_en,
    output p2c
);

`ifdef RTL_BEHAV
  assign pad = c2p_en ? c2p : 1'bz;
  assign p2c = pad;
`else
  (* keep *) (* dont_touch = "true" *)
  // sg13g2_IOPadInOut4mA u_sg13g2_IOPadInOut4mA (
  //     .pad   (pad),
  //     .c2p   (c2p),
  //     .c2p_en(c2p_en),
  //     .p2c   (p2c)
  // );
  PB4W u_PB4W (
      .OEN(~c2p_en),
      .I  (c2p),
      .PAD(pad),
      .C  (p2c)
  );

`endif

endmodule


module tc_io_tri_schmitt_pad (
    inout  pad,
    input  c2p,
    input  c2p_en,
    output p2c
);

`ifdef RTL_BEHAV
  assign pad = c2p_en ? c2p : 1'bz;
  assign p2c = pad;
`else
  (* keep *) (* dont_touch = "true" *)
  // sg13g2_IOPadInOut4mA u_sg13g2_IOPadInOut4mA (
  //     .pad   (pad),
  //     .c2p   (c2p),
  //     .c2p_en(c2p_en),
  //     .p2c   (p2c)
  // );
  PBS4W u_PBS4W (
      .OEN(~c2p_en),
      .I  (c2p),
      .PAD(pad),
      .C  (p2c)
  );

`endif

endmodule