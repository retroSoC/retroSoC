// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"

`include "uart_define.svh"
`include "pwm_define.svh"
`include "ps2_define.svh"
`include "i2c_define.svh"
`include "spi_define.svh"

`include "mdd_config.svh"

module ip_apb_wrapper (
    // verilog_format: off
    input  logic                        clk_i,
    input  logic                        rst_n_i,
    input  logic                        clk_aud_i,
    input  logic                        rst_aud_n_i,
    input  logic                        tmr_capch_i,
    input  logic                        spfs_div4_i,
    nmi_if.slave                        nmi,
    uart_if.dut                         uart,
    pwm_if.dut                          pwm,
    ps2_if.dut                          ps2,
    i2c_if.dut                          i2c,
    qspi_if.dut                         qspi,
    spi_if.dut                          spfs,
`ifdef IP_MDD
    input logic [`USER_IPSEL_WIDTH-1:0] ip_sel_i,
    user_gpio_if.dut                    gpio,
`endif
    output logic [ 8:0]                 irq_o
    // verilog_format: on
);

  // verilog_format: off
  apb4_if      u_archinfo_apb_if (clk_i, rst_n_i);
  apb4_if      u_rng_apb_if      (clk_i, rst_n_i);
  apb4_if      u_uart1_apb_if    (clk_i, rst_n_i);
  apb4_if      u_pwm_apb_if      (clk_i, rst_n_i);
  apb4_if      u_ps2_apb_if      (clk_i, rst_n_i);
  apb4_if      u_i2c_apb_if      (clk_i, rst_n_i);
  apb4_if      u_qspi_apb_if     (clk_i, rst_n_i);
  apb4_if      u_rtc_apb_if      (clk_i, rst_n_i);
  apb4_if      u_wdg_apb_if      (clk_i, rst_n_i);
  apb4_if      u_crc_apb_if      (clk_i, rst_n_i);
  apb4_if      u_tmr_apb_if      (clk_i, rst_n_i);
  apb4_if      u_spfs_apb_if     (clk_i, rst_n_i);

  // NOTE: for FPGA-compatible
  apb4_pure_if u_archinfo_apb_pure_if ();
  apb4_pure_if u_rng_apb_pure_if      ();
  apb4_pure_if u_uart1_apb_pure_if    ();
  apb4_pure_if u_pwm_apb_pure_if      ();
  apb4_pure_if u_ps2_apb_pure_if      ();
  apb4_pure_if u_i2c_apb_pure_if      ();
  apb4_pure_if u_qspi_apb_pure_if     ();
  apb4_pure_if u_rtc_apb_pure_if      ();
  apb4_pure_if u_wdg_apb_pure_if      ();
  apb4_pure_if u_crc_apb_pure_if      ();
  apb4_pure_if u_tmr_apb_pure_if      ();
  apb4_pure_if u_spfs_apb_pure_if     ();

  // low freq clock perip
  rtc_if u_rtc_if (clk_aud_i, rst_aud_n_i);
  wdg_if u_wdg_if (clk_aud_i);
  tmr_if u_tmr_if (clk_aud_i);

  assign u_tmr_if.capch_i = tmr_capch_i;
  // verilog_format: on

  // verilog_format: off
`ifdef IP_MDD
  apb4_if      u_user_ip_apb_if       (clk_i, rst_n_i);
  apb4_pure_if u_user_ip_apb_pure_if  ();
