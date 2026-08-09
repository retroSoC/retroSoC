// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.


`timescale 1 ns / 1 ps
// `default_nettype none

module retrosoc_tb;
  localparam real XTAL_CPU_FREQ = 24.0;
  localparam real EXT_CPU_FREQ = 72.0;
  localparam real AUD_CPU_FREQ = 18.432;

  integer sim_runtime;

  reg     r_ext_clk;
  wire    s_ext_clk;
  reg     r_aud_clk;
  wire    s_aud_clk;
  reg     r_rst_n;
  wire    s_rst_n;
`ifdef HAVE_PLL
  reg r_xtal_clk;
`endif
  wire        s_jtag_tck;
  wire        s_jtag_tms;
  wire        s_jtag_tdi;
  wire        s_jtag_trst_n;
  wire        s_uart0_tx;
  // for handle x-prop issue
  wire        s_uart0_rx = 1'b1;
  tri1        s_gpio_0_io;
  tri1        s_gpio_1_io;
  wire        s_psram_sck;
  wire        s_psram_nss0;
  wire        s_psram_nss1;
  wire        s_psram_dat0;
  wire        s_psram_dat1;
  wire        s_psram_dat2;
  wire        s_psram_dat3;
  wire        s_i2c0_sda_io;
  wire        s_i2c0_scl_io;
  wire        s_xpi_sck_o;
  wire        s_xpi_nss0_o;
  wire        s_xpi_nss1_o;
  wire        s_xpi_nss2_o;
  wire        s_xpi_dat0_io;
  wire        s_xpi_dat1_io;
  wire        s_xpi_dat2_io;
  wire        s_xpi_dat3_io;
  wire        s_i2s_sclk;
  wire        s_i2s_lrck;
  wire        s_i2s_adcdat;
  wire        s_sdram_clk;
  wire        s_sdram_cke;
  wire        s_sdram_cs_n;
  wire        s_sdram_ras_n;
  wire        s_sdram_cas_n;
  wire        s_sdram_we_n;
  wire [ 1:0] s_sdram_ba;
  wire [12:0] s_sdram_addr;
  wire [ 1:0] s_sdram_dqm;
  wire [15:0] s_sdram_dq;
  wire        s_dvp_pclk;
  wire        s_dvp_href;
  wire        s_dvp_vsync;
  wire [ 7:0] s_dvp_data;

  wire        s_uart1_tx;
  wire        s_uart1_rx;

