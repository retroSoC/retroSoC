// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// Liberty-compatible fast model for the OpenRAM-generated SKY130 1024x32 macro.
/* verilator lint_off DECLFILENAME */
module sky130_sram_4kbyte_1rw_32x1024_8 (
    // verilog_format: off -- preserve the OpenRAM memory interface columns
`ifdef USE_POWER_PINS
    inout  wire         vccd1,
    inout  wire         vssd1,
`endif
    input  logic        clk0,
    input  logic        csb0,
    input  logic        web0,
    input  logic [ 3:0] wmask0,
    input  logic [10:0] addr0,
    input  logic [31:0] din0,
    output logic [31:0] dout0
    // verilog_format: on
);
  logic s_disable;

`ifdef USE_POWER_PINS
  assign s_disable = csb0 || !vccd1 || vssd1;
`else
  assign s_disable = csb0;
`endif

  tech_ram_bm #(
      .BIT_WIDTH (32),
      .WORD_DEPTH(1024)
  ) u_tech_ram_bm (
      .clk_i (clk0),
      .en_i  (s_disable),
      .wen_i (web0),
      .bm_i  (~wmask0),
      .addr_i(addr0[9:0]),
      .dat_i (din0),
      .dat_o (dout0)
  );
endmodule
/* verilator lint_on DECLFILENAME */
