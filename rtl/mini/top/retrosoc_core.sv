// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.

`include "gpio_define.svh"
`include "soc_clock_config.svh"
`include "user_extensions.svh"

// Technology-independent hardening top. The generated bindings retain the
// exact logical pin contract of retrosoc_asic but intentionally omit pad cells.
module retrosoc_core (
    `include "retrosoc_core_ports.svh"
);
  logic       s_ext_clk;
  logic       s_ref24_clk;
  logic       s_aud_clk;
  logic       s_aud_clk_buf;
  logic       s_sys_clkdiv4;
  logic       s_timebase_tick;
  logic       s_aon_clk;
  logic       s_aon_rst_n;
  logic       s_sys_clk;
  logic       s_hp_clk;
  logic       s_hp_rst_n;
  logic       s_pclk;
  logic       s_pclk_rst_n;
  logic       s_mem_clk;
  logic       s_mem_rst_n;
  logic       s_hp_block;
  logic       s_pll_fault;
  logic [1:0] s_mem_pad_mode;
  logic       s_mem_pad_lock;
  logic       s_hp_idle;
  logic       s_pclk_idle;
  logic       s_ext_rst_n;
  logic       s_sys_rst_n;
  logic       s_aud_rst_n;
  logic       s_wdg_reset_req;
  logic       s_jtag_tck;
  logic       s_jtag_tms;
  logic       s_jtag_tdi;
  logic       s_jtag_trst_n;
  logic       s_jtag_tdo;
  logic       s_uart0_rx;
  logic       s_uart0_tx;
  logic       s_uart1_rx;
  logic       s_uart1_tx;
  logic       s_usb2_ulpi_clk;
  (* keep = "true" *)logic       s_test_done;
  (* keep = "true" *)logic       s_test_pass;
  (* keep = "true" *)logic [7:0] s_test_code;

  gpio_if u_gpio_if ();
  xpi_if u_xpi_if ();
  sdram_if u_sdram_if ();
  sdio_if u_sdio1_if ();
  usb2_ulpi_if u_usb2_ulpi_if ();
  pll_ctrl_if u_pll_ctrl_if ();
  clock_ctrl_if u_clock_ctrl_if ();

  `include "retrosoc_core_bindings.svh"

rcu #(
      .RefClkHz       (24_000_000),
      .ClintTimebaseHz(`SOC_CLINT_TIMEBASE_HZ)
  ) u_rcu (
      .ref24_clk_i    (s_ref24_clk),
      .ext_clk_i      (s_ext_clk),
      .aud_clk_i      (s_aud_clk),
      .ext_rst_n_i    (s_ext_rst_n),
      .wdg_reset_req_i(s_wdg_reset_req),
      .hp_idle_i      (s_hp_idle),
      .pclk_idle_i    (s_pclk_idle),
      .pll_ctrl       (u_pll_ctrl_if),
      .clock_ctrl     (u_clock_ctrl_if),
      .aon_clk_o      (s_aon_clk),
      .aon_rst_n_o    (s_aon_rst_n),
      .sys_clk_o      (s_sys_clk),
      .sys_rst_n_o    (s_sys_rst_n),
      .hp_clk_o       (s_hp_clk),
      .hp_rst_n_o     (s_hp_rst_n),
      .pclk_o         (s_pclk),
      .pclk_rst_n_o   (s_pclk_rst_n),
      .mem_clk_o      (s_mem_clk),
      .mem_rst_n_o    (s_mem_rst_n),
      .aud_clk_o      (s_aud_clk_buf),
      .aud_rst_n_o    (s_aud_rst_n),
      .sys_clkdiv4_o  (s_sys_clkdiv4),
      .timebase_tick_o(s_timebase_tick),
      .hp_block_o     (s_hp_block),
      .pll_fault_o    (s_pll_fault),
      .mem_pad_mode_o (s_mem_pad_mode),
      .mem_pad_lock_o (s_mem_pad_lock)
  );

  retrosoc u_retrosoc (
      .clk_lp_i       (s_sys_clk),
      .rst_lp_n_i     (s_sys_rst_n),
      .clk_hp_i       (s_hp_clk),
      .rst_hp_n_i     (s_hp_rst_n),
      .clk_pclk_i     (s_pclk),
      .rst_pclk_n_i   (s_pclk_rst_n),
      .clk_mem_i      (s_mem_clk),
      .rst_mem_n_i    (s_mem_rst_n),
      .mem_pad_mode_i (s_mem_pad_mode),
      .mem_pad_lock_i (s_mem_pad_lock),
      .hp_block_i     (s_hp_block),
      .clk_aud_i      (s_aud_clk_buf),
      .rst_aud_n_i    (s_aud_rst_n),
      .clk_ulpi_i     (s_usb2_ulpi_clk),
      .clkdiv4_i      (s_sys_clkdiv4),
      .timebase_tick_i(s_timebase_tick),
      .pll_ctrl       (u_pll_ctrl_if),
      .clock_ctrl     (u_clock_ctrl_if),
      .gpio           (u_gpio_if),
      .uart_rx_i      (s_uart0_rx),
      .uart_tx_o      (s_uart0_tx),
      .uart1_rx_i     (s_uart1_rx),
      .uart1_tx_o     (s_uart1_tx),
      .xpi            (u_xpi_if),
      .sdram          (u_sdram_if),
      .sdio1          (u_sdio1_if),
      .usb2           (u_usb2_ulpi_if),
      .jtag_tck_i     (s_jtag_tck),
      .jtag_tms_i     (s_jtag_tms),
      .jtag_tdi_i     (s_jtag_tdi),
      .jtag_trst_n_i  (s_jtag_trst_n),
      .jtag_tdo_o     (s_jtag_tdo),
      .wdg_reset_req_o(s_wdg_reset_req),
      .test_done_o    (s_test_done),
      .test_pass_o    (s_test_pass),
      .test_code_o    (s_test_code),
      .hp_idle_o      (s_hp_idle),
      .pclk_idle_o    (s_pclk_idle)
  );

  logic [3:0] s_unused_clock_status;
  assign s_unused_clock_status = {s_aon_clk, s_aon_rst_n, s_hp_block, s_pll_fault};

endmodule
