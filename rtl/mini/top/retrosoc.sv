// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"
`include "mdd_config.svh"

module retrosoc (
    // verilog_format: off
    input  logic                           clk_i,
    input  logic                           rst_n_i,
    input  logic                           clk_aud_i,
    input  logic                           rst_aud_n_i,
    input  logic                           clkdiv4_i,
`ifdef CORE_MDD
    input  logic [`USER_CORESEL_WIDTH-1:0] core_sel_i,
`endif
`ifdef IP_MDD
    gpio_if.dut                            user_gpio,
`endif
`ifdef HAVE_SRAM_IF
    ram_if.master                          ram,
`endif
    output logic [31:0]                    gpio_oe_o,
    output logic [31:0]                    gpio_cs_o,
    output logic [31:0]                    gpio_pu_o,
    output logic [31:0]                    gpio_pd_o,
    output logic [31:0]                    gpio_do_o,
    input  logic [31:0]                    gpio_di_i,
    uart_if.dut                            uart0,
    xpi_if.dut                             xpi,
    sdram_if.dut                           sdram
    // verilog_format: on
);


  // verilog_format: off
  // bus interface
  nmi_if u_core_nmi_if ();
  nmi_if u_dma_nmi_if  ();
  nmi_if u_nmi_nmi_if  ();
  nmi_if u_apb_nmi_if  ();
  // ip interface
  gpio_if     u_gpio_if     ();
  psram_if    u_psram_if    ();
  spi_if      u_spisd_if    ();
  i2c_if      u_i2c0_if     ();
  i2s_if      u_i2s_if      ();
  onewire_if  u_onewire_if  ();
  sysctrl_if  u_sysctrl_if  ();
  dvp_if      u_dvp_if      ();
  sdio_if     u_sdio_if     ();
  opipsram_if u_opipsram_if ();
  i2c_if      u_i2c1_if     ();
  uart_if     u_uart1_if    ();
  pwm_if      u_pwm_if      ();
  ps2_if      u_ps2_if      ();
  // verilog_format: on

  logic        s_tmr_capch;
  logic [31:0] s_irq;
  logic [ 9:0] s_nmi_irq;
  logic [ 6:0] s_apb_irq;

`ifdef CORE_MDD
  assign u_sysctrl_if.core_sel_i = core_sel_i;
`else
  assign u_sysctrl_if.core_sel_i = '0;
