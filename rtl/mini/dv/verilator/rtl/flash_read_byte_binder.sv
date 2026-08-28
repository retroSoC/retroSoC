// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the License at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.

`timescale 1 ns / 1 ps

import "DPI-C" function void flash_read_byte(
  input  int  addr_i,
  output byte data_o
);

module flash_read_byte_binder (
    input  logic        clk_i,
    input  logic        rd_en_i,
    input  logic [31:0] addr_i,
    output logic [ 7:0] data_o
);

  always_ff @(posedge clk_i) begin
    if (rd_en_i) begin
      flash_read_byte(addr_i, data_o);
    end
  end

endmodule
