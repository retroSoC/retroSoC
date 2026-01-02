// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.


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
  wire s_xi_pad;
  assign s_xi_pad = xi_pad;
  (* keep *) (* dont_touch = "true" *)
  sg13g2_IOPadIn u_sg13g2_IOPadIn (
      .pad(s_xi_pad),
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

`elsif PDK_ICS55
  (* keep *) (* dont_touch = "true" *)
  P65_1233_PWE u_P65_1233_PWE (
      .E   (en),
      .XIN (xi_pad),
      .XOUT(xo_pad),
      .XC  (clk)
  );

`elsif PDK_GF180
  (* keep *) (* dont_touch = "true" *)
  wire s_xi_pad;
  assign s_xi_pad = xi_pad;
  assign xo_pad   = xi_pad;
  gf180mcu_fd_io__in_c u_gf180mcu_fd_io__in_c (
      .PU  (1'b0),
      .PD  (1'b0),
      .PAD (s_xi_pad),
      .Y   (clk),
      .DVDD(),
      .DVSS(),
      .VDD (),
      .VSS ()
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

`elsif PDK_GF180
  (* keep *) (* dont_touch = "true" *)
  gf180mcu_fd_io__in_c u_gf180mcu_fd_io__in_c (
      .PU  (1'b0),
      .PD  (1'b0),
      .PAD (pad),
      .Y   (c2p),
      .DVDD(),
      .DVSS(),
      .VDD (),
      .VSS ()
  );

`endif

endmodule

module tc_io_out_pad (
    inout wire  pad,
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

`elsif PDK_ICS55
  (* keep *) (* dont_touch = "true" *)
  P65_1233_PBMUX u_P65_1233_PBMUX (
      .C  (p2c),
      .A  (),
      .PAD(pad),
      .IE (~c2p_en),
      .CS (1'b1),     // 1: CMOS 0: SCHMI
      .I  (c2p),
      .OE (c2p_en),
      .OD (1'b0),
      .PU (1'b0),
      .PD (1'b0),
      .DS0(1'b0),
      .DS1(1'b1)      // 8mA
  );

`elsif PDK_GF180
  (* keep *) (* dont_touch = "true" *)
  gf180mcu_fd_io__bi_t u_gf180mcu_fd_io__bi_t (
      .CS   (1'b0),     // 1: SCHMI 0: CMOS
      .SL   (1'b0),     // 1: SLOW 0: FAST
      .IE   (~c2p_en),
      .OE   (c2p_en),
      .PU   (1'b0),
      .PD   (1'b0),
      .A    (c2p),
      .PDRV0(1'b0),
      .PDRV1(1'b0),     // 4mA
      .PAD  (pad),
      .Y    (p2c),
      .DVDD (),
      .DVSS (),
      .VDD  (),
      .VSS  ()
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

`elsif PDK_ICS55
  (* keep *) (* dont_touch = "true" *)
  P65_1233_PBMUX u_P65_1233_PBMUX (
      .C  (p2c),
      .A  (),
      .PAD(pad),
      .IE (~c2p_en),
      .CS (1'b0),     // 1: CMOS 0: SCHMI
      .I  (c2p),
      .OE (c2p_en),
      .OD (1'b0),
      .PU (1'b0),
      .PD (1'b0),
      .DS0(1'b0),
      .DS1(1'b1)      // 8mA
  );

`elsif PDK_GF180
  (* keep *) (* dont_touch = "true" *)
  gf180mcu_fd_io__bi_t u_gf180mcu_fd_io__bi_t (
      .CS   (1'b1),     // 1: SCHMI 0: CMOS
      .SL   (1'b0),     // 1: SLOW 0: FAST
      .IE   (~c2p_en),
      .OE   (c2p_en),
      .PU   (1'b0),
      .PD   (1'b0),
      .A    (c2p),
      .PDRV0(1'b0),
      .PDRV1(1'b0),     // 4mA
      .PAD  (pad),
      .Y    (p2c),
      .DVDD (),
      .DVSS (),
      .VDD  (),
      .VSS  ()
  );

`endif

endmodule


module tc_io_tri_full_pad (
    inout  wire  pad,
    input  logic c2p,
    input  logic c2p_en,
    output logic p2c,
    input  logic cs,
    input  logic pu,
    input  logic pd
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

`elsif PDK_ICS55
  (* keep *) (* dont_touch = "true" *)
  P65_1233_PBMUX u_P65_1233_PBMUX (
      .C  (p2c),
      .A  (),
      .PAD(pad),
      .IE (~c2p_en),
      .CS (cs),       // 1: CMOS 0: SCHMI
      .I  (c2p),
      .OE (c2p_en),
      .OD (1'b0),
      .PU (pu),       // active high
      .PD (pd),       // active high
      .DS0(1'b0),
      .DS1(1'b1)      // 8mA
  );

`elsif PDK_GF180
  (* keep *) (* dont_touch = "true" *)
  gf180mcu_fd_io__bi_t u_gf180mcu_fd_io__bi_t (
      .CS   (1'b1),     // 1: SCHMI 0: CMOS
      .SL   (1'b0),     // 1: SLOW 0: FAST
      .IE   (~c2p_en),
      .OE   (c2p_en),
      .PU   (1'b0),
      .PD   (1'b0),
      .A    (c2p),
      .PDRV0(1'b0),
      .PDRV1(1'b0),     // 4mA
      .PAD  (pad),
      .Y    (p2c),
      .DVDD (),
      .DVSS (),
      .VDD  (),
      .VSS  ()
  );

`endif

endmodule
