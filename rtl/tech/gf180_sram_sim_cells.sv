// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// Pin-compatible functional model for the GF180 512x8 bit-write SRAM macro.
/* verilator lint_off DECLFILENAME */
module gf180mcu_fd_ip_sram__sram512x8m8wm1 (
    // verilog_format: off -- preserve the PDK memory interface columns
    input  logic       CLK,
    input  logic       CEN,
    input  logic       GWEN,
    input  logic [7:0] WEN,
    input  logic [8:0] A,
    input  logic [7:0] D,
    output logic [7:0] Q,
    inout  wire        VDD,
    inout  wire        VSS
    // verilog_format: on
);
  logic [7:0] s_storage_q[0:511];

  always_ff @(posedge CLK) begin
    if (!CEN && (VDD !== 1'b0) && (VSS !== 1'b1)) begin
      if (GWEN) begin
        Q <= s_storage_q[A];
      end else begin
        for (int unsigned bit_index = 0; bit_index < 8; bit_index++) begin
          if (!WEN[bit_index]) begin
            s_storage_q[A][bit_index] <= D[bit_index];
          end
        end
      end
    end
  end
endmodule
/* verilator lint_on DECLFILENAME */
