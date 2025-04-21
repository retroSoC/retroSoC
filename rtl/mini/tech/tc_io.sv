
module tc_io_xtl_pad (
    input  logic xi_pad,
    output logic xo_pad,
    input  logic en,
    output logic clk
);
`ifdef PDK_BEHAV
  assign clk    = en ? xi_pad : 1'b0;
  assign xo_pad = xi_pad;
`elsif PDK_IHP130
  (* keep *) (* dont_touch = "true" *)
  sg13g2_IOPadIn u_sg13g2_IOPadIn (
      .pad(xi_pad),
      .p2c(clk)
  );
  assign xo_pad = xi_pad;

`elsif PDK_S110
  (* keep *) (* dont_touch = "true" *)
  PXWE1W u_PXWE1W (
      .E   (en),
      .XIN (xi_pad),
      .XOUT(xo_pad),
      .XC  (clk)
  );
`endif

endmodule

module tc_io_in_pad (
    inout  logic pad,
    output logic p2c
);

`ifdef PDK_BEHAV
  assign p2c = pad;
`elsif PDK_IHP130
  (* keep *) (* dont_touch = "true" *)
  sg13g2_IOPadIn u_sg13g2_IOPadIn (
      .pad(pad),
      .p2c(p2c)
  );
`endif
endmodule

module tc_io_out_pad (
    inout logic pad,
    input logic c2p
);

`ifdef PDK_BEHAV
  assign pad = c2p;
`elsif PDK_IHP130
  (* keep *) (* dont_touch = "true" *)
  sg13g2_IOPadOut4mA u_sg13g2_IOPadOut4mA (
      .pad(pad),
      .c2p(c2p)
  );
`endif
endmodule

module tc_io_tri_pad (
    inout  wire  pad,
    input  logic c2p,
    input  logic c2p_en,
    output logic p2c
);

`ifdef PDK_BEHAV
  assign pad = c2p_en ? c2p : 1'bz;
  assign p2c = pad;
`elsif PDK_IHP130
  (* keep *) (* dont_touch = "true" *)
  sg13g2_IOPadInOut4mA u_sg13g2_IOPadInOut4mA (
      .pad   (pad),
      .c2p   (c2p),
      .c2p_en(c2p_en),
      .p2c   (p2c)
  );
`elsif PDK_S110
  (* keep *) (* dont_touch = "true" *)
  PB4W u_PB4W (
      .OEN(~c2p_en),
      .I  (c2p),
      .PAD(pad),
      .C  (p2c)
  );
`endif

endmodule


module tc_io_tri_schmitt_pad (
    inout  wire  pad,
    input  logic c2p,
    input  logic c2p_en,
    output logic p2c
);

`ifdef PDK_BEHAV
  assign pad = c2p_en ? c2p : 1'bz;
  assign p2c = pad;
`elsif PDK_IHP130
  (* keep *) (* dont_touch = "true" *)
  sg13g2_IOPadInOut4mA u_sg13g2_IOPadInOut4mA (
      .pad   (pad),
      .c2p   (c2p),
      .c2p_en(c2p_en),
      .p2c   (p2c)
  );
`elsif PDK_S110
  (* keep *) (* dont_touch = "true" *)
  PBS4W u_PBS4W (
      .OEN(~c2p_en),
      .I  (c2p),
      .PAD(pad),
      .C  (p2c)
  );
`endif

endmodule