`endif
  // verilog_format: on

  assign u_archinfo_apb_if.paddr        = u_archinfo_apb_pure_if.paddr;
  assign u_archinfo_apb_if.pprot        = u_archinfo_apb_pure_if.pprot;
  assign u_archinfo_apb_if.psel         = u_archinfo_apb_pure_if.psel;
  assign u_archinfo_apb_if.penable      = u_archinfo_apb_pure_if.penable;
  assign u_archinfo_apb_if.pwrite       = u_archinfo_apb_pure_if.pwrite;
  assign u_archinfo_apb_if.pwdata       = u_archinfo_apb_pure_if.pwdata;
  assign u_archinfo_apb_if.pstrb        = u_archinfo_apb_pure_if.pstrb;
  assign u_archinfo_apb_pure_if.pready  = u_archinfo_apb_if.pready;
  assign u_archinfo_apb_pure_if.prdata  = u_archinfo_apb_if.prdata;
  assign u_archinfo_apb_pure_if.pslverr = u_archinfo_apb_if.pslverr;

  assign u_rng_apb_if.paddr             = u_rng_apb_pure_if.paddr;
  assign u_rng_apb_if.pprot             = u_rng_apb_pure_if.pprot;
  assign u_rng_apb_if.psel              = u_rng_apb_pure_if.psel;
  assign u_rng_apb_if.penable           = u_rng_apb_pure_if.penable;
  assign u_rng_apb_if.pwrite            = u_rng_apb_pure_if.pwrite;
  assign u_rng_apb_if.pwdata            = u_rng_apb_pure_if.pwdata;
  assign u_rng_apb_if.pstrb             = u_rng_apb_pure_if.pstrb;
  assign u_rng_apb_pure_if.pready       = u_rng_apb_if.pready;
  assign u_rng_apb_pure_if.prdata       = u_rng_apb_if.prdata;
  assign u_rng_apb_pure_if.pslverr      = u_rng_apb_if.pslverr;

  assign u_uart1_apb_if.paddr           = u_uart1_apb_pure_if.paddr;
  assign u_uart1_apb_if.pprot           = u_uart1_apb_pure_if.pprot;
  assign u_uart1_apb_if.psel            = u_uart1_apb_pure_if.psel;
  assign u_uart1_apb_if.penable         = u_uart1_apb_pure_if.penable;
  assign u_uart1_apb_if.pwrite          = u_uart1_apb_pure_if.pwrite;
  assign u_uart1_apb_if.pwdata          = u_uart1_apb_pure_if.pwdata;
  assign u_uart1_apb_if.pstrb           = u_uart1_apb_pure_if.pstrb;
  assign u_uart1_apb_pure_if.pready     = u_uart1_apb_if.pready;
  assign u_uart1_apb_pure_if.prdata     = u_uart1_apb_if.prdata;
  assign u_uart1_apb_pure_if.pslverr    = u_uart1_apb_if.pslverr;

  assign u_pwm_apb_if.paddr             = u_pwm_apb_pure_if.paddr;
  assign u_pwm_apb_if.pprot             = u_pwm_apb_pure_if.pprot;
  assign u_pwm_apb_if.psel              = u_pwm_apb_pure_if.psel;
  assign u_pwm_apb_if.penable           = u_pwm_apb_pure_if.penable;
  assign u_pwm_apb_if.pwrite            = u_pwm_apb_pure_if.pwrite;
  assign u_pwm_apb_if.pwdata            = u_pwm_apb_pure_if.pwdata;
  assign u_pwm_apb_if.pstrb             = u_pwm_apb_pure_if.pstrb;
  assign u_pwm_apb_pure_if.pready       = u_pwm_apb_if.pready;
  assign u_pwm_apb_pure_if.prdata       = u_pwm_apb_if.prdata;
  assign u_pwm_apb_pure_if.pslverr      = u_pwm_apb_if.pslverr;

  assign u_ps2_apb_if.paddr             = u_ps2_apb_pure_if.paddr;
  assign u_ps2_apb_if.pprot             = u_ps2_apb_pure_if.pprot;
  assign u_ps2_apb_if.psel              = u_ps2_apb_pure_if.psel;
  assign u_ps2_apb_if.penable           = u_ps2_apb_pure_if.penable;
  assign u_ps2_apb_if.pwrite            = u_ps2_apb_pure_if.pwrite;
  assign u_ps2_apb_if.pwdata            = u_ps2_apb_pure_if.pwdata;
  assign u_ps2_apb_if.pstrb             = u_ps2_apb_pure_if.pstrb;
  assign u_ps2_apb_pure_if.pready       = u_ps2_apb_if.pready;
  assign u_ps2_apb_pure_if.prdata       = u_ps2_apb_if.prdata;
  assign u_ps2_apb_pure_if.pslverr      = u_ps2_apb_if.pslverr;

  assign u_i2c_apb_if.paddr             = u_i2c_apb_pure_if.paddr;
  assign u_i2c_apb_if.pprot             = u_i2c_apb_pure_if.pprot;
  assign u_i2c_apb_if.psel              = u_i2c_apb_pure_if.psel;
  assign u_i2c_apb_if.penable           = u_i2c_apb_pure_if.penable;
  assign u_i2c_apb_if.pwrite            = u_i2c_apb_pure_if.pwrite;
  assign u_i2c_apb_if.pwdata            = u_i2c_apb_pure_if.pwdata;
  assign u_i2c_apb_if.pstrb             = u_i2c_apb_pure_if.pstrb;
  assign u_i2c_apb_pure_if.pready       = u_i2c_apb_if.pready;
  assign u_i2c_apb_pure_if.prdata       = u_i2c_apb_if.prdata;
  assign u_i2c_apb_pure_if.pslverr      = u_i2c_apb_if.pslverr;

  assign u_qspi_apb_if.paddr            = u_qspi_apb_pure_if.paddr;
  assign u_qspi_apb_if.pprot            = u_qspi_apb_pure_if.pprot;
  assign u_qspi_apb_if.psel             = u_qspi_apb_pure_if.psel;
  assign u_qspi_apb_if.penable          = u_qspi_apb_pure_if.penable;
  assign u_qspi_apb_if.pwrite           = u_qspi_apb_pure_if.pwrite;
  assign u_qspi_apb_if.pwdata           = u_qspi_apb_pure_if.pwdata;
  assign u_qspi_apb_if.pstrb            = u_qspi_apb_pure_if.pstrb;
  assign u_qspi_apb_pure_if.pready      = u_qspi_apb_if.pready;
  assign u_qspi_apb_pure_if.prdata      = u_qspi_apb_if.prdata;
  assign u_qspi_apb_pure_if.pslverr     = u_qspi_apb_if.pslverr;

  assign u_rtc_apb_if.paddr             = u_rtc_apb_pure_if.paddr;
  assign u_rtc_apb_if.pprot             = u_rtc_apb_pure_if.pprot;
  assign u_rtc_apb_if.psel              = u_rtc_apb_pure_if.psel;
  assign u_rtc_apb_if.penable           = u_rtc_apb_pure_if.penable;
  assign u_rtc_apb_if.pwrite            = u_rtc_apb_pure_if.pwrite;
  assign u_rtc_apb_if.pwdata            = u_rtc_apb_pure_if.pwdata;
  assign u_rtc_apb_if.pstrb             = u_rtc_apb_pure_if.pstrb;
  assign u_rtc_apb_pure_if.pready       = u_rtc_apb_if.pready;
  assign u_rtc_apb_pure_if.prdata       = u_rtc_apb_if.prdata;
  assign u_rtc_apb_pure_if.pslverr      = u_rtc_apb_if.pslverr;

  assign u_wdg_apb_if.paddr             = u_wdg_apb_pure_if.paddr;
  assign u_wdg_apb_if.pprot             = u_wdg_apb_pure_if.pprot;
  assign u_wdg_apb_if.psel              = u_wdg_apb_pure_if.psel;
  assign u_wdg_apb_if.penable           = u_wdg_apb_pure_if.penable;
  assign u_wdg_apb_if.pwrite            = u_wdg_apb_pure_if.pwrite;
  assign u_wdg_apb_if.pwdata            = u_wdg_apb_pure_if.pwdata;
  assign u_wdg_apb_if.pstrb             = u_wdg_apb_pure_if.pstrb;
  assign u_wdg_apb_pure_if.pready       = u_wdg_apb_if.pready;
  assign u_wdg_apb_pure_if.prdata       = u_wdg_apb_if.prdata;
  assign u_wdg_apb_pure_if.pslverr      = u_wdg_apb_if.pslverr;

  assign u_crc_apb_if.paddr             = u_crc_apb_pure_if.paddr;
  assign u_crc_apb_if.pprot             = u_crc_apb_pure_if.pprot;
  assign u_crc_apb_if.psel              = u_crc_apb_pure_if.psel;
  assign u_crc_apb_if.penable           = u_crc_apb_pure_if.penable;
  assign u_crc_apb_if.pwrite            = u_crc_apb_pure_if.pwrite;
  assign u_crc_apb_if.pwdata            = u_crc_apb_pure_if.pwdata;
  assign u_crc_apb_if.pstrb             = u_crc_apb_pure_if.pstrb;
  assign u_crc_apb_pure_if.pready       = u_crc_apb_if.pready;
  assign u_crc_apb_pure_if.prdata       = u_crc_apb_if.prdata;
  assign u_crc_apb_pure_if.pslverr      = u_crc_apb_if.pslverr;

  assign u_tmr_apb_if.paddr             = u_tmr_apb_pure_if.paddr;
  assign u_tmr_apb_if.pprot             = u_tmr_apb_pure_if.pprot;
  assign u_tmr_apb_if.psel              = u_tmr_apb_pure_if.psel;
  assign u_tmr_apb_if.penable           = u_tmr_apb_pure_if.penable;
  assign u_tmr_apb_if.pwrite            = u_tmr_apb_pure_if.pwrite;
  assign u_tmr_apb_if.pwdata            = u_tmr_apb_pure_if.pwdata;
  assign u_tmr_apb_if.pstrb             = u_tmr_apb_pure_if.pstrb;
  assign u_tmr_apb_pure_if.pready       = u_tmr_apb_if.pready;
  assign u_tmr_apb_pure_if.prdata       = u_tmr_apb_if.prdata;
  assign u_tmr_apb_pure_if.pslverr      = u_tmr_apb_if.pslverr;

  assign u_spfs_apb_if.paddr            = u_spfs_apb_pure_if.paddr;
  assign u_spfs_apb_if.pprot            = u_spfs_apb_pure_if.pprot;
  assign u_spfs_apb_if.psel             = u_spfs_apb_pure_if.psel;
  assign u_spfs_apb_if.penable          = u_spfs_apb_pure_if.penable;
  assign u_spfs_apb_if.pwrite           = u_spfs_apb_pure_if.pwrite;
  assign u_spfs_apb_if.pwdata           = u_spfs_apb_pure_if.pwdata;
  assign u_spfs_apb_if.pstrb            = u_spfs_apb_pure_if.pstrb;
  assign u_spfs_apb_pure_if.pready      = u_spfs_apb_if.pready;
  assign u_spfs_apb_pure_if.prdata      = u_spfs_apb_if.prdata;
  assign u_spfs_apb_pure_if.pslverr     = u_spfs_apb_if.pslverr;
`ifdef IP_MDD
  assign u_user_ip_apb_if.paddr        = u_user_ip_apb_pure_if.paddr;
  assign u_user_ip_apb_if.pprot        = u_user_ip_apb_pure_if.pprot;
  assign u_user_ip_apb_if.psel         = u_user_ip_apb_pure_if.psel;
  assign u_user_ip_apb_if.penable      = u_user_ip_apb_pure_if.penable;
  assign u_user_ip_apb_if.pwrite       = u_user_ip_apb_pure_if.pwrite;
  assign u_user_ip_apb_if.pwdata       = u_user_ip_apb_pure_if.pwdata;
  assign u_user_ip_apb_if.pstrb        = u_user_ip_apb_pure_if.pstrb;
  assign u_user_ip_apb_pure_if.pready  = u_user_ip_apb_if.pready;
  assign u_user_ip_apb_pure_if.prdata  = u_user_ip_apb_if.prdata;
  assign u_user_ip_apb_pure_if.pslverr = u_user_ip_apb_if.pslverr;
