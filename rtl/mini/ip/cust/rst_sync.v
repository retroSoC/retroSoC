// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// common is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef INC_RST_SYNC_SV
`define INC_RST_SYNC_SV

module rst_sync #(
    parameter STAGE = 3
) (
    input  clk_i,
    input  rst_n_i,
    output rst_n_o
);

  wire [STAGE-1:0] s_rst_sync;
  genvar i;
  generate
    for (i = 0; i < STAGE; i = i + 1) begin : RST_SYNC_BLOCK
      if (i == 0) begin
        dffr #(1) u_sync_dffr (
            clk_i,
            rst_n_i,
            1'b1,
            s_rst_sync[0]
        );
      end else begin
        dffr #(1) u_sync_dffr (
            clk_i,
            rst_n_i,
            s_rst_sync[i-1],
            s_rst_sync[i]
        );
      end
    end
  endgenerate

  assign rst_n_o = s_rst_sync[STAGE-1];

endmodule

`endif