`endif

  // irq
  assign s_irq[9:0]               = s_nmi_irq;
  assign s_irq[16:10]             = s_apb_irq;
  assign s_irq[31:17]             = 15'd0;

  // bind io
  // =====================================================
  // | GPIO0 | FUNC0                | FUNC1              |
  // =====================================================
  // | 0     | uart1_rx_i_pad       | ps2_clk_i_pad      |
  // | 1     | uart1_tx_o_pad       | ps2_dat_i_pad      |
  // | 2     | tmr_capch_i_pad      | onewire_dat_o_pad  |
  // | 3     | pwm_0_o_pad          | i2c1_scl_io_pad    |
  // | 4     | pwm_1_o_pad          | i2c1_sda_io_pad    |
  // | 5     | pwm_2_o_pad          | sys_clkdiv4_o_pad  |
  // | 6     | pwm_3_o_pad          | spisd_sck_pad      |
  // | 7     | i2c0_scl_io_pad      | spisd_nss_pad      |
  // | 8     | i2c0_sda_io_pad      | spisd_mosi_pad     |
  // | 9     | __NONE_FUNC__        | spisd_miso_pad     |
  // | 10    | i2s_0_mclk_o_pad     | dvp_pclk_i_pad     |
  // | 11    | i2s_0_sck_io_pad     | dvp_href_i_pad     |
  // | 12    | i2s_lrck_o_pad       | dvp_vsync_i_pad    |
  // | 13    | i2s_dacdat_o_pad     | dvp_dat0_i_pad     |
  // | 14    | i2s_adcdat_i_pad     | dvp_dat1_i_pad     |
  // | 15    | sdio_sck_o_pad       | dvp_dat2_i_pad     |
  // | 16    | sdio_cmd_o_pad       | dvp_dat3_i_pad     |
  // | 17    | sdio_dat0_io_pad     | dvp_dat4_i_pad     |
  // | 18    | sdio_dat1_io_pad     | dvp_dat5_i_pad     |
  // | 19    | sdio_dat2_io_pad     | dvp_dat6_i_pad     |
  // | 20    | sdio_dat3_io_pad     | dvp_dat7_i_pad     |
  // | 21    | opipsram_sck_o_pad   | psram_sck_o_pad    |
  // | 22    | opipsram_ce_o_pad    | psram_ce0_o_pad    |
  // | 23    | opipsram_dat0_io_pad | psram_dat0_io_pad  |
  // | 24    | opipsram_dat1_io_pad | psram_dat1_io_pad  |
  // | 25    | opipsram_dat2_io_pad | psram_dat2_io_pad  |
  // | 26    | opipsram_dat3_io_pad | psram_dat3_io_pad  |
  // | 27    | opipsram_dat4_io_pad | psram_ce1_o_pad    |
  // | 28    | opipsram_dat5_io_pad | psram_ce2_o_pad    |
  // | 29    | opipsram_dat6_io_pad | psram_ce3_o_pad    |
  // | 30    | opipsram_dat7_io_pad | __NONE_FUNC__      |
  // | 31    | opipsram_dqs_o_pad   | __NONE_FUNC__      |
  // =====================================================
  assign gpio_oe_o                = u_gpio_if.oe_o;
  assign gpio_cs_o                = u_gpio_if.cs_o;
  assign gpio_pu_o                = u_gpio_if.pu_o;
  assign gpio_pd_o                = u_gpio_if.pd_o;
  assign gpio_do_o                = u_gpio_if.do_o;
  assign u_gpio_if.di_i           = gpio_di_i;
  // GPIO0 FUNC0
  // pad0
  assign u_uart1_if.rx_i          = u_gpio_if.di_i[0];
  assign u_gpio_if.alt0_do_i[0]   = '0;
  assign u_gpio_if.alt0_oe_i[0]   = '0;
  // pad1
  assign u_gpio_if.alt0_do_i[1]   = u_uart1_if.tx_o;
  assign u_gpio_if.alt0_oe_i[1]   = '1;
  // pad2
  assign s_tmr_capch              = u_gpio_if.di_i[2];
  assign u_gpio_if.alt0_do_i[2]   = '0;
  assign u_gpio_if.alt0_oe_i[2]   = '0;
  // pad3
  assign u_gpio_if.alt0_do_i[3]   = u_pwm_if.do_o[0];
  assign u_gpio_if.alt0_oe_i[3]   = '1;
  // pad4
  assign u_gpio_if.alt0_do_i[4]   = u_pwm_if.do_o[1];
  assign u_gpio_if.alt0_oe_i[4]   = '1;
  // pad5
  assign u_gpio_if.alt0_do_i[5]   = u_pwm_if.do_o[2];
  assign u_gpio_if.alt0_oe_i[5]   = '1;
  // pad6
  assign u_gpio_if.alt0_do_i[6]   = u_pwm_if.do_o[3];
  assign u_gpio_if.alt0_oe_i[6]   = '1;
  // pad7
  assign u_i2c0_if.scl_i          = u_gpio_if.di_i[7];
  assign u_gpio_if.alt0_do_i[7]   = u_i2c0_if.scl_o;
  assign u_gpio_if.alt0_oe_i[7]   = u_i2c0_if.scl_oe_o;
  // pad8
  assign u_i2c0_if.sda_i          = u_gpio_if.di_i[8];
  assign u_gpio_if.alt0_do_i[8]   = u_i2c0_if.sda_o;
  assign u_gpio_if.alt0_oe_i[8]   = u_i2c0_if.sda_oe_o;
  // pad9
  assign u_gpio_if.alt0_do_i[9]   = '0;
  assign u_gpio_if.alt0_oe_i[9]   = '0;
  // pad10
  assign u_gpio_if.alt0_do_i[10]  = u_i2s_if.mclk_o;
  assign u_gpio_if.alt0_oe_i[10]  = '1;
  // pad11
  assign u_gpio_if.alt0_do_i[11]  = u_i2s_if.sclk_o;
  assign u_gpio_if.alt0_oe_i[11]  = '1;
  // pad12
  assign u_gpio_if.alt0_do_i[12]  = u_i2s_if.lrck_o;
  assign u_gpio_if.alt0_oe_i[12]  = '1;
  // pad13
  assign u_gpio_if.alt0_do_i[13]  = u_i2s_if.dacdat_o;
  assign u_gpio_if.alt0_oe_i[13]  = '1;
  // pad14
  assign u_i2s_if.adcdat_i        = u_gpio_if.di_i[14];
  assign u_gpio_if.alt0_do_i[14]  = '0;
  assign u_gpio_if.alt0_oe_i[14]  = '0;
  // pad15
  assign u_gpio_if.alt0_do_i[15]  = u_sdio_if.sck_o;
  assign u_gpio_if.alt0_oe_i[15]  = '1;
  // pad16
  assign u_sdio_if.cmd_di_i       = u_gpio_if.di_i[16];
  assign u_gpio_if.alt0_do_i[16]  = u_sdio_if.cmd_do_o;
  assign u_gpio_if.alt0_oe_i[16]  = u_sdio_if.cmd_oe_o;
  // pad17
  assign u_sdio_if.dat_di_i[0]    = u_gpio_if.di_i[17];
  assign u_gpio_if.alt0_do_i[17]  = u_sdio_if.dat_do_o[0];
  assign u_gpio_if.alt0_oe_i[17]  = u_sdio_if.dat_oe_o[0];
  // pad18
  assign u_sdio_if.dat_di_i[1]    = u_gpio_if.di_i[18];
  assign u_gpio_if.alt0_do_i[18]  = u_sdio_if.dat_do_o[1];
  assign u_gpio_if.alt0_oe_i[18]  = u_sdio_if.dat_oe_o[1];
  // pad19
  assign u_sdio_if.dat_di_i[2]    = u_gpio_if.di_i[19];
  assign u_gpio_if.alt0_do_i[19]  = u_sdio_if.dat_do_o[2];
  assign u_gpio_if.alt0_oe_i[19]  = u_sdio_if.dat_oe_o[2];
  // pad20
  assign u_sdio_if.dat_di_i[3]    = u_gpio_if.di_i[20];
  assign u_gpio_if.alt0_do_i[20]  = u_sdio_if.dat_do_o[3];
  assign u_gpio_if.alt0_oe_i[20]  = u_sdio_if.dat_oe_o[3];
  // pad21
  assign u_gpio_if.alt0_do_i[21]  = u_opipsram_if.sck_o;
  assign u_gpio_if.alt0_oe_i[21]  = '1;
  // pad22
  assign u_gpio_if.alt0_do_i[22]  = u_opipsram_if.ce_o;
  assign u_gpio_if.alt0_oe_i[22]  = '1;
  // pad23
  assign u_opipsram_if.io_di_i[0] = u_gpio_if.di_i[23];
  assign u_gpio_if.alt0_do_i[23]  = u_opipsram_if.io_do_o[0];
  assign u_gpio_if.alt0_oe_i[23]  = u_opipsram_if.io_oe_o[0];
  // pad24
  assign u_opipsram_if.io_di_i[1] = u_gpio_if.di_i[24];
  assign u_gpio_if.alt0_do_i[24]  = u_opipsram_if.io_do_o[1];
  assign u_gpio_if.alt0_oe_i[24]  = u_opipsram_if.io_oe_o[1];
  // pad25
  assign u_opipsram_if.io_di_i[2] = u_gpio_if.di_i[25];
  assign u_gpio_if.alt0_do_i[25]  = u_opipsram_if.io_do_o[2];
  assign u_gpio_if.alt0_oe_i[25]  = u_opipsram_if.io_oe_o[2];
  // pad26
  assign u_opipsram_if.io_di_i[3] = u_gpio_if.di_i[26];
  assign u_gpio_if.alt0_do_i[26]  = u_opipsram_if.io_do_o[3];
  assign u_gpio_if.alt0_oe_i[26]  = u_opipsram_if.io_oe_o[3];
  // pad27
  assign u_opipsram_if.io_di_i[4] = u_gpio_if.di_i[27];
  assign u_gpio_if.alt0_do_i[27]  = u_opipsram_if.io_do_o[4];
  assign u_gpio_if.alt0_oe_i[27]  = u_opipsram_if.io_oe_o[4];
  // pad28
  assign u_opipsram_if.io_di_i[5] = u_gpio_if.di_i[28];
  assign u_gpio_if.alt0_do_i[28]  = u_opipsram_if.io_do_o[5];
  assign u_gpio_if.alt0_oe_i[28]  = u_opipsram_if.io_oe_o[5];
  // pad29
  assign u_opipsram_if.io_di_i[6] = u_gpio_if.di_i[29];
  assign u_gpio_if.alt0_do_i[29]  = u_opipsram_if.io_do_o[6];
  assign u_gpio_if.alt0_oe_i[29]  = u_opipsram_if.io_oe_o[6];
  // pad30
  assign u_opipsram_if.io_di_i[7] = u_gpio_if.di_i[30];
  assign u_gpio_if.alt0_do_i[30]  = u_opipsram_if.io_do_o[7];
  assign u_gpio_if.alt0_oe_i[30]  = u_opipsram_if.io_oe_o[7];
  // pad31
  assign u_opipsram_if.dqs_di_i   = u_gpio_if.di_i[31];
  assign u_gpio_if.alt0_do_i[31]  = u_opipsram_if.dqs_do_o;
  assign u_gpio_if.alt0_oe_i[31]  = u_opipsram_if.dqs_oe_o;

  // GPIO0 FUNC1
  // pad0
  assign u_ps2_if.ps2_clk_i       = u_gpio_if.di_i[0];
  assign u_gpio_if.alt1_do_i[0]   = '0;
  assign u_gpio_if.alt1_oe_i[0]   = '0;
  // pad1
  assign u_ps2_if.ps2_dat_i       = u_gpio_if.di_i[1];
  assign u_gpio_if.alt1_do_i[1]   = '0;
  assign u_gpio_if.alt1_oe_i[1]   = '0;
  // pad2
  assign u_gpio_if.alt1_do_i[2]   = u_onewire_if.dat_o;
  assign u_gpio_if.alt1_oe_i[2]   = '1;
  // pad3
  assign u_i2c1_if.scl_i          = u_gpio_if.di_i[3];
  assign u_gpio_if.alt1_do_i[3]   = u_i2c1_if.scl_o;
  assign u_gpio_if.alt1_oe_i[3]   = u_i2c1_if.scl_oe_o;
  // pad4
  assign u_i2c1_if.sda_i          = u_gpio_if.di_i[4];
  assign u_gpio_if.alt1_do_i[4]   = u_i2c1_if.sda_o;
  assign u_gpio_if.alt1_oe_i[4]   = u_i2c1_if.sda_oe_o;
  // pad5
  assign u_gpio_if.alt1_do_i[5]   = clkdiv4_i;
  assign u_gpio_if.alt1_oe_i[5]   = '1;
  // pad6
  assign u_gpio_if.alt1_do_i[6]   = u_spisd_if.sck_o;
  assign u_gpio_if.alt1_oe_i[6]   = '1;
  // pad7
  assign u_gpio_if.alt1_do_i[7]   = u_spisd_if.nss_o;
  assign u_gpio_if.alt1_oe_i[7]   = '1;
  // pad8
  assign u_gpio_if.alt1_do_i[8]   = u_spisd_if.mosi_o;
  assign u_gpio_if.alt1_oe_i[8]   = '1;
  // pad9
  assign u_spisd_if.miso_i        = u_gpio_if.di_i[9];
  assign u_gpio_if.alt1_do_i[9]   = '0;
  assign u_gpio_if.alt1_oe_i[9]   = '0;
  // pad10
  assign u_dvp_if.pclk_i          = u_gpio_if.di_i[10];
  assign u_gpio_if.alt1_do_i[10]  = '0;
  assign u_gpio_if.alt1_oe_i[10]  = '0;
  // pad11
  assign u_dvp_if.href_i          = u_gpio_if.di_i[11];
  assign u_gpio_if.alt1_do_i[11]  = '0;
  assign u_gpio_if.alt1_oe_i[11]  = '0;
  // pad12
  assign u_dvp_if.vsync_i         = u_gpio_if.di_i[12];
  assign u_gpio_if.alt1_do_i[12]  = '0;
  assign u_gpio_if.alt1_oe_i[12]  = '0;
  // pad13
  assign u_dvp_if.dat_i[0]        = u_gpio_if.di_i[13];
  assign u_gpio_if.alt1_do_i[13]  = '0;
  assign u_gpio_if.alt1_oe_i[13]  = '0;
  // pad14
  assign u_dvp_if.dat_i[1]        = u_gpio_if.di_i[14];
  assign u_gpio_if.alt1_do_i[14]  = '0;
  assign u_gpio_if.alt1_oe_i[14]  = '0;
  // pad15
  assign u_dvp_if.dat_i[2]        = u_gpio_if.di_i[15];
  assign u_gpio_if.alt1_do_i[15]  = '0;
  assign u_gpio_if.alt1_oe_i[15]  = '0;
  // pad16
  assign u_dvp_if.dat_i[3]        = u_gpio_if.di_i[16];
  assign u_gpio_if.alt1_do_i[16]  = '0;
  assign u_gpio_if.alt1_oe_i[16]  = '0;
  // pad17
  assign u_dvp_if.dat_i[4]        = u_gpio_if.di_i[17];
  assign u_gpio_if.alt1_do_i[17]  = '0;
  assign u_gpio_if.alt1_oe_i[17]  = '0;
  // pad18
  assign u_dvp_if.dat_i[5]        = u_gpio_if.di_i[18];
  assign u_gpio_if.alt1_do_i[18]  = '0;
  assign u_gpio_if.alt1_oe_i[18]  = '0;
  // pad19
  assign u_dvp_if.dat_i[6]        = u_gpio_if.di_i[19];
  assign u_gpio_if.alt1_do_i[19]  = '0;
  assign u_gpio_if.alt1_oe_i[19]  = '0;
  // pad20
  assign u_dvp_if.dat_i[7]        = u_gpio_if.di_i[20];
  assign u_gpio_if.alt1_do_i[20]  = '0;
  assign u_gpio_if.alt1_oe_i[20]  = '0;
  // pad21
  assign u_gpio_if.alt1_do_i[21]  = u_psram_if.sck_o;
  assign u_gpio_if.alt1_oe_i[21]  = '1;
  // pad22
  assign u_gpio_if.alt1_do_i[22]  = u_psram_if.nss_o[0];
  assign u_gpio_if.alt1_oe_i[22]  = '1;
  // pad23
  assign u_psram_if.io_di_i[0]    = u_gpio_if.di_i[23];
  assign u_gpio_if.alt1_do_i[23]  = u_psram_if.io_do_o[0];
  assign u_gpio_if.alt1_oe_i[23]  = u_psram_if.io_oe_o[0];
  // pad24
  assign u_psram_if.io_di_i[1]    = u_gpio_if.di_i[24];
  assign u_gpio_if.alt1_do_i[24]  = u_psram_if.io_do_o[1];
  assign u_gpio_if.alt1_oe_i[24]  = u_psram_if.io_oe_o[1];
  // pad25
  assign u_psram_if.io_di_i[2]    = u_gpio_if.di_i[25];
  assign u_gpio_if.alt1_do_i[25]  = u_psram_if.io_do_o[2];
  assign u_gpio_if.alt1_oe_i[25]  = u_psram_if.io_oe_o[2];
  // pad26
  assign u_psram_if.io_di_i[3]    = u_gpio_if.di_i[26];
  assign u_gpio_if.alt1_do_i[26]  = u_psram_if.io_do_o[3];
  assign u_gpio_if.alt1_oe_i[26]  = u_psram_if.io_oe_o[3];
  // pad27
  assign u_gpio_if.alt1_do_i[27]  = u_psram_if.nss_o[1];
  assign u_gpio_if.alt1_oe_i[27]  = '1;
  // pad28
  assign u_gpio_if.alt1_do_i[28]  = u_psram_if.nss_o[2];
  assign u_gpio_if.alt1_oe_i[28]  = '1;
  // pad29
  assign u_gpio_if.alt1_do_i[29]  = u_psram_if.nss_o[3];
  assign u_gpio_if.alt1_oe_i[29]  = '1;
  // pad30
  assign u_gpio_if.alt1_do_i[30]  = '0;
  assign u_gpio_if.alt1_oe_i[30]  = '0;
  // pad31
  assign u_gpio_if.alt1_do_i[31]  = '0;
  assign u_gpio_if.alt1_oe_i[31]  = '0;


  core_wrapper u_core_wrapper (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
`ifdef CORE_MDD
      .core_sel_i(core_sel_i),
