// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
// Synthesis-only headers for locked IHP SRAM macro physical views.

(* blackbox *)
module RM_IHPSG13_1P_4096x16_c3_bm_bist (
    input  wire        A_CLK,
    input  wire        A_MEN,
    input  wire        A_WEN,
    input  wire        A_REN,
    input  wire [11:0] A_ADDR,
    input  wire [15:0] A_DIN,
    input  wire        A_DLY,
    output wire [15:0] A_DOUT,
    input  wire [15:0] A_BM,
    input  wire        A_BIST_CLK,
    input  wire        A_BIST_EN,
    input  wire        A_BIST_MEN,
    input  wire        A_BIST_WEN,
    input  wire        A_BIST_REN,
    input  wire [11:0] A_BIST_ADDR,
    input  wire [15:0] A_BIST_DIN,
    input  wire [15:0] A_BIST_BM
);
endmodule

(* blackbox *)
module RM_IHPSG13_1P_4096x8_c3_bm_bist (
    input  wire        A_CLK,
    input  wire        A_MEN,
    input  wire        A_WEN,
    input  wire        A_REN,
    input  wire [11:0] A_ADDR,
    input  wire [ 7:0] A_DIN,
    input  wire        A_DLY,
    output wire [ 7:0] A_DOUT,
    input  wire [ 7:0] A_BM,
    input  wire        A_BIST_CLK,
    input  wire        A_BIST_EN,
    input  wire        A_BIST_MEN,
    input  wire        A_BIST_WEN,
    input  wire        A_BIST_REN,
    input  wire [11:0] A_BIST_ADDR,
    input  wire [ 7:0] A_BIST_DIN,
    input  wire [ 7:0] A_BIST_BM
);
endmodule
