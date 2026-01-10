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

`ifndef NMI_GPIO_DEF_SV
`define NMI_GPIO_DEF_SV

// verilog_format: off
`define NMI_GPIO_NUM 8
`define NMI_GPIO_OE  8'h00 // rw
`define NMI_GPIO_CS  8'h04 // rw
`define NMI_GPIO_PU  8'h08 // rw
`define NMI_GPIO_PD  8'h0C // rw
`define NMI_GPIO_DO  8'h10 // rw
`define NMI_GPIO_DI  8'h14 // ro
// verilog_format: on
`endif

interface nmi_gpio_if #(
    parameter int DATA_WIDTH = 32
) ();
  logic [DATA_WIDTH-1:0] gpio_in;
  logic [DATA_WIDTH-1:0] gpio_out;
  logic [DATA_WIDTH-1:0] gpio_oe;
  logic [DATA_WIDTH-1:0] gpio_cs;
  logic [DATA_WIDTH-1:0] gpio_pu;
  logic [DATA_WIDTH-1:0] gpio_pd;

  modport dut(
      input gpio_in,
      output gpio_oe,
      output gpio_cs,
      output gpio_pu,
      output gpio_pd,
      output gpio_out
  );
endinterface

module nmi_gpio (
    // verilog_format: off
    input logic     clk_i,
    input logic     rst_n_i,
    nmi_if.slave    nmi,
    nmi_gpio_if.dut gpio
    // verilog_format: on
);

  // nmi
  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;
  // register
  logic s_gpio_oe_en;
  logic [`NMI_GPIO_NUM-1:0] s_gpio_oe_d, s_gpio_oe_q;
  logic s_gpio_cs_en;
  logic [`NMI_GPIO_NUM-1:0] s_gpio_cs_d, s_gpio_cs_q;
  logic s_gpio_pu_en;
  logic [`NMI_GPIO_NUM-1:0] s_gpio_pu_d, s_gpio_pu_q;
  logic s_gpio_pd_en;
  logic [`NMI_GPIO_NUM-1:0] s_gpio_pd_d, s_gpio_pd_q;
  logic s_gpio_do_en;
  logic [`NMI_GPIO_NUM-1:0] s_gpio_do_d, s_gpio_do_q;

  // HACK: because just wr/rd 8b GPIO
  assign s_nmi_wr_hdshk = nmi.valid && (~s_nmi_ready_q) && nmi.wstrb[0];
  assign s_nmi_rd_hdshk = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready      = s_nmi_ready_q;
  assign nmi.rdata      = s_nmi_rdata_q;
  // gpio
  assign gpio.gpio_oe   = s_gpio_oe_q;
  assign gpio.gpio_cs   = s_gpio_cs_q;  // 1: CMOS 0: SCHMI
  assign gpio.gpio_pu   = s_gpio_pu_q;
  assign gpio.gpio_pd   = s_gpio_pd_q;
  assign gpio.gpio_out  = s_gpio_do_q;

  // register
  assign s_gpio_oe_en   = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_GPIO_OE;
  assign s_gpio_oe_d    = nmi.wdata[`NMI_GPIO_NUM-1:0];
  dffer #(`NMI_GPIO_NUM) u_gpio_oe_dffer (
      clk_i,
      rst_n_i,
      s_gpio_oe_en,
      s_gpio_oe_d,
      s_gpio_oe_q
  );


  assign s_gpio_cs_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_GPIO_CS;
  assign s_gpio_cs_d  = nmi.wdata[`NMI_GPIO_NUM-1:0];
  dffer #(`NMI_GPIO_NUM) u_gpio_cs_dffer (
      clk_i,
      rst_n_i,
      s_gpio_cs_en,
      s_gpio_cs_d,
      s_gpio_cs_q
  );


  assign s_gpio_pu_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_GPIO_PU;
  assign s_gpio_pu_d  = nmi.wdata[`NMI_GPIO_NUM-1:0];
  dffer #(`NMI_GPIO_NUM) u_gpio_pu_dffer (
      clk_i,
      rst_n_i,
      s_gpio_pu_en,
      s_gpio_pu_d,
      s_gpio_pu_q
  );


  assign s_gpio_pd_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_GPIO_PD;
  assign s_gpio_pd_d  = nmi.wdata[`NMI_GPIO_NUM-1:0];
  dffer #(`NMI_GPIO_NUM) u_gpio_pd_dffer (
      clk_i,
      rst_n_i,
      s_gpio_pd_en,
      s_gpio_pd_d,
      s_gpio_pd_q
  );


  assign s_gpio_do_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_GPIO_DO;
  assign s_gpio_do_d  = nmi.wdata[`NMI_GPIO_NUM-1:0];
  dffer #(`NMI_GPIO_NUM) u_gpio_do_dffer (
      clk_i,
      rst_n_i,
      s_gpio_do_en,
      s_gpio_do_d,
      s_gpio_do_q
  );

  // nmi resp
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
      `NMI_GPIO_OE: s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_oe_q};
      `NMI_GPIO_CS: s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_cs_q};
      `NMI_GPIO_PU: s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_pu_q};
      `NMI_GPIO_PD: s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_pd_q};
      `NMI_GPIO_DO: s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_do_q};
      `NMI_GPIO_DI: s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, gpio.gpio_in};
      default:      s_nmi_rdata_d = s_nmi_rdata_q;
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
