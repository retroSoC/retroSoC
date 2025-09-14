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

module ip_apb_wrapper (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    nmi_if.slave        nmi,
    // uart
    input  logic        uart_rx_i,
    output logic        uart_tx_o,
    // pwm
    output logic [ 3:0] pwm_pwm_o,
    // ps2
    input  logic        ps2_ps2_clk_i,
    input  logic        ps2_ps2_dat_i,
    // i2c
    input  logic        i2c_scl_i,
    output logic        i2c_scl_o,
    output logic        i2c_scl_dir_o,
    input  logic        i2c_sda_i,
    output logic        i2c_sda_o,
    output logic        i2c_sda_dir_o,
    // qspi
    output logic        qspi_spi_clk_o,
    output logic [ 3:0] qspi_spi_csn_o,
    output logic [ 3:0] qspi_spi_sdo_o,
    output logic [ 3:0] qspi_spi_oe_o,
    input  logic [ 3:0] qspi_spi_sdi_i,
    // spfs
    input  logic        spfs_div4_i,
    output logic        spfs_clk_o,
    output logic        spfs_cs_o,
    output logic        spfs_mosi_o,
    input  logic        spfs_miso_i,
`ifdef IP_MDD
    output logic [15:0] ip_mdd_gpio_out_o,
    input  logic [15:0] ip_mdd_gpio_in_i,
    output logic [15:0] ip_mdd_gpio_oen_o,
`endif
    output logic [ 5:0] irq_o
    // verilog_format: on
);

`ifdef IP_MDD
  localparam APB_SLAVES_NUM = 9;
`else
  localparam APB_SLAVES_NUM = 8;
`endif

  logic [              31:0] s_m_apb_paddr;
  logic [               2:0] s_m_apb_pprot;
  logic [APB_SLAVES_NUM-1:0] s_m_apb_psel;
  logic                      s_m_apb_penable;
  logic                      s_m_apb_pwrite;
  logic [              31:0] s_m_apb_pwdata;
  logic [               3:0] s_m_apb_pstrb;
  logic [APB_SLAVES_NUM-1:0] s_m_apb_pready;

  logic [              31:0] s_m_apb_prdata0;
  logic [              31:0] s_m_apb_prdata1;
  logic [              31:0] s_m_apb_prdata2;
  logic [              31:0] s_m_apb_prdata3;
  logic [              31:0] s_m_apb_prdata4;
  logic [              31:0] s_m_apb_prdata5;
  logic [              31:0] s_m_apb_prdata6;
  logic [              31:0] s_m_apb_prdata7;
`ifdef IP_MDD
  logic [31:0] s_ip_mdd_apb_paddr;
  logic [ 2:0] s_ip_mdd_apb_pprot;
  logic        s_ip_mdd_apb_psel;
  logic        s_ip_mdd_apb_penable;
  logic        s_ip_mdd_apb_pwrite;
  logic [31:0] s_ip_mdd_apb_pwdata;
  logic [ 3:0] s_ip_mdd_apb_pstrb;
  logic        s_ip_mdd_apb_pready;
  logic [31:0] s_ip_mdd_apb_prdata;
  logic [31:0] s_m_apb_prdata8;
