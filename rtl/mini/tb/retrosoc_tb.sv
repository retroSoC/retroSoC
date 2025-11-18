// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.


`timescale 1 ns / 1 ps

module retrosoc_tb;
  localparam real XTAL_CPU_FREQ = 24.0;  // MHz
  localparam real EXT_CPU_FREQ = 72.0;
  localparam real AUD_CPU_FREQ = 12.288;

  reg        r_xtal_clk;
  reg        r_ext_clk;
  wire       s_ext_clk;
  reg        r_aud_clk;
  wire       s_aud_clk;
  reg        r_rst_n;
  wire       s_rst_n;
  reg  [4:0] r_core_sel;
  wire [4:0] s_core_sel;
  reg        r_pll_en;
  wire       s_clk_bypass;
  reg  [2:0] r_pll_cfg;
`ifdef HAVE_PLL
  wire [2:0] s_pll_cfg;
`endif

  wire s_uart0_tx;
  // for handle x-prop issue
  wire s_uart0_rx = 1'b1;
  wire s_psram_sck;
  wire s_psram_nss0;
  wire s_psram_nss1;
  wire s_psram_dat0;
  wire s_psram_dat1;
  wire s_psram_dat2;
  wire s_psram_dat3;
  wire s_i2c_sda_io;
  wire s_i2c_scl_io;
  wire s_qspi_sck_o;
  wire s_qspi_nss0_o;
  wire s_qspi_nss1_o;
  wire s_qspi_nss2_o;
  wire s_qspi_nss3_o;
  wire s_qspi_dat0_io;
  wire s_qspi_dat1_io;
  wire s_qspi_dat2_io;
  wire s_qspi_dat3_io;
  wire s_i2s_sclk;
  wire s_i2s_lrck;
  wire s_i2s_adcdat;
  wire s_uart1_tx;
  wire s_uart1_rx;
  wire s_ps2_clk;
  wire s_ps2_dat;
  wire s_spfs_sck;
  wire s_spfs_nss;
  wire s_spfs_mosi;
  wire s_spfs_miso;

  always #(1000 / XTAL_CPU_FREQ / 2) r_xtal_clk = (r_xtal_clk === 1'b0);
  always #(1000 / EXT_CPU_FREQ / 2) r_ext_clk = (r_ext_clk === 1'b0);
  always #(1000 / AUD_CPU_FREQ / 2) r_aud_clk = (r_aud_clk === 1'b0);

  // connect inout pad
  assign s_ext_clk    = r_ext_clk;
  assign s_aud_clk    = r_aud_clk;
  assign s_rst_n      = r_rst_n;
  assign s_core_sel   = r_core_sel;
  assign s_clk_bypass = ~r_pll_en;
`ifdef HAVE_PLL
  assign s_pll_cfg = r_pll_cfg;
`endif

  retrosoc_asic u_retrosoc_asic (
      .xi_i_pad           (r_xtal_clk),
      .xo_o_pad           (),
      .extclk_i_pad       (s_ext_clk),
      .audclk_i_pad       (s_aud_clk),
      .tmr_capch_i_pad    (),
      .extn_irq_i_pad     (),
`ifdef CORE_MDD
      .core_sel_0_i_pad   (s_core_sel[0]),
      .core_sel_1_i_pad   (s_core_sel[1]),
      .core_sel_2_i_pad   (s_core_sel[2]),
      .core_sel_3_i_pad   (s_core_sel[3]),
      .core_sel_4_i_pad   (s_core_sel[4]),
`endif
`ifdef IP_MDD
      .user_gpio_0_io_pad (),
      .user_gpio_1_io_pad (),
      .user_gpio_2_io_pad (),
      .user_gpio_3_io_pad (),
      .user_gpio_4_io_pad (),
      .user_gpio_5_io_pad (),
      .user_gpio_6_io_pad (),
      .user_gpio_7_io_pad (),
      .user_gpio_8_io_pad (),
      .user_gpio_9_io_pad (),
      .user_gpio_10_io_pad(),
      .user_gpio_11_io_pad(),
      .user_gpio_12_io_pad(),
      .user_gpio_13_io_pad(),
      .user_gpio_14_io_pad(),
      .user_gpio_15_io_pad(),
`endif
`ifdef HAVE_PLL
      .pll_cfg_0_i_pad    (s_pll_cfg[0]),
      .pll_cfg_1_i_pad    (s_pll_cfg[1]),
      .pll_cfg_2_i_pad    (s_pll_cfg[2]),
