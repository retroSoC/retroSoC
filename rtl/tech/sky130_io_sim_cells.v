// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You may use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// The upstream Sky130 IO Verilog model uses switch primitives and drive strengths
// unsupported by the active simulator. This pin-compatible functional model is
// simulation-only; synthesis preserves the corresponding Sky130 PDK cell instance.
module sky130_fd_io__top_gpiov2 (
    IN_H,
    PAD_A_NOESD_H,
    PAD_A_ESD_0_H,
    PAD_A_ESD_1_H,
    PAD,
    DM,
    HLD_H_N,
    IN,
    INP_DIS,
    IB_MODE_SEL,
    ENABLE_H,
    ENABLE_VDDA_H,
    ENABLE_INP_H,
    OE_N,
    TIE_HI_ESD,
    TIE_LO_ESD,
    SLOW,
    VTRIP_SEL,
    HLD_OVR,
    ANALOG_EN,
    ANALOG_SEL,
    ENABLE_VDDIO,
    ENABLE_VSWITCH_H,
    ANALOG_POL,
    OUT,
    AMUXBUS_A,
    AMUXBUS_B
);
  input OUT;
  input OE_N;
  input HLD_H_N;
  input ENABLE_H;
  input ENABLE_INP_H;
  input ENABLE_VDDA_H;
  input ENABLE_VSWITCH_H;
  input ENABLE_VDDIO;
  input INP_DIS;
  input IB_MODE_SEL;
  input VTRIP_SEL;
  input SLOW;
  input HLD_OVR;
  input ANALOG_EN;
  input ANALOG_SEL;
  input ANALOG_POL;
  input [2:0] DM;
  inout PAD;
  inout PAD_A_NOESD_H;
  inout PAD_A_ESD_0_H;
  inout PAD_A_ESD_1_H;
  inout AMUXBUS_A;
  inout AMUXBUS_B;
  output IN;
  output IN_H;
  output TIE_HI_ESD;
  output TIE_LO_ESD;

  wire s_output_enable;

  assign s_output_enable = !OE_N && (DM != 3'b000) && (DM != 3'b001);
  assign PAD             = s_output_enable ? OUT : 1'bz;
  assign IN              = INP_DIS ? 1'b0 : PAD;
  assign IN_H            = IN;
  assign TIE_HI_ESD      = 1'b1;
  assign TIE_LO_ESD      = 1'b0;
endmodule
