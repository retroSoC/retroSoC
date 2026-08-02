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

interface gpio_if #(
    parameter int DATA_WIDTH = `RIB_GPIO_NUM
) ();
  logic [DATA_WIDTH-1:0] oe_o;
  logic [DATA_WIDTH-1:0] cs_o;
  logic [DATA_WIDTH-1:0] pu_o;
  logic [DATA_WIDTH-1:0] pd_o;
  logic [DATA_WIDTH-1:0] do_o;
  logic [DATA_WIDTH-1:0] di_i;
  logic [DATA_WIDTH-1:0] alt0_do_i;
  logic [DATA_WIDTH-1:0] alt0_oe_i;
  logic [DATA_WIDTH-1:0] alt1_do_i;
  logic [DATA_WIDTH-1:0] alt1_oe_i;
  logic                  irq_o;

  modport dut(
      output oe_o,
      output cs_o,
      output pu_o,
      output pd_o,
      output do_o,
      input di_i,
      input alt0_do_i,
      input alt0_oe_i,
      input alt1_do_i,
      input alt1_oe_i,
      output irq_o
  );

  modport pad(input oe_o, input cs_o, input pu_o, input pd_o, input do_o, output di_i);

  modport soc_pad(output oe_o, output cs_o, output pu_o, output pd_o, output do_o, input di_i);
endinterface

interface user_gpio_if #(
    parameter int DATA_WIDTH = `RIB_GPIO_NUM
) ();
  logic [DATA_WIDTH-1:0] do_o;
  logic [DATA_WIDTH-1:0] oe_o;
  logic [DATA_WIDTH-1:0] di_i;

  modport user_ip(output do_o, output oe_o, input di_i);
  modport padctrl(input do_o, input oe_o, output di_i);
endinterface

