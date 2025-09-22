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
 */
// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef SIMP_GPIO_DEF_SV
`define SIMP_GPIO_DEF_SV

// verilog_format: off
`define SIMP_GPIO_NUM  8
`define SIMP_GPIO_DATA 8'h00
`define SIMP_GPIO_OEN  8'h04
`define SIMP_GPIO_PUN  8'h08
`define SIMP_GPIO_PDN  8'h0C
// verilog_format: on

`endif

interface simp_gpio_if ();
  logic [`SIMP_GPIO_NUM-1:0] gpio_out;
  logic [`SIMP_GPIO_NUM-1:0] gpio_in;
  logic [`SIMP_GPIO_NUM-1:0] gpio_oen;
  logic [`SIMP_GPIO_NUM-1:0] gpio_pun;
  logic [`SIMP_GPIO_NUM-1:0] gpio_pdn;

  modport dut(output gpio_out, input gpio_in, output gpio_oen, output gpio_pun, output gpio_pdn);
endinterface

module simple_gpio (
    // verilog_format: off
    input logic      clk_i,
    input logic      rst_n_i,
    nmi_if.slave     nmi,
    simp_gpio_if.dut gpio
    // verilog_format: on
);

  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;

  logic s_gpio_en;
  logic [`SIMP_GPIO_NUM-1:0] s_gpio_d, s_gpio_q;
  logic s_gpio_oen_en;
  logic [`SIMP_GPIO_NUM-1:0] s_gpio_oen_d, s_gpio_oen_q;
  logic s_gpio_pun_en;
  logic [`SIMP_GPIO_NUM-1:0] s_gpio_pun_d, s_gpio_pun_q;
  logic s_gpio_pdn_en;
  logic [`SIMP_GPIO_NUM-1:0] s_gpio_pdn_d, s_gpio_pdn_q;

  // HACK: because just wr/rd 8b GPIO
  assign s_nmi_wr_hdshk = nmi.valid && (~s_nmi_ready_q) && nmi.wstrb[0];
  assign s_nmi_rd_hdshk = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready      = s_nmi_ready_q;
  assign nmi.rdata      = s_nmi_rdata_q;

  assign gpio.gpio_out  = s_gpio_q;
  assign gpio.gpio_oen  = {(`SIMP_GPIO_NUM) {~rst_n_i}} | s_gpio_oen_q;
  assign gpio.gpio_pun  = s_gpio_pun_q;
  assign gpio.gpio_pdn  = s_gpio_pdn_q;


  assign s_gpio_en      = s_nmi_wr_hdshk && nmi.addr[7:0] == `SIMP_GPIO_DATA;
  assign s_gpio_d       = nmi.wdata[7:0];
  dffer #(`SIMP_GPIO_NUM) u_gpio_dffer (
      clk_i,
      rst_n_i,
      s_gpio_en,
      s_gpio_d,
      s_gpio_q
  );

  assign s_gpio_oen_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `SIMP_GPIO_OEN;
  assign s_gpio_oen_d  = nmi.wdata[7:0];
  dffer #(`SIMP_GPIO_NUM) u_gpio_oen_dffer (
      clk_i,
      rst_n_i,
      s_gpio_oen_en,
      s_gpio_oen_d,
      s_gpio_oen_q
  );

  assign s_gpio_pun_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `SIMP_GPIO_PUN;
  assign s_gpio_pun_d  = nmi.wdata[7:0];
  dffer #(`SIMP_GPIO_NUM) u_gpio_pun_dffer (
      clk_i,
      rst_n_i,
      s_gpio_pun_en,
      s_gpio_pun_d,
      s_gpio_pun_q
  );

  assign s_gpio_pdn_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `SIMP_GPIO_PDN;
  assign s_gpio_pdn_d  = nmi.wdata[7:0];
  dffer #(`SIMP_GPIO_NUM) u_gpio_pdn_dffer (
      clk_i,
      rst_n_i,
      s_gpio_pdn_en,
      s_gpio_pdn_d,
      s_gpio_pdn_q
  );

  assign s_nmi_ready_d = nmi.valid && (~s_nmi_ready_q);
  dffr #(1) u_nmi_ready_dffr (
      clk_i,
      rst_n_i,
      s_nmi_ready_d,
      s_nmi_ready_q
  );

  assign s_nmi_rdata_en = s_nmi_rd_hdshk;
  always_comb begin
    s_nmi_rdata_d = s_nmi_rdata_q;
    unique case (nmi.addr[7:0])
      `SIMP_GPIO_DATA: s_nmi_rdata_d = {16'd0, s_gpio_q, gpio.gpio_in};
      `SIMP_GPIO_OEN:  s_nmi_rdata_d = {24'd0, s_gpio_oen_q};
      `SIMP_GPIO_PUN:  s_nmi_rdata_d = {24'd0, s_gpio_pun_q};
      `SIMP_GPIO_PDN:  s_nmi_rdata_d = {24'd0, s_gpio_pdn_q};
      default:         s_nmi_rdata_d = s_nmi_rdata_q;
    endcase
  end
  dffer #(32) u_nmi_rdata_dffer (
      clk_i,
      rst_n_i,
      s_nmi_rdata_en,
      s_nmi_rdata_d,
      s_nmi_rdata_q
  );

endmodule
