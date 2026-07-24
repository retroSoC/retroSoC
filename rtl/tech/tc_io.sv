// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.


`ifdef PDK_GF180
module tc_io_gf180_bi_pad (
    inout  wire  pad,
    input  logic c2p,
    input  logic c2p_en,
    output logic p2c,
    input  logic cs,
    input  logic pu,
    input  logic pd
);
  logic s_p2c;
  wire  s_dvdd = 1'b1;
  wire  s_dvss = 1'b0;
  wire  s_vdd = 1'b1;
  wire  s_vss = 1'b0;

  (* keep *) (* dont_touch = "true" *)
  gf180mcu_fd_io__bi_t u_gf180mcu_fd_io__bi_t (
      .CS   (cs),
      .SL   (1'b0),
      .IE   (~c2p_en),
      .OE   (c2p_en),
      .PU   (pu),
      .PD   (pd),
      .A    (c2p),
      .PDRV0(1'b0),
      .PDRV1(1'b0),
      .PAD  (pad),
      .Y    (s_p2c),
      .DVDD (s_dvdd),
      .DVSS (s_dvss),
      .VDD  (s_vdd),
      .VSS  (s_vss)
  );

  // gf180mcu_fd_io__bi_t forbids simultaneous input and output enable.
  assign p2c = c2p_en ? c2p : s_p2c;
endmodule
`endif

`ifdef PDK_SKY130
module tc_io_sky130_pad (
    inout  wire  pad,
    input  logic c2p,
    input  logic c2p_en,
    output logic p2c,
    input  logic cs
);
  logic s_p2c;

  (* keep *) (* dont_touch = "true" *)
  sky130_fd_io__top_gpiov2 u_sky130_fd_io__top_gpiov2 (
      .OUT             (c2p),
      .OE_N            (~c2p_en),
      .HLD_H_N         (1'b1),
      .INP_DIS         (1'b0),
      .IB_MODE_SEL     (1'b0),
      .ENABLE_H        (1'b1),
      .ENABLE_VDDA_H   (1'b0),
      .ENABLE_INP_H    (1'b0),
      .ENABLE_VDDIO    (1'b1),
      .ENABLE_VSWITCH_H(1'b0),
      .TIE_HI_ESD      (),
      .TIE_LO_ESD      (),
      .SLOW            (1'b0),
      .VTRIP_SEL       (cs),
      .HLD_OVR         (1'b0),
      .ANALOG_EN       (1'b0),
      .ANALOG_SEL      (1'b0),
      .ANALOG_POL      (1'b0),
      .DM              (3'b110),
      .PAD             (pad),
      .PAD_A_NOESD_H   (),
      .PAD_A_ESD_0_H   (),
      .PAD_A_ESD_1_H   (),
      .IN              (s_p2c),
      .IN_H            (),
      .AMUXBUS_A       (),
      .AMUXBUS_B       ()
  );

  assign p2c = s_p2c;
endmodule
`endif


module tc_io_xtl_pad (
    input  logic xi_pad,
    output logic xo_pad,
    input  logic en,
    output logic clk
);
`ifdef PDK_BEHAV
  assign clk    = en ? xi_pad : 1'b0;
  assign xo_pad = xi_pad;

`elsif PDK_SKY130
  // No qualified SKY130 crystal pad is selected. The Makefile rejects HAVE_PLL=YES.
  assign clk    = en ? xi_pad : 1'b0;
  assign xo_pad = xi_pad;

`elsif PDK_GF180
  // No qualified GF180 crystal pad is selected. The Makefile rejects HAVE_PLL=YES.
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

`endif

endmodule

module tc_io_in_pad (
    inout  logic pad,
    output logic p2c
);

`ifdef PDK_BEHAV
  assign p2c = pad;

`elsif PDK_SKY130
  tc_io_sky130_pad u_tc_io_sky130_pad (
      .pad   (pad),
      .c2p   (1'b0),
      .c2p_en(1'b0),
      .p2c   (p2c),
      .cs    (1'b0)
  );

`elsif PDK_GF180
  wire s_dvdd = 1'b1;
  wire s_dvss = 1'b0;
  wire s_vdd = 1'b1;
  wire s_vss = 1'b0;
  (* keep *) (* dont_touch = "true" *)
  gf180mcu_fd_io__in_c u_gf180mcu_fd_io__in_c (
      .PU  (1'b0),
      .PD  (1'b0),
      .PAD (pad),
      .Y   (p2c),
      .DVDD(s_dvdd),
      .DVSS(s_dvss),
      .VDD (s_vdd),
      .VSS (s_vss)
  );

`elsif PDK_IHP130
  (* keep *) (* dont_touch = "true" *)
  sg13g2_IOPadIn u_sg13g2_IOPadIn (
      .pad(pad),
      .p2c(p2c)
  );

`endif

endmodule

module tc_io_out_pad (
    inout wire  pad,
    input logic c2p
);

`ifdef PDK_BEHAV
  assign pad = c2p;

`elsif PDK_SKY130
  logic unused_p2c;
  tc_io_sky130_pad u_tc_io_sky130_pad (
      .pad   (pad),
      .c2p   (c2p),
      .c2p_en(1'b1),
      .p2c   (unused_p2c),
      .cs    (1'b0)
  );

`elsif PDK_GF180
  logic unused_p2c;
  tc_io_gf180_bi_pad u_tc_io_gf180_bi_pad (
      .pad   (pad),
      .c2p   (c2p),
      .c2p_en(1'b1),
      .p2c   (unused_p2c),
      .cs    (1'b0),
      .pu    (1'b0),
      .pd    (1'b0)
  );

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

`elsif PDK_SKY130
  tc_io_sky130_pad u_tc_io_sky130_pad (
      .pad   (pad),
      .c2p   (c2p),
      .c2p_en(c2p_en),
      .p2c   (p2c),
      .cs    (1'b0)
  );

`elsif PDK_GF180
  tc_io_gf180_bi_pad u_tc_io_gf180_bi_pad (
      .pad   (pad),
      .c2p   (c2p),
      .c2p_en(c2p_en),
      .p2c   (p2c),
      .cs    (1'b0),
      .pu    (1'b0),
      .pd    (1'b0)
  );

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

`elsif PDK_SKY130
  tc_io_sky130_pad u_tc_io_sky130_pad (
      .pad   (pad),
      .c2p   (c2p),
      .c2p_en(c2p_en),
      .p2c   (p2c),
      .cs    (1'b1)
  );

`elsif PDK_GF180
  tc_io_gf180_bi_pad u_tc_io_gf180_bi_pad (
      .pad   (pad),
      .c2p   (c2p),
      .c2p_en(c2p_en),
      .p2c   (p2c),
      .cs    (1'b1),
      .pu    (1'b0),
      .pd    (1'b0)
  );

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

`elsif PDK_SKY130
  logic [1:0] unused_pull;
  assign unused_pull = {pu, pd};
  tc_io_sky130_pad u_tc_io_sky130_pad (
      .pad   (pad),
      .c2p   (c2p),
      .c2p_en(c2p_en),
      .p2c   (p2c),
      .cs    (cs)
  );

`elsif PDK_GF180
  tc_io_gf180_bi_pad u_tc_io_gf180_bi_pad (
      .pad   (pad),
      .c2p   (c2p),
      .c2p_en(c2p_en),
      .p2c   (p2c),
      .cs    (cs),
      .pu    (pu),
      .pd    (pd)
  );

`elsif PDK_IHP130
  logic [2:0] dum;
  assign dum[0] = cs;
  assign dum[1] = pu;
  assign dum[2] = pd;
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

`endif

endmodule
