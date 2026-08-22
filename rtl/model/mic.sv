// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// i2s is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "config.svh"

module mic #(
    parameter int DATA_WIDTH = 24
) (
    input  logic sck_i,
    input  logic ws_i,
    output logic sd_o
);

  logic [DATA_WIDTH-1:0] r_right_chnl_dat = '0;
  logic [DATA_WIDTH-1:0] r_left_chnl_dat = '0;
  logic                  r_ws = '0;

  always @(posedge sck_i) r_ws <= #`REGISTER_DELAY ws_i;
  always @(negedge r_ws) r_left_chnl_dat <= #`REGISTER_DELAY $random;
  always @(posedge r_ws) r_right_chnl_dat <= #`REGISTER_DELAY $random;

  always @(negedge sck_i)
    if (~r_ws) begin
      sd_o            <= #`REGISTER_DELAY r_left_chnl_dat[DATA_WIDTH-1];
      r_left_chnl_dat <= #`REGISTER_DELAY r_left_chnl_dat << 1;
    end else begin
      sd_o             <= #`REGISTER_DELAY r_right_chnl_dat[DATA_WIDTH-1];
      r_right_chnl_dat <= #`REGISTER_DELAY r_right_chnl_dat << 1;
    end

endmodule