`ifdef HAVE_PLL
  always #(1000 / XTAL_CPU_FREQ / 2) r_xtal_clk = (r_xtal_clk === 1'b0);
`endif
  always #(1000 / EXT_CPU_FREQ / 2) r_ext_clk = (r_ext_clk === 1'b0);
  always #(1000 / AUD_CPU_FREQ / 2) r_aud_clk = (r_aud_clk === 1'b0);

  // connect inout pad
  assign s_ext_clk     = r_ext_clk;
  assign s_aud_clk     = r_aud_clk;
  assign s_rst_n       = r_rst_n;
  assign s_jtag_tck    = 1'b0;
  assign s_jtag_tms    = 1'b0;
  assign s_jtag_tdi    = 1'b0;
  assign s_jtag_trst_n = 1'b0;

  retrosoc_asic u_retrosoc_asic (
      `include "retrosoc_asic_tb_bindings.svh"
  );


  W25Q128JVxIM u_W25Q128JVxIM_norflash (
      .CSn  (s_xpi_nss0_o),
      .CLK  (s_xpi_sck_o),
      .DIO  (s_xpi_dat0_io),
      .DO   (s_xpi_dat1_io),
      .WPn  (s_xpi_dat2_io),
      .HOLDn(s_xpi_dat3_io)
  );


  W25Q128JVxIM u_W25Q128JVxIM_1 (
      .CSn  (s_xpi_nss1_o),
      .CLK  (s_xpi_sck_o),
      .DIO  (s_xpi_dat0_io),
      .DO   (s_xpi_dat1_io),
      .WPn  (s_xpi_dat2_io),
      .HOLDn(s_xpi_dat3_io)
  );


  sdr u_sdr (
      .Clk  (s_sdram_clk),
      .Cke  (s_sdram_cke),
      .Cs_n (s_sdram_cs_n),
      .Ras_n(s_sdram_ras_n),
      .Cas_n(s_sdram_cas_n),
      .We_n (s_sdram_we_n),
      .Addr (s_sdram_addr),
      .Ba   (s_sdram_ba),
      .Dq   (s_sdram_dq),
      .Dqm  (s_sdram_dqm)
  );


  pullup u_i2c0_scl_pullup (s_i2c0_scl_io);
  pullup u_i2c0_sda_pullup (s_i2c0_sda_io);
  AT24C04 u_AT24C04_0 (
      .WP (1'b0),
      .SCL(s_i2c0_scl_io),
      .SDA(s_i2c0_sda_io)
  );


  rs232 #(
      .BAUD_RATE(921600)
  ) u_rs232_0 (
      .rs232_rx_i(s_uart0_tx),
      .rs232_tx_o()
  );


  rs232 #(
      .BAUD_RATE(115200)
  ) u_rs232_1 (
      .rs232_rx_i(s_uart1_tx),
      .rs232_tx_o(s_uart1_rx)
  );


  ps2_device_model u_ps2_device_model (
      .ps2_clk_io(s_gpio_0_io),
      .ps2_dat_io(s_gpio_1_io)
  );


  pullup u_psram_nss0_pullup (s_psram_nss0);
  ESP_PSRAM64H #(0) u_ESP_PSRAM64H_0 (
      .sclk(s_psram_sck),
      .csn (s_psram_nss0),
      .sio ({s_psram_dat3, s_psram_dat2, s_psram_dat1, s_psram_dat0})
  );


  pullup u_psram_nss1_pullup (s_psram_nss1);
  ESP_PSRAM64H #(1) u_ESP_PSRAM64H_1 (
      .sclk(s_psram_sck),
      .csn (s_psram_nss1),
      .sio ({s_psram_dat3, s_psram_dat2, s_psram_dat1, s_psram_dat0})
  );


  mic #(16) u_mic (
      .sck_i(s_i2s_sclk),
      .ws_i (s_i2s_lrck),
      .sd_o (s_i2s_adcdat)
  );


  DVP_CAMERA u_DVP_CAMERA (
      .pclk (s_dvp_pclk),
      .href (s_dvp_href),
      .vsync(s_dvp_vsync),
      .data (s_dvp_data)
  );


  initial begin
    r_rst_n = 1;
    #43;
    r_rst_n = 0;
    #170701;
    r_rst_n = 1;
  end

  initial begin : PS2_DEVICE_MODEL_BLOCK
    integer i;
    #1000;
    while (1) begin
      #1000;
      for (i = 0; i < 26; ++i) begin
        u_ps2_device_model.send_byte(i + 8'd65, 3'b000);
        #500;
      end
    end
  end

  initial begin : UART_RX_BLOCK
    integer i;
    #1000;
    while (1) begin
      #1000;
      for (i = 0; i < 26; ++i) begin
        u_rs232_1.send(i + 8'd66);
        #500;
      end
    end
  end

  initial begin
    if ($test$plusargs("wave_YES")) begin
      $display("== generate simulation wave ==");
`ifdef SIMU_VCS
      $fsdbDumpfile("retrosoc_tb.fsdb");
      $fsdbDumpvars(0);
      $fsdbDumpMDA();
`elsif SIMU_IVERILOG
      $dumpfile("retrosoc_tb.fst");
      $dumpvars(0);
`endif
      #4705000;
      $finish;
    end
  end

  initial begin
    if ($value$plusargs("sim_timeout=%d", sim_runtime) && sim_runtime > 0) begin
      $display("Simulation timeout set to: %0dns", sim_runtime);
      #sim_runtime;
      $fatal(1, "SIM_TEST_TIMEOUT");
    end
    $display("Simulation timeout disabled; waiting for terminal software status");
  end

  always @(posedge u_retrosoc_asic.s_sys_clk) begin
    if (u_retrosoc_asic.s_test_done) begin
      if (u_retrosoc_asic.s_test_pass) begin
        $display("\nSIM_TEST_PASS");
        $finish;
      end else begin
        $fatal(1, "\nSIM_TEST_FAIL");
      end
    end
  end

  initial begin
    $display("========================================================");
`ifdef HAVE_PLL
    $display("pll clock control: sysctrl");
`else
    $display("ext clk_freq: %0dMHz", EXT_CPU_FREQ);
`endif
    $display("========================================================");
  end
endmodule
