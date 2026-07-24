// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You may use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// Icarus functional models for the sequential GF180 cells selected by Yosys.
// The upstream models expose a timing notifier that the synthesized netlist
// leaves unconnected; these models retain the PDK cell interfaces without
// propagating that high-impedance notifier into functional simulation.
module gf180mcu_fd_sc_mcu7t5v0__dffq_1 (
    input  wire CLK,
    input  wire D,
    output reg  Q,
    input  wire notifier
);
  always @(posedge CLK) Q <= D;
endmodule

module gf180mcu_fd_sc_mcu7t5v0__dffrnq_1 (
    input  wire CLK,
    input  wire D,
    input  wire RN,
    output reg  Q,
    input  wire notifier
);
  always @(posedge CLK or negedge RN) begin
    if (!RN) Q <= 1'b0;
    else Q <= D;
  end
endmodule

module gf180mcu_fd_sc_mcu7t5v0__dffsnq_1 (
    input  wire CLK,
    input  wire D,
    input  wire SETN,
    output reg  Q,
    input  wire notifier
);
  always @(posedge CLK or negedge SETN) begin
    if (!SETN) Q <= 1'b1;
    else Q <= D;
  end
endmodule
