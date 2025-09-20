/*
 *  retroSoC - A simple example SoC using PicoRV32
 *
 *  Copyright (C) 2017  Clifford Wolf <clifford@clifford.at>
 *  Copyright (C) 2018,2019  Tim Edwards <tim@efabless.com>
 *  Copyright (C) 2025  Yuchi Miao <miaoyuchi@ict.ac.cn>

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

`include "mmap_define.svh"

module retrosoc (
    // verilog_format: off
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       clk_aud_i,
    input  logic       rst_aud_n_i,
    input  logic       spfs_div4_i,
    input  logic       irq_pin_i,
`ifdef CORE_MDD
    input  logic [4:0] core_mdd_sel_i,
`endif
`ifdef IP_MDD
    user_gpio_if.dut    gpio,
`endif
`ifdef HAVE_SRAM_IF
    ram_if.master       ram,
`endif
    simp_gpio_if.dut   gpio,
    uart_if.dut        uart0,
    qspi_if.dut        psram,
    spi_if.dut         spisd,
    nv_i2s_if.dut      i2s,
    onewire_if.dut     onewire,
    uart_if.dut        uart1,
    pwm_if.dut         pwm,
    ps2_if.dut         ps2,
    i2c_if.dut         i2c,
    qspi_if.dut        qspi,
    spi_if.dut         spfs
    // verilog_format: on
);

  // verilog_format: off
  nmi_if u_core_nmi_if ();
  nmi_if u_natv_nmi_if();
  nmi_if u_apb_nmi_if();
  i2c_if u_natv_i2c_if();
  i2c_if u_apb_i2c_if();
  // verilog_format: on

  // tmp: i2c sel
  logic s_i2c_sel_d, s_i2c_sel_q;
  // irq
  logic [31:0] s_irq;
  logic [ 2:0] s_natv_irq;
  logic [ 5:0] s_apb_irq;

  assign u_apb_i2c_if.scl_i  = i2c.scl_i;
  assign u_natv_i2c_if.sda_i = i2c.sda_i;
  assign u_apb_i2c_if.sda_i  = i2c.sda_i;
  assign i2c.scl_o           = s_i2c_sel_q ? u_natv_i2c_if.scl_o : u_apb_i2c_if.scl_o;
  assign i2c.scl_dir_o       = s_i2c_sel_q ? u_natv_i2c_if.scl_dir_o : ~u_apb_i2c_if.scl_dir_o;
  assign i2c.sda_o           = s_i2c_sel_q ? u_natv_i2c_if.sda_o : u_apb_i2c_if.sda_o;
  assign i2c.sda_dir_o       = s_i2c_sel_q ? u_natv_i2c_if.sda_dir_o : ~u_apb_i2c_if.sda_dir_o;

  assign s_irq[4:0]          = 5'd0;
  assign s_irq[5]            = irq_pin_i;
  assign s_irq[8:6]          = s_natv_irq;
  assign s_irq[14:9]         = s_apb_irq;
  assign s_irq[31:15]        = 17'd0;


  assign s_i2c_sel_d         = 1'b1;
  dffr #(1) u_i2c_sel_dffr (
      clk_i,
      rst_n_i,
      s_i2c_sel_d,
      s_i2c_sel_q
  );


  core_wrapper u_core_wrapper (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
`ifdef CORE_MDD
      .core_mdd_sel_i(core_mdd_sel_i),
`endif
      .nmi           (u_core_nmi_if),
      .irq_i         (s_irq)
  );

  bus u_bus (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
`ifdef HAVE_SRAM_IF
      .ram     (ram),
`endif
      .core_nmi(u_core_nmi_if),
      .natv_nmi(u_natv_nmi_if),
      .apb_nmi (u_apb_nmi_if)
  );

  ip_natv_wrapper u_ip_natv_wrapper (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .clk_aud_i  (clk_aud_i),
      .rst_aud_n_i(rst_aud_n_i),
      .nmi        (u_natv_nmi_if),
      .gpio       (gpio),
      .uart       (uart0),
      .psram      (psram),
      .spisd      (spisd),
      .i2c        (u_natv_i2c_if),
      .i2s        (i2s),
      .onewire    (onewire),
      .irq_o      (s_natv_irq)
  );

  ip_apb_wrapper u_ip_apb_wrapper (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .spfs_div4_i(spfs_div4_i),
      .nmi        (u_apb_nmi_if),
      .uart       (uart1),
      .pwm        (pwm),
      .ps2        (ps2),
      .i2c        (u_apb_i2c_if),
      .qspi       (qspi),
      .spfs       (spfs),
`ifdef IP_MDD
      .gpio       (gpio),
`endif
      .irq_o      (s_apb_irq)
  );

endmodule
