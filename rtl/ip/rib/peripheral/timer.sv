/*
 *  Ravenna - A full example SoC using PicoRV32 in ASIC
 *
 *  Copyright (C) 2017  Clifford Wolf <clifford@clifford.at>
 *  Copyright (C) 2018,2019  Tim Edwards <tim@efabless.com>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 * Simple 32-bit counter-timer for ravenna. */

// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RIB_TIMER_DEF_SV
`define RIB_TIMER_DEF_SV

// verilog_format: off
`define RIB_TIMER_CFG 8'h00
`define RIB_TIMER_RLD 8'h04
`define RIB_TIMER_VAL 8'h08
// verilog_format: on

`endif

module rib_timer (
    // verilog_format: off
    input  logic clk_i,
    input  logic rst_n_i,
    rib_if.slave rib,
    output logic irq_o
    // verilog_format: on
);

  // rib
  logic s_irq_d, s_irq_q;
  logic s_rib_wr_hdshk, s_rib_rd_hdshk;
  logic s_rib_ready_d, s_rib_ready_q;
  logic s_rib_rdata_en;
  logic [31:0] s_rib_rdata_d, s_rib_rdata_q;
  // register
  logic s_tim_cfg_en;
  logic [3:0] s_tim_cfg_d, s_tim_cfg_q;
  logic s_tim_rld_en;
  logic [31:0] s_tim_rld_d, s_tim_rld_q;
  logic [31:0] s_tim_val_d, s_tim_val_q;
  // enable (start) the counter/timer
  // set s_bit_oneshot (1) mode or continuous (0) mode
  // count up (1) or down (0)
  // enable interrupt on timeout
  logic s_bit_en, s_bit_oneshot;
  logic s_bit_updown, s_bit_irq_en;
  // irq
  assign irq_o          = s_irq_q;

  assign s_rib_wr_hdshk = rib.valid && (~s_rib_ready_q) && (|rib.wstrb);
  assign s_rib_rd_hdshk = rib.valid && (~s_rib_ready_q) && (~(|rib.wstrb));
  assign rib.ready      = s_rib_ready_q;
  assign rib.rdata      = s_rib_rdata_q;

  assign s_bit_en       = s_tim_cfg_q[0];
  assign s_bit_oneshot  = s_tim_cfg_q[1];
  assign s_bit_updown   = s_tim_cfg_q[2];
  assign s_bit_irq_en   = s_tim_cfg_q[3];

  // register
  assign s_tim_cfg_en   = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_TIMER_CFG;
  assign s_tim_cfg_d    = rib.wdata[3:0];
  dffer #(4) u_tim_cfg_dffer (
      clk_i,
      rst_n_i,
      s_tim_cfg_en && rib.wstrb[0],
      s_tim_cfg_d,
      s_tim_cfg_q
  );


  assign s_tim_rld_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_TIMER_RLD;
  always_comb begin
    s_tim_rld_d = s_tim_rld_q;
    if (rib.wstrb[0]) s_tim_rld_d[7:0] = rib.wdata[7:0];
    if (rib.wstrb[1]) s_tim_rld_d[15:8] = rib.wdata[15:8];
    if (rib.wstrb[2]) s_tim_rld_d[23:16] = rib.wdata[23:16];
    if (rib.wstrb[3]) s_tim_rld_d[31:24] = rib.wdata[31:24];
  end
  dffer #(32) u_tim_rld_dffer (
      clk_i,
      rst_n_i,
      s_tim_rld_en,
      s_tim_rld_d,
      s_tim_rld_q
  );


  always_comb begin
    s_tim_val_d = s_tim_val_q;
    s_irq_d     = s_irq_q;
    if (s_rib_wr_hdshk && rib.addr[7:0] == `RIB_TIMER_VAL) begin
      if (rib.wstrb[0]) s_tim_val_d[7:0] = rib.wdata[7:0];
      if (rib.wstrb[1]) s_tim_val_d[15:8] = rib.wdata[15:8];
      if (rib.wstrb[2]) s_tim_val_d[23:16] = rib.wdata[23:16];
      if (rib.wstrb[3]) s_tim_val_d[31:24] = rib.wdata[31:24];
    end else if (s_bit_en) begin
      if (s_bit_updown) begin
        if (s_tim_val_q == s_tim_rld_q) begin
          if (~s_bit_oneshot) s_tim_val_d = '0;
          s_irq_d = s_bit_irq_en;
        end else begin
          s_tim_val_d = s_tim_val_q + 1'b1;
          s_irq_d     = '0;
        end
      end else begin
        if (s_tim_val_q == '0) begin
          if (~s_bit_oneshot) s_tim_val_d = s_tim_rld_q;
          s_irq_d = s_bit_irq_en;
        end else begin
          s_tim_val_d = s_tim_val_q - 1'b1;
          s_irq_d     = '0;
        end
      end
    end
  end
  dffr #(32) u_tim_val_dffr (
      clk_i,
      rst_n_i,
      s_tim_val_d,
      s_tim_val_q
  );

  dffr #(1) u_irq_dffr (
      clk_i,
      rst_n_i,
      s_irq_d,
      s_irq_q
  );


  assign s_rib_ready_d = rib.valid && (~s_rib_ready_q);
  dffr #(1) u_rib_ready_dffr (
      clk_i,
      rst_n_i,
      s_rib_ready_d,
      s_rib_ready_q
  );

  assign s_rib_rdata_en = s_rib_rd_hdshk;
  always_comb begin
    s_rib_rdata_d = s_rib_rdata_q;
    unique case (rib.addr[7:0])
      `RIB_TIMER_CFG: s_rib_rdata_d = {28'd0, s_tim_cfg_q};
      `RIB_TIMER_RLD: s_rib_rdata_d = s_tim_rld_q;
      `RIB_TIMER_VAL: s_rib_rdata_d = s_tim_val_q;
      default:        s_rib_rdata_d = s_rib_rdata_q;
    endcase
  end
  dffer #(32) u_rib_rdata_dffer (
      clk_i,
      rst_n_i,
      s_rib_rdata_en,
      s_rib_rdata_d,
      s_rib_rdata_q
  );

endmodule
