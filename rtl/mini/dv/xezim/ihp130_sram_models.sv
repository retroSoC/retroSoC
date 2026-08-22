// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
//
// Xezim-only functional substitutes for the IHP130 SRAM wrappers.
// The production RTL and the Icarus/VCS PDK filelists keep the original models.

module RM_IHPSG13_1P_1024x64_c2_bm_bist (
    input  logic        A_CLK,
    input  logic        A_MEN,
    input  logic        A_WEN,
    input  logic        A_REN,
    input  logic [ 9:0] A_ADDR,
    input  logic [63:0] A_DIN,
    input  logic        A_DLY,
    output logic [63:0] A_DOUT,
    input  logic [63:0] A_BM,
    input  logic        A_BIST_CLK,
    input  logic        A_BIST_EN,
    input  logic        A_BIST_MEN,
    input  logic        A_BIST_WEN,
    input  logic        A_BIST_REN,
    input  logic [ 9:0] A_BIST_ADDR,
    input  logic [63:0] A_BIST_DIN,
    input  logic [63:0] A_BIST_BM
);
  logic   [63:0] memory[0:1023];
  integer        index;

  always_ff @(posedge A_CLK) begin
    if (A_MEN && A_WEN) begin
      for (index = 0; index < 64; index = index + 1) begin
        if (A_BM[index]) begin
          memory[A_ADDR][index] <= A_DIN[index];
        end
      end
    end
    if (A_MEN && A_REN) begin
      A_DOUT <= memory[A_ADDR];
    end
  end
endmodule

module RM_IHPSG13_1P_4096x16_c3_bm_bist (
    input  logic        A_CLK,
    input  logic        A_MEN,
    input  logic        A_WEN,
    input  logic        A_REN,
    input  logic [11:0] A_ADDR,
    input  logic [15:0] A_DIN,
    input  logic        A_DLY,
    output logic [15:0] A_DOUT,
    input  logic [15:0] A_BM,
    input  logic        A_BIST_CLK,
    input  logic        A_BIST_EN,
    input  logic        A_BIST_MEN,
    input  logic        A_BIST_WEN,
    input  logic        A_BIST_REN,
    input  logic [11:0] A_BIST_ADDR,
    input  logic [15:0] A_BIST_DIN,
    input  logic [15:0] A_BIST_BM
);
  logic   [15:0] memory[0:4095];
  integer        index;

  always_ff @(posedge A_CLK) begin
    if (A_MEN && A_WEN) begin
      for (index = 0; index < 16; index = index + 1) begin
        if (A_BM[index]) begin
          memory[A_ADDR][index] <= A_DIN[index];
        end
      end
    end
    if (A_MEN && A_REN) begin
      A_DOUT <= memory[A_ADDR];
    end
  end
endmodule

module RM_IHPSG13_1P_4096x8_c3_bm_bist (
    input  logic        A_CLK,
    input  logic        A_MEN,
    input  logic        A_WEN,
    input  logic        A_REN,
    input  logic [11:0] A_ADDR,
    input  logic [ 7:0] A_DIN,
    input  logic        A_DLY,
    output logic [ 7:0] A_DOUT,
    input  logic [ 7:0] A_BM,
    input  logic        A_BIST_CLK,
    input  logic        A_BIST_EN,
    input  logic        A_BIST_MEN,
    input  logic        A_BIST_WEN,
    input  logic        A_BIST_REN,
    input  logic [11:0] A_BIST_ADDR,
    input  logic [ 7:0] A_BIST_DIN,
    input  logic [ 7:0] A_BIST_BM
);
  logic   [7:0] memory[0:4095];
  integer       index;

  always_ff @(posedge A_CLK) begin
    if (A_MEN && A_WEN) begin
      for (index = 0; index < 8; index = index + 1) begin
        if (A_BM[index]) begin
          memory[A_ADDR][index] <= A_DIN[index];
        end
      end
    end
    if (A_MEN && A_REN) begin
      A_DOUT <= memory[A_ADDR];
    end
  end
endmodule
