// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// rng is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef INC_RNG_DEF_SV
`define INC_RNG_DEF_SV

/* register mapping
 * RNG_CTRL:
 * BITS:   | 31:1 | 0  |
 * FIELDS: | RES  | EN |
 * PERMS:  | RW   | RW |
 * ---------------------
 * RNG_SEED:
 * BITS:   | 31:0 |
 * FIELDS: | SEED |
 * PERMS:  | WO   |
 * ---------------------
 * RNG_VAL:
 * BITS:   | 31:0 |
 * FIELDS: | VAL  |
 * PERMS:  | RO   |
 * ---------------------
*/

// verilog_format: off
`define RNG_CTRL 4'b0000 // BASEADDR + 0x00
`define RNG_SEED 4'b0001 // BASEADDR + 0x04
`define RNG_VAL  4'b0010 // BASEADDR + 0x08

`define RNG_CTRL_ADDR {26'b0, `RNG_CTRL, 2'b00}
`define RNG_SEED_ADDR {26'b0, `RNG_SEED, 2'b00}
`define RNG_VAL_ADDR  {26'b0, `RNG_VAL , 2'b00}

`define RNG_CTRL_WIDTH 1
`define RNG_SEED_WIDTH 32
`define RNG_VAL_WIDTH  32
// verilog_format: on

`endif


// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// rng is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module apb4_rng (
    input         pclk,
    input         presetn,
    input  [31:0] paddr,
    input  [ 2:0] pprot,
    input         psel,
    input         penable,
    input         pwrite,
    input  [31:0] pwdata,
    input  [ 3:0] pstrb,
    output        pready,
    output [31:0] prdata,
    output        pslverr
);

  wire [3:0] s_apb4_addr;
  wire s_apb4_wr_hdshk, s_apb4_rd_hdshk;
  wire [`RNG_VAL_WIDTH-1:0] s_rng_val;
  wire [`RNG_CTRL_WIDTH-1:0] s_rng_ctrl_d, s_rng_ctrl_q;
  wire s_rng_ctrl_en;

  assign s_apb4_addr     = paddr[5:2];
  assign s_apb4_wr_hdshk = psel && penable && pwrite;
  assign s_apb4_rd_hdshk = psel && penable && (~pwrite);
  assign pready          = 1'b1;
  assign pslverr         = 1'b0;

  assign s_rng_ctrl_en   = s_apb4_wr_hdshk && s_apb4_addr == `RNG_CTRL;
  assign s_rng_ctrl_d    = pwdata[`RNG_CTRL_WIDTH-1:0];
  dffer #(`RNG_CTRL_WIDTH) u_rng_ctrl_dffer (
      pclk,
      presetn,
      s_rng_ctrl_en,
      s_rng_ctrl_d,
      s_rng_ctrl_q
  );

  // 32bits m-sequence
  lfsr_galois #(`RNG_VAL_WIDTH, 32'hE000_0200) u_lfsr_galois (
      .clk_i  (pclk),
      .rst_n_i(presetn),
      .wr_i   (s_apb4_wr_hdshk && s_apb4_addr == `RNG_SEED && s_rng_ctrl_q[0]),
      .dat_i  (pwdata[`RNG_VAL_WIDTH-1:0]),
      .dat_o  (s_rng_val)
  );

  assign prdata = ({32{~s_apb4_rd_hdshk}} & 32'h0) |
                  ({32{s_apb4_rd_hdshk}} & (({32{s_apb4_addr == `RNG_CTRL}} & {31'h0, s_rng_ctrl_q}) |
                  ({32{s_apb4_addr == `RNG_VAL}} & s_rng_val) | 32'h0));
endmodule
