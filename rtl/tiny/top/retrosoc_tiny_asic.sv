// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
module retrosoc_tiny_asic (
    `include "retrosoc_asic_ports.svh"
);
  logic s_ext_clk, s_clk, s_ext_rst_n;
  logic s_jtag_tck, s_jtag_tms, s_jtag_tdi, s_jtag_trst_n, s_jtag_tdo;
  logic s_uart0_rx, s_uart0_tx, s_uart1_rx, s_uart1_tx;
  // Stable simulator/netlist observation points; no package test pins.
  /* verilator lint_off UNUSEDSIGNAL */
  (* keep = "true" *)logic       s_test_done;
  (* keep = "true" *)logic       s_test_pass;
  (* keep = "true" *)logic [7:0] s_test_code;
  /* verilator lint_on UNUSEDSIGNAL */
  gpio_if u_gpio_if ();
  xpi_if u_xpi_if ();
  `include "retrosoc_asic_pad_bindings.svh"
tc_clk_buf u_clock_buffer (
      .clk_i(s_ext_clk),
      .clk_o(s_clk)
  );
  retrosoc_tiny u_soc (
      .clk_i        (s_clk),
      .rst_n_i      (s_ext_rst_n),
      .jtag_tck_i   (s_jtag_tck),
      .jtag_tms_i   (s_jtag_tms),
      .jtag_tdi_i   (s_jtag_tdi),
      .jtag_trst_n_i(s_jtag_trst_n),
      .jtag_tdo_o   (s_jtag_tdo),
      .uart0_rx_i   (s_uart0_rx),
      .uart0_tx_o   (s_uart0_tx),
      .uart1_rx_i   (s_uart1_rx),
      .uart1_tx_o   (s_uart1_tx),
      .gpio         (u_gpio_if),
      .xpi          (u_xpi_if),
      .test_done_o  (s_test_done),
      .test_pass_o  (s_test_pass),
      .test_code_o  (s_test_code)
  );
endmodule