`endif
      .nmi       (u_core_nmi_if),
      .irq_i     (s_irq)
  );


  bus u_bus (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
`ifdef HAVE_SRAM_IF
      .ram     (ram),
`endif
      // master
      .core_nmi(u_core_nmi_if),
      .dma_nmi (u_dma_nmi_if),
      // slave
      .natv_nmi(u_nmi_nmi_if),
      .apb_nmi (u_apb_nmi_if)
  );


  ip_nmi_wrapper u_ip_nmi_wrapper (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .clk_aud_i  (clk_aud_i),
      .rst_aud_n_i(rst_aud_n_i),
      .nmi        (u_nmi_nmi_if),
      .gpio       (u_gpio_if),
      .uart       (uart0),
      .psram      (u_psram_if),
      .spisd      (u_spisd_if),
      .i2c0       (u_i2c0_if),
      .i2s        (u_i2s_if),
      .onewire    (u_onewire_if),
      .xpi        (xpi),
      .dma_nmi    (u_dma_nmi_if),
      .sysctrl    (u_sysctrl_if),
      .sdram      (sdram),
      .dvp        (u_dvp_if),
      .sdio       (u_sdio_if),
      .opipsram   (u_opipsram_if),
      .i2c1       (u_i2c1_if),
      .irq_o      (s_nmi_irq)
  );


  ip_apb_wrapper u_ip_apb_wrapper (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .clk_aud_i  (clk_aud_i),
      .rst_aud_n_i(rst_aud_n_i),
      .tmr_capch_i(s_tmr_capch),
      .nmi        (u_apb_nmi_if),
      .uart       (u_uart1_if),
      .pwm        (u_pwm_if),
      .ps2        (u_ps2_if),
`ifdef IP_MDD
      .ip_sel_i   (u_sysctrl_if.ip_sel_o),
      .gpio       (user_gpio),
`endif
      .irq_o      (s_apb_irq)
  );

endmodule
