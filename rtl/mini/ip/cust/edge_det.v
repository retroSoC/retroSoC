
// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// common is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef INC_EDGE_DET_SV
`define INC_EDGE_DET_SV

// need to use high freq clk to oversample the dat edge with sync
module edge_det #(
    parameter STAGE      = 2,
    parameter DATA_WIDTH = 1
) (
    input                   clk_i,
    input                   rst_n_i,
    input  [DATA_WIDTH-1:0] dat_i,
    output [DATA_WIDTH-1:0] dat_o,
    output [DATA_WIDTH-1:0] re_o,
    output [DATA_WIDTH-1:0] fe_o
);

  wire [DATA_WIDTH-1:0] s_dat_d, s_dat_q;
  assign dat_o = s_dat_q;
  cdc_sync #(STAGE, DATA_WIDTH) u_cdc_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (dat_i),
      .dat_o  (s_dat_d)
  );

  dffr #(DATA_WIDTH) u_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dat_d),
      .dat_o  (s_dat_q)
  );

  assign re_o = (~s_dat_q) & s_dat_d;
  assign fe_o = s_dat_q & (~s_dat_d);
endmodule

module edge_det_re #(
    parameter STAGE      = 2,
    parameter DATA_WIDTH = 1
) (
    input                   clk_i,
    input                   rst_n_i,
    input  [DATA_WIDTH-1:0] dat_i,
    output [DATA_WIDTH-1:0] re_o
);

  wire [DATA_WIDTH-1:0] s_dat_d, s_dat_q;
  cdc_sync #(STAGE, DATA_WIDTH) u_cdc_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (dat_i),
      .dat_o  (s_dat_d)
  );

  dffr #(DATA_WIDTH) u_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dat_d),
      .dat_o  (s_dat_q)
  );

  assign re_o = (~s_dat_q) & s_dat_d;
endmodule

module edge_det_sync #(
    parameter DATA_WIDTH = 1
) (
    input                   clk_i,
    input                   rst_n_i,
    input  [DATA_WIDTH-1:0] dat_i,
    output [DATA_WIDTH-1:0] re_o,
    output [DATA_WIDTH-1:0] fe_o
);

  wire [DATA_WIDTH-1:0] s_dat_d, s_dat_q;
  assign s_dat_d = dat_i;
  dffr #(DATA_WIDTH) u_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dat_d),
      .dat_o  (s_dat_q)
  );

  assign re_o = (~s_dat_q) & s_dat_d;
  assign fe_o = s_dat_q & (~s_dat_d);
endmodule

module edge_det_sync_re #(
    parameter DATA_WIDTH = 1
) (
    input                   clk_i,
    input                   rst_n_i,
    input  [DATA_WIDTH-1:0] dat_i,
    output [DATA_WIDTH-1:0] re_o
);

  wire [DATA_WIDTH-1:0] s_dat_d, s_dat_q;
  assign s_dat_d = dat_i;
  dffr #(DATA_WIDTH) u_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dat_d),
      .dat_o  (s_dat_q)
  );

  assign re_o = (~s_dat_q) & s_dat_d;
endmodule

module edge_det_fe #(
    parameter STAGE      = 2,
    parameter DATA_WIDTH = 1
) (
    input                   clk_i,
    input                   rst_n_i,
    input  [DATA_WIDTH-1:0] dat_i,
    output [DATA_WIDTH-1:0] fe_o
);

  wire [DATA_WIDTH-1:0] s_dat_d, s_dat_q;
  cdc_sync #(STAGE, DATA_WIDTH) u_cdc_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (dat_i),
      .dat_o  (s_dat_d)
  );

  dffr #(DATA_WIDTH) u_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dat_d),
      .dat_o  (s_dat_q)
  );

  assign fe_o = s_dat_q & (~s_dat_d);
endmodule

module edge_det_sync_fe #(
    parameter DATA_WIDTH = 1
) (
    input                   clk_i,
    input                   rst_n_i,
    input  [DATA_WIDTH-1:0] dat_i,
    output [DATA_WIDTH-1:0] fe_o
);

  wire [DATA_WIDTH-1:0] s_dat_d, s_dat_q;
  assign s_dat_d = dat_i;
  dffr #(DATA_WIDTH) u_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dat_d),
      .dat_o  (s_dat_q)
  );

  assign fe_o = s_dat_q & (~s_dat_d);
endmodule
`endif
