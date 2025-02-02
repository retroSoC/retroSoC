// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// ps2 is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module kdb_model (
    output reg ps2_clk_o,
    output reg ps2_dat_o
);
  parameter [31:0] clk_period = 60;
  initial begin
    ps2_clk_o = 1'b1;
    ps2_dat_o = 1'b1;
  end

  task send_code;
    input [7:0] code;
    integer        i;
    reg     [10:0] send_buf;
    begin
      send_buf[0]   = 1'b0;  // start bit
      send_buf[8:1] = code;  // code
      send_buf[9]   = ~(^code);  // odd parity bit
      send_buf[10]  = 1'b1;  // stop bit
      i             = 0;
      while (i < 11) begin
        // set kbd_data
        ps2_dat_o = send_buf[i];
        #(clk_period / 2) ps2_clk_o = 1'b0;
        #(clk_period / 2) ps2_clk_o = 1'b1;
        i = i + 1;
      end
      ps2_clk_o = 1'b1;
      ps2_dat_o = 1'b1;
    end
  endtask
endmodule
