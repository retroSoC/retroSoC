// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// common is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef INC_LFSR_SV
`define INC_LFSR_SV

//https://en.wikipedia.org/wiki/Linear-feedback_shift_register
// MSB -> LSB [DATA_WIDTH-1:0]
module lfsr_galois #(
    parameter DATA_WIDTH = 32,
    parameter POLY       = 32'h0
) (
    input  wire                  clk_i,
    input  wire                  rst_n_i,
    input  wire                  wr_i,
    input  wire [DATA_WIDTH-1:0] dat_i,
    output wire [DATA_WIDTH-1:0] dat_o
);

  wire [DATA_WIDTH-1:0] s_shift_d, s_shift_q;
  genvar i;

  generate
    for (i = 0; i < DATA_WIDTH; i = i + 1) begin : LFSR_GALOIS_BLOCK
      if (i == DATA_WIDTH - 1) begin
        assign s_shift_d[i] = wr_i ? dat_i[i] : s_shift_q[0];
      end else begin
        if (POLY & (1 << i)) begin
          assign s_shift_d[i] = wr_i ? dat_i[i] : s_shift_q[i+1] ^ s_shift_q[0];
        end else begin
          assign s_shift_d[i] = wr_i ? dat_i[i] : s_shift_q[i+1];
        end
      end
    end
  endgenerate

  assign dat_o = s_shift_q;
  dffr #(DATA_WIDTH) u_shift_dffr (
      clk_i,
      rst_n_i,
      s_shift_d,
      s_shift_q
  );

endmodule
`endif