`endif
  logic [APB_SLAVES_NUM-1:0] s_m_apb_pslverr;

  // verilog_format: off
  apb4_if u_archinfo_0_apb4_if   (clk_i, rst_n_i);
  apb4_if u_rng_0_apb4_if        (clk_i, rst_n_i);
  apb4_if u_uart_0_apb4_if       (clk_i, rst_n_i);
  apb4_if u_pwm_0_apb4_if        (clk_i, rst_n_i);
  apb4_if u_ps2_0_apb4_if        (clk_i, rst_n_i);
  apb4_if u_i2c_0_apb4_if        (clk_i, rst_n_i);
  apb4_if u_qspi_0_apb4_if       (clk_i, rst_n_i);

  uart_if u_uart_0_if            ();
  pwm_if  u_pwm_0_if             ();
  ps2_if  u_ps2_0_if             ();
  i2c_if  u_i2c_0_if             ();
  spi_if  u_spi_0_if             ();

  apb4_archinfo                u_apb4_archinfo_0(u_archinfo_0_apb4_if);
  apb4_rng                     u_apb4_rng_0     (u_rng_0_apb4_if);
  apb4_uart #(.FIFO_DEPTH(32)) u_apb4_uart_0    (u_uart_0_apb4_if, u_uart_0_if);
  apb4_pwm                     u_apb4_pwm_0     (u_pwm_0_apb4_if, u_pwm_0_if);
  apb4_ps2                     u_apb4_ps2_0     (u_ps2_0_apb4_if, u_ps2_0_if);
  apb4_i2c                     u_apb4_i2c_0     (u_i2c_0_apb4_if, u_i2c_0_if);
  apb4_spi #(.FIFO_DEPTH(32))  u_apb4_spi_0     (u_qspi_0_apb4_if, u_spi_0_if);
  // verilog_format: on

  assign u_archinfo_0_apb4_if.paddr   = s_m_apb_paddr;
  assign u_archinfo_0_apb4_if.pprot   = s_m_apb_pprot;
  assign u_archinfo_0_apb4_if.psel    = s_m_apb_psel[0];
  assign u_archinfo_0_apb4_if.penable = s_m_apb_penable;
  assign u_archinfo_0_apb4_if.pwrite  = s_m_apb_pwrite;
  assign u_archinfo_0_apb4_if.pwdata  = s_m_apb_pwdata;
  assign u_archinfo_0_apb4_if.pstrb   = s_m_apb_pstrb;
  assign s_m_apb_pready[0]            = u_archinfo_0_apb4_if.pready;
  assign s_m_apb_pslverr[0]           = u_archinfo_0_apb4_if.pslverr;
  assign s_m_apb_prdata0              = u_archinfo_0_apb4_if.prdata;

  assign u_rng_0_apb4_if.paddr        = s_m_apb_paddr;
  assign u_rng_0_apb4_if.pprot        = s_m_apb_pprot;
  assign u_rng_0_apb4_if.psel         = s_m_apb_psel[1];
  assign u_rng_0_apb4_if.penable      = s_m_apb_penable;
  assign u_rng_0_apb4_if.pwrite       = s_m_apb_pwrite;
  assign u_rng_0_apb4_if.pwdata       = s_m_apb_pwdata;
  assign u_rng_0_apb4_if.pstrb        = s_m_apb_pstrb;
  assign s_m_apb_pready[1]            = u_rng_0_apb4_if.pready;
  assign s_m_apb_pslverr[1]           = u_rng_0_apb4_if.pslverr;
  assign s_m_apb_prdata1              = u_rng_0_apb4_if.prdata;

  assign u_uart_0_apb4_if.paddr       = s_m_apb_paddr;
  assign u_uart_0_apb4_if.pprot       = s_m_apb_pprot;
  assign u_uart_0_apb4_if.psel        = s_m_apb_psel[2];
  assign u_uart_0_apb4_if.penable     = s_m_apb_penable;
  assign u_uart_0_apb4_if.pwrite      = s_m_apb_pwrite;
  assign u_uart_0_apb4_if.pwdata      = s_m_apb_pwdata;
  assign u_uart_0_apb4_if.pstrb       = s_m_apb_pstrb;
  assign s_m_apb_pready[2]            = u_uart_0_apb4_if.pready;
  assign s_m_apb_pslverr[2]           = u_uart_0_apb4_if.pslverr;
  assign s_m_apb_prdata2              = u_uart_0_apb4_if.prdata;
  assign u_uart_0_if.uart_rx_i        = uart_rx_i;
  assign uart_tx_o                    = u_uart_0_if.uart_tx_o;
  assign irq_o[0]                     = u_uart_0_if.irq_o;

  assign u_pwm_0_apb4_if.paddr        = s_m_apb_paddr;
  assign u_pwm_0_apb4_if.pprot        = s_m_apb_pprot;
  assign u_pwm_0_apb4_if.psel         = s_m_apb_psel[3];
  assign u_pwm_0_apb4_if.penable      = s_m_apb_penable;
  assign u_pwm_0_apb4_if.pwrite       = s_m_apb_pwrite;
  assign u_pwm_0_apb4_if.pwdata       = s_m_apb_pwdata;
  assign u_pwm_0_apb4_if.pstrb        = s_m_apb_pstrb;
  assign s_m_apb_pready[3]            = u_pwm_0_apb4_if.pready;
  assign s_m_apb_pslverr[3]           = u_pwm_0_apb4_if.pslverr;
  assign s_m_apb_prdata3              = u_pwm_0_apb4_if.prdata;
  assign pwm_pwm_o                    = u_pwm_0_if.pwm_o;
  assign irq_o[1]                     = u_pwm_0_if.irq_o;

  assign u_ps2_0_apb4_if.paddr        = s_m_apb_paddr;
  assign u_ps2_0_apb4_if.pprot        = s_m_apb_pprot;
  assign u_ps2_0_apb4_if.psel         = s_m_apb_psel[4];
  assign u_ps2_0_apb4_if.penable      = s_m_apb_penable;
  assign u_ps2_0_apb4_if.pwrite       = s_m_apb_pwrite;
  assign u_ps2_0_apb4_if.pwdata       = s_m_apb_pwdata;
  assign u_ps2_0_apb4_if.pstrb        = s_m_apb_pstrb;
  assign s_m_apb_pready[4]            = u_ps2_0_apb4_if.pready;
  assign s_m_apb_pslverr[4]           = u_ps2_0_apb4_if.pslverr;
  assign s_m_apb_prdata4              = u_ps2_0_apb4_if.prdata;
  assign u_ps2_0_if.ps2_clk_i         = ps2_ps2_clk_i;
  assign u_ps2_0_if.ps2_dat_i         = ps2_ps2_dat_i;
  assign irq_o[2]                     = u_ps2_0_if.irq_o;

  assign u_i2c_0_apb4_if.paddr        = s_m_apb_paddr;
  assign u_i2c_0_apb4_if.pprot        = s_m_apb_pprot;
  assign u_i2c_0_apb4_if.psel         = s_m_apb_psel[5];
  assign u_i2c_0_apb4_if.penable      = s_m_apb_penable;
  assign u_i2c_0_apb4_if.pwrite       = s_m_apb_pwrite;
  assign u_i2c_0_apb4_if.pwdata       = s_m_apb_pwdata;
  assign u_i2c_0_apb4_if.pstrb        = s_m_apb_pstrb;
  assign s_m_apb_pready[5]            = u_i2c_0_apb4_if.pready;
  assign s_m_apb_pslverr[5]           = u_i2c_0_apb4_if.pslverr;
  assign s_m_apb_prdata5              = u_i2c_0_apb4_if.prdata;
  assign u_i2c_0_if.scl_i             = i2c_scl_i;
  assign i2c_scl_o                    = u_i2c_0_if.scl_o;
  assign i2c_scl_dir_o                = u_i2c_0_if.scl_dir_o;
  assign u_i2c_0_if.sda_i             = i2c_sda_i;
  assign i2c_sda_o                    = u_i2c_0_if.sda_o;
  assign i2c_sda_dir_o                = u_i2c_0_if.sda_dir_o;
  assign irq_o[3]                     = u_i2c_0_if.irq_o;

  assign u_qspi_0_apb4_if.paddr       = s_m_apb_paddr;
  assign u_qspi_0_apb4_if.pprot       = s_m_apb_pprot;
  assign u_qspi_0_apb4_if.psel        = s_m_apb_psel[6];
  assign u_qspi_0_apb4_if.penable     = s_m_apb_penable;
  assign u_qspi_0_apb4_if.pwrite      = s_m_apb_pwrite;
  assign u_qspi_0_apb4_if.pwdata      = s_m_apb_pwdata;
  assign u_qspi_0_apb4_if.pstrb       = s_m_apb_pstrb;
  assign s_m_apb_pready[6]            = u_qspi_0_apb4_if.pready;
  assign s_m_apb_pslverr[6]           = u_qspi_0_apb4_if.pslverr;
  assign s_m_apb_prdata6              = u_qspi_0_apb4_if.prdata;
  assign qspi_spi_clk_o               = u_spi_0_if.spi_sck_o;
  assign qspi_spi_csn_o               = u_spi_0_if.spi_nss_o;
  assign qspi_spi_sdo_o               = u_spi_0_if.spi_io_out_o;
  assign qspi_spi_oe_o                = u_spi_0_if.spi_io_en_o;
  assign u_spi_0_if.spi_io_in_i       = qspi_spi_sdi_i;
  assign irq_o[4]                     = u_spi_0_if.irq_o;

`ifdef IP_MDD
  assign s_ip_mdd_apb_paddr   = s_m_apb_paddr;
  assign s_ip_mdd_apb_pprot   = s_m_apb_pprot;
  assign s_ip_mdd_apb_psel    = s_m_apb_psel[8];
  assign s_ip_mdd_apb_penable = s_m_apb_penable;
  assign s_ip_mdd_apb_pwrite  = s_m_apb_pwrite;
  assign s_ip_mdd_apb_pwdata  = s_m_apb_pwdata;
  assign s_ip_mdd_apb_pstrb   = s_m_apb_pstrb;
  assign s_m_apb_pready[8]    = s_ip_mdd_apb_pready;
  assign s_m_apb_pslverr[8]   = '0;
  assign s_m_apb_prdata8      = s_ip_mdd_apb_prdata;