module rib_gpio (
    // verilog_format: off
    input logic     clk_i,
    input logic     rst_n_i,
    rib_if.slave    rib,
    gpio_if.dut     gpio,
    user_gpio_if.padctrl user_gpio
    // verilog_format: on
);

  // rib
  logic s_rib_wr_hdshk, s_rib_rd_hdshk;
  logic s_rib_ready_d, s_rib_ready_q;
  logic s_rib_rdata_en;
  logic [31:0] s_rib_rdata_d, s_rib_rdata_q;
  // reg
  logic s_gpio_oe_en;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_oe_d, s_gpio_oe_q;
  logic s_gpio_cs_en;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_cs_d, s_gpio_cs_q;
  logic s_gpio_pu_en;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_pu_d, s_gpio_pu_q;
  logic s_gpio_pd_en;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_pd_d, s_gpio_pd_q;
  logic s_gpio_do_en;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_do_d, s_gpio_do_q;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_di;
  logic                     s_gpio_ien_en;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_ien_d, s_gpio_ien_q;
  logic s_gpio_itype0_en;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_itype0_d, s_gpio_itype0_q;
  logic s_gpio_itype1_en;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_itype1_d, s_gpio_itype1_q;
  logic s_gpio_istat_en;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_istat_d, s_gpio_istat_q;
  logic s_gpio_iofcfg_en;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_iofcfg_d, s_gpio_iofcfg_q;
  logic s_gpio_pinmux_en;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_pinmux_d, s_gpio_pinmux_q;
  logic s_gpio_user_sel_en;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_user_sel_d, s_gpio_user_sel_q;
  logic s_gpio_user_lock_en;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_user_lock_d, s_gpio_user_lock_q;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_user_handoff_d, s_gpio_user_handoff_q;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_user_status;
  // irq
  logic [`RIB_GPIO_NUM-1:0] s_gpio_di_re, s_gpio_di_fe, s_gpio_irq;
  logic [`RIB_GPIO_NUM-1:0] s_irq_rise, s_irq_fall;
  logic [`RIB_GPIO_NUM-1:0] s_irq_lev0, s_irq_lev1;
  logic [`RIB_GPIO_NUM-1:0] s_irq_masked;
  logic s_irq_trg, s_irq_stat;
  // alt
  logic [`RIB_GPIO_NUM-1:0] s_gpio_alt_out, s_gpio_alt_oe;
  logic [`RIB_GPIO_NUM-1:0] s_gpio_native_out, s_gpio_native_oe;

  // shake
  assign s_rib_wr_hdshk = rib.valid && (~s_rib_ready_q) && (|rib.wstrb);
  assign s_rib_rd_hdshk = rib.valid && (~s_rib_ready_q) && (~(|rib.wstrb));
  assign rib.ready      = s_rib_ready_q;
  assign rib.rdata      = s_rib_rdata_q;
  // gpio
  assign gpio.cs_o      = s_gpio_cs_q;  // 1: CMOS 0: SCHMI
  assign gpio.pu_o      = s_gpio_pu_q;
  assign gpio.pd_o      = s_gpio_pd_q;
  for (genvar i = 0; i < `RIB_GPIO_NUM; i++) begin : ALT_PINMUX_BLOCK
    assign s_gpio_alt_oe[i]  = s_gpio_pinmux_q[i] ? gpio.alt1_oe_i[i] : gpio.alt0_oe_i[i];
    assign s_gpio_alt_out[i] = s_gpio_pinmux_q[i] ? gpio.alt1_do_i[i] : gpio.alt0_do_i[i];
  end
  for (genvar i = 0; i < `RIB_GPIO_NUM; i++) begin : IOF_PINMUX_BLOCK
    assign s_gpio_native_oe[i]  = s_gpio_iofcfg_q[i] ? s_gpio_alt_oe[i] : s_gpio_oe_q[i];
    assign s_gpio_native_out[i] = s_gpio_iofcfg_q[i] ? s_gpio_alt_out[i] : s_gpio_do_q[i];
  end
  assign user_gpio.di_i = gpio.di_i;
  for (genvar i = 0; i < `RIB_GPIO_NUM; i++) begin : USER_GPIO_MUX_BLOCK
    assign gpio.oe_o[i] = s_gpio_user_handoff_q[i]
                         ? 1'b0
                         : (s_gpio_user_sel_q[i] ? user_gpio.oe_o[i] : s_gpio_native_oe[i]);
    assign gpio.do_o[i] = s_gpio_user_sel_q[i] ? user_gpio.do_o[i] : s_gpio_native_out[i];
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
      .DATA_WIDTH(`RIB_GPIO_NUM)
  ) u_gpio_di_edge_det (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (gpio.di_i),
      .dat_o  (s_gpio_di),
      .re_o   (s_gpio_di_re),
      .fe_o   (s_gpio_di_fe)
  );

  // register
  assign s_gpio_oe_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_GPIO_OE;
  assign s_gpio_oe_d  = rib.wdata[`RIB_GPIO_NUM-1:0];
  dffer #(`RIB_GPIO_NUM) u_gpio_oe_dffer (
      clk_i,
      rst_n_i,
      s_gpio_oe_en,
      s_gpio_oe_d,
      s_gpio_oe_q
  );


  assign s_gpio_cs_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_GPIO_CS;
  assign s_gpio_cs_d  = rib.wdata[`RIB_GPIO_NUM-1:0];
  dffer #(`RIB_GPIO_NUM) u_gpio_cs_dffer (
      clk_i,
      rst_n_i,
      s_gpio_cs_en,
      s_gpio_cs_d,
      s_gpio_cs_q
  );


  assign s_gpio_pu_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_GPIO_PU;
  assign s_gpio_pu_d  = rib.wdata[`RIB_GPIO_NUM-1:0];
  dffer #(`RIB_GPIO_NUM) u_gpio_pu_dffer (
      clk_i,
      rst_n_i,
      s_gpio_pu_en,
      s_gpio_pu_d,
      s_gpio_pu_q
  );


  assign s_gpio_pd_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_GPIO_PD;
  assign s_gpio_pd_d  = rib.wdata[`RIB_GPIO_NUM-1:0];
  dffer #(`RIB_GPIO_NUM) u_gpio_pd_dffer (
      clk_i,
      rst_n_i,
      s_gpio_pd_en,
      s_gpio_pd_d,
      s_gpio_pd_q
  );


  assign s_gpio_do_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_GPIO_DO;
  assign s_gpio_do_d  = rib.wdata[`RIB_GPIO_NUM-1:0];
  dffer #(`RIB_GPIO_NUM) u_gpio_do_dffer (
      clk_i,
      rst_n_i,
      s_gpio_do_en,
      s_gpio_do_d,
      s_gpio_do_q
  );


  assign s_gpio_ien_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_GPIO_IEN;
  assign s_gpio_ien_d  = rib.wdata[`RIB_GPIO_NUM-1:0];
  dffer #(`RIB_GPIO_NUM) u_gpio_ien_dffer (
      clk_i,
      rst_n_i,
      s_gpio_ien_en,
      s_gpio_ien_d,
      s_gpio_ien_q
  );


  assign s_gpio_itype0_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_GPIO_ITYPE0;
  assign s_gpio_itype0_d  = rib.wdata[`RIB_GPIO_NUM-1:0];
  dffer #(`RIB_GPIO_NUM) u_gpio_itype0_dffer (
      clk_i,
      rst_n_i,
      s_gpio_itype0_en,
      s_gpio_itype0_d,
      s_gpio_itype0_q
  );


  assign s_gpio_itype1_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_GPIO_ITYPE1;
  assign s_gpio_itype1_d  = rib.wdata[`RIB_GPIO_NUM-1:0];
  dffer #(`RIB_GPIO_NUM) u_gpio_itype1_dffer (
      clk_i,
      rst_n_i,
      s_gpio_itype1_en,
      s_gpio_itype1_d,
      s_gpio_itype1_q
  );


  assign s_gpio_iofcfg_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_GPIO_IOFCFG;
  assign s_gpio_iofcfg_d  = rib.wdata[`RIB_GPIO_NUM-1:0];
  dffer #(`RIB_GPIO_NUM) u_gpio_iocfg_dffer (
      clk_i,
      rst_n_i,
      s_gpio_iofcfg_en,
      s_gpio_iofcfg_d,
      s_gpio_iofcfg_q
  );


  always_comb begin
    s_gpio_istat_en = 1'b0;
    s_gpio_istat_d  = s_gpio_istat_q;
    if (s_irq_stat && s_rib_rd_hdshk && rib.addr[7:0] == `RIB_GPIO_ISTAT) begin
      s_gpio_istat_en = 1'b1;
      // HACK: clear all irq
      s_gpio_istat_d  = '0;
    end else if (~s_irq_stat && s_irq_trg) begin
      s_gpio_istat_en = 1'b1;
      s_gpio_istat_d  = s_irq_masked;
    end
  end
  dffer #(`RIB_GPIO_NUM) u_gpio_istat_dffer (
      clk_i,
      rst_n_i,
      s_gpio_istat_en,
      s_gpio_istat_d,
      s_gpio_istat_q
  );


  assign s_gpio_pinmux_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_GPIO_PINMUX;
  assign s_gpio_pinmux_d  = rib.wdata[`RIB_GPIO_NUM-1:0];
  dffer #(`RIB_GPIO_NUM) u_gpio_pinmux_dffer (
      clk_i,
      rst_n_i,
      s_gpio_pinmux_en,
      s_gpio_pinmux_d,
      s_gpio_pinmux_q
  );

  assign s_gpio_user_sel_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_GPIO_USER_SEL;
  assign s_gpio_user_sel_d  = (s_gpio_user_sel_q & s_gpio_user_lock_q) |
                             (rib.wdata[`RIB_GPIO_NUM-1:0] & ~s_gpio_user_lock_q);
  dffer #(`RIB_GPIO_NUM) u_gpio_user_sel_dffer (
      clk_i,
      rst_n_i,
      s_gpio_user_sel_en,
      s_gpio_user_sel_d,
      s_gpio_user_sel_q
  );

  assign s_gpio_user_lock_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_GPIO_USER_LOCK;
  assign s_gpio_user_lock_d  = s_gpio_user_lock_q | rib.wdata[`RIB_GPIO_NUM-1:0];
  dffer #(`RIB_GPIO_NUM) u_gpio_user_lock_dffer (
      clk_i,
      rst_n_i,
      s_gpio_user_lock_en,
      s_gpio_user_lock_d,
      s_gpio_user_lock_q
  );

  assign s_gpio_user_handoff_d = s_gpio_user_sel_en ? (s_gpio_user_sel_d ^ s_gpio_user_sel_q) : '0;
  dffr #(`RIB_GPIO_NUM) u_gpio_user_handoff_dffr (
      clk_i,
      rst_n_i,
      s_gpio_user_handoff_d,
      s_gpio_user_handoff_q
  );
  assign s_gpio_user_status = s_gpio_user_sel_q & ~s_gpio_user_handoff_q;


  // rib resp
  assign s_rib_ready_d      = rib.valid && (~s_rib_ready_q);
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
      `RIB_GPIO_OE:          s_rib_rdata_d = {{(32 - `RIB_GPIO_NUM) {1'b0}}, s_gpio_oe_q};
      `RIB_GPIO_CS:          s_rib_rdata_d = {{(32 - `RIB_GPIO_NUM) {1'b0}}, s_gpio_cs_q};
      `RIB_GPIO_PU:          s_rib_rdata_d = {{(32 - `RIB_GPIO_NUM) {1'b0}}, s_gpio_pu_q};
      `RIB_GPIO_PD:          s_rib_rdata_d = {{(32 - `RIB_GPIO_NUM) {1'b0}}, s_gpio_pd_q};
      `RIB_GPIO_DO:          s_rib_rdata_d = {{(32 - `RIB_GPIO_NUM) {1'b0}}, s_gpio_do_q};
      `RIB_GPIO_DI:          s_rib_rdata_d = {{(32 - `RIB_GPIO_NUM) {1'b0}}, s_gpio_di};
      `RIB_GPIO_IEN:         s_rib_rdata_d = {{(32 - `RIB_GPIO_NUM) {1'b0}}, s_gpio_ien_q};
      `RIB_GPIO_ITYPE0:      s_rib_rdata_d = {{(32 - `RIB_GPIO_NUM) {1'b0}}, s_gpio_itype0_q};
      `RIB_GPIO_ITYPE1:      s_rib_rdata_d = {{(32 - `RIB_GPIO_NUM) {1'b0}}, s_gpio_itype1_q};
      `RIB_GPIO_ISTAT:       s_rib_rdata_d = {{(32 - `RIB_GPIO_NUM) {1'b0}}, s_gpio_istat_q};
      `RIB_GPIO_IOFCFG:      s_rib_rdata_d = {{(32 - `RIB_GPIO_NUM) {1'b0}}, s_gpio_iofcfg_q};
      `RIB_GPIO_PINMUX:      s_rib_rdata_d = {{(32 - `RIB_GPIO_NUM) {1'b0}}, s_gpio_pinmux_q};
      `RIB_GPIO_USER_SEL:    s_rib_rdata_d = {{(32 - `RIB_GPIO_NUM) {1'b0}}, s_gpio_user_sel_q};
      `RIB_GPIO_USER_LOCK:   s_rib_rdata_d = {{(32 - `RIB_GPIO_NUM) {1'b0}}, s_gpio_user_lock_q};
      `RIB_GPIO_USER_STATUS: s_rib_rdata_d = {{(32 - `RIB_GPIO_NUM) {1'b0}}, s_gpio_user_status};
      default:               s_rib_rdata_d = s_rib_rdata_q;
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
