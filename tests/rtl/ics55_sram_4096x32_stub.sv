// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module SRAM_4096X32_M8_BW (
    input  logic [11:0] A,
    input  logic [31:0] D,
    input  logic        CEB,
    input  logic        CLK,
    input  logic        GWEB,
    input  logic [31:0] WEB,
    input  logic        MARE,
    input  logic [ 3:0] MAR,
    output logic [31:0] Q
);
  logic [31:0] s_memory[0:4095];

  always_ff @(posedge CLK) begin
    if (!CEB) begin
      if (!GWEB) begin
        for (int bit_index = 0; bit_index < 32; bit_index++) begin
          if (!WEB[bit_index]) begin
            s_memory[A][bit_index] <= D[bit_index];
          end
        end
      end else begin
        Q <= s_memory[A];
      end
    end
  end

endmodule