`endif

  spi_flash #(
      .flash_addr_start(`FLASH_START_ADDR),
      .flash_addr_end  (`FLASH_END_ADDR),
      .spi_cs_num      (1)
  ) u_spi_flash (
      .pclk       (clk_i),
      .presetn    (rst_n_i),
      .paddr      (s_m_apb_paddr),
      .psel       (s_m_apb_psel[7]),
      .penable    (s_m_apb_penable),
      .pwrite     (s_m_apb_pwrite),
      .pwdata     (s_m_apb_pwdata),
      .pwstrb     (4'hF),
      .pready     (s_m_apb_pready[7]),
      .prdata     (s_m_apb_prdata7),
      .pslverr    (s_m_apb_pslverr[7]),
      .div4_i     (spfs_div4_i),
      .spi_clk    (spfs_clk_o),
      .spi_cs     (spfs_cs_o),
      .spi_mosi   (spfs_mosi_o),
      .spi_miso   (spfs_miso_i),
      .spi_irq_out(irq_o[5])
  );

`ifdef IP_MDD
  ip_mdd_wrapper u_ip_mdd_wrapper (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .sel_i            ('0),                    // HACK:
      .gpio_out_o       (ip_mdd_gpio_out_o),
      .gpio_in_i        (ip_mdd_gpio_in_i),
      .gpio_oen_o       (ip_mdd_gpio_oen_o),
      .slv_apb_paddr_i  (s_ip_mdd_apb_paddr),
      .slv_apb_pprot_i  (s_ip_mdd_apb_pprot),
      .slv_apb_psel_i   (s_ip_mdd_apb_psel),
      .slv_apb_penable_i(s_ip_mdd_apb_penable),
      .slv_apb_pwrite_i (s_ip_mdd_apb_pwrite),
      .slv_apb_pwdata_i (s_ip_mdd_apb_pwdata),
      .slv_apb_pstrb_i  (s_ip_mdd_apb_pstrb),
      .slv_apb_pready_o (s_ip_mdd_apb_pready),
      .slv_apb_prdata_o (s_ip_mdd_apb_prdata)
  );
`endif

  mem2apb #(
      .APB_SLAVES_NUM(APB_SLAVES_NUM)
  ) u_mem2apb (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .mem_valid_i  (nmi.valid),
      .mem_addr_i   (nmi.addr),
      .mem_wdata_i  (nmi.wdata),
      .mem_wstrb_i  (nmi.wstrb),
      .mem_rdata_o  (nmi.rdata),
      .mem_ready_o  (nmi.ready),
      .apb_paddr_o  (s_m_apb_paddr),
      .apb_pprot_o  (s_m_apb_pprot),
      .apb_psel_o   (s_m_apb_psel),
      .apb_penable_o(s_m_apb_penable),
      .apb_pwrite_o (s_m_apb_pwrite),
      .apb_pwdata_o (s_m_apb_pwdata),
      .apb_pstrb_o  (s_m_apb_pstrb),
      .apb_pready_i (s_m_apb_pready),
      .apb_prdata0_i(s_m_apb_prdata0),
      .apb_prdata1_i(s_m_apb_prdata1),
      .apb_prdata2_i(s_m_apb_prdata2),
      .apb_prdata3_i(s_m_apb_prdata3),
      .apb_prdata4_i(s_m_apb_prdata4),
      .apb_prdata5_i(s_m_apb_prdata5),
      .apb_prdata6_i(s_m_apb_prdata6),
      .apb_prdata7_i(s_m_apb_prdata7),
`ifdef IP_MDD
      .apb_prdata8_i(s_m_apb_prdata8),
`endif
      .apb_pslverr_i(s_m_apb_pslverr)
  );

endmodule
