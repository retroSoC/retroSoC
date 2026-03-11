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
// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "gpio_define.svh"

interface nmi_gpio_if ();
  logic [`NMI_GPIO_NUM-1:0] gpio_oe_o;
  logic [`NMI_GPIO_NUM-1:0] gpio_cs_o;
  logic [`NMI_GPIO_NUM-1:0] gpio_pu_o;
  logic [`NMI_GPIO_NUM-1:0] gpio_pd_o;
  logic [`NMI_GPIO_NUM-1:0] gpio_do_o;
  logic [`NMI_GPIO_NUM-1:0] gpio_di_i;
  logic [`NMI_GPIO_NUM-1:0] gpio_alt_in_o;
  logic [`NMI_GPIO_NUM-1:0] gpio_alt0_out_i;
  logic [`NMI_GPIO_NUM-1:0] gpio_alt0_oe_i;
  logic [`NMI_GPIO_NUM-1:0] gpio_alt1_out_i;
  logic [`NMI_GPIO_NUM-1:0] gpio_alt1_oe_i;
  logic                     irq_o;

  modport dut(
      output gpio_oe_o,
      output gpio_cs_o,
      output gpio_pu_o,
      output gpio_pd_o,
      output gpio_do_o,
      input gpio_di_i,
      output gpio_alt_in_o,
      input gpio_alt0_out_i,
      input gpio_alt0_oe_i,
      input gpio_alt1_out_i,
      input gpio_alt1_oe_i,
      output irq_o
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
  // reg
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
  logic [`NMI_GPIO_NUM-1:0] s_gpio_di;
  logic                     s_gpio_ien_en;
  logic [`NMI_GPIO_NUM-1:0] s_gpio_ien_d, s_gpio_ien_q;
  logic s_gpio_itype0_en;
  logic [`NMI_GPIO_NUM-1:0] s_gpio_itype0_d, s_gpio_itype0_q;
  logic s_gpio_itype1_en;
  logic [`NMI_GPIO_NUM-1:0] s_gpio_itype1_d, s_gpio_itype1_q;
  logic s_gpio_istat_en;
  logic [`NMI_GPIO_NUM-1:0] s_gpio_istat_d, s_gpio_istat_q;
  logic s_gpio_iofcfg_en;
  logic [`NMI_GPIO_NUM-1:0] s_gpio_iofcfg_d, s_gpio_iofcfg_q;
  logic s_gpio_pinmux_en;
  logic [`NMI_GPIO_NUM-1:0] s_gpio_pinmux_d, s_gpio_pinmux_q;
  // irq
  logic [`NMI_GPIO_NUM-1:0] s_gpio_di_re, s_gpio_di_fe, s_gpio_irq;
  logic [`NMI_GPIO_NUM-1:0] s_irq_rise, s_irq_fall;
  logic [`NMI_GPIO_NUM-1:0] s_irq_lev0, s_irq_lev1;
  logic [`NMI_GPIO_NUM-1:0] s_irq_masked;
  logic s_irq_trg, s_irq_stat;
  // alt
  logic [`NMI_GPIO_NUM-1:0] s_gpio_alt_out, s_gpio_alt_oe;

  // shake
  assign s_nmi_wr_hdshk = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready      = s_nmi_ready_q;
  assign nmi.rdata      = s_nmi_rdata_q;
  // gpio
  assign gpio.gpio_cs_o = s_gpio_cs_q;  // 1: CMOS 0: SCHMI
  assign gpio.gpio_pu_o = s_gpio_pu_q;
  assign gpio.gpio_pd_o = s_gpio_pd_q;
  for (genvar i = 0; i < `NMI_GPIO_NUM; i++) begin : ALT_PINMUX_BLOCK
    assign s_gpio_alt_oe[i] = s_gpio_pinmux_q[i] ? gpio.gpio_alt1_oe_i[i] : gpio.gpio_alt0_oe_i[i];
    assign s_gpio_alt_out[i] = s_gpio_pinmux_q[i] ? gpio.gpio_alt1_out_i[i] : gpio.gpio_alt0_out_i[i];
  end
  for (genvar i = 0; i < `NMI_GPIO_NUM; i++) begin : IOF_PINMUX_BLOCK
    assign gpio.gpio_oe_o[i]     = s_gpio_iofcfg_q[i] ? s_gpio_alt_oe[i] : s_gpio_oe_q[i];
    assign gpio.gpio_do_o[i]     = s_gpio_iofcfg_q[i] ? s_gpio_alt_out[i] : s_gpio_do_q[i];
    assign gpio.gpio_alt_in_o[i] = s_gpio_iofcfg_q[i] ? gpio.gpio_di_i[i] : '0;
  end
  assign s_irq_stat = |s_gpio_istat_q;
  assign gpio.irq_o = s_irq_stat;

  // verilog_format: off
  // irq
  assign s_irq_rise     = (~s_gpio_itype1_q & ~s_gpio_itype0_q) & s_gpio_di_re;
  assign s_irq_fall     = (~s_gpio_itype1_q & s_gpio_itype0_q)  & s_gpio_di_fe;
  assign s_irq_lev0     = (s_gpio_itype1_q  & ~s_gpio_itype0_q) & ~s_gpio_di;
  assign s_irq_lev1     = (s_gpio_itype1_q  & s_gpio_itype0_q)  & s_gpio_di;
  assign s_gpio_irq     = s_irq_rise | s_irq_fall | s_irq_lev0 | s_irq_lev1;
  assign s_irq_masked   = s_gpio_ien_q & s_gpio_irq;
  assign s_irq_trg      = |s_irq_masked;
  // verilog_format: on

  edge_det #(
      .STAGE     (2),
      .DATA_WIDTH(`NMI_GPIO_NUM)
  ) u_gpio_di_edge_det (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (gpio.gpio_di_i),
      .dat_o  (s_gpio_di),
      .re_o   (s_gpio_di_re),
      .fe_o   (s_gpio_di_fe)
  );

  // register
  assign s_gpio_oe_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_GPIO_OE;
  assign s_gpio_oe_d  = nmi.wdata[`NMI_GPIO_NUM-1:0];
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


  assign s_gpio_ien_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_GPIO_IEN;
  assign s_gpio_ien_d  = nmi.wdata[`NMI_GPIO_NUM-1:0];
  dffer #(`NMI_GPIO_NUM) u_gpio_ien_dffer (
      clk_i,
      rst_n_i,
      s_gpio_ien_en,
      s_gpio_ien_d,
      s_gpio_ien_q
  );


  assign s_gpio_itype0_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_GPIO_ITYPE0;
  assign s_gpio_itype0_d  = nmi.wdata[`NMI_GPIO_NUM-1:0];
  dffer #(`NMI_GPIO_NUM) u_gpio_itype0_dffer (
      clk_i,
      rst_n_i,
      s_gpio_itype0_en,
      s_gpio_itype0_d,
      s_gpio_itype0_q
  );


  assign s_gpio_itype1_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_GPIO_ITYPE1;
  assign s_gpio_itype1_d  = nmi.wdata[`NMI_GPIO_NUM-1:0];
  dffer #(`NMI_GPIO_NUM) u_gpio_itype1_dffer (
      clk_i,
      rst_n_i,
      s_gpio_itype1_en,
      s_gpio_itype1_d,
      s_gpio_itype1_q
  );


  assign s_gpio_iofcfg_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_GPIO_IOFCFG;
  assign s_gpio_iofcfg_d  = nmi.wdata[`NMI_GPIO_NUM-1:0];
  dffer #(`NMI_GPIO_NUM) u_gpio_iocfg_dffer (
      clk_i,
      rst_n_i,
      s_gpio_iofcfg_en,
      s_gpio_iofcfg_d,
      s_gpio_iofcfg_q
  );


  always_comb begin
    s_gpio_istat_en = 1'b0;
    s_gpio_istat_d  = s_gpio_istat_q;
    if (s_irq_stat && s_nmi_rd_hdshk && nmi.addr[7:0] == `NMI_GPIO_ISTAT) begin
      s_gpio_istat_en = 1'b1;
      // HACK: clear all irq
      s_gpio_istat_d  = '0;
    end else if (~s_irq_stat && s_irq_trg) begin
      s_gpio_istat_en = 1'b1;
      s_gpio_istat_d  = s_irq_masked;
    end
  end
  dffer #(`NMI_GPIO_NUM) u_gpio_istat_dffer (
      clk_i,
      rst_n_i,
      s_gpio_istat_en,
      s_gpio_istat_d,
      s_gpio_istat_q
  );


  assign s_gpio_pinmux_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NMI_GPIO_PINMUX;
  assign s_gpio_pinmux_d  = nmi.wdata[`NMI_GPIO_NUM-1:0];
  dffer #(`NMI_GPIO_NUM) u_gpio_pinmux_dffer (
      clk_i,
      rst_n_i,
      s_gpio_pinmux_en,
      s_gpio_pinmux_d,
      s_gpio_pinmux_q
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
      `NMI_GPIO_OE:     s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_oe_q};
      `NMI_GPIO_CS:     s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_cs_q};
      `NMI_GPIO_PU:     s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_pu_q};
      `NMI_GPIO_PD:     s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_pd_q};
      `NMI_GPIO_DO:     s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_do_q};
      `NMI_GPIO_DI:     s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_di};
      `NMI_GPIO_IEN:    s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_ien_q};
      `NMI_GPIO_ITYPE0: s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_itype0_q};
      `NMI_GPIO_ITYPE1: s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_itype1_q};
      `NMI_GPIO_ISTAT:  s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_istat_q};
      `NMI_GPIO_IOFCFG: s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_iofcfg_q};
      `NMI_GPIO_PINMUX: s_nmi_rdata_d = {{(32 - `NMI_GPIO_NUM) {1'b0}}, s_gpio_pinmux_q};
      default:          s_nmi_rdata_d = s_nmi_rdata_q;
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