`endif

  // verilog_format: off
  apb4_archinfo                u_apb4_archinfo (u_archinfo_apb_if);
  apb4_rng                     u_apb4_rng      (u_rng_apb_if);
  apb4_uart #(.FIFO_DEPTH(32)) u_apb4_uart     (u_uart1_apb_if, uart);
  apb4_pwm                     u_apb4_pwm      (u_pwm_apb_if, pwm);
  apb4_ps2                     u_apb4_ps2      (u_ps2_apb_if, ps2);
  apb4_i2c                     u_apb4_i2c      (u_i2c_apb_if, i2c);
  apb4_spi #(.FIFO_DEPTH(32))  u_apb4_spi      (u_qspi_apb_if, qspi);
  apb4_rtc                     u_apb4_rtc      (u_rtc_apb_if, u_rtc_if);
  apb4_wdg                     u_apb4_wdg      (u_wdg_apb_if, u_wdg_if);
  apb4_crc                     u_apb4_crc      (u_crc_apb_if);
  apb4_tmr                     u_apb4_tmr      (u_tmr_apb_if, u_tmr_if);
  // verilog_format: on

  // handle irq signals
  assign irq_o[0] = uart.irq_o;
  assign irq_o[1] = pwm.irq_o;
  assign irq_o[2] = ps2.irq_o;
  assign irq_o[3] = i2c.irq_o;
  assign irq_o[4] = qspi.irq_o;
  assign irq_o[5] = u_rtc_if.irq_o;
  assign irq_o[6] = u_wdg_if.rst_o;
  assign irq_o[7] = u_tmr_if.irq_o;
  assign irq_o[8] = spfs.irq_o;

  nmi2apb u_nmi2apb (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .nmi     (nmi),
`ifdef IP_MDD
      .user_ip (u_user_ip_apb_pure_if),
