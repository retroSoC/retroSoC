// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
`timescale 1ns / 1ps

module retrosoc_tiny_tb;
  logic s_clk_driver = 1'b0;
  wire  s_clk = s_clk_driver;
  logic s_reset_driver = 1'b0;
  wire  s_rst_n = s_reset_driver;
  wire s_uart0_tx, s_uart1_tx;
  wire           s_uart0_rx = 1'b1;
  wire           s_uart1_rx = 1'b1;
  wire           s_jtag_tck = 1'b0;
  wire           s_jtag_tms = 1'b1;
  wire           s_jtag_tdi = 1'b0;
  wire           s_jtag_trst_n = s_rst_n;
  wire           s_jtag_tdo;
  tri1    [31:0] s_gpio;
  wire           s_xpi_sck;
  wire    [ 3:0] s_xpi_nss;
  tri     [ 3:0] s_xpi_data;
  integer        s_cycles;
  integer        s_max_cycles = 20000000;
  integer        s_done_cycles = 0;
  logic   [ 7:0] s_uart_byte;

`ifdef RETROSOC_SOC__TINY_NETLIST
  wire [7:0] s_test_code = {
    u_dut.s_test_code_7_,
    u_dut.s_test_code_6_,
    u_dut.s_test_code_5_,
    u_dut.s_test_code_4_,
    u_dut.s_test_code_3_,
    u_dut.s_test_code_2_,
    u_dut.s_test_code_1_,
    u_dut.s_test_code_0_
  };
`else
  wire [7:0] s_test_code = u_dut.s_test_code;
`endif

  always #20.833333 s_clk_driver = !s_clk_driver;
  initial begin
    if ($value$plusargs("max_cycles=%d", s_max_cycles)) begin
    end
    repeat (20) @(posedge s_clk);
    @(negedge s_clk);
    s_reset_driver = 1'b1;
    for (s_cycles = 0; s_cycles < s_max_cycles; s_cycles = s_cycles + 1) begin
      @(posedge s_clk);
      if (u_dut.s_test_done) begin
        if (!u_dut.s_test_pass) $fatal(1, "SIM_TEST_FAIL code=%0d", s_test_code);
        s_done_cycles = s_done_cycles + 1;
        if (s_done_cycles == 128) begin
          $display("SIM_TEST_PASS Tiny cycles=%0d", s_cycles);
          $finish;
        end
      end
    end
    if (s_done_cycles != 128) $fatal(1, "SIM_TEST_TIMEOUT Tiny cycles=%0d", s_cycles);
  end

`ifdef RETROSOC_SOC__TINY_NETLIST
  // UART0 diagnostic output; SYSCTRL remains the authoritative test verdict.
  initial
    forever begin
      @(negedge s_uart0_tx);
      #1627.604;
      for (int bit_index = 0; bit_index < 8; bit_index++) begin
        s_uart_byte[bit_index] = s_uart0_tx;
        #1085.069;
      end
      $write("%c", s_uart_byte);
    end

`endif

  retrosoc_tiny_asic u_dut (
      `include "retrosoc_asic_tb_bindings.svh"
  );
  tiny_qspi_nor u_flash (
      .sck_i  (s_xpi_sck),
      .cs_n_i (s_xpi_nss[0]),
      .data_io(s_xpi_data)
  );
endmodule
