// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module dffr #(
    parameter int DATA_WIDTH = 1
) (
    input  logic                  clk_i,
    input  logic                  rst_n_i,
    input  logic [DATA_WIDTH-1:0] dat_i,
    output logic [DATA_WIDTH-1:0] dat_o
);
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) dat_o <= '0;
    else dat_o <= dat_i;
  end
endmodule

module dffer #(
    parameter int DATA_WIDTH = 1
) (
    input  logic                  clk_i,
    input  logic                  rst_n_i,
    input  logic                  en_i,
    input  logic [DATA_WIDTH-1:0] dat_i,
    output logic [DATA_WIDTH-1:0] dat_o
);
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) dat_o <= '0;
    else if (en_i) dat_o <= dat_i;
  end
endmodule

module PLL_TOP (
    output logic       CKOUT1,
    output logic       CKOUT2,
    output logic       CKTST,
    input  logic       EN,
    input  logic       REFCLK,
    input  logic       BP,
    input  logic       SELECT,
    input  logic [1:0] OD,
    input  logic [7:0] N
);
  assign CKOUT1 = REFCLK & EN;
  assign CKOUT2 = 1'b0;
  assign CKTST  = 1'b0;
endmodule

module tc_pll_ics55_tb;
  logic       fref;
  logic       rst_n;
  logic [2:0] cfg_sel;
  logic       cfg_apply;
  logic       capable;
  logic       locked;
  logic       pll_clk;

  tc_pll u_dut (
      .fref_i       (fref),
      .rst_n_i      (rst_n),
      .cfg_sel_i    (cfg_sel),
      .cfg_apply_i  (cfg_apply),
      .pll_capable_o(capable),
      .pll_lock_o   (locked),
      .pll_clk_o    (pll_clk)
  );

  always #5 fref = ~fref;

  task automatic apply_mode(input logic [2:0] mode);
    cfg_sel   = mode;
    cfg_apply = 1'b1;
    @(posedge fref);
    #1;
    cfg_apply = 1'b0;
  endtask

  initial begin
    fref      = 1'b0;
    rst_n     = 1'b0;
    cfg_sel   = 3'd0;
    cfg_apply = 1'b0;
    repeat (2) @(posedge fref);
    rst_n = 1'b1;
    repeat (6) @(posedge fref);
    #1;
    if (!capable || !locked) $fatal(1, "qualified ICS55 PLL mode did not lock");
    if (u_dut.u_PLL_TOP.N != 8'd2 || u_dut.u_PLL_TOP.OD != 2'd2) begin
      $fatal(1, "ICS55 PLL fixed configuration changed");
    end

    apply_mode(3'd1);
    repeat (8) @(posedge fref);
    #1;
    if (locked || u_dut.u_PLL_TOP.EN) $fatal(1, "unsupported ICS55 PLL mode locked");

    apply_mode(3'd0);
    repeat (6) @(posedge fref);
    #1;
    if (!locked || !u_dut.u_PLL_TOP.EN) $fatal(1, "qualified mode did not relock");
    $display("TC_PLL_ICS55_PASS");
    $finish;
  end
endmodule
