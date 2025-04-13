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

`include "apb4_if.sv"
`include "uart_define.sv"
`include "pwm_define.sv"
`include "ps2_define.sv"
`include "i2c_define.sv"

module apb_ip_wrapper (
    input  logic        clk_i,
    input  logic        rst_n_i,
    // mem if
    input  logic        mmap_valid_i,
    input  logic [31:0] mmap_addr_i,
    input  logic [31:0] mmap_wdata_i,
    input  logic [ 3:0] mmap_wstrb_i,
    output logic [31:0] mmap_rdata_o,
    output logic        mmap_ready_o,
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
    output logic [ 5:0] irq_o
);

  localparam APB_SLAVES_NUM = 8;

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
  logic [APB_SLAVES_NUM-1:0] s_m_apb_pslverr;

  // verilog_format: off
  apb4_if u_archinfo_0_apb4_if   (clk_i, rst_n_i);
  apb4_if u_rng_0_apb4_if        (clk_i, rst_n_i);
  apb4_if u_uart_0_apb4_if       (clk_i, rst_n_i);
  apb4_if u_pwm_0_apb4_if        (clk_i, rst_n_i);
  apb4_if u_ps2_0_apb4_if        (clk_i, rst_n_i);
  apb4_if u_i2c_0_apb4_if        (clk_i, rst_n_i);

  uart_if u_uart_0_if            ();
  pwm_if  u_pwm_0_if             ();
  ps2_if  u_ps2_0_if             ();
  i2c_if  u_i2c_0_if             ();

  apb4_archinfo u_apb4_archinfo_0(u_archinfo_0_apb4_if);
  apb4_rng      u_apb4_rng_0     (u_rng_0_apb4_if);
  apb4_uart     u_apb4_uart_0    (u_uart_0_apb4_if, u_uart_0_if);
  apb4_pwm      u_apb4_pwm_0     (u_pwm_0_apb4_if, u_pwm_0_if);
  apb4_ps2      u_apb4_ps2_0     (u_ps2_0_apb4_if, u_ps2_0_if);
  apb4_i2c      u_apb4_i2c_0     (u_i2c_0_apb4_if, u_i2c_0_if);
  // verilog_format: on

  assign u_archinfo_0_apb4_if.psel = s_m_apb_psel[0];
  assign s_m_apb_pready[0]         = u_archinfo_0_apb4_if.pready;
  assign s_m_apb_pslverr[0]        = u_archinfo_0_apb4_if.pslverr;
  assign s_m_apb_prdata0           = u_archinfo_0_apb4_if.prdata;

  assign u_rng_0_apb4_if.psel      = s_m_apb_psel[1];
  assign s_m_apb_pready[1]         = u_rng_0_apb4_if.pready;
  assign s_m_apb_pslverr[1]        = u_rng_0_apb4_if.pslverr;
  assign s_m_apb_prdata1           = u_rng_0_apb4_if.prdata;

  assign u_uart_0_apb4_if.psel     = s_m_apb_psel[2];
  assign s_m_apb_pready[2]         = u_uart_0_apb4_if.pready;
  assign s_m_apb_pslverr[2]        = u_uart_0_apb4_if.pslverr;
  assign s_m_apb_prdata2           = u_uart_0_apb4_if.prdata;
  assign u_uart_0_if.uart_rx_i     = uart_rx_i;
  assign uart_tx_o                 = u_uart_0_if.uart_tx_o;
  assign irq_o[0]                  = u_uart_0_if.irq_o;

  assign u_pwm_0_apb4_if.psel      = s_m_apb_psel[3];
  assign s_m_apb_pready[3]         = u_pwm_0_apb4_if.pready;
  assign s_m_apb_pslverr[3]        = u_pwm_0_apb4_if.pslverr;
  assign s_m_apb_prdata3           = u_pwm_0_apb4_if.prdata;
  assign pwm_pwm_o                 = u_pwm_0_if.pwm_o;
  assign irq_o[1]                  = u_pwm_0_if.irq_o;

  assign u_ps2_0_apb4_if.psel      = s_m_apb_psel[4];
  assign s_m_apb_pready[4]         = u_ps2_0_apb4_if.pready;
  assign s_m_apb_pslverr[4]        = u_ps2_0_apb4_if.pslverr;
  assign s_m_apb_prdata4           = u_ps2_0_apb4_if.prdata;
  assign u_ps2_0_if.ps2_clk_i      = ps2_ps2_clk_i;
  assign u_ps2_0_if.ps2_dat_i      = ps2_ps2_dat_i;
  assign irq_o[2]                  = u_ps2_0_if.irq_o;

  assign u_i2c_0_apb4_if.psel      = s_m_apb_psel[5];
  assign s_m_apb_pready[5]         = u_i2c_0_apb4_if.pready;
  assign s_m_apb_pslverr[5]        = u_i2c_0_apb4_if.pslverr;
  assign s_m_apb_prdata5           = u_i2c_0_apb4_if.prdata;
  assign u_i2c_0_if.scl_i          = i2c_scl_i;
  assign i2c_scl_o                 = u_i2c_0_if.scl_o;
  assign i2c_scl_dir_o             = u_i2c_0_if.scl_dir_o;
  assign u_i2c_0_if.sda_i          = i2c_sda_i;
  assign i2c_sda_o                 = u_i2c_0_if.sda_o;
  assign i2c_sda_dir_o             = u_i2c_0_if.sda_dir_o;
  assign irq_o[3]                  = u_i2c_0_if.irq_o;

  apb_spi_master #(
      .BUFFER_DEPTH  (32),
      .APB_ADDR_WIDTH(32)
  ) u_apb_spi_master (
      .HCLK    (clk_i),
      .HRESETn (rst_n_i),
      .PADDR   (s_m_apb_paddr),
      .PWDATA  (s_m_apb_pwdata),
      .PWRITE  (s_m_apb_pwrite),
      .PSEL    (s_m_apb_psel[6]),
      .PENABLE (s_m_apb_penable),
      .PRDATA  (s_m_apb_prdata6),
      .PREADY  (s_m_apb_pready[6]),
      .PSLVERR (s_m_apb_pslverr[6]),
      .spi_clk (qspi_spi_clk_o),
      .spi_csn0(qspi_spi_csn_o[0]),
      .spi_csn1(qspi_spi_csn_o[1]),
      .spi_csn2(qspi_spi_csn_o[2]),
      .spi_csn3(qspi_spi_csn_o[3]),
      .spi_sdo0(qspi_spi_sdo_o[0]),
      .spi_sdo1(qspi_spi_sdo_o[1]),
      .spi_sdo2(qspi_spi_sdo_o[2]),
      .spi_sdo3(qspi_spi_sdo_o[3]),
      .spi_oe0 (qspi_spi_oe_o[0]),
      .spi_oe1 (qspi_spi_oe_o[1]),
      .spi_oe2 (qspi_spi_oe_o[2]),
      .spi_oe3 (qspi_spi_oe_o[3]),
      .spi_sdi0(qspi_spi_sdi_i[0]),
      .spi_sdi1(qspi_spi_sdi_i[1]),
      .spi_sdi2(qspi_spi_sdi_i[2]),
      .spi_sdi3(qspi_spi_sdi_i[3]),
      .events_o(irq_o[4])
  );

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

  mem2apb #(
      .APB_SLAVES_NUM(APB_SLAVES_NUM)
  ) u_mem2apb (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .mem_valid_i  (mmap_valid_i),
      .mem_addr_i   (mmap_addr_i),
      .mem_wdata_i  (mmap_wdata_i),
      .mem_wstrb_i  (mmap_wstrb_i),
      .mem_rdata_o  (mmap_rdata_o),
      .mem_ready_o  (mmap_ready_o),
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
      .apb_pslverr_i(s_m_apb_pslverr)
  );

endmodule
