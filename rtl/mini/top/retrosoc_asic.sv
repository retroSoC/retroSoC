// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "gpio_define.svh"
`include "soc_clock_config.svh"
`include "user_extensions.svh"

module retrosoc_asic (
    `include "retrosoc_asic_ports.svh"
);
  logic s_ext_clk;
  logic s_aud_clk;
  logic s_sys_clkdiv4;
  logic s_timebase_tick;
`ifdef HAVE_PLL
  logic s_xtal_io;
`endif
  logic       s_sys_clk;
  logic       s_ext_rst_n;
  logic       s_sys_rst_n;
  logic       s_aud_rst_n;
  logic       s_wdg_reset_req;
  logic       s_jtag_tck;
  logic       s_jtag_tms;
  logic       s_jtag_tdi;
  logic       s_jtag_trst_n;
  logic       s_jtag_tdo;
  (* keep = "true" *)logic       s_test_done;
  (* keep = "true" *)logic       s_test_pass;
  (* keep = "true" *)logic [7:0] s_test_code;

`ifdef HAVE_SRAM_IF
  ram_if u_ram_if ();
`endif

  gpio_if u_gpio_if ();
  uart_if u_uart0_if ();
  xpi_if u_xpi_if ();
  sdram_if u_sdram_if ();
  pll_ctrl_if u_pll_ctrl_if ();

  `include "retrosoc_asic_pad_bindings.svh"

rcu #(
      .EXT_CLK_HZ       (`SOC_EXT_CLK_HZ),
      .CLINT_TIMEBASE_HZ(`SOC_CLINT_TIMEBASE_HZ)
  ) u_rcu (
      .ext_clk_i      (s_ext_clk),
      .aud_clk_i      (s_aud_clk),
      .ext_rst_n_i    (s_ext_rst_n),
      .wdg_reset_req_i(s_wdg_reset_req),
`ifdef HAVE_PLL
      .xtal_clk_i     (s_xtal_io),
`endif
      .pll_ctrl       (u_pll_ctrl_if),
      .sys_clk_o      (s_sys_clk),
      .sys_rst_n_o    (s_sys_rst_n),
      .aud_rst_n_o    (s_aud_rst_n),
      .sys_clkdiv4_o  (s_sys_clkdiv4),
      .timebase_tick_o(s_timebase_tick)
  );

`ifdef HAVE_SRAM_IF
  onchip_ram u_onchip_ram (
      .clk_i(s_sys_clk),
      .ram  (u_ram_if)
  );
`endif

  retrosoc u_retrosoc (
      .clk_i          (s_sys_clk),
      .rst_n_i        (s_sys_rst_n),
      .clk_aud_i      (s_aud_clk),
      .rst_aud_n_i    (s_aud_rst_n),
      .clkdiv4_i      (s_sys_clkdiv4),
      .timebase_tick_i(s_timebase_tick),
      .pll_ctrl       (u_pll_ctrl_if),
`ifdef HAVE_SRAM_IF
      .ram            (u_ram_if),
`endif
      .gpio           (u_gpio_if),
      .uart0          (u_uart0_if),
      .xpi            (u_xpi_if),
      .sdram          (u_sdram_if),
      .jtag_tck_i     (s_jtag_tck),
      .jtag_tms_i     (s_jtag_tms),
      .jtag_tdi_i     (s_jtag_tdi),
      .jtag_trst_n_i  (s_jtag_trst_n),
      .jtag_tdo_o     (s_jtag_tdo),
      .wdg_reset_req_o(s_wdg_reset_req),
      .test_done_o    (s_test_done),
      .test_pass_o    (s_test_pass),
      .test_code_o    (s_test_code)
  );

endmodule
