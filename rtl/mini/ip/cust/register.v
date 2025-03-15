// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// common is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef INC_REGISTER_SV
`define INC_REGISTER_SV

`define SV_ASSRT_DISABLE

// `include "config.svh"

module dff #(
    parameter DATA_WIDTH = 1
) (
    input                       clk_i,
    input      [DATA_WIDTH-1:0] dat_i,
    output reg [DATA_WIDTH-1:0] dat_o
);

  always @(posedge clk_i) begin
    dat_o <= dat_i;
  end
endmodule

module dffr #(
    parameter DATA_WIDTH = 1
) (
    input                       clk_i,
    input                       rst_n_i,
    input      [DATA_WIDTH-1:0] dat_i,
    output reg [DATA_WIDTH-1:0] dat_o
);

  always @(posedge clk_i, negedge rst_n_i) begin
    if (~rst_n_i) begin
      dat_o <= {DATA_WIDTH{1'b0}};
    end else begin
      dat_o <= dat_i;
    end
  end
endmodule

module ndffr #(
    parameter DATA_WIDTH = 1
) (
    input                       clk_i,
    input                       rst_n_i,
    input      [DATA_WIDTH-1:0] dat_i,
    output reg [DATA_WIDTH-1:0] dat_o
);

  always @(negedge clk_i, negedge rst_n_i) begin
    if (~rst_n_i) begin
      dat_o <= {DATA_WIDTH{1'b0}};
    end else begin
      dat_o <= dat_i;
    end
  end
endmodule

module dffrh #(
    parameter DATA_WIDTH = 1
) (
    input                       clk_i,
    input                       rst_n_i,
    input      [DATA_WIDTH-1:0] dat_i,
    output reg [DATA_WIDTH-1:0] dat_o
);

  always @(posedge clk_i, negedge rst_n_i) begin
    if (~rst_n_i) begin
      dat_o <= {DATA_WIDTH{1'b1}};
    end else begin
      dat_o <= dat_i;
    end
  end
endmodule

module dffrc #(
    parameter                  DATA_WIDTH = 1,
    parameter [DATA_WIDTH-1:0] RESET_VAL  = {DATA_WIDTH{1'b0}}
) (
    input                       clk_i,
    input                       rst_n_i,
    input      [DATA_WIDTH-1:0] dat_i,
    output reg [DATA_WIDTH-1:0] dat_o
);

  always @(posedge clk_i, negedge rst_n_i) begin
    if (~rst_n_i) begin
      dat_o <= RESET_VAL;
    end else begin
      dat_o <= dat_i;
    end
  end
endmodule

module dffsr #(
    parameter DATA_WIDTH = 1
) (
    input                       clk_i,
    input                       rst_n_i,
    input      [DATA_WIDTH-1:0] dat_i,
    output reg [DATA_WIDTH-1:0] dat_o
);

  always @(posedge clk_i) begin
    if (~rst_n_i) begin
      dat_o <= {DATA_WIDTH{1'b0}};
    end else begin
      dat_o <= dat_i;
    end
  end
endmodule

module dffl #(
    parameter DATA_WIDTH = 1
) (
    input                       clk_i,
    input                       en_i,
    input      [DATA_WIDTH-1:0] dat_i,
    output reg [DATA_WIDTH-1:0] dat_o
);

  always @(posedge clk_i) begin
    if (en_i) begin
      dat_o <= dat_i;
    end
  end

`ifndef SV_ASSRT_DISABLE
  xchecker #(
      .DATA_WIDTH(1)
  ) u_xchecker (
      clk_i,
      en_i
  );
`endif

endmodule

module dffer #(
    parameter DATA_WIDTH = 1
) (
    input                       clk_i,
    input                       rst_n_i,
    input                       en_i,
    input      [DATA_WIDTH-1:0] dat_i,
    output reg [DATA_WIDTH-1:0] dat_o
);

  always @(posedge clk_i, negedge rst_n_i) begin
    if (~rst_n_i) begin
      dat_o <= {DATA_WIDTH{1'b0}};
    end else if (en_i) begin
      dat_o <= dat_i;
    end
  end

`ifndef SV_ASSRT_DISABLE
  xchecker #(
      .DATA_WIDTH(1)
  ) u_xchecker (
      clk_i,
      en_i
  );
`endif

endmodule

module dfferh #(
    parameter DATA_WIDTH = 1
) (
    input                       clk_i,
    input                       rst_n_i,
    input                       en_i,
    input      [DATA_WIDTH-1:0] dat_i,
    output reg [DATA_WIDTH-1:0] dat_o
);

  always @(posedge clk_i, negedge rst_n_i) begin
    if (~rst_n_i) begin
      dat_o <= {DATA_WIDTH{1'b1}};
    end else if (en_i) begin
      dat_o <= dat_i;
    end
  end

`ifndef SV_ASSRT_DISABLE
  xchecker #(
      .DATA_WIDTH(1)
  ) u_xchecker (
      clk_i,
      en_i
  );
`endif

endmodule

module dfferc #(
    parameter                  DATA_WIDTH = 1,
    parameter [DATA_WIDTH-1:0] RESET_VAL  = {DATA_WIDTH{1'b0}}
) (
    input                       clk_i,
    input                       rst_n_i,
    input                       en_i,
    input      [DATA_WIDTH-1:0] dat_i,
    output reg [DATA_WIDTH-1:0] dat_o
);

  always @(posedge clk_i, negedge rst_n_i) begin
    if (~rst_n_i) begin
      dat_o <= RESET_VAL;
    end else if (en_i) begin
      dat_o <= dat_i;
    end
  end

`ifndef SV_ASSRT_DISABLE
  xchecker #(
      .DATA_WIDTH(1)
  ) u_xchecker (
      clk_i,
      en_i
  );
`endif

endmodule

module dffesr #(
    parameter DATA_WIDTH = 1
) (
    input                       clk_i,
    input                       rst_n_i,
    input                       en_i,
    input      [DATA_WIDTH-1:0] dat_i,
    output reg [DATA_WIDTH-1:0] dat_o
);

  always @(posedge clk_i) begin
    if (~rst_n_i) begin
      dat_o <= {DATA_WIDTH{1'b0}};
    end else if (en_i) begin
      dat_o <= dat_i;
    end
  end

`ifndef SV_ASSRT_DISABLE
  xchecker #(
      .DATA_WIDTH(1)
  ) u_xchecker (
      clk_i,
      en_i
  );
`endif

endmodule

`endif
