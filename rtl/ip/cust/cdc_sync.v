// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// common is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef INC_CDC_SYNC_SV
`define INC_CDC_SYNC_SV

module cdc_sync #(
    parameter STAGE      = 2,
    parameter DATA_WIDTH = 1
) (
    input                   clk_i,
    input                   rst_n_i,
    input  [DATA_WIDTH-1:0] dat_i,
    output [DATA_WIDTH-1:0] dat_o
);

  wire [DATA_WIDTH-1:0] s_sync_dat[0:STAGE-1];
  genvar i;
  generate
    for (i = 0; i < STAGE; i = i + 1) begin : CDC_SYNC_BLOCK
      if (i == 0) begin
        dffr #(DATA_WIDTH) u_sync_dffr (
            clk_i,
            rst_n_i,
            dat_i,
            s_sync_dat[0]
        );
      end else begin
        dffr #(DATA_WIDTH) u_sync_dffr (
            clk_i,
            rst_n_i,
            s_sync_dat[i-1],
            s_sync_dat[i]
        );
      end
    end
  endgenerate


  assign dat_o = s_sync_dat[STAGE-1];
endmodule

module cdc_sync_det #(
    parameter STAGE      = 2,
    parameter DATA_WIDTH = 1
) (
    input                   clk_i,
    input                   rst_n_i,
    input  [DATA_WIDTH-1:0] dat_i,
    output [DATA_WIDTH-1:0] dat_pre_o,
    output [DATA_WIDTH-1:0] dat_o
);

  wire [DATA_WIDTH-1:0] s_sync_dat[0:STAGE-1];
  genvar i;
  generate
    for (i = 0; i < STAGE; i = i + 1) begin : CDC_SYNC_DET_BLOCK
      if (i == 0) begin
        dffr #(DATA_WIDTH) u_sync_dffr (
            clk_i,
            rst_n_i,
            dat_i,
            s_sync_dat[0]
        );
      end else begin
        dffr #(DATA_WIDTH) u_sync_dffr (
            clk_i,
            rst_n_i,
            s_sync_dat[i-1],
            s_sync_dat[i]
        );
      end
    end
  endgenerate

  assign dat_pre_o = s_sync_dat[STAGE-2];
  assign dat_o     = s_sync_dat[STAGE-1];
endmodule
`endif
