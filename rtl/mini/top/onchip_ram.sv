// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// 32x4KB=128KB
module onchip_ram (
    // verilog_format: off
    input logic  clk_i,
    ram_if.slave ram
    // verilog_format: on
);

  logic        s_cs   [31:0];
  logic [31:0] s_rdata[0:31];

  // verilog_format: off
  assign s_cs[0]  = ~ram.addr[14] && ~ram.addr[13] && ~ram.addr[12] & ~ram.addr[11] && ~ram.addr[10];
  assign s_cs[1]  = ~ram.addr[14] && ~ram.addr[13] && ~ram.addr[12] & ~ram.addr[11] &&  ram.addr[10];
  assign s_cs[2]  = ~ram.addr[14] && ~ram.addr[13] && ~ram.addr[12] &  ram.addr[11] && ~ram.addr[10];
  assign s_cs[3]  = ~ram.addr[14] && ~ram.addr[13] && ~ram.addr[12] &  ram.addr[11] &&  ram.addr[10];
  assign s_cs[4]  = ~ram.addr[14] && ~ram.addr[13] &&  ram.addr[12] & ~ram.addr[11] && ~ram.addr[10];
  assign s_cs[5]  = ~ram.addr[14] && ~ram.addr[13] &&  ram.addr[12] & ~ram.addr[11] &&  ram.addr[10];
  assign s_cs[6]  = ~ram.addr[14] && ~ram.addr[13] &&  ram.addr[12] &  ram.addr[11] && ~ram.addr[10];
  assign s_cs[7]  = ~ram.addr[14] && ~ram.addr[13] &&  ram.addr[12] &  ram.addr[11] &&  ram.addr[10];
  assign s_cs[8]  = ~ram.addr[14] &&  ram.addr[13] && ~ram.addr[12] & ~ram.addr[11] && ~ram.addr[10];
  assign s_cs[9]  = ~ram.addr[14] &&  ram.addr[13] && ~ram.addr[12] & ~ram.addr[11] &&  ram.addr[10];
  assign s_cs[10] = ~ram.addr[14] &&  ram.addr[13] && ~ram.addr[12] &  ram.addr[11] && ~ram.addr[10];
  assign s_cs[11] = ~ram.addr[14] &&  ram.addr[13] && ~ram.addr[12] &  ram.addr[11] &&  ram.addr[10];
  assign s_cs[12] = ~ram.addr[14] &&  ram.addr[13] &&  ram.addr[12] & ~ram.addr[11] && ~ram.addr[10];
  assign s_cs[13] = ~ram.addr[14] &&  ram.addr[13] &&  ram.addr[12] & ~ram.addr[11] &&  ram.addr[10];
  assign s_cs[14] = ~ram.addr[14] &&  ram.addr[13] &&  ram.addr[12] &  ram.addr[11] && ~ram.addr[10];
  assign s_cs[15] = ~ram.addr[14] &&  ram.addr[13] &&  ram.addr[12] &  ram.addr[11] &&  ram.addr[10];
  assign s_cs[16] =  ram.addr[14] && ~ram.addr[13] && ~ram.addr[12] & ~ram.addr[11] && ~ram.addr[10];
  assign s_cs[17] =  ram.addr[14] && ~ram.addr[13] && ~ram.addr[12] & ~ram.addr[11] &&  ram.addr[10];
  assign s_cs[18] =  ram.addr[14] && ~ram.addr[13] && ~ram.addr[12] &  ram.addr[11] && ~ram.addr[10];
  assign s_cs[19] =  ram.addr[14] && ~ram.addr[13] && ~ram.addr[12] &  ram.addr[11] &&  ram.addr[10];
  assign s_cs[20] =  ram.addr[14] && ~ram.addr[13] &&  ram.addr[12] & ~ram.addr[11] && ~ram.addr[10];
  assign s_cs[21] =  ram.addr[14] && ~ram.addr[13] &&  ram.addr[12] & ~ram.addr[11] &&  ram.addr[10];
  assign s_cs[22] =  ram.addr[14] && ~ram.addr[13] &&  ram.addr[12] &  ram.addr[11] && ~ram.addr[10];
  assign s_cs[23] =  ram.addr[14] && ~ram.addr[13] &&  ram.addr[12] &  ram.addr[11] &&  ram.addr[10];
  assign s_cs[24] =  ram.addr[14] &&  ram.addr[13] && ~ram.addr[12] & ~ram.addr[11] && ~ram.addr[10];
  assign s_cs[25] =  ram.addr[14] &&  ram.addr[13] && ~ram.addr[12] & ~ram.addr[11] &&  ram.addr[10];
  assign s_cs[26] =  ram.addr[14] &&  ram.addr[13] && ~ram.addr[12] &  ram.addr[11] && ~ram.addr[10];
  assign s_cs[27] =  ram.addr[14] &&  ram.addr[13] && ~ram.addr[12] &  ram.addr[11] &&  ram.addr[10];
  assign s_cs[28] =  ram.addr[14] &&  ram.addr[13] &&  ram.addr[12] & ~ram.addr[11] && ~ram.addr[10];
  assign s_cs[29] =  ram.addr[14] &&  ram.addr[13] &&  ram.addr[12] & ~ram.addr[11] &&  ram.addr[10];
  assign s_cs[30] =  ram.addr[14] &&  ram.addr[13] &&  ram.addr[12] &  ram.addr[11] && ~ram.addr[10];
  assign s_cs[31] =  ram.addr[14] &&  ram.addr[13] &&  ram.addr[12] &  ram.addr[11] &&  ram.addr[10];

  assign ram.rdata = s_rdata[ram.addr[14:10]];
  // verilog_format: on

  for (genvar i = 0; i < 32; ++i) begin : gen_sram_block
    tc_sram_1024x32 u_ram (
        .clk_i (clk_i),
        .cs_i  (s_cs[i]),
        .addr_i(ram.addr[9:0]),
        .data_i(ram.wdata),
        .mask_i(ram.wstrb),
        .wren_i(|ram.wstrb_i),
        .data_o(s_rdata[i])
    );
  end

endmodule