`endif
      .archinfo(u_archinfo_apb_pure_if),
      .rng     (u_rng_apb_pure_if),
      .uart    (u_uart1_apb_pure_if),
      .pwm     (u_pwm_apb_pure_if),
      .ps2     (u_ps2_apb_pure_if),
      .i2c     (u_i2c_apb_pure_if),
      .qspi    (u_qspi_apb_pure_if),
      .rtc     (u_rtc_apb_pure_if),
      .wdg     (u_wdg_apb_pure_if),
      .crc     (u_crc_apb_pure_if),
      .tmr     (u_tmr_apb_pure_if),
      .spfs    (u_spfs_apb_pure_if)
  );

  spi_flash #(
      .flash_addr_start(`FLASH_START_ADDR),
      .flash_addr_end  (`FLASH_END_ADDR),
      .spi_cs_num      (1)
  ) u_spi_flash (
      .pclk       (clk_i),
      .presetn    (rst_n_i),
      .paddr      (u_spfs_apb_if.paddr),
      .psel       (u_spfs_apb_if.psel),
      .penable    (u_spfs_apb_if.penable),
      .pwrite     (u_spfs_apb_if.pwrite),
      .pwdata     (u_spfs_apb_if.pwdata),
      .pwstrb     (4'hF),
      .pready     (u_spfs_apb_if.pready),
      .prdata     (u_spfs_apb_if.prdata),
      .pslverr    (u_spfs_apb_if.pslverr),
      .div4_i     (spfs_div4_i),
      .spi_clk    (spfs.spi_sck_o),
      .spi_cs     (spfs.spi_nss_o),
      .spi_mosi   (spfs.spi_mosi_o),
      .spi_miso   (spfs.spi_miso_i),
      .spi_irq_out(spfs.irq_o)
  );

`ifdef IP_MDD
  user_ip_wrapper u_user_ip_wrapper (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .sel_i  (ip_sel_i),
      .gpio   (gpio),
      .apb    (u_user_ip_apb_if)
  );
`endif

endmodule
