// Copyright (C) 2022 ETH Zurich, University of Bologna Copyright and related
// rights are licensed under the Solderpad Hardware License, Version 0.51 (the
// "License"); you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law or
// agreed to in writing, software, hardware and materials distributed under this
// License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS
// OF ANY KIND, either express or implied. See the License for the specific
// language governing permissions and limitations under the License.
// SPDX-License-Identifier: SHL-0.51
//
// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// common is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef INC_CLK_INT_DIV_SV
`define INC_CLK_INT_DIV_SV

// NOTE: need to make sure the div_i is driven by reg
// div_val: (div_i + 1)
module clk_int_div_simple #(
    parameter DIV_VALUE_WIDTH  = 32,
    parameter DONE_DELAY_WIDTH = 3
) (
    input                        clk_i,
    input                        rst_n_i,
    input  [DIV_VALUE_WIDTH-1:0] div_i,
    input                        clk_init_i,
    input                        div_valid_i,
    output                       div_ready_o,
    output                       div_done_o,
    output [DIV_VALUE_WIDTH-1:0] clk_cnt_o,
    output                       clk_fir_trg_o,
    output                       clk_sec_trg_o,
    output                       clk_o
);

  reg  [ DIV_VALUE_WIDTH-1:0] s_cnt_d;
  wire [ DIV_VALUE_WIDTH-1:0] s_cnt_q;
  reg  [DONE_DELAY_WIDTH-1:0] s_div_done_d;
  wire [DONE_DELAY_WIDTH-1:0] s_div_done_q;
  reg                         s_clk_d;
  wire                        s_clk_q;
  wire                        div_hdshk;

  assign div_ready_o   = 1'b1;
  assign div_hdshk     = div_valid_i & div_ready_o;
  assign clk_cnt_o     = s_cnt_q;
  assign clk_fir_trg_o = div_i == 'h0 ? 'h0 : s_cnt_q == (div_i - 1) / 2;
  assign clk_sec_trg_o = s_cnt_q == div_i;

  always @(*) begin
    s_cnt_d = s_cnt_q + 1'b1;
    if (div_hdshk || div_i == 'h0) s_cnt_d = 'h0;
    else if (clk_sec_trg_o) s_cnt_d = 'h0;
  end
  dffr #(DIV_VALUE_WIDTH) u_cnt_dffr (
      clk_i,
      rst_n_i,
      s_cnt_d,
      s_cnt_q
  );

  // if div_i == 0, clk_o = clk_i
  // if div_i == 1, clk_o = clk_i / 2 chg on s_cnt_q == 0
  // if div_i == 2, clk_o = clk_i / 3 chg on s_cnt_q == 0
  // if div_i == 3, clk_o = clk_i / 4 chg on s_cnt_q == 1
  assign clk_o = div_i == 'h0 ? clk_i : s_clk_q;
  always @(*) begin
    if (div_hdshk) s_clk_d = clk_init_i;
    else if (clk_fir_trg_o || clk_sec_trg_o) s_clk_d = ~s_clk_q;
    else s_clk_d = s_clk_q;
  end
  dffr #(1) u_clk_dffr (
      clk_i,
      rst_n_i,
      s_clk_d,
      s_clk_q
  );

  assign div_done_o = s_div_done_q == {DONE_DELAY_WIDTH{1'b1}};
  always @(*) begin
    s_div_done_d = s_div_done_q;
    if (div_hdshk) begin
      s_div_done_d = 'h0;
    end else if (clk_sec_trg_o && s_div_done_q < {DONE_DELAY_WIDTH{1'b1}}) begin
      s_div_done_d = s_div_done_q + 1'b1;
    end
  end
  dffr #(DONE_DELAY_WIDTH) u_ready_dffr (
      clk_i,
      rst_n_i,
      s_div_done_d,
      s_div_done_q
  );

endmodule
`endif
