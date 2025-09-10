/*
 *  retroSoC - A simple example SoC using PicoRV32
 *
 *  Copyright (C) 2017  Clifford Wolf <clifford@clifford.at>
 *  Copyright (C) 2018,2019  Tim Edwards <tim@efabless.com>
 *  Copyright (C) 2025  Yuchi Miao <miaoyuchi@ict.ac.cn>

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

`include "mmap_define.svh"

module retrosoc (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        clk_aud_i,
    input  logic        rst_aud_n_i,
`ifdef CORE_MDD
    input  logic [ 4:0] core_mdd_sel_i,
`endif
`ifdef IP_MDD
    input  logic [ 4:0] ip_mdd_sel_i,
    output logic [15:0] ip_mdd_gpio_out_o,
    input  logic [15:0] ip_mdd_gpio_in_i,
    output logic [15:0] ip_mdd_gpio_oeb_o,
`endif
`ifdef HAVE_SRAM_IF
    output logic [14:0] ram_addr_o,
    output logic [31:0] ram_wdata_o,
    output logic [ 3:0] ram_wstrb_o,
    input  logic [31:0] ram_rdata_i,
`endif
    // memory mapped I/O signals
    output logic [ 7:0] gpio_out_o,
    input  logic [ 7:0] gpio_in_i,
    output logic [ 7:0] gpio_pub_o,
    output logic [ 7:0] gpio_pdb_o,
    output logic [ 7:0] gpio_oeb_o,
    output logic        uart_tx_o,
    input  logic        uart_rx_i,
    // irq
    input  logic        irq_pin_i,
    // cust
    input  logic        cust_uart_rx_i,
    output logic        cust_uart_tx_o,
    output logic [ 3:0] cust_pwm_pwm_o,
    input  logic        cust_ps2_ps2_clk_i,
    input  logic        cust_ps2_ps2_dat_i,
    input  logic        cust_i2c_scl_i,
    output logic        cust_i2c_scl_o,
    output logic        cust_i2c_scl_dir_o,
    input  logic        cust_i2c_sda_i,
    output logic        cust_i2c_sda_o,
    output logic        cust_i2c_sda_dir_o,
    output logic        cust_qspi_spi_clk_o,
    output logic [ 3:0] cust_qspi_spi_csn_o,
    output logic [ 3:0] cust_qspi_spi_sdo_o,
    output logic [ 3:0] cust_qspi_spi_oe_o,
    input  logic [ 3:0] cust_qspi_spi_sdi_i,
    output logic        cust_psram_sclk_o,
    output logic [ 1:0] cust_psram_ce_o,
    input  logic        cust_psram_sio0_i,
    input  logic        cust_psram_sio1_i,
    input  logic        cust_psram_sio2_i,
    input  logic        cust_psram_sio3_i,
    output logic        cust_psram_sio0_o,
    output logic        cust_psram_sio1_o,
    output logic        cust_psram_sio2_o,
    output logic        cust_psram_sio3_o,
    output logic        cust_psram_sio_oe_o,
    output logic        cust_spisd_sclk_o,
    output logic        cust_spisd_cs_o,
    output logic        cust_spisd_mosi_o,
    input  logic        cust_spisd_miso_i,
    input  logic        cust_spfs_div4_i,
    output logic        cust_spfs_clk_o,
    output logic        cust_spfs_cs_o,
    output logic        cust_spfs_mosi_o,
    input  logic        cust_spfs_miso_i
);
  // core if
  logic        s_core_valid;
  logic [31:0] s_core_addr;
  logic [31:0] s_core_wdata;
  logic [ 3:0] s_core_wstrb;
  logic [31:0] s_core_rdata;
  logic        s_core_ready;
  // mmap if
  logic        s_mmap_valid;
  logic [ 3:0] s_mmap_wstrb;
  logic [31:0] s_mmap_addr;
  logic [31:0] s_mmap_wdata;
  logic [31:0] s_mmap_rdata;
  logic        s_mmap_ready;
  // natv if
  logic        s_natv_valid;
  logic [ 3:0] s_natv_wstrb;
  logic [31:0] s_natv_addr;
  logic [31:0] s_natv_wdata;
  logic [31:0] s_natv_rdata;
  logic        s_natv_ready;
  // psram if
  logic        s_psram_valid;
  logic [ 3:0] s_psram_wstrb;
  logic [31:0] s_psram_addr;
  logic [31:0] s_psram_wdata;
  logic [31:0] s_psram_rdata;
  logic        s_psram_ready;
  // spisd if
  logic        s_spisd_valid;
  logic [ 3:0] s_spisd_wstrb;
  logic [31:0] s_spisd_addr;
  logic [31:0] s_spisd_wdata;
  logic [31:0] s_spisd_rdata;
  logic        s_spisd_ready;
  // i2s if
  logic        s_i2s_valid;
  logic [ 3:0] s_i2s_wstrb;
  logic [31:0] s_i2s_addr;
  logic [31:0] s_i2s_wdata;
  logic [31:0] s_i2s_rdata;
  logic        s_i2s_ready;
  logic        s_i2s_aud_valid;
  logic [ 3:0] s_i2s_aud_wstrb;
  logic [31:0] s_i2s_aud_addr;
  logic [31:0] s_i2s_aud_wdata;
  logic [31:0] s_i2s_aud_rdata;
  logic        s_i2s_aud_ready;
  // psram cfg if
  logic        s_psram_cfg_wait_wr_en;
  logic [ 4:0] s_psram_cfg_wait_i;
  logic [ 4:0] s_psram_cfg_wait_o;
  logic        s_psram_cfg_chd_wr_en;
  logic [ 2:0] s_psram_cfg_chd_i;
  logic [ 2:0] s_psram_cfg_chd_o;
  // spisd cfg if
  logic [ 1:0] s_spisd_cfg_clkdiv;

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
`endif

  // irq
  logic [31:0] s_irq;
  logic [ 2:0] s_natv_irq;
  logic [ 5:0] s_apb_irq;

  assign s_irq[4:0]   = 5'd0;
  assign s_irq[5]     = irq_pin_i;
  assign s_irq[8:6]   = s_natv_irq;
  assign s_irq[14:9]  = s_apb_irq;
  assign s_irq[31:15] = 17'd0;

  core_wrapper u_core_wrapper (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
`ifdef CORE_MDD
      .core_mdd_sel_i(core_mdd_sel_i),
`endif
      .core_valid_o  (s_core_valid),
      .core_addr_o   (s_core_addr),
      .core_wdata_o  (s_core_wdata),
      .core_wstrb_o  (s_core_wstrb),
      .core_rdata_i  (s_core_rdata),
      .core_ready_i  (s_core_ready),
      .irq_i         (s_irq)
  );

  bus u_bus (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      // core if
      .core_valid_i (s_core_valid),
      .core_ready_o (s_core_ready),
      .core_addr_i  (s_core_addr),
      .core_wdata_i (s_core_wdata),
      .core_wstrb_i (s_core_wstrb),
      .core_rdata_o (s_core_rdata),
      // natv if
      .natv_valid_o (s_natv_valid),
      .natv_ready_i (s_natv_ready),
      .natv_addr_o  (s_natv_addr),
      .natv_wdata_o (s_natv_wdata),
      .natv_wstrb_o (s_natv_wstrb),
      .natv_rdata_i (s_natv_rdata),
      // mmap if
      .mmap_valid_o (s_mmap_valid),
      .mmap_ready_i (s_mmap_ready),
      .mmap_addr_o  (s_mmap_addr),
      .mmap_wdata_o (s_mmap_wdata),
      .mmap_wstrb_o (s_mmap_wstrb),
      .mmap_rdata_i (s_mmap_rdata),
`ifdef HAVE_SRAM_IF
      .ram_addr_o   (ram_addr_o),
      .ram_wdata_o  (ram_wdata_o),
      .ram_wstrb_o  (ram_wstrb_o),
      .ram_rdata_i  (ram_rdata_i),
`endif
      // psram if
      .psram_valid_o(s_psram_valid),
      .psram_ready_i(s_psram_ready),
      .psram_addr_o (s_psram_addr),
      .psram_wdata_o(s_psram_wdata),
      .psram_wstrb_o(s_psram_wstrb),
      .psram_rdata_i(s_psram_rdata),
      // spisd if
      .spisd_valid_o(s_spisd_valid),
      .spisd_ready_i(s_spisd_ready),
      .spisd_addr_o (s_spisd_addr),
      .spisd_wdata_o(s_spisd_wdata),
      .spisd_wstrb_o(s_spisd_wstrb),
      .spisd_rdata_i(s_spisd_rdata),
      // i2s if
      .i2s_valid_o  (s_i2s_valid),
      .i2s_addr_o   (s_i2s_addr),
      .i2s_wdata_o  (s_i2s_wdata),
      .i2s_wstrb_o  (s_i2s_wstrb),
      .i2s_rdata_i  (s_i2s_rdata),
      .i2s_ready_i  (s_i2s_ready)
  );

  ip_natv_wrapper u_ip_natv_wrapper (
      .clk_i                 (clk_i),
      .rst_n_i               (rst_n_i),
      .natv_valid_i          (s_natv_valid),
      .natv_addr_i           (s_natv_addr),
      .natv_wdata_i          (s_natv_wdata),
      .natv_wstrb_i          (s_natv_wstrb),
      .natv_rdata_o          (s_natv_rdata),
      .natv_ready_o          (s_natv_ready),
      .gpio_out_o            (gpio_out_o),
      .gpio_in_i             (gpio_in_i),
      .gpio_pub_o            (gpio_pub_o),
      .gpio_pdb_o            (gpio_pdb_o),
      .gpio_oeb_o            (gpio_oeb_o),
      .uart_rx_i             (uart_rx_i),
      .uart_tx_o             (uart_tx_o),
      .psram_cfg_wait_wr_en_o(s_psram_cfg_wait_wr_en),
      .psram_cfg_wait_i      (s_psram_cfg_wait_i),
      .psram_cfg_wait_o      (s_psram_cfg_wait_o),
      .psram_cfg_chd_wr_en_o (s_psram_cfg_chd_wr_en),
      .psram_cfg_chd_i       (s_psram_cfg_chd_i),
      .psram_cfg_chd_o       (s_psram_cfg_chd_o),
      .spisd_cfg_clkdiv_o    (s_spisd_cfg_clkdiv),
      .irq_o                 (s_natv_irq)
  );

  ip_apb_wrapper u_ip_apb_wrapper (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .mmap_valid_i        (s_mmap_valid),
      .mmap_addr_i         (s_mmap_addr),
      .mmap_wdata_i        (s_mmap_wdata),
      .mmap_wstrb_i        (s_mmap_wstrb),
      .mmap_rdata_o        (s_mmap_rdata),
      .mmap_ready_o        (s_mmap_ready),
`ifdef IP_MDD
      .ip_mdd_apb_paddr_o  (s_ip_mdd_apb_paddr),
      .ip_mdd_apb_pprot_o  (s_ip_mdd_apb_pprot),
      .ip_mdd_apb_psel_o   (s_ip_mdd_apb_psel),
      .ip_mdd_apb_penable_o(s_ip_mdd_apb_penable),
      .ip_mdd_apb_pwrite_o (s_ip_mdd_apb_pwrite),
      .ip_mdd_apb_pwdata_o (s_ip_mdd_apb_pwdata),
      .ip_mdd_apb_pstrb_o  (s_ip_mdd_apb_pstrb),
      .ip_mdd_apb_pready_i (s_ip_mdd_apb_pready),
      .ip_mdd_apb_prdata_i (s_ip_mdd_apb_prdata),
`endif
      .uart_rx_i           (cust_uart_rx_i),
      .uart_tx_o           (cust_uart_tx_o),
      .pwm_pwm_o           (cust_pwm_pwm_o),
      .ps2_ps2_clk_i       (cust_ps2_ps2_clk_i),
      .ps2_ps2_dat_i       (cust_ps2_ps2_dat_i),
      .i2c_scl_i           (cust_i2c_scl_i),
      .i2c_scl_o           (cust_i2c_scl_o),
      .i2c_scl_dir_o       (cust_i2c_scl_dir_o),
      .i2c_sda_i           (cust_i2c_sda_i),
      .i2c_sda_o           (cust_i2c_sda_o),
      .i2c_sda_dir_o       (cust_i2c_sda_dir_o),
      .qspi_spi_clk_o      (cust_qspi_spi_clk_o),
      .qspi_spi_csn_o      (cust_qspi_spi_csn_o),
      .qspi_spi_sdo_o      (cust_qspi_spi_sdo_o),
      .qspi_spi_oe_o       (cust_qspi_spi_oe_o),
      .qspi_spi_sdi_i      (cust_qspi_spi_sdi_i),
      .spfs_div4_i         (cust_spfs_div4_i),
      .spfs_clk_o          (cust_spfs_clk_o),
      .spfs_cs_o           (cust_spfs_cs_o),
      .spfs_mosi_o         (cust_spfs_mosi_o),
      .spfs_miso_i         (cust_spfs_miso_i),
      .irq_o               (s_apb_irq)
  );

`ifdef IP_MDD
  ip_mdd_wrapper u_ip_mdd_wrapper (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .sel_i            (ip_mdd_sel_i),
      .gpio_out_o       (ip_mdd_gpio_out_o),
      .gpio_in_i        (ip_mdd_gpio_in_i),
      .gpio_oeb_o       (ip_mdd_gpio_oeb_o),
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

  psram_top u_psram_top (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .cfg_wait_wr_en_i(s_psram_cfg_wait_wr_en),
      .cfg_wait_i      (s_psram_cfg_wait_o),
      .cfg_wait_o      (s_psram_cfg_wait_i),
      .cfg_chd_wr_en_i (s_psram_cfg_chd_wr_en),
      .cfg_chd_i       (s_psram_cfg_chd_o),
      .cfg_chd_o       (s_psram_cfg_chd_i),
      .mem_valid_i     (s_psram_valid),
      .mem_addr_i      (s_psram_addr[23:0]),
      .mem_wdata_i     (s_psram_wdata),
      .mem_wstrb_i     (s_psram_wstrb),
      .mem_rdata_o     (s_psram_rdata),
      .mem_ready_o     (s_psram_ready),
      .psram_sclk_o    (cust_psram_sclk_o),
      .psram_ce_o      (cust_psram_ce_o),
      .psram_mosi_i    (cust_psram_sio0_i),
      .psram_miso_i    (cust_psram_sio1_i),
      .psram_sio2_i    (cust_psram_sio2_i),
      .psram_sio3_i    (cust_psram_sio3_i),
      .psram_mosi_o    (cust_psram_sio0_o),
      .psram_miso_o    (cust_psram_sio1_o),
      .psram_sio2_o    (cust_psram_sio2_o),
      .psram_sio3_o    (cust_psram_sio3_o),
      .psram_sio_oen_o (cust_psram_sio_oe_o)
  );

  spisd u_spisd (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .cfg_clkdiv_i(s_spisd_cfg_clkdiv),
      .mem_valid_i (s_spisd_valid),
      .mem_ready_o (s_spisd_ready),
      .mem_addr_i  (s_spisd_addr),
      .mem_wdata_i (s_spisd_wdata),
      .mem_wstrb_i (s_spisd_wstrb),
      .mem_rdata_o (s_spisd_rdata),
      .spisd_sclk_o(cust_spisd_sclk_o),
      .spisd_cs_o  (cust_spisd_cs_o),
      .spisd_mosi_o(cust_spisd_mosi_o),
      .spisd_miso_i(cust_spisd_miso_i)
  );

  nmi2nmi u_nmi2nmi (
      .mstr_clk_i  (clk_i),
      .mstr_rst_n_i(rst_n_i),
      .mstr_valid_i(s_i2s_valid),
      .mstr_addr_i (s_i2s_addr),
      .mstr_wdata_i(s_i2s_wdata),
      .mstr_wstrb_i(s_i2s_wstrb),
      .mstr_rdata_o(s_i2s_rdata),
      .mstr_ready_o(s_i2s_ready),
      .slvr_clk_i  (clk_aud_i),
      .slvr_rst_n_i(rst_aud_n_i),
      .slvr_valid_o(s_i2s_aud_valid),
      .slvr_addr_o (s_i2s_aud_addr),
      .slvr_wdata_o(s_i2s_aud_wdata),
      .slvr_wstrb_o(s_i2s_aud_wstrb),
      .slvr_rdata_i(s_i2s_aud_rdata),
      .slvr_ready_i(s_i2s_aud_ready)
  );

  // HACK:
  assign s_i2s_aud_rdata = '0;
  assign s_i2s_aud_ready = '0;
endmodule
