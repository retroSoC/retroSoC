// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.


`timescale 1 ns / 1 ps

import "DPI-C" function void flash_read(
  input  int addr_i,
  output int data_o
);

module flash_read_binder #(
    parameter int BUS_WIDTH = 32
) (
    input                      clk_i,
    input                      rd_en_i,
    input      [BUS_WIDTH-1:0] addr_i,
    output reg [BUS_WIDTH-1:0] data_o
);
  always @(posedge clk_i) begin
    if (rd_en_i) flash_read(addr_i, data_o);
  end
endmodule
