// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"

module mgmt_core_wrapper (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [31:0] irq_i,
    nmi_if.master       nmi
    // verilog_format: on
);

  picorv32 #(
      .BARREL_SHIFTER (1),
      .COMPRESSED_ISA (1),
      .ENABLE_MUL     (1),
      .ENABLE_FAST_MUL(1),
      .ENABLE_DIV     (1),
      .ENABLE_IRQ     (0),
      .PROGADDR_RESET (`FLASH_START_ADDR)
  ) u_picorv32 (
      .clk      (clk_i),
      .resetn   (rst_n_i),
      .mem_valid(nmi.valid),
      .mem_instr(),
      .mem_addr (nmi.addr),
      .mem_wdata(nmi.wdata),
      .mem_wstrb(nmi.wstrb),
      .mem_rdata(nmi.rdata),
      .mem_ready(nmi.ready),
      .irq      (irq_i),
      .trap     ()
  );
endmodule
