/*
 *  PicoSoC - A simple example SoC using PicoRV32
 *
 *  Copyright (C) 2017  Claire Xenia Wolf <claire@yosyshq.com>
 *  Copyright (C) 2025  Yuchi Miao <miaoyuchi@ict.ac.cn>
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

`timescale 1 ns / 1 ps

module retrosoc_tb;
  localparam real XTAL_CPU_FREQ = 24.0;  // MHz
  localparam real EXT_CPU_FREQ = 72.0;

  reg        r_xtal_clk;
  reg        r_ext_clk;
  wire       s_ext_clk;
  reg        r_rst_n;
  wire       s_rst_n;
  reg  [4:0] r_core_mdd_sel;
  wire [4:0] s_core_mdd_sel;
  reg  [4:0] r_ip_mdd_sel;
  wire [4:0] s_ip_mdd_sel;
  reg        r_pll_en;
  wire       s_clk_bypass;
  reg  [2:0] r_pll_cfg;
`ifdef HAVE_PLL
  wire [2:0] s_pll_cfg;
`endif

  wire s_uart_tx;
  wire s_flash_csb;
  wire s_flash_clk;
  wire s_flash_io0;
  wire s_flash_io1;
  wire s_flash_io2;
  wire s_flash_io3;
  // wire s_i2c_sda_io;
  // wire s_i2c_scl_io;
  wire s_cust_uart_tx;
  wire s_cust_uart_rx;
  wire s_cust_ps2_ps2_clk;
  wire s_cust_ps2_ps2_dat;
  wire s_cust_psram_sclk;
  wire s_cust_psram_ce0;
  wire s_cust_psram_ce1;
  wire s_cust_psram_sio0;
  wire s_cust_psram_sio1;
  wire s_cust_psram_sio2;
  wire s_cust_psram_sio3;
  wire s_cust_spfs_clk_o;
  wire s_cust_spfs_cs_o;
  wire s_cust_spfs_mosi_o;
  wire s_cust_spfs_miso_i;

  always #(1000 / XTAL_CPU_FREQ / 2) r_xtal_clk = (r_xtal_clk === 1'b0);
  always #(1000 / EXT_CPU_FREQ / 2) r_ext_clk = (r_ext_clk === 1'b0);

  // connect inout pad
  assign s_ext_clk      = r_ext_clk;
  assign s_rst_n        = r_rst_n;
  assign s_core_mdd_sel = r_core_mdd_sel;
  assign s_ip_mdd_sel   = r_ip_mdd_sel;
  assign s_clk_bypass   = ~r_pll_en;
`ifdef HAVE_PLL
  assign s_pll_cfg = r_pll_cfg;
`endif

  retrosoc_asic u_retrosoc_asic (
      .xi_i_pad                 (r_xtal_clk),
      .xo_o_pad                 (),
      .extclk_i_pad             (s_ext_clk),
`ifdef CORE_MDD
      .core_mdd_sel_0_i_pad     (s_core_mdd_sel[0]),
      .core_mdd_sel_1_i_pad     (s_core_mdd_sel[1]),
      .core_mdd_sel_2_i_pad     (s_core_mdd_sel[2]),
      .core_mdd_sel_3_i_pad     (s_core_mdd_sel[3]),
      .core_mdd_sel_4_i_pad     (s_core_mdd_sel[4]),
`endif
`ifdef IP_MDD
      .ip_mdd_sel_0_i_pad       (s_ip_mdd_sel[0]),
      .ip_mdd_sel_1_i_pad       (s_ip_mdd_sel[1]),
      .ip_mdd_sel_2_i_pad       (s_ip_mdd_sel[2]),
      .ip_mdd_sel_3_i_pad       (s_ip_mdd_sel[3]),
      .ip_mdd_sel_4_i_pad       (s_ip_mdd_sel[4]),
      .ip_mdd_gpio_0_io_pad     (),
      .ip_mdd_gpio_1_io_pad     (),
      .ip_mdd_gpio_2_io_pad     (),
      .ip_mdd_gpio_3_io_pad     (),
      .ip_mdd_gpio_4_io_pad     (),
      .ip_mdd_gpio_5_io_pad     (),
      .ip_mdd_gpio_6_io_pad     (),
      .ip_mdd_gpio_7_io_pad     (),
      .ip_mdd_gpio_8_io_pad     (),
      .ip_mdd_gpio_9_io_pad     (),
      .ip_mdd_gpio_10_io_pad    (),
      .ip_mdd_gpio_11_io_pad    (),
      .ip_mdd_gpio_12_io_pad    (),
      .ip_mdd_gpio_13_io_pad    (),
      .ip_mdd_gpio_14_io_pad    (),
      .ip_mdd_gpio_15_io_pad    (),
`endif
`ifdef HAVE_PLL
      .pll_cfg_0_i_pad          (s_pll_cfg[0]),
      .pll_cfg_1_i_pad          (s_pll_cfg[1]),
      .pll_cfg_2_i_pad          (s_pll_cfg[2]),
`endif
      .clk_bypass_i_pad         (s_clk_bypass),
      .ext_rst_n_i_pad          (s_rst_n),
      .sys_clkdiv4_o_pad        (),
      .uart_tx_o_pad            (s_uart_tx),
      .uart_rx_i_pad            (),
      .gpio_0_io_pad            (),
      .gpio_1_io_pad            (),
      .gpio_2_io_pad            (),
      .gpio_3_io_pad            (),
      .gpio_4_io_pad            (),
      .gpio_5_io_pad            (),
      .gpio_6_io_pad            (),
      .gpio_7_io_pad            (),
      .irq_pin_i_pad            (),
      .cust_uart_tx_o_pad       (s_cust_uart_tx),
      .cust_uart_rx_i_pad       (s_cust_uart_rx),
      .cust_pwm_pwm_0_o_pad     (),
      .cust_pwm_pwm_1_o_pad     (),
      .cust_pwm_pwm_2_o_pad     (),
      .cust_pwm_pwm_3_o_pad     (),
      .cust_ps2_ps2_clk_i_pad   (s_cust_ps2_ps2_clk),
      .cust_ps2_ps2_dat_i_pad   (s_cust_ps2_ps2_dat),
      .cust_i2c_scl_io_pad      (),
      .cust_i2c_sda_io_pad      (),
      .cust_qspi_spi_clk_o_pad  (),
      .cust_qspi_spi_csn_0_o_pad(),
      .cust_qspi_spi_csn_1_o_pad(),
      .cust_qspi_spi_csn_2_o_pad(),
      .cust_qspi_spi_csn_3_o_pad(),
      .cust_qspi_dat_0_io_pad   (),
      .cust_qspi_dat_1_io_pad   (),
      .cust_qspi_dat_2_io_pad   (),
      .cust_qspi_dat_3_io_pad   (),
      .cust_psram_sclk_o_pad    (s_cust_psram_sclk),
      .cust_psram_ce0_o_pad     (s_cust_psram_ce0),
      .cust_psram_ce1_o_pad     (s_cust_psram_ce1),
      .cust_psram_sio0_io_pad   (s_cust_psram_sio0),
      .cust_psram_sio1_io_pad   (s_cust_psram_sio1),
      .cust_psram_sio2_io_pad   (s_cust_psram_sio2),
      .cust_psram_sio3_io_pad   (s_cust_psram_sio3),
      .cust_spfs_clk_o_pad      (s_cust_spfs_clk_o),
      .cust_spfs_cs_o_pad       (s_cust_spfs_cs_o),
      .cust_spfs_mosi_o_pad     (s_cust_spfs_mosi_o),
      .cust_spfs_miso_i_pad     (s_cust_spfs_miso_i)
  );

  N25Qxxx u_N25Qxxx (
      .C_       (s_cust_spfs_clk_o),
      .S        (s_cust_spfs_cs_o),
      .DQ0      (s_cust_spfs_mosi_o),
      .DQ1      (s_cust_spfs_miso_i),
      .HOLD_DQ3 (),
      .Vpp_W_DQ2(),
      .Vcc      ('d3000)
  );

  // Testbench pullups on SDA, SCL lines
  // pullup i2c_scl_up (s_i2c_scl_io);
  // pullup i2c_sda_up (s_i2c_sda_io);
  // i2c_slave u_i2c_slave (
  //     .scl(s_i2c_scl_io),
  //     .sda(s_i2c_sda_io)
  // );

  rs232 u_rs232_0 (
      .rs232_rx_i(s_uart_tx),
      .rs232_tx_o()
  );

  rs232 u_rs232_1 (
      .rs232_rx_i(s_cust_uart_tx),
      .rs232_tx_o(s_cust_uart_rx)
  );

  kdb_model u_kdb_model (
      .ps2_clk_o(s_cust_ps2_ps2_clk),
      .ps2_dat_o(s_cust_ps2_ps2_dat)
  );

  ESP_PSRAM64H #(0) u_ESP_PSRAM64H_0 (
      .sclk(s_cust_psram_sclk),
      .csn (s_cust_psram_ce0),
      .sio ({s_cust_psram_sio3, s_cust_psram_sio2, s_cust_psram_sio1, s_cust_psram_sio0})
  );

  ESP_PSRAM64H #(1) u_ESP_PSRAM64H_1 (
      .sclk(s_cust_psram_sclk),
      .csn (s_cust_psram_ce1),
      .sio ({s_cust_psram_sio3, s_cust_psram_sio2, s_cust_psram_sio1, s_cust_psram_sio0})
  );

  initial begin
    r_rst_n = 1;
    #43;
    r_rst_n = 0;
    #170701;
    r_rst_n = 1;
  end

  initial begin : KDB_MODEL_BLOCK
    integer i;
    #1000;
    while (1) begin
      #1000;
      for (i = 0; i < 26; ++i) begin
        u_kdb_model.send_code(i + 8'd65);
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
    if ($test$plusargs("behv_wave")) begin
      $display("gen behv sim wave");
      $fsdbDumpfile("retrosoc_tb.fsdb");
      $fsdbDumpvars(0);
      $fsdbDumpMDA();
      // #398844962;
      // #867652;
      // #340686376;
      #489238714;

      // repeat (1500) begin
      //   repeat (5000) @(posedge r_xtal_clk);
      // end
      $finish;
    end else if ($test$plusargs("syn_wave")) begin
      $display("gen syn sim wave");
      $fsdbDumpfile("retrosoc_syn_tb.fsdb");
      $fsdbDumpvars(0);

      repeat (10) begin
        $display("hello");
        repeat (100) @(posedge r_xtal_clk);
      end
      $finish;
    end

    // repeat (1500) begin
    // repeat (5000) @(posedge r_xtal_clk);
    // $display("+5000 cycles");
    // end
    // $finish;
  end

  initial begin
    r_core_mdd_sel = 5'd1;
    r_ip_mdd_sel   = 5'd0;

    if ($test$plusargs("pll_en")) r_pll_en = 1'b1;
    else r_pll_en = 1'b0;

    if ($test$plusargs("pll_cfg0")) r_pll_cfg = 3'd0;  // 24M
    else if ($test$plusargs("pll_cfg1")) r_pll_cfg = 3'd1;  // 48M
    else if ($test$plusargs("pll_cfg2")) r_pll_cfg = 3'd2;  // 72M
    else if ($test$plusargs("pll_cfg3")) r_pll_cfg = 3'd3;  // 96M
    else if ($test$plusargs("pll_cfg4")) r_pll_cfg = 3'd4;  // 120M
    else if ($test$plusargs("pll_cfg5")) r_pll_cfg = 3'd5;  // 144M
    else if ($test$plusargs("pll_cfg6")) r_pll_cfg = 3'd6;  // 168M
    else if ($test$plusargs("pll_cfg7")) r_pll_cfg = 3'd7;  // 192M
    else r_pll_cfg = 3'd0;  // 24M

    $display("========================================================");
`ifdef CORE_MDD
    $display("core_mdd_sel: %0d", r_core_mdd_sel);
`endif
`ifdef IP_MDD
    $display("ip_mdd_sel: %0d", r_ip_mdd_sel);
`endif

    if (r_pll_en == 1'b0) begin
      $display("pll_en: %0d pll_cfg: %0d clk_freq: %0dMHz", r_pll_en, r_pll_cfg, EXT_CPU_FREQ);
    end else if (r_pll_cfg == 3'd0 || r_pll_cfg == 3'd1) begin
      $display("pll_en: %0d pll_cfg: %0d clk_freq: %0dMHz", r_pll_en, r_pll_cfg, XTAL_CPU_FREQ);
    end else begin
      $display("pll_en: %0d pll_cfg: %0d clk_freq: %0dMHz", r_pll_en, r_pll_cfg,
               (r_pll_cfg + 1) * 24);
    end
    $display("========================================================");
  end
endmodule
