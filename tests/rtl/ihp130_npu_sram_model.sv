// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// Deterministic functional-only model for gate-level NPU transactions. The
// physical flow continues to use the locked IHP macro and Liberty views.
module RM_IHPSG13_1P_1024x32_c2_bm_bist (
    input  logic        A_CLK,
    input  logic        A_MEN,
    input  logic        A_WEN,
    input  logic        A_REN,
    input  logic [ 9:0] A_ADDR,
    input  logic [31:0] A_DIN,
    input  logic        A_DLY,
    output logic [31:0] A_DOUT,
    input  logic [31:0] A_BM,
    input  logic        A_BIST_CLK,
    input  logic        A_BIST_EN,
    input  logic        A_BIST_MEN,
    input  logic        A_BIST_WEN,
    input  logic        A_BIST_REN,
    input  logic [ 9:0] A_BIST_ADDR,
    input  logic [31:0] A_BIST_DIN,
    input  logic [31:0] A_BIST_BM
);
  logic [31:0] s_memory[0:1023];
  logic        s_men;
  logic        s_wen;
  logic        s_ren;
  logic [ 9:0] s_addr;
  logic [31:0] s_din;
  logic [31:0] s_mask;

  assign s_men  = A_BIST_EN ? A_BIST_MEN : A_MEN;
  assign s_wen  = A_BIST_EN ? A_BIST_WEN : A_WEN;
  assign s_ren  = A_BIST_EN ? A_BIST_REN : A_REN;
  assign s_addr = A_BIST_EN ? A_BIST_ADDR : A_ADDR;
  assign s_din  = A_BIST_EN ? A_BIST_DIN : A_DIN;
  assign s_mask = A_BIST_EN ? A_BIST_BM : A_BM;

  initial begin
    A_DOUT = '0;
    for (int unsigned index = 0; index < 1024; index++) begin
      s_memory[index] = '0;
    end
  end

  always_ff @(posedge A_CLK or posedge A_BIST_CLK) begin
    if (s_men && s_wen) begin
      s_memory[s_addr] <= (s_memory[s_addr] & ~s_mask) | (s_din & s_mask);
      if (s_ren) A_DOUT <= (s_memory[s_addr] & ~s_mask) | (s_din & s_mask);
    end else if (s_men && s_ren) begin
      A_DOUT <= s_memory[s_addr];
    end
  end

  logic s_unused;
  assign s_unused = A_DLY;
endmodule
