// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
// You may use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// Yosys needs the macro interface even though PDK simulation models are excluded
// from the synthesis file list. The technology cell remains a black box.
`ifdef SYNTHESIS
`ifdef PDK_SKY130
(* blackbox *)
module sky130_fd_io__top_gpiov2 (
    input  wire       OUT,
    input  wire       OE_N,
    input  wire       HLD_H_N,
    input  wire       ENABLE_H,
    input  wire       ENABLE_INP_H,
    input  wire       ENABLE_VDDA_H,
    input  wire       ENABLE_VSWITCH_H,
    input  wire       ENABLE_VDDIO,
    input  wire       INP_DIS,
    input  wire       IB_MODE_SEL,
    input  wire       VTRIP_SEL,
    input  wire       SLOW,
    input  wire       HLD_OVR,
    input  wire       ANALOG_EN,
    input  wire       ANALOG_SEL,
    input  wire       ANALOG_POL,
    input  wire [2:0] DM,
    inout  wire       PAD,
    inout  wire       PAD_A_NOESD_H,
    inout  wire       PAD_A_ESD_0_H,
    inout  wire       PAD_A_ESD_1_H,
    inout  wire       AMUXBUS_A,
    inout  wire       AMUXBUS_B,
    output wire       IN,
    output wire       IN_H,
    output wire       TIE_HI_ESD,
    output wire       TIE_LO_ESD
);
endmodule
`endif
`endif