`endif
      .clk_bypass_i_pad   (s_clk_bypass),
      .ext_rst_n_i_pad    (s_rst_n),
      .sys_clkdiv4_o_pad  (),
      .uart0_tx_o_pad     (s_uart0_tx),
      .uart0_rx_i_pad     (s_uart0_rx),
      .gpio_0_io_pad      (),
      .gpio_1_io_pad      (),
      .gpio_2_io_pad      (),
      .gpio_3_io_pad      (),
      .gpio_4_io_pad      (),
      .gpio_5_io_pad      (),
      .gpio_6_io_pad      (),
      .gpio_7_io_pad      (),
      .psram_sck_o_pad    (s_psram_sck),
      .psram_nss0_o_pad   (s_psram_nss0),
      .psram_nss1_o_pad   (s_psram_nss1),
      .psram_nss2_o_pad   (s_psram_nss2),
      .psram_nss3_o_pad   (s_psram_nss3),
      .psram_dat0_io_pad  (s_psram_dat0),
      .psram_dat1_io_pad  (s_psram_dat1),
      .psram_dat2_io_pad  (s_psram_dat2),
      .psram_dat3_io_pad  (s_psram_dat3),
      .spisd_sck_o_pad    (),
      .spisd_nss_o_pad    (),
      .spisd_mosi_o_pad   (),
      .spisd_miso_i_pad   (),
      .i2s_mclk_o_pad     (),
      .i2s_sclk_o_pad     (s_i2s_sclk),
      .i2s_lrck_o_pad     (s_i2s_lrck),
      .i2s_dacdat_o_pad   (),
      .i2s_adcdat_i_pad   (s_i2s_adcdat),
      .onewire_dat_o_pad  (),
      .uart1_tx_o_pad     (s_uart1_tx),
      .uart1_rx_i_pad     (s_uart1_rx),
      .pwm_0_o_pad        (),
      .pwm_1_o_pad        (),
      .pwm_2_o_pad        (),
      .pwm_3_o_pad        (),
      .ps2_clk_i_pad      (s_ps2_clk),
      .ps2_dat_i_pad      (s_ps2_dat),
      .i2c_scl_io_pad     (s_i2c_scl_io),
      .i2c_sda_io_pad     (s_i2c_sda_io),
      .qspi_sck_o_pad     (s_qspi_sck_o),
      .qspi_nss0_o_pad    (s_qspi_nss0_o),
      .qspi_nss1_o_pad    (s_qspi_nss1_o),
      .qspi_nss2_o_pad    (s_qspi_nss2_o),
      .qspi_nss3_o_pad    (), // tft test
      .qspi_dat0_io_pad   (s_qspi_dat0_io),
      .qspi_dat1_io_pad   (s_qspi_dat1_io),
      .qspi_dat2_io_pad   (s_qspi_dat2_io),
      .qspi_dat3_io_pad   (s_qspi_dat3_io),
      .spfs_sck_o_pad     (s_spfs_sck),
      .spfs_nss_o_pad     (s_spfs_nss),
      .spfs_mosi_o_pad    (s_spfs_mosi),
      .spfs_miso_i_pad    (s_spfs_miso)
  );

  N25Qxxx u_N25Qxxx (
      .C_       (s_spfs_sck),
      .S        (s_spfs_nss),
      .DQ0      (s_spfs_mosi),
      .DQ1      (s_spfs_miso),
      .HOLD_DQ3 (),
      .Vpp_W_DQ2(),
      .Vcc      ('d3000)
  );

  W25Q128JVxIM u_W25Q128JVxIM_0 (
      .CSn  (s_qspi_nss0_o),
      .CLK  (s_qspi_sck_o),
      .DIO  (s_qspi_dat0_io),
      .DO   (s_qspi_dat1_io),
      .WPn  (s_qspi_dat2_io),
      .HOLDn(s_qspi_dat3_io)
  );

  W25Q128JVxIM u_W25Q128JVxIM_1 (
      .CSn  (s_qspi_nss1_o),
      .CLK  (s_qspi_sck_o),
      .DIO  (s_qspi_dat0_io),
      .DO   (s_qspi_dat1_io),
      .WPn  (s_qspi_dat2_io),
      .HOLDn(s_qspi_dat3_io)
  );


  // Testbench pullups on SDA, SCL lines
  pullup i2c_scl_up (s_i2c_scl_io);
  pullup i2c_sda_up (s_i2c_sda_io);
  AT24C04 u_AT24C04_0 (
      .WP (1'b0),
      .SCL(s_i2c_scl_io),
      .SDA(s_i2c_sda_io)
  );

  rs232 u_rs232_0 (
      .rs232_rx_i(s_uart0_tx),
      .rs232_tx_o()
  );

  rs232 u_rs232_1 (
      .rs232_rx_i(s_uart1_tx),
      .rs232_tx_o(s_uart1_rx)
  );

  kdb_model u_kdb_model (
      .ps2_clk_o(s_ps2_clk),
      .ps2_dat_o(s_ps2_dat)
  );

  ESP_PSRAM64H #(0) u_ESP_PSRAM64H_0 (
      .sclk(s_psram_sck),
      .csn (s_psram_nss0),
      .sio ({s_psram_dat3, s_psram_dat2, s_psram_dat1, s_psram_dat0})
  );

  ESP_PSRAM64H #(1) u_ESP_PSRAM64H_1 (
      .sclk(s_psram_sck),
      .csn (s_psram_nss1),
      .sio ({s_psram_dat3, s_psram_dat2, s_psram_dat1, s_psram_dat0})
  );

  ESP_PSRAM64H #(2) u_ESP_PSRAM64H_2 (
      .sclk(s_psram_sck),
      .csn (s_psram_nss2),
      .sio ({s_psram_dat3, s_psram_dat2, s_psram_dat1, s_psram_dat0})
  );

  ESP_PSRAM64H #(3) u_ESP_PSRAM64H_3 (
      .sclk(s_psram_sck),
      .csn (s_psram_nss3),
      .sio ({s_psram_dat3, s_psram_dat2, s_psram_dat1, s_psram_dat0})
  );

  mic #(16) u_mic (
      .sck_i(s_i2s_sclk),
      .ws_i (s_i2s_lrck),
      .sd_o (s_i2s_adcdat)
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
      #398844962;
      // #867652;
      // #1667652;
      // #327820116;
      // #327179489;
      // #836901000;
      // #468320000;
      // #505600311;
      // #507983431
      // #507983430;
      // #535996319;
      // #543128473;
      // #577859417; // pure
      // #585923415;
      // #1070933733; // debug spi
      // #873310000;
      // #340686376;

      // #489238714;

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
    r_core_sel = 5'd0;

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
    $display("core_sel: %0d", r_core_sel);
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
